"""RPG 스프라이트 라우터."""

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from rpg_sprite import generate_sprite

router = APIRouter(prefix="/rpg", tags=["rpg-sprite"])


class SpriteRequest(BaseModel):
    description: str
    asset_type: str = "캐릭터"


@router.post("/sprite")
def rpg_sprite(payload: SpriteRequest):
    try:
        b = generate_sprite(payload.description, payload.asset_type)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"스프라이트 생성 실패: {e}")
    return Response(content=b, media_type="image/png")
