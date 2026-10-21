import os
import io
import re
import time
import base64
import asyncio
import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Optional
from fastapi import APIRouter
from pydantic import BaseModel, Field
from openai import AsyncOpenAI
from PIL import Image
from dotenv import load_dotenv

# 🎯 1. .env 환경변수 직접 로드
load_dotenv()

router = APIRouter(prefix="/api/story", tags=["Story Illustration"])
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# 🎯 2. 비전 분석 모델: gpt-5.5 바인딩
VISION_MODEL = os.getenv("OPENAI_TEXT_MODEL", "gpt-5.5")

# 🎯 3. 최종 동화 일러스트 생성 모델: gpt-image-2 바인딩
IMAGE_MODEL = os.getenv("OPENAI_IMAGE_MODEL", "gpt-image-2")


def link_story_tags(text: str, asset_descriptions: Optional[Dict[str, Dict[str, str]]] = None) -> str:
    """[hero] 같은 에셋 ID 태그를 ENTITY 블록의 role 이름과 아이가 붙인 이름으로 바꿔 장면 속 행동 주체를 유지"""
    if not text:
        return ""

    def _replace(match: re.Match) -> str:
        asset_id = match.group(1)
        role = CATEGORY_LABELS.get(asset_id, asset_id.replace("_", " ").title()).lower()
        name, _ = _asset_name_and_desc((asset_descriptions or {}).get(asset_id))
        return f"the {role} '{name}'" if name else f"the {role}"

    return re.sub(r"\[([A-Za-z0-9_]+)\]", _replace, text).strip()


# ── Pydantic 모델 정의 ──
class PageIllustrationRequest(BaseModel):
    page_number: int
    scene_prompt: str
    layout_type: str = "single"
    mood: str = "warm and gentle"
    characters: Optional[List[str]] = Field(default_factory=list)
    scene_assets: Optional[List[str]] = Field(default_factory=list)

    @property
    def active_asset_ids(self) -> List[str]:
        return self.scene_assets or self.characters or []


class StoryIllustrationBatchRequest(BaseModel):
    pages: List[PageIllustrationRequest]
    drawn_assets_base64: Optional[Dict[str, str]] = None
    asset_images: Optional[Dict[str, str]] = None
    # 에셋 ID별 아이가 붙인 이름·특징 ({"hero": {"name": "...", "desc": "..."}})
    asset_descriptions: Optional[Dict[str, Dict[str, str]]] = None

    @property
    def assets(self) -> Dict[str, str]:
        return self.drawn_assets_base64 or self.asset_images or {}


class PageIllustrationResponse(BaseModel):
    page_number: int
    image_url: str
    error: Optional[str] = None  # 실패한 페이지는 image_url을 비우고 사유를 담음


class StoryIllustrationBatchResponse(BaseModel):
    illustrations: List[PageIllustrationResponse]


CATEGORY_LABELS = {
    "hero": "Hero Protagonist",
    "companion": "Companion Entity",
    "item": "Story Item",
    "place": "Environment Setting",
    "vehicle": "Vehicle Entity",
    "villain": "Villain Creature",
    "food": "Magical Food",
    "treasure": "Hidden Treasure",
}


# 앱이 "AI에게 맡기기"를 고른 에셋에 붙이는 표시 문구 (이미지 프롬프트에는 넣지 않음)
AI_DELEGATED_NAME_SUFFIX = "(AI 생성)"
AI_DELEGATED_DESC = "요정이 대신 상상해서 그릴 예정"


def _asset_name_and_desc(info: Optional[Dict[str, str]]) -> tuple[str, str]:
    """asset_descriptions 항목에서 앱의 표시용 문구를 걷어낸 이름·특징을 반환"""
    info = info or {}
    name = info.get("name", "").replace(AI_DELEGATED_NAME_SUFFIX, "").strip()
    desc = info.get("desc", "").strip()
    if desc == AI_DELEGATED_DESC:
        desc = ""
    return name, desc


