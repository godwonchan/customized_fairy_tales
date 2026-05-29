from datetime import datetime
from typing import Optional, List

from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlmodel import SQLModel, Session, select

from app_core import (
    engine,
    Story,
    StoryVersion,
    StoryPage,
    StoryPlot,
    StoryPlotContent,
    StoryPlotImage,
    StoryListItem,
    StoryRead,
    StoryReviseRequest,
    StoryRevisePreviewResponse,
    StoryVersionRead,
    StoryRollbackResponse,
    StoryPageRead,
    SketchInterpretResponse,
    ScenePreviewImageRequest,
    ScenePreviewImageResponse,
    PlotRearrangeRequest,
    StoryPlotRead,
    PlotRearrangeResponse,
    PlotContentGenerateRequest,
    StoryPlotContentRead,
    PlotContentGenerateResponse,
    PlotImageGenerateRequest,
    StoryPlotImageRead,
    PlotImageGenerationStatusItem,
    PlotImageGenerationStatusResponse,
    normalize_image_mime_type,
    save_story_version,
    import_story_folders_if_empty,
    build_story_content_from_pages,
    build_style_reference_hint,
    collect_style_reference_images,
    get_style_reference_pages,
    pick_reference_pages_for_style,
)

from ai_services import (
    revise_story,
    interpret_sketch,
    revise_pages_from_confirmed_request,
    rearrange_plots,
    generate_plot_contents,
    generate_scene_preview_image,
    generate_plot_image_prompt,
    generate_plot_image_bytes,
)

app = FastAPI(title="Storybook Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# =========================
# 추가 요청/응답 스키마
# =========================
class SketchRevisionPreviewRequestV2(BaseModel):
    page_number: int
    selected_text: str
    confirmed_request: str


class SketchRevisionPreviewResponseV2(BaseModel):
    story_id: int
    page_number: int
    selected_text: str
    confirmed_request: str
    original_pages: List[str]
    revised_pages: List[str]


class StoryApplyRevisionPagesRequest(BaseModel):
    revised_pages: List[str]
    confirmed_request: Optional[str] = None


class RegenerateFromPlotRequest(BaseModel):
    start_plot_number: int
    style_request: Optional[str] = None


class ApplyPlotImagesToPagesRequest(BaseModel):
    start_plot_number: int = 1


@app.on_event("startup")
def on_startup():
    SQLModel.metadata.create_all(engine)
    import_story_folders_if_empty()


@app.get("/")
def root():
    return {"message": "Storybook server is running"}


# =========================
# Story list / detail
# =========================
@app.get("/stories", response_model=list[StoryListItem])
def list_stories():
    with Session(engine) as session:
        stories = session.exec(
            select(Story).order_by(Story.created_at.desc())
        ).all()

        return [
            StoryListItem(
                id=s.id,
                book_id=s.book_id,
                title=s.title,
                original_title=s.original_title,
                total_pages=s.total_pages,
                source_folder=s.source_folder,
                is_user_story=s.is_user_story,
                parent_story_id=s.parent_story_id,
                created_at=s.created_at,
                updated_at=s.updated_at,
            )
            for s in stories
        ]


@app.get("/stories/original", response_model=list[StoryListItem])
def list_original_stories():
    with Session(engine) as session:
        stories = session.exec(
            select(Story)
            .where(Story.is_user_story == False)  # noqa: E712
            .order_by(Story.created_at.desc())
        ).all()

        return [
            StoryListItem(
                id=s.id,
                book_id=s.book_id,
                title=s.title,
                original_title=s.original_title,
                total_pages=s.total_pages,
                source_folder=s.source_folder,
                is_user_story=s.is_user_story,
                parent_story_id=s.parent_story_id,
                created_at=s.created_at,
                updated_at=s.updated_at,
            )
            for s in stories
        ]


@app.get("/stories/my", response_model=list[StoryListItem])
def list_my_stories():
    with Session(engine) as session:
        stories = session.exec(
            select(Story)
            .where(Story.is_user_story == True)  # noqa: E712
            .order_by(Story.created_at.desc())
        ).all()

        return [
            StoryListItem(
                id=s.id,
                book_id=s.book_id,
                title=s.title,
                original_title=s.original_title,
                total_pages=s.total_pages,
                source_folder=s.source_folder,
                is_user_story=s.is_user_story,
                parent_story_id=s.parent_story_id,
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

        return StoryRead(
            id=story.id,
            book_id=story.book_id,
            title=story.title,
            original_title=story.original_title,
            language=story.language,
            total_pages=story.total_pages,
            description=story.description,
            source_folder=story.source_folder,
            content=story.content,
            last_confirmed_change=story.last_confirmed_change,
            is_user_story=story.is_user_story,
            parent_story_id=story.parent_story_id,
            created_at=story.created_at,
            updated_at=story.updated_at,
        )


# =========================
# Story pages
# =========================
@app.get("/stories/{story_id}/pages", response_model=list[StoryPageRead])
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
                original_text_content=p.original_text_content,
                text_content=p.text_content,
                image_filename=p.image_filename,
                image_mime_type=p.image_mime_type,
                created_at=p.created_at,
                updated_at=p.updated_at,
            )
            for p in pages
        ]


@app.get("/stories/{story_id}/pages/original", response_model=list[StoryPageRead])
def get_original_pages(story_id: int):
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
                original_text_content=p.original_text_content,
                text_content=p.original_text_content,
                image_filename=p.original_image_filename,
                image_mime_type=p.original_image_mime_type,
                created_at=p.created_at,
                updated_at=p.updated_at,
            )
            for p in pages
        ]


