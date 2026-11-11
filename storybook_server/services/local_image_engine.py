"""우리 모델로 동화 그림 만들기 (gpt-image 대신). .env 의 IMAGE_ENGINE=local 이면 routers/story_image.py 가 부른다.

1. GPT 글 호출 1번: 아이 그림 설명서(블루프린트)와 페이지 글을 보고
   장면 계획(칸마다 배경·캐릭터 자리·자세·소품·조연) + 캐릭터마다 짧은 영어 설명·팔다리 개수를 JSON 으로 받는다.
2. Kaggle 그림 서버에 맡기고(POST /jobs) 끝날 때까지 물어본다(GET /jobs/{id}).
   터널이 응답을 100초까지만 기다려서 한 번에 받지 않고 이렇게 나눈다.

캐릭터 미리 그리기 (prepare_characters): 아이가 그림을 다 그렸을 때 앱이 보낸다 (어떤 그림 방법을 고를지와 상관없이).
그림 한 장마다 짧은 영어 설명·팔다리 개수를 GPT 로 한 번 만들어 그림 픽셀 기준으로 기억하고(LOOKS), 그림 서버에
캐릭터 완성만 맡긴다(POST /characters). 나중에 '우리 모델'로 동화를 만들면 같은 설명을 써서 그림 서버 캐시가 맞아
캐릭터 완성(1명 약 30초)을 건너뛴다. 그림 서버가 꺼져 있거나 실패해도 조용히 넘어간다 (동화 만들기에는 영향 없음).

그림 서버 코드: customized_fairy_tales-main/lora_training (kaggle_image_server.ipynb, story_pipeline.py, scene_plan.py)
아래 지시문의 slot·size·pose·anchor 이름은 scene_plan.py 의 SLOTS·SIZES·ANCHORS, puppet.py 의 POSES 와 같아야 한다
(다르면 그림 서버가 기본값으로 바꿔 그린다).
"""
import asyncio
import base64
import hashlib
import io
import json
import os
from typing import Dict, List, Optional

import httpx
from PIL import Image

SLOTS = ["left", "center-left", "center", "center-right", "right"]
SIZES = ["small", "medium", "large"]
POSES = ["stand", "wave", "cheer", "walk", "jump", "sad", "scared"]
ANCHORS = ["on_head", "in_hand", "beside", "above"]
PANELS = {"single": 1, "two_panel": 2, "three_panel": 3}

# 아이 그림이 아니라 배경(장소)을 그린 에셋: 캐릭터로 세우지 않고 배경 설명에만 쓴다
PLACE_IDS = {"place"}

PLAN_PROMPT = """\
You plan picture-book pages that are assembled from separate pieces:
an EMPTY background painting, the child's drawn characters (fixed drawings that can only change pose),
small props, and optional side characters.

Child's drawn characters (id: what the child's drawing looks like):
{drawn}

Characters the child named but did NOT draw (paint them as side characters, never as drawn characters):
{undrawn}

Place the child drew (use it for every background if given):
{place}

Return ONLY JSON in this exact format:
{{"characters": {{"hero": {{"desc": "short English look of the drawing, colors and shape, max 20 words",
                          "arms": 2, "legs": 0}}}},
  "pages": [
  {{"page": 1, "panels": [
    {{"background": "short English description of the empty place, no characters",
      "characters": [{{"id": "hero", "slot": "left", "size": "medium", "place": "ground",
                       "pose": "wave", "facing": "right"}}],
      "props": [{{"name": "a big cooking pot", "anchor": "on_head", "owner": "hero"}}],
      "extras": [{{"name": "a small blue bird", "recurring": false}}]}}
  ]}}
]}}

Rules:
- "characters" (top level): one entry per drawn character id. "arms"/"legs": how many the child actually drew
  (0 if none; ears, horns, hair, star points, fins, tails and wings are not arms or legs).
- Use the given page numbers. panels: 1 for "single", 2 for "two_panel" (top, bottom),
  3 for "three_panel" (top, bottom left, bottom right) - one moment of the page text per panel.
- panel characters: only drawn ids that the page lists. At most 3 per panel. Each id at most once per panel.
- slot: one of {slots}. size: one of {sizes}. place: "ground" or "air" (flying, jumping, floating).
- pose: one of {poses}. Pick the one closest to what the character does.
- facing: "left" or "right" - toward whoever they talk to or the direction they move.
- props: at most 2 simple objects the page mentions. anchor: one of {anchors}. owner: a character id in this panel.
  Objects a character wears or holds ("on_head", "in_hand") are drawn once and attached to the character;
  objects only standing nearby ("beside", "above") are painted into the background.
- extras: creatures or people in the page that are not drawn characters (including the named-but-undrawn ones),
  as a short English description of how they look. "recurring": true if the same one appears on several pages
  (it is drawn once and reused - use the exact same name every time), false if only once (painted into the background).
- background: never mention the drawn characters; describe the place and mood only, in English, at most 15 words
  (the image model reads only a short prompt; longer text is cut off).
- prop and extra names: at most 6 words each.

Story pages:
{pages}
"""


