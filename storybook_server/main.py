from typing import Optional, List
from datetime import datetime
from pathlib import Path
import os
import time
import json
import re
import mimetypes
import base64

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.responses import Response
from pydantic import BaseModel, Field as PydanticField
from sqlmodel import SQLModel, Field, Session, create_engine, select
from google import genai
from google.genai import types
from google.genai.errors import ServerError

# =========================
# 0. 환경변수 로드
# =========================
load_dotenv()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
if not GEMINI_API_KEY:
    raise RuntimeError("GEMINI_API_KEY가 .env에 설정되지 않았습니다.")

# 텍스트 모델 / 이미지 모델은 .env 에서 바꾸기
GEMINI_TEXT_MODEL = os.getenv("GEMINI_TEXT_MODEL", "gemini-2.5-flash")
GEMINI_IMAGE_MODEL = os.getenv("GEMINI_IMAGE_MODEL", "gemini-image-model")

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
    book_id: Optional[str] = None
    title: str
    original_title: Optional[str] = None
    language: Optional[str] = None
    total_pages: Optional[int] = None
    description: Optional[str] = None
    source_folder: Optional[str] = None

    # 최신 전체 줄거리
    content: str = ""

    # 최근 사용자 확정 변경사항
    last_confirmed_change: Optional[str] = None

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

    text_content: Optional[str] = None

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
# 3. 요청/응답 스키마
# =========================
class StoryListItem(BaseModel):
    id: int
    book_id: Optional[str]
    title: str
    original_title: Optional[str]
    total_pages: Optional[int]
    source_folder: Optional[str]
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
    confirmed_request: Optional[str] = None


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


class SketchRevisionPreviewRequest(BaseModel):
    page_number: int
    selected_text: str
    confirmed_request: str


class SketchRevisionPreviewResponse(BaseModel):
    story_id: int
    page_number: int
    selected_text: str
    confirmed_request: str
    original_content: str
    revised_content: str


class PlotRearrangeRequest(BaseModel):
    plot_count: int = PydanticField(..., ge=1, le=20)
    style_request: Optional[str] = None


class StoryPlotRead(BaseModel):
    id: int
    story_id: int
    plot_number: int
    summary: str
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

# =========================
# 4. 앱 생성
# =========================
app = FastAPI(title="Storybook Server with Gemini")

# =========================
# 5. 유틸 함수
# =========================
def build_story_content_from_pages(page_texts: List[str]) -> str:
    return " ".join([t.strip() for t in page_texts if t and t.strip()])


def call_gemini_with_retry(prompt: str, model_name: Optional[str] = None) -> str:
    if model_name is None:
        model_name = GEMINI_TEXT_MODEL

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


def interpret_sketch_with_gemini(
    selected_text: str,
    page_text: str,
    image_bytes: bytes,
    mime_type: str
) -> str:
    prompt = f"""
너는 아동용 동화 편집 보조 도우미야.

사용자가 동화의 특정 텍스트를 밑줄치고, 그 부분을 바꾸고 싶어서 낙서를 그렸다.
너의 역할은 낙서를 해석해서 사용자가 무엇으로 바꾸고 싶어 하는지 짧은 한국어 문장으로 정리하는 것이다.

규칙:
1. 반드시 밑줄친 텍스트를 기준으로 바꾸고 싶은 내용을 해석한다.
2. 답변은 한 문장으로 짧게 작성한다.
3. "selected_text를 ~로 바꾸고 싶다" 형태로 작성한다.
4. 설명, 추측 과정, 부가 문장은 쓰지 않는다.

[밑줄친 텍스트]
{selected_text}

[해당 페이지 내용]
{page_text}
""".strip()

    response = client.models.generate_content(
        model=GEMINI_TEXT_MODEL,
        contents=[
            prompt,
            types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
        ],
    )

    if not getattr(response, "text", None):
        raise RuntimeError(f"낙서 해석 실패: response={response}")

    return response.text.strip()