def _flatten_to_white_bg(base64_str: str) -> str:
    """투명 배경 PNG를 흰색 배경으로 합성"""
    try:
        if "," in base64_str:
            base64_str = base64_str.split(",")[1]
        img_bytes = base64.b64decode(base64_str)
        img = Image.open(io.BytesIO(img_bytes)).convert("RGBA")

        bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
        combined = Image.alpha_composite(bg, img).convert("RGB")

        buffer = io.BytesIO()
        combined.save(buffer, format="PNG")
        return base64.b64encode(buffer.getvalue()).decode("utf-8")
    except Exception as e:
        print(f"이미지 전처리 오류: {e}")
        return base64_str


# 👁️ 1. OpenAI gpt-5.5 전용 2D 캐릭터 디자인 시트 추출기
async def _extract_sketch_dna(cat_id: str, image_b64: str) -> tuple[str, str]:
    role_label = CATEGORY_LABELS.get(cat_id, cat_id.replace("_", " ").title())
    flat_b64 = _flatten_to_white_bg(image_b64)

    # 🎯 Gestalt 2D 캐릭터 모델 시트 프롬프트
    # - 기하 도면 분해(정점 개수, 핏줄 획) 폐기 -> 온전한 2D 캐릭터 형상 인지
    # - 별 모양, 소년, 카드 등 아이의 전체 조형 상징을 자연스럽게 인식
    # - 점 눈, 다리, 머리칼 색상을 왜곡 없이 보존
    prompt_text = (
        f"You are a master animation character designer recording an authentic model sheet for '{role_label}'. "
        "Faithfully document the unique hand-drawn character design exactly as drawn by the child. "
        "Do NOT invent undrawn features, and do NOT over-fragment lines into engineering blueprints. "
        "Strictly follow this structured schema without conversational filler:\n\n"
        "1. OVERALL SILHOUETTE & BODY MORPHOLOGY:\n"
        "- Primary Silhouette Shape: Describe the complete gestalt form (e.g., star-like form with lateral points, simple humanoid boy figure, rectangular card tablet, animal-like creature, etc.).\n"
        "- Outer Boundary Features: Note distinctive contours such as pointed horizontal tips, curved lobes, or angular corners.\n"
        "- Framing State: Full-body figure or upper-body portrait.\n\n"
        "2. APPENDAGES, LIMBS & PROTRUSIONS:\n"
        "- Distinct Limbs: Record drawn appendages such as simple stick legs extending downward, arms extending outward, or decorative tufts.\n"
        "- Upper Head / Top Contour: Describe any hair tufts, spiky hair crests, or ear-like shapes drawn on the top contour. If the top is completely smooth and bare, state 'SMOOTH_ROUNDED'.\n"
        "- If no separate limbs or appendages exist, state 'NONE'.\n\n"
        "3. FACIAL FEATURES & INTERIOR MARKS:\n"
        "- Eyes: Describe the drawn eyes (two simple dark dot eyes, circular outlines, or tilt). Never dismiss small dots as noise.\n"
        "- Mouth & Expression: Describe any drawn mouth line (simple smile arc, open line, teeth, or neutral mark).\n"
        "- Interior Marks: Note any drawn patterns or shapes inside the body boundary.\n"
        "- If the interior has zero drawn facial marks or patterns, write strictly 'NONE'.\n\n"
        "4. COLOR PALETTE SPECIFICATION:\n"
        "- Line Art Ink: Color of outer drawn contour lines.\n"
        "- Hair / Distinct Feature Ink: Specific drawn colors for hair tufts, footwear, or specific marks.\n"
        "- Interior Body Fill: If filled with color, specify the hue. If uncolored white paper outline, state 'UNCOLORED_WHITE_FILL'.\n\n"
        "Output an authentic, cohesive 2D character model sheet."
    )

    try:
        start_time = time.perf_counter()

        # 🎯 gpt-5.5 호출: high detail 및 넉넉한 토큰 버짓
        res = await client.chat.completions.create(
            model=VISION_MODEL,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt_text},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/png;base64,{flat_b64}",
                                "detail": "high"
                            }
                        },
                    ],
                }
            ],
            max_completion_tokens=1500,
        )

        elapsed = time.perf_counter() - start_time
        choice = res.choices[0]
        description = choice.message.content.strip()

        usage = res.usage
        completion_tokens = usage.completion_tokens if usage else 0
        reasoning_tokens = 0
        if usage and hasattr(usage, "completion_tokens_details") and usage.completion_tokens_details:
            reasoning_tokens = getattr(usage.completion_tokens_details, "reasoning_tokens", 0) or 0

        print(f"📐 [블루프린트 추출 완료] {role_label} ({elapsed:.2f}초, 추론: {reasoning_tokens}t, 출력: {completion_tokens}t):\n{description}\n", flush=True)
        return cat_id, description

    except Exception as e:
        print(f"⚠️ {role_label} 분석 오류: {e}", flush=True)
        return cat_id, f"A 2D hand-drawn character design for {role_label}"


