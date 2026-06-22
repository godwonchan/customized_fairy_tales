"""
RPG 전용 AI 함수.

OpenAI 최신 SDK(openai>=1.0) 기준으로 작성했다.
키는 .env 의 OPENAI_API_KEY 를 사용한다.
"""

import os
import json
from typing import List, Dict, Optional

from openai import OpenAI

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

MODEL = "gpt-4o"

SAFE_STYLE = (
    "한국어로, 7~10세 어린이 눈높이에 맞춰 따뜻하고 안전하게 쓴다. "
    "폭력·공포·잔인한 묘사는 순화한다. 짧고 생생하게 쓴다."
)


def _chat_json(system: str, user: str, temperature: float = 0.8) -> dict:
    """JSON 형식 응답을 강제하고 파싱해서 반환."""
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        response_format={"type": "json_object"},
        temperature=temperature,
    )
    return json.loads(resp.choices[0].message.content)


def _chat_text(system: str, messages: List[Dict[str, str]], temperature: float = 0.8) -> str:
    """일반 텍스트 응답."""
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "system", "content": system}, *messages],
        temperature=temperature,
    )
    return (resp.choices[0].message.content or "").strip()


# =========================================================
# 1) 오프닝(인트로) 장면
# =========================================================
def generate_rpg_intro(
    story_title: str,
    story_content: str,
    player_name: str,
    asset_hint: str,
) -> dict:
    system = (
        "너는 어린이 인터랙티브 동화 RPG의 게임 마스터다. "
        "원작 동화의 핵심 줄거리와 교훈은 유지하되, 플레이어를 1인칭 주인공으로 만들고 "
        "플레이어가 직접 그린 요소를 이야기에 자연스럽게 녹인다. "
        f"{SAFE_STYLE} 반드시 JSON만 출력한다."
    )
    user = f"""원작 제목: {story_title}
원작 내용(참고용):
{story_content[:3000]}

주인공 이름: {player_name}
사용자가 그린 요소 치환 규칙: {asset_hint or '없음'}

요구사항:
- 플레이어가 주인공이 되는 오프닝 장면을 2~4문장으로 쓴다(1인칭, '당신').
- 다음 행동을 고를 선택지 2~4개를 제시한다(각 짧게).
- 누적 요약(summary)을 1~2문장으로 준다.

출력 JSON 형식:
{{"narrative": "string", "choices": [{{"id": "string", "text": "string"}}], "summary": "string"}}"""
    return _chat_json(system, user)


# =========================================================
# 2) 다음 턴 진행
# =========================================================
def generate_rpg_turn(
    story_title: str,
    story_content: str,
    summary: str,
    last_narrative: str,
    action_text: str,
    player_name: str,
    asset_hint: str,
    courage: int,
    wisdom: int,
    kindness: int,
    turn_index: int,
    max_turns: int,
) -> dict:
    system = (
        "너는 어린이 인터랙티브 동화 RPG의 게임 마스터다. "
        "원작의 핵심 줄거리와 교훈을 유지하면서 플레이어의 행동에 따라 이야기를 분기시킨다. "
        f"{SAFE_STYLE} 반드시 JSON만 출력한다."
    )
    user = f"""원작 제목: {story_title}
원작 내용(참고용):
{story_content[:2500]}

주인공 이름: {player_name}
치환 규칙: {asset_hint or '없음'}

지금까지 줄거리 요약:
{summary or '(이야기 시작)'}

직전 장면:
{last_narrative}

플레이어 행동: {action_text}

현재 능력치 → 용기 {courage}, 지혜 {wisdom}, 친절 {kindness}
현재 턴: {turn_index + 1} / 최대 {max_turns}

요구사항:
- 플레이어 행동의 '결과'로 이어지는 다음 장면을 2~4문장으로 쓴다(1인칭).
- 선택지 2~4개 제시(각 짧게).
- 이번 장면에서 변동된 능력치를 stat_changes로 준다.
  (courage/wisdom/kindness 각 0~3 정수, exp 5~15 정수)
- 다음 호출용 누적 요약(summary_update)을 1~3문장으로 준다.
- 현재 턴이 최대 턴에 도달했거나 이야기가 절정/마무리에 이르면
  is_ending=true 로 하고 choices는 빈 배열로 준다.

출력 JSON 형식:
{{"narrative": "string",
  "choices": [{{"id": "string", "text": "string"}}],
  "stat_changes": {{"courage": 0, "wisdom": 0, "kindness": 0, "exp": 0}},
  "summary_update": "string",
  "is_ending": false}}"""
    return _chat_json(system, user)