def revise_story_from_confirmed_sketch_request(
    original_story: str,
    selected_text: str,
    confirmed_request: str
) -> str:
    prompt = f"""
너는 아동용 동화를 다듬는 편집 도우미야.

사용자가 동화의 특정 부분을 낙서를 통해 바꾸고 싶어 했다.
낙서 해석 결과는 이미 사용자에게 확인받은 상태다.
따라서 아래의 확정된 변경 요청을 반영해서 전체 동화를 자연스럽게 다시 써라.

규칙:
1. 전체 이야기 흐름은 최대한 자연스럽게 유지한다.
2. 밑줄친 대상과 관련된 장면들만 일관되게 수정한다.
3. 사용자 확인이 끝난 변경 요청을 기준으로 반영한다.
4. 너무 어렵지 않은 한국어로 쓴다.
5. 설명하지 말고 수정된 동화 본문만 출력한다.

[기존 전체 동화]
{original_story}

[변경 대상 텍스트]
{selected_text}

[사용자 확인 완료된 변경 요청]
{confirmed_request}
""".strip()

    return call_gemini_with_retry(prompt)


def rearrange_plots_with_gemini(
    story_content: str,
    plot_count: int,
    required_changes: Optional[str] = None,
    style_request: Optional[str] = None
) -> List[str]:
    extra_style = style_request if style_request else "아동용 동화 구조에 맞게 핵심 장면을 나눠라."
    must_keep = required_changes if required_changes else "없음"

    prompt = f"""
너는 아동용 동화의 플롯 구조를 재배치하는 편집자야.

아래 전체 줄거리를 바탕으로 총 {plot_count}개의 플롯 요약을 만들어라.

중요:
아래 '반드시 유지할 변경 사항'은 사용자가 직접 수정한 핵심 내용이다.
이 내용은 절대로 삭제하거나 축약하거나 다른 표현으로 약화하면 안 된다.
특히 수정된 행동, 대상, 순서, 결과를 그대로 유지해야 한다.

[반드시 유지할 변경 사항]
{must_keep}

규칙:
1. 각 플롯은 핵심 장면 단위로 나눈다.
2. 각 플롯 요약은 1~2문장 정도로 작성한다.
3. 페이지 문장이 아니라 장면 요약으로 작성한다.
4. 사용자가 수정한 핵심 장면은 요약 과정에서도 충분히 드러나야 한다.
5. 설명 문장 없이 아래 형식을 지킨다.

출력 형식:
[PLOT 1]
첫 번째 플롯 요약

[PLOT 2]
두 번째 플롯 요약

추가 스타일 요청:
{extra_style}

[전체 줄거리]
{story_content}
""".strip()

    raw_text = call_gemini_with_retry(prompt)

    lines = [line.strip() for line in raw_text.splitlines() if line.strip()]
    plots: List[str] = []
    current_lines: List[str] = []

    def is_plot_header(line: str) -> bool:
        upper = line.upper()
        return (upper.startswith("[PLOT ") and upper.endswith("]")) or upper.startswith("PLOT ")

    for line in lines:
        if is_plot_header(line):
            if current_lines:
                plots.append(" ".join(current_lines).strip())
                current_lines = []
        else:
            current_lines.append(line)

    if current_lines:
        plots.append(" ".join(current_lines).strip())

    if len(plots) < plot_count:
        raise RuntimeError(f"플롯 파싱 실패: 요청={plot_count}, 생성={len(plots)}, raw_text={raw_text}")

    if len(plots) > plot_count:
        plots = plots[:plot_count]

    return plots