# ✏️ 그림 없이 맡긴 에셋의 디자인 시트를 한 번만 만들어 모든 페이지에 같은 모습으로 쓰이게 함
async def _design_undrawn_asset(cat_id: str, name: str, desc: str) -> tuple[str, str]:
    role_label = CATEGORY_LABELS.get(cat_id, cat_id.replace("_", " ").title())
    prompt_text = (
        f"Design one concrete look for the '{role_label}' named '{name}' in a children's storybook. "
        f"The child's description: {desc or 'none'}. "
        "Write a short English design sheet (3-5 lines, no filler) that fixes its shape, size, "
        "main colors, and distinctive features, so an illustrator draws it identically on every page."
    )
    try:
        res = await client.chat.completions.create(
            model=VISION_MODEL,
            messages=[{"role": "user", "content": prompt_text}],
            max_completion_tokens=1500,
        )
        sheet = res.choices[0].message.content.strip()
        print(f"✏️ [디자인 시트 생성 완료] {role_label} '{name}':\n{sheet}\n", flush=True)
        return cat_id, sheet
    except Exception as e:
        print(f"⚠️ {role_label} 디자인 시트 생성 오류: {e}", flush=True)
        return cat_id, ""


async def design_undrawn_assets(
    blueprints_by_id: Dict[str, str],
    asset_descriptions: Optional[Dict[str, Dict[str, str]]],
) -> Dict[str, str]:
    """그림이 없고 이름만 있는 에셋마다 디자인 시트를 생성"""
    tasks = []
    for k, info in (asset_descriptions or {}).items():
        name, desc = _asset_name_and_desc(info)
        if k in blueprints_by_id or not name:
            continue
        tasks.append(_design_undrawn_asset(k, name, desc))
    return {k: sheet for k, sheet in await asyncio.gather(*tasks) if sheet}


