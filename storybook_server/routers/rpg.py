"""
RPG 라우터.

main.py 에 아래 2줄만 추가하면 등록된다:

    from routers.rpg import router as rpg_router
    app.include_router(rpg_router)

엔드포인트:
    POST /rpg/start            : 동화로 RPG 세션 시작(오프닝 반환)
    POST /rpg/turn             : 선택/자유입력으로 다음 턴 진행
    POST /rpg/npc/chat         : NPC와 자유 대화
    POST /rpg/ending           : 엔딩 판정 및 기록
    GET  /rpg/playthrough/{id} : 현재 상태 조회
"""

import json
from datetime import datetime

from fastapi import APIRouter, HTTPException
from sqlmodel import Session, select

from app_core import engine, Story
from rpg_models import (
    RpgPlaythrough,
    RpgTurn,
    RpgNpcMessage,
    RpgEnding,
    RpgChoice,
    RpgStartRequest,
    RpgTurnRequest,
    RpgTurnResponse,
    RpgNpcChatRequest,
    RpgNpcChatResponse,
    RpgEndingResponse,
    RpgPlaythroughState,
)
from rpg_ai import (
    generate_rpg_intro,
    generate_rpg_turn,
    generate_npc_reply,
    decide_rpg_ending,
)

router = APIRouter(prefix="/rpg", tags=["rpg"])


# ---------- 헬퍼 ----------
def _stats(pt: RpgPlaythrough) -> dict:
    return {
        "level": pt.level,
        "exp": pt.exp,
        "courage": pt.courage,
        "wisdom": pt.wisdom,
        "kindness": pt.kindness,
    }


def _apply_changes(pt: RpgPlaythrough, changes: dict) -> None:
    """능력치/경험치 반영 + 간단 레벨업(레벨*20 누적)."""
    def _i(key):
        try:
            return int(changes.get(key, 0) or 0)
        except (TypeError, ValueError):
            return 0

    pt.courage = max(0, pt.courage + _i("courage"))
    pt.wisdom = max(0, pt.wisdom + _i("wisdom"))
    pt.kindness = max(0, pt.kindness + _i("kindness"))
    pt.exp = max(0, pt.exp + _i("exp"))

    while pt.exp >= pt.level * 20:
        pt.exp -= pt.level * 20
        pt.level += 1


def _choices_from(raw) -> list:
    out = []
    for c in (raw or []):
        cid = str(c.get("id") or len(out) + 1)
        text = str(c.get("text") or "").strip()
        if text:
            out.append({"id": cid, "text": text})
    return out


