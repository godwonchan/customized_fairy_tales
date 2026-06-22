"""RPG 장면/엔딩 이미지 생성."""

import hashlib

from ai_services import generate_plot_image_bytes
from rpg_ai import generate_comic_panels

STYLE = (
    "children's fairy tale storybook illustration, 2D digital painting, "
    "soft warm colors, gentle glow, friendly and whimsical, wholesome, cozy, "
    "child-friendly, non-violent, no text, no letters"
)

_SOFTEN = {
    "명월검": "반짝이는 마법 검",
    "얼음검": "반짝이는 얼음 검",
    "불검": "반짝이는 불꽃 검",
    "무기": "신비한 도구",
    "왕비": "마법사",
    "물리": "달래",
    "대적": "마주하",
    "피": "붉은 노을빛",
    "죽이": "잠재우",
    "죽": "잠들",
    "독": "신비한",
    "공격": "다가가",
    "싸움": "놀이",
    "전투": "모험",
}

_CACHE: dict = {}
_CACHE_MAX = 300


def _soften(text: str) -> str:
    out = text
    for bad, good in _SOFTEN.items():
        out = out.replace(bad, good)
    return out


def _key(prefix: str, *parts: str) -> str:
    raw = prefix + "|" + "|".join(parts)
    return hashlib.md5(raw.encode("utf-8")).hexdigest()


# ---------- 단일 장면(호환 유지, 현재 미사용) ----------
def generate_scene_image(narrative: str, story_title: str = "", asset_hint: str = ""):
    key = _key("scene", story_title, narrative)
    cached = _CACHE.get(key)
    if cached:
        return cached
    plot_no = int(key[:8], 16) % 1_000_000
    prompt = (
        f"A single gentle storybook scene. Scene: {_soften(narrative[:300])} "
        f"Style: {STYLE}."
    )
    image_bytes, mime_type, _f = generate_plot_image_bytes(
        image_prompt=prompt, plot_number=plot_no, reference_images=[],
    )
    result = (image_bytes, mime_type or "image/png")
    if len(_CACHE) >= _CACHE_MAX:
        _CACHE.clear()
    _CACHE[key] = result
    return result


# ---------- 엔딩 4컷: GPT-4o 패널 설명 → 그림 ----------
def generate_final_comic(
    player_name: str = "주인공",
    story_text: str = "",
    asset_hint: str = "",
    item_hints=None,
):
    item_hints = item_hints or []
    panels = []
    try:
        panels = generate_comic_panels(player_name, story_text, asset_hint, item_hints)
    except Exception as e:
        print(f"[final] 패널 설명 생성 실패 → 폴백: {e}")

    plot_no = int(
        _key("final", player_name, story_text, "|".join(item_hints))[:8], 16
    ) % 1_000_000

    items_line = ""
    if item_hints:
        items_line = (
            " Also make sure each of these child-drawn items clearly appears in a "
            "panel: " + "; ".join(item_hints) + "."
        )

    if len(panels) == 4:
        panel_block = "\n".join(f"Panel {i + 1}: {p}" for i, p in enumerate(panels))
        primary = (
            "A single four-panel comic page for young children: a 2x2 grid of four "
            "equal panels separated by clean thin white borders "
            "(panel 1 top-left, panel 2 top-right, panel 3 bottom-left, panel 4 bottom-right). "
            f"The main character is a child named {player_name}, drawn the SAME way in every panel. "
            "Draw exactly these four panels, in order:\n"
            f"{panel_block}\n"
            f"{items_line}\n"
            f"Style: {STYLE}."
        )
    else:
        story = _soften(story_text).strip()[:1500]
        primary = (
            "A four-panel comic page (2x2 grid, clear white borders) for children, "
            "illustrating ONLY the specific events below (NOT the classic version). "
            f"Main character: {player_name}. Story:\n{story}\n{items_line}\nStyle: {STYLE}."
        )

    fallback = (
        "A gentle four-panel comic page (2x2 grid of four panels with clear white "
        f"borders) about a kind child named {player_name} on a small magical "
        f"adventure.{items_line} Style: {STYLE}."
    )

    last_err = None
    for prompt in (primary, fallback):
        try:
            image_bytes, mime_type, _f = generate_plot_image_bytes(
                image_prompt=prompt, plot_number=plot_no, reference_images=[],
            )
            if not image_bytes:
                raise RuntimeError("빈 이미지 응답")
            return image_bytes, (mime_type or "image/png")
        except Exception as e:
            last_err = e
            print(f"[final] 이미지 생성 실패 → 재시도: {e}")
    raise last_err