# 🎨 2. OpenAI gpt-image-2 전용 2D 스프라이트 융합 및 2계층 일러스트 프롬프트 생성기
def _build_page_prompt(
    p: PageIllustrationRequest,
    blueprints_by_id: Dict[str, str],
    hero_name: str = "",
    asset_descriptions: Optional[Dict[str, Dict[str, str]]] = None,
    design_sheets_by_id: Optional[Dict[str, str]] = None,
) -> str:
    # 그림 없이 이름·특징만 있는 에셋(AI에게 맡긴 캐릭터)의 설명
    described_by_id: Dict[str, str] = {}
    for k, info in (asset_descriptions or {}).items():
        name, desc = _asset_name_and_desc(info)
        if k in blueprints_by_id or not name:
            continue
        described_by_id[k] = (
            "NO DRAWING PROVIDED: Design this entity yourself from its role and the child's words, "
            "and keep the same design on every page.\n"
            f"- Name: '{name}'\n"
            f"- Child's description: {desc or 'none'}"
        )
        sheet = (design_sheets_by_id or {}).get(k)
        if sheet:
            described_by_id[k] += f"\n- Fixed design sheet (draw exactly this design):\n{sheet}"

    active_candidate_ids = p.active_asset_ids
    active_keys = [k for k in active_candidate_ids if k in blueprints_by_id or k in described_by_id]
    if not active_keys and blueprints_by_id:
        active_keys = [next(iter(blueprints_by_id))]

    page_blueprints = []
    for k in active_keys:
        label = CATEGORY_LABELS.get(k, k.replace("_", " ").title())
        entity_text = blueprints_by_id.get(k) or described_by_id[k]
        page_blueprints.append(
            f'<ENTITY count="1" id="{k}" role="{label}">\n{entity_text}\n</ENTITY>'
        )

    scene_entities_text = "\n\n".join(page_blueprints) if page_blueprints else "No specific character drawings provided."
    print(f"  👉 [{p.page_number}화] 활성화된 에셋: {active_keys}")

    clean_action_text = link_story_tags(p.scene_prompt, asset_descriptions)

    # 아이가 붙인 주인공 이름 (없으면 일반 명칭)
    hero_ref = f"'{hero_name}'" if hero_name else "the hero"
    hero_ref_cap = f"'{hero_name}'" if hero_name else "The hero"

    if p.layout_type == "three_panel":
        layout_text = (
            "Format: A 3-panel story comic layout on a single canvas, separated by clean thin borders:\n"
            "- TOP HALF (Wide Establishing Panel): One full-width horizontal panel showing the main situation.\n"
            "- BOTTOM HALF (Split Sequential Panels): Two equal side-by-side square panels (Left and Right) showing sequential reactions and actions.\n"
            f"Narrative Flow: {clean_action_text}\n"
            "Keep all panels and figures safely inside the borders. Maintain identical character designs and golden auras across all three panels."
        )
    else:
        layout_text = f"Scene Action: {clean_action_text}"

    # 🌟 OpenAI gpt-image-2 전용 일러스트 프롬프트
    # - 검증된 2D 손그림 캐릭터 스프라이트 + 부드러운 금빛 아우라 스타일 복원
    # - 도플갱어 인간 아이 렌더링 엄격 차단 (아이가 그린 [hero]가 곧 주인공)
    # - 이야기 추가 소품(이불, 밧줄) 2계층 분리 (금빛 테두리 제외)
    # - 활성 엔티티 전원 무대 배치 (Anti-Dropping)
    image_prompt = (
        "===========================================================\n"
        "[IMMUTABLE CHARACTER & ENTITY MODEL SHEETS - MASTER VISUAL ANCHORS]:\n"
        f"{scene_entities_text}\n"
        "===========================================================\n\n"
        "A masterwork children's storybook watercolor illustration.\n"
        f"Mood: {p.mood}.\n"
        f"Scene Action & Composition: {layout_text}\n\n"
        "EXECUTION DIRECTIVES FOR GPT-IMAGE-2:\n"
        "1. CHARACTER RENDERING & PROTAGONIST IDENTITY:\n"
        f"   - THE DRAWN SPRITE IS THE CHARACTER: The declared <ENTITY id=\"hero\"> is {hero_ref} himself. Strictly NEVER render an ordinary human boy, real child, or human body in the scene. {hero_ref_cap} MUST be rendered entirely as the unique drawn 2D character specified in its blueprint.\n"
        "   - 2D SPRITE ART WITH GOLDEN AURA: Render declared character entities (<ENTITY>) as charming, expressive 2D hand-drawn character sprites retaining their original crayon/ink stroke feel and colors. Each declared character sprite must feature a gentle, warm, luminous golden aura contour that makes them shine naturally in the fairy tale world.\n"
        "   - EXPRESSIVE LIVING BEINGS: While keeping their core silhouette and signature colors (e.g., hair tufts, limb shapes, dot eyes) completely consistent, characters can express emotions, bend limbs, run, and interact naturally with the scene.\n\n"
        "2. STRICT TWO-LAYER SEPARATION (CHILD ENTITIES VS STORY PROPS):\n"
        "   - GOLDEN AURA ONLY FOR DECLARED ENTITIES: Only the declared <ENTITY> sprites receive the warm golden aura.\n"
        "   - STORY-ADDED PROPS ARE ORDINARY WATERCOLOR OBJECTS: Any additional items, bedding, blankets, ropes, bowls, jars, or rocks mentioned in the narrative that are NOT declared <ENTITY> items must be rendered as ordinary background watercolor objects with painterly washes. Absolutely ZERO golden outlines or glowing edges on story-added props.\n\n"
        "3. FULL ENTITY PRESENCE (ANTI-DROPPING PROTOCOL):\n"
        "   - Every declared character entity in the active asset list MUST appear visibly on stage as an independent, active participant. Never omit or replace any declared character with mere inanimate props or background marks.\n\n"
        "4. SCENERY & ENVIRONMENT INTEGRATION:\n"
        "   - If an <ENTITY> with role 'Environment Setting' (or id 'place') is declared, seamlessly render the full watercolor background based on its environment design without drawing it as a floating sprite.\n"
        "   - The world must have soft, rich watercolor textures, atmospheric lighting, and translucent painterly depth.\n\n"
        "5. CLEAN PICTURE BOOK ART:\n"
        "   - Pure illustration. Absolutely NO text, NO speech bubbles, NO subtitles, NO watermarks."
    )
    return image_prompt


