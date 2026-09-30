# storybook_server/routers/story_image.py
import asyncio
import base64
import io
import os
from typing import Dict, List, Optional, Any
from dotenv import load_dotenv
from fastapi import APIRouter, HTTPException
from openai import AsyncOpenAI
from pydantic import BaseModel
from PIL import Image

load_dotenv(override=True)

router = APIRouter(prefix="/api/story", tags=["Story Illustration"])
IMAGE_MODEL = os.getenv("OPENAI_IMAGE_MODEL", "gpt-image-1-mini")
VISION_MODEL = "gpt-4o"

client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY", ""))

CATEGORY_LABELS = {
    "hero": "Hero Entity",
    "companion": "Companion Entity",
    "item": "Magic Artifact",
    "magic_tool": "Magic Artifact",
    "place": "Landscape Landmark",
    "secret_place": "Landscape Landmark",
    "villain": "Shadow Entity",
    "pet": "Pet Creature",
    "vehicle": "Vehicle",
    "food": "Food Item",
    "treasure": "Treasure",
}

class PageIllustrationRequest(BaseModel):
    page_number: int
    scene_prompt: str
    mood: str = "신나는 모험"
    layout_type: str = "single"

class StoryIllustrationRequest(BaseModel):
    drawn_assets_base64: Optional[Dict[str, str]] = {}
    asset_descriptions: Optional[Dict[str, Any]] = {}
    pages: List[PageIllustrationRequest]

class PageIllustrationResponse(BaseModel):
    page_number: int
    image_url: str

class StoryIllustrationResponse(BaseModel):
    illustrations: List[PageIllustrationResponse]

def _flatten_to_white_bg(b64_png: str) -> str:
    try:
        img_bytes = base64.b64decode(b64_png)
        img = Image.open(io.BytesIO(img_bytes)).convert("RGBA")
        white_bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
        composite = Image.alpha_composite(white_bg, img).convert("RGB")
        composite.thumbnail((512, 512))

        buffer = io.BytesIO()
        composite.save(buffer, format="PNG", optimize=True)
        return base64.b64encode(buffer.getvalue()).decode("utf-8")
    except Exception as e:
        print(f"⚠️ 배경 합성 건너뜀: {e}")
        return b64_png

# 👁️ GPT-image 맞춤형 정밀 스케치 분석 (레이어 분리: 두상 외곽 / 이마 헤어선 / 표정 / 몸체)
async def _extract_sketch_dna(cat_id: str, image_b64: str) -> tuple[str, str]:
    role_label = CATEGORY_LABELS.get(cat_id, cat_id.capitalize())
    flat_b64 = _flatten_to_white_bg(image_b64)

    prompt_text = (
        f"You are a master character artist analyzing a hand-drawn 2D doodle sketch of '{role_label}'. "
        "Your absolute goal is to document the child's exact drawing faithfully without guessing or stereotyping. "
        "Analyze the visual structure in these 4 separate layers:\n\n"
        "1. HEAD CONTOUR & PROTRUSIONS:\n"
        "- Trace the base head boundary outline. Is it round, oval, or elongated?\n"
        "- Record any distinct upward protrusions connected to the head outline (such as 2 distinct rounded lobes/ears, pointed horn-like peaks, or a surrounding outer perimeter frame). Describe their exact positions and shapes.\n\n"
        "2. FOREHEAD & HAIR/SURFACE MARKS (Inside the head):\n"
        "- Look inside the upper head area: Are there drawn hair strokes or zigzag fringe lines across the forehead? (Distinguish internal hair lines from the outer head contour itself).\n"
        "- Describe the exact pattern of the hair or state if the forehead is completely clean.\n\n"
        "3. FACIAL MARKS & EXPRESSION:\n"
        "- Eye shape: Look closely at whether they are drawn as single horizontal sleeping slit lines '- -', open circular loops, or solid dots. State the exact drawn eye shape.\n"
        "- Mouth and nose: Exact drawn line shapes (straight line, open circular mouth, smiling curve, or dot).\n\n"
        "4. BODY, LIMBS & DETACHED EXTENSIONS:\n"
        "- Body stance: Upright vertical torso or horizontal quadruped body.\n"
        "- Limbs/Feet: Number and placement of stubby limbs or support bumps along the bottom.\n"
        "- Torso surface: Record if the torso is completely blank white, or contains patterns/stripes.\n"
        "- Outward Tail/Extension: Look behind the body for an outward trailing stroke (such as a curled spiral or loop). If none exists, write strictly: 'NONE'.\n\n"
        "End with: 'Visual Style: Flat 2D white doodle sprite with crisp black outline strokes and a glowing warm golden aura.'"
    )

    try:
        res = await client.chat.completions.create(
            model=VISION_MODEL,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt_text},
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{flat_b64}"}},
                    ],
                }
            ],
            max_tokens=320,
            temperature=0.0,
        )
        description = res.choices[0].message.content.strip()
        print(f"📐 [GPT-image 캐릭터 블루프린트 추출 완료] {role_label}:\n{description}\n")
        return cat_id, description
    except Exception as e:
        print(f"⚠️ {role_label} 분석 오류: {e}")
        return cat_id, "a flat 2D white doodle sprite with a glowing warm golden aura"


