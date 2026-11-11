"""scene_plan.py 시험: 언어 모델이 낸 것처럼 꾸민 장면 계획으로 3페이지(마지막은 3컷)를 조립한다.

배경은 지난 SDXL 결과를, 소품(냄비)은 임시로 그린 그림을, 여러 번 나오는 조연(강아지)은 예시 강아지 그림을 쓴다.
실제로는 배경·소품·조연 그림을 SDXL 이 만든다 (다음 Kaggle 시험).

    python scene_test.py
"""
import os

from PIL import Image, ImageDraw

from puppet import cutout, find_parts, choose_limbs
from scene_plan import (assemble_page, background_prompt, compose_panel,
                        normalize_plan, panel_sizes)

OUT = "scene_test"
os.makedirs(OUT, exist_ok=True)
SDXL = "sdxl_chars/sdxl_chars"

# 아이 그림 캐릭터 (팔·다리 개수는 실제로는 AI 판단)
assets = {}
for k, limbs in {"hero": (2, 0), "star": (0, 0), "villain": (2, 0)}.items():
    sprite = cutout(Image.open(f"{SDXL}/sheet_{k}.png"))
    assets[k] = {"sprite": sprite, "rig": choose_limbs(find_parts(sprite), *limbs), "child": True}

# 여러 번 나오는 조연 (AI 가 그린 것으로 가정)
dog = Image.new("RGB", (512, 512), "white")
d = ImageDraw.Draw(dog)
d.ellipse((140, 230, 380, 380), fill=(150, 95, 50), outline="black", width=5)
d.ellipse((300, 150, 430, 270), fill=(150, 95, 50), outline="black", width=5)
d.ellipse((290, 160, 330, 260), fill=(100, 60, 30), outline="black", width=4)
d.ellipse((400, 160, 440, 260), fill=(100, 60, 30), outline="black", width=4)
d.ellipse((340, 190, 352, 202), fill="black"); d.ellipse((375, 190, 387, 202), fill="black")
for x in (170, 220, 290, 340):
    d.line((x, 360, x, 440), fill="black", width=8)
puppy = cutout(dog)
extras = {"a little brown puppy": {"sprite": puppy, "rig": choose_limbs(find_parts(puppy), 0, 4)}}

# 소품 (임시 그림: 손잡이 달린 회색 냄비)
pot = Image.new("RGBA", (300, 220), (0, 0, 0, 0))
d = ImageDraw.Draw(pot)
d.rounded_rectangle((40, 60, 260, 200), radius=30, fill=(150, 155, 165), outline=(70, 70, 80), width=8)
d.rectangle((25, 45, 275, 75), fill=(170, 175, 185), outline=(70, 70, 80), width=8)
d.rounded_rectangle((5, 90, 45, 120), radius=10, fill=(90, 90, 100))
d.rounded_rectangle((255, 90, 295, 120), radius=10, fill=(90, 90, 100))
props = {"a big cooking pot": pot}

# 언어 모델이 낼 법한 계획 (일부러 틀린 값도 섞어 normalize_plan 이 고치는지 본다)
raw_plan = {"pages": [
    {"page": 1, "panels": [{
        "background": "a winding forest path between big friendly trees, bluebells",
        "characters": [{"id": "hero", "slot": "left", "size": "large", "place": "ground", "pose": "walk", "facing": "right"},
                       {"id": "star", "slot": "center-right", "size": "small", "place": "air", "pose": "stand", "facing": "left"}],
        "props": [], "extras": [{"name": "a small blue bird on a branch", "recurring": False},
                                {"name": "a little brown puppy", "recurring": True}]}]},
    {"page": 2, "panels": [{
        "background": "a sandy cove with gentle waves",
        "characters": [{"id": "hero", "slot": "left", "size": "medium", "place": "ground", "pose": "wave", "facing": "right"},
                       {"id": "villain", "slot": "right", "size": "large", "place": "ground", "pose": "cheer", "facing": "left"},
                       {"id": "dragon", "slot": "center"}],                        # 없는 캐릭터 -> 버림
        "props": [{"name": "a big cooking pot", "anchor": "on_head", "owner": "villain"}], "extras": []}]},
    {"page": 3, "panels": [
        {"background": "a cozy bedroom with a round window",
         "characters": [{"id": "villain", "slot": "center", "size": "large", "place": "air", "pose": "jump", "facing": "right"}],
         "props": [], "extras": []},
        {"background": "a mossy forest floor",
         "characters": [{"id": "hero", "slot": "center-left", "size": "large", "place": "ground", "pose": "sad", "facing": "right"},
                        {"id": "star", "slot": "right", "size": "small", "place": "air", "pose": "dance", "facing": "left"}],   # 없는 자세 -> stand
         "props": [], "extras": [{"name": "a little brown puppy", "recurring": True}]},
        {"background": "a forest clearing with a white flower",
         "characters": [{"id": "villain", "slot": "center", "size": "large", "place": "ground", "pose": "stand", "facing": "left"}],
         "props": [{"name": "a big cooking pot", "anchor": "in_hand", "owner": "villain"}], "extras": []},
    ]},
]}

pages = normalize_plan(raw_plan, list(assets))
bg_files = [f"{SDXL}/page1_0.png", f"{SDXL}/page2_0.png", f"{SDXL}/page3_0.png"]
for n, page in enumerate(pages):
    sizes = panel_sizes(len(page["panels"]))
    panels = []
    for i, (panel, size) in enumerate(zip(page["panels"], sizes)):
        print(f"{page['page']}페이지 {i + 1}칸 배경 프롬프트: {background_prompt(panel)}")
        bg = Image.open(bg_files[(n + i) % 3]).convert("RGB").resize(size, Image.LANCZOS)   # 임시 배경
        panels.append(compose_panel(bg, panel, assets, props, extras))
    assemble_page(panels).save(f"{OUT}/page{page['page']}.png")

row = Image.new("RGB", (1024 * len(pages) + 16 * (len(pages) - 1), 1024), "white")
for n in range(len(pages)):
    row.paste(Image.open(f"{OUT}/page{n + 1}.png"), (n * 1040, 0))
row.save(f"{OUT}/story.png")
print(f"완료: {OUT}/story.png")
