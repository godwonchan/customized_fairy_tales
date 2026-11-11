"""아이 그림 캐릭터를 몸통·팔다리로 나눠 자세를 바꾸는 도구.

학습 없이 처음 보는 그림에도 바로 쓴다. 그림의 선과 색은 그대로 두고 부분의 각도·위치만 바꾸므로 모양이 유지된다.

    sprite = cutout(drawing)              # 흰 바탕 그림 -> 투명 바탕 캐릭터
    rig = find_parts(sprite)              # 몸통에서 튀어나온 부분을 모두 후보로 (번호 붙임)
    overlay = numbered_overlay(sprite, rig)   # AI 에게 보여줄 번호 그림 (LIMB_QUESTION 과 함께)
    choose_limbs(rig, labels={"arms": [2, 3], "legs": []})   # AI 답 (또는 arms=2, legs=0 처럼 개수만)
    posed = pose(sprite, rig, "wave")     # 자세 적용 - 팔로 정해진 후보만 움직이고, 팔이 없으면 만들지 않는다
    name = pose_from_action("waving hello")   # 줄거리 문장 -> 자세 이름
"""
from dataclasses import dataclass, field, replace

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage


# 원(반지름 r) 모양으로 깎기·불리기. 거리 계산으로 구하므로 비용이 r 과 상관없이 그림 크기에만 비례한다.
# (원 모양 도장을 찍는 방식은 r 의 제곱에 비례해 느려지고 메모리가 터진다 - 몸통이 큰 캐릭터일수록 r 이 커진다)
def _erode(mask, r):
    return ndimage.distance_transform_edt(mask) > r


def _dilate(mask, r):
    return ndimage.distance_transform_edt(~mask) <= r


def _open(mask, r):
    return _dilate(_erode(mask, r), r)


def _close(mask, r):
    return _erode(_dilate(mask, r), r)


# ── 1. 캐릭터 오려내기 ──────────────────────────────────────────────

def silhouette(img, tol=60):
    """단색 바탕 위 캐릭터 모양 (흰색 = 캐릭터).
    모서리 색과 비슷하고 가장자리와 이어진 곳만 바탕으로 보므로, 하얀 캐릭터의 윤곽선 안쪽도 캐릭터로 잡힌다."""
    a = np.array(img.convert("RGB").filter(ImageFilter.GaussianBlur(2))).astype(int)
    h, w = a.shape[:2]
    bg_color = np.median(np.array([a[2, 2], a[2, w - 3], a[h - 3, 2], a[h - 3, w - 3]]), axis=0)
    drawn = np.abs(a - bg_color).sum(axis=2) >= tol

    def enclosed(d):
        """가장자리와 이어진 바탕을 뺀 나머지 = 캐릭터."""
        background, _ = ndimage.label(~d)
        border = set(np.unique(np.concatenate([background[0], background[-1], background[:, 0], background[:, -1]])))
        return ~np.isin(background, list(border - {0})) | d

    plain = enclosed(drawn)
    closed = enclosed(_close(drawn, 4))       # 끊긴 선의 작은 틈을 메운 경우
    # 틈 메우기로 새로 생긴 부분 중 넓은 면(윤곽선이 살짝 끊긴 몸 안쪽)만 살리고,
    # 가는 틈(나란히 그린 두 다리 사이 등)은 다시 비워서 다리가 한 덩어리로 붙지 않게 한다
    added = closed & ~plain
    inside = plain | _open(added, 4)
    return Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))


def cutout(img, max_side=768, matte=None, inside=None):
    """흰(단색) 바탕 그림 -> 캐릭터만 남긴 투명 바탕 RGBA (여백 잘라냄).
    matte: 학습된 배경 제거 모델이 낸 모양(L). 주면 그것을 쓴다 - 바탕이 단색이 아니어도(그림자·번짐·색 바탕) 오려낸다.
    윤곽선으로 둘러싸인 하얀 몸 안쪽을 모델이 바탕으로 볼 수 있으므로 닫힌 구멍은 메운다.
    inside: 아이 그림 기준 몸 안쪽 (child_regions). 생성 그림의 선이 한 곳이라도 끊기면 하얀 안쪽이 바깥과 이어져
    구멍 메우기로도 안 채워지고 투명하게 잘린다 (별 친구 안쪽·주인공 얼굴이 비친 원인). 아이 그림에서는 선이 이어져 있으므로
    그 안쪽을 더한 뒤, 둘 사이에 남는 가는 틈만 닫고 구멍을 메운다.
    페이지에 들어갈 때는 어차피 이보다 작게 놓이므로, 긴 변을 max_side 로 줄여 이후 분석·자세 비용을 일정하게 한다."""
    if matte is None:
        shape = silhouette(img)
    else:
        m = np.array(matte.convert("L").resize(img.size)) > 128
        if inside is not None:
            m = _close(m | inside, max(img.size) * 0.004)
        m = ndimage.binary_fill_holes(m)
        shape = Image.fromarray((m * 255).astype(np.uint8))
    sprite = img.convert("RGBA")
    sprite.putalpha(shape)
    sprite = sprite.crop(shape.getbbox())
    sprite.thumbnail((max_side, max_side), Image.LANCZOS)
    return sprite


def _enclosed_by(lines):
    """선 그림에서 선으로 둘러싸인 곳 (가장자리와 이어진 바깥과 선 자체는 뺀다)."""
    labels, _ = ndimage.label(~lines)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    return ~np.isin(labels, list(border)) & ~lines


