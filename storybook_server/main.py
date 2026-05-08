from typing import Optional, List
from datetime import datetime
from pathlib import Path
import os

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sqlmodel import SQLModel, Field, Session, create_engine, select
from google import genai
import time
import os
from google.genai.errors import ServerError

# =========================
# 0. 환경변수 로드
# =========================
load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise RuntimeError("GEMINI_API_KEY가 .env에 설정되지 않았습니다.")

client = genai.Client(api_key=GEMINI_API_KEY)

# =========================
# 1. DB 설정
# =========================
BASE_DIR = Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "stories.db"
DATABASE_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(DATABASE_URL, echo=False)


# =========================
# 2. DB 모델
# =========================
class Story(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# =========================
# 3. 요청/응답 스키마
# =========================
class StoryCreate(BaseModel):
    title: str
    content: str


class StoryRead(BaseModel):
    id: int
    title: str
    content: str
    created_at: datetime
    updated_at: datetime


class StoryListItem(BaseModel):
    id: int
    title: str
    created_at: datetime
    updated_at: datetime


class StoryReviseRequest(BaseModel):
    user_request: str


class StoryReviseResponse(BaseModel):
    id: int
    title: str
    original_content: str
    revised_content: str
    user_request: str


# =========================
# 4. 앱 생성
# =========================
app = FastAPI(title="Storybook Server with Gemini")


@app.on_event("startup")
def on_startup():
    SQLModel.metadata.create_all(engine)


# =========================
# 5. 유틸 함수
# =========================
def revise_story_with_gemini(original_story: str, user_request: str) -> str:
    prompt = f"""
너는 아동용 동화를 다듬는 편집 도우미야.

규칙:
1. 기존 이야기의 전체 흐름은 최대한 유지한다.
2. 사용자 요청만 반영해서 자연스럽게 수정한다.
3. 너무 어렵지 않은 한국어로 쓴다.
4. 설명하지 말고, 수정된 동화 본문만 출력한다.

[기존 동화]
{original_story}

[사용자 요청]
{user_request}
""".strip()

    print("=== KEY EXISTS ===", os.getenv("GEMINI_API_KEY") is not None)
    print("=== START GEMINI CALL ===")

    last_error = None

    for wait_sec in [2, 5, 10]:
        try:
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
            )

            print("=== RAW RESPONSE ===")
            print(response)
            print("=== RESPONSE TEXT ===")
            print(getattr(response, "text", None))

            if getattr(response, "text", None):
                return response.text.strip()

            raise RuntimeError(f"Gemini 응답에서 text를 받지 못했습니다. response={response}")

        except ServerError as e:
            print("=== SERVER ERROR ===")
            print(repr(e))
            last_error = e
            time.sleep(wait_sec)

    raise last_error if last_error else RuntimeError("Gemini 호출 실패")

# =========================
# 6. 엔드포인트
# =========================
@app.get("/")
def root():
    return {"message": "Storybook server is running"}


@app.post("/stories", response_model=StoryRead)
def create_story(payload: StoryCreate):
    with Session(engine) as session:
        story = Story(
            title=payload.title,
            content=payload.content,
        )
        session.add(story)
        session.commit()
        session.refresh(story)
        return story


@app.get("/stories", response_model=List[StoryListItem])
def list_stories():
    with Session(engine) as session:
        stories = session.exec(
            select(Story).order_by(Story.created_at.desc())
        ).all()

        return [
            StoryListItem(
                id=s.id,
                title=s.title,
                created_at=s.created_at,
                updated_at=s.updated_at,
            )
            for s in stories
        ]


@app.post("/stories/{story_id}/revise", response_model=StoryReviseResponse)
def revise_story(story_id: int, payload: StoryReviseRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)

        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        original_content = story.content

        try:
            revised_content = revise_story_with_gemini(
                original_story=original_content,
                user_request=payload.user_request,
            )
        except Exception as e:
            print("=== GEMINI ERROR ===")
            print(repr(e))
            raise HTTPException(status_code=500, detail=f"Gemini 호출 실패: {repr(e)}")
        story.content = revised_content
        story.updated_at = datetime.utcnow()

        session.add(story)
        session.commit()
        session.refresh(story)

        return StoryReviseResponse(
            id=story.id,
            title=story.title,
            original_content=original_content,
            revised_content=revised_content,
            user_request=payload.user_request,
        )

print("KEY EXISTS:", os.getenv("GEMINI_API_KEY") is not None)