# 🎨 3. 페이지 한 장 생성 (실패 시 예외 대신 빈 이미지와 사유 반환)
async def _generate_single_page(
    p: PageIllustrationRequest,
    blueprints_by_id: Dict[str, str],
    hero_name: str = "",
    asset_descriptions: Optional[Dict[str, Dict[str, str]]] = None,
    design_sheets_by_id: Optional[Dict[str, str]] = None,
) -> PageIllustrationResponse:
    print(f"\n🚀 [{p.page_number}화] 이미지 생성 호출 시작 (요청 모델: {IMAGE_MODEL}, 레이아웃: {p.layout_type})")
    image_prompt = _build_page_prompt(p, blueprints_by_id, hero_name, asset_descriptions, design_sheets_by_id)

    try:
        response = await client.images.generate(
            model=IMAGE_MODEL,
            prompt=image_prompt,
            size="1024x1024",
            n=1,
        )
        first_item = response.data[0]

        if hasattr(first_item, "b64_json") and first_item.b64_json:
            img_data = f"data:image/png;base64,{first_item.b64_json}"
            print(f"✅ [{p.page_number}화] 이미지 생성 완료 (적용 모델: {IMAGE_MODEL})", flush=True)
            return PageIllustrationResponse(page_number=p.page_number, image_url=img_data)
        elif hasattr(first_item, "url") and first_item.url:
            print(f"✅ [{p.page_number}화] 이미지 생성 완료 (적용 모델: {IMAGE_MODEL})", flush=True)
            return PageIllustrationResponse(page_number=p.page_number, image_url=first_item.url)
        else:
            raise ValueError("이미지 데이터가 없습니다.")

    except Exception as e:
        # 한 페이지 실패가 요청 전체를 실패시키지 않도록, 예외 대신 빈 이미지와 사유를 반환
        print(f"❌ [{p.page_number}화] {IMAGE_MODEL} 생성 실패: {e}", flush=True)
        return PageIllustrationResponse(page_number=p.page_number, image_url="", error=str(e))


