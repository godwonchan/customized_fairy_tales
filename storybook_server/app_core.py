from typing import Optional, List
from datetime import datetime
from pathlib import Path
import os
import json
import re
import mimetypes

from dotenv import load_dotenv
from pydantic import BaseModel, Field as PydanticField
from sqlmodel import SQLModel, Field, Session, create_engine, select

# =========================
# 0. 환경변수 로드
# =========================
load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_TEXT_MODEL = os.getenv("OPENAI_TEXT_MODEL", "gpt-5.5")
OPENAI_IMAGE_MODEL = os.getenv("OPENAI_IMAGE_MODEL", "gpt-image-1")

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
    book_id: Optional[str] = None
    title: str
    original_title: Optional[str] = None
    language: Optional[str] = None
    total_pages: Optional[int] = None
    description: Optional[str] = None
    source_folder: Optional[str] = None

    content: str = ""
    last_confirmed_change: Optional[str] = None

    is_user_story: bool = False
    parent_story_id: Optional[int] = None

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
    is_cover: bool = False

    original_text_content: Optional[str] = None
    text_content: Optional[str] = None

    original_image_data: Optional[bytes] = None
    original_image_mime_type: Optional[str] = None
    original_image_filename: Optional[str] = None

    image_data: Optional[bytes] = None
    image_mime_type: Optional[str] = None
    image_filename: Optional[str] = None

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class StoryPlot(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    story_id: int = Field(index=True, foreign_key="story.id")
    plot_number: int
    summary: str

    image_status: str = Field(default="pending")
    image_error: Optional[str] = None

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class StoryPlotContent(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    story_id: int = Field(index=True, foreign_key="story.id")
    plot_id: int = Field(index=True, foreign_key="storyplot.id")
    plot_number: int
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class StoryPlotImage(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    story_id: int = Field(index=True, foreign_key="story.id")
    plot_id: int = Field(index=True, foreign_key="storyplot.id")
    plot_number: int

    image_prompt: str
    style_reference_page_numbers: Optional[str] = None

    image_data: Optional[bytes] = None
    image_mime_type: Optional[str] = None
    image_filename: Optional[str] = None

    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


# =========================
# 3. API 스키마
# =========================
class StoryListItem(BaseModel):
    id: int
    book_id: Optional[str]
    title: str
    original_title: Optional[str]
    total_pages: Optional[int]
    source_folder: Optional[str]
    is_user_story: bool
    parent_story_id: Optional[int]
    created_at: datetime
    updated_at: datetime


class StoryRead(BaseModel):
    id: int
    book_id: Optional[str]
    title: str
    original_title: Optional[str]
    language: Optional[str]
    total_pages: Optional[int]
    description: Optional[str]
    source_folder: Optional[str]
    content: str
    last_confirmed_change: Optional[str]
    is_user_story: bool
    parent_story_id: Optional[int]
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


class StoryPageRead(BaseModel):
    id: int
    story_id: int
    page_number: int
    is_cover: bool
    original_text_content: Optional[str]
    text_content: Optional[str]
    image_filename: Optional[str]
    image_mime_type: Optional[str]
    created_at: datetime
    updated_at: datetime


class SketchInterpretResponse(BaseModel):
    story_id: int
    page_number: int
    selected_text: str
    interpreted_request: str


class ScenePreviewImageRequest(BaseModel):
    selected_text: str
    interpreted_request: str
    style_request: Optional[str] = None


class ScenePreviewImageResponse(BaseModel):
    story_id: int
    page_number: int
    prompt: str
    image_mime_type: str
    message: str


class PlotRearrangeRequest(BaseModel):
    plot_count: int = PydanticField(..., ge=1, le=20)
    style_request: Optional[str] = None


class StoryPlotRead(BaseModel):
    id: int
    story_id: int
    plot_number: int
    summary: str
    image_status: str
    image_error: Optional[str]
    created_at: datetime
    updated_at: datetime


class PlotRearrangeResponse(BaseModel):
    story_id: int
    title: str
    plot_count: int
    required_changes: Optional[str]
    plots: List[StoryPlotRead]


class PlotContentGenerateRequest(BaseModel):
    style_request: Optional[str] = None


class StoryPlotContentRead(BaseModel):
    id: int
    story_id: int
    plot_id: int
    plot_number: int
    content: str
    created_at: datetime
    updated_at: datetime


class PlotContentGenerateResponse(BaseModel):
    story_id: int
    count: int
    required_changes: Optional[str]
    contents: List[StoryPlotContentRead]


class PlotImageGenerateRequest(BaseModel):
    style_request: Optional[str] = None


class StoryPlotImageRead(BaseModel):
    id: int
    story_id: int
    plot_id: int
    plot_number: int
    image_prompt: str
    style_reference_page_numbers: Optional[str]
    image_filename: Optional[str]
    image_mime_type: Optional[str]
    created_at: datetime
    updated_at: datetime


class PlotImageGenerationStatusItem(BaseModel):
    plot_number: int
    image_status: str
    image_error: Optional[str] = None


class PlotImageGenerationStatusResponse(BaseModel):
    story_id: int
    total: int
    completed: int
    failed: int
    processing: int
    progress_percent: int
    current_plot_number: Optional[int] = None
    status: str
    plots: List[PlotImageGenerationStatusItem]


# =========================
# 4. 공통 유틸
# =========================
def build_story_content_from_pages(page_texts: List[str]) -> str:
    return " ".join([t.strip() for t in page_texts if t and t.strip()])


def normalize_image_mime_type(upload_file) -> str:
    content_type = getattr(upload_file, "content_type", None)

    if content_type and content_type.startswith("image/"):
        return content_type

    filename = getattr(upload_file, "filename", "") or ""
    guessed, _ = mimetypes.guess_type(filename)
    if guessed and guessed.startswith("image/"):
        return guessed

    return "image/png"


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


def get_style_reference_pages(session: Session, story_id: int) -> List[StoryPage]:
    return session.exec(
        select(StoryPage)
        .where(StoryPage.story_id == story_id)
        .where(StoryPage.original_image_data != None)  # noqa: E711
        .order_by(StoryPage.page_number)
    ).all()


def pick_reference_pages_for_style(
    session: Session,
    story_id: int,
    current_page_number: int,
) -> List[StoryPage]:
    pages = get_style_reference_pages(session, story_id)

    refs: List[StoryPage] = []

    cover = next((p for p in pages if p.is_cover), None)
    if cover:
        refs.append(cover)

    normal_pages = [
        p for p in pages
        if not p.is_cover and p.page_number != current_page_number
    ]

    refs.extend(normal_pages[:2])
    return refs


def build_style_reference_hint(reference_pages: List[StoryPage]) -> str:
    if not reference_pages:
        return "기존 동화 이미지 reference 없음"

    page_numbers = [str(p.page_number) for p in reference_pages]
    cover_text = "cover 이미지 포함" if "0" in page_numbers else "cover 이미지 없음"

    return (
        f"스타일 reference 페이지 번호: {', '.join(page_numbers)}. "
        f"{cover_text}. 기존 동화의 그림체, 캐릭터 표현 방식, 색감, 분위기와 유사하게 유지해야 함."
    )


def collect_style_reference_images(reference_pages: List[StoryPage]) -> List[dict]:
    refs = []
    for p in reference_pages:
        if p.original_image_data and p.original_image_mime_type:
            refs.append(
                {
                    "page_number": p.page_number,
                    "image_data": p.original_image_data,
                    "mime_type": p.original_image_mime_type,
                }
            )
    return refs


# =========================
# 5. 초기 데이터 import
# =========================
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
            metadata = {}

            if metadata_path.exists():
                try:
                    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
                except Exception:
                    metadata = {}

            title = metadata.get("title", story_folder.name)
            page_map = {}
            cover_file = None

            for file in story_folder.iterdir():
                if not file.is_file():
                    continue

                if "cover" in file.stem.lower() and file.suffix.lower() in [".png", ".jpg", ".jpeg", ".webp"]:
                    cover_file = file
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
                book_id=metadata.get("book_id"),
                title=title,
                original_title=metadata.get("original_title"),
                language=metadata.get("language"),
                total_pages=metadata.get("total_pages"),
                description=metadata.get("description"),
                source_folder=story_folder.name,
                content=story_content,
                last_confirmed_change=None,
                is_user_story=False,
                parent_story_id=None,
            )
            session.add(story)
            session.commit()
            session.refresh(story)

            if cover_file:
                cover_mime, _ = mimetypes.guess_type(str(cover_file))
                cover_bytes = cover_file.read_bytes()
                cover_page = StoryPage(
                    story_id=story.id,
                    page_number=0,
                    is_cover=True,
                    original_text_content=None,
                    text_content=None,
                    original_image_data=cover_bytes,
                    original_image_mime_type=cover_mime or "application/octet-stream",
                    original_image_filename=cover_file.name,
                    image_data=cover_bytes,
                    image_mime_type=cover_mime or "application/octet-stream",
                    image_filename=cover_file.name,
                )
                session.add(cover_page)

            for page_number, page_data in sorted(page_map.items()):
                page = StoryPage(
                    story_id=story.id,
                    page_number=page_number,
                    is_cover=False,
                    original_text_content=page_data["text_content"],
                    text_content=page_data["text_content"],
                    original_image_data=page_data["image_data"],
                    original_image_mime_type=page_data["image_mime_type"],
                    original_image_filename=page_data["image_filename"],
                    image_data=page_data["image_data"],
                    image_mime_type=page_data["image_mime_type"],
                    image_filename=page_data["image_filename"],
                )
                session.add(page)

            session.commit()