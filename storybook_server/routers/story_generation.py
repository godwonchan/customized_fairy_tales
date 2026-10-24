import json
import os
import time  # 👈 [추가] 각 단계별 소요 시간 측정용
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, HTTPException
from openai import AsyncOpenAI
from pydantic import BaseModel, Field
from dotenv import load_dotenv

import traceback  # 👈 디버깅 트레이스백용 추가

load_dotenv()

router = APIRouter(prefix="/api/story", tags=["Story Generation"])
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# 🎯 타깃 스토리 모델: gpt-5.5 바인딩
STORY_MODEL = os.getenv("OPENAI_TEXT_MODEL", "gpt-5.5")


# ── Pydantic 모델 정의 (프론트엔드 통신 규격 100% 호환 보존) ──
class StoryPage(BaseModel):
    page: int
    title: str
    content: str
    layout_type: str = "single"
    characters: List[str] = Field(default_factory=list)
    visual_scene_prompt: str = ""

class StoryGenerateRequest(BaseModel):
    mood: Optional[str] = "자유로운 상상 모험"
    asset_descriptions: Dict[str, Dict[str, str]]
    story_notes: Optional[List[Dict[str, Any]]] = None  # 🎯 [추가!] 아이의 대화 메모 수신
    feedback: Optional[str] = None
    previous_story: Optional[Dict[str, Any]] = None
    page_count: int = Field(4, ge=1)  # 아이가 고른 화 수

class StoryGenerateResponse(BaseModel):
    title: str
    pages: List[StoryPage]


def _summarize_assets(asset_descriptions: Dict[str, Dict[str, str]]):
    """에셋 목록 프롬프트 텍스트, ID→한글 이름 매핑, 에셋 ID 목록 (줄거리·장면 생성 공용)"""
    assets_summary = []
    available_ids = list(asset_descriptions.keys())

    # ID와 실제 한글 이름 매핑 (본문 안전 치환용)
    id_to_name: Dict[str, str] = {}

    for cat_id, info in asset_descriptions.items():
        name = info.get("name", "").strip()
        desc = info.get("desc", "").strip()
        if name:
            id_to_name[cat_id] = name
            detail = f"- [{cat_id}] 이름: '{name}'"
            if desc:
                detail += f" (특징: {desc})"
            assets_summary.append(detail)

    assets_text = "\n".join(assets_summary) if assets_summary else "- [hero] 이름: '용감한 친구'"
    return assets_text, id_to_name, available_ids


@router.post("/generate", response_model=StoryGenerateResponse)
async def generate_fairy_tale(req: StoryGenerateRequest):
    assets_text, id_to_name, available_ids = _summarize_assets(req.asset_descriptions)

    # 🎯 3. gpt-5.5 전용 고도화 시스템 프롬프트
    # - 카테고리/템플릿 족쇄 완전 제거 (아이의 캐릭터 설정과 대화 중심 전개)
    # - 장면 설명(visual_scene_prompt)은 아이가 줄거리를 다 고친 뒤 /scenes에서 따로 생성
    system_prompt = f"""
너는 6~8세 아이들의 기발한 상상력을 세상에 단 하나뿐인 동화책으로 완성하는 대한민국 최고의 아동 문학 작가이자 아트 디렉터야.
등록된 캐릭터/에셋 목록:
{assets_text}

[핵심 서사 원칙]
1. 획일적인 모험 클리셰(단순 만남 -> 도구 탐색 -> 악당 마법 대결 -> 화해)나 고정된 카테고리 틀에 이야기를 억지로 맞추지 마세요.
2. 아이가 부여한 캐릭터들의 독특한 이름, 특징, 행동 방식을 사건 전개의 최우선 인과관계로 삼아 자유롭고 창의적인 서사를 펼치세요.
3. 캐릭터가 사물 형태이거나 눈코입이 없더라도 인위적으로 사람이나 전형적인 동물로 의인화하지 말고, 아이가 부여한 형태 그대로 자연스럽게 활약하도록 서술하세요.
4. 대상 연령: 만 5~8세 (따뜻하고 리듬감 넘치는 구어체, '~했어요', '~했답니다')
5. 분량: 정확히 총 {req.page_count}개 페이지 (자연스러운 기승전결, 페이지당 3~4문장)
6. 본문(content) 규칙:
   - 아이들이 직접 읽는 동화 본문이므로 영문 ID 토큰([hero] 등)을 절대 쓰지 마세요.
   - 반드시 에셋 목록에 주어진 실제 한글 이름만 사용하여 읽기 쉽게 작성하세요.

[응답 JSON 규격]
반드시 아래 JSON 구조로만 답하세요:
{{
  "title": "동화책 전체 제목",
  "pages": [
    {{
      "page": 1,
      "title": "소제목",
      "content": "동화 본문 내용 (반드시 실제 한글 이름 사용)"
    }}
  ]
}}
"""