def generate_plot_contents_with_gemini(
    plot_summaries: List[str],
    required_changes: Optional[str] = None,
    style_request: Optional[str] = None
) -> List[str]:
    extra_style = style_request if style_request else "각 플롯을 동화책 본문처럼 2~4문장으로 작성하라."
    must_keep = required_changes if required_changes else "없음"

    joined_plots = "\n".join([f"[PLOT {idx}] {txt}" for idx, txt in enumerate(plot_summaries, start=1)])

    prompt = f"""
너는 아동용 동화책 작가야.

아래 플롯 요약들을 바탕으로, 각 플롯에 대응하는 실제 동화책 본문을 작성하라.

중요:
아래 '반드시 유지할 변경 사항'은 사용자가 수정한 핵심 내용이다.
본문을 생성할 때 이 내용을 축약하거나 삭제하거나 약하게 표현하면 안 된다.
예를 들어 '배에 눕혀 물 위에 띄웠다'를 '물 위에 띄웠다'로 단순화하면 안 된다.

[반드시 유지할 변경 사항]
{must_keep}

규칙:
1. 각 플롯 내용은 2~4문장 정도로 작성한다.
2. 아동용 동화 문체를 사용한다.
3. 수정된 핵심 장면은 구체적으로 유지한다.
4. 설명 문장 없이 아래 형식을 지킨다.

출력 형식:
[PLOT 1]
첫 번째 플롯 본문

[PLOT 2]
두 번째 플롯 본문

추가 스타일 요청:
{extra_style}

[플롯 목록]
{joined_plots}
""".strip()

    raw_text = call_gemini_with_retry(prompt)

    lines = [line.strip() for line in raw_text.splitlines() if line.strip()]
    contents: List[str] = []
    current_lines: List[str] = []

    def is_plot_header(line: str) -> bool:
        upper = line.upper()
        return (upper.startswith("[PLOT ") and upper.endswith("]")) or upper.startswith("PLOT ")

    for line in lines:
        if is_plot_header(line):
            if current_lines:
                contents.append(" ".join(current_lines).strip())
                current_lines = []
        else:
            current_lines.append(line)

    if current_lines:
        contents.append(" ".join(current_lines).strip())

    if len(contents) < len(plot_summaries):
        raise RuntimeError(f"플롯 내용 파싱 실패: 요청={len(plot_summaries)}, 생성={len(contents)}, raw_text={raw_text}")

    if len(contents) > len(plot_summaries):
        contents = contents[:len(plot_summaries)]

    return contents


def get_style_reference_pages(session: Session, story_id: int) -> List[StoryPage]:
    pages = session.exec(
        select(StoryPage)
        .where(StoryPage.story_id == story_id)
        .where(StoryPage.image_data != None)  # noqa: E711
        .order_by(StoryPage.page_number)
    ).all()
    return pages


def build_style_reference_hint(reference_pages: List[StoryPage]) -> str:
    if not reference_pages:
        return "기존 동화 이미지 reference 없음"

    page_numbers = [str(p.page_number) for p in reference_pages]
    cover_text = "cover 이미지 포함" if "0" in page_numbers else "cover 이미지 없음"

    return (
        f"스타일 reference 페이지 번호: {', '.join(page_numbers)}. "
        f"{cover_text}. 기존 동화의 그림체, 캐릭터 표현 방식, 색감, 분위기와 유사하게 유지해야 함."
    )


def generate_plot_image_prompt_with_gemini(
    story_title: str,
    plot_number: int,
    plot_summary: str,
    plot_content: str,
    style_reference_hint: str,
    style_request: Optional[str] = None
) -> str:
    style_text = style_request if style_request else "기존 동화 삽화와 유사한 따뜻하고 귀여운 2D 아동용 동화책 그림체"

    prompt = f"""
너는 동화책 삽화용 이미지 생성 프롬프트를 작성하는 도우미야.

규칙:
1. 아래 플롯 요약과 플롯 본문을 바탕으로 장면을 시각적으로 잘 설명한다.
2. 등장인물, 배경, 분위기, 행동이 잘 드러나야 한다.
3. 반드시 기존 동화 이미지와 유사한 그림체를 유지해야 한다.
4. 기존 동화 이미지의 색감, 선화 느낌, 캐릭터 비율, 전체 분위기를 참고하는 방향으로 작성한다.
5. 스타일은 "{style_text}" 로 한다.
6. 출력은 이미지 생성 모델에 바로 넣을 수 있는 프롬프트 한 단락만 출력한다.
7. 군더더기 설명 없이 프롬프트 본문만 출력한다.

[스타일 참고 정보]
{style_reference_hint}

[동화 제목]
{story_title}

[플롯 번호]
{plot_number}

[플롯 요약]
{plot_summary}

[플롯 본문]
{plot_content}
""".strip()

    return call_gemini_with_retry(prompt)