# ---------- 시작 ----------
@router.post("/start", response_model=RpgTurnResponse)
def rpg_start(payload: RpgStartRequest):
    with Session(engine) as session:
        story = session.get(Story, payload.story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        try:
            intro = generate_rpg_intro(
                story_title=story.title,
                story_content=story.content or "",
                player_name=payload.player_name,
                asset_hint=payload.asset_hint,
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"오프닝 생성 실패: {e}")

        narrative = str(intro.get("narrative", "")).strip()
        choices = _choices_from(intro.get("choices"))
        summary = str(intro.get("summary", "")).strip()

        pt = RpgPlaythrough(
            story_id=payload.story_id,
            player_name=payload.player_name,
            asset_hint=payload.asset_hint,
            max_turns=max(3, payload.max_turns),
            summary=summary,
            last_narrative=narrative,
            turn_index=0,
        )
        session.add(pt)
        session.commit()
        session.refresh(pt)

        session.add(RpgTurn(
            playthrough_id=pt.id,
            turn_index=0,
            narrative=narrative,
            choices_json=json.dumps(choices, ensure_ascii=False),
        ))
        session.commit()

        return RpgTurnResponse(
            playthrough_id=pt.id,
            turn_index=pt.turn_index,
            narrative=narrative,
            choices=[RpgChoice(**c) for c in choices],
            stat_changes={},
            stats=_stats(pt),
            is_ending=False,
        )


# ---------- 진행 ----------
@router.post("/turn", response_model=RpgTurnResponse)
def rpg_turn(payload: RpgTurnRequest):
    with Session(engine) as session:
        pt = session.get(RpgPlaythrough, payload.playthrough_id)
        if not pt:
            raise HTTPException(status_code=404, detail="플레이 세션을 찾을 수 없습니다.")
        if pt.status == "ended":
            raise HTTPException(status_code=400, detail="이미 종료된 세션입니다.")

        story = session.get(Story, pt.story_id)
        if not story:
            raise HTTPException(status_code=404, detail="동화를 찾을 수 없습니다.")

        # 플레이어 행동 텍스트 결정
        action_text = (payload.free_text or "").strip()
        if not action_text and payload.choice_id:
            last_turn = session.exec(
                select(RpgTurn)
                .where(RpgTurn.playthrough_id == pt.id)
                .order_by(RpgTurn.turn_index.desc())
            ).first()
            if last_turn:
                for c in json.loads(last_turn.choices_json or "[]"):
                    if str(c.get("id")) == str(payload.choice_id):
                        action_text = c.get("text", "")
                        break
        if not action_text:
            action_text = "주변을 둘러본다."

        try:
            result = generate_rpg_turn(
                story_title=story.title,
                story_content=story.content or "",
                summary=pt.summary,
                last_narrative=pt.last_narrative,
                action_text=action_text,
                player_name=pt.player_name,
                asset_hint=pt.asset_hint,
                courage=pt.courage,
                wisdom=pt.wisdom,
                kindness=pt.kindness,
                turn_index=pt.turn_index,
                max_turns=pt.max_turns,
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"턴 생성 실패: {e}")

        narrative = str(result.get("narrative", "")).strip()
        stat_changes = result.get("stat_changes", {}) or {}
        summary_update = str(result.get("summary_update", "")).strip()
        is_ending = bool(result.get("is_ending", False))
        choices = [] if is_ending else _choices_from(result.get("choices"))

        # 턴 한계 도달 시 강제 엔딩
        if pt.turn_index + 1 >= pt.max_turns:
            is_ending = True
            choices = []

        _apply_changes(pt, stat_changes)
        pt.turn_index += 1
        pt.last_narrative = narrative
        if summary_update:
            pt.summary = summary_update
        pt.updated_at = datetime.utcnow()
        session.add(pt)

        session.add(RpgTurn(
            playthrough_id=pt.id,
            turn_index=pt.turn_index,
            narrative=narrative,
            choices_json=json.dumps(choices, ensure_ascii=False),
            chosen_id=payload.choice_id,
            stat_changes_json=json.dumps(stat_changes, ensure_ascii=False),
        ))
        session.commit()
        session.refresh(pt)

        return RpgTurnResponse(
            playthrough_id=pt.id,
            turn_index=pt.turn_index,
            narrative=narrative,
            choices=[RpgChoice(**c) for c in choices],
            stat_changes=stat_changes,
            stats=_stats(pt),
            is_ending=is_ending,
        )


# ---------- NPC 대화 ----------
@router.post("/npc/chat", response_model=RpgNpcChatResponse)
def rpg_npc_chat(payload: RpgNpcChatRequest):
    with Session(engine) as session:
        pt = session.get(RpgPlaythrough, payload.playthrough_id)
        if not pt:
            raise HTTPException(status_code=404, detail="플레이 세션을 찾을 수 없습니다.")

        story = session.get(Story, pt.story_id)
        if not story:
            raise HTTPException(status_code=404, detail="동화를 찾을 수 없습니다.")

        prev = session.exec(
            select(RpgNpcMessage)
            .where(RpgNpcMessage.playthrough_id == pt.id)
            .where(RpgNpcMessage.npc_name == payload.npc_name)
            .order_by(RpgNpcMessage.created_at)
        ).all()
        history = [{"role": m.role, "content": m.content} for m in prev]

        try:
            reply = generate_npc_reply(
                npc_name=payload.npc_name,
                story_title=story.title,
                story_content=story.content or "",
                summary=pt.summary,
                history=history,
                message=payload.message,
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"NPC 대화 실패: {e}")

        session.add(RpgNpcMessage(
            playthrough_id=pt.id, npc_name=payload.npc_name,
            role="user", content=payload.message,
        ))
        session.add(RpgNpcMessage(
            playthrough_id=pt.id, npc_name=payload.npc_name,
            role="assistant", content=reply,
        ))
        session.commit()

        return RpgNpcChatResponse(npc_name=payload.npc_name, reply=reply)


# ---------- 엔딩 ----------
@router.post("/ending", response_model=RpgEndingResponse)
def rpg_ending(payload: RpgTurnRequest):
    with Session(engine) as session:
        pt = session.get(RpgPlaythrough, payload.playthrough_id)
        if not pt:
            raise HTTPException(status_code=404, detail="플레이 세션을 찾을 수 없습니다.")

        story = session.get(Story, pt.story_id)
        title_src = story.title if story else "동화"

        try:
            result = decide_rpg_ending(
                story_title=title_src,
                player_name=pt.player_name,
                summary=pt.summary,
                courage=pt.courage,
                wisdom=pt.wisdom,
                kindness=pt.kindness,
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"엔딩 생성 실패: {e}")

        ending_type = str(result.get("ending_type", "ordinary"))
        ending_title = str(result.get("title", "이야기의 끝"))
        ending_narrative = str(result.get("narrative", "")).strip()

        pt.status = "ended"
        pt.updated_at = datetime.utcnow()
        session.add(pt)

        session.add(RpgEnding(
            playthrough_id=pt.id,
            story_id=pt.story_id,
            ending_type=ending_type,
            title=ending_title,
            narrative=ending_narrative,
        ))
        session.commit()
        session.refresh(pt)

        return RpgEndingResponse(
            playthrough_id=pt.id,
            ending_type=ending_type,
            title=ending_title,
            narrative=ending_narrative,
            stats=_stats(pt),
        )


# ---------- 상태 조회 ----------
@router.get("/playthrough/{playthrough_id}", response_model=RpgPlaythroughState)
def rpg_state(playthrough_id: int):
    with Session(engine) as session:
        pt = session.get(RpgPlaythrough, playthrough_id)
        if not pt:
            raise HTTPException(status_code=404, detail="플레이 세션을 찾을 수 없습니다.")

        return RpgPlaythroughState(
            playthrough_id=pt.id,
            story_id=pt.story_id,
            player_name=pt.player_name,
            status=pt.status,
            turn_index=pt.turn_index,
            max_turns=pt.max_turns,
            narrative=pt.last_narrative,
            stats=_stats(pt),
        )