@app.get("/stories/{story_id}/pages/current", response_model=list[StoryPageRead])
def get_current_pages(story_id: int):
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
                original_text_content=p.original_text_content,
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
            original_text_content=page.original_text_content,
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
            media_type=page.image_mime_type or "application/octet-stream",
        )


@app.get("/stories/{story_id}/pages/{page_number}/original-image")
def get_original_page_image(story_id: int, page_number: int):
    with Session(engine) as session:
        page = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.page_number == page_number)
        ).first()

        if not page or not page.original_image_data:
            raise HTTPException(status_code=404, detail="원본 이미지가 없습니다.")

        return Response(
            content=page.original_image_data,
            media_type=page.original_image_mime_type or "application/octet-stream",
        )


# =========================
# Story text revision
# =========================
@app.post("/stories/{story_id}/revise-preview", response_model=StoryRevisePreviewResponse)
def revise_story_preview(story_id: int, payload: StoryReviseRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        revised_content = revise_story(story.content, payload.user_request)

        return StoryRevisePreviewResponse(
            id=story.id,
            title=story.title,
            original_content=story.content,
            revised_content=revised_content,
            user_request=payload.user_request,
        )


@app.post("/stories/{story_id}/apply-revision", response_model=StoryRead)
def apply_story_revision(story_id: int, payload: StoryApplyRevisionPagesRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        pages = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.is_cover == False)  # noqa: E712
            .order_by(StoryPage.page_number)
        ).all()

        if not pages:
            raise HTTPException(status_code=400, detail="수정할 페이지가 없습니다.")

        if len(payload.revised_pages) != len(pages):
            raise HTTPException(
                status_code=400,
                detail=f"페이지 수가 맞지 않습니다. expected={len(pages)}, actual={len(payload.revised_pages)}",
            )

        save_story_version(session, story)

        for idx, page in enumerate(pages):
            page.text_content = payload.revised_pages[idx]
            page.updated_at = datetime.utcnow()
            session.add(page)

        story.content = build_story_content_from_pages(payload.revised_pages)
        story.updated_at = datetime.utcnow()

        if payload.confirmed_request:
            story.last_confirmed_change = payload.confirmed_request

        session.add(story)

        # 수정 후 기존 플롯 데이터 초기화
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
        session.refresh(story)

        return StoryRead(
            id=story.id,
            book_id=story.book_id,
            title=story.title,
            original_title=story.original_title,
            language=story.language,
            total_pages=story.total_pages,
            description=story.description,
            source_folder=story.source_folder,
            content=story.content,
            last_confirmed_change=story.last_confirmed_change,
            is_user_story=story.is_user_story,
            parent_story_id=story.parent_story_id,
            created_at=story.created_at,
            updated_at=story.updated_at,
        )