def _rooms_behind_doors(lines, doors=(0.03, 0.045, 0.07, 0.10, 0.13, 0.16)):
    """선으로 완전히 닫히지는 않았지만 몸의 일부인 곳: '좁은 입구를 지나야 들어가는 넓은 공간'이면서 '안에 아이가 그린 것이 있는' 곳.
    몸을 다 그리지 않아 목 아래가 열린 얼굴처럼, 아이들이 자주 선을 다 닫지 않는다 (닫힌 곳만 안쪽으로 보면 얼굴이 투명해진다).
    반대로 막대 다리 사이·들어 올린 팔과 머리 사이 같은 빈 틈은 안에 그린 것이 없으므로 바깥으로 둔다.
    입구 폭은 그림마다 달라서 여러 폭(그림 크기의 doors x2)으로 깎아 보고, 어느 하나에서라도 조건을 만족하면 안쪽으로 본다
    (깎는 폭이 공간보다 크면 공간 자체가 사라지고, 입구보다 작으면 입구가 안 끊긴다).
    작은 폭(3%, 4.5%)은 2026-11-11 앱 시험에서 추가: 흰둥이 머리는 귀 밑이 6% 열렸는데, 머리 안의 눈·입 선 때문에
    빈 공간이 좁아져 7% 이상으로 깎으면 머리 공간이 통째로 사라졌다 (머리가 투명하게 오려짐). 기존 시험 그림 13개는 변화 없음."""
    from skimage.segmentation import watershed
    size = lines.shape[0]
    labels, _ = ndimage.label(~lines)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    outside = np.isin(labels, list(border))
    found = np.zeros_like(lines)
    for door in doors:
        r = size * door
        core, n = ndimage.label(_open(outside, r))       # 입구가 2r 보다 좁으면 여기서 끊긴다
        edge = set(np.unique(np.concatenate([core[0], core[-1], core[:, 0], core[:, -1]]))) - {0}
        if n <= len(edge):
            continue
        # 깎은 부분을 되돌릴 때는 공간을 입구의 가장 좁은 곳에서 나눈다 (선에서 먼 곳부터 물이 차오르는 경계 = 워터셰드).
        # 그냥 r 만큼 불리면 입구 밖으로 넘치고, 바깥에서 r 안쪽을 빼면 공간 안쪽까지 깎인다.
        parts = watershed(-ndimage.distance_transform_edt(outside), core, mask=outside)
        for i in range(1, n + 1):
            if i in edge:
                continue
            room = ndimage.binary_fill_holes(parts == i)                          # 안의 선(눈·코·입)까지
            if (room & lines).sum() > size * size * 0.0005:                       # 안에 그린 것(눈·코·입 등)이 있어야
                # 입구에서 나눈 경계 너머의 통로(목선 사이)도 몸이므로, 선을 넘지 않고 통로를 따라 r 만큼 더 넓힌다
                found |= ndimage.binary_dilation(room, iterations=int(r), mask=outside | room)
    if found.any():
        # 열린 통로(목 사이)가 선이 끝난 곳 너머까지 이어지지 않게, 아이가 그린 선의 바깥 둘레(볼록 껍질) 안으로 자른다
        from skimage.morphology import convex_hull_image
        found &= convex_hull_image(lines)
    return found & ~lines


def child_regions(drawing, size):
    """아이 그림을 생성 그림과 같은 틀(size x size, scribble 과 같음)로 옮겨 잰 두 영역 (bool).
    inside: 아이가 선으로 둘러싼 몸 안쪽 - 선 굵기만큼 안으로 줄여, 생성 그림이 조금 어긋나도 선 바깥으로 넘치지 않게 한다.
    unpainted: 그 안쪽 중 아이가 칠하지 않고 종이로 둔 곳 - 다시 선에서 조금 더 떨어뜨린다 (선·눈 근처는 건드리지 않게)."""
    lines = np.array(to_scribble(drawing, size).convert("L")) > 128
    inside = _erode(_enclosed_by(lines) | _rooms_behind_doors(lines), size * 0.006)
    d = np.array(drawing.convert("RGB").resize((size, size))).astype(int)
    paper = (d.min(axis=2) > 215) & (d.max(axis=2) - d.min(axis=2) < 25)
    unpainted = _erode(inside & paper, size * 0.008)
    return inside, unpainted


def child_face(sheet, drawing, inside):
    """완성 그림(sheet)의 몸 안 표시(눈·코·입·안경·무늬)를 아이 그림의 몸 안 표시로 바꾼다.
    2026-11-11 앱 시험: 캐릭터 완성 단계에서 아이가 그리지 않은 코·웃는 입·안경이 생겼다 (흰둥이, 별 악당, 주인공 세모 코).
    완성 그림은 아이 그림 선(scribble)을 따라 같은 틀(1024)에 그려지므로 위치가 맞는다:
    ① 몸 안쪽(윤곽선에서 떨어진 곳)에서 몸 색보다 뚜렷이 진한 완성 그림의 표시를 주변 몸 색으로 지우고
    ② 같은 영역의 아이 그림 표시(몸 색보다 뚜렷이 진한 곳)를 아이 그림에서 그대로 옮긴다.
    윤곽선 근처는 건드리지 않는다 (윤곽은 완성 그림의 것을 쓴다). inside: child_regions 의 몸 안쪽 (1024)."""
    size = sheet.size[0]
    if not inside.any():
        return sheet
    # 몸 안쪽 = 아이 그림 전체 모양(몸을 가로지르는 선 포함)에서 바깥 윤곽만 띠만큼 뺀 곳.
    # inside 만 쓰면 몸을 가로지르는 아이 선(별의 모자 아래 선) 둘레가 빠져, 거기 걸친 안경이 남았다.
    lines = np.array(to_scribble(drawing, size).convert("L")) > 128
    figure = ndimage.binary_fill_holes(_close(lines | inside, size * 0.005))
    body = _erode(figure, size * 0.015)
    if body.sum() < size * size * 0.002:
        return sheet
    s = np.array(sheet.convert("RGB")).astype(np.float32)
    d = np.array(drawing.convert("RGB").resize((size, size), Image.LANCZOS)).astype(np.float32)
    s_lum, d_lum = s.mean(axis=2), d.mean(axis=2)
    s_marks = body & (s_lum < np.median(s_lum[body]) - 50)
    d_marks = body & (d_lum < np.median(d_lum[body]) - 50)
    # ① 완성 그림 표시 지우기: 표시를 뺀 몸 색을 부드럽게 퍼뜨려 채운다
    gone = _dilate(s_marks, 2) & body
    w = (body & ~gone).astype(np.float32)
    sigma = size * 0.01
    num = np.stack([ndimage.gaussian_filter(s[..., c] * w, sigma) for c in range(3)], axis=2)
    den = ndimage.gaussian_filter(w, sigma)[..., None]
    fill = np.where(den > 1e-3, num / np.maximum(den, 1e-3), np.median(s[body], axis=0))
    s[gone] = fill[gone]
    # ② 아이 표시 옮기기 (가장자리는 부드럽게)
    alpha = ndimage.gaussian_filter((_dilate(d_marks, 1) & body).astype(np.float32), 1.0)[..., None]
    s = s * (1 - alpha) + d * alpha
    return Image.fromarray(np.clip(s, 0, 255).astype(np.uint8))


