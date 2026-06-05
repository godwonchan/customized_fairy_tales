import os
import base64
import tempfile
from typing import Optional, List, Dict
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()


def _get_openai_client() -> tuple[OpenAI, str]:
    api_key = os.getenv("OPENAI_API_KEY")
    model = os.getenv("OPENAI_IMAGE_MODEL", "gpt-image-2")

    if not api_key:
        raise RuntimeError("OPENAI_API_KEY가 .env에 설정되지 않았습니다.")

    client = OpenAI(api_key=api_key)
    return client, model


def _mime_to_suffix(mime_type: Optional[str]) -> str:
    mapping = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/webp": ".webp",
    }
    return mapping.get(mime_type or "", ".png")


def build_scene_preview_prompt(
    story_title: str,
    page_text: str,
    selected_text: str,
    interpreted_request: str,
    style_request: Optional[str] = None,
) -> str:
    style_line = style_request or "기존 동화책 삽화와 동일하거나 매우 유사한 그림체"

    return f"""
아동용 동화책 삽화를 생성한다.

중요:
- 입력으로 제공된 이미지들의 그림체를 최대한 유지해야 한다.
- 선화 느낌, 색감, 채색 방식, 캐릭터 얼굴 표현, 비율, 배경 분위기를 입력 이미지와 유사하게 유지한다.
- 특히 첫 번째 이미지는 현재 장면의 원본 이미지이므로, 이를 바탕으로 수정된 장면을 만든다.
- 다른 reference 이미지들은 전체 동화의 일관된 그림체를 유지하기 위한 참고 자료이다.

[동화 정보]
- 동화 제목: {story_title}
- 현재 페이지 내용: {page_text}

[수정 정보]
- 사용자가 선택한 원문: {selected_text}
- 사용자의 수정 의도: {interpreted_request}

[그림 스타일]
- {style_line}

[생성 지침]
- 수정 의도가 반영된 새로운 장면을 그린다.
- 현재 장면의 핵심 인물과 배경 분위기는 유지하되, 사용자의 수정 의도를 반영해 장면을 바꾼다.
- 동화책 삽화처럼 부드럽고 귀엽게 표현한다.
- 과하게 사실적이지 않게 한다.
- 텍스트, 말풍선, 워터마크는 넣지 않는다.
- 한 장의 완성된 동화책 장면처럼 구성한다.
""".strip()


def _bytes_to_temp_file(image_bytes: bytes, mime_type: Optional[str]) -> str:
    suffix = _mime_to_suffix(mime_type)
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.write(image_bytes)
    tmp.flush()
    tmp.close()
    return tmp.name


def generate_scene_preview_image(
    story_title: str,
    page_text: str,
    selected_text: str,
    interpreted_request: str,
    base_image_bytes: bytes,
    base_image_mime_type: Optional[str],
    reference_images: Optional[List[Dict]] = None,
    style_request: Optional[str] = None,
) -> tuple[bytes, str, str]:
    """
    base_image_bytes:
        현재 수정 중인 페이지의 원본 이미지
    reference_images:
        [{"image_data": bytes, "mime_type": "image/png"}, ...]
    """
    client, model = _get_openai_client()

    prompt = build_scene_preview_prompt(
        story_title=story_title,
        page_text=page_text,
        selected_text=selected_text,
        interpreted_request=interpreted_request,
        style_request=style_request,
    )

    temp_paths: List[str] = []
    opened_files = []

    try:
        # 1) 첫 번째 이미지 = 현재 페이지 원본 이미지
        base_path = _bytes_to_temp_file(base_image_bytes, base_image_mime_type)
        temp_paths.append(base_path)
        opened_files.append(open(base_path, "rb"))

        # 2) 추가 reference 이미지들
        if reference_images:
            for ref in reference_images[:3]:  # 너무 많으면 비효율적이므로 3장 정도만
                if not ref.get("image_data"):
                    continue
                ref_path = _bytes_to_temp_file(ref["image_data"], ref.get("mime_type"))
                temp_paths.append(ref_path)
                opened_files.append(open(ref_path, "rb"))

        result = client.images.edit(
            model=model,
            image=opened_files,
            prompt=prompt,
            size="1024x1024",
        )

        image_b64 = result.data[0].b64_json
        if not image_b64:
            raise RuntimeError("OpenAI 이미지 응답에 b64_json이 없습니다.")

        image_bytes = base64.b64decode(image_b64)
        mime_type = "image/png"

        return image_bytes, mime_type, prompt

    finally:
        for f in opened_files:
            try:
                f.close()
            except Exception:
                pass

        for path in temp_paths:
            try:
                os.remove(path)
            except Exception:
                pass