# =========================================================
# 3) NPC 자유 대화
# =========================================================
def generate_npc_reply(
    npc_name: str,
    story_title: str,
    story_content: str,
    summary: str,
    history: List[Dict[str, str]],
    message: str,
) -> str:
    system = (
        f"너는 동화 '{story_title}' 속 등장인물 '{npc_name}'이다. "
        "캐릭터를 절대 깨지 말고, 그 인물의 말투와 성격으로 한국어로 짧게(1~3문장) 답한다. "
        "너는 아래 세계관과 현재 상황만 알고 있으며, 그 밖의 현대 지식은 모른다. "
        f"{SAFE_STYLE}\n\n"
        f"[세계관 참고]\n{story_content[:1500]}\n\n"
        f"[현재 상황]\n{summary or '이야기 초반'}"
    )
    msgs = [*history[-8:], {"role": "user", "content": message}]
    return _chat_text(system, msgs)


# =========================================================
# 4) 엔딩 판정
# =========================================================
def decide_rpg_ending(
    story_title: str,
    player_name: str,
    summary: str,
    courage: int,
    wisdom: int,
    kindness: int,
) -> dict:
    system = (
        "너는 어린이 동화 RPG의 결말 작가다. "
        "능력치와 줄거리에 가장 어울리는 결말 유형 하나를 고르고 따뜻하게 서술한다. "
        f"{SAFE_STYLE} 반드시 JSON만 출력한다."
    )
    user = f"""제목: {story_title}
주인공: {player_name}
누적 줄거리: {summary}
최종 능력치 → 용기 {courage}, 지혜 {wisdom}, 친절 {kindness}

아래 5가지 결말 유형 중, 능력치와 줄거리에 가장 맞는 하나를 골라라:
- "kind"     : 친절이 높고 남을 도왔을 때 (착한 마음 엔딩)
- "brave"    : 용기가 높고 위기에 맞섰을 때 (용기 엔딩)
- "wise"     : 지혜가 높고 슬기롭게 풀었을 때 (지혜 엔딩)
- "balanced" : 세 능력치가 고르게 성장했을 때 (균형 엔딩)
- "ordinary" : 능력치가 전반적으로 낮거나 소극적이었을 때 (평범한 엔딩)

요구사항:
- title: 결말 제목(짧게).
- narrative: 4~7문장의 따뜻한 결말. 주인공 이름과 그동안의 선택을 반영.

출력 JSON 형식:
{{"ending_type": "string", "title": "string", "narrative": "string"}}"""
    return _chat_json(system, user, temperature=0.7)


# =========================================================
# 5) 엔딩 4컷 만화 — 동화 전체를 4개 장면(영어) 설명으로 변환
# =========================================================
def generate_comic_panels(
    player_name: str,
    story_text: str,
    asset_hint: str = "",
) -> List[str]:
    """플레이한 동화 전체 → 일러스트용 4개 장면의 구체적 영어 설명."""
    system = (
        "You convert a child's ORIGINAL interactive story into EXACTLY FOUR comic "
        "panel descriptions for an illustrator. Output ONLY JSON. "
        "Each description is in ENGLISH, concrete and visual: who is in it, where, "
        "what action, and the key objects. One or two sentences each. "
        "Child-friendly, gentle, non-violent. "
        "Pick the four MOST IMPORTANT and visually distinct moments that ACTUALLY "
        "happen in THIS story, in chronological order. "
        "Never invent classic or Disney scenes that are not in the story. "
        "Keep the same main character in every panel. "
        "If the story features a special object the child created (a drawn item such "
        "as an ice sword, a pet, a treasure, etc.), include it where it appears."
    )
    user = (
        f"Main character name: {player_name}\n"
        f"Main character appearance: {asset_hint or 'a kind young child'}\n\n"
        f"Full story (Korean), in order:\n{story_text[:3500]}\n\n"
        'Return JSON exactly like: {"panels": ["panel 1 ...", "panel 2 ...", '
        '"panel 3 ...", "panel 4 ..."]}  (exactly 4 English descriptions)'
    )
    data = _chat_json(system, user, temperature=0.6)
    panels = [str(p).strip() for p in (data.get("panels") or []) if str(p).strip()]
    while len(panels) < 4:
        panels.append(f"{player_name} smiles happily at the end of the adventure.")
    return panels[:4]
