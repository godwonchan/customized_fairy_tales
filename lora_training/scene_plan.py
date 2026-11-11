"""장면 계획 -> 페이지 조립.

언어 모델이 줄거리를 읽고 페이지(칸)마다 "누가, 어디에, 어떤 자세로, 어떤 소품과" 나오는지 JSON 으로 정하면,
이 모듈이 배경 위에 캐릭터를 배치·자세 적용하고 소품과 조연을 붙여 페이지를 만든다.

계획을 받아 오는 지시문(GPT)은 기존 서버 storybook_server/services/local_image_engine.py 에 있다 (SLOTS·SIZES·POSES·ANCHORS 와
같은 이름을 쓴다). 이 모듈은 받은 계획을 정리(normalize_plan)하고 조립한다. 이미지 생성은 하지 않는다.
"""
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps
from scipy import ndimage

from puppet import POSES, pose

# ── 1. 계획 형식 ──────────────────────────────────────────────────

SLOTS = {"left": 0.18, "center-left": 0.34, "center": 0.5, "center-right": 0.66, "right": 0.82}
SIZES = {"small": 0.30, "medium": 0.44, "large": 0.58}          # 페이지 높이 대비 캐릭터 키
PLACES = {"ground": 0.90, "air": 0.50}                          # 발(아래쪽)이 놓이는 높이
ANCHORS = ("on_head", "in_hand", "beside", "above")

def normalize_plan(plan, asset_ids):
    """언어 모델 답에서 틀린 값은 기본값으로 바꾸고, 모르는 캐릭터·소품은 버린다 (조립이 멈추지 않게)."""
    pages = []
    for p in plan.get("pages", []):
        panels = []
        for panel in p.get("panels", []) or [p]:
            chars, seen = [], set()
            for c in panel.get("characters", [])[:3]:
                if c.get("id") not in asset_ids or c["id"] in seen:
                    continue
                seen.add(c["id"])
                chars.append({
                    "id": c["id"],
                    "slot": c.get("slot") if c.get("slot") in SLOTS else "center",
                    "size": c.get("size") if c.get("size") in SIZES else "medium",
                    "place": c.get("place") if c.get("place") in PLACES else "ground",
                    "pose": c.get("pose") if c.get("pose") in POSES else "stand",
                    "facing": c.get("facing") if c.get("facing") in ("left", "right") else "right",
                })
            props = [pr for pr in panel.get("props", [])[:2]
                     if pr.get("anchor") in ANCHORS and pr.get("owner") in seen and pr.get("name")]
            extras = [e for e in panel.get("extras", []) if e.get("name")]
            panels.append({"background": panel.get("background", "a cozy storybook place"),
                           "characters": chars, "props": props, "extras": extras})
        pages.append({"page": p.get("page", len(pages) + 1), "panels": panels})
    # 캐릭터가 쓰거나 드는 소품만 따로 그려 붙인다. 한 번이라도 들린 소품은 다른 칸에서도 같은 그림을 쓴다 (모양 일치).
    # 옆에 놓이기만 하는 소품은 배경과 함께 그린다 (painted).
    held = {pr["name"] for p in pages for panel in p["panels"] for pr in panel["props"] if pr["anchor"] in HELD}
    for p in pages:
        for panel in p["panels"]:
            for pr in panel["props"]:
                pr["painted"] = pr["name"] not in held
    return pages


HELD = ("on_head", "in_hand")
_SIDE_WORDS = [(0.26, "on the far left"), (0.42, "on the left"), (0.58, "in the middle"), (0.74, "on the right"),
               (1.01, "on the far right")]


def background_prompt(panel):
    """배경 그림 프롬프트: 한 번만 나오는 조연과 옆에 놓이는 소품은 배경에 같이 그리되,
    캐릭터가 들어갈 자리를 피해 가장 먼 빈 쪽에 작게 그리라고 적는다 (배경이 캐릭터 자리를 모르면 겹치기 때문)."""
    painted = ([e["name"] for e in panel["extras"] if not e.get("recurring")]
               + [pr["name"] for pr in panel["props"] if pr.get("painted")])
    if not painted:
        return panel["background"]
    # 피할 자리 = 아이 캐릭터 + 여러 번 나오는 조연이 놓일 자리. 그중 어느 것과도 가장 먼 가로 위치를 고른다
    recurring = sum(1 for e in panel["extras"] if e.get("recurring"))
    used = [SLOTS[c["slot"]] for c in panel["characters"]] + [SLOTS[s] for s in _free_slots(panel)[:recurring]]
    x = max(np.linspace(0.1, 0.9, 17), key=lambda s: min((abs(s - u) for u in used), default=1))
    where = next(w for edge, w in _SIDE_WORDS if x < edge)
    return f"{panel['background']}, with {', '.join(painted)} small in the distance {where}"