# 🎯 대화 메모(story_notes) 텍스트 정제
    notes_summary = []
    if req.story_notes:
        for note in req.story_notes:
            about = note.get("about", "이야기")
            ans = note.get("answer", "").strip()
            if ans:
                notes_summary.append(f"- [{about}] 아이의 생각/사건: '{ans}'")
    notes_text = "\n".join(notes_summary) if notes_summary else "- 자유롭고 즐거운 상상 모험"

    if req.feedback and req.previous_story:
        user_prompt = f"""
[기존 이야기]
제목: {req.previous_story.get('title')}
내용: {json.dumps(req.previous_story.get('pages', []), ensure_ascii=False)}

[아이의 그림 에셋]
{assets_text}

[아이와 나눈 대화 기록 (반영 필수)]
{notes_text}

[수정 요청]
"{req.feedback}"

위 요청과 아이의 대화 기록을 반영하여 기존 이야기의 맥락을 살려 총 {req.page_count}쪽으로 자연스럽게 각색해 줘. 본문에는 에셋 ID 대신 실제 한글 이름을 사용해 줘!
"""
    else:
        user_prompt = f"""
[아이의 그림 에셋]
{assets_text}

[아이와 나눈 대화 기록 (최우선 반영 필수)]
{notes_text}

아이들이 등록한 캐릭터의 개성과 위 대화 기록의 사건/생각을 최우선 인과관계로 삼아 {req.page_count}쪽짜리 창의적인 동화를 작성해 줘. 본문에는 에셋 ID 대신 실제 한글 이름을 사용해 줘!
"""

    try:
        print("\n" + "═" * 60, flush=True)
        print("🚀 [1/3] 줄거리 생성 요청 수신!", flush=True)
        print(f"  - 등록된 캐릭터 에셋: {len(req.asset_descriptions)}개 ({list(id_to_name.values())})", flush=True)
        print(f"  - 아이의 대화 메모 수: {len(req.story_notes or [])}개", flush=True)
        print(f"🤖 [2/3] OpenAI {STORY_MODEL} 호출 시작 (최대 8,000 토큰 예산 할당)...", flush=True)

        start_time = time.perf_counter()

        # 🎯 gpt-5.5 호출: 8,000 토큰 버짓으로 추론 + 4컷 JSON 완전 출력 보장
        response = await client.chat.completions.create(
            model=STORY_MODEL,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            max_completion_tokens=8000,
        )

        elapsed = time.perf_counter() - start_time
        choice = response.choices[0]
        finish_reason = choice.finish_reason

        # 📊 토큰 사용량 및 gpt-5.5 내부 추론(Reasoning) 토큰 정밀 분석
        usage = response.usage
        prompt_tokens = usage.prompt_tokens if usage else 0
        completion_tokens = usage.completion_tokens if usage else 0
        total_tokens = usage.total_tokens if usage else 0

        reasoning_tokens = 0
        if usage and hasattr(usage, "completion_tokens_details") and usage.completion_tokens_details:
            reasoning_tokens = getattr(usage.completion_tokens_details, "reasoning_tokens", 0) or 0

        print(f"⏱️ [완료 소요 시간]: {elapsed:.2f}초", flush=True)
        print("📊 [토큰 텔레메트리]:", flush=True)
        print(f"  - 프롬프트(입력) 토큰: {prompt_tokens:,} tokens", flush=True)
        print(f"  - 모델 내부 추론 토큰: {reasoning_tokens:,} tokens (gpt-5.5의 생각 분량)", flush=True)
        print(f"  - 최종 생성(출력) 토큰: {completion_tokens:,} tokens", flush=True)
        print(f"  - 총합 사용 토큰:     {total_tokens:,} tokens", flush=True)

        # 🚨 토큰 부족으로 인한 잘림 여부 즉시 판별
        if finish_reason == "length":
            print("🚨 [경고] finish_reason == 'length' : 토큰 한도 초과로 JSON이 중간에 잘렸습니다!", flush=True)
        else:
            print(f"✅ [생성 상태]: finish_reason == '{finish_reason}' (정상 완료)", flush=True)

        print("✨ [3/3] OpenAI 응답 수신 완료! JSON 파싱 및 데이터 정제 시작...", flush=True)
        result_json = json.loads(choice.message.content)

        # 🛡️ 2중 안전망 100% 유지: 본문 토큰 자동 치환 및 범용 에셋 전역 복원
        for page_data in result_json.get("pages", []):
            # 1. 혹시 LLM이 본문(content)에 [hero] 등을 남겼다면 실제 한글 이름으로 치환
            content_text = page_data.get("content", "")
            for cat_id, name in id_to_name.items():
                content_text = content_text.replace(f"[{cat_id}]", name)
                content_text = content_text.replace(cat_id, name)
            page_data["content"] = content_text

        print("🎉 [성공] 모든 페이지 정제 완료 -> 프론트엔드로 200 OK 응답 반환\n" + "═" * 60, flush=True)
        return StoryGenerateResponse(**result_json)

    except Exception as e:
        print(f"동화 줄거리 생성 에러: {e}")
        traceback.print_exc()  # 👈 정확한 에러 위치와 원인 상세 출력
        first_id = available_ids[0] if available_ids else "hero"
        first_name = id_to_name.get(first_id, "주인공")
        return StoryGenerateResponse(
            title="신나는 모험 이야기",
            pages=[
                StoryPage(page=1, title="모험의 시작", content=f"{first_name}의 신나는 이야기가 시작되었어요.", layout_type="single", characters=[first_id], visual_scene_prompt=f"[{first_id}] setting off on a journey in a sunny forest."),
                StoryPage(page=2, title="신비한 발견", content="길을 걷다 신기한 것을 발견했답니다!", layout_type="three_panel", characters=available_ids[:2], visual_scene_prompt=f"Top: [{first_id}] exploring. Bottom left: Finding a glowing stone. Bottom right: cheering."),
                StoryPage(page=3, title="즐거운 마무리", content="모두 함께 웃으며 즐겁게 하루를 마쳤어요!", layout_type="single", characters=available_ids, visual_scene_prompt=f"[{first_id}] smiling together under the sunset.")
            ]
        )

