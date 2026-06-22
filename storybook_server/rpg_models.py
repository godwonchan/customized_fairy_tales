"""
RPG 레이어 DB 테이블 + 요청/응답 스키마.

기존 app_core 의 engine 을 그대로 사용한다.
이 파일은 routers/rpg.py 에서 import 되며,
main.py 의 startup 단계에서 SQLModel.metadata.create_all(engine) 가
호출될 때 아래 테이블들이 자동 생성된다.
"""

from datetime import datetime
from typing import Optional, List

from sqlmodel import SQLModel, Field
from pydantic import BaseModel


# =========================================================
# DB 테이블
# =========================================================
class RpgPlaythrough(SQLModel, table=True):
    """동화 한 편을 RPG로 플레이하는 1회 세션."""
    id: Optional[int] = Field(default=None, primary_key=True)
    story_id: int = Field(index=True)
    player_name: str = "주인공"
    status: str = "playing"          # playing | ended
    summary: str = ""                # 누적 줄거리 요약(매 턴 AI에 주입)
    last_narrative: str = ""         # 직전 장면(다음 턴 컨텍스트)
    turn_index: int = 0
    max_turns: int = 6
    level: int = 1
    exp: int = 0
    courage: int = 0                 # 용기
    wisdom: int = 0                  # 지혜
    kindness: int = 0                # 친절
    asset_hint: str = ""             # "제비→꼬마 드래곤, 박씨→별빛 씨앗"
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class RpgTurn(SQLModel, table=True):
    """진행 로그(엔딩 판정/복기용)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    playthrough_id: int = Field(index=True)
    turn_index: int
    narrative: str
    choices_json: str = "[]"
    chosen_id: Optional[str] = None
    stat_changes_json: str = "{}"
    created_at: datetime = Field(default_factory=datetime.utcnow)


class RpgNpcMessage(SQLModel, table=True):
    """NPC 자유 대화 히스토리."""
    id: Optional[int] = Field(default=None, primary_key=True)
    playthrough_id: int = Field(index=True)
    npc_name: str = Field(index=True)
    role: str                        # user | assistant
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class RpgEnding(SQLModel, table=True):
    """획득 엔딩 기록(도감)."""
    id: Optional[int] = Field(default=None, primary_key=True)
    playthrough_id: int = Field(index=True)
    story_id: int = Field(index=True)
    ending_type: str
    title: str
    narrative: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


# =========================================================
# 요청 / 응답 스키마
# =========================================================
class RpgChoice(BaseModel):
    id: str
    text: str


class RpgStartRequest(BaseModel):
    story_id: int
    player_name: str = "주인공"
    asset_hint: str = ""             # 사용자가 그린 요소 치환 규칙
    max_turns: int = 6


class RpgTurnRequest(BaseModel):
    playthrough_id: int
    choice_id: Optional[str] = None  # 선택지로 진행
    free_text: Optional[str] = None  # 자유 입력으로 진행


class RpgTurnResponse(BaseModel):
    playthrough_id: int
    turn_index: int
    narrative: str
    choices: List[RpgChoice]
    stat_changes: dict
    stats: dict
    is_ending: bool


class RpgNpcChatRequest(BaseModel):
    playthrough_id: int
    npc_name: str
    message: str


class RpgNpcChatResponse(BaseModel):
    npc_name: str
    reply: str


class RpgEndingResponse(BaseModel):
    playthrough_id: int
    ending_type: str
    title: str
    narrative: str
    stats: dict


class RpgPlaythroughState(BaseModel):
    playthrough_id: int
    story_id: int
    player_name: str
    status: str
    turn_index: int
    max_turns: int
    narrative: str
    stats: dict