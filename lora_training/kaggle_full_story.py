# %% [markdown]
# # 동화 3페이지 완성 시험: 장면 계획 → SDXL 배경·소품·조연 → 자세·조립
#
# 1. 아이 그림 → **캐릭터 완성** (SDXL scribble ControlNet + IP-Adapter), 모양은 이후 고정
# 2. **장면 계획** (언어 모델이 낼 JSON 을 이번에는 미리 적어 둠) → 칸마다 배경·자세·소품·조연
# 3. SDXL 로 **칸별 배경 먼저**(한 번만 나오는 조연·옆에 놓인 소품 포함). 1장만 그리고 캐릭터 자리가 막혔을 때만 다시 그림
# 4. **들고 쓰는 소품**, **여러 번 나오는 조연**: 그 칸의 배경을 그림체 참고 그림으로 보여 주며 그림 (배경에 녹아들게),
#    학습된 배경 제거 모델로 오려내고 검사 → 실패 시 다시 그리기
# 5. `puppet.py` 로 자세(고무처럼 휘기), `scene_plan.py` 로 조립 (그림자·배경 빛, 1컷/3컷)
#    → **아이 캐릭터 장면 안에서 다시 그리기 (그림체 입히기)**: 캐릭터 둘레만, 자세 그대로의 선(ControlNet) +
#      그 칸 배경의 그림체(IP-Adapter 그림체 층)로, 얼굴은 그리지 말라고 지시. **선 지키기**: 다시 그린 뒤 아이가 그린 선
#      (윤곽·막대 팔·눈·입)을 원래 그림에서 다시 덮음. 검사(몸 남음·얼굴 남음·새 얼굴 무늬)에 걸리면 버리고 붙인 그대로
#      **색 지키기**: 다시 그린 몸의 색조를 원래 색으로 (질감·명암은 둠)
#    → (장면에 녹이기는 기본 끔 - 빼도 차이가 거의 없었음)
#    → **발광** (후광·윤곽 빛 띠·몸 밝히기·주변 배경 살짝 어둡게) → 금색 테두리
# 6. 소요 시간 표. 아이 캐릭터는 기본 SDXL 20단계, 나머지는 빠른 SDXL(Hyper-SD 8단계)
# 7. **비교**: 같은 배경·캐릭터로 ① 새 기본값 (녹이기 끔, 색 지키기) ② 색 지키기 끔.
#    줄마다 걸린 시간을 `rows_timing.txt` 에. 비교 줄은 검사에 걸려도 버리지 않고 점수만 `live_scores.txt` 에 남긴다
#
# 준비물: GPU T4 x2, Internet On. (선택) `hero.png`, `star.png`, `villain.png` 를 Input 에 붙이면 실제 아이 그림을 쓴다.
# `puppet.py`, `scene_plan.py`, `story_pipeline.py` 는 아래 셀이 작업 폴더에 직접 써 넣는다.
# 파이프라인 본체는 `story_pipeline.py` 하나 - 그림 서버 노트북(kaggle_image_server)도 같은 파일을 쓴다.

# %%
# ① 설치 - 버전 고정 (2026-11-04 에 끝까지 성공한 조합)
# 항상 최신을 받으면 라이브러리가 바뀔 때마다 노트북이 깨진다 (enable_vae_tiling 삭제, torchao 충돌 등)
# peft: 빠른 SDXL(LoRA) 을 켜고 끄는 데 필요. onnxruntime: 배경 제거 모델 실행 (rembg 패키지는 numpy 를 올려서 안 씀)
!pip install -q diffusers==0.42.1 transformers==5.22.1 accelerate peft onnxruntime
# Kaggle 의 오래된 torchao 는 최신 라이브러리와 충돌한다 (없으면 아무 일도 안 함)
!pip uninstall -y -q torchao

# torch·numpy·scipy·pillow 는 Kaggle 기본 환경 것을 쓴다 (다시 받으면 수 GB). 성공했던 버전과 다르면 알려 준다.
import importlib.metadata as md
TESTED = {"diffusers": "0.42.1", "transformers": "5.22.1", "torch": "2.11.0",
          "numpy": "2.1.3", "scipy": "1.16.3", "pillow": "13.0.0"}
for name, want in TESTED.items():
    have = md.version(name)
    print(f"{'  ' if have.startswith(want) else '⚠️'} {name} {have}" + ("" if have.startswith(want) else f" (시험한 버전 {want})"))