@app.post("/stories/{story_id}/reset-to-original", response_model=StoryRead)
def reset_story_to_original(story_id: int):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        pages = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.is_cover == False)  # noqa: E712
            .order_by(StoryPage.page_number)
        ).all()

        save_story_version(session, story)

        restored_pages = []
        for page in pages:
            page.text_content = page.original_text_content
            page.image_data = page.original_image_data
            page.image_mime_type = page.original_image_mime_type
            page.image_filename = page.original_image_filename
            page.updated_at = datetime.utcnow()
            session.add(page)
            restored_pages.append(page.original_text_content or "")

        story.content = build_story_content_from_pages(restored_pages)
        story.updated_at = datetime.utcnow()
        story.last_confirmed_change = None
        session.add(story)

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
        session.refresh(story)

        return StoryRead(
            id=story.id,
            book_id=story.book_id,
            title=story.title,
            original_title=story.original_title,
            language=story.language,
            total_pages=story.total_pages,
            description=story.description,
            source_folder=story.source_folder,
            content=story.content,
            last_confirmed_change=story.last_confirmed_change,
            is_user_story=story.is_user_story,
            parent_story_id=story.parent_story_id,
            created_at=story.created_at,
            updated_at=story.updated_at,
        )


@app.get("/stories/{story_id}/versions", response_model=list[StoryVersionRead])
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


# =========================
# Sketch + preview
# =========================
@app.post("/stories/{story_id}/pages/{page_number}/sketch-interpret", response_model=SketchInterpretResponse)
async def sketch_interpret_endpoint(
    story_id: int,
    page_number: int,
    selected_text: str = Form(...),
    sketch_file: UploadFile = File(...),
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
        mime_type = normalize_image_mime_type(sketch_file)

        interpreted_request = interpret_sketch(
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


@app.post("/stories/{story_id}/sketch-revise-preview", response_model=SketchRevisionPreviewResponseV2)
def sketch_revise_preview_endpoint(story_id: int, payload: SketchRevisionPreviewRequestV2):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        pages = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .where(StoryPage.is_cover == False)  # noqa: E712
            .order_by(StoryPage.page_number)
        ).all()

        page_texts = [p.text_content or "" for p in pages]

        revised_pages = revise_pages_from_confirmed_request(
            page_texts=page_texts,
            edited_page_number=payload.page_number,
            selected_text=payload.selected_text,
            confirmed_request=payload.confirmed_request,
        )

        return SketchRevisionPreviewResponseV2(
            story_id=story_id,
            page_number=payload.page_number,
            selected_text=payload.selected_text,
            confirmed_request=payload.confirmed_request,
            original_pages=page_texts,
            revised_pages=revised_pages,
        )


@app.post(
    "/stories/{story_id}/pages/{page_number}/generate-preview-image",
    response_model=ScenePreviewImageResponse,
)
def generate_preview_image_endpoint(
    story_id: int,
    page_number: int,
    payload: ScenePreviewImageRequest,
):
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
        if not page.original_image_data:
            raise HTTPException(status_code=400, detail="현재 페이지의 원본 이미지가 없습니다.")

        ref_pages = pick_reference_pages_for_style(
            session=session,
            story_id=story_id,
            current_page_number=page_number,
        )
        reference_images = [
            {
                "image_data": p.original_image_data,
                "mime_type": p.original_image_mime_type,
            }
            for p in ref_pages
            if p.original_image_data
        ]

        try:
            _, mime_type, prompt = generate_scene_preview_image(
                story_title=story.title,
                page_text=page.text_content or "",
                selected_text=payload.selected_text,
                interpreted_request=payload.interpreted_request,
                base_image_bytes=page.original_image_data,
                base_image_mime_type=page.original_image_mime_type or "image/png",
                reference_images=reference_images,
                style_request=payload.style_request,
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"장면 이미지 생성 실패: {e}")

        # 미리보기는 저장하지 않음
        return ScenePreviewImageResponse(
            story_id=story_id,
            page_number=page_number,
            prompt=prompt,
            image_mime_type=mime_type,
            message="장면 이미지 생성 완료",
        )


# =========================
# Plot
# =========================
@app.post("/stories/{story_id}/plots/rearrange", response_model=PlotRearrangeResponse)
def rearrange_story_plots_endpoint(story_id: int, payload: PlotRearrangeRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        plot_summaries = rearrange_plots(
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

        saved_plots: list[StoryPlot] = []
        for idx, summary in enumerate(plot_summaries, start=1):
            plot = StoryPlot(
                story_id=story_id,
                plot_number=idx,
                summary=summary,
                image_status="pending",
                image_error=None,
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
                    image_status=p.image_status,
                    image_error=p.image_error,
                    created_at=p.created_at,
                    updated_at=p.updated_at,
                )
                for p in sorted(saved_plots, key=lambda x: x.plot_number)
            ],
        )


@app.get("/stories/{story_id}/plots", response_model=list[StoryPlotRead])
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
                image_status=p.image_status,
                image_error=p.image_error,
                created_at=p.created_at,
                updated_at=p.updated_at,
            )
            for p in plots
        ]


