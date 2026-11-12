# storybook_server/routers/avatar.py
"""나를 닮은 주인공 만들기: 사진에서 머리 모양·머리색·피부 톤·안경 여부만 읽어 꾸미기 화면의 처음 모습을 맞춘다.

- 사진은 저장하지 않는다 (파일로 쓰지 않고, 로그에도 남기지 않는다). 읽은 특징(번호 4개)만 돌려준다.
- 그림 생성 모델을 쓰지 않고 가벼운 비전 모델을 한 번만 부른다 (비용·대기 시간을 줄이기 위해).
- 보기 번호는 앱의 lib/screens/creation/avatar_maker_screen.dart (AvatarConfig) 와 같아야 한다.
"""
import base64
import io
import json
import os

from dotenv import load_dotenv
from fastapi import APIRouter, HTTPException
from openai import AsyncOpenAI
from PIL import Image
from pydantic import BaseModel

load_dotenv()

router = APIRouter(prefix="/api/avatar", tags=["Avatar"])
client = AsyncOpenAI(api_key=os.getenv("OPENAI_API_KEY"))

AVATAR_MODEL = os.getenv("OPENAI_AVATAR_MODEL", "gpt-4o-mini")

FEATURE_PROMPT = """This photo is used to pre-fill a cartoon avatar maker for a children's storybook app.
Look only at the main person's hairstyle, hair color, skin tone and glasses, and pick the closest option numbers.
Do not identify the person and do not describe anything else.

Return ONLY JSON:
{"skin": 0, "hair_style": 0, "hair_color": 0, "glasses": false}

skin: 0 very light, 1 light, 2 tan, 3 dark
hair_style: 0 short hair, 1 bob (around chin length), 2 long hair (past the shoulders),
            3 two pigtails or two braids, 4 tied up (bun or ponytail), 5 curly hair
hair_color: 0 black, 1 dark brown, 2 light brown, 3 blond, 4 red or orange, 5 pink or other dyed color
glasses: true if wearing glasses"""


class AvatarFeatureRequest(BaseModel):
    image_base64: str


class AvatarFeatureResponse(BaseModel):
    skin: int = 0
    hair_style: int = 0
    hair_color: int = 0
    glasses: bool = False


def _small_jpeg_b64(image_b64: str) -> str:
    """사진을 작게 줄여 JPEG 로 (보내는 양과 비용을 줄이고, 사진에 들어 있는 위치 정보 등도 함께 지워진다)."""
    if "," in image_b64:
        image_b64 = image_b64.split(",", 1)[1]
    img = Image.open(io.BytesIO(base64.b64decode(image_b64))).convert("RGB")
    img.thumbnail((512, 512))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=80)
    return base64.b64encode(buf.getvalue()).decode()


def _clamp(value, count: int) -> int:
    try:
        v = int(value)
    except (TypeError, ValueError):
        return 0
    return v if 0 <= v < count else 0


@router.post("/features", response_model=AvatarFeatureResponse)
async def read_avatar_features(req: AvatarFeatureRequest):
    try:
        photo_b64 = _small_jpeg_b64(req.image_base64)
    except Exception:
        raise HTTPException(status_code=400, detail="사진을 읽을 수 없습니다.")

    try:
        res = await client.chat.completions.create(
            model=AVATAR_MODEL,
            response_format={"type": "json_object"},
            max_tokens=100,
            messages=[{"role": "user", "content": [
                {"type": "text", "text": FEATURE_PROMPT},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{photo_b64}", "detail": "low"}},
            ]}],
        )
        data = json.loads(res.choices[0].message.content)
    except Exception as e:
        print(f"⚠️ [아바타] 사진 특징 읽기 실패: {type(e).__name__}", flush=True)
        raise HTTPException(status_code=502, detail="사진에서 특징을 읽지 못했습니다.")

    result = AvatarFeatureResponse(
        skin=_clamp(data.get("skin"), 4),
        hair_style=_clamp(data.get("hair_style"), 6),
        hair_color=_clamp(data.get("hair_color"), 6),
        glasses=bool(data.get("glasses")),
    )
    print(f"🪞 [아바타] 사진 특징: {result.model_dump()}", flush=True)
    return result