# 🎨 2. GPT-image 전용 페이지 생성 (원본 1:1 보존 & 1~4화 일관성 잠금)
async def _generate_single_page(p: PageIllustrationRequest, master_entity_sheet: str) -> PageIllustrationResponse:
    print(f"\n🚀 [{p.page_number}화] GPT-image 생성 호출 (타입: {p.layout_type})")

    if p.layout_type == "three_panel":
        layout_text = (
            "Format: 3-panel horizontal comic strip side-by-side separated by clean thin borders. "
            f"Left to right narrative progression: {p.scene_prompt}. "
            "CRITICAL: Maintain the exact identical doodle character silhouettes consistently across all 3 panels."
        )
    else:
        layout_text = f"Scene Action: {p.scene_prompt}."

    image_prompt = (
        f"A charming fantasy children's storybook watercolor illustration. Atmosphere: {p.mood}.\n"
        f"Scene: {layout_text}\n\n"
        "===========================================================\n"
        "[LOCKED CHARACTER MASTER BLUEPRINTS - STRICT FIDELITY]:\n"
        f"{master_entity_sheet}\n"
        "===========================================================\n\n"
        "MANDATES FOR GPT-IMAGE EXECUTION:\n"
        "1. STRICT CHARACTER FIDELITY (FAITHFUL TO CHILD'S DRAWING):\n"
        "   - Render each character exactly according to its blueprint. Preserve every drawn feature (head protrusions, forehead zigzag hair, exact eye slits or dots, body limbs, and trailing tail).\n"
        "   - Do NOT turn characters into generic cartoon animals or humans. Retain the authentic charm and structure of the child's sketch.\n"
        "2. COMPLETE CHARACTER ISOLATION (ZERO BLEEDING):\n"
        "   - Features described for Hero belong ONLY to Hero. Features described for Companion belong ONLY to Companion. NEVER copy or mix traits between characters.\n"
        "3. CROSS-PANEL CONSISTENCY:\n"
        "   - Characters must look 100% identical in silhouette, facial glyphs, and features across every page and panel.\n"
        "4. ART STYLE INTEGRATION:\n"
        "   - Characters are flat 2D white doodle stickers with crisp black ink strokes and a warm glowing golden outline, seamlessly living inside a rich, dreamy watercolor storybook world. Masterpiece, high resolution, NO speech bubbles, NO text."
    )

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
            print(f"✅ [{p.page_number}화] 생성 완료")
            return PageIllustrationResponse(page_number=p.page_number, image_url=img_data)
        elif hasattr(first_item, "url") and first_item.url:
            print(f"✅ [{p.page_number}화] 생성 완료")
            return PageIllustrationResponse(page_number=p.page_number, image_url=first_item.url)
        else:
            raise ValueError("이미지 데이터가 없습니다.")

    except Exception as e:
        print(f"❌ [{p.page_number}화] 생성 실패: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/generate_illustrations", response_model=StoryIllustrationResponse)
async def generate_illustrations(req: StoryIllustrationRequest):
    print(f"\n🎨 동화 일러스트 생성 파이프라인 가동 (총 {len(req.pages)}페이지)")

    drawn_assets = req.drawn_assets_base64 or {}
    master_entity_sheet = ""

    for cat_id, b64 in drawn_assets.items():
        print(f"📦 [수신된 스케치] {cat_id}: {len(b64)} 자 (Base64)")

    if drawn_assets:
        vision_tasks = [
            _extract_sketch_dna(cat_id, b64)
            for cat_id, b64 in drawn_assets.items()
        ]
        results = await asyncio.gather(*vision_tasks)

        lines = []
        for cat_id, sheet_desc in results:
            label = CATEGORY_LABELS.get(cat_id, cat_id.capitalize())
            lines.append(f"● [LOCKED BLUEPRINT: {label.upper()}]\n{sheet_desc}")
        master_entity_sheet = "\n\n".join(lines)
    else:
        master_entity_sheet = "● [LOCKED BLUEPRINT: HERO ENTITY]\nA flat 2D white doodle sprite with a glowing warm golden aura."

    tasks = [_generate_single_page(p, master_entity_sheet) for p in req.pages]
    page_results = await asyncio.gather(*tasks)
    return StoryIllustrationResponse(illustrations=list(page_results))