# ── 🎨 장면 설명 생성: "이 이야기로 완성!"을 누를 때 최종 줄거리로 만듦 ──
class SceneStoryPage(BaseModel):
    page: int
    title: str = ""
    content: str
    visual_scene_prompt: str = ""  # 다시 만들지 않는 화의 기존 장면 설명 (조연 생김새 참고용)
    layout_type: str = ""  # 다시 만들지 않는 화의 기존 배치 (분할 화 개수·연속 제한 참고용)

class SceneGenerateRequest(BaseModel):
    asset_descriptions: Dict[str, Dict[str, str]]
    title: str = ""
    pages: List[SceneStoryPage]  # 맥락 파악용 동화 전체
    target_pages: List[int]  # 장면 설명이 필요한 화 번호

class PageScene(BaseModel):
    page: int
    layout_type: str = "single"
    characters: List[str] = Field(default_factory=list)
    visual_scene_prompt: str

class SceneGenerateResponse(BaseModel):
    scenes: List[PageScene]


@router.post("/scenes", response_model=SceneGenerateResponse)
async def generate_scenes(req: SceneGenerateRequest):
    assets_text, id_to_name, available_ids = _summarize_assets(req.asset_descriptions)

    system_prompt = f"""
너는 6~8세 아이들의 동화책 일러스트를 연출하는 대한민국 최고의 아트 디렉터야.
등록된 캐릭터/에셋 목록:
{assets_text}

[장면별 활성 에셋(characters)]
- 해당 장면에 등장하거나, 배경 무대가 되거나, 본문 이야기 속에서 언급·사용되는 모든 에셋 ID를 characters 배열에 빠짐없이 포함하세요.
- 결말부 페이지에서는 모험을 함께 마무리하는 주요 인물 ID가 누락되지 않도록 모두 담으세요.

[레이아웃 연출]
- 각 화의 본문을 보고 그림 배치를 정하세요.
  - 핵심 장면 하나로 충분하면 'single'
  - 시간 순서로 이어지는 사건이 2개라 한 장면에 담기 어려우면 'two_panel' (위아래 2칸)
  - 사건이 3개 이상이면 'three_panel' (위 넓은 칸 1개 + 아래 2칸)
- 분할(two_panel, three_panel) 화는 전체 화 수의 절반 이하로 하고, 분할 화가 연달아 나오지 않게 하며, 1화는 반드시 'single'로 하세요. (다른 화의 기존 배치가 주어지면 함께 고려하세요.)
- 분할 화의 visual_scene_prompt는 칸마다 나누어 쓰세요. (two_panel: "Top: ... Bottom: ...", three_panel: "Top: ... Bottom left: ... Bottom right: ...")

[🎨 OpenAI gpt-image-2 시각 묘사(visual_scene_prompt) 엄격 프로토콜]
1. 모든 페이지에 빠짐없이 visual_scene_prompt 키를 영문 1~2문장으로 작성하세요.
2. 캐릭터 주체는 오직 등록된 에셋 ID 토큰([hero], [companion], [villain], [custom_...])으로만 표기하세요. (인간 명사 boy, girl, human 등 사용 엄격 금지)
3. [ENTITY PRESENCE GROUNDING (에셋 본체 상시 출현 강제)]:
- 본문에 등장한 행동, 능력, 도구 뒤로 캐릭터 본체가 가려지거나 사물로 치환되는 현상을 엄격히 금지합니다.
- 특정 에셋이 마법, 도구, 구조물을 사용할 때 해당 결과물만 묘사하지 말고, 반드시 해당 에셋 토큰 본체가 화면에 직접 서 있거나 떠서 그 행동을 주도하는 모습을 문장에 명시하세요.
4. [STORY PROPS VS CHILD ASSET LAYER SEPARATION (소품 분리 서술)]:
- 아이가 등록한 에셋 토큰([hero], [companion], [item], [villain], [custom_...]) 외에, 동화 이야기 전개를 위해 본문에 추가된 사물이나 도구는 반드시 'ordinary background watercolor props without glowing outlines'로 규정하여 분리 서술하세요.
5. [SCENE FOCUS & STAGING (장면당 집중도)]:
- 한 장면에 모든 에셋을 무리하게 몰아넣지 마세요. 해당 장면의 이야기 사건을 주도하는 핵심 에셋 2~3개 위주로 시각적 포커스를 맞추어 visual_scene_prompt를 구성하세요.
6. [배경과 전경의 분리]:
   - 배경 요소(동굴의 보석, 숲의 버섯 등)와 인물이 사용하는 도구를 명확히 분리하여, gpt-image-2가 배경 물건을 인물의 무기나 행동 도구로 오인하지 않도록 서술하세요.
7. [STORY-ADDED SIDE CHARACTERS (이야기에 새로 나온 조연)]:
- 등록된 에셋 토큰이 아닌 생물·동물·인물(예: 길 잃은 아기 동물)이 장면에 나오면, 종류·크기·색·특징을 구체적인 영문 문구로 한 번 정하고(예: a tiny brown baby rabbit with a white fluffy tail), 그 조연이 나오는 모든 장면에 똑같은 문구를 그대로 쓰세요.
- 조연은 반드시 'ordinary watercolor side character without glowing outlines'로 규정하여 아이가 등록한 에셋과 분리 서술하세요.
- 다른 화의 기존 장면 설명이 주어지면 같은 조연은 그 문구를 그대로 따르세요. 단, 지금 본문에 더 이상 나오지 않는 조연은 넣지 말고, 본문에서 다른 조연으로 바뀌었다면 새 조연의 문구를 새로 정하세요.

[응답 JSON 규격]
반드시 아래 JSON 구조로만 답하세요:
{{
  "scenes": [
    {{
      "page": 1,
      "layout_type": "single",
      "characters": ["hero", "companion"],
      "visual_scene_prompt": "[hero] and [companion] walking together along a sunny grassy path toward a distant castle."
    }}
  ]
}}
"""

    story_pages = [{"page": p.page, "title": p.title, "content": p.content} for p in req.pages]
    existing_scenes = [
        {"page": p.page, "layout_type": p.layout_type, "visual_scene_prompt": p.visual_scene_prompt}
        for p in req.pages
        if p.page not in req.target_pages and p.visual_scene_prompt.strip()
    ]
    existing_text = (
        f"\n[다른 화의 기존 배치·장면 설명 (분할 제한과 같은 조연의 생김새 참고용)]\n{json.dumps(existing_scenes, ensure_ascii=False)}\n"
        if existing_scenes else ""
    )
    user_prompt = f"""
[동화 전체]
제목: {req.title}
내용: {json.dumps(story_pages, ensure_ascii=False)}
{existing_text}
위 동화 전체 흐름을 참고해서, 다음 화들의 장면만 작성해 줘: {req.target_pages}
"""

    try:
        print(f"\n🎨 장면 설명 생성 요청: 대상 {req.target_pages}화 / 전체 {len(req.pages)}화", flush=True)
        response = await client.chat.completions.create(
            model=STORY_MODEL,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            max_completion_tokens=8000,
        )
        result_json = json.loads(response.choices[0].message.content)
    except Exception as e:
        print(f"장면 설명 생성 에러: {e}")
        traceback.print_exc()
        raise HTTPException(status_code=502, detail="장면 설명 생성 실패")

    content_by_page = {p.page: p.content for p in req.pages}
    scenes = []
    for scene in result_json.get("scenes", []):
        try:
            scene["page"] = int(scene.get("page"))  # 모델이 "1"처럼 문자열로 줄 때 대비
        except (TypeError, ValueError):
            continue
        if scene["page"] not in req.target_pages:
            continue
        content_text = content_by_page.get(scene["page"], "")

        # 1. 범용 characters 복원 (단독 누락 방어 및 전역 에셋 검사)
        chars = scene.get("characters", [])
        for cat_id, name in id_to_name.items():
            if len(name) >= 2 and name in content_text and cat_id not in chars:
                chars.append(cat_id)

        # fallback: 아무것도 잡히지 않았을 경우 기본 ID 보장
        if not chars:
            chars = [available_ids[0] if available_ids else "hero"]
        scene["characters"] = chars

        # 2. visual_scene_prompt 누락 방어
        prompt = scene.get("visual_scene_prompt") or scene.get("scene_prompt") or scene.get("prompt")
        if not prompt or not str(prompt).strip():
            active_tokens = " and ".join(f"[{c}]" for c in chars)
            scene["visual_scene_prompt"] = f"{active_tokens} interacting together in a scenic setting."
        else:
            scene["visual_scene_prompt"] = str(prompt).strip()

        print(f"  📄 [{scene.get('page')}화] 최종 바인딩 에셋: {scene['characters']}")
        scenes.append(PageScene(**scene))

    return SceneGenerateResponse(scenes=scenes)


