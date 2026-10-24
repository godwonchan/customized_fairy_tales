# storybook_server/routers/story_storage.py
import base64
import uuid
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from sqlmodel import Session

# 팀원의 메인 DB 모델 및 엔진 연결
from app_core import engine, Story, StoryPage

router = APIRouter(prefix="/api/stories", tags=["Story Storage"])

class SavePageRequest(BaseModel):
    page_number: int
    title: Optional[str] = ""
    content: str
    image_url: str

class SaveStoryRequest(BaseModel):
    title: str
    mood: Optional[str] = "신나는 모험"
    pages: List[SavePageRequest]

# 📚 새로 만든 동화를 팀원의 기존 Story / StoryPage 테이블로 통합 저장
@router.post("")
def save_story(req: SaveStoryRequest):
    if not req.pages:
        raise HTTPException(status_code=400, detail="저장할 페이지가 없습니다.")

    # 1. 전체 본문 텍스트 합치기
    full_content = "\n\n".join([p.content for p in req.pages if p.content])

    with Session(engine) as session:
        # 2. 메인 Story 레코드 생성 (is_user_story = True -> '내 이야기' 목록에 즉시 반영)
        book_id = f"custom_{uuid.uuid4().hex[:8]}"
        story = Story(
            book_id=book_id,
            title=req.title,
            original_title=req.title,
            language="ko",
            total_pages=len(req.pages),
            description=req.mood or "내가 직접 그린 동화",
            source_folder="",
            content=full_content,
            is_user_story=True,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        session.add(story)
        session.commit()
        session.refresh(story)

        # 3. 각 페이지의 Base64 이미지를 바이트로 변환하여 StoryPage에 저장
        for p in req.pages:
            img_bytes = b""
            img_data = p.image_url
            if img_data:
                try:
                    b64_str = img_data.split(",")[-1] if "," in img_data else img_data
                    img_bytes = base64.b64decode(b64_str)
                except Exception as e:
                    print(f"⚠️ [{p.page_number}화] 이미지 바이트 디코딩 실패: {e}")

            page = StoryPage(
                story_id=story.id,
                page_number=p.page_number,
                is_cover=False,
                original_text_content=p.content,
                text_content=p.content,
                original_image_data=img_bytes if img_bytes else None,
                image_data=img_bytes if img_bytes else None,
                original_image_mime_type="image/png",
                image_mime_type="image/png",
                original_image_filename=f"page_{p.page_number}.png",
                image_filename=f"page_{p.page_number}.png",
                created_at=datetime.utcnow(),
                updated_at=datetime.utcnow(),
            )
            session.add(page)

        session.commit()
        print(f"📚 [기존 DB 연동 보관 완료] Story ID={story.id}, Title='{story.title}' (총 {len(req.pages)}페이지)")

        return {"story_id": story.id, "message": "동화가 기존 서재에 성공적으로 등록되었습니다."}