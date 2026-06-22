"""RPG 최종 4컷 이미지 — 실제 플레이한 전체 이야기 + 그린 아이템 기반 생성."""

from fastapi import APIRouter, HTTPException, Response
from sqlmodel import Session, select

from app_core import engine, Story
from rpg_models import RpgPlaythrough, RpgTurn
from rpg_scene import generate_final_comic

router = APIRouter(prefix="/rpg", tags=["rpg"])

_FINAL_CACHE: dict = {}


@router.post("/final-image")
def rpg_final_image(payload: dict):
    pid = payload.get("playthrough_id")
    if pid is None:
        raise HTTPException(status_code=400, detail="playthrough_id 필요")

    raw_hints = payload.get("item_hints") or []
    item_hints = [str(h).strip() for h in raw_hints if str(h).strip()]

    cache_key = f"{pid}|{'|'.join(item_hints)}"
    cached = _FINAL_CACHE.get(cache_key)
    if cached:
        return Response(content=cached[0], media_type=cached[1])

    with Session(engine) as session:
        pt = session.get(RpgPlaythrough, pid)
        if not pt:
            raise HTTPException(status_code=404, detail="플레이 세션을 찾을 수 없습니다.")

        turns = session.exec(
            select(RpgTurn)
            .where(RpgTurn.playthrough_id == pid)
            .order_by(RpgTurn.turn_index)
        ).all()
        story_text = "\n".join(
            t.narrative for t in turns if getattr(t, "narrative", None)
        ).strip()
        if not story_text:
            story_text = pt.last_narrative or pt.summary or ""

        try:
            image_bytes, mime = generate_final_comic(
                player_name=pt.player_name or "주인공",
                story_text=story_text,
                asset_hint=pt.asset_hint or "",
                item_hints=item_hints,
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"4컷 이미지 생성 실패: {e}")

    _FINAL_CACHE[cache_key] = (image_bytes, mime)
    return Response(content=image_bytes, media_type=mime)