print("   (아직 고정 전)", ", ".join(f"{n} {md.version(n)}" for n in ("accelerate", "peft", "onnxruntime", "scikit-image")))

# %% [writefile puppet.py]

# %% [writefile scene_plan.py]

# %% [writefile story_pipeline.py]

# %%
# ② 시험 설정: 아이 그림 3개 + 장면 계획 (언어 모델이 낼 JSON 을 미리 적어 둠)
import glob, os, sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, "/kaggle/working")
from story_pipeline import StoryPipeline

OUT = "/kaggle/working/full_story"
COMPARE = False    # True: 아이 캐릭터를 기본 30단계로도 그려 20단계와 나란히 비교 (시간이 더 든다)
# 비교할 설정: (이름, 색 지키기). 모두 그림체 + 선 지키기 + 발광, 녹이기 끔, 기본 SDXL 다시 그리기.
# 2026-11-08 시간 비교: 녹이기 빼도 차이 거의 없음(-33초) -> 기본 끔. 빠른 다시 그리기는 품질 떨어짐 -> 안 씀.
# 주황 악당이 다시 그리며 노랑으로 바뀜 -> 색 지키기 추가. 비교 줄은 검사 기준에 걸려도 버리지 않고 점수만 남긴다.
ROWS = [("default (no blend, color kept)", True),
        ("color keep off", False)]

# 아이가 그린 캐릭터: 설명은 지금 앱의 GPT 설명서를 짧게 줄인 것, 팔·다리 개수는 AI 판단(LIMB_QUESTION)을 대신 적은 것
ASSETS = {
    "hero": {"desc": "a round white ghost-like little character with dot eyes and a brown hair curl", "arms": 2, "legs": 0},
    "star": {"desc": "a yellow five-pointed star character with small T-shaped eyes", "arms": 0, "legs": 0},
    "villain": {"desc": "an orange cat-like creature with pointy ears and T-shaped eyes", "arms": 2, "legs": 0},
}

# 언어 모델이 낼 장면 계획 (기존 서버 local_image_engine.py 의 지시문에 대한 답을 대신 적어 둠)
RAW_PLAN = {"pages": [
    {"page": 1, "panels": [{
        "background": "a winding forest path between big friendly trees, bluebell flowers and mushrooms",
        "characters": [{"id": "hero", "slot": "left", "size": "large", "place": "ground", "pose": "walk", "facing": "right"},
                       {"id": "star", "slot": "center-right", "size": "small", "place": "air", "pose": "stand", "facing": "left"}],
        "props": [], "extras": [{"name": "a small blue bird on a branch", "recurring": False},
                                {"name": "a little brown puppy", "recurring": True}]}]},
    {"page": 2, "panels": [{
        "background": "a small sandy cove with gentle waves and seashells",
        "characters": [{"id": "hero", "slot": "left", "size": "medium", "place": "ground", "pose": "wave", "facing": "right"},
                       {"id": "villain", "slot": "right", "size": "large", "place": "ground", "pose": "cheer", "facing": "left"}],
        "props": [{"name": "a big cooking pot", "anchor": "on_head", "owner": "villain"}], "extras": []}]},
    {"page": 3, "panels": [
        {"background": "a deep green forest path with fireflies and a sparkling light trail",
         "characters": [{"id": "villain", "slot": "center", "size": "large", "place": "air", "pose": "jump", "facing": "right"}],
         "props": [], "extras": []},
        {"background": "a mossy forest floor with a tiny sprouting seed",
         "characters": [{"id": "hero", "slot": "center-left", "size": "large", "place": "ground", "pose": "sad", "facing": "right"},
                        {"id": "star", "slot": "right", "size": "small", "place": "air", "pose": "stand", "facing": "left"}],
         "props": [], "extras": [{"name": "a little brown puppy", "recurring": True}]},
        {"background": "a sunny forest clearing with a single white flower",
         "characters": [{"id": "villain", "slot": "center", "size": "large", "place": "ground", "pose": "stand", "facing": "left"}],
         "props": [{"name": "a big cooking pot", "anchor": "in_hand", "owner": "villain"}], "extras": []},
    ]},
]}

# %%
# ③ 아이 그림 (Input 에 hero.png 등이 없으면 예시: 하얀 주인공, 노란 별, 주황 악당)
BROWN = (110, 70, 40)


