"""사용자 낙서 → 무엇을 그렸는지 한국어 설명 (GPT-4o Vision)."""

import os
import base64

from openai import OpenAI

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


def describe_sketch(image_bytes: bytes, mime_type: str, asset_type: str = "캐릭터") -> str:
    b64 = base64.b64encode(image_bytes).decode("utf-8")
    resp = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {
                "role": "system",
                "content": (
                    "너는 아이가 그린 낙서를 분석하는 전문가다. "
                    "그림을 보고 무엇을 그렸는지 한국어로 '한 문장'으로 친근하게 묘사하라. "
                    "이 그림은 동화 RPG의 요소(캐릭터/무기/동물/아이템)로 쓰인다. "
                    "예: '커다란 날개를 가진 노란 용', '별이 박힌 마법 지팡이'. "
                    "묘사 문장만 출력한다."
                ),
            },
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": f"이 그림은 '{asset_type}' 타입이야. 무엇을 그렸는지 한 문장으로 묘사해줘."},
                    {"type": "image_url", "image_url": {"url": f"data:{mime_type};base64,{b64}"}},
                ],
            },
        ],
        temperature=0.4,
    )
    return (resp.choices[0].message.content or "").strip()