def keep_unpainted(sheet, unpainted):
    """아이가 비워 둔 안쪽(종이)에 생성 그림이 색을 칠했으면 하얗게 되돌린다 (악당 얼굴의 연분홍).
    다시 그리기(캐릭터마다 수십 초) 대신 그린 뒤 고친다. 밝은 칠(최소 채널 140 이상)만 바꾸고 눈·입·선 같은 진한 부분은 둔다.
    경계는 흐리게 섞어 칠과 흰색 사이에 자국이 남지 않게 한다. 아이가 칠한 곳(종이가 아닌 곳)은 건드리지 않는다."""
    a = np.array(sheet.convert("RGB")).astype(np.float32)
    light = a.min(axis=2) > 140
    w = Image.fromarray(((unpainted & light) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(max(sheet.size) / 400))
    w = np.array(w).astype(np.float32)[..., None] / 255 * light[..., None]
    white = np.array([253, 253, 253], np.float32)
    return Image.fromarray(np.clip(a * (1 - w) + white * w, 0, 255).astype(np.uint8))


ISNET_URL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx"
# GitHub 이 안 될 때 받을 Hugging Face 복사본 (rembg 공식은 아님). 2026-11-08 GitHub 504 장애 때 확인:
# 따로 올린 두 복사본(fofr/comfyui, martintomov/comfy)의 크기·SHA256 이 같았다. 지문이 맞을 때만 쓴다.
ISNET_MIRROR = "https://huggingface.co/fofr/comfyui/resolve/main/rembg/isnet-general-use.onnx"
ISNET_SHA256 = "60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a"


class Matte:
    """학습된 배경 제거 모델 (IS-Net, rembg 가 쓰는 것과 같은 ONNX 파일). 그림 -> 눈에 띄는 물체 모양(L).
    rembg 패키지는 numpy 를 올려 버전 고정을 깨므로 onnxruntime 으로 직접 돌린다 (CPU, 1장 몇 초).
    배경 후보에서는 '눈에 띄는 물체가 어디 있나'를 재는 데도 쓴다."""

    def __init__(self, path):
        import onnxruntime as ort
        self.sess = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
        self.name = self.sess.get_inputs()[0].name

    def __call__(self, img):
        x = np.array(img.convert("RGB").resize((1024, 1024), Image.LANCZOS)).astype(np.float32)
        x = x / max(float(x.max()), 1e-6) - 0.5
        out = self.sess.run(None, {self.name: x.transpose(2, 0, 1)[None]})[0][0, 0]
        out = (out - out.min()) / max(float(out.max() - out.min()), 1e-6)
        return Image.fromarray((out * 255).astype(np.uint8)).resize(img.size, Image.BILINEAR)


def cutout_problems(sprite):
    """오려낸 결과가 '그림 자체'가 아니라 포장까지 딸려 온 경우를 찾는다 (빈 목록이면 통과).
    - card: 모양이 자기 상자의 네 변 중 셋 이상을 거의 다 채운다 = 바탕 카드·액자째 오려냄
    - band: 윤곽을 따라 하얀 층이 둘러 있는데 몸 안쪽은 하얗지 않다 = 스티커 칼선 같은 흰 테두리.
      흰 층 바깥에 가는 선이 한 줄 더 있어도(가장 바깥이 흰색이 아니어도) 잡는다.
      몸 자체가 하얀 캐릭터(하얀 유령)는 안쪽도 하얘서 걸리지 않는다."""
    alpha = np.array(sprite.getchannel("A")) > 128
    if not alpha.any():
        return ["empty"]
    ys, xs = np.nonzero(alpha)
    box = alpha[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    k = max(1, int(max(box.shape) * 0.01))                         # 상자 변에서 살짝 안쪽 줄
    sides = [box[k].mean(), box[-1 - k].mean(), box[:, k].mean(), box[:, -1 - k].mean()]
    problems = ["card"] if sum(s > 0.7 for s in sides) >= 3 else []    # 한 변은 잘림·여백으로 빌 수 있다
    rgb = np.array(sprite.convert("RGB")).astype(int)
    light = (rgb.min(axis=2) > 215) & (rgb.max(axis=2) - rgb.min(axis=2) < 25)
    depth = ndimage.distance_transform_edt(alpha) / max(box.shape)      # 윤곽에서 안쪽으로 들어간 정도 (크기 대비)
    inner = alpha & (depth > 0.06)
    layers = [alpha & (depth > a) & (depth <= a + 0.005) for a in np.arange(0, 0.04, 0.005)]
    white_layer = max((light[l].mean() for l in layers if l.sum() > 20), default=0)
    # 윤곽 근처 어느 층이 둘레의 1/4 이상 하얗고, 몸 안쪽보다 4배 이상 하얗다 = 몸 색과 상관없는 흰 테두리.
    # (지난 시험들: 악당 흰 띠 0.33~0.66 / 안쪽 0.05 이하, 하얀 주인공 0.98 / 안쪽 0.95)
    if inner.any() and white_layer >= 0.25 and white_layer >= 4 * light[inner].mean():
        problems.append("band")
    return problems


def background_clutter(img, matte):
    """흰 바탕에 혼자 그리라고 한 그림에서, 물체 바깥에 다른 것이 얼마나 그려졌나 (0 = 바탕 한 색, 1 = 전부 다른 색).
    그림체 참고 그림(장면)이 너무 세게 걸리면 풍경·풀밭·액자까지 따라 그려지는데, 그러면 오려낸 물체에 풍경 조각이 붙고
    물체도 풍경에 섞여 흐려진다. 물체에서 조금 떨어진 바깥 픽셀 중 바탕색(바깥의 가운데 색)과 뚜렷이 다른 비율로 잰다.
    수채화 번짐처럼 부드러운 풍경은 잔무늬가 없어서, 잔무늬 대신 색 차이로 본다."""
    obj = np.array(matte.convert("L").resize(img.size)) > 128
    outside = ~_dilate(obj, max(img.size) * 0.02)
    if outside.sum() < 100:
        return 0.0
    a = np.array(img.convert("RGB")).astype(int)[outside]
    return float((np.abs(a - np.median(a, axis=0)).sum(axis=1) > 40).mean())


_COLOR_NAMES = {"black": (20, 20, 20), "dark gray": (90, 90, 90), "gray": (150, 150, 150), "brown": (110, 70, 40),
                "dark brown": (70, 40, 20), "red": (210, 40, 40), "dark red": (130, 20, 30), "orange": (240, 140, 40),
                "golden yellow": (210, 160, 30), "yellow": (250, 220, 60), "green": (60, 160, 60),
                "dark green": (30, 90, 40), "blue": (50, 100, 220), "navy blue": (30, 40, 110), "purple": (130, 60, 180),
                "pink": (240, 130, 180)}


def outline_color(drawing):
    """아이 그림의 바깥 윤곽선 색 이름 (윤곽선이 없으면 None).
    scribble 은 선이 '어디에' 있는지만 알려 주고, 선의 색·굵기는 IP-Adapter 가 아이 그림을 보고 전한다.
    칠한 면 가장자리에 붙은 윤곽선(주황 몸의 갈색 테두리)은 그것만으로는 약하게 전해져 그냥 색 경계로 그려지므로,
    색을 재서 글로도 알려 준다. 바깥 테두리 띠의 색이 몸 안쪽 색과 뚜렷이 다를 때만 윤곽선으로 본다."""
    sprite = cutout(drawing)
    alpha = np.array(sprite.getchannel("A")) > 128
    if not alpha.any():
        return None
    rgb = np.array(sprite.convert("RGB")).astype(int)
    depth = ndimage.distance_transform_edt(alpha) / max(alpha.shape)
    # 오려낸 가장자리에 남는 1~2픽셀 종이(흰색) 띠는 선 색이 아니므로 뺀다
    paper = (rgb.min(axis=2) > 215) & (rgb.max(axis=2) - rgb.min(axis=2) < 25)
    ring, inner = alpha & (depth <= 0.015) & ~paper, alpha & (depth > 0.04)
    if ring.sum() < 20 or not inner.any():
        return None
    line, fill = np.median(rgb[ring], axis=0), np.median(rgb[inner], axis=0)
    if np.abs(line - fill).sum() < 120:
        return None
    return min(_COLOR_NAMES, key=lambda n: np.abs(np.array(_COLOR_NAMES[n]) - line).sum())


def to_scribble(img, size=1024, edge_tol=40):
    """아이 그림 -> ControlNet scribble 조건 (검은 바탕 흰 선).
    선은 선 그대로 꽉 찬 한 줄로, 칠한 면은 바깥 윤곽선(색 경계)만 남긴다.
    색 경계만 선으로 쓰면 굵은 선 하나가 양쪽 경계 두 줄이 되어 속 빈 이중선(관 같은 팔)으로 그려지기 때문이다.
    색 경계로 나뉜 영역마다 두께를 재서, 캐릭터 전체 크기의 5% 보다 가는 영역은 선(의 안쪽)으로 채운다.
    펜·크레용 선은 캐릭터 크기에 비해 늘 가늘고, 칠한 몸·머리는 늘 굵기 때문에 그림 크기·선 굵기와 상관없이 나뉜다.
    (눈·단추처럼 작게 칠한 점도 꽉 채워지는데, 작은 점은 그게 원래 모양이다.)
    단, 종이와 같은 색인 영역(흰 눈알, 이빨, 줄무늬 사이 빈칸)은 가늘어도 펜 선일 수 없으므로 채우지 않는다.
    마지막으로 모든 선을 뼈대로 줄여 같은 굵기로 다시 그린다 (펜 굵기와 상관없이 일정)."""
    rgb = img.convert("RGB").filter(ImageFilter.GaussianBlur(1))
    edges = np.max([np.array(ch.filter(ImageFilter.FIND_EDGES)) for ch in rgb.split()], axis=0) > edge_tol
    edges[[0, -1]] = edges[:, [0, -1]] = False                     # FIND_EDGES 가 그림 가장자리에 내는 가짜 경계

    ys, xs = np.nonzero(edges)
    if not len(ys):
        return Image.new("RGB", (size, size), "black")
    figure = max(ys.max() - ys.min(), xs.max() - xs.min())        # 그린 캐릭터 전체 크기

    # 색 경계는 뾰족한 모서리에서 몇 픽셀씩 끊긴다 -> 끊긴 틈으로 선 안쪽이 옆의 넓은 면과 이어져 면으로 잘못 잡힌다.
    # 경계를 2픽셀 불려 틈을 막고 나눈 뒤, 선으로 정한 영역은 다시 2픽셀 불려 채운다.
    labels, n = ndimage.label(~_dilate(edges, 2))
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    a = np.array(rgb).astype(int)
    paper = np.median(a[np.isin(labels, list(border))], axis=0) if border else np.array([255, 255, 255])
    strokes = np.zeros_like(edges)
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        if i in border:                                            # 종이(바탕)
            continue
        region = labels[sl] == i
        if np.abs(np.median(a[sl][region], axis=0) - paper).sum() < 60:   # 종이 색 = 칠하지 않은 곳
            continue
        thick = 2 * ndimage.distance_transform_edt(np.pad(region, 1))[1:-1, 1:-1].max()
        if thick < figure * 0.05:                                  # 가는 영역 = 선의 안쪽
            strokes[sl] |= region
    scribble = edges | _dilate(strokes, 2.5)

    # 선 굵기를 아이 그림의 펜 굵기와 상관없이 일정하게: 선의 뼈대(가운데 한 줄)를 뽑아 같은 굵기로 다시 그린다.
    # 굵은 scribble 선은 ControlNet 이 '흰 띠 + 양쪽 가는 선'으로 그려 캐릭터 둘레에 흰 테두리가 생긴다 (굵은 크레용·마커일수록 심함).
    # 두께가 가장 두꺼운 점들(거리 극대점)로 가운데 줄을 잡으면 모서리·끝에 가지가 생겨, 정식 뼈대 추출(thinning)을 쓴다.
    from skimage.morphology import skeletonize
    # 색 경계선과 선 안쪽 사이의 1~2픽셀 틈은 뼈대에 작은 고리(선 끝·이음매의 혹)를 만든다 -> 그만큼만 메운다
    center = skeletonize(_close(scribble, 2.5))
    out = Image.fromarray((center * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR)
    k = max(3, size // 150 | 1)                                    # 조건 그림 크기에 맞춘 일정한 굵기 (1024 -> 7)
    return out.point(lambda v: 255 if v > 0 else 0).filter(ImageFilter.MaxFilter(k)).convert("RGB")


# ── 2. 몸통과 팔다리 찾기 ──────────────────────────────────────────
# 모양 분석은 "몸통에서 튀어나온 부분"을 두께와 상관없이 모두 후보로 찾고 번호를 붙인다.
# 그중 무엇이 팔·다리인지는 그림을 이해하는 AI(지금 앱의 캐릭터 설명서 단계)가 정한다.
# 별 꼭짓점·귀·뿔처럼 모양만으로는 팔과 구분할 수 없는 부분이 있기 때문이다.

@dataclass
class Limb:
    id: int
    mask: np.ndarray        # 이 부분의 픽셀 (bool, 스프라이트 크기)
    pivot: tuple            # 몸통에 붙은 점 (x, y) - 여기를 축으로 돌린다
    kind: str               # 위치로 추정한 종류: "arm" | "leg" | "top" (AI 판단으로 바뀔 수 있음)
    side: str               # "left" | "right" | "center"
    movable: bool = False   # AI 가 팔·다리라고 한 후보만 True


@dataclass
class Rig:
    body: np.ndarray
    limbs: list = field(default_factory=list)
    line_color: tuple = (0, 0, 0)
    line_width: float = 4.0

    @property
    def moving(self):
        return [l for l in self.limbs if l.movable]




def find_parts(sprite):
    """몸통 = 가장 두꺼운 덩어리, 후보 = 몸통보다 가는 돌출부(선 한 줄이든 두껍게 칠한 팔이든).
    몸통 두께의 절반보다 가는 부분을 지우는 열림 연산으로 나누므로 그림 크기·선 굵기와 상관없다."""
    alpha = np.array(sprite.getchannel("A")) > 128
    h, w = alpha.shape
    rgb = np.array(sprite.convert("RGB")).astype(int)

    # 선 색·굵기: 팔을 떼어낸 어깨 자리에 윤곽선을 이어 그릴 때 쓴다
    ink = ~((rgb.sum(axis=2) > 600) & (rgb.max(axis=2) - rgb.min(axis=2) < 40)) & alpha   # 흰 번짐 제외
    ring = _dilate(alpha & ~_erode(alpha, 12), 2) & ink
    ring_px = rgb[ring] if ring.any() else rgb[alpha]
    lum = ring_px.sum(axis=1)
    line_color = np.median(ring_px[lum <= np.median(lum)], axis=0)
    line = ink & (np.abs(rgb - line_color).sum(axis=2) < 120)
    line_width = 2 * np.percentile(ndimage.distance_transform_edt(line)[line], 95) if line.any() else 4.0

    torso = ndimage.distance_transform_edt(alpha).max()          # 몸통 반지름 정도
    core = _open(alpha, max(2, torso * 0.5))
    labels, n = ndimage.label(core)
    if n == 0:
        return Rig(body=alpha, line_color=tuple(line_color), line_width=line_width)
    core = labels == (int(np.argmax(ndimage.sum(core, labels, range(1, n + 1)))) + 1)
    body = _dilate(core, 2) & alpha
    body &= ~_joined_legs(body)

    by, bx = np.nonzero(body)
    top, bottom, cx = by.min(), by.max(), bx.mean()
    body_h = bottom - top + 1
    near_body = _dilate(body, 4)
    dist_to_body = ndimage.distance_transform_edt(~body)

    labels, n = ndimage.label(alpha & ~body)
    found = []
    for i in range(1, n + 1):
        part = labels == i
        # 몸통 가장자리 부스러기는 몸통으로. 넓이만 보면 막대 선으로 그린 팔(길지만 픽셀 수가 적음)이 부스러기로 잘못 합쳐진다
        # (2026-11-08 Kaggle: 배경 제거 모델로 오려 선이 가늘어지자 주인공·악당 팔이 모두 사라져 자세·행동이 안 먹음).
        # 작은 조각이라도 몸통에서 멀리(몸통 키의 8% 이상) 뻗어 나가면 후보로 둔다.
        # (선 굵기는 기준으로 쓰지 않는다: 윤곽선 없이 칠한 몸은 몸 전체가 '선'으로 재여 굵기가 몸통만큼 나온다)
        # 몸통과 떨어진 작은 점(그림 구석의 잡티)은 팔이 아니므로, 작은 조각은 몸통 가까이(키의 5% 안)에서 시작해야 한다.
        if part.sum() < alpha.sum() * 0.008:
            near = dist_to_body[part]
            if near.max() < body_h * 0.08 or near.min() > body_h * 0.05:
                body |= part
                continue
        py, px = np.nonzero(part)
        contact = part & near_body
        if contact.any():
            cy_c, cx_c = np.nonzero(contact)
            pivot = (float(cx_c.mean()), float(cy_c.mean()))
        else:                                     # 몸통과 떨어져 그린 부분: 몸통에 가장 가까운 점을 축으로
            k = dist_to_body[py, px].argmin()
            pivot = (float(px[k]), float(py[k]))
        dy = py.mean() - pivot[1]
        rel_y = (pivot[1] - top) / body_h         # 몸통의 어느 높이에 붙었나 (0 = 맨 위, 1 = 맨 아래)
        side = "left" if px.mean() < cx - w * 0.05 else "right" if px.mean() > cx + w * 0.05 else "center"
        if (rel_y > 0.75 and dy > 0) or py.mean() > bottom:
            kind = "leg"
        elif (rel_y < 0.3 and dy < 0) or py.mean() < top:
            kind = "top"
        else:
            kind = "arm"
        found.append((py.mean(), px.mean(), part, pivot, kind, side))

    found.sort(key=lambda f: (round(f[0] / (h / 4)), f[1]))        # 위→아래, 왼→오른 순으로 번호
    limbs = [Limb(i + 1, part, pivot, kind, side) for i, (_, _, part, pivot, kind, side) in enumerate(found)]
    return Rig(body=body, limbs=limbs, line_color=tuple(int(v) for v in line_color), line_width=float(line_width))


def _joined_legs(body):
    """붙여 그린 두 다리: 몸통만큼 두꺼운 다리 덩어리는 '가장 두꺼운 덩어리'인 몸통에 흡수된다.
    몸통 아래 윤곽에서 아래로 열린 가장 깊은 홈(사타구니)을 찾아, 그 높이 아래를 홈 왼쪽·오른쪽으로 떼어 낸다.
    떼어 낸 부분은 다른 돌출부처럼 후보가 되고, 정말 다리인지는 AI 판단(또는 설명서의 다리 개수)이 정한다.
    홈 깊이가 몸통 키의 5% 보다 얕으면 그냥 둥근 몸 아래의 굴곡으로 본다."""
    rows = np.arange(body.shape[0])[:, None]
    has = body.any(axis=0)
    xs = np.nonzero(has)[0]
    none = np.zeros_like(body)
    if len(xs) < 5:
        return none
    bottom = np.where(body, rows, -1).max(axis=0)[xs].astype(float)    # 열마다 몸통 맨 아래
    # 홈 깊이 = 양쪽에서 가장 낮게 내려온 곳 중 덜 내려온 쪽 - 이 열의 바닥 (물을 부으면 고이는 깊이)
    left = np.maximum.accumulate(bottom)
    right = np.maximum.accumulate(bottom[::-1])[::-1]
    depth = np.minimum(left, right) - bottom
    k = int(depth.argmax())
    by = np.nonzero(body.any(axis=1))[0]
    if depth[k] < (by.max() - by.min()) * 0.05:
        return none
    apex_x, apex_y = xs[k], int(bottom[k])
    below = body & (rows > apex_y)
    cols = np.arange(body.shape[1])[None, :]
    legs = (below & (cols < apex_x)) | (below & (cols > apex_x))
    return legs


def choose_limbs(rig, arms=None, legs=None, labels=None):
    """움직일 후보를 정한다.
    labels: AI 가 번호로 답한 경우 {"arms": [2, 3], "legs": [5, 6]}
    arms/legs: 설명서에 개수만 있는 경우 - 위치로 추정한 종류가 맞는 후보 중 큰 것부터 고른다
    둘 다 없으면 아무것도 움직이지 않는다 (팔을 만들지 않는다)."""
    for l in rig.limbs:
        l.movable = False
    if labels:
        for key, kind in (("arms", "arm"), ("legs", "leg")):
            for l in rig.limbs:
                if l.id in labels.get(key, []):
                    l.kind, l.movable = kind, True
        return rig
    for kind, count in (("arm", arms or 0), ("leg", legs or 0)):
        cands = sorted([l for l in rig.limbs if l.kind == kind], key=lambda l: -l.mask.sum())
        for l in cands[:count]:
            l.movable = True
    return rig


def analyze(sprite, arms=None, legs=None, labels=None):
    return choose_limbs(find_parts(sprite), arms, legs, labels)


def numbered_overlay(sprite, rig):
    """AI 에게 보여줄 그림: 후보마다 다른 색과 번호를 칠한다."""
    palette = [(230, 60, 60), (40, 150, 230), (40, 170, 70), (240, 160, 30), (160, 80, 210),
               (20, 180, 180), (230, 90, 170), (120, 120, 120)]
    base = Image.alpha_composite(Image.new("RGBA", sprite.size, "white"), sprite)
    over = np.array(base.convert("RGB"))
    for l in rig.limbs:
        over[l.mask] = (over[l.mask] * 0.4 + np.array(palette[(l.id - 1) % len(palette)]) * 0.6).astype(np.uint8)
    out = Image.fromarray(over)
    d = ImageDraw.Draw(out)
    fs = max(14, sprite.width // 14)
    for l in rig.limbs:
        ys, xs = np.nonzero(l.mask)
        x, y = xs.mean(), ys.mean()
        d.ellipse((x - fs * 0.7, y - fs * 0.7, x + fs * 0.7, y + fs * 0.7), fill="white", outline="black", width=2)
        d.text((x - fs * 0.25, y - fs * 0.45), str(l.id), fill="black")
    return out


# 지금 앱의 캐릭터 설명서(GPT 비전) 요청에 함께 넣을 질문. 두 번째 이미지로 numbered_overlay 를 보낸다.
LIMB_QUESTION = (
    "The second image shows the same drawing with numbered colored regions that stick out from the body. "
    "Which numbers are ARMS and which are LEGS that the child actually drew? Thick arms count as arms. "
    "Ears, horns, hair, star points, fins, tails, wings and decorations are NOT arms or legs. "
    'Answer only JSON like {"arms": [2, 3], "legs": [5, 6]}; use empty lists if none.'
)


# ── 3. 자세 ───────────────────────────────────────────────────────
# 처음 그린 각도와 상관없이 "어느 방향을 가리키게 할지"를 정한다 (그래서 이미 위로 뻗은 팔도 몸 뒤로 숨지 않는다).
# arm: 바깥쪽 수평선 기준 높이(도). 양수 = 위로, 음수 = 아래로.  leg: 바로 아래 기준 바깥으로 벌린 각도(도).
# tilt: 몸 전체 기울기(양수 = 왼쪽으로).  stretch: (가로, 세로) 배율.
# 지정하지 않은 팔다리는 그린 그대로 둔다. 팔다리가 없는 캐릭터는 tilt·stretch 만으로 표현된다.
POSES = {
    "stand":  {},
    "wave":   {"arm": {"right": 60}, "tilt": 4},
    "cheer":  {"arm": {"left": 65, "right": 65}, "stretch": (0.97, 1.05)},
    "walk":   {"arm": {"left": -55, "right": -25}, "leg": {"left": 22, "right": -6}, "tilt": -5},
    "jump":   {"arm": {"left": 40, "right": 40}, "leg": {"left": 8, "right": 8}, "stretch": (0.93, 1.08), "float": True},
    "sad":    {"arm": {"left": -75, "right": -75}, "tilt": -7, "stretch": (1.03, 0.95)},
    "scared": {"arm": {"left": 25, "right": 25}, "tilt": 8, "stretch": (0.92, 0.94)},
}

# 줄거리 문장 -> 자세. 앱에서는 언어 모델이 장면마다 이 목록 중 하나를 고르게 하면 된다.
_KEYWORDS = [
    ("wave", ["wave", "waving", "hello", "greet", "인사", "손을 흔", "손 흔"]),
    ("jump", ["jump", "leap", "hop", "bounce", "뛰어오", "점프", "폴짝", "뛰"]),
    ("cheer", ["cheer", "celebrat", "dance", "danc", "happy", "hooray", "춤", "기뻐", "환호", "만세"]),
    ("walk", ["walk", "run", "go ", "going", "stroll", "걷", "걸어", "달리", "갔"]),
    ("sad", ["sad", "cry", "tear", "lonely", "슬프", "울", "외로"]),
    ("scared", ["scared", "afraid", "fear", "surpris", "tremb", "무서", "놀라", "떨"]),
]


def pose_from_action(text):
    t = (text or "").lower()
    for name, words in _KEYWORDS:
        if any(w in t for w in words):
            return name
    return "stand"


def _limb_angle(limb, target):
    """지금 가리키는 방향에서 목표 방향까지 돌릴 각도(반시계 +). 화면 좌표는 y 가 아래로 커서 부호를 뒤집는다."""
    ys, xs = np.nonzero(limb.mask)
    current = np.degrees(np.arctan2(-(ys.mean() - limb.pivot[1]), xs.mean() - limb.pivot[0]))
    if limb.kind == "arm":
        goal = target if limb.side == "right" else 180 - target
    else:
        goal = -90 + target if limb.side == "right" else -90 - target
    return (goal - current + 180) % 360 - 180


def _hinge(limb, body, angle):
    """돌리는 축 = 몸통과 붙은 면에서 '접히는 쪽' 끝 (팔을 내리면 아래 모서리, 올리면 위 모서리).
    붙은 면 한가운데를 축으로 돌리면 굵은 팔일수록 반쪽이 몸통 안으로 쓸려 들어가고,
    몸통 가까이 거의 안 움직이는 팔 윤곽선 조각이 새 팔 모양 안쪽에 남는다 (흰 점·검은 자국).
    실제 어깨처럼 접히는 쪽 모서리를 축으로 하면 팔 굵기와 상관없이 몸 바깥으로 접힌다. 다리도 같다."""
    contact = limb.mask & _dilate(body, 4)
    if not contact.any() or abs(angle) < 1:
        return limb.pivot
    cy, cx = np.nonzero(contact)
    ly, lx = np.nonzero(limb.mask)
    ux, uy = lx.mean() - limb.pivot[0], -(ly.mean() - limb.pivot[1])     # 축 -> 팔 방향 (y 위로)
    nx, ny = -uy, ux                                                      # 그 왼쪽(반시계) 방향
    side = np.sign(angle) * ((cx - limb.pivot[0]) * nx + (-(cy - limb.pivot[1])) * ny)
    k = side.argmax()
    return (float(cx[k]), float(cy[k]))


def _smoothstep(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def _bend(canvas, rig, moving, pad):
    """자르지 않고 팔·다리를 고무처럼 휘게 한다.
    몸통은 그대로 두고, 팔·다리 영역에 촘촘한 삼각형 그물을 씌워 꼭짓점을 옮긴다.
    몸통 경계에서는 전혀 움직이지 않고(0), 멀어질수록 목표 각도까지 돌아가므로(1)
    어깨가 늘어나며 휘어질 뿐 끊기거나 잘린 자국이 생기지 않는다."""
    W, H = canvas.size
    sh, sw = rig.body.shape
    rgba = np.array(canvas).astype(float) / 255
    rgba[..., :3] *= rgba[..., 3:4]                 # 알파를 곱해 두면 가장자리가 검게 번지지 않는다
    visible = rgba[..., 3] > 0

    still = np.zeros((H, W), bool)                 # 움직이지 않는 부분 (몸통 + 움직이지 않는 후보)
    still[pad:pad + sh, pad:pad + sw] = rig.body
    for l in rig.limbs:
        if not l.movable:
            still[pad:pad + sh, pad:pad + sw] |= l.mask
    d_out = ndimage.distance_transform_edt(~still)
    limb_d = []
    for limb, _ in moving:
        m = np.zeros((H, W), bool)
        m[pad:pad + sh, pad:pad + sw] = limb.mask
        limb_d.append(ndimage.distance_transform_edt(~m))
    limb_d = np.array(limb_d)
    nearest = limb_d.argmin(axis=0)

    body_layer = rgba.copy()
    limb_layers = []
    step = max(4, min(sw, sh) // 60)
    for k, (limb, angle) in enumerate(moving):
        # 이 팔다리의 몫: 움직이지 않는 부분보다 이 팔다리에 더 가까운 바깥 영역
        owned = ~still & (nearest == k) & (limb_d[k] < d_out)
        region = owned & _dilate(visible, 3)
        if not region.any():
            continue
        body_layer[owned] = 0
        thickness = 2 * ndimage.distance_transform_edt(limb.mask).max()
        ly, lx = np.nonzero(limb.mask)
        length = np.hypot(lx - limb.pivot[0], ly - limb.pivot[1]).max()
        # 어깨에서 휘어지는 구간의 길이. 팔 길이의 40% 를 넘으면 짧고 굵은 팔이 갈고리처럼 말리므로 제한한다
        band = min(max(thickness * 1.5, min(sw, sh) * 0.08), length * 0.4)
        weight = np.where(owned, _smoothstep(d_out / band), 0.0)
        # 몸통 층에서 지운 경계와 팔 층의 경계가 둘 다 반투명이면 겹쳐도 1픽셀 틈이 비친다.
        # 팔 층이 경계 너머 2픽셀을 더 가져가 몸통과 겹치게 한다 (경계 근처는 거의 움직이지 않아 자국이 없다)
        src_img = rgba * (owned | (_dilate(owned, 2) & still))[..., None]
        cx, cy = limb.pivot[0] + pad, limb.pivot[1] + pad
        th = np.radians(angle)

        ys, xs = np.nonzero(region)
        x0, x1 = xs.min() - step, xs.max() + step
        y0, y1 = ys.min() - step, ys.max() + step
        gx = np.arange(x0, x1 + step, step, dtype=float)
        gy = np.arange(y0, y1 + step, step, dtype=float)
        vx, vy = np.meshgrid(gx, gy)
        wv = ndimage.map_coordinates(weight, [vy, vx], order=1, mode="constant", cval=0.0)
        dx, dy = vx - cx, vy - cy
        rx = cx + dx * np.cos(th) + dy * np.sin(th)            # 화면에서 반시계 방향 회전
        ry = cy - dx * np.sin(th) + dy * np.cos(th)
        ux, uy = vx + wv * (rx - vx), vy + wv * (ry - vy)      # 옮긴 꼭짓점

        cell_has = ndimage.maximum_filter(region.astype(np.uint8), size=step * 2 + 1)
        layer = np.zeros_like(rgba)
        # 크게 접으면 굽는 안쪽이 바깥쪽보다 덜 돌아서 그물 삼각형이 뒤집혀 겹친다(접힘).
        # 뒤집힌 삼각형은 팔 아랫선·가장자리를 팔 안쪽에 다시 그리므로, 먼저 그리고 정상 삼각형으로 덮는다.
        # 접힌 부분은 늘 정상 면과 겹쳐 있으므로 덮으면 사라지고, 정상 면이 없는 곳만 뒤집힌 그림이 남아 빈틈을 메운다.
        normal, folded = [], []
        for i in range(len(gy) - 1):
            for j in range(len(gx) - 1):
                cyc, cxc = int(min(max(gy[i] + step / 2, 0), H - 1)), int(min(max(gx[j] + step / 2, 0), W - 1))
                if not cell_has[cyc, cxc]:
                    continue
                for tri in (((i, j), (i, j + 1), (i + 1, j)), ((i, j + 1), (i + 1, j + 1), (i + 1, j))):
                    src = [(vx[a, b], vy[a, b]) for a, b in tri]
                    dst = [(ux[a, b], uy[a, b]) for a, b in tri]
                    (normal if _signed_area(src) * _signed_area(dst) > 0 else folded).append((src, dst))
        for src, dst in folded + normal:
            _raster_triangle(layer, src_img, src, dst)
        limb_layers.append(layer)

    out = body_layer
    for layer in limb_layers:                      # 팔다리를 몸통 위에 얹는다 (알파를 곱한 상태의 over 합성)
        out = layer + out * (1 - layer[..., 3:4])
    alpha = out[..., 3:4]
    out[..., :3] = np.where(alpha > 1e-3, out[..., :3] / np.maximum(alpha, 1e-3), 0)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGBA")


def _signed_area(tri):
    (x1, y1), (x2, y2), (x3, y3) = tri
    return (x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)


def _raster_triangle(dst_img, src_img, src_tri, dst_tri):
    """옮긴 삼각형(dst) 안의 픽셀마다 원래 삼각형(src)의 같은 자리를 찾아 색을 가져온다."""
    H, W = dst_img.shape[:2]
    (x1, y1), (x2, y2), (x3, y3) = dst_tri
    bx0, bx1 = int(max(np.floor(min(x1, x2, x3)), 0)), int(min(np.ceil(max(x1, x2, x3)), W - 1))
    by0, by1 = int(max(np.floor(min(y1, y2, y3)), 0)), int(min(np.ceil(max(y1, y2, y3)), H - 1))
    if bx1 < bx0 or by1 < by0:
        return
    det = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3)
    if abs(det) < 1e-6:
        return
    py, px = np.mgrid[by0:by1 + 1, bx0:bx1 + 1].astype(float)
    l1 = ((y2 - y3) * (px - x3) + (x3 - x2) * (py - y3)) / det
    l2 = ((y3 - y1) * (px - x3) + (x1 - x3) * (py - y3)) / det
    l3 = 1 - l1 - l2
    inside = (l1 >= -1e-3) & (l2 >= -1e-3) & (l3 >= -1e-3)
    if not inside.any():
        return
    (sx1, sy1), (sx2, sy2), (sx3, sy3) = src_tri
    sx = l1 * sx1 + l2 * sx2 + l3 * sx3
    sy = l1 * sy1 + l2 * sy2 + l3 * sy3
    iy, ix = py[inside].astype(int), px[inside].astype(int)
    for c in range(4):
        dst_img[iy, ix, c] = ndimage.map_coordinates(src_img[..., c], [sy[inside], sx[inside]], order=1, mode="constant")


def pose(sprite, rig, name):
    """자세를 적용한 RGBA 스프라이트를 돌려준다. 'float' 자세는 .info['float'] = True 로 표시."""
    spec = POSES.get(name, {})
    w, h = sprite.size
    pad = int(max(w, h) * 0.45)                    # 팔이 들려도 잘리지 않게 여유
    W, H = w + 2 * pad, h + 2 * pad

    # AI 가 팔·다리라고 한 후보만 움직인다. 축은 접히는 쪽 모서리(_hinge)로 옮긴 사본을 쓴다
    hinged = {}
    for limb in rig.limbs:
        if limb.movable and limb.side in spec.get(limb.kind, {}):
            angle = _limb_angle(limb, spec[limb.kind][limb.side])
            hinged[id(limb)] = (replace(limb, pivot=_hinge(limb, rig.body, angle)), angle)
    moving = list(hinged.values())
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.paste(sprite, (pad, pad))
    if moving:
        canvas = _bend(canvas, rig, moving, pad)

    # 소품을 붙일 자리: 머리 꼭대기 = 몸통 맨 윗부분 (귀·뿔·머리카락 같은 후보는 몸통이 아니므로 빠진다),
    # 손 = 팔 후보에서 어깨(축)로부터 가장 먼 점. 그림과 똑같이 돌리고 늘이고 기울여 자세 적용 뒤 좌표로 옮긴다.
    # 몸통에 합쳐 둔 가장자리 부스러기가 머리로 잡히지 않게, 가장 큰 덩어리만 본다
    labels, n = ndimage.label(rig.body)
    core = labels == (np.argmax(ndimage.sum(rig.body, labels, range(1, n + 1))) + 1) if n > 1 else rig.body
    by, bx = np.nonzero(core)
    top = by.min()
    points = {"head": (float(bx[by <= top + max(2, (by.max() - top) * 0.03)].mean()) + pad, float(top) + pad)}
    for limb in rig.limbs:
        if limb.movable and limb.kind == "arm":
            ly, lx = np.nonzero(limb.mask)
            k = np.hypot(lx - limb.pivot[0], ly - limb.pivot[1]).argmax()
            p = (lx[k] + pad, ly[k] + pad)
            if id(limb) in hinged:                 # 팔 끝은 휘는 구간 밖이라 목표 각도만큼 그대로 돈다
                moved, angle = hinged[id(limb)]
                p = _rotate_point(p, (moved.pivot[0] + pad, moved.pivot[1] + pad), angle)
            points[f"hand_{limb.side}"] = p

    sx, sy = spec.get("stretch", (1.0, 1.0))
    if (sx, sy) != (1.0, 1.0):                     # 발바닥 기준으로 늘이거나 줄인다
        bbox = canvas.getbbox()
        part = canvas.crop(bbox)
        part = part.resize((max(1, int(part.width * sx)), max(1, int(part.height * sy))), Image.LANCZOS)
        canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ox, oy = int((bbox[0] + bbox[2] - part.width) / 2), bbox[3] - part.height
        canvas.paste(part, (ox, oy), part)
        kx, ky = part.width / (bbox[2] - bbox[0]), part.height / (bbox[3] - bbox[1])
        points = {n: (ox + (x - bbox[0]) * kx, oy + (y - bbox[1]) * ky) for n, (x, y) in points.items()}
    if spec.get("tilt"):
        bbox = canvas.getbbox()
        center = ((bbox[0] + bbox[2]) / 2, bbox[3])
        canvas = canvas.rotate(spec["tilt"], center=center, resample=Image.BICUBIC)
        points = {n: _rotate_point(p, center, spec["tilt"]) for n, p in points.items()}

    bbox = canvas.getbbox()
    out = canvas.crop(bbox)
    out.info["float"] = bool(spec.get("float"))
    out.info["points"] = {n: (x - bbox[0], y - bbox[1]) for n, (x, y) in points.items()}
    return out


def _rotate_point(p, center, degrees):
    """화면에서 반시계 방향으로 degrees 만큼 돌린 점 (_bend 의 꼭짓점 회전, PIL rotate 와 같은 방향)."""
    th = np.radians(degrees)
    dx, dy = p[0] - center[0], p[1] - center[1]
    return (center[0] + dx * np.cos(th) + dy * np.sin(th), center[1] - dx * np.sin(th) + dy * np.cos(th))


def debug_view(sprite, rig):
    """분석 결과 확인용: 몸통 파랑, 움직이는 팔 빨강·다리 초록, 움직이지 않는 후보 회색, 축은 검은 점."""
    colors = {"arm": (230, 60, 60), "leg": (40, 170, 70)}
    a = np.zeros((*rig.body.shape, 3), np.uint8)
    a[rig.body] = (70, 120, 230)
    for l in rig.limbs:
        a[l.mask] = colors.get(l.kind, (150, 150, 150)) if l.movable else (170, 170, 170)
    img = Image.fromarray(a).convert("RGBA")
    img.putalpha(sprite.getchannel("A"))
    bg = Image.new("RGBA", img.size, "white")
    out = Image.alpha_composite(bg, img)
    d = ImageDraw.Draw(out)
    for l in rig.moving:
        x, y = l.pivot
        d.ellipse((x - 5, y - 5, x + 5, y + 5), fill="black")
    return out.convert("RGB")