def demo_drawing(asset_id):
    img = Image.new("RGB", (512, 512), "white")
    d = ImageDraw.Draw(img)
    if asset_id == "hero":
        d.rounded_rectangle((185, 200, 325, 440), radius=60, fill="white", outline=BROWN, width=7)
        d.ellipse((170, 90, 340, 260), fill="white", outline=BROWN, width=7)
        d.arc((150, 70, 360, 150), 190, 350, fill=BROWN, width=8)
        d.line((228, 160, 228, 195), fill=BROWN, width=9); d.line((282, 160, 282, 195), fill=BROWN, width=9)
        d.line((185, 300, 140, 360), fill=BROWN, width=7); d.line((325, 300, 370, 360), fill=BROWN, width=7)
    elif asset_id == "star":
        cx, cy, R, r = 256, 270, 210, 85
        pts = [(cx + (R if i % 2 == 0 else r) * np.cos(np.pi / 2 + i * np.pi / 5),
                cy - (R if i % 2 == 0 else r) * np.sin(np.pi / 2 + i * np.pi / 5)) for i in range(10)]
        d.polygon(pts, fill=(255, 225, 90), outline=(200, 150, 20), width=8)
        for x in (220, 290):
            d.line((x - 20, 240, x + 20, 240), fill=BROWN, width=8); d.line((x, 240, x, 275), fill=BROWN, width=8)
    else:
        o = (240, 140, 50)
        d.polygon([(170, 200), (180, 70), (240, 160)], fill=o, outline=BROWN)
        d.polygon([(340, 200), (330, 70), (270, 160)], fill=o, outline=BROWN)
        d.ellipse((150, 130, 360, 460), fill=o, outline=BROWN, width=7)
        d.line((150, 280, 90, 220), fill=BROWN, width=8); d.line((360, 280, 420, 220), fill=BROWN, width=8)
        for x in (215, 295):
            d.line((x - 22, 220, x + 22, 220), fill=BROWN, width=9); d.line((x, 220, x, 258), fill=BROWN, width=9)
    return img


def load_drawing(asset_id):
    found = sorted(glob.glob(f"/kaggle/input/**/{asset_id}.png", recursive=True))
    if found:
        img = Image.open(found[0]).convert("RGBA")
        return Image.alpha_composite(Image.new("RGBA", img.size, "white"), img).convert("RGB").resize((512, 512))
    return demo_drawing(asset_id)


drawings = {k: load_drawing(k) for k in ASSETS}

# %%
# ④ 모델 불러오기 → 캐릭터 완성 → 배경 → 조연·소품 → 조립
pipe = StoryPipeline(save_dir=OUT).load()
assets = pipe.make_characters({k: dict(info, image=drawings[k]) for k, info in ASSETS.items()}, compare=COMPARE)
pictures = pipe.make_book(RAW_PLAN, assets)       # 기본값(그림체 0.75 + 선 0.7 + 선·색 지키기, 녹이기 끔, 발광, 검사 적용)으로 1권 - 시간 표는 이것 기준

story = Image.new("RGB", (1024 * len(pictures) + 16 * (len(pictures) - 1), 1024), "white")
for i, p in enumerate(pictures):
    story.paste(p, (i * 1040, 0))
