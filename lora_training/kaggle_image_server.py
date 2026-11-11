# %% [markdown]
# # 우리 모델 그림 서버 (전시용)
#
# 앱에서 '그림 그리는 방법'을 **우리 모델**로 고르면, 기존 서버(`storybook_server`)가 동화 그림을 gpt-image 대신 이 노트북에 맡긴다.
# 이 노트북은 모델을 한 번 올려 두고, 맡겨진 동화를 한 권씩 그려 돌려준다 (그리는 코드는 `story_pipeline.py` - 시험 노트북과 같은 파일).
#
# 사용법
# 1. GPU T4 x2, Internet On 으로 **Run All** (모델 받기·올리기 약 2~3분)
# 2. ③ 셀이 출력하는 두 줄을 기존 서버의 `storybook_server/.env` 에 붙이고 서버를 다시 켠다 (IMAGE_ENGINE 은 넣지 않는다)
#    `LOCAL_IMAGE_URL=https://....trycloudflare.com` / `LOCAL_IMAGE_TOKEN=...`
# 3. ④ 셀은 멈추지 않고 계속 돈다 (서버가 살아 있는 동안). 끝나면 세션 끄기(⏻)
# 4. (문제 볼 때) ④를 멈추고 ⑤를 실행하면 중간 그림(debug.zip)을 받는다. 서버는 그대로 켜져 있다
#
# 주의: 주소는 노트북을 켤 때마다 바뀐다. Kaggle 세션은 최대 12시간, GPU 는 주 30시간.
# "Save Version"(백그라운드 실행)이 아니라 편집 화면에서 직접 실행해야 서버가 계속 살아 있다.

# %%
# ① 설치 - 버전 고정 (2026-11-04 시험 노트북에서 성공한 조합) + 웹 서버(기존 서버와 같은 버전) + 터널 프로그램
!pip install -q diffusers==0.42.1 transformers==5.22.1 accelerate peft onnxruntime fastapi==0.135.3 uvicorn==0.44.0
!pip uninstall -y -q torchao
# Cloudflare 임시 터널: 계정 없이 https 주소를 하나 받아 이 노트북의 서버로 연결해 준다
!wget -q -O /kaggle/working/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
!chmod +x /kaggle/working/cloudflared

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

# %% [writefile image_server.py]

# %%
# ② 모델 불러오기 (한 번만)
import sys

sys.path.insert(0, "/kaggle/working")
from story_pipeline import StoryPipeline

SAVE_DEBUG = True    # 칸마다 배경 후보·캐릭터 원본 등을 /kaggle/working/debug 에 저장 (시험 기간에는 켜 둔다, 전시 때는 False)
pipe = StoryPipeline(save_dir="/kaggle/working/debug" if SAVE_DEBUG else None).load()

# %%
# ③ 서버 켜기 + 터널 주소 받기
import re
import secrets
import subprocess
import threading

import uvicorn
from image_server import create_app

TOKEN = secrets.token_urlsafe(24)    # 터널 주소는 인터넷에 열려 있으므로, 이 값을 아는 서버만 그림을 맡길 수 있다
server = uvicorn.Server(uvicorn.Config(create_app(pipe, TOKEN), host="0.0.0.0", port=8000, log_level="warning"))
threading.Thread(target=server.run, daemon=True).start()

tunnel = subprocess.Popen(["/kaggle/working/cloudflared", "tunnel", "--url", "http://localhost:8000", "--no-autoupdate"],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
URL = None
for line in tunnel.stdout:
    m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", line)
    if m:
        URL = m.group(0)
        break
# 터널 로그를 계속 비워 줘야 터널이 멈추지 않는다
threading.Thread(target=lambda: [None for _ in tunnel.stdout], daemon=True).start()

print("아래 두 줄을 storybook_server/.env 에 붙이고 서버를 다시 켜세요 (앱에서 '우리 모델'을 고르면 이 서버로 그립니다):\n")
print(f"LOCAL_IMAGE_URL={URL}")
print(f"LOCAL_IMAGE_TOKEN={TOKEN}")

# %%
# ④ 계속 켜 두기 - 이 셀이 도는 동안 서버가 산다. 1분마다 살아 있다고 알린다
import time

while True:
    time.sleep(60)
    print(time.strftime("%H:%M"), "그림 서버 동작 중", flush=True)

# %%
# ⑤ (문제 볼 때) 중간 그림 내려받기 - ④ 셀을 멈춘(■) 뒤 이 셀을 실행한다. ④를 멈춰도 서버는 계속 켜져 있다
# 같은 이름 파일은 다음 동화가 덮어쓰므로, 본 동화 바로 뒤에 받는다
import os

from IPython.display import FileLink

os.chdir("/kaggle/working")
!zip -qr debug.zip debug
FileLink("debug.zip")
