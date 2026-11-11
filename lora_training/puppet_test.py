"""puppet.py 시험: 캐릭터별 분석 결과와 자세표, SDXL 배경 위에 올린 페이지를 puppet_test/ 에 만든다.

    python puppet_test.py
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from puppet import analyze, cutout, debug_view, numbered_overlay, pose, pose_from_action, POSES

OUT = "puppet_test"
os.makedirs(OUT, exist_ok=True)
SDXL = "sdxl_chars/sdxl_chars"
K = "black"


def kid_drawings():
    """첫 시험 때의 아이 그림 예시: 막대 다리 소녀, 강아지, 보라 괴물."""
    girl = Image.new("RGB", (512, 512), "white"); d = ImageDraw.Draw(girl)
    for x in range(200, 320, 12):
        d.line((x, 90, x - 15, 190), fill=(240, 200, 30), width=8)
    d.ellipse((205, 100, 305, 200), fill=(255, 225, 200), outline=K, width=5)
    d.ellipse((230, 135, 242, 147), fill=K); d.ellipse((268, 135, 280, 147), fill=K)
    d.polygon([(255, 200), (175, 380), (335, 380)], fill=(220, 40, 40), outline=K, width=5)
    d.line((215, 260, 150, 300), fill=K, width=6); d.line((295, 260, 360, 300), fill=K, width=6)
    d.line((225, 380, 215, 460), fill=K, width=6); d.line((285, 380, 295, 460), fill=K, width=6)

    dog = Image.new("RGB", (512, 512), "white"); d = ImageDraw.Draw(dog)
    d.ellipse((140, 230, 380, 380), fill=(150, 95, 50), outline=K, width=5)
    d.ellipse((300, 150, 430, 270), fill=(150, 95, 50), outline=K, width=5)
    d.ellipse((290, 160, 330, 260), fill=(100, 60, 30), outline=K, width=4)
    d.ellipse((400, 160, 440, 260), fill=(100, 60, 30), outline=K, width=4)
    d.ellipse((340, 190, 352, 202), fill=K); d.ellipse((375, 190, 387, 202), fill=K)
    for x in (170, 220, 290, 340):
        d.line((x, 360, x, 440), fill=K, width=8)
    d.line((140, 290, 80, 230), fill=K, width=8)

    mon = Image.new("RGB", (512, 512), "white"); d = ImageDraw.Draw(mon)
    d.ellipse((110, 140, 400, 440), fill=(140, 70, 200), outline=K, width=6)
    d.polygon([(170, 170), (150, 70), (220, 150)], fill=(250, 250, 250), outline=K, width=5)
    d.polygon([(340, 170), (360, 70), (290, 150)], fill=(250, 250, 250), outline=K, width=5)
    d.ellipse((180, 220, 230, 270), fill="white", outline=K, width=4); d.ellipse((198, 238, 214, 254), fill=K)
    d.ellipse((280, 220, 330, 270), fill="white", outline=K, width=4); d.ellipse((296, 238, 312, 254), fill=K)
    d.rectangle((190, 320, 320, 360), fill=(90, 20, 40), outline=K, width=4)
    d.line((140, 420, 120, 470), fill=K, width=8); d.line((370, 420, 390, 470), fill=K, width=8)
    return {"girl": girl, "dog": dog, "monster": mon}


def thick_drawings():
    """팔·다리를 몸통과 이어서 두껍게 그린 아이 그림 예시. 칠한 모양을 합친 뒤 바깥 윤곽선을 한 번에 그린다."""
    def outlined(shapes, fill, size=512, width=7):
        m = Image.new("L", (size, size), 0)
        d = ImageDraw.Draw(m)
        for kind, xy in shapes:
            getattr(d, kind)(xy, fill=255)
        img = Image.new("RGB", (size, size), "white")
        img.paste(Image.new("RGB", (size, size), fill), (0, 0), m)
        edge = m.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(width))
        img.paste(Image.new("RGB", (size, size), "black"), (0, 0), edge)
        return img, ImageDraw.Draw(img)

    # 두꺼운 팔을 양옆으로 뻗은 초록 덩어리 친구 (다리 없음)
    blob, d = outlined([("ellipse", (160, 140, 350, 440)),
                        ("polygon", [(170, 250), (70, 200), (55, 235), (175, 310)]),
                        ("polygon", [(340, 250), (440, 190), (458, 222), (335, 310)])], (120, 200, 90))
    d.ellipse((215, 230, 235, 250), fill="black"); d.ellipse((275, 230, 295, 250), fill="black")
    d.arc((220, 270, 290, 320), 20, 160, fill="black", width=5)

    # 생강빵 사람: 머리·몸·팔·다리를 한 덩어리로
    ginger, d = outlined([("ellipse", (200, 50, 312, 160)), ("rounded_rectangle", (190, 150, 322, 330)),
                          ("rounded_rectangle", (95, 170, 205, 225)), ("rounded_rectangle", (307, 170, 417, 225)),
                          ("rounded_rectangle", (190, 310, 242, 470)), ("rounded_rectangle", (270, 310, 322, 470))],
                         (200, 130, 70))
    d.ellipse((230, 90, 244, 104), fill="white"); d.ellipse((268, 90, 282, 104), fill="white")
    for y in (200, 240, 280):
        d.ellipse((250, y, 262, y + 12), fill="white")

    # 다리가 두꺼운 곰 (팔은 짧게)
    bear, d = outlined([("ellipse", (170, 60, 340, 210)), ("ellipse", (165, 45, 215, 95)), ("ellipse", (295, 45, 345, 95)),
                        ("ellipse", (150, 180, 360, 400)), ("rounded_rectangle", (175, 360, 235, 480)),
                        ("rounded_rectangle", (275, 360, 335, 480)),
                        ("rounded_rectangle", (95, 220, 175, 270)), ("rounded_rectangle", (335, 220, 415, 270))],
                       (170, 120, 80))
    d.ellipse((215, 115, 231, 131), fill="black"); d.ellipse((279, 115, 295, 131), fill="black")
    d.ellipse((243, 145, 267, 162), fill="black")

    # 두 다리를 붙여 그린 아이 (바지처럼 한 덩어리, 아래만 V 로 갈라짐)
    pants, d = outlined([("ellipse", (195, 40, 315, 160)), ("rounded_rectangle", (185, 150, 325, 340)),
                         ("polygon", [(190, 330), (320, 330), (330, 480), (268, 480), (255, 395), (242, 480), (180, 480)]),
                         ("rounded_rectangle", (105, 170, 195, 215)), ("rounded_rectangle", (315, 170, 405, 215))],
                        (90, 140, 220))
    d.ellipse((230, 85, 244, 99), fill="black"); d.ellipse((266, 85, 280, 99), fill="black")

    # 발끝만 살짝 벌어진 붙은 다리 (얕은 홈)
    shorts, d = outlined([("ellipse", (170, 60, 340, 230)), ("ellipse", (165, 200, 345, 400)),
                          ("polygon", [(195, 370), (315, 370), (320, 475), (262, 475), (255, 445), (248, 475), (190, 475)]),
                          ("rounded_rectangle", (95, 250, 175, 290)), ("rounded_rectangle", (335, 250, 415, 290))],
                         (240, 170, 190))
    d.ellipse((220, 130, 236, 146), fill="black"); d.ellipse((274, 130, 290, 146), fill="black")
    return {"blob": blob, "ginger": ginger, "bear": bear, "pants": pants, "shorts": shorts}


def fit(img, size):
    img = img.copy(); img.thumbnail(size)
    bg = Image.new("RGB", size, "white")
    bg.paste(img, ((size[0] - img.width) // 2, (size[1] - img.height) // 2), img if img.mode == "RGBA" else None)
    return bg


# ── 1. 캐릭터별 분석 + 자세표 ──
sources = {k: Image.open(f"{SDXL}/sheet_{k}.png") for k in ("hero", "star", "villain")}
sources.update(kid_drawings())
sources.update(thick_drawings())
# 캐릭터 설명서(AI)가 알려줄 팔·다리 개수. 별·괴물처럼 팔이 없으면 0 -> 꼭짓점·뿔은 움직이지 않는다
LIMBS = {"hero": (2, 0), "star": (0, 0), "villain": (2, 0), "girl": (2, 2), "dog": (0, 4),
         "monster": (0, 2), "blob": (2, 0), "ginger": (2, 2), "bear": (2, 2), "pants": (2, 2), "shorts": (2, 2)}
sprites, rigs = {}, {}
CELL = (220, 240)
pose_names = list(POSES)
sheet = Image.new("RGB", (CELL[0] * (len(pose_names) + 1), (CELL[1] + 20) * len(sources)), "white")
draw = ImageDraw.Draw(sheet)
for r, (name, img) in enumerate(sources.items()):
    sprites[name] = cutout(img)
    arms, legs = LIMBS[name]
    rigs[name] = analyze(sprites[name], arms=arms, legs=legs)
    numbered_overlay(sprites[name], rigs[name]).save(f"{OUT}/overlay_{name}.png")
    print(f"{name}: 후보 {len(rigs[name].limbs)}개, 움직임 {[f'{l.id}:{l.kind}-{l.side}' for l in rigs[name].moving]}")
    y = r * (CELL[1] + 20)
    sheet.paste(fit(debug_view(sprites[name], rigs[name]), CELL), (0, y + 20))
    draw.text((4, y + 4), f"{name} (rig)", fill="black")
    for c, p in enumerate(pose_names, 1):
        sheet.paste(fit(pose(sprites[name], rigs[name], p), CELL), (CELL[0] * c, y + 20))
        draw.text((CELL[0] * c + 4, y + 4), p, fill="black")
sheet.save(f"{OUT}/pose_sheet.png")

# ── 2. SDXL 배경 위에 줄거리 행동대로 올리기 (그림자 + 배경 빛 + 금색 테두리) ──
GOLD = (240, 190, 50)


def gold_outline(page, shape):
    inside = shape.point(lambda v: 255 if v > 128 else 0)
    outside = np.array(ImageOps.invert(inside)) / 255
    glow = np.array(inside.filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.GaussianBlur(9)))
    glow = Image.fromarray((glow * 0.6 * outside).astype(np.uint8))
    ring = Image.fromarray((np.array(inside.filter(ImageFilter.MaxFilter(9))) * outside).astype(np.uint8))
    gold = Image.new("RGB", page.size, GOLD)
    page = Image.composite(gold, page, glow)
    return Image.composite(gold, page, ring.filter(ImageFilter.GaussianBlur(1)))


def place(page_size, sprite, box, flip):
    W, H = page_size
    s = ImageOps.mirror(sprite) if flip else sprite
    x0, y0, x1, y1 = box[0] * W, box[1] * H, box[2] * W, box[3] * H
    sc = min((x1 - x0) / s.width, (y1 - y0) / s.height)
    s = s.resize((max(int(s.width * sc), 1), max(int(s.height * sc), 1)), Image.LANCZOS)
    layer = Image.new("RGBA", page_size, (0, 0, 0, 0))
    layer.paste(s, (int((x0 + x1 - s.width) / 2), int(y1 - s.height)), s)
    return layer


def shadow(page, layer, floating):
    x0, y0, x1, y1 = layer.getchannel("A").getbbox()
    w = (x1 - x0) * (0.6 if floating else 1.1)
    cx = (x0 + x1) / 2
    cy = y1 + page.height * 0.08 if floating else y1 + w * 0.03
    m = Image.new("L", page.size, 0)
    ImageDraw.Draw(m).ellipse((cx - w / 2, cy - w * 0.1, cx + w / 2, cy + w * 0.1),
                              fill=int(255 * (0.25 if floating else 0.55)))
    return Image.composite(Image.new("RGB", page.size, (60, 40, 30)), page,
                           m.filter(ImageFilter.GaussianBlur(w * 0.06 + 2)))


def scene_light(bg, layer):
    alpha = layer.getchannel("A")
    rgb = np.array(layer.convert("RGB")).astype(np.float32)
    b = np.array(bg).astype(np.float32).reshape(-1, 3)
    lit = rgb * 0.85 + rgb * (b.mean(axis=0) / 255) * 0.15 * 1.6
    rim = np.array(alpha).astype(np.float32) - np.array(alpha.filter(ImageFilter.MinFilter(9))).astype(np.float32)
    r = np.array(Image.fromarray(np.clip(rim, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)))[..., None] / 255 * 0.35
    lit = lit * (1 - r) + np.percentile(b, 95, axis=0) * r
    out = Image.fromarray(np.clip(lit, 0, 255).astype(np.uint8)).convert("RGBA")
    out.putalpha(alpha)
    return out


# (배경, [(캐릭터, 줄거리 속 행동, 자리, 뒤집기)])
PAGES = [
    (f"{SDXL}/page1_0.png", [("hero", "walking into the magical forest", (0.08, 0.40, 0.36, 0.86), False),
                             ("star", "jumping happily over the path", (0.44, 0.06, 0.64, 0.36), False)]),
    (f"{SDXL}/page2_0.png", [("hero", "says hello and waves", (0.05, 0.42, 0.33, 0.86), False),
                             ("villain", "is surprised and scared", (0.58, 0.38, 0.92, 0.86), True)]),
    (f"{SDXL}/page3_0.png", [("hero", "dances with joy", (0.08, 0.42, 0.36, 0.86), False),
                             ("star", "shining softly", (0.42, 0.08, 0.60, 0.38), False),
                             ("villain", "feels sad and lonely", (0.62, 0.44, 0.94, 0.86), True)]),
]
pages = []
for bg_path, chars in PAGES:
    bg = Image.open(bg_path).convert("RGB")
    page = bg.copy()
    layers = []
    for k, action, box, flip in chars:
        p = pose_from_action(action)
        posed = pose(sprites[k], rigs[k], p)
        floating = posed.info["float"] or k == "star"
        if posed.info["float"]:                       # 뛰는 자세는 자리 위쪽으로 띄운다
            box = (box[0], box[1] - 0.10, box[2], box[3] - 0.10)
        layer = place(bg.size, posed, box, flip)
        page = shadow(page, layer, floating)
        layer = scene_light(bg, layer)
        page = Image.alpha_composite(page.convert("RGBA"), layer).convert("RGB")
        layers.append(layer)
        print(f"  {k}: '{action}' -> {p}")
    for layer in layers:
        page = gold_outline(page, layer.getchannel("A"))
    pages.append(page)

story = Image.new("RGB", (sum(p.width for p in pages), pages[0].height), "white")
x = 0
for p in pages:
    story.paste(p, (x, 0)); x += p.width
story.save(f"{OUT}/story_posed.png")
print(f"완료: {OUT}/pose_sheet.png, {OUT}/story_posed.png")