story.save(f"{OUT}/story.png")
story.resize((story.width // 3, story.height // 3))

# %%
# ⑤ 소요 시간 표
report = pipe.timing_report(len(ASSETS), RAW_PLAN["pages"])
print(report)
with open(f"{OUT}/timing.txt", "w", encoding="utf-8") as f:
    f.write(report)

# %%
# ⑥ 비교: ④에서 그린 배경·조연·소품을 그대로 두고 설정만 바꿔 다시 조립한다
pages, backgrounds, assets, props, extras = pipe.last_book
rows = []
main_log = list(pipe.live_log)        # ④ 기본 설정(검사 적용) 기록
pipe.live_enforce = False
import time
row_times = []
for r, (label, color_keep) in enumerate(ROWS):
    pipe.color_keep = color_keep
    print(f"── {r + 1}. {label}", flush=True)
    pipe.live_log = []
    t0 = time.perf_counter()
    rows.append(pipe.compose_pages(pages, backgrounds, assets, props, extras, tag=f"_row{r + 1}"))
    row_times.append((label, time.perf_counter() - t0))
    for rec in pipe.live_log:
        rec["row"] = r + 1
    main_log += pipe.live_log
pipe.color_keep, pipe.live_enforce = True, True
with open(f"{OUT}/rows_timing.txt", "w", encoding="utf-8") as f:
    f.write("칸 조립 전체 (5칸, 다시 그리기·발광 포함) - 배경·캐릭터·소품 시간은 줄마다 같다" + chr(10))
    for label, sec in row_times:
        f.write(f"{label}: {sec:.0f}초" + chr(10))
print(open(f"{OUT}/rows_timing.txt", encoding="utf-8").read())
with open(f"{OUT}/live_scores.txt", "w", encoding="utf-8") as f:
    f.write("row | name | mode | body | face | new | ok" + chr(10))
    for rec in main_log:
        f.write(f"{rec.get('row', 'main')} | {rec['name']} | {rec['mode']} | {rec['body']:.2f} | "
                f"{rec['face']:.2f} | {rec['new']:.3f} | {rec['ok']}" + chr(10))
W = 512
sheet = Image.new("RGB", (W * len(pages) + 8 * (len(pages) - 1), (W + 28) * len(ROWS)), "white")
for r, ((label, *_), pics) in enumerate(zip(ROWS, rows)):
    for c, pic in enumerate(pics):
        sheet.paste(pic.resize((W, W)), (c * (W + 8), r * (W + 28) + 28))
    ImageDraw.Draw(sheet).text((6, r * (W + 28) + 8), f"{r + 1}. {label}", fill="black")
sheet.save(f"{OUT}/live_compare.png")
sheet.resize((sheet.width // 2, sheet.height // 2))

# %%
# ⑦ 결과 내려받기
from IPython.display import FileLink

os.chdir("/kaggle/working")
!zip -qr full_story.zip full_story
FileLink("full_story.zip")

# %% [markdown]
# ## 확인할 것
# - `story.png`: 3페이지(마지막은 3컷) 완성본. 아이 캐릭터 색·선이 또렷한지, 조연·소품 그림체가 배경에 녹아드는지,
#   냄비가 머리 위·손에 붙는지, 배경 물체가 캐릭터와 겹치지 않는지, 배경에 함께 그릴 조연(파랑새)이 있는지
# - `scribble_*.png`: 아이 그림 조건 - 굵은 선이 속 빈 두 줄이 아니라 한 줄인지
# - `sheet_*.png` / `limbs_*.png`: 캐릭터 완성 결과와 팔·다리 후보 번호
# - `prop_*.png` / `extra_*.png`: 소품·조연 원본. 다시 그렸다면 `try_*.png` 에 걸린 그림이 남고 로그에 풍경 섞임 값이 나온다
# - `cands_*.png`: 그린 배경과 캐릭터 자리(빨간 선), 막힌 정도 (대부분 1장이어야 정상, 0.25 넘으면 다시 그림)
# - `live_compare.png`: 줄마다 ① 새 기본값 (색 지키기) ② 색 지키기 끔. 악당이 주황 그대로인지, 질감은 남는지.
#   원본 크기는 `page*_row*.png`
# - `timing.txt`: 1권 시간 (지난번 6.4분, 녹이기 끔 -33초 예상), 소품·조연 그림 시간 (그림체 참고 0.5 시작으로 다시 그리기가 줄었는지)
# - `live_scores.txt`: 캐릭터·줄마다 검사 점수 (body 몸 남음, face 얼굴 표시 남음, new 새 얼굴 무늬) 와 기준 통과 여부.
#   좋아 보이는데 False 인 것 / 이상한데 True 인 것을 보고 기준(LIVE_CHECK)을 맞춘다.
# - `live_*.png`: 캐릭터마다 다시 그리기 전 | 선(조건) | 후 | 선 덮은 뒤, 검사 값과 OK / FAIL.
# - `timing.txt` 의 '아이 캐릭터 장면 안에서 다시 그리기 (1번)', '장면에 녹이기 (칸 1개)' 시간
# - `compare_sheet_*.png`: 아이 캐릭터 왼쪽 기본 20단계 | 오른쪽 기본 30단계
# - `timing.txt`: 단계별 시간, 동화 1권 예상 시간, GPU 메모리
# - 끝나면 세션 끄기(⏻)