# ── 2. 페이지 조립 ────────────────────────────────────────────────

GOLD = (240, 190, 50)


def _layout(size, entries, sprites):
    """칸 안에서 각 캐릭터가 실제로 차지하는 영역(자세 적용 뒤 크기)으로 자리를 정한다 -> [(x, y, 배율)].
    슬롯은 '대략 어디쯤'일 뿐이라, 칸이 좁거나 캐릭터가 넓으면 슬롯 간격보다 몸이 넓어 겹친다.
    1) 아이 캐릭터: 슬롯 순서를 지키며, 높이가 겹치는 이웃과 겹치지 않을 만큼 좌우로 민다.
       칸 너비가 모자라면 모두 같은 비율로 조금씩 줄인다 (누구 하나만 작아지지 않게).
    2) 여러 번 나오는 조연: 아이 캐릭터가 차지하지 않은 가장 넓은 빈 구간 가운데에, 그 구간에 맞게 줄여 놓는다."""
    W, H = size
    gap = W * 0.02

    def box(c, s, sc, cx):
        w, h = s.width * sc, s.height * sc
        foot = min(c["foot"] * H, H - 2)
        return [cx - w / 2, foot - h, cx + w / 2, foot]

    def overlap_y(a, b):
        return min(a[3], b[3]) - max(a[1], b[1]) > 0.2 * min(a[3] - a[1], b[3] - b[1])

    kids = [i for i, c in enumerate(entries) if not c.get("extra")]
    kids.sort(key=lambda i: SLOTS[entries[i]["slot"]])
    base = {i: min(H * SIZES[entries[i]["size"]] / sprites[i].height, W * 0.45 / sprites[i].width) for i in kids}
    boxes = {}
    for shrink in (1.0, 0.9, 0.8, 0.7, 0.6):
        boxes = {i: box(entries[i], sprites[i], base[i] * shrink, SLOTS[entries[i]["slot"]] * W) for i in kids}
        for _ in range(30):                          # 겹친 이웃끼리 반씩 밀어내기
            moved = False
            for a, b in zip(kids, kids[1:]):
                A, B = boxes[a], boxes[b]
                push = A[2] + gap - B[0]
                if push > 0.5 and overlap_y(A, B):
                    for bx, d in ((A, -push / 2), (B, push / 2)):
                        bx[0] += d; bx[2] += d
                    moved = True
            for bx in boxes.values():               # 칸 밖으로 나가지 않게
                d = max(0 - bx[0], 0) - max(bx[2] - W, 0)
                bx[0] += d; bx[2] += d
            if not moved:
                break
        if all(boxes[a][2] + gap - boxes[b][0] <= 1 or not overlap_y(boxes[a], boxes[b]) for a, b in zip(kids, kids[1:])):
            break
    out = {i: (boxes[i][0], boxes[i][1], base[i] * shrink) for i in kids}
    taken = list(boxes.values())

    for i, c in enumerate(entries):
        if not c.get("extra"):
            continue
        s = sprites[i]
        sc = min(H * SIZES["small"] / s.height, W * 0.45 / s.width)
        probe = box(c, s, sc, W / 2)
        cuts = sorted((max(b[0] - gap, 0), min(b[2] + gap, W)) for b in taken if overlap_y(b, probe))
        free, x = [], 0.0
        for a, b in cuts:
            if a > x:
                free.append((x, a))
            x = max(x, b)
        free.append((x, W))
        lo, hi = max(free, key=lambda f: f[1] - f[0])
        # 빈 구간에 맞게 줄이되 절반 아래로는 줄이지 않는다 (점처럼 작아지면 알아볼 수 없다).
        # 그래도 모자라면 아이 캐릭터 뒤에 일부 가려진 채 놓인다 (작은 것부터 그리므로 뒤에 깔린다)
        sc = max(min(sc, (hi - lo) / s.width), sc * 0.5)
        b = box(c, s, sc, (lo + hi) / 2)
        out[i] = (b[0], b[1], sc)
        taken.append(b)
    return [out[i] for i in range(len(entries))]