# ── ✏️ 아이가 직접 고친 화 살펴보기: 다른 화와 어긋나는지, 그림이 달라지는지 ──
EDIT_CHECK_MODEL = os.getenv("OPENAI_EDIT_CHECK_MODEL", "gpt-4o-mini")

class OtherPage(BaseModel):
    page: int
    content: str

class EditCheckRequest(BaseModel):
    page: int
    old_content: str
    new_content: str
    other_pages: List[OtherPage]

class EditCheckResponse(BaseModel):
    affects_other_pages: bool = False
    suggestion: str = ""  # 다른 화에 반영할 내용 (예: "아기 동물을 아기 새로")
    changes_picture: bool = True


@router.post("/check_edit", response_model=EditCheckResponse)
async def check_edit(req: EditCheckRequest):
    system_prompt = """
너는 아이가 직접 고친 동화 한 화를 살펴보는 편집 도우미야. 아이가 쓴 글은 절대 고치지 말고 판단만 해.

[판단 기준]
1. affects_other_pages: 고친 화에서 다른 화에도 나오는 등장인물·조연·중요한 대상이 다른 것으로 바뀌었거나 사라져서, 다른 화와 이야기가 어긋나게 될 때만 true.
   - 문장을 덧붙인 것, 그 화에만 나오는 것을 고친 것, 표현을 다듬은 것, 줄거리와 관계없는 말을 넣은 것은 false.
2. suggestion: affects_other_pages가 true일 때, 다른 화에도 반영할 변경을 아이에게 말하듯 짧은 한국어로 써 (예: "아기 동물을 아기 새로"). false면 빈 문자열.
3. changes_picture: 장면에 보이는 것(등장인물, 행동, 장소, 물건, 분위기)이 달라지면 true. 오타·띄어쓰기·말투만 바뀌었으면 false.

반드시 아래 JSON 구조로만 답하세요:
{"affects_other_pages": false, "suggestion": "", "changes_picture": true}
"""
    user_prompt = f"""
[고친 화: {req.page}화]
고치기 전: {req.old_content}
고친 후: {req.new_content}

[다른 화]
{json.dumps([p.model_dump() for p in req.other_pages], ensure_ascii=False)}
"""
    try:
        response = await client.chat.completions.create(
            model=EDIT_CHECK_MODEL,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            max_tokens=200,
        )
        result = EditCheckResponse(**json.loads(response.choices[0].message.content))
        print(f"✏️ [{req.page}화 직접 수정 판단] 다른 화 영향: {result.affects_other_pages} ({result.suggestion}) / 그림 변경: {result.changes_picture}", flush=True)
        return result
    except Exception as e:
        # 판단에 실패하면 묻지 않고, 그 화만 다시 그리는 기본 동작으로
        print(f"직접 수정 판단 에러: {e}")
        return EditCheckResponse()
