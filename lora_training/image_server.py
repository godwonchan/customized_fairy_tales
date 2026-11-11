"""Kaggle 그림 서버: 기존 서버(storybook_server)가 동화 한 권을 맡기면 우리 모델로 그려서 돌려준다.

    POST /jobs           {"characters": {id: {"image_b64", "desc", "arms", "legs"}}, "plan": {"pages": [...]}}
                         -> {"job_id": "..."}
    POST /characters     {"characters": {...}} -> {"job_id": "..."}   캐릭터 완성만 미리 (그림 결과는 돌려주지 않고 캐시에 둔다).
                         아이가 그림을 다 그렸을 때 기존 서버가 보낸다 -> 나중에 동화를 맡기면 같은 그림·설명은 다시 그리지 않는다
    GET  /jobs/{job_id}  -> {"status": "queued" | "running" | "done" | "error", "pages": [{"page", "image_b64"}], "error"}
    GET  /health         -> {"ok": true, "queued": n}

모든 요청은 헤더 X-Token 이 맞아야 한다 (터널 주소는 인터넷에 열려 있으므로).
Cloudflare 임시 터널은 응답을 100초까지만 기다려서, 동화 한 권(약 5분)은 '맡기고 끝났는지 묻는' 방식으로 주고받는다.
GPU 는 한 번에 한 권만 그린다 - 뒤에 온 요청은 줄을 선다.
"""
import base64
import io
import queue
import threading
import time
import traceback
import uuid

from fastapi import FastAPI, Header, HTTPException
from PIL import Image

KEEP_DONE = 20      # 끝난 작업 결과는 최근 것만 들고 있는다 (메모리)


def _decode(b64):
    if "," in b64:
        b64 = b64.split(",", 1)[1]
    return Image.open(io.BytesIO(base64.b64decode(b64)))


def _encode(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def create_app(pipe, token):
    app = FastAPI()
    jobs = {}
    waiting = queue.Queue()

    def check(x_token):
        if x_token != token:
            raise HTTPException(status_code=401, detail="token")

    def worker():
        while True:
            job_id, body = waiting.get()
            job = jobs[job_id]
            job["status"], t0 = "running", time.perf_counter()
            try:
                characters = {k: dict(v, image=_decode(v["image_b64"])) for k, v in body["characters"].items()}
                assets = pipe.make_characters(characters)
                if "plan" not in body:                  # 캐릭터 미리 그리기만
                    job["status"] = "done"
                    print(f"✅ 작업 {job_id[:8]} 캐릭터 미리 그리기 완료: {list(characters)}, "
                          f"{time.perf_counter() - t0:.0f}초", flush=True)
                    continue
                pictures = pipe.make_book(body["plan"], assets)
                numbers = [p.get("page", i + 1) for i, p in enumerate(body["plan"].get("pages", []))]
                job["pages"] = [{"page": n, "image_b64": _encode(img)} for n, img in zip(numbers, pictures)]
                job["status"] = "done"
                print(f"✅ 작업 {job_id[:8]} 완료: {len(pictures)}페이지, {time.perf_counter() - t0:.0f}초", flush=True)
            except Exception as e:
                job["status"], job["error"] = "error", f"{type(e).__name__}: {e}"
                traceback.print_exc()
            finally:
                done =[k for k, j in jobs.items() if j["status"] in ("done", "error")]
                for k in done[:-KEEP_DONE]:
                    jobs.pop(k, None)

    threading.Thread(target=worker, daemon=True).start()

    @app.get("/health")
    def health(x_token: str = Header(default="")):
        check(x_token)
        return {"ok": True, "queued": waiting.qsize()}

    @app.post("/jobs")
    def submit(body: dict, x_token: str = Header(default="")):
        check(x_token)
        if not body.get("plan", {}).get("pages") or not isinstance(body.get("characters"), dict):
            raise HTTPException(status_code=400, detail="plan.pages 와 characters 가 필요합니다")
        job_id = uuid.uuid4().hex
        jobs[job_id] = {"status": "queued", "pages": [], "error": None}
        waiting.put((job_id, body))
        print(f"📥 작업 {job_id[:8]} 접수: {len(body['plan']['pages'])}페이지, 캐릭터 {list(body['characters'])}", flush=True)
        return {"job_id": job_id}

    @app.post("/characters")
    def prepare(body: dict, x_token: str = Header(default="")):
        check(x_token)
        chars = body.get("characters")
        if not isinstance(chars, dict) or not chars:
            raise HTTPException(status_code=400, detail="characters 가 필요합니다")
        job_id = uuid.uuid4().hex
        jobs[job_id] = {"status": "queued", "pages": [], "error": None}
        waiting.put((job_id, {"characters": chars}))   # 동화와 같은 줄 - GPU 는 한 번에 하나, 뒤에 온 동화는 이것을 기다렸다가 캐시를 쓴다
        print(f"📥 작업 {job_id[:8]} 접수: 캐릭터 미리 그리기 {list(chars)}", flush=True)
        return {"job_id": job_id}

    @app.get("/jobs/{job_id}")
    def status(job_id: str, x_token: str = Header(default="")):
        check(x_token)
        if job_id not in jobs:
            raise HTTPException(status_code=404, detail="job")
        return jobs[job_id]

    return app