def _place_layer(size, sprite, spot, flip):
    """페이지 크기 투명 층에 캐릭터를 spot=(x, y, 배율) 에 놓는다.
    sprite.info["points"](머리·손 좌표)도 같은 자리로 옮겨 돌려준다."""
    W, H = size
    s = ImageOps.mirror(sprite) if flip else sprite
    x, y, sc = spot
    s = s.resize((max(1, int(s.width * sc)), max(1, int(s.height * sc))), Image.LANCZOS)
    x = int(min(max(x, 0), W - s.width))
    y = int(max(y, 0))
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(s, (x, y), s)
    # 오려낸 가장자리가 칼로 자른 듯 딱 떨어지면 스티커처럼 보인다 -> 1픽셀 정도만 부드럽게 (더 흐리면 가는 펜 선이 흐려진다)
    layer.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(1.2)))
    points = {}
    for name, (px, py) in sprite.info.get("points", {}).items():
        if flip:                                     # 좌우가 뒤집히면 왼손·오른손도 바뀐다
            px = sprite.width - px
            name = {"hand_left": "hand_right", "hand_right": "hand_left"}.get(name, name)
        points[name] = (x + px * sc, y + py * sc)
    return layer, points


def _shadow(page, layer, floating):
    box = layer.getchannel("A").getbbox()
    if not box:
        return page
    x0, y0, x1, y1 = box
    w = (x1 - x0) * (0.6 if floating else 1.1)
    cx = (x0 + x1) / 2
    cy = min(y1 + page.height * 0.08, page.height * 0.95) if floating else y1 + w * 0.03
    m = Image.new("L", page.size, 0)
    ImageDraw.Draw(m).ellipse((cx - w / 2, cy - w * 0.1, cx + w / 2, cy + w * 0.1),
                              fill=int(255 * (0.25 if floating else 0.55)))
    return Image.composite(Image.new("RGB", page.size, (60, 40, 30)), page,
                           m.filter(ImageFilter.GaussianBlur(w * 0.06 + 2)))


