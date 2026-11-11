"""동화 그림 파이프라인 (API 없이 우리 모델로). Kaggle 시험 노트북(kaggle_full_story)과 그림 서버(kaggle_image_server)가 같이 쓴다.

    pipe = StoryPipeline().load()
    assets = pipe.make_characters({"hero": {"image": 아이그림(PIL), "desc": "영어 짧은 설명", "arms": 2, "legs": 0}})
    pictures = pipe.make_book(plan, assets)      # plan: scene_plan 형식 {"pages": [...]} -> 페이지 그림 목록

1. 아이 그림 -> 캐릭터 완성 (기본 SDXL 20단계 + scribble ControlNet + IP-Adapter), 오려내기·검사, 팔다리 후보
2. 칸마다 배경 먼저 (빠른 SDXL 8단계 1장, 캐릭터 자리가 막혔을 때만 다시 그림)
3. 들고 쓰는 소품·여러 번 나오는 조연: 처음 나오는 칸의 배경을 그림체 참고 그림으로 보여 주며 그림
4. 자세·그림자로 조립 -> 장면에 녹이기 (칸 전체를 약하게 다시 그림, 붙인 것 안쪽 모양은 유지) -> 금색 테두리 (puppet.py, scene_plan.py)
"""
import gc
import hashlib
import os
import time
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager

# GPU 메모리 조각화 방지 (torch 가 GPU 를 쓰기 전에 정해야 함)
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

import numpy as np
import torch
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter
from scipy import ndimage

from puppet import (ISNET_MIRROR, ISNET_SHA256, ISNET_URL, Matte, child_face, background_clutter, choose_limbs, cutout, cutout_problems, find_parts,
                    child_regions, keep_unpainted, numbered_overlay, outline_color, to_scribble)
from scene_plan import GLOW, assemble_page, background_prompt, compose_panel, normalize_plan, panel_sizes, reserved_mask

GOOD_STYLE = ("cozy storybook illustration, close view, warm golden afternoon light, soft glow, "
              "gentle pastel colors, gouache painting, clean simple shapes, whimsical, children's picture book")
# 따로 그리는 조연·소품은 배경과 같은 그림체 (장소·구도 말만 뺌). 아이 캐릭터만 아이 그림 모양을 따른다.
ASSET_STYLE = ("storybook illustration, warm soft light, gentle pastel colors, gouache painting, "
               "clean simple shapes, whimsical, children's picture book")
# 중요한 것부터 (StoryPipeline.negative 가 단계별 말을 앞에 붙이고 77토큰을 넘는 뒤쪽을 뺀다)
NEGATIVE = ("photo, realistic, 3d render, text, letters, watermark, signature, blurry, deformed, ugly, dark, scary, creepy, "
            "messy, muddy, oversaturated, neon colors, harsh contrast, cluttered, busy, too many details, "
            "wide landscape, panorama, horizon, dense foliage, pattern, wallpaper, tiled, caption, banner, title, logo")
NO_CHARACTERS = "people, person, human, child, animal, creature, character, face"
# 프롬프트에는 "무엇을 그릴지"만 쓴다. sticker·card·badge 같은 '포장' 말은 칼선 흰 테두리·바탕 카드까지 그리게 만든다.
CHARACTER_LOOK = "simple cute cartoon character, clean bold outline, flat soft colors, full body"
ALONE = "the whole thing fully visible, alone on a plain white background"
# 장면에 녹이기 지시문: 붙인 캐릭터가 그 장소의 빛·그림자 안에 있게
SCENE_TOUCH = "cute characters naturally part of the scene, soft shadows on the ground, warm light wrapping around them"
# 아이 캐릭터를 장면 안에서 다시 그릴 때: 모양은 선(ControlNet)이, 생김새는 완성 그림(IP-Adapter)이 지키고 글은 빛·질감만
LIVE_LOOK = ("storybook character standing in the scene, soft shading, warm light and gentle shadow, "
             "gouache texture, same character, children's picture book")
LIVE_IP = 0.6       # 완성 캐릭터 그림을 따르는 세기 (캐릭터 완성 때 0.5 보다 조금 세게 - 장면 색에 끌려가지 않게)
LIVE_SIZE = 768     # 캐릭터 둘레를 잘라 이 크기로 그린다
LIVE_STYLE_IP = 0.8     # 그림체 입히기: 그 칸 배경을 그림체 층에 보여 주는 세기
STYLE_REF_START = 0.5   # 조연·소품을 그릴 때 배경 그림체 참고 첫 세기 (걸리면 반으로, 마지막엔 0)
# 장면 안 다시 그리기 검사 기준 {점수: (최소, 최대)} - _live_scores 참고. 2026-11-08 처음 정한 값이라 비교 결과로 다시 맞춘다.
# (가짜 시험: 질감·음영·붓 자국은 통과, 몸이 배경으로 지워짐·얼굴 지움·새 만화 눈은 걸림)
LIVE_CHECK = {"body": (0.75, 9), "face": (0.6, 9), "new": (0, 0.3)}
# 그림체 입히기 때 얼굴을 새로 그리지 않게 (아이가 그린 얼굴은 선 지키기로 다시 덮는다)
LIVE_NO_FACE = "eyes, big eyes, mouth, smile, teeth, blush, rosy cheeks, nose, facial features"
BLOCKED = 0.25      # 캐릭터 자리의 이만큼 이상을 눈에 띄는 물체가 막으면 배경을 다시 그린다 (지난 시험 후보 대부분 0.05 이하)


def warm_grade(img, glow=True):
    """배경과 같은 따뜻한 색 보정. glow: 밝은 곳 번짐 - 오려 붙이는 그림에는 끈다 (가장자리에 밝은 띠가 생기므로)."""
    img = ImageEnhance.Color(img.convert("RGB")).enhance(0.9)
    a = np.array(img).astype(np.float32) * np.array([1.08, 1.02, 0.84])
    a = a * 0.96 + 255 * 0.04 * np.array([1.0, 0.85, 0.6])
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if not glow:
        return img
    bright = img.point(lambda v: max(v - 170, 0) * 3).filter(ImageFilter.GaussianBlur(18))
    b, g = np.array(img).astype(np.float32), np.array(bright).astype(np.float32)
    return Image.fromarray(np.clip(255 - (255 - b) * (255 - g * 0.35) / 255, 0, 255).astype(np.uint8))


def graded(sprite):
    """오려낸 조연·소품에 배경과 같은 색 보정 (번짐 없이)."""
    out = warm_grade(sprite, glow=False).convert("RGBA")
    out.putalpha(sprite.getchannel("A"))
    return out


def gen_size(size, area=1024 * 1024):
    """칸 비율 그대로, SDXL 이 잘 그리는 넓이(약 100만 픽셀)로 키운 생성 크기 (64의 배수)."""
    w, h = size
    k = (area / (w * h)) ** 0.5
    return int(w * k) // 64 * 64, int(h * k) // 64 * 64


