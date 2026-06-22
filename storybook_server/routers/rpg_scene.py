"""RPG 장면 이미지 라우터."""

import hashlib

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from sqlmodel import Session

from app_core import engine, Story
from rpg_models import RpgPlaythrough
from rpg_scene import generate_scene_image

router = APIRouter(prefix="/rpg", tags=["rpg-scene"])

_scene_cache: dict[str, tuple[bytes, str]] = {}


class SceneRequest(BaseModel):
    playthrough_id: int
    narrative: str


@router.post("/scene")
def rpg_scene(payload: SceneRequest):
    key = (
        f"{payload.playthrough_id}:"
        f"{hashlib.md5(payload.narrative.encode('utf-8')).hexdigest()}"
    )
    if key in _scene_cache:
        b, m = _scene_cache[key]
        return Response(content=b, media_type=m)

    title = ""
    asset_hint = ""
    with Session(engine) as session:
        pt = session.get(RpgPlaythrough, payload.playthrough_id)
        if pt:
            asset_hint = pt.asset_hint or ""
            story = session.get(Story, pt.story_id)
            if story:
                title = story.title

    try:
        b, m = generate_scene_image(payload.narrative, title, asset_hint)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"장면 이미지 생성 실패: {e}")

    _scene_cache[key] = (b, m)
    return Response(content=b, media_type=m)
