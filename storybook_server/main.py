from typing import Optional, List
from datetime import datetime
from pathlib import Path
import os
import time

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field as PydanticField
from sqlmodel import SQLModel, Field, Session, create_engine, select
from google import genai
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
# 2. 기본 동화 데이터
# =========================
PRELOADED_STORIES = [
    {
        "title": "인어공주",
        "content": (
            "깊고 푸른 바다 속 왕국에 아름다운 인어공주가 살고 있었어요. "
            "인어공주는 바다 위 인간 세상을 늘 동경했어요. "
            "열다섯 살이 된 어느 날, 인어공주는 처음으로 바다 위로 올라가게 되었고, "
            "폭풍우 속에서 한 왕자를 발견했어요. "
            "인어공주는 물에 빠진 왕자를 구해 해변으로 데려다주고, "
            "멀리서 그가 무사하길 바라며 지켜보았어요. "
            "그 뒤로 인어공주는 왕자를 잊지 못했고, 인간이 되어 그의 곁에 가고 싶다고 생각했어요. "
            "결국 인어공주는 바다 마녀를 찾아가 자신의 아름다운 목소리를 주는 대신 인간의 다리를 얻게 되었어요. "
            "하지만 인간이 된 인어공주는 걸을 때마다 날카로운 칼 위를 걷는 듯한 고통을 견뎌야 했어요. "
            "인어공주는 왕자 곁에 머물렀지만, 왕자는 자신을 구해준 이가 다른 공주라고 믿고 "
            "그 공주와 결혼하게 되었어요. "
            "바다로 돌아갈 수 없게 된 인어공주는 마지막 기회를 얻었어요. "
            "왕자를 죽이면 다시 인어로 돌아갈 수 있었지만, 인어공주는 끝내 왕자를 해치지 못했어요. "
            "인어공주는 새벽 바다로 몸을 던졌고, 결국 바다의 거품이 되어 사라졌어요."
        ),
    },
    {
        "title": "신데렐라",
        "content": (
            "작은 마을에 마음씨 착한 신데렐라가 살고 있었어요. "
            "신데렐라는 힘든 하루하루를 보내면서도 언제나 희망을 잃지 않았어요. "
            "어느 날 왕궁 무도회가 열린다는 소식이 전해졌고, 신데렐라는 자신의 삶도 달라질 수 있다는 작은 기대를 품게 되었어요. "
            "요정의 도움으로 무도회에 가게 된 신데렐라는 뜻밖의 만남을 통해 새로운 미래를 마주하게 되었어요."
        ),
    },
]