@app.post("/stories/{story_id}/plots/generate-contents", response_model=PlotContentGenerateResponse)
def generate_plot_contents_endpoint(story_id: int, payload: PlotContentGenerateRequest):
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
        contents = generate_plot_contents(
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

        saved_contents: list[StoryPlotContent] = []
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
            ],
        )


@app.get("/stories/{story_id}/plots/contents", response_model=list[StoryPlotContentRead])
def get_plot_contents_endpoint(story_id: int):
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
def generate_single_plot_image_endpoint(story_id: int, plot_number: int, payload: PlotImageGenerateRequest):
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

        image_prompt = generate_plot_image_prompt(
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
            raise HTTPException(status_code=500, detail=f"플롯 이미지 생성 실패: {e}")

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

        plot.image_status = "completed"
        plot.image_error = None
        plot.updated_at = datetime.utcnow()
        session.add(plot)

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


@app.post("/stories/{story_id}/plots/regenerate-from")
def regenerate_plot_images_from_endpoint(story_id: int, payload: RegenerateFromPlotRequest):
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
            raise HTTPException(status_code=400, detail="먼저 플롯을 생성해야 합니다.")

        start_plot_number = max(1, payload.start_plot_number)
        target_plots = [p for p in plots if p.plot_number >= start_plot_number]

        if not target_plots:
            raise HTTPException(status_code=400, detail="재생성할 플롯이 없습니다.")

        for plot in target_plots:
            print(f"[START] plot={plot.plot_number}")

            content_row = session.exec(
                select(StoryPlotContent)
                .where(StoryPlotContent.story_id == story_id)
                .where(StoryPlotContent.plot_number == plot.plot_number)
            ).first()

            if not content_row:
                print(f"[NO CONTENT] plot={plot.plot_number}")
                plot.image_status = "failed"
                plot.image_error = "플롯 본문이 없습니다."
                plot.updated_at = datetime.utcnow()
                session.add(plot)
                session.commit()
                continue

            plot.image_status = "processing"
            plot.image_error = None
            plot.updated_at = datetime.utcnow()
            session.add(plot)
            session.commit()

            print(f"[PROCESSING] plot={plot.plot_number}")
            print(f"[SUMMARY] {plot.summary}")
            print(f"[CONTENT] {content_row.content}")

            try:
                reference_pages = get_style_reference_pages(session, story_id)
                style_reference_hint = build_style_reference_hint(reference_pages)
                style_reference_page_numbers = ",".join([str(p.page_number) for p in reference_pages])
                reference_images = collect_style_reference_images(reference_pages)

                print(f"[PROMPT BUILD START] plot={plot.plot_number}")
                image_prompt = generate_plot_image_prompt(
                    story_title=story.title,
                    plot_number=plot.plot_number,
                    plot_summary=plot.summary,
                    plot_content=content_row.content,
                    style_reference_hint=style_reference_hint,
                    style_request=payload.style_request,
                )
                print(f"[PROMPT BUILT] plot={plot.plot_number}")
                print(f"[IMAGE PROMPT] {image_prompt}")

                print(f"[OPENAI REQUEST START] plot={plot.plot_number}")
                image_bytes, mime_type, filename = generate_plot_image_bytes(
                    image_prompt=image_prompt,
                    plot_number=plot.plot_number,
                    reference_images=reference_images,
                )
                print(f"[OPENAI REQUEST DONE] plot={plot.plot_number}")

                existing_row = session.exec(
                    select(StoryPlotImage)
                    .where(StoryPlotImage.story_id == story_id)
                    .where(StoryPlotImage.plot_number == plot.plot_number)
                ).first()

                if existing_row:
                    existing_row.image_prompt = image_prompt
                    existing_row.style_reference_page_numbers = style_reference_page_numbers
                    existing_row.image_data = image_bytes
                    existing_row.image_mime_type = mime_type
                    existing_row.image_filename = filename
                    existing_row.updated_at = datetime.utcnow()
                    session.add(existing_row)
                else:
                    new_row = StoryPlotImage(
                        story_id=story_id,
                        plot_id=plot.id,
                        plot_number=plot.plot_number,
                        image_prompt=image_prompt,
                        style_reference_page_numbers=style_reference_page_numbers,
                        image_data=image_bytes,
                        image_mime_type=mime_type,
                        image_filename=filename,
                    )
                    session.add(new_row)

                plot.image_status = "completed"
                plot.image_error = None
                plot.updated_at = datetime.utcnow()
                session.add(plot)
                session.commit()
                print(f"[SUCCESS] plot={plot.plot_number}")

            except Exception as e:
                print(f"[FAILED] plot={plot.plot_number}, error={e}")
                plot.image_status = "failed"
                plot.image_error = str(e)
                plot.updated_at = datetime.utcnow()
                session.add(plot)
                session.commit()

        return {
            "message": f"{start_plot_number}번 플롯부터 이미지 재생성을 완료했습니다."
        }


@app.get("/stories/{story_id}/plots/image-generation-status", response_model=PlotImageGenerationStatusResponse)
def get_plot_image_generation_status(story_id: int):
    with Session(engine) as session:
        plots = session.exec(
            select(StoryPlot)
            .where(StoryPlot.story_id == story_id)
            .order_by(StoryPlot.plot_number)
        ).all()

        if not plots:
            raise HTTPException(status_code=404, detail="플롯을 찾을 수 없습니다.")

        total = len(plots)
        completed = sum(1 for p in plots if p.image_status == "completed")
        failed = sum(1 for p in plots if p.image_status == "failed")
        processing = sum(1 for p in plots if p.image_status == "processing")

        current_plot = next(
            (p.plot_number for p in plots if p.image_status == "processing"),
            None,
        )

        if processing > 0:
            overall_status = "processing"
        elif completed == total and total > 0:
            overall_status = "completed"
        elif failed > 0 and completed + failed == total:
            overall_status = "completed"
        else:
            overall_status = "pending"

        progress_percent = int((completed / total) * 100) if total > 0 else 0

        return PlotImageGenerationStatusResponse(
            story_id=story_id,
            total=total,
            completed=completed,
            failed=failed,
            processing=processing,
            progress_percent=progress_percent,
            current_plot_number=current_plot,
            status=overall_status,
            plots=[
                PlotImageGenerationStatusItem(
                    plot_number=p.plot_number,
                    image_status=p.image_status,
                    image_error=p.image_error,
                )
                for p in plots
            ],
        )


@app.get("/stories/{story_id}/plots/images", response_model=list[StoryPlotImageRead])
def get_plot_images_endpoint(story_id: int):
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
def get_plot_image_endpoint(story_id: int, plot_number: int):
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
            media_type=image_row.image_mime_type or "application/octet-stream",
        )


