"""낙서 설명 → 배경 투명 깔끔 스프라이트 (gpt-image-1)."""

import os
import base64

from openai import OpenAI

client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))


def generate_sprite(description: str, asset_type: str = "캐릭터") -> bytes:
    prompt = (
        f"A single {asset_type}: {description}. "
        "Centered, full body, clean simple 2D game sprite, "
        "friendly children's storybook illustration style, soft warm colors, "
        "bold clean outlines, plain background, no scenery, no text, no letters."
    )
    try:
        resp = client.images.generate(
            model="gpt-image-1",
            prompt=prompt,
            size="1024x1024",
            background="transparent",
            n=1,
        )
    except Exception:
        # 구버전 SDK 등으로 background 미지원 시 폴백
        resp = client.images.generate(
            model="gpt-image-1",
            prompt=prompt,
            size="1024x1024",
            n=1,
        )

    data = resp.data[0]
    b64 = getattr(data, "b64_json", None)
    if b64:
        return base64.b64decode(b64)

    url = getattr(data, "url", None)
    if url:
        import urllib.request
        return urllib.request.urlopen(url).read()

    raise RuntimeError("스프라이트 생성 실패")
