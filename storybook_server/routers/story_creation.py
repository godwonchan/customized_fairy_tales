from fastapi import APIRouter
from pydantic import BaseModel
from openai import AsyncOpenAI
from dotenv import load_dotenv
import httpx
import base64
import os
import json
import asyncio

load_dotenv()

router = APIRouter()
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))
OPENAI_IMAGE_MODEL = os.getenv("OPENAI_IMAGE_MODEL", "gpt-image-1")


class DrawingGuideRequest(BaseModel):
    character: str
    background: str


class GenerateStoryRequest(BaseModel):
    character: str
    background: str
    drawing_base64: str


# ─── 1. AI 그리기 가이드 생성 ───
@router.post("/stories/drawing-guide")
async def generate_drawing_guide(req: DrawingGuideRequest):
    prompt = f"""
당신은 어린이 미술 선생님이에요. 아이가 동화 속 장면을 그릴 수 있도록 쉽고 친절한 그리기 가이드를 만들어주세요.

주인공: {req.character}
배경: {req.background}

아래 JSON 형식으로만 응답해주세요. 다른 텍스트 없이 JSON만:
{{
  "description": "이 그림에 대한 짧은 소개 (2-3문장, 아이에게 말하는 톤으로)",
  "steps": [
    "1단계 설명",
    "2단계 설명",
    "3단계 설명",
    "4단계 설명",
    "5단계 설명"
  ]
}}
"""
    response = await client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": prompt}],
        temperature=0.7,
        max_tokens=800,
    )
    raw = response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    return json.loads(raw.strip())


# ─── 페이지별 이미지 생성 ───
async def _generate_page_image(page_text: str, character: str, background: str, page_num: int) -> str | None:
    image_prompt = f"""
A beautiful children's fairy tale illustration in soft watercolor and digital art style.

Story scene: {page_text}
Character: {character}
Setting: {background}

Style requirements:
- Warm, magical, cute children's book illustration
- Soft pastel colors with warm golden lighting
- Whimsical and dreamy fairy tale atmosphere
- Adorable and friendly character designs
- No text or words in the image
- Safe and child-friendly content
"""
    try:
        image_response = await client.images.generate(
            model=OPENAI_IMAGE_MODEL,
            prompt=image_prompt,
            size="1024x1024",
            n=1,
        )

        # gpt-image 계열: b64_json으로 직접 반환
        if image_response.data[0].b64_json:
            return image_response.data[0].b64_json

        # dall-e 계열: URL로 반환 → 다운로드 후 base64 변환
        image_url = image_response.data[0].url
        if image_url:
            async with httpx.AsyncClient(timeout=60.0) as http_client:
                img_bytes = (await http_client.get(image_url)).content
            return base64.b64encode(img_bytes).decode("utf-8")

        return None

    except Exception as e:
        print(f"[IMAGE GEN ERROR] page {page_num}: {e}")
        return None


# ─── 2. 그림 분석 + 동화 + 페이지별 AI 이미지 병렬 생성 ───
@router.post("/stories/generate-from-drawing")
async def generate_story_from_drawing(req: GenerateStoryRequest):

    # Step 1: GPT-4o Vision 그림 분석
    vision_response = await client.chat.completions.create(
        model="gpt-4o",
        messages=[{
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/png;base64,{req.drawing_base64}"},
                },
                {
                    "type": "text",
                    "text": f"""이것은 어린이가 그린 그림이에요.
주인공: {req.character}
배경: {req.background}

이 그림을 보고 아이가 무엇을 그렸는지 따뜻하고 긍정적으로 설명해주세요. (2-3문장, 한국어로)
아이의 상상력을 칭찬하는 톤으로 써주세요.""",
                },
            ],
        }],
        max_tokens=300,
    )
    drawing_description = vision_response.choices[0].message.content.strip()

    # Step 2: 동화 생성
    story_prompt = f"""
당신은 어린이 동화 작가예요. 아이가 직접 그린 그림을 바탕으로 따뜻하고 재미있는 동화를 써주세요.

주인공: {req.character}
배경: {req.background}
아이의 그림 설명: {drawing_description}

조건:
- 정확히 5페이지 분량 (각 페이지 2-4문장, 간결하게)
- 어린이가 이해할 수 있는 쉬운 언어
- 긍정적이고 따뜻한 결말
- 각 페이지는 하나의 장면을 묘사

아래 JSON 형식으로만 응답해주세요:
{{
  "title": "동화 제목",
  "pages": [
    "1페이지 내용",
    "2페이지 내용",
    "3페이지 내용",
    "4페이지 내용",
    "5페이지 내용"
  ]
}}
"""
    story_response = await client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": story_prompt}],
        temperature=0.8,
        max_tokens=2000,
    )
    raw = story_response.choices[0].message.content.strip()
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    story_data = json.loads(raw.strip())
    pages = story_data.get("pages", [])

    # Step 3: 5장 이미지 병렬 생성
    page_images = await asyncio.gather(*[
        _generate_page_image(page_text, req.character, req.background, i + 1)
        for i, page_text in enumerate(pages)
    ])

    return {
        "title": story_data.get("title", "나만의 동화"),
        "drawing_description": drawing_description,
        "pages": pages,
        "page_images": list(page_images),
    }