# =========================
# 3. DB 모델
# =========================
class Story(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class StoryVersion(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    story_id: int = Field(index=True, foreign_key="story.id")
    version_number: int
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class StoryPage(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    story_id: int = Field(index=True, foreign_key="story.id")
    page_number: int
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

# =========================
# 4. 요청/응답 스키마
# =========================
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


class StoryRevisePreviewResponse(BaseModel):
    id: int
    title: str
    original_content: str
    revised_content: str
    user_request: str


class StoryApplyRevisionRequest(BaseModel):
    revised_content: str


class StoryVersionRead(BaseModel):
    id: int
    story_id: int
    version_number: int
    content: str
    created_at: datetime


class StoryRollbackResponse(BaseModel):
    story_id: int
    title: str
    restored_version_number: int
    content: str
    updated_at: datetime


class PageGenerateRequest(BaseModel):
    page_count: int = PydanticField(..., ge=1, le=20)
    style_request: Optional[str] = None


class StoryPageRead(BaseModel):
    id: int
    story_id: int
    page_number: int
    content: str
    created_at: datetime
    updated_at: datetime


class PageGenerateResponse(BaseModel):
    story_id: int
    title: str
    page_count: int
    pages: List[StoryPageRead]


class PageReviseRequest(BaseModel):
    user_request: str


class PageReviseResponse(BaseModel):
    story_id: int
    page_number: int
    original_content: str
    revised_content: str
    user_request: str

# =========================
# 5. 앱 생성
# =========================
app = FastAPI(title="Storybook Server with Gemini")

# =========================
# 6. 유틸 함수
# =========================
def call_gemini_with_retry(prompt: str, model_name: str = "gemini-2.5-flash") -> str:
    last_error = None

    for wait_sec in [2, 5, 10]:
        try:
            response = client.models.generate_content(
                model=model_name,
                contents=prompt,
            )

            if getattr(response, "text", None):
                return response.text.strip()

            raise RuntimeError(f"Gemini 응답에서 text를 받지 못했습니다. response={response}")

        except ServerError as e:
            print("=== SERVER ERROR ===")
            print(repr(e))
            last_error = e
            time.sleep(wait_sec)

    raise last_error if last_error else RuntimeError("Gemini 호출 실패")


def revise_story_with_gemini(original_story: str, user_request: str) -> str:
    prompt = f"""
너는 아동용 동화를 다듬는 편집 도우미야.

규칙:
1. 기존 이야기의 전체 흐름은 최대한 유지한다.
2. 사용자 요청만 반영해서 자연스럽게 수정한다.
3. 너무 어렵지 않은 한국어로 쓴다.
4. 설명하지 말고 수정된 동화 본문만 출력한다.

[기존 동화]
{original_story}

[사용자 요청]
{user_request}
""".strip()

    return call_gemini_with_retry(prompt)


def generate_story_pages_with_gemini(story_content: str, page_count: int, style_request: Optional[str] = None) -> List[str]:
    extra_style = style_request if style_request else "아동용 그림책처럼 짧고 부드럽게 써라."

    prompt = f"""
너는 아동용 동화책의 페이지 구성을 담당하는 편집자야.

아래 전체 줄거리를 바탕으로 총 {page_count}페이지의 동화책 내용을 만들어라.

규칙:
1. 각 페이지는 2~4문장 정도로 작성한다.
2. 페이지 간 흐름이 자연스럽게 이어져야 한다.
3. 너무 어렵지 않은 한국어를 사용한다.
4. 설명 문장 없이 페이지 본문만 출력한다.
5. 반드시 아래 형식을 지킨다.

출력 형식:
[PAGE 1]
첫 번째 페이지 내용

[PAGE 2]
두 번째 페이지 내용

...

추가 스타일 요청:
{extra_style}

[전체 줄거리]
{story_content}
""".strip()

    raw_text = call_gemini_with_retry(prompt)

    pages: List[str] = []
    current_lines: List[str] = []

    for line in raw_text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        if stripped.startswith("[PAGE ") and stripped.endswith("]"):
            if current_lines:
                pages.append(" ".join(current_lines).strip())
                current_lines = []
        else:
            current_lines.append(stripped)

    if current_lines:
        pages.append(" ".join(current_lines).strip())

    if len(pages) != page_count:
        raise RuntimeError(
            f"페이지 파싱 실패: 요청={page_count}, 생성={len(pages)}, raw_text={raw_text}"
        )

    return pages


def revise_page_with_gemini(page_content: str, user_request: str) -> str:
    prompt = f"""
너는 아동용 동화책의 특정 페이지 내용을 수정하는 편집자야.

규칙:
1. 기존 페이지의 핵심 장면은 유지한다.
2. 사용자 요청만 반영해서 자연스럽게 수정한다.
3. 너무 길지 않게 작성한다.
4. 설명 없이 수정된 페이지 본문만 출력한다.

[기존 페이지 내용]
{page_content}

[사용자 요청]
{user_request}
""".strip()

    return call_gemini_with_retry(prompt)


def save_story_version(session: Session, story: Story) -> StoryVersion:
    versions = session.exec(
        select(StoryVersion)
        .where(StoryVersion.story_id == story.id)
        .order_by(StoryVersion.version_number.desc())
    ).all()

    next_version_number = 1 if not versions else versions[0].version_number + 1

    version = StoryVersion(
        story_id=story.id,
        version_number=next_version_number,
        content=story.content,
    )
    session.add(version)
    session.commit()
    session.refresh(version)
    return version


def seed_stories_if_empty():
    with Session(engine) as session:
        existing_story = session.exec(select(Story)).first()
        if existing_story:
            return

        for item in PRELOADED_STORIES:
            story = Story(
                title=item["title"],
                content=item["content"],
            )
            session.add(story)

        session.commit()

# =========================
# 7. 시작 시 초기화
# =========================
@app.on_event("startup")
def on_startup():
    SQLModel.metadata.create_all(engine)
    seed_stories_if_empty()
    print("KEY EXISTS:", os.getenv("GEMINI_API_KEY") is not None)

# =========================
# 8. 엔드포인트
# =========================
@app.get("/")
def root():
    return {"message": "Storybook server is running"}


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


@app.get("/stories/{story_id}", response_model=StoryRead)
def get_story(story_id: int):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")
        return story


@app.post("/stories/{story_id}/revise-preview", response_model=StoryRevisePreviewResponse)
def revise_story_preview(story_id: int, payload: StoryReviseRequest):
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

        return StoryRevisePreviewResponse(
            id=story.id,
            title=story.title,
            original_content=original_content,
            revised_content=revised_content,
            user_request=payload.user_request,
        )


@app.post("/stories/{story_id}/apply-revision", response_model=StoryRead)
def apply_story_revision(story_id: int, payload: StoryApplyRevisionRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)

        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        save_story_version(session, story)

        story.content = payload.revised_content
        story.updated_at = datetime.utcnow()

        session.add(story)
        session.commit()
        session.refresh(story)

        return story


@app.get("/stories/{story_id}/versions", response_model=List[StoryVersionRead])
def list_story_versions(story_id: int):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        versions = session.exec(
            select(StoryVersion)
            .where(StoryVersion.story_id == story_id)
            .order_by(StoryVersion.version_number.desc())
        ).all()

        return [
            StoryVersionRead(
                id=v.id,
                story_id=v.story_id,
                version_number=v.version_number,
                content=v.content,
                created_at=v.created_at,
            )
            for v in versions
        ]


@app.post("/stories/{story_id}/rollback/{version_id}", response_model=StoryRollbackResponse)
def rollback_story_to_version(story_id: int, version_id: int):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        version = session.get(StoryVersion, version_id)
        if not version or version.story_id != story_id:
            raise HTTPException(status_code=404, detail="복원할 버전을 찾을 수 없습니다.")

        save_story_version(session, story)

        story.content = version.content
        story.updated_at = datetime.utcnow()

        session.add(story)
        session.commit()
        session.refresh(story)

        return StoryRollbackResponse(
            story_id=story.id,
            title=story.title,
            restored_version_number=version.version_number,
            content=story.content,
            updated_at=story.updated_at,
        )


@app.post("/stories/{story_id}/pages/generate", response_model=PageGenerateResponse)
def generate_story_pages(story_id: int, payload: PageGenerateRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        try:
            page_contents = generate_story_pages_with_gemini(
                story_content=story.content,
                page_count=payload.page_count,
                style_request=payload.style_request,
            )
        except Exception as e:
            print("=== PAGE GENERATION ERROR ===")
            print(repr(e))
            raise HTTPException(status_code=500, detail=f"페이지 생성 실패: {repr(e)}")

        old_pages = session.exec(
            select(StoryPage).where(StoryPage.story_id == story_id)
        ).all()
        for old_page in old_pages:
            session.delete(old_page)
        session.commit()

        saved_pages: List[StoryPage] = []
        for idx, content in enumerate(page_contents, start=1):
            page = StoryPage(
                story_id=story_id,
                page_number=idx,
                content=content,
            )
            session.add(page)
            saved_pages.append(page)

        session.commit()

        for page in saved_pages:
            session.refresh(page)

        return PageGenerateResponse(
            story_id=story.id,
            title=story.title,
            page_count=payload.page_count,
            pages=[
                StoryPageRead(
                    id=p.id,
                    story_id=p.story_id,
                    page_number=p.page_number,
                    content=p.content,
                    created_at=p.created_at,
                    updated_at=p.updated_at,
                )
                for p in sorted(saved_pages, key=lambda x: x.page_number)
            ],
        )


@app.get("/stories/{story_id}/pages", response_model=List[StoryPageRead])
def get_story_pages(story_id: int):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        pages = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .order_by(StoryPage.page_number)
        ).all()

        return [
            StoryPageRead(
                id=p.id,
                story_id=p.story_id,
                page_number=p.page_number,
                content=p.content,
                created_at=p.created_at,
                updated_at=p.updated_at,
            )
            for p in pages
        ]


@app.post("/stories/{story_id}/pages/{page_number}/revise", response_model=PageReviseResponse)
def revise_story_page(story_id: int, page_number: int, payload: PageReviseRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        page = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.page_number == page_number)
        ).first()

        if not page:
            raise HTTPException(status_code=404, detail="해당 페이지를 찾을 수 없습니다.")

        original_content = page.content

        try:
            revised_content = revise_page_with_gemini(
                page_content=original_content,
                user_request=payload.user_request,
            )
        except Exception as e:
            print("=== PAGE REVISE ERROR ===")
            print(repr(e))
            raise HTTPException(status_code=500, detail=f"페이지 수정 실패: {repr(e)}")

        page.content = revised_content
        page.updated_at = datetime.utcnow()

        session.add(page)
        session.commit()
        session.refresh(page)

        return PageReviseResponse(
            story_id=story_id,
            page_number=page_number,
            original_content=original_content,
            revised_content=revised_content,
            user_request=payload.user_request,
        )
