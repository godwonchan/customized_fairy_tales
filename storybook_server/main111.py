from typing import Optional, List
from datetime import datetime
from pathlib import Path
import os
import time
import json
import re
import mimetypes

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
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
# 1. 경로 및 DB 설정
# =========================
BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = BASE_DIR / "stories.db"
DATABASE_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(DATABASE_URL, echo=False)


# =========================
# 2. DB 모델
# =========================
class Story(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str
    source_folder: Optional[str] = None
    content: str = ""  # 현재 최신 전체 줄거리
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

    text_content: Optional[str] = None

    # 이미지를 DB에 직접 저장
    image_data: Optional[bytes] = None
    image_mime_type: Optional[str] = None
    image_filename: Optional[str] = None

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# =========================
# 3. 요청/응답 스키마
# =========================
class StoryListItem(BaseModel):
    id: int
    title: str
    source_folder: Optional[str]
    created_at: datetime
    updated_at: datetime


class StoryRead(BaseModel):
    id: int
    title: str
    source_folder: Optional[str]
    content: str
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
    text_content: Optional[str]
    image_filename: Optional[str]
    image_mime_type: Optional[str]
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
    original_content: Optional[str]
    revised_content: str
    user_request: str


# =========================
# 4. 앱 생성
# =========================
app = FastAPI(title="Storybook Server with Gemini")


# =========================
# 5. 유틸 함수
# =========================
def build_story_content_from_pages(page_texts: List[str]) -> str:
    return " ".join([t.strip() for t in page_texts if t and t.strip()])


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


def generate_story_pages_with_gemini(
    story_content: str,
    page_count: int,
    style_request: Optional[str] = None
) -> List[str]:
    extra_style = style_request if style_request else "아동용 그림책처럼 짧고 부드럽게 써라."

    prompt = f"""
너는 아동용 동화책의 페이지 구성을 담당하는 편집자야.

아래 전체 줄거리를 바탕으로 총 {page_count}페이지의 동화책 내용을 만들어라.

규칙:
1. 각 페이지는 2~4문장 정도로 작성한다.
2. 페이지 간 흐름이 자연스럽게 이어져야 한다.
3. 너무 어렵지 않은 한국어를 사용한다.
4. 설명 문장 없이 페이지 본문만 출력한다.
5. 반드시 아래 형식 중 하나로 출력한다.

출력 형식 예시 1:
[PAGE 1]
첫 번째 페이지 내용

[PAGE 2]
두 번째 페이지 내용

출력 형식 예시 2:
PAGE 1:
첫 번째 페이지 내용

PAGE 2:
두 번째 페이지 내용

추가 스타일 요청:
{extra_style}

[전체 줄거리]
{story_content}
""".strip()

    raw_text = call_gemini_with_retry(prompt)
    print("=== PAGE RAW TEXT ===")
    print(raw_text)

    lines = [line.strip() for line in raw_text.splitlines() if line.strip()]
    pages: List[str] = []
    current_lines: List[str] = []

    def is_page_header(line: str) -> bool:
        upper = line.upper()
        return (
            (upper.startswith("[PAGE ") and upper.endswith("]")) or
            upper.startswith("PAGE ")
        )

    for line in lines:
        if is_page_header(line):
            if current_lines:
                pages.append(" ".join(current_lines).strip())
                current_lines = []
        else:
            current_lines.append(line)

    if current_lines:
        pages.append(" ".join(current_lines).strip())

    if len(pages) < page_count:
        raise RuntimeError(
            f"페이지 파싱 실패: 요청={page_count}, 생성={len(pages)}, raw_text={raw_text}"
        )

    if len(pages) > page_count:
        pages = pages[:page_count]

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


def import_story_folders_if_empty():
    if not DATA_DIR.exists():
        print("data 폴더가 없습니다.")
        return

    with Session(engine) as session:
        existing_story = session.exec(select(Story)).first()
        if existing_story:
            return

        for story_folder in DATA_DIR.iterdir():
            if not story_folder.is_dir():
                continue

            metadata_path = story_folder / "metadata.json"
            title = story_folder.name

            if metadata_path.exists():
                try:
                    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                    title = metadata.get("title", title)
                except Exception:
                    pass

            page_map = {}

            for file in story_folder.iterdir():
                if not file.is_file():
                    continue

                match = re.search(r"_(\d+)", file.name)
                if not match:
                    continue

                page_number = int(match.group(1))

                if page_number not in page_map:
                    page_map[page_number] = {
                        "text_content": None,
                        "image_data": None,
                        "image_mime_type": None,
                        "image_filename": None,
                    }

                if file.name.endswith("_text.txt"):
                    page_map[page_number]["text_content"] = file.read_text(encoding="utf-8")

                elif file.suffix.lower() in [".png", ".jpg", ".jpeg", ".webp"]:
                    page_map[page_number]["image_data"] = file.read_bytes()
                    page_map[page_number]["image_filename"] = file.name
                    mime_type, _ = mimetypes.guess_type(str(file))
                    page_map[page_number]["image_mime_type"] = mime_type or "application/octet-stream"

            ordered_page_texts = [
                page_map[k]["text_content"]
                for k in sorted(page_map.keys())
                if page_map[k]["text_content"]
            ]
            story_content = build_story_content_from_pages(ordered_page_texts)

            story = Story(
                title=title,
                source_folder=story_folder.name,
                content=story_content,
            )
            session.add(story)
            session.commit()
            session.refresh(story)

            for page_number, page_data in sorted(page_map.items()):
                page = StoryPage(
                    story_id=story.id,
                    page_number=page_number,
                    text_content=page_data["text_content"],
                    image_data=page_data["image_data"],
                    image_mime_type=page_data["image_mime_type"],
                    image_filename=page_data["image_filename"],
                )
                session.add(page)

            session.commit()


# =========================
# 6. 시작 시 초기화
# =========================
@app.on_event("startup")
def on_startup():
    SQLModel.metadata.create_all(engine)
    import_story_folders_if_empty()
    print("KEY EXISTS:", os.getenv("GEMINI_API_KEY") is not None)


# =========================
# 7. API 엔드포인트
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
                source_folder=s.source_folder,
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

        # 기존 페이지 삭제
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
                text_content=content,
                image_data=None,
                image_mime_type=None,
                image_filename=None,
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
                    text_content=p.text_content,
                    image_filename=p.image_filename,
                    image_mime_type=p.image_mime_type,
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
                text_content=p.text_content,
                image_filename=p.image_filename,
                image_mime_type=p.image_mime_type,
                created_at=p.created_at,
                updated_at=p.updated_at,
            )
            for p in pages
        ]