@app.post("/stories/{story_id}/plots/apply-to-pages")
def apply_plot_images_to_pages_endpoint(story_id: int, payload: ApplyPlotImagesToPagesRequest):
    with Session(engine) as session:
        story = session.get(Story, story_id)
        if not story:
            raise HTTPException(status_code=404, detail="해당 동화를 찾을 수 없습니다.")

        start_plot_number = max(1, payload.start_plot_number)

        plots = session.exec(
            select(StoryPlotImage)
            .where(StoryPlotImage.story_id == story_id)
            .where(StoryPlotImage.plot_number >= start_plot_number)
            .order_by(StoryPlotImage.plot_number)
        ).all()

        if not plots:
            raise HTTPException(status_code=400, detail="적용할 플롯 이미지가 없습니다.")

        applied_pages = []

        for plot_img in plots:
            page = session.exec(
                select(StoryPage)
                .where(StoryPage.story_id == story_id)
                .where(StoryPage.page_number == plot_img.plot_number)
            ).first()

            if not page or not plot_img.image_data:
                continue

            page.image_data = plot_img.image_data
            page.image_mime_type = plot_img.image_mime_type
            page.image_filename = plot_img.image_filename or f"page_{page.page_number}_final.png"
            page.updated_at = datetime.utcnow()
            session.add(page)
            applied_pages.append(page.page_number)

        session.commit()

        return {
            "story_id": story_id,
            "applied_pages": applied_pages,
            "message": f"{start_plot_number}페이지 이후 이미지가 동화 페이지에 적용되었습니다.",
        }