def _scene_light(bg, layer):
    """캐릭터에 '그 자리 주변'의 배경 색을 입히고(곱하기 25%), 가장자리에 배경의 밝은 빛을 둘러 같은 공간에 있는 느낌.
    그림 전체 평균색을 15% 섞던 방식은 흰색이 거의 그대로 남아, 흰 몸이 수채 배경 위에서 스티커처럼 떴다.
    곱하기라서 흰 곳일수록 주변 빛을 받고 진한 선·눈은 거의 그대로다. 25% 를 넘기면 초록 숲·밤 장면에서 캐릭터가 그 색으로 물든다."""
    alpha = layer.getchannel("A")
    rgb = np.array(layer.convert("RGB")).astype(np.float32)
    b = np.array(bg).astype(np.float32).reshape(-1, 3)
    around = np.array(bg.convert("RGB").filter(ImageFilter.GaussianBlur(bg.width // 16))).astype(np.float32)
    lit = rgb * 0.75 + rgb * (around / 255) * 0.25 * 1.15
    rim = np.array(alpha).astype(np.float32) - np.array(alpha.filter(ImageFilter.MinFilter(9))).astype(np.float32)
    r = np.array(Image.fromarray(np.clip(rim, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)))[..., None] / 255 * 0.35
    lit = lit * (1 - r) + np.percentile(b, 95, axis=0) * r
    out = Image.fromarray(np.clip(lit, 0, 255).astype(np.uint8)).convert("RGBA")
    out.putalpha(alpha)
    return out


def _gold_outline(page, shape):
    """아이 캐릭터만 두르는 금색 테두리. 굵은 띠(9px)와 넓은 번짐은 스티커 칼선처럼 보여, 얇은 띠(5px, 80%)와 은은한 번짐으로."""
    inside = shape.point(lambda v: 255 if v > 128 else 0)
    outside = np.array(ImageOps.invert(inside)) / 255
    glow = np.array(inside.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(8)))
    glow = Image.fromarray((glow * 0.45 * outside).astype(np.uint8))
    ring = Image.fromarray((np.array(inside.filter(ImageFilter.MaxFilter(5))) * outside * 0.8).astype(np.uint8))
    gold = Image.new("RGB", page.size, GOLD)
    page = Image.composite(gold, page, glow)
    return Image.composite(gold, page, ring.filter(ImageFilter.GaussianBlur(1.5)))


# 아이 캐릭터 발광 (2026-11-08 사용자: 배경에 녹아드는 건 좋은데 구분이 너무 약함 - gpt 그림처럼 빛나게).
# 그리는 것이 아니라 마지막에 빛을 합성하므로 모양은 바뀌지 않는다. 세기는 미리보기로 고른다.
# 첫 미리보기: 몸을 흰빛으로 밝히니 주황 몸이 바래 보였고, 밝은 해변에선 후광이 거의 안 보였다 ->
# 몸은 색을 유지한 채 밝게(곱하기), 윤곽 바로 바깥에 밝은 빛 띠(gpt 그림의 노랗게 빛나는 윤곽), 캐릭터 주변 배경을 더 어둡게.
GLOW_LEVELS = {
    "weak":   {"halo": 0.45, "edge": 0.45, "lift": 0.06, "dim": 0.12},
    "medium": {"halo": 0.65, "edge": 0.65, "lift": 0.10, "dim": 0.22},
    "strong": {"halo": 0.85, "edge": 0.85, "lift": 0.14, "dim": 0.32},
}
# 사용자 결정 (2026-11-08 미리보기 후): 강, 단 배경 어둡게는 절반
GLOW = dict(GLOW_LEVELS["strong"], dim=0.16)
HALO_COLOR, EDGE_COLOR = (255, 196, 80), (255, 236, 140)


def _screen(a, color, w):
    """밝게 더하기(스크린) 를 w(0~1, 픽셀마다) 만큼. 어두운 선은 거의 그대로, 밝은 곳은 빛 색으로."""
    lit = 255 - (255 - a) * (255 - np.array(color, np.float32)) / 255
    return a + (lit - a) * w[..., None]


def child_glow(page, shapes, halo, edge, lift, dim):
    """아이 캐릭터가 스스로 빛나는 느낌: ① 캐릭터 둘레 배경을 어둡게(dim, 캐릭터 바로 옆은 후광이 덮고 멀수록 어두움)
    ② 넓고 부드러운 후광(halo) ③ 윤곽 바로 바깥의 밝은 빛 띠(edge) ④ 몸을 색 그대로 한 단계 밝게(lift, 진한 선·눈 제외).
    빛의 크기는 캐릭터 크기에 비례한다 (작은 캐릭터에 큰 후광이 붙지 않게)."""
    masks = [np.array(s) > 128 for s in shapes]
    masks = [m for m in masks if m.any()]
    if not masks:
        return page
    a = np.array(page.convert("RGB")).astype(np.float32)
    union = np.any(masks, axis=0)
    size = np.mean([np.sqrt(m.sum()) for m in masks])
    far = 1 - np.exp(-ndimage.distance_transform_edt(~union) / (0.35 * size))
    a *= (1 - dim * far)[..., None]
    for m in masks:
        s = np.sqrt(m.sum())
        d = ndimage.distance_transform_edt(~m)
        a = _screen(a, HALO_COLOR, halo * np.exp(-d / (0.16 * s)) * ~m)
        a = _screen(a, EDGE_COLOR, edge * np.exp(-((d - 0.012 * s) / (0.012 * s)) ** 2) * ~m)
        lum = a.mean(axis=2)
        light = m & (lum > np.median(lum[m]) - 50)          # 진한 선·눈·입은 밝히지 않는다
        a = np.where(light[..., None], a * (1 + lift), a)    # 곱하기: 주황은 더 선명한 주황으로 (흰빛을 섞으면 바랜다)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def _prop_layer(size, prop, owner_box, facing, points):
    """소품을 주인 캐릭터의 머리 위 / 손 / 옆 / 위 공중에 붙인다.
    머리 위·손은 바깥 상자가 아니라 자세 적용 뒤의 실제 좌표(points)를 쓴다 - 상자 꼭대기는 귀·뿔 끝일 수 있고,
    상자 옆면은 팔이 어디로 갔는지와 상관없기 때문이다. 팔이 없는 캐릭터는 바라보는 쪽 몸 옆에 붙인다."""
    x0, y0, x1, y1 = owner_box
    w, h = x1 - x0, y1 - y0
    anchor = prop["anchor"]
    rel_h = {"on_head": 0.32, "in_hand": 0.30, "beside": 0.40, "above": 0.30}[anchor]
    img = prop["image"]
    sc = h * rel_h / img.height
    img = img.resize((max(1, int(img.width * sc)), max(1, int(img.height * sc))), Image.LANCZOS)
    side = 1 if facing == "right" else -1
    hands = [p for n, p in points.items() if n.startswith("hand_")]
    if anchor == "on_head":
        hx, hy = points.get("head", ((x0 + x1) / 2, y0))
        x, y = hx - img.width / 2, hy - img.height * 0.85                  # 머리에 살짝 걸치게
    elif anchor == "in_hand" and hands:
        hx, hy = max(hands, key=lambda p: p[0] * side)                     # 바라보는 쪽 손
        x, y = hx - img.width / 2, hy - img.height / 2
    elif anchor == "in_hand":
        edge = x1 if side > 0 else x0
        x, y = edge - img.width / 2 + side * w * 0.05, y0 + h * 0.45 - img.height / 2
    elif anchor == "beside":
        x, y = (x1 + w * 0.05) if side > 0 else (x0 - w * 0.05 - img.width), y1 - img.height
    else:
        x, y = (x0 + x1) / 2 - img.width / 2, y0 - img.height * 1.15
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(img, (int(x), int(y)), img)
    return layer


def compose_panel(background, panel, assets, prop_images=None, extra_images=None, refine=None, glow=None):
    """background: 배경 그림. assets: {id: {"sprite", "rig", "child": True/False}}.
    prop_images: {소품 이름: RGBA}. extra_images: {조연 이름: {"sprite", "rig"}} (여러 번 나오는 조연).
    아이 그림 캐릭터에만 금색 테두리를 두르고, 조연·소품은 배경처럼 둔다.
    refine: refine(칸 그림, 붙인 것들의 자리 L, [아이 캐릭터 {"id", "layer": 붙인 층 RGBA}, ...])
    -> (칸 그림, 아이 캐릭터 모양 L 목록).
    금색 테두리를 두르기 전에 장면을 다듬는다 (테두리까지 다시 그리면 금색이 흐려진다). 아이 캐릭터를 장면 안에서
    다시 그리면 모양이 조금 바뀔 수 있으므로, 금색 테두리는 refine 이 돌려준 모양에 두른다."""
    page = background.convert("RGB")
    size = page.size
    placed = {}
    outlines = []
    child_layers = []
    pasted = Image.new("L", size, 0)               # 붙인 캐릭터·조연·소품 자리 (refine 이 안쪽 모양을 지키는 데 쓴다)

    entries = _entries(panel, assets, extra_images)
    posed_all = [pose(c["sprite"], c["rig"], c["pose"]) for c in entries]
    for c, posed in zip(entries, posed_all):
        c["foot"] = PLACES[c["place"]] - (0.08 if posed.info.get("float") and c["place"] == "ground" else 0)
    spots = _layout(size, entries, posed_all)
    for c, posed, spot in zip(entries, posed_all, spots):
        floating = c["place"] == "air" or posed.info.get("float")
        layer, points = _place_layer(size, posed, spot, flip=(c["facing"] == "left"))
        page = _shadow(page, layer, floating)
        layer = _scene_light(background.convert("RGB"), layer)
        page = Image.alpha_composite(page.convert("RGBA"), layer).convert("RGB")
        pasted = ImageChops.lighter(pasted, layer.getchannel("A"))
        placed[c["id"]] = (layer.getchannel("A").getbbox(), c["facing"], points)
        if c["child"]:
            outlines.append(layer.getchannel("A"))
            child_layers.append({"id": c["id"], "layer": layer})

    for pr in panel["props"]:
        if pr.get("painted") or not prop_images or pr["name"] not in prop_images or pr["owner"] not in placed:
            continue
        box, facing, points = placed[pr["owner"]]
        layer = _prop_layer(size, dict(pr, image=prop_images[pr["name"]]), box, facing, points)
        if pr["anchor"] == "beside":
            page = _shadow(page, layer, False)
        page = Image.alpha_composite(page.convert("RGBA"), _scene_light(background.convert("RGB"), layer)).convert("RGB")
        pasted = ImageChops.lighter(pasted, layer.getchannel("A"))

    if refine:
        page, outlines = refine(page, pasted, child_layers)
    if glow:                                        # glow: GLOW_LEVELS 의 값 (아이 캐릭터 발광)
        page = child_glow(page, outlines, **glow)
    for shape in outlines:                          # 금색 테두리는 마지막에 (소품에 가려지지 않게)
        page = _gold_outline(page, shape)
    return page


def _free_slots(panel):
    """여러 번 나오는 조연이 쓸 자리: 아이 캐릭터 자리에서 먼 빈 자리부터."""
    used = [SLOTS[c["slot"]] for c in panel["characters"]]
    return sorted((s for s in SLOTS if SLOTS[s] not in used),
                  key=lambda s: -min((abs(SLOTS[s] - u) for u in used), default=1))


def _entries(panel, assets, extra_images):
    """칸에 놓을 캐릭터 목록 (아이 캐릭터 + 여러 번 나오는 조연), 뒤(작은 것, 위쪽)부터 앞 순서.
    조연 자리는 _layout 이 아이 캐릭터를 놓고 남은 가장 넓은 빈 구간으로 정한다."""
    entries = [dict(c, child=assets[c["id"]].get("child", True), sprite=assets[c["id"]]["sprite"],
                    rig=assets[c["id"]]["rig"]) for c in panel["characters"]]
    for e in panel["extras"]:
        if e.get("recurring") and extra_images and e["name"] in extra_images:
            x = extra_images[e["name"]]
            entries.append({"id": e["name"], "extra": True, "size": "small", "place": "ground",
                            "pose": "stand", "facing": "left", "child": False, "sprite": x["sprite"], "rig": x["rig"]})

    # 뒤(작은 것, 위쪽)부터 앞으로 그린다
    entries.sort(key=lambda c: (PLACES[c["place"]], SIZES[c["size"]]))
    return entries


def reserved_mask(size, panel, assets, extra_images=None):
    """배경을 고르기 전에 쓰는 '캐릭터가 들어갈 자리' (L, 255 = 자리). 자세 전 모양으로 놓은 뒤 조금 넓힌다.
    배경 후보 중 이 자리에 눈에 띄는 물체가 없는 것을 고르는 데 쓴다."""
    m = np.zeros(size[::-1], np.uint8)
    # 아직 그리지 않은 여러 번 나오는 조연은 작은 네모로 자리만 잡는다 (배경을 조연보다 먼저 그리므로)
    extra_images = dict(extra_images or {})
    for e in panel["extras"]:
        if e.get("recurring") and e["name"] not in extra_images:
            extra_images[e["name"]] = {"sprite": Image.new("RGBA", (100, 100), (0, 0, 0, 255)), "rig": None}
    entries = _entries(panel, assets, extra_images)
    for c in entries:
        c["foot"] = PLACES[c["place"]]
    for c, spot in zip(entries, _layout(size, entries, [c["sprite"] for c in entries])):
        layer, _ = _place_layer(size, c["sprite"], spot, flip=(c["facing"] == "left"))
        m = np.maximum(m, np.array(layer.getchannel("A")))
    grown = ndimage.distance_transform_edt(m <= 128) <= size[1] * 0.02
    return Image.fromarray((grown * 255).astype(np.uint8))


PANEL_LAYOUTS = {
    1: [(0, 0, 1, 1)],
    2: [(0, 0, 1, 0.5), (0, 0.5, 1, 1)],
    3: [(0, 0, 1, 0.5), (0, 0.5, 0.5, 1), (0.5, 0.5, 1, 1)],
}


def panel_sizes(n_panels, page_size=(1024, 1024), border=8):
    """칸마다 배경을 따로 그릴 크기 (8의 배수)."""
    W, H = page_size
    out = []
    for x0, y0, x1, y1 in PANEL_LAYOUTS[n_panels]:
        w = int((x1 - x0) * W - border * 1.5) // 8 * 8
        h = int((y1 - y0) * H - border * 1.5) // 8 * 8
        out.append((w, h))
    return out


def assemble_page(panels, page_size=(1024, 1024), border=8):
    """칸 그림들을 흰 줄로 나눈 한 장으로 붙인다 (지금 앱의 single / two_panel / three_panel 레이아웃)."""
    W, H = page_size
    canvas = Image.new("RGB", page_size, "white")
    for img, (x0, y0, x1, y1) in zip(panels, PANEL_LAYOUTS[len(panels)]):
        if len(panels) == 1:
            canvas = img.resize(page_size, Image.LANCZOS)
            break
        bx, by = int(x0 * W + border * (0.5 if x0 else 1)), int(y0 * H + border * (0.5 if y0 else 1))
        canvas.paste(img, (bx, by))
    return canvas