@app.get("/stories/{story_id}/pages/{page_number}", response_model=StoryPageRead)
def get_story_page(story_id: int, page_number: int):
    with Session(engine) as session:
        page = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.page_number == page_number)
        ).first()

        if not page:
            raise HTTPException(status_code=404, detail="해당 페이지를 찾을 수 없습니다.")

        return StoryPageRead(
            id=page.id,
            story_id=page.story_id,
            page_number=page.page_number,
            text_content=page.text_content,
            image_filename=page.image_filename,
            image_mime_type=page.image_mime_type,
            created_at=page.created_at,
            updated_at=page.updated_at,
        )


@app.get("/stories/{story_id}/pages/{page_number}/image")
def get_story_page_image(story_id: int, page_number: int):
    with Session(engine) as session:
        page = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.page_number == page_number)
        ).first()

        if not page or not page.image_data:
            raise HTTPException(status_code=404, detail="이미지가 없습니다.")

        return Response(
            content=page.image_data,
            media_type=page.image_mime_type or "application/octet-stream"
        )


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

        original_content = page.text_content or ""

        try:
            revised_content = revise_page_with_gemini(
                page_content=original_content,
                user_request=payload.user_request,
            )
        except Exception as e:
            print("=== PAGE REVISE ERROR ===")
            print(repr(e))
            raise HTTPException(status_code=500, detail=f"페이지 수정 실패: {repr(e)}")

        page.text_content = revised_content
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