LOOK_PROMPT = """This is a child's drawing of a story character. Return ONLY JSON:
{"desc": "short English look of the drawing, colors and shape, max 20 words",
 "arms": 2, "legs": 0}
"arms"/"legs": how many the child actually drew (0 if none; ears, horns, hair, star points, fins, tails and wings
are not arms or legs)."""

# 그림 픽셀 해시 -> {"desc", "arms", "legs"} (미리 그리기에서 만든 설명. 동화 만들 때 같은 설명을 써야 그림 서버 캐시가 맞는다)
LOOKS: Dict[str, dict] = {}
# 그림 픽셀 해시 -> 설명을 만드는 중인 작업 (동화 요청이 먼저 오면 이것을 기다린다)
PENDING: Dict[str, "asyncio.Task"] = {}


def _png(b64: str) -> Image.Image:
    if "," in b64:
        b64 = b64.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(b64)))


def pixel_key(b64: str) -> str:
    """같은 그림이면 PNG 인코딩이 달라도 같은 값 (그림 서버 캐시도 픽셀 기준)."""
    img = _png(b64).convert("RGBA")
    return hashlib.sha1(img.tobytes() + str(img.size).encode()).hexdigest()


def _on_white(b64: str) -> str:
    img = _png(b64).convert("RGBA")
    bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
    buf = io.BytesIO()
    Image.alpha_composite(bg, img).convert("RGB").save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