def style_only(strength):
    """IP-Adapter 를 '그림체 층'에만 건다 (InstantStyle): 참고 그림의 색·붓질만 가져오고 나무·길 같은 내용은 가져오지 않는다."""
    return {"up": {"block_0": [0.0, strength, 0.0]}}


def candidate_strip(images, blocked, reserved):
    """확인용: 그린 배경마다 캐릭터 자리(빨간 선)와 그 자리가 막힌 정도를 적은 줄 그림."""
    w = 384
    h = int(w * images[0].height / images[0].width)
    edge = reserved.resize((w, h)).filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 0 else 0)
    strip = Image.new("RGB", (w * len(images), h + 22), "white")
    for i, (img, busy) in enumerate(zip(images, blocked)):
        strip.paste(Image.composite(Image.new("RGB", (w, h), "red"), img.resize((w, h)), edge), (i * w, 0))
        ImageDraw.Draw(strip).text((i * w + 4, h + 4), f"blocked {busy:.2f}", fill="black")
    return strip


class StoryPipeline:
    def __init__(self, workdir="/kaggle/working", fast=True, character_steps=20, bg_tries=2, retries=2, seed=31,
                 save_dir=None, blend=0.0, inner_mix=0.3, live=0.6,
                 style=True, style_live=0.75, style_cn=0.7, line_keep=True, color_keep=True, live_fast=False,
                 live_enforce=True):
        """fast: 배경·조연·소품을 빠른 SDXL(Hyper-SD 8단계)로. 아이 캐릭터는 항상 기본 SDXL character_steps 단계
        (빠른 SDXL 은 ControlNet·IP-Adapter 와 함께 쓰면 색이 빠지고 선이 흐려진다).
        bg_tries: 배경은 1장 그리고, 캐릭터 자리가 막혔을 때만 다시 그려 최대 이 수만큼. retries: 검사에 걸렸을 때 다시 그리는 횟수.
        blend: 조립한 칸을 다시 그리는 세기 (0 = 장면에 녹이기 안 함 - 2026-11-08 비교에서 빼도 그림 차이가 거의 없어 기본 0, -33초). inner_mix: 붙인 것 안쪽에 다시 그린 그림을 섞는 비율
        (나머지는 원래 모양 그대로). save_dir: 중간 그림 저장 폴더 (확인용).
        live: 아이 캐릭터를 장면 안에서 다시 그리는 세기 (0 = 안 함, 붙인 그대로).
        style: 배경 그림체를 캐릭터에 입힌다 (세기 style_live, 선 따르기 style_cn). line_keep: 다시 그린 뒤 아이가 그린 선
        (윤곽·팔·눈·입)을 원래 그림에서 다시 덮는다. color_keep: 다시 그린 몸의 색조를 원래 색으로 되돌린다 (질감·명암은 둠).
        live_fast: 장면 안 다시 그리기도 빠른 SDXL(8단계)로.
        live_enforce: 검사(LIVE_CHECK)에 걸리면 버린다 (False = 점수만 기록)."""
        self.workdir, self.fast, self.character_steps = workdir, fast, character_steps
        self.bg_tries, self.retries, self.seed, self.save_dir = bg_tries, retries, seed, save_dir
        self.blend, self.inner_mix, self.live = blend, inner_mix, live
        self.style, self.style_live, self.style_cn = style, style_live, style_cn
        self.line_keep, self.color_keep = line_keep, color_keep
        self.live_fast, self.live_enforce = live_fast, live_enforce
        self.cpu = ThreadPoolExecutor(max_workers=1)   # 배경 제거 모델(CPU)을 GPU 작업과 겹쳐 돌린다
        self.glow = GLOW            # 아이 캐릭터 발광 (scene_plan.child_glow). None 이면 끔
        self.live_log = []          # 장면 안 다시 그리기 검사 점수 기록 (기준을 정할 때 본다)
        self.times = defaultdict(list)
        self.device, self.fp16 = "cuda", torch.float16
        self._characters = {}       # 같은 그림·설명이면 다시 그리지 않는다 (실패 페이지 다시 그리기에서도 같은 모습 유지)
        if save_dir:
            os.makedirs(save_dir, exist_ok=True)

    # ── 준비 ──────────────────────────────────────────────────────
    @contextmanager
    def timed(self, label):
        torch.cuda.synchronize()
        t = time.perf_counter()
        yield
        torch.cuda.synchronize()
        self.times[label].append(time.perf_counter() - t)

    def _save(self, img, name):
        if self.save_dir:
            img.save(os.path.join(self.save_dir, name))

    def load(self):
        from diffusers import (AutoencoderKL, ControlNetModel, DDIMScheduler, DPMSolverMultistepScheduler,
                               StableDiffusionXLControlNetInpaintPipeline, StableDiffusionXLControlNetPipeline,
                               StableDiffusionXLImg2ImgPipeline, StableDiffusionXLPipeline)

        with self.timed("모델 불러오기 (처음 1번)"):
            vae = AutoencoderKL.from_pretrained("madebyollin/sdxl-vae-fp16-fix", torch_dtype=self.fp16)
            self.sdxl = StableDiffusionXLPipeline.from_pretrained(
                "stabilityai/stable-diffusion-xl-base-1.0", vae=vae, torch_dtype=self.fp16, variant="fp16",
                use_safetensors=True).to(self.device)
            self.base_sched = DPMSolverMultistepScheduler.from_config(self.sdxl.scheduler.config, use_karras_sigmas=True)
            self.fast_sched = DDIMScheduler.from_config(self.sdxl.scheduler.config, timestep_spacing="trailing")  # Hyper-SD 권장
            self.sdxl.load_ip_adapter("h94/IP-Adapter", subfolder="sdxl_models",
                                      weight_name="ip-adapter-plus_sdxl_vit-h.safetensors",
                                      image_encoder_folder="models/image_encoder")
            # 빠른 SDXL: 기본 모델에 8단계용 LoRA 를 얹는다 (CFG 버전 = negative prompt 를 그대로 쓸 수 있음). 켜고 끌 수 있다.
            self.sdxl.load_lora_weights("ByteDance/Hyper-SD", weight_name="Hyper-SDXL-8steps-CFG-lora.safetensors",
                                        adapter_name="hyper")
            # ControlNet 은 아이 캐릭터를 그릴 때만 GPU 에 올린다 (장면 안에서 다시 그리기(live)를 끄면 다 그린 뒤 CPU 로 내림)
            self.controlnet = ControlNetModel.from_pretrained("xinsir/controlnet-scribble-sdxl-1.0", torch_dtype=self.fp16)
            self.sheet_pipe = StableDiffusionXLControlNetPipeline(**self.sdxl.components, controlnet=self.controlnet)
            # 장면에 녹이기: 조립한 칸을 약하게 다시 그린다 (같은 모델을 나눠 쓰므로 메모리가 더 들지 않는다)
            self.refine_pipe = StableDiffusionXLImg2ImgPipeline(**self.sdxl.components)
            # 아이 캐릭터를 장면 안에서 다시 그리기: 붙인 캐릭터 자리만, 자세 그대로의 선(scribble)과 캐릭터 그림(IP-Adapter)을 보며
            self.live_pipe = StableDiffusionXLControlNetInpaintPipeline(**self.sdxl.components, controlnet=self.controlnet)
            # 학습된 배경 제거 모델 (CPU). 오려내기, 배경에서 캐릭터 자리를 막는 물체 찾기에 쓴다
            path = os.path.join(self.workdir, "isnet-general-use.onnx")
            fetch_isnet(path)
            self.matte = Matte(path)
        for p in (self.sdxl, self.sheet_pipe, self.refine_pipe, self.live_pipe):
            p.set_progress_bar_config(disable=True)
        # 그림으로 바꾸는 마지막 단계(VAE 디코딩)를 조각내서 한다: 필요한 메모리가 그림 해상도와 상관없이 일정해진다
        self.sdxl.vae.enable_tiling()   # 파이프라인의 enable_vae_tiling() 은 최신 diffusers 에서 없어짐 - VAE 에 직접 건다
        self.white = Image.new("RGB", (224, 224), "white")   # IP-Adapter 를 안 쓸 때 넣는 빈 그림 (scale 0 과 함께)
        self.set_speed(self.fast)
        self.gpu_report("모델을 모두 올린 뒤")
        return self

    def gpu_report(self, label):
        print(f"[GPU] {label}: 사용 {torch.cuda.memory_allocated() / 1e9:.1f} GB, "
              f"여유 {torch.cuda.mem_get_info()[0] / 1e9:.1f} GB", flush=True)

    def gen(self, seed):
        return torch.Generator(self.device).manual_seed(seed)

    def set_speed(self, fast, steps=None):
        """빠른 SDXL(Hyper-SD LoRA + DDIM trailing, 8단계) <-> 기본(DPM++ Karras). 두 파이프라인이 같은 UNet 을 쓴다."""
        for p in (self.sdxl, self.sheet_pipe, self.refine_pipe, self.live_pipe):
            p.scheduler = self.fast_sched if fast else self.base_sched
        (self.sdxl.enable_lora if fast else self.sdxl.disable_lora)()
        self.steps = steps or (8 if fast else 30)

    def fit_prompt(self, content, tail):
        """SDXL 은 지시문 앞쪽 77토큰만 읽는다. 장면 설명(content)이 길면 뒤에 붙인 그림체·'empty scene' 같은 말(tail)이
        잘려 나가므로, 넘칠 때는 tail 은 그대로 두고 content 를 뒤에서부터 단어 단위로 줄인다."""
        tok = getattr(self.sdxl, "tokenizer", None)
        words = content.split()
        while tok is not None and words:
            prompt = f"{' '.join(words)}, {tail}"
            if len(tok(prompt).input_ids) <= tok.model_max_length:
                return prompt
            words.pop()
        return f"{' '.join(words)}, {tail}" if words else tail

    def negative(self, *specific):
        """단계별 금지어(specific)를 앞에 두고 공통 금지어(NEGATIVE)를 77토큰이 찰 때까지 붙인다.
        SDXL 은 negative 도 앞 77토큰만 읽는데 NEGATIVE 만으로 약 75토큰이라, 예전처럼 NEGATIVE 뒤에 붙인 말
        (배경의 '사람·동물 빼기', 캐릭터·소품의 '배경 풍경 빼기', 다시 그리기의 '얼굴 그리지 마')은 모두 잘려 효과가 없었다
        (2026-11-08 발견 - 냄비가 매번 풍경 섞임으로 3번 그려진 것과 관련 추정)."""
        items = [x.strip() for part in specific for x in part.split(",") if x.strip()]
        common = [x.strip() for x in NEGATIVE.split(",")]
        tok = getattr(self.sdxl, "tokenizer", None)
        if tok is None:
            return ", ".join(items + common)
        out = list(items)
        for x in common:
            if len(tok(", ".join(out + [x])).input_ids) > tok.model_max_length:
                break
            out.append(x)
        return ", ".join(out)

    def txt2img(self, prompt, negative, size, seed):
        self.sdxl.set_ip_adapter_scale(0.0)
        return self.sdxl(prompt, negative_prompt=negative, width=size[0], height=size[1], guidance_scale=5.5,
                         num_inference_steps=self.steps, generator=self.gen(seed), ip_adapter_image=self.white).images[0]

    # ── 검사·점수 ────────────────────────────────────────────────
    def drawn_sprite(self, make, label, seed, inside=None):
        """그리기 -> 학습된 모델로 오려내기 -> 검사: 포장(바탕 카드·흰 테두리 띠), 바탕에 풍경이 따라 그려짐(busy).
        걸리면 seed 를 바꿔 최대 retries 번 다시 그린다 (make(seed, 몇 번째, 마지막인가) - 그림체 참고 세기도 줄인다).
        끝까지 걸리면 문제가 가장 적고, 같으면 풍경이 가장 적게 섞인 것을 쓴다
        ('같으면 첫 번째'로 고르면 가장 세게 참고한 첫 그림이 다시 뽑혀 다시 그린 보람이 없다).
        inside: 아이 그림 기준 몸 안쪽 (아이 캐릭터만) - 생성 그림의 선이 끊겨도 안쪽이 투명하게 잘리지 않게 오려내기에 더한다."""
        best = None
        for t in range(self.retries + 1):
            img = make(seed + 1000 * t, t, t == self.retries)
            mt = self.matte(img)
            sprite = cutout(img, matte=mt, inside=inside)
            clutter = background_clutter(img, mt)
            # 물체 바깥의 1/3 이상이 바탕색과 뚜렷이 다르면 '혼자 흰 바탕'이 아니라 풍경까지 그려진 것
            problems = cutout_problems(sprite) + (["busy"] if clutter > 1 / 3 else [])
            rank = (len(problems), clutter)
            if best is None or rank < best[2]:
                best = (img, sprite, rank)
            if not problems:
                break
            self._save(img, f"try_{_safe(label)}_{t}.png")          # 다시 그린 까닭을 나중에 볼 수 있게
            print(f"   {label}: 오려내기 검사 {problems} (풍경 섞임 {clutter:.2f})"
                  + (" -> 다시 그리기" if t < self.retries else " -> 가장 나은 것 사용"), flush=True)
        return best[0], best[1]

    @staticmethod
    def blocked(matte, reserved):
        """캐릭터 자리(reserved_mask)를 눈에 띄는 물체(배경 제거 모델 출력)가 막고 있는 정도 0~1."""
        spot = np.array(reserved.convert("L")) > 128
        return float((np.array(matte.resize(reserved.size)) / 255.0)[spot].mean()) if spot.any() else 0.0

    def refine(self, page, pasted, kids, text, seed):
        """장면에 녹이기: 조립한 칸 전체를 빠른 SDXL 로 약하게(blend) 다시 그린다 -> 붙인 가장자리가 배경에 녹고
        바닥 그림자·빛·종이 질감이 캐릭터까지 이어진다. 다시 그리면 아이 그림 모양이 흔들릴 수 있으므로
        조연·소품(pasted)은 다시 그린 그림을 inner_mix 만큼만 섞는다 (2px 안으로 줄인 자리).
        아이 캐릭터(kids)는 다시 그린 그림을 섞지 않고, 자리를 3px 넓혀 원래 그대로 둔다: 2026-11-08 Kaggle 비교에서
        섞으면 세기 0.3 부터 풀밭 위 가는 팔이 나뭇가지로 바뀌거나 사라지고, 0.4 부터 하얀 얼굴에 부리·볼터치가 새로 생겼다
        (반투명한 가는 선은 자리 기준(128)에도 못 들어 32 로 낮춤). 아이 캐릭터는 이미 _scene_light 로 주변 빛을 받는다.
        붙인 것 바깥(그림자·주변 배경)은 다시 그린 그림을 그대로 써서 캐릭터와 배경 사이 경계가 이어진다."""
        if self.blend <= 0:
            return page
        size = page.size
        self.sdxl.set_ip_adapter_scale(0.0)
        with self.timed("장면에 녹이기 (칸 1개)"):
            out = self.refine_pipe(self.fit_prompt(text, f"{SCENE_TOUCH}, {GOOD_STYLE}"), negative_prompt=NEGATIVE,
                                   image=page.resize(gen_size(size), Image.LANCZOS), strength=self.blend,
                                   guidance_scale=5.5, num_inference_steps=self.steps, generator=self.gen(seed),
                                   ip_adapter_image=self.white).images[0].resize(size, Image.LANCZOS)
        inner = pasted.point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.MinFilter(5))
        keep = np.array(inner.filter(ImageFilter.GaussianBlur(2))).astype(np.float32)[..., None] / 255 * (1 - self.inner_mix)
        child = kids.point(lambda v: 255 if v > 32 else 0).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.5))
        keep = np.maximum(keep, np.array(child).astype(np.float32)[..., None] / 255)
        mixed = np.array(out).astype(np.float32) * (1 - keep) + np.array(page).astype(np.float32) * keep
        return Image.fromarray(np.clip(mixed, 0, 255).astype(np.uint8))

    def liven(self, page, item, pasted, asset, text, seed, name, background):
        """아이 캐릭터를 장면 안에서 다시 그린다 (붙인 스티커 -> 그 장소에 있는 캐릭터).
        - 어디를: 붙인 캐릭터 자리 + 둘레 띠(자른 그림의 4%)만. 둘레까지 다시 그려야 가장자리·바닥이 배경과 이어진다.
          다른 캐릭터·소품 자리는 빼서 지운다 (손에 든 냄비가 지워지지 않게).
        - 무엇을 따라: 자세를 적용한 캐릭터의 선(scribble ControlNet) = 모양, 지금 칸 그림에서 출발 = 색 배치,
          IP-Adapter = 완성 캐릭터 그림(기본) 또는 그 칸 배경의 그림체(style).
        - 얼마나 크게: 캐릭터 둘레를 정사각형으로 잘라 LIVE_SIZE 로 키워 그린다 (작은 캐릭터도 선이 안 뭉개지고, 칸 전체보다 빠르다).
        - 그림체 입히기(style): 배경을 IP-Adapter 그림체 층에만 보여 주고(LIVE_STYLE_IP), 선을 style_cn 으로, 세기 style_live.
          2026-11-08 Kaggle: 수채·동화풍으로 크게 바뀌어 gpt 그림에 가장 가까웠지만, 아이가 그린 점·일자 눈이 큰 만화 눈·볼터치·
          부리·이빨로 바뀌었다 -> 얼굴 그리지 말라는 지시(LIVE_NO_FACE)를 negative 에 넣고,
          line_keep: 다시 그린 뒤 아이가 그린 선 전부(윤곽선·막대 팔·눈·입 = 몸 색보다 뚜렷이 진한 곳)를 원래 그림에서 다시 덮는다
          -> 선은 아이 그림 그대로, 안쪽 색·질감만 그림체. (얼굴만 덮던 방식은 막대 팔이 흐려지거나 사라졌다.)
        - (행동 모드는 없앴다: SDXL 이 행동을 그리지 못하고 지운 팔 자리가 흰 안개로 덮였으며, 팔다리 자리 넓히기가 1번에 20초 걸렸다.
          행동은 꼭두각시 자세(puppet.pose)로 표현한다.)
        - 검사 (_live_scores): 몸이 남았나(배경과 다른 색으로 남았나) / 원래 얼굴 표시가 남았나 / 몸 안에 새 얼굴·무늬가 생겼나.
          기준 LIVE_CHECK. live_enforce=False 면 버리지 않고 점수만 남긴다 (기준을 정하는 비교용).
          (배경 제거 모델로 모양을 재던 방식은 밝은 배경 위 하얀·노란 캐릭터를 놓쳐 좋은 그림을 버렸다 - 2026-11-08)
        -> (칸 그림, 금색 테두리를 두를 모양 L = 원래 붙인 모양. 선을 원래대로 덮으므로 모양이 같다)."""
        layer = item["layer"]
        alpha = layer.getchannel("A")
        if self.live <= 0 or not alpha.getbbox():
            return page, alpha
        W, H = page.size
        x0, y0, x1, y1 = alpha.getbbox()
        side = int(min(max(x1 - x0, y1 - y0) * 1.3, W, H))
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        bx = int(min(max(cx - side / 2, 0), W - side))
        by = int(min(max(cy - side / 2, 0), H - side))
        box = (bx, by, bx + side, by + side)
        S = LIVE_SIZE

        def cut(img, resample=Image.LANCZOS):
            return img.crop(box).resize((S, S), resample)

        shape = np.array(cut(alpha)) > 32
        # 다른 캐릭터·소품 자리 (붙인 것 전체 - 이 캐릭터), 조금 넓혀서
        others = _grow((np.array(cut(pasted)) > 64) & ~shape, 2)
        mask = Image.fromarray(((_grow(shape, S * 0.02) & ~others) * 255).astype(np.uint8))
        core = ndimage.distance_transform_edt(shape) > 3
        ring = max(3, int(S * 0.04))
        lines = Image.new("RGB", layer.size, "white")
        lines.paste(layer, (0, 0), layer)
        crop = cut(page)
        control = to_scribble(cut(lines), size=S)
        prompt = self.fit_prompt(f"{asset['look']}, in {text}", LIVE_LOOK)
        self.set_speed(self.live_fast, None if self.live_fast else self.character_steps)
        if self.style:     # 그림체 층에만 그 칸 배경을 참고 그림으로
            self.sdxl.set_ip_adapter_scale(style_only(LIVE_STYLE_IP))
            ref, cn, strength = background.convert("RGB"), self.style_cn, self.style_live
        else:              # 완성 캐릭터 그림 전체를 참고 그림으로
            self.sdxl.set_ip_adapter_scale(LIVE_IP)
            ref, cn, strength = asset["sheet"], 0.8, self.live
        with self.timed("아이 캐릭터 장면 안에서 다시 그리기 (1번)"):
            out = self.live_pipe(prompt, negative_prompt=self.negative(LIVE_NO_FACE) if self.style else self.negative(),
                                 image=crop, mask_image=mask, control_image=control,
                                 width=S, height=S, strength=strength, controlnet_conditioning_scale=cn,
                                 guidance_scale=6.0, num_inference_steps=self.steps, generator=self.gen(seed),
                                 ip_adapter_image=ref).images[0]
        self.set_speed(self.fast)
        drawn = out
        if self.color_keep:  # 몸 색조를 원래 색으로 (그림체를 따라 주황이 노랑으로 바뀌던 문제), 그다음 부분 얼룩(볼터치)도 되돌림
            body_px = core & ~_child_lines(crop, shape, core)
            out = _drop_new_colors(crop, _keep_colors(crop, out, body_px), body_px)
        if self.line_keep:   # 아이가 그린 선(윤곽·팔·눈·입)을 원래 그림에서 다시 덮는다
            ink = _child_lines(crop, shape, core)
            if ink.any():
                soft = Image.fromarray((_grow(ink, 1.5) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
                out = Image.composite(crop, out, soft)
        with self.timed("다시 그린 모양 검사 (CPU)"):
            bg_crop = cut(background.convert("RGB"))
            sc = _live_scores(crop, out, core, bg_crop)
            # 몸이 남았나는 모델이 그린 그대로(색·선 되돌리기 전)로 본다: 몸이 배경으로 지워졌어도 색 지키기가
            # 그 자리를 캐릭터 색으로 다시 물들이면 '남은 것'처럼 보인다 (노트북 가짜 시험에서 발견)
            sc["body"] = _live_scores(crop, drawn, core, bg_crop)["body"]
            fails = [k for k, (lo, hi) in LIVE_CHECK.items() if not (lo <= sc[k] <= hi)]
            ok = not fails
        mode = (("그림체" + (" + 선 지키기" if self.line_keep else "") + (" + 색 지키기" if self.color_keep else ""))
                if self.style else "자세 그대로")
        score_en = " ".join(f"{k} {v:.3f}" if k == "new" else f"{k} {v:.2f}" for k, v in sc.items())
        verdict = "OK" if ok else f"FAIL({','.join(fails)})"
        print(f"   {name}: 장면 안 다시 그리기 ({mode}) {score_en} -> "
              f"{'사용' if ok else ('기준 미달이지만 사용 (비교용)' if not self.live_enforce else '버림 (붙인 그대로)')}"
              + ("" if ok else f" - 걸린 것 {fails}"), flush=True)
        self.live_log.append({"name": name, "mode": mode, **sc, "ok": ok})
        if self.save_dir:
            shots = (crop, control, drawn) + ((out,) if out is not drawn else ())
            strip = Image.new("RGB", (S * len(shots), S + 24), "white")
            for k, im in enumerate(shots):
                strip.paste(im, (k * S, 24))
            ImageDraw.Draw(strip).text((6, 6), "before | lines | after" + (" | lines kept" if len(shots) == 4 else "")
                                       + f"   {'STYLE' if self.style else 'POSE'}   {score_en}  {verdict}", fill="black")
            strip.resize((strip.width // 2, strip.height // 2)).save(os.path.join(self.save_dir, f"live_{_safe(name)}.png"))
        if not ok and self.live_enforce:
            return page, alpha
        # 다시 그린 자리만 부드럽게 바꿔 넣는다 (자르고 키운 그림을 원래 크기로)
        soft = mask.filter(ImageFilter.GaussianBlur(ring / 4))
        page = page.copy()
        page.paste(out.resize((side, side), Image.LANCZOS), box[:2], soft.resize((side, side), Image.LANCZOS))
        return page, alpha

    # ── 1. 아이 캐릭터 ────────────────────────────────────────────
    def make_characters(self, characters, compare=False):
        """characters: {id: {"image": 아이 그림(PIL), "desc": 영어 짧은 설명, "arms": 개수, "legs": 개수}}
        -> {id: {"sprite", "rig", "child": True}}. compare: 기본 30단계로도 그려 나란히 저장 (확인용)."""
        todo = {k: v for k, v in characters.items() if self._key(v) not in self._characters}
        if todo:
            self.controlnet.to(self.device)
            self.sdxl.set_ip_adapter_scale(0.5)
            self.set_speed(False, self.character_steps)
            for i, (k, info) in enumerate(todo.items()):
                drawing = _on_white(info["image"])
                self._save(to_scribble(drawing), f"scribble_{k}.png")
                inside, unpainted = child_regions(drawing, 1024)
                make, measured = self._sheet_maker(info, drawing, unpainted, inside)
                with self.timed(f"캐릭터 완성 (1명, 기본 {self.character_steps}단계, 검사·다시 그리기 포함)"):
                    sheet, sprite = self.drawn_sprite(make, k, self.seed + i, inside=inside)
                self._save(sheet, f"sheet_{k}.png")
                if compare:
                    self.set_speed(False, 30)
                    with self.timed("캐릭터 완성 (기본 30단계, 비교용)"):
                        base = make(self.seed + i, 0)
                    self.set_speed(False, self.character_steps)
                    pair = Image.new("RGB", (2048, 1024), "white")
                    pair.paste(sheet, (0, 0)); pair.paste(base, (1024, 0))
                    self._save(pair.resize((1024, 512)), f"compare_sheet_{k}.png")   # 왼쪽 20단계 | 오른쪽 30단계
                rig = choose_limbs(find_parts(sprite), arms=info.get("arms"), legs=info.get("legs"))
                self._save(numbered_overlay(sprite, rig), f"limbs_{k}.png")
                # sheet·look: 장면 안에서 다시 그릴 때 IP-Adapter 참고 그림과 지시문으로 쓴다
                self._characters[self._key(info)] = {"sprite": sprite, "rig": rig, "child": True, "sheet": sheet,
                                                     "look": ", ".join([info["desc"]] + measured)}
                print(f"{k}: 후보 {len(rig.limbs)}개, 움직이는 것 {[f'{l.id}:{l.kind}' for l in rig.moving]}", flush=True)
            # 장면 안에서 다시 그리기를 안 쓰면 ControlNet 은 CPU 로 내린다 (다음 동화에서 다시 올림).
            # IP-Adapter 는 조연·소품 그림체 참고에 쓰므로 둔다.
            if self.live <= 0:
                self.controlnet.to("cpu")
                gc.collect(); torch.cuda.empty_cache()
            self.set_speed(self.fast)
        return {k: self._characters[self._key(v)] for k, v in characters.items()}

    def _sheet_maker(self, info, drawing, unpainted, inside):
        # 아이 그림에서 잰 것을 글로도 알려 준다 (지시문이 길어도 잘리지 않게 뒤쪽 고정 부분에 넣는다):
        # 윤곽선 색 - 주황 몸의 갈색 테두리처럼 면에 붙은 선은 그림만으로는 사라지기 쉽다
        # white inside - 안쪽을 칠하지 않았는데 선 색이 글에 있으면 안쪽까지 그 색으로 칠하기 쉽다
        measured = []
        line = outline_color(drawing)
        if line:
            measured.append(f"{line} outline")
        if inside.any() and unpainted.sum() > 0.5 * inside.sum():
            measured.append("white inside")
        prompt = self.fit_prompt(info["desc"], ", ".join(measured + [CHARACTER_LOOK, "plain white background"]))

        def make(seed, t=0, last=False):
            sheet = self.sheet_pipe(prompt, negative_prompt=self.negative("background scenery"),
                                    image=to_scribble(drawing), ip_adapter_image=drawing,
                                    controlnet_conditioning_scale=0.9, width=1024, height=1024,
                                    guidance_scale=6.0, num_inference_steps=self.steps, generator=self.gen(seed)).images[0]
            # 그래도 아이가 비워 둔 곳에 색이 생기면 그린 뒤 하얗게 되돌린다 (다시 그리기보다 빠르다).
            # 몸 안 표시(눈·코·입)는 아이 그림의 것으로 바꾼다 - 완성 단계가 코·웃는 입·안경을 지어내던 문제 (2026-11-11)
            return child_face(keep_unpainted(sheet, unpainted), drawing, inside)
        return make, measured

    @staticmethod
    def _key(info):
        h = hashlib.sha1(info["image"].convert("RGBA").tobytes())
        h.update(f"{info.get('desc')}|{info.get('arms')}|{info.get('legs')}".encode())
        return h.hexdigest()

    # ── 2~4. 배경 -> 조연·소품 -> 조립 ───────────────────────────────
    def make_book(self, plan, assets):
        """plan: scene_plan 형식 {"pages": [...]}. assets: make_characters 결과. -> 페이지 그림(PIL) 목록."""
        pages = normalize_plan(plan, list(assets))
        backgrounds, style_ref = self._backgrounds(pages, assets)
        props, extras = self._side_pieces(pages, style_ref)
        self.last_book = (pages, backgrounds, assets, props, extras)    # 시험 노트북이 녹이기 세기만 바꿔 다시 조립할 때 쓴다
        return self.compose_pages(pages, backgrounds, assets, props, extras)

    def compose_pages(self, pages, backgrounds, assets, props, extras, tag=""):
        """칸 조립 -> 아이 캐릭터 장면 안에서 다시 그리기 -> 장면에 녹이기 -> 금색 테두리 -> 페이지.
        배경·조연·소품을 다시 그리지 않고 세기만 바꿔 비교할 때도 쓴다."""
        pictures = []
        for n, page in enumerate(pages):
            panels = []
            for i, panel in enumerate(page["panels"]):
                text = background_prompt(panel)
                seed = self.seed + 900 + 100 * (n + 1) + 10 * i

                def refine(img, pasted, child_layers, text=text, seed=seed, where=f"p{page['page']}_{i + 1}",
                           bg=backgrounds[(n, i)]):
                    shapes = []
                    for j, item in enumerate(child_layers):
                        img, shape = self.liven(img, item, pasted, assets[item["id"]], text, seed + j,
                                                f"{item['id']}_{where}{tag}", bg)
                        shapes.append(shape)
                    kids = Image.new("L", img.size, 0)
                    for shape in shapes:
                        kids = ImageChops.lighter(kids, shape)
                    return self.refine(img, pasted, kids, text, seed), shapes
                with self.timed("칸 조립 (자세·그림자·테두리, 녹이기 포함)"):
                    panels.append(compose_panel(backgrounds[(n, i)], panel, assets, props, extras, refine=refine,
                                                glow=self.glow))
            picture = assemble_page(panels)
            self._save(picture, f"page{page['page']}{tag}.png")
            pictures.append(picture)
        return pictures

    def _backgrounds(self, pages, assets):
        """칸마다 배경 먼저: 1장 그리고, 캐릭터 자리를 눈에 띄는 물체가 막았을 때만 다시 그린다 (최대 bg_tries 장).
        예전처럼 3장을 그려 CLIP 으로 고르던 방식은 후보 차이가 작아도 1등·꼴찌를 억지로 벌려 사실상 무작위였고,
        자리 점수도 거의 모든 후보가 0.95 이상이라 시간만 썼다.
        한 번만 나오는 조연·옆에 놓이기만 하는 소품은 배경과 함께 그린다 (normalize_plan 이 painted 표시).
        여러 번 나오는 조연은 아직 그리기 전이라 reserved_mask 가 작은 네모 크기로 자리만 비워 둔다."""
        backgrounds, style_ref = {}, {}
        jobs = []          # (n, i, panel, size, text, negative, reserved, 첫 장, 자리 검사 작업)
        for n, page in enumerate(pages):
            for i, (panel, size) in enumerate(zip(page["panels"], panel_sizes(len(page["panels"])))):
                text = background_prompt(panel)
                once = [e for e in panel["extras"] if not e.get("recurring")]
                negative = self.negative('people, person, human, child, face' if once else NO_CHARACTERS)  # 배경 속 조연 허용
                reserved = reserved_mask(gen_size(size), panel, assets)
                with self.timed("배경 (1장)"):
                    first = self.txt2img(self.fit_prompt(text, f"{GOOD_STYLE}, empty scene"), negative, gen_size(size),
                                         self.seed + 100 * (n + 1) + 10 * i)
                # 자리 검사(배경 제거 모델, CPU)는 GPU 가 다음 칸을 그리는 동안 따로 돌린다
                jobs.append((n, i, panel, size, text, negative, reserved, first, self.cpu.submit(self.matte, first)))
        for n, i, panel, size, text, negative, reserved, first, job in jobs:
            page = pages[n]
            cands = [first]
            with self.timed("배경 자리 검사 (CPU, 기다린 시간)"):
                blocked = [self.blocked(job.result(), reserved)]
            for c in range(1, self.bg_tries):
                if blocked[-1] <= BLOCKED:
                    break
                with self.timed("배경 (1장)"):
                    cands.append(self.txt2img(self.fit_prompt(text, f"{GOOD_STYLE}, empty scene"), negative, gen_size(size),
                                              self.seed + 100 * (n + 1) + 10 * i + c))
                with self.timed("배경 자리 검사 (CPU, 기다린 시간)"):
                    blocked.append(self.blocked(self.matte(cands[-1]), reserved))
            name = f"p{page['page']}_{i + 1}"
            if self.save_dir:
                candidate_strip(cands, blocked, reserved).save(os.path.join(self.save_dir, f"cands_{name}.png"))
            best = int(np.argmin(blocked))
            bg = warm_grade(cands[best]).resize(size, Image.LANCZOS)
            self._save(bg, f"bg_{name}.png")
            backgrounds[(n, i)] = bg
            for pr in panel["props"]:
                if not pr["painted"]:
                    style_ref.setdefault(pr["name"], bg)
            for e in panel["extras"]:
                if e.get("recurring"):
                    style_ref.setdefault(e["name"], bg)
            print(f"{page['page']}페이지 {i + 1}칸: {text}\n   캐릭터 자리 막힘 {[round(b, 2) for b in blocked]} -> {best + 1}번",
                  flush=True)
        return backgrounds, style_ref

    def _styled(self, ref, prompt, negative):
        """그림체 참고 세기 STYLE_REF_START 로 그리고, 검사(풍경이 따라 그려짐 등)에 걸려 다시 그릴 때마다 반으로 줄인다.
        (1.0 에서 시작하면 참고 그림(배경)의 풍경까지 따라와 자주 걸렸다 - 2026-11-08 강아지 3번 모두 busy, 42초.)
        마지막 다시 그리기는 참고를 끈다(0) - 어떤 물체든 마지막엔 흰 바탕에 혼자 있는 그림이 보장되고,
        그림체는 글자 지시(ASSET_STYLE)와 색 보정(graded)으로 맞춘다.
        물체마다 참고 그림에 끌려가는 정도가 달라서 (강아지는 괜찮고 냄비는 풍경에 묻힘) 하나로 정한 세기는 맞지 않는다."""
        def make(seed, t, last=False):
            self.sdxl.set_ip_adapter_scale(style_only(0.0 if last and t > 0 else STYLE_REF_START * 0.5 ** t))
            return self.sdxl(prompt, negative_prompt=negative, width=1024, height=1024, guidance_scale=5.5,
                             num_inference_steps=self.steps, generator=self.gen(seed), ip_adapter_image=ref).images[0]
        return make

    def _side_pieces(self, pages, style_ref):
        """들고 쓰는 소품·여러 번 나오는 조연: 처음 나오는 칸의 배경을 그림체 참고 그림으로 보여 주며 그린다.
        그림체를 글자로만 지시하면 흰 바탕에 혼자 그린 동물은 SDXL 이 원래 잘 그리는 실사풍으로 끌려간다."""
        prop_names = sorted(style_ref.keys() & {pr["name"] for p in pages for panel in p["panels"] for pr in panel["props"]})
        extra_names = sorted(style_ref.keys() - set(prop_names))
        props, extras = {}, {}
        for i, name in enumerate(prop_names):
            with self.timed("소품 그림 (1개, 검사·다시 그리기 포함)"):
                img, sprite = self.drawn_sprite(self._styled(style_ref[name], self.fit_prompt(name, f"{ALONE}, {ASSET_STYLE}"),
                                                             self.negative(NO_CHARACTERS, "background scenery")),
                                                name, self.seed + 500 + i)
            self._save(img, f"prop_{i}.png")
            props[name] = graded(sprite)
        for i, name in enumerate(extra_names):
            with self.timed("조연 그림 (1명, 검사·다시 그리기 포함)"):
                img, sprite = self.drawn_sprite(self._styled(style_ref[name], self.fit_prompt(name, f"full body, {ALONE}, {ASSET_STYLE}"),
                                                             self.negative("background scenery")),
                                                name, self.seed + 700 + i)
            self._save(img, f"extra_{i}.png")
            sprite = graded(sprite)
            extras[name] = {"sprite": sprite, "rig": choose_limbs(find_parts(sprite))}   # 조연은 자세 없이 서 있게
        print("따로 그린 소품:", prop_names, "| 여러 번 나오는 조연:", extra_names, flush=True)
        return props, extras

    def timing_report(self, n_characters, pages):
        lines = [f"모드: 아이 캐릭터 기본 SDXL {self.character_steps}단계, 나머지 "
                 f"{'빠른 SDXL (Hyper-SD 8단계)' if self.fast else '기본 SDXL 30단계'}, 배경 1장 (자리 막히면 최대 {self.bg_tries}장), "
                 f"장면에 녹이기 세기 {self.blend} (안쪽 섞기 {self.inner_mix}), "
                 f"아이 캐릭터 장면 안 다시 그리기 세기 {self.live}, "
                 f"그림체 입히기 {f'켬, 세기 {self.style_live}, 선 {self.style_cn}' if self.style else '끔'}, "
                 f"선 지키기 {'켬' if self.line_keep else '끔'}, 색 지키기 {'켬' if self.color_keep else '끔'}, "
                 f"발광 {'켬' if self.glow else '끔'}, "
                 f"다시 그리기 {'빠른 SDXL' if self.live_fast else '기본 SDXL'}",
                 "단계 | 횟수 | 평균(초) | 합계(초)", "---|---|---|---"]
        for label, ts in self.times.items():
            lines.append(f"{label} | {len(ts)} | {np.mean(ts):.1f} | {np.sum(ts):.1f}")
        total = sum(np.sum(ts) for label, ts in self.times.items()
                    if label != "모델 불러오기 (처음 1번)" and "비교용" not in label
                    and not label.startswith(("장면에 녹이기", "아이 캐릭터 장면 안", "다시 그린 모양")))   # 칸 조립 시간에 이미 들어 있다
        n_panels = sum(len(p.get("panels", [p])) for p in pages)
        lines.append(f"\n→ 동화 1권 (캐릭터 {n_characters}명, {len(pages)}페이지 {n_panels}칸): "
                     f"{total / 60:.1f}분 (모델 불러오기·비교용 제외)")
        total_gb = torch.cuda.get_device_properties(0).total_memory / 1e9
        lines.append(f"→ GPU 메모리: 최대 {torch.cuda.max_memory_allocated() / 1e9:.1f} GB 사용 / 전체 {total_gb:.1f} GB")
        return "\n".join(lines)


def fetch_isnet(path):
    """배경 제거 모델 파일 준비. Kaggle Input 에 올려 둔 것 -> GitHub(공식) -> Hugging Face 복사본(SHA256 이 맞을 때만) 순.
    2026-11-08 GitHub 내려받기가 504(시간 초과)로 계속 실패해 노트북이 멈췄다 - 전시 날 그림 서버가 같은 일로 못 켜지지 않게."""
    import glob, hashlib, shutil
    if os.path.exists(path):
        return path
    for found in sorted(glob.glob("/kaggle/input/**/isnet-general-use.onnx", recursive=True)):
        shutil.copy(found, path)
        return path
    for url, check in ((ISNET_URL, False), (ISNET_URL, False), (ISNET_MIRROR, True), (ISNET_MIRROR, True)):
        try:
            urllib.request.urlretrieve(url, path + ".part")
            if check:
                h = hashlib.sha256()
                with open(path + ".part", "rb") as f:
                    for chunk in iter(lambda: f.read(1 << 20), b""):
                        h.update(chunk)
                if h.hexdigest() != ISNET_SHA256:
                    raise OSError(f"파일 지문이 다름 ({h.hexdigest()[:12]}...)")
            os.replace(path + ".part", path)
            print(f"배경 제거 모델 받음: {url}", flush=True)
            return path
        except OSError as e:          # HTTPError·URLError·지문 다름 모두
            print(f"배경 제거 모델 내려받기 실패 ({url.split('/')[2]}: {e}) - 10초 뒤 다음 시도", flush=True)
            time.sleep(10)
    raise RuntimeError("배경 제거 모델을 내려받지 못했습니다. isnet-general-use.onnx 를 Kaggle Input 에 올려 주세요.")


def _grow(mask, r):
    """bool 모양을 반지름 r 만큼 넓힌다. 거리 계산이라 r 과 상관없이 빠르다
    (PIL MaxFilter 는 크기의 제곱만큼 느려져 768 그림에서 크기 169 가 21초 걸렸다 - 2026-11-08 칸당 40초의 원인)."""
    return ndimage.distance_transform_edt(~mask) <= r


def _face_marks(before, core):
    """몸 안의 진한 표시 (아이가 그린 눈·입·코 등): 윤곽선에서 떨어진 몸 안쪽 중 몸 색보다 뚜렷이 어두운 곳."""
    S = core.shape[0]
    lum = np.array(before.convert("L")).astype(float)
    inner = ndimage.distance_transform_edt(core) > S * 0.03
    if inner.sum() <= 100:
        return np.zeros_like(core)
    marks = inner & (lum < np.median(lum[inner]) - 50)
    return marks if marks.sum() > 30 else np.zeros_like(core)


def _keep_colors(before, after, body):
    """다시 그린 몸(body)의 색을 원래 색으로 되돌린다. 채널마다 '원래 몸의 가운데 값 / 다시 그린 몸의 가운데 값' 을 곱하므로
    붓 자국·명암(밝고 어두운 차이)은 남고 전체 색조만 돌아온다 (2026-11-08: 배경 그림체를 따라가며 주황 악당이 노랑으로).
    가장자리는 부드럽게 섞어 몸 경계에 색 띠가 생기지 않게 한다."""
    if body.sum() < 100:
        return after
    a0 = np.array(before.convert("RGB")).astype(np.float32)
    a1 = np.array(after.convert("RGB")).astype(np.float32)
    gain = np.clip((np.median(a0[body], axis=0) + 1) / (np.median(a1[body], axis=0) + 1), 0.5, 2.0)
    w = ndimage.gaussian_filter(body.astype(np.float32), 2)[..., None]
    fixed = np.clip(a1 * gain, 0, 255)
    return Image.fromarray((a1 * (1 - w) + fixed * w).astype(np.uint8))


def _drop_new_colors(before, after, body, limit=30):
    """다시 그린 몸 안에서 색조가 원래와 뚜렷이 달라진 얼룩(볼터치·새 무늬)을 원래 그림으로 되돌린다.
    색조 = 픽셀 색에서 밝기(세 채널 평균)를 뺀 것. 명암·붓 자국은 주로 밝기 변화라 남고, 하얀 몸에 생긴 주황 볼처럼
    색 자체가 바뀐 곳만 걸린다 (2026-11-11 앱 시험: 주인공 볼터치는 부드러운 색이라 새 무늬 검사에도 안 걸렸다).
    색 지키기(_keep_colors)로 몸 전체 색조를 맞춘 뒤에 쓴다 - 그래야 남은 차이가 '부분 얼룩'이다."""
    if body.sum() < 100:
        return after
    a0 = np.array(before.convert("RGB")).astype(np.float32)
    a1 = np.array(after.convert("RGB")).astype(np.float32)
    c0 = a0 - a0.mean(axis=2, keepdims=True)
    c1 = a1 - a1.mean(axis=2, keepdims=True)
    changed = body & (np.linalg.norm(c1 - c0, axis=2) > limit)
    if not changed.any():
        return after
    w = ndimage.gaussian_filter((_grow(changed, 5) & body).astype(np.float32), 2)[..., None]   # 얼룩 가장자리 테두리까지
    return Image.fromarray((a1 * (1 - w) + a0 * w).astype(np.uint8))


def _child_lines(before, shape, core):
    """아이가 그린 선: 캐릭터 모양 안에서 몸 색보다 뚜렷이 진한 곳 (윤곽선·막대 팔·눈·입). 몸 자체가 진한 캐릭터는
    몸 색 기준이라 몸 전체가 잡히지 않는다."""
    lum = np.array(before.convert("L")).astype(float)
    if not core.any():
        return np.zeros_like(shape)
    return shape & (lum < np.median(lum[core]) - 50)


def _live_scores(before, after, core, background):
    """장면 안 다시 그리기 검사 점수.
    before/after: 다시 그리기 전·후 자른 그림. core: 원래 몸 자리. background: 같은 자리의 배경(캐릭터 없음).
    - body: 원래 몸 중 배경과 뚜렷이 달랐던 곳이 다시 그린 뒤에도 배경과 다른 비율 (몸이 배경으로 지워지면 낮다).
      배경 제거 모델은 밝은 배경 위 하얀·노란 캐릭터를 놓쳐서(2026-11-08 주인공 0.46, 별 0.02) 쓰지 않는다
    - face: 원래 얼굴 표시가 원래 진하기의 절반 이상으로 남은 비율 (표시가 없으면 1)
    - new: 몸 안에 원래 없던 또렷한 무늬(새 눈·입·이빨)가 생긴 넓이 / 원래 얼굴 표시 넓이 (표시가 작거나 없으면 몸 안쪽의 2%).
      또렷함 = 자기 주변 평균과의 밝기 차이라서, 부드러운 음영·옅은 질감·볼터치는 거의 세지 않는다.
      (2026-11-08: 그림체 입히기에서 악당이 초록 눈 고양이로 바뀌었는데 face 는 0.76 으로 통과 - '남았나'만 봤기 때문)"""
    S = core.shape[0]
    b0 = np.abs(np.array(before).astype(float) - np.array(background).astype(float)).sum(axis=2)
    b1 = np.abs(np.array(after).astype(float) - np.array(background).astype(float)).sum(axis=2)
    stood_out = core & (b0 > 60)
    body = float((b1[stood_out] > 0.4 * b0[stood_out]).mean()) if stood_out.sum() > 100 else 1.0
    lum0 = np.array(before.convert("L")).astype(float)
    lum1 = np.array(after.convert("L")).astype(float)
    inner = ndimage.distance_transform_edt(core) > S * 0.03
    face = 1.0
    marks = _face_marks(before, core)
    if marks.any():
        darkest = ndimage.minimum_filter(lum1, size=max(3, S // 100) | 1)   # 표시가 몇 픽셀 움직여도 남은 것으로
        was = np.median(lum0[inner]) - lum0[marks]
        now = np.median(lum1[inner]) - darkest[marks]
        face = float((now >= 0.5 * was).mean())
    d0 = np.abs(lum0 - ndimage.gaussian_filter(lum0, 3))
    d1 = np.abs(lum1 - ndimage.gaussian_filter(lum1, 3))
    fresh = inner & (d1 > 25) & ~_grow(d0 > 15, S * 0.01)
    new_detail = float(fresh.sum() / max(int(marks.sum()), int(inner.sum() * 0.02), 1))
    return {"body": body, "face": face, "new": new_detail}


def _safe(name):
    return "".join(c if c.isalnum() else "_" for c in name)[:40]


def _on_white(img):
    """투명 바탕 그림(앱에서 오는 PNG)을 흰 바탕 512x512 로."""
    img = img.convert("RGBA")
    return Image.alpha_composite(Image.new("RGBA", img.size, "white"), img).convert("RGB").resize((512, 512))