# =========================
# Save as my story
# =========================
@app.post("/stories/{story_id}/save-as-my-story", response_model=StoryRead)
def save_as_my_story(story_id: int):
    with Session(engine) as session:
        source_story = session.get(Story, story_id)
        if not source_story:
            raise HTTPException(status_code=404, detail="원본 동화를 찾을 수 없습니다.")

        source_pages = session.exec(
            select(StoryPage)
            .where(StoryPage.story_id == story_id)
            .order_by(StoryPage.page_number)
        ).all()

        # 현재 수정본 기준으로 content 재구성
        current_text_pages = [
            (p.text_content or "")
            for p in source_pages
            if not p.is_cover
        ]
        current_story_content = build_story_content_from_pages(current_text_pages)

        new_story = Story(
            book_id=source_story.book_id,
            title=f"{source_story.title} - 내 이야기",
            original_title=source_story.original_title,
            language=source_story.language,
            total_pages=source_story.total_pages,
            description=source_story.description,
            source_folder=source_story.source_folder,
            content=current_story_content,
            last_confirmed_change=source_story.last_confirmed_change,
            is_user_story=True,
            parent_story_id=source_story.id,
        )
        session.add(new_story)
        session.commit()
        session.refresh(new_story)

        for p in source_pages:
            copied_page = StoryPage(
                story_id=new_story.id,
                page_number=p.page_number,
                is_cover=p.is_cover,

                # 원본도 보존
                original_text_content=p.original_text_content,
                original_image_data=p.original_image_data,
                original_image_mime_type=p.original_image_mime_type,
                original_image_filename=p.original_image_filename,

                # 현재 수정본을 "내 이야기" 현재본으로 저장
                text_content=p.text_content,
                image_data=p.image_data,
                image_mime_type=p.image_mime_type,
                image_filename=p.image_filename,
            )
            session.add(copied_page)

        session.commit()

        return StoryRead(
            id=new_story.id,
            book_id=new_story.book_id,
            title=new_story.title,
            original_title=new_story.original_title,
            language=new_story.language,
            total_pages=new_story.total_pages,
            description=new_story.description,
            source_folder=new_story.source_folder,
            content=new_story.content,
            last_confirmed_change=new_story.last_confirmed_change,
            is_user_story=new_story.is_user_story,
            parent_story_id=new_story.parent_story_id,
            created_at=new_story.created_at,
            updated_at=new_story.updated_at,
        )