async def describe_drawing(client, model, b64: str) -> dict:
    """GPT 비전 호출 1번: 그림의 짧은 영어 설명 + 팔다리 개수."""
    res = await client.chat.completions.create(
        model=model, response_format={"type": "json_object"}, max_completion_tokens=800,
        messages=[{"role": "user", "content": [
            {"type": "text", "text": LOOK_PROMPT},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{_on_white(b64)}"}}]}])
    look = json.loads(res.choices[0].message.content)
    return {"desc": str(look.get("desc") or "")[:200], "arms": int(look.get("arms") or 0), "legs": int(look.get("legs") or 0)}


async def prepare_characters(client, model, drawings: Dict[str, str]) -> None:
    """앱이 그림을 다 그렸을 때 부른다 (응답을 기다리지 않는 배경 작업). drawings: {에셋 id: base64 PNG}."""
    url, token = os.getenv("LOCAL_IMAGE_URL", ""), os.getenv("LOCAL_IMAGE_TOKEN", "")
    if not url:
        return
    try:
        todo = {k: b64 for k, b64 in drawings.items() if k not in PLACE_IDS and b64 and len(b64) > 100}
        keys = {k: pixel_key(b64) for k, b64 in todo.items()}
        todo = {k: b64 for k, b64 in todo.items() if keys[k] not in LOOKS and keys[k] not in PENDING}
        if not todo:
            return
        tasks = {k: asyncio.create_task(describe_drawing(client, model, b64)) for k, b64 in todo.items()}
        for k, task in tasks.items():
            PENDING[keys[k]] = task
        characters = {}
        for k, task in tasks.items():
            try:
                LOOKS[keys[k]] = await task
                characters[k] = {"image_b64": todo[k], **LOOKS[keys[k]]}
            finally:
                PENDING.pop(keys[k], None)
        async with httpx.AsyncClient(base_url=url.rstrip("/"), headers={"X-Token": token}, timeout=30) as http:
            r = await http.post("/characters", json={"characters": characters})
            r.raise_for_status()
        print(f"🧸 [미리 그리기] 그림 서버에 맡김: { {k: v['desc'] for k, v in characters.items()} }", flush=True)
    except Exception as e:      # 그림 서버가 꺼져 있어도 동화 만들기에는 영향 없음
        print(f"⚠️ [미리 그리기] 건너뜀: {_describe(e)}", flush=True)


async def _prepared_look(b64: str) -> Optional[dict]:
    """미리 그리기에서 만든 설명 (만드는 중이면 기다린다). 없으면 None."""
    key = pixel_key(b64)
    if key in PENDING:
        try:
            await PENDING[key]
        except Exception:
            return None
    return LOOKS.get(key)


def _lines(items: Dict[str, str]) -> str:
    return "\n".join(f"- {k}: {v}" for k, v in items.items()) or "- none"


async def plan_story(client, model, pages, drawn, undrawn, place) -> dict:
    """GPT 글 호출 1번으로 장면 계획 + 캐릭터별 짧은 설명·팔다리 개수."""
    prompt = PLAN_PROMPT.format(
        drawn=_lines(drawn), undrawn=_lines(undrawn), place=place or "none",
        slots=", ".join(SLOTS), sizes=", ".join(SIZES), poses=", ".join(POSES), anchors=", ".join(ANCHORS),
        pages=json.dumps(pages, ensure_ascii=False, indent=1))
    res = await client.chat.completions.create(
        model=model, messages=[{"role": "user", "content": prompt}],
        response_format={"type": "json_object"}, max_completion_tokens=6000)
    return json.loads(res.choices[0].message.content)


def _describe(e: Exception) -> str:
    """시간 초과·연결 끊김 같은 오류는 메시지가 비어 있는 경우가 많아 종류 이름을 함께 남긴다."""
    return f"{type(e).__name__}: {e}" if str(e) else type(e).__name__


async def run_on_image_server(characters: dict, plan: dict, url: str, token: str, timeout: float,
                              give_up_after: float = 120) -> Dict[int, str]:
    """그림 서버에 맡기고 끝날 때까지 기다린다 -> {페이지 번호: base64 PNG}.
    임시 터널은 가끔 요청 하나를 놓치거나(연결 끊김·시간 초과·502) 늦게 답한다. 그때마다 동화 전체를 실패로 하면
    그림 서버가 다 그려 놓은 결과를 버리게 되므로, 묻기는 실패해도 다시 묻고 give_up_after 초 넘게 계속 실패할 때만 포기한다.
    (토큰이 틀렸거나 작업이 없다는 답(4xx)은 다시 물어도 같으므로 바로 멈춘다.)"""
    headers = {"X-Token": token}
    # 터널이 응답을 100초까지만 기다리므로 그보다 짧게
    async with httpx.AsyncClient(base_url=url.rstrip("/"), headers=headers, timeout=90) as http:
        r = await http.post("/jobs", json={"characters": characters, "plan": plan})
        r.raise_for_status()
        job_id = r.json()["job_id"]
        start = asyncio.get_running_loop().time()
        failing_since = None
        while asyncio.get_running_loop().time() - start < timeout:
            await asyncio.sleep(5)
            now = asyncio.get_running_loop().time()
            try:
                r = await http.get(f"/jobs/{job_id}")
                if 400 <= r.status_code < 500:
                    r.raise_for_status()
                if r.status_code >= 500:
                    raise httpx.HTTPStatusError(f"{r.status_code}", request=r.request, response=r)
                job = r.json()
            except httpx.HTTPStatusError as e:
                if e.response.status_code < 500:
                    raise
                job = None
                error = e
            except (httpx.TransportError, ValueError) as e:     # 연결 끊김·시간 초과, 깨진 응답
                job = None
                error = e
            if job is None:
                failing_since = failing_since or now
                print(f"⚠️ [우리 모델] 그림 서버에 묻기 실패 ({_describe(error)}) - 다시 묻습니다", flush=True)
                if now - failing_since > give_up_after:
                    raise RuntimeError(f"그림 서버와 {give_up_after:.0f}초 넘게 연결이 안 됩니다 ({_describe(error)})")
                continue
            failing_since = None
            if job["status"] == "done":
                return {p["page"]: p["image_b64"] for p in job["pages"]}
            if job["status"] == "error":
                raise RuntimeError(f"그림 서버 오류: {job['error']}")
        raise TimeoutError(f"그림 서버가 {timeout:.0f}초 안에 끝내지 못했습니다")


async def generate_with_local_engine(
    client,
    model: str,
    pages: List[dict],
    drawings: Dict[str, str],
    blueprints_by_id: Dict[str, str],
    undrawn: Dict[str, str],
) -> List[dict]:
    """pages: [{"page_number", "scene_prompt", "layout_type", "characters"}], drawings: {id: base64 PNG (아이 그림)},
    blueprints_by_id: {id: 그림 설명서}, undrawn: {id: 이름과 특징 (그림 없이 맡긴 에셋)}.
    -> [{"page_number", "image_url", "error"}] (실패해도 예외 대신 페이지마다 사유를 담는다)."""
    url, token = os.getenv("LOCAL_IMAGE_URL", ""), os.getenv("LOCAL_IMAGE_TOKEN", "")
    numbers = [p["page_number"] for p in pages]
    if not url:
        return [{"page_number": n, "image_url": "", "error": "LOCAL_IMAGE_URL 이 없습니다 (Kaggle 그림 서버 주소)"} for n in numbers]
    try:
        drawn_ids = [k for k in drawings if k not in PLACE_IDS]
        plan = await plan_story(
            client, model,
            [{"page": p["page_number"], "layout_type": p.get("layout_type", "single"),
              "panels": PANELS.get(p.get("layout_type"), 1), "text": p["scene_prompt"],
              "characters": [c for c in p.get("characters") or [] if c in drawn_ids]} for p in pages],
            {k: blueprints_by_id.get(k, k) for k in drawn_ids}, undrawn,
            next((blueprints_by_id.get(k) for k in drawings if k in PLACE_IDS), None))
        # 페이지 번호는 앱이 보낸 것을 그대로 쓴다 (GPT 가 1부터 다시 세는 경우)
        for p, n in zip(plan.get("pages", []), numbers):
            p["page"] = n
        used = {c.get("id") for p in plan.get("pages", []) for panel in p.get("panels", []) for c in panel.get("characters", [])}
        looks = plan.get("characters", {})
        characters = {k: {"image_b64": drawings[k], "desc": looks.get(k, {}).get("desc") or k,
                          "arms": int(looks.get(k, {}).get("arms") or 0), "legs": int(looks.get(k, {}).get("legs") or 0)}
                      for k in drawn_ids if k in used}
        # 미리 그리기에서 만든 설명이 있으면 그것을 쓴다 - 설명이 같아야 그림 서버가 미리 그려 둔 캐릭터를 다시 쓴다
        for k in characters:
            prepared = await _prepared_look(drawings[k])
            if prepared:
                characters[k].update(prepared)
        print(f"🗺️ [장면 계획] 캐릭터 {json.dumps({k: {x: v[x] for x in ('desc', 'arms', 'legs')} for k, v in characters.items()}, ensure_ascii=False)}",
              flush=True)
        images = await run_on_image_server(characters, plan, url, token, float(os.getenv("LOCAL_IMAGE_TIMEOUT", "1200")))
    except Exception as e:
        print(f"❌ [우리 모델] 그림 생성 실패: {_describe(e)}", flush=True)
        return [{"page_number": n, "image_url": "", "error": f"우리 모델 그림 생성 실패: {_describe(e)}"} for n in numbers]
    return [{"page_number": n, "image_url": f"data:image/png;base64,{images[n]}" if n in images else "",
             "error": None if n in images else "그림 서버가 이 페이지를 돌려주지 않았습니다"} for n in numbers]
