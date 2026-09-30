# storybook_server/routers/story_generation.py
import json
import os
from typing import Any, Dict, List, Optional
from fastapi import APIRouter, HTTPException
from openai import AsyncOpenAI  # 👈 1. 진짜 비동기 클라이언트 사용!
from pydantic import BaseModel

router = APIRouter(prefix="/api/story", tags=["Story Generation"])
# 비동기 클라이언트 인스턴스화
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# ── 요청/응답 모델 정의 ──
class StoryGenerateRequest(BaseModel):
    mood: str
    asset_descriptions: Dict[str, Dict[str, str]]
    feedback: Optional[str] = None
    previous_story: Optional[Dict[str, Any]] = None

class StoryPage(BaseModel):
    page: int
    title: str
    content: str
    layout_type: str = "single"
    visual_scene_prompt: str

class StoryGenerateResponse(BaseModel):
    title: str
    pages: List[StoryPage]

@router.post("/generate", response_model=StoryGenerateResponse)
async def generate_fairy_tale(req: StoryGenerateRequest):
    """
    아이의 그림 정보와 분위기를 바탕으로 GPT-4o-mini가 동화 줄거리를 빠르게 작성합니다.
    """
    # 1. 아이의 그림 에셋 정보 텍스트로 정리
    assets_summary = []
    for cat_id, info in req.asset_descriptions.items():
        name = info.get("name", "").strip()
        desc = info.get("desc", "").strip()
        if name:
            detail = f"- [{cat_id}] {name}"
            if desc:
                detail += f" ({desc})"
            assets_summary.append(detail)

    assets_text = "\n".join(assets_summary) if assets_summary else "- 주인공: 용감한 꼬마 영웅"

    # 2. 시스템 프롬프트 (간결한 출력 토큰 유도 & JSON 일원화)
    system_prompt = """
너는 6~8세 아이들을 위한 따뜻하고 상상력이 넘치는 대한민국 최고의 동화 작가야.
아이들이 그린 캐릭터와 도구들을 반드시 이야기의 핵심 요소로 등장시켜줘.

[작성 규칙]
1. 대상 연령: 만 5~8세 (쉬운 구어체, '~했어요', '~했답니다')
2. 분량: 총 3~4개 페이지 (기승전결 구조, 페이지당 3~4문장)
3. 외형 보존: 주인공이나 친구를 다른 생물로 변신시키지 말 것. 머리를 덮는 투구/가면 착용 금지.
4. 연출 분기: 전체 페이지 중 딱 1개 페이지만 'three_panel'로 지정하고, 나머지는 'single'로 지정할 것.
5. 시각 묘사(visual_scene_prompt): 이미지 생성을 위해 **영어 1~2문장(또는 3패널 동작 키워드)**으로 간결하게 작성할 것 (불필요한 미사여구 생략).

[응답 JSON 규격]
반드시 아래 JSON 구조로만 답하세요:
{
  "title": "동화책 전체 제목",
  "pages": [
    {
      "page": 1,
      "title": "소제목",
      "content": "동화 본문 내용",
      "layout_type": "single",
      "visual_scene_prompt": "A boy and a lion walking on a sunny forest path holding a leaf umbrella."
    },
    {
      "page": 2,
      "title": "소제목",
      "content": "동화 본문 내용",
      "layout_type": "three_panel",
      "visual_scene_prompt": "Panel 1: Finds a crystal. Panel 2: Waves the tool. Panel 3: Bright light shines."
    }
  ]
}
"""

    # 3. 유저 프롬프트 (중복 가이드 제거)
    if req.feedback and req.previous_story:
        user_prompt = f"""
[기존 이야기]
제목: {req.previous_story.get('title')}
내용: {json.dumps(req.previous_story.get('pages', []), ensure_ascii=False)}

[아이의 그림 에셋]
{assets_text}

[선택한 분위기]
{req.mood}

[수정 요청]
"{req.feedback}"

위 요청을 반영하여 기존 이야기를 자연스럽게 각색해 줘.
"""
    else:
        user_prompt = f"""
[아이의 그림 에셋]
{assets_text}

[분위기]
{req.mood}

위 에셋들을 주인공으로 3~4쪽짜리 동화를 작성해 줘.
"""

    try:
        # 🚀 2. 비동기 await 호출로 스레드 차단 방지 & 불필요한 토큰 낭비 제거
        response = await client.chat.completions.create(
            model="gpt-4o-mini",
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.7,
            max_tokens=800,  # 💡 1200 -> 800으로 컴팩트하게 제한 (생성 속도 대폭 향상)
        )

        result_json = json.loads(response.choices[0].message.content)
        return StoryGenerateResponse(**result_json)

    except Exception as e:
        print(f"동화 줄거리 생성 에러: {e}")
        hero_name = req.asset_descriptions.get("hero", {}).get("name", "꼬마 영웅")
        return StoryGenerateResponse(
            title=f"{hero_name}의 신나는 모험",
            pages=[
                StoryPage(page=1, title="모험의 시작", content=f"{hero_name}(이)는 비밀의 숲으로 떠났어요.", layout_type="single", visual_scene_prompt="A cute doodle hero stepping into a magical glowing forest"),
                StoryPage(page=2, title="신비한 마법", content="친구와 함께 힘을 합쳐 멋진 마법을 발견했답니다!", layout_type="three_panel", visual_scene_prompt="Panel 1: Finding an item. Panel 2: Using magic. Panel 3: Rainbow glow"),
                StoryPage(page=3, title="행복한 결말", content="모두 함께 활짝 웃으며 모험을 마쳤어요!", layout_type="single", visual_scene_prompt="Joyful party under colorful sky with cute characters")
            ]
        )