def collect_style_reference_images(reference_pages: List[StoryPage]) -> List[dict]:
    refs = []
    for p in reference_pages:
        if p.image_data and p.image_mime_type:
            refs.append(
                {
                    "page_number": p.page_number,
                    "image_data": p.image_data,
                    "mime_type": p.image_mime_type,
                }
            )
    return refs


def _extract_image_bytes_from_response(response) -> tuple[bytes, str]:
    parts = getattr(response, "parts", None)
    if not parts:
        raise RuntimeError(f"Gemini 이미지 생성 실패: parts 없음, response={response}")

    for part in parts:
        inline_data = getattr(part, "inline_data", None)
        if not inline_data:
            continue

        data = getattr(inline_data, "data", None)
        mime_type = getattr(inline_data, "mime_type", None) or "image/png"

        if not data:
            continue

        if isinstance(data, (bytes, bytearray)):
            return bytes(data), mime_type

        if isinstance(data, str):
            return base64.b64decode(data), mime_type

    raise RuntimeError(f"Gemini 이미지 생성 응답에서 이미지 데이터를 찾지 못했습니다. response={response}")
   


def generate_plot_image_bytes(
    image_prompt: str,
    plot_number: int,
    reference_images: List[dict]
) -> tuple[bytes, str, str]:
    contents = [image_prompt]

    for ref in reference_images:
        if ref.get("image_data") and ref.get("mime_type"):
            contents.append(
                types.Part.from_bytes(
                    data=ref["image_data"],
                    mime_type=ref["mime_type"]
                )
            )

    response = client.models.generate_content(
        model=GEMINI_IMAGE_MODEL,
        contents=contents,
    )

    image_bytes, mime_type = _extract_image_bytes_from_response(response)

    ext = ".png"
    if mime_type == "image/jpeg":
        ext = ".jpg"
    elif mime_type == "image/webp":
        ext = ".webp"

    return image_bytes, mime_type, f"plot_{plot_number}{ext}"


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
            )
            session.add(story)
            session.commit()
            session.refresh(story)

            if cover_file:
                cover_mime, _ = mimetypes.guess_type(str(cover_file))
                cover_page = StoryPage(
                    story_id=story.id,
                    page_number=0,
                    is_cover=True,
                    text_content=None,
                    image_data=cover_file.read_bytes(),
                    image_mime_type=cover_mime or "application/octet-stream",
                    image_filename=cover_file.name,
                )
                session.add(cover_page)

            for page_number, page_data in sorted(page_map.items()):
                page = StoryPage(
                    story_id=story.id,
                    page_number=page_number,
                    is_cover=False,
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
        stories = session.exec(select(Story).order_by(Story.created_at.desc())).all()
        return [
            StoryListItem(
                id=s.id,
                book_id=s.book_id,
                title=s.title,
                original_title=s.original_title,
                total_pages=s.total_pages,
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


@app.get("/stories/{story_id}/pages", response_model=List[StoryPageRead])
def get_story_pages(story_id: int):
    with Session(engine) as session:
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
                is_cover=p.is_cover,
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
            is_cover=page.is_cover,
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


@app.post("/stories/{story_id}/revise-preview", response_model=StoryRevisePreviewResponse)
def revise_story_preview(story_id: int, payload: StoryReviseRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        revised_content = revise_story_with_gemini(story.content, payload.user_request)

        return StoryRevisePreviewResponse(
            id=story.id,
            title=story.title,
            original_content=story.content,
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

        if payload.confirmed_request:
            story.last_confirmed_change = payload.confirmed_request

        session.add(story)
        session.commit()
        session.refresh(story)
        return story


@app.get("/stories/{story_id}/versions", response_model=List[StoryVersionRead])
def list_story_versions(story_id: int):
    with Session(engine) as session:
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


@app.post("/stories/{story_id}/pages/{page_number}/sketch-interpret", response_model=SketchInterpretResponse)
async def sketch_interpret(
    story_id: int,
    page_number: int,
    selected_text: str = Form(...),
    sketch_file: UploadFile = File(...)
):
    with Session(engine) as session:
        page = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.page_number == page_number)
        ).first()

        if not page:
            raise HTTPException(status_code=404, detail="해당 페이지를 찾을 수 없습니다.")
        if page.is_cover:
            raise HTTPException(status_code=400, detail="cover 페이지에서는 사용할 수 없습니다.")

        image_bytes = await sketch_file.read()
        mime_type = sketch_file.content_type or "image/png"

        interpreted_request = interpret_sketch_with_gemini(
            selected_text=selected_text,
            page_text=page.text_content or "",
            image_bytes=image_bytes,
            mime_type=mime_type,
        )

        return SketchInterpretResponse(
            story_id=story_id,
            page_number=page_number,
            selected_text=selected_text,
            interpreted_request=interpreted_request,
        )


@app.post("/stories/{story_id}/sketch-revise-preview", response_model=SketchRevisionPreviewResponse)
def sketch_revise_preview(story_id: int, payload: SketchRevisionPreviewRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        revised_content = revise_story_from_confirmed_sketch_request(
            original_story=story.content,
            selected_text=payload.selected_text,
            confirmed_request=payload.confirmed_request,
        )

        return SketchRevisionPreviewResponse(
            story_id=story_id,
            page_number=payload.page_number,
            selected_text=payload.selected_text,
            confirmed_request=payload.confirmed_request,
            original_content=story.content,
            revised_content=revised_content,
        )


@app.post("/stories/{story_id}/plots/rearrange", response_model=PlotRearrangeResponse)
def rearrange_story_plots(story_id: int, payload: PlotRearrangeRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        plot_summaries = rearrange_plots_with_gemini(
            story_content=story.content,
            plot_count=payload.plot_count,
            required_changes=story.last_confirmed_change,
            style_request=payload.style_request,
        )

        old_plot_contents = session.exec(
            select(StoryPlotContent).where(StoryPlotContent.story_id == story_id)
        ).all()
        for c in old_plot_contents:
            session.delete(c)

        old_plot_images = session.exec(
            select(StoryPlotImage).where(StoryPlotImage.story_id == story_id)
        ).all()
        for img in old_plot_images:
            session.delete(img)

        old_plots = session.exec(
            select(StoryPlot).where(StoryPlot.story_id == story_id)
        ).all()
        for p in old_plots:
            session.delete(p)

        session.commit()

        saved_plots: List[StoryPlot] = []
        for idx, summary in enumerate(plot_summaries, start=1):
            plot = StoryPlot(
                story_id=story_id,
                plot_number=idx,
                summary=summary,
            )
            session.add(plot)
            saved_plots.append(plot)

        session.commit()
        for p in saved_plots:
            session.refresh(p)

        return PlotRearrangeResponse(
            story_id=story.id,
            title=story.title,
            plot_count=payload.plot_count,
            required_changes=story.last_confirmed_change,
            plots=[
                StoryPlotRead(
                    id=p.id,
                    story_id=p.story_id,
                    plot_number=p.plot_number,
                    summary=p.summary,
                    created_at=p.created_at,
                    updated_at=p.updated_at,
                )
                for p in sorted(saved_plots, key=lambda x: x.plot_number)
            ]
        )


@app.get("/stories/{story_id}/plots", response_model=List[StoryPlotRead])
def get_story_plots(story_id: int):
    with Session(engine) as session:
        plots = session.exec(
            select(StoryPlot)
            .where(StoryPlot.story_id == story_id)
            .order_by(StoryPlot.plot_number)
        ).all()

        return [
            StoryPlotRead(
                id=p.id,
                story_id=p.story_id,
                plot_number=p.plot_number,
                summary=p.summary,
                created_at=p.created_at,
                updated_at=p.updated_at,
            )
            for p in plots
        ]


@app.post("/stories/{story_id}/plots/generate-contents", response_model=PlotContentGenerateResponse)
def generate_plot_contents(story_id: int, payload: PlotContentGenerateRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        plots = session.exec(
            select(StoryPlot)
            .where(StoryPlot.story_id == story_id)
            .order_by(StoryPlot.plot_number)
        ).all()

        if not plots:
            raise HTTPException(status_code=400, detail="먼저 플롯을 재배치해야 합니다.")

        plot_summaries = [p.summary for p in plots]
        contents = generate_plot_contents_with_gemini(
            plot_summaries=plot_summaries,
            required_changes=story.last_confirmed_change,
            style_request=payload.style_request,
        )

        old_contents = session.exec(
            select(StoryPlotContent).where(StoryPlotContent.story_id == story_id)
        ).all()
        for c in old_contents:
            session.delete(c)
        session.commit()

        saved_contents: List[StoryPlotContent] = []
        for plot, content in zip(plots, contents):
            row = StoryPlotContent(
                story_id=story_id,
                plot_id=plot.id,
                plot_number=plot.plot_number,
                content=content,
            )
            session.add(row)
            saved_contents.append(row)

        session.commit()
        for c in saved_contents:
            session.refresh(c)

        return PlotContentGenerateResponse(
            story_id=story_id,
            count=len(saved_contents),
            required_changes=story.last_confirmed_change,
            contents=[
                StoryPlotContentRead(
                    id=c.id,
                    story_id=c.story_id,
                    plot_id=c.plot_id,
                    plot_number=c.plot_number,
                    content=c.content,
                    created_at=c.created_at,
                    updated_at=c.updated_at,
                )
                for c in sorted(saved_contents, key=lambda x: x.plot_number)
            ]
        )


@app.get("/stories/{story_id}/plots/contents", response_model=List[StoryPlotContentRead])
def get_plot_contents(story_id: int):
    with Session(engine) as session:
        contents = session.exec(
            select(StoryPlotContent)
            .where(StoryPlotContent.story_id == story_id)
            .order_by(StoryPlotContent.plot_number)
        ).all()

        return [
            StoryPlotContentRead(
                id=c.id,
                story_id=c.story_id,
                plot_id=c.plot_id,
                plot_number=c.plot_number,
                content=c.content,
                created_at=c.created_at,
                updated_at=c.updated_at,
            )
            for c in contents
        ]


@app.post("/stories/{story_id}/plots/{plot_number}/generate-image", response_model=StoryPlotImageRead)
def generate_single_plot_image(story_id: int, plot_number: int, payload: PlotImageGenerateRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        plot = session.exec(
            select(StoryPlot)
            .where(StoryPlot.story_id == story_id)
            .where(StoryPlot.plot_number == plot_number)
        ).first()

        if not plot:
            raise HTTPException(status_code=404, detail="해당 플롯을 찾을 수 없습니다.")

        content_row = session.exec(
            select(StoryPlotContent)
            .where(StoryPlotContent.story_id == story_id)
            .where(StoryPlotContent.plot_number == plot_number)
        ).first()

        if not content_row:
            raise HTTPException(status_code=400, detail="먼저 해당 플롯의 내용을 생성해야 합니다.")

        reference_pages = get_style_reference_pages(session, story_id)
        style_reference_hint = build_style_reference_hint(reference_pages)
        style_reference_page_numbers = ",".join([str(p.page_number) for p in reference_pages])
        reference_images = collect_style_reference_images(reference_pages)

        image_prompt = generate_plot_image_prompt_with_gemini(
            story_title=story.title,
            plot_number=plot.plot_number,
            plot_summary=plot.summary,
            plot_content=content_row.content,
            style_reference_hint=style_reference_hint,
            style_request=payload.style_request,
        )

        try:
            image_bytes, mime_type, filename = generate_plot_image_bytes(
                image_prompt=image_prompt,
                plot_number=plot.plot_number,
                reference_images=reference_images,
            )
        except Exception as e:
            print("=== SINGLE PLOT IMAGE GENERATION ERROR ===")
            print(repr(e))
            raise HTTPException(status_code=500, detail=f"플롯 이미지 생성 실패: {repr(e)}")

        existing_row = session.exec(
            select(StoryPlotImage)
            .where(StoryPlotImage.story_id == story_id)
            .where(StoryPlotImage.plot_number == plot_number)
        ).first()

        if existing_row:
            existing_row.image_prompt = image_prompt
            existing_row.style_reference_page_numbers = style_reference_page_numbers
            existing_row.image_data = image_bytes
            existing_row.image_mime_type = mime_type
            existing_row.image_filename = filename
            existing_row.updated_at = datetime.utcnow()
            session.add(existing_row)
            session.commit()
            session.refresh(existing_row)
            row = existing_row
        else:
            row = StoryPlotImage(
                story_id=story_id,
                plot_id=plot.id,
                plot_number=plot.plot_number,
                image_prompt=image_prompt,
                style_reference_page_numbers=style_reference_page_numbers,
                image_data=image_bytes,
                image_mime_type=mime_type,
                image_filename=filename,
            )
            session.add(row)
            session.commit()
            session.refresh(row)

        return StoryPlotImageRead(
            id=row.id,
            story_id=row.story_id,
            plot_id=row.plot_id,
            plot_number=row.plot_number,
            image_prompt=row.image_prompt,
            style_reference_page_numbers=row.style_reference_page_numbers,
            image_filename=row.image_filename,
            image_mime_type=row.image_mime_type,
            created_at=row.created_at,
            updated_at=row.updated_at,
        )


@app.get("/stories/{story_id}/plots/images", response_model=List[StoryPlotImageRead])
def get_plot_images(story_id: int):
    with Session(engine) as session:
        images = session.exec(
            select(StoryPlotImage)
            .where(StoryPlotImage.story_id == story_id)
            .order_by(StoryPlotImage.plot_number)
        ).all()

        return [
            StoryPlotImageRead(
                id=img.id,
                story_id=img.story_id,
                plot_id=img.plot_id,
                plot_number=img.plot_number,
                image_prompt=img.image_prompt,
                style_reference_page_numbers=img.style_reference_page_numbers,
                image_filename=img.image_filename,
                image_mime_type=img.image_mime_type,
                created_at=img.created_at,
                updated_at=img.updated_at,
            )
            for img in images
        ]


@app.get("/stories/{story_id}/plots/{plot_number}/image")
def get_plot_image(story_id: int, plot_number: int):
    with Session(engine) as session:
        image_row = session.exec(
            select(StoryPlotImage)
            .where(StoryPlotImage.story_id == story_id)
            .where(StoryPlotImage.plot_number == plot_number)
        ).first()

        if not image_row or not image_row.image_data:
            raise HTTPException(status_code=404, detail="플롯 이미지가 없습니다.")

        return Response(
            content=image_row.image_data,
            media_type=image_row.image_mime_type or "application/octet-stream"
        )