@router.post("/generate_illustrations", response_model=StoryIllustrationBatchResponse)
async def generate_story_illustrations(req: StoryIllustrationBatchRequest):
    assets_map = req.assets
    print(f"\n🎨 동화 일러스트 생성 파이프라인 가동 (타입: {IMAGE_MODEL}, 총 {len(req.pages)}페이지)")
    for cat_id, b64 in assets_map.items():
        print(f"📦 [수신된 스케치] {cat_id}: {len(b64)} 자 (Base64)")

    dna_tasks = [
        _extract_sketch_dna(cat_id, b64)
        for cat_id, b64 in assets_map.items()
        if b64 and len(b64) > 100
    ]
    extracted_dnas = await asyncio.gather(*dna_tasks)

    blueprints_by_id: Dict[str, str] = {cat_id: text for cat_id, text in extracted_dnas}

    hero_name, _ = _asset_name_and_desc((req.asset_descriptions or {}).get("hero"))
    design_sheets_by_id = await design_undrawn_assets(blueprints_by_id, req.asset_descriptions)

    page_tasks = [
        _generate_single_page(p, blueprints_by_id, hero_name, req.asset_descriptions, design_sheets_by_id)
        for p in req.pages
    ]
    results = await asyncio.gather(*page_tasks)

    if os.getenv("PROMPT_EVAL_CAPTURE") == "1":
        _save_eval_capture(req, blueprints_by_id, hero_name, list(results), design_sheets_by_id)

    return StoryIllustrationBatchResponse(illustrations=list(results))


# 🧪 프롬프트 비교 테스트용 입력 저장 (PROMPT_EVAL_CAPTURE=1 일 때만 동작)
PROMPT_EVAL_DIR = Path(__file__).resolve().parent.parent / "prompt_eval"


def save_page_outputs(
    out_dir: Path,
    pages: List[PageIllustrationRequest],
    blueprints_by_id: Dict[str, str],
    hero_name: str,
    asset_descriptions: Optional[Dict[str, Dict[str, str]]],
    results: List[PageIllustrationResponse],
    design_sheets_by_id: Optional[Dict[str, str]] = None,
) -> None:
    """페이지별 실제 사용된 프롬프트와 생성 이미지를 out_dir에 저장"""
    out_dir.mkdir(parents=True, exist_ok=True)
    by_page = {r.page_number: r for r in results}
    for p in pages:
        prompt = _build_page_prompt(p, blueprints_by_id, hero_name, asset_descriptions, design_sheets_by_id)
        (out_dir / f"page_{p.page_number}_prompt.txt").write_text(prompt, encoding="utf-8")

        r = by_page.get(p.page_number)
        if r is None:
            continue
        if r.image_url.startswith("data:image"):
            (out_dir / f"page_{p.page_number}.png").write_bytes(base64.b64decode(r.image_url.split(",", 1)[1]))
        elif r.image_url:
            (out_dir / f"page_{p.page_number}_url.txt").write_text(r.image_url, encoding="utf-8")
        else:
            (out_dir / f"page_{p.page_number}_error.txt").write_text(r.error or "", encoding="utf-8")


def _save_eval_capture(
    req: StoryIllustrationBatchRequest,
    blueprints_by_id: Dict[str, str],
    hero_name: str,
    results: List[PageIllustrationResponse],
    design_sheets_by_id: Optional[Dict[str, str]] = None,
) -> None:
    try:
        capture_dir = PROMPT_EVAL_DIR / "inputs" / datetime.now().strftime("%Y%m%d_%H%M%S")
        capture_dir.mkdir(parents=True, exist_ok=True)
        (capture_dir / "request.json").write_text(
            json.dumps(req.model_dump(), ensure_ascii=False, indent=2), encoding="utf-8"
        )
        (capture_dir / "blueprints.json").write_text(
            json.dumps(blueprints_by_id, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        save_page_outputs(
            capture_dir / "before", req.pages, blueprints_by_id, hero_name, req.asset_descriptions, results,
            design_sheets_by_id,
        )
        print(f"🧪 [프롬프트 비교용 입력 저장] {capture_dir}", flush=True)
    except Exception as e:
        print(f"⚠️ 프롬프트 비교용 입력 저장 실패: {e}", flush=True)