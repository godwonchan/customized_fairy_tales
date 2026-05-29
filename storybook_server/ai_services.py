import os
import json
import base64
import tempfile
import re
from typing import Optional, List, Dict

from dotenv import load_dotenv
from openai import OpenAI

from app_core import (
    OPENAI_API_KEY,
    OPENAI_TEXT_MODEL,
    OPENAI_IMAGE_MODEL,
)

load_dotenv()


# =========================
# 0. OpenAI 클라이언트
# =========================
def _get_openai_client() -> OpenAI:
    if not OPENAI_API_KEY:
        raise RuntimeError("OPENAI_API_KEY가 .env에 설정되지 않았습니다.")
    return OpenAI(api_key=OPENAI_API_KEY)


# =========================
# 1. 공통 텍스트 호출
# =========================
def call_text_model(
    prompt: str,
    instructions: str = "You are a helpful assistant."
) -> str:
    client = _get_openai_client()

    response = client.responses.create(
        model=OPENAI_TEXT_MODEL,
        instructions=instructions,
        input=prompt,
    )

    text = getattr(response, "output_text", None)
    if not text:
        raise RuntimeError(f"OpenAI 텍스트 응답이 비어 있습니다. response={response}")

    return text.strip()


def _extract_json_list(raw_text: str, expected_count: int) -> List[str]:
    raw_text = raw_text.strip()

    if raw_text.startswith("```"):
        raw_text = raw_text.strip("`")
        raw_text = raw_text.replace("json", "", 1).strip()

    start = raw_text.find("[")
    end = raw_text.rfind("]")

    if start == -1 or end == -1 or end <= start:
        raise RuntimeError(f"JSON 배열을 찾지 못했습니다. raw_text={raw_text}")

    json_str = raw_text[start:end + 1]

    try:
        data = json.loads(json_str)
    except Exception as e:
        raise RuntimeError(f"JSON 파싱 실패: {e}, raw_text={raw_text}")

    if not isinstance(data, list):
        raise RuntimeError(f"JSON 결과가 list가 아닙니다. raw_text={raw_text}")

    cleaned = [str(x).strip() for x in data if str(x).strip()]

    if len(cleaned) < expected_count:
        raise RuntimeError(
            f"생성 개수가 부족합니다. expected={expected_count}, actual={len(cleaned)}, raw_text={raw_text}"
        )

    return cleaned[:expected_count]


# =========================
# 2. 동화 수정 관련 텍스트 함수
# =========================
def revise_story(original_story: str, user_request: str) -> str:
    prompt = f"""
기존 이야기의 전체 흐름은 최대한 유지하면서, 사용자 요청만 반영해 자연스럽게 수정하라.

규칙:
1. 기존 이야기의 전체 구조와 흐름은 유지한다.
2. 사용자 요청에 해당하는 부분만 반영한다.
3. 너무 어렵지 않은 한국어로 쓴다.
4. 설명하지 말고 수정된 동화 본문만 출력한다.

[기존 동화]
{original_story}

[사용자 요청]
{user_request}
""".strip()

    return call_text_model(
        prompt,
        instructions="You are an expert children's story editor. Return only the revised Korean story text."
    )


def interpret_sketch(
    selected_text: str,
    page_text: str,
    image_bytes: bytes,
    mime_type: str
) -> str:
    client = _get_openai_client()

    image_b64 = base64.b64encode(image_bytes).decode("utf-8")

    response = client.responses.create(
        model=OPENAI_TEXT_MODEL,
        instructions=(
            "You are a children's story editing assistant. "
            "Interpret the user's sketch and return exactly one short Korean sentence only."
        ),
        input=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": f"""
사용자가 동화의 특정 텍스트를 바꾸고 싶어서 낙서를 그렸다.

규칙:
1. 반드시 한 문장만 출력한다.
2. "selected_text를 ~로 바꾸고 싶다" 형태로 작성한다.
3. 설명, 추론과정, 부가 문장은 쓰지 않는다.

[밑줄친 텍스트]
{selected_text}

[해당 페이지 내용]
{page_text}
""".strip(),
                    },
                    {
                        "type": "input_image",
                        "image_url": f"data:{mime_type};base64,{image_b64}",
                    },
                ],
            }
        ],
    )

    text = getattr(response, "output_text", None)
    if not text:
        raise RuntimeError(f"낙서 해석 실패: response={response}")

    return text.strip()


def revise_story_from_confirmed_request(
    original_story: str,
    selected_text: str,
    confirmed_request: str
) -> str:
    prompt = f"""
사용자가 확인한 변경 요청을 반영해 전체 동화를 자연스럽게 다시 써라.

규칙:
1. 전체 이야기 흐름은 최대한 자연스럽게 유지한다.
2. 밑줄친 대상과 관련된 장면들만 일관되게 수정한다.
3. 확인된 변경 요청을 기준으로 수정한다.
4. 너무 어렵지 않은 한국어로 쓴다.
5. 설명하지 말고 수정된 동화 본문만 출력한다.

[기존 전체 동화]
{original_story}

[변경 대상 텍스트]
{selected_text}

[사용자 확인 완료된 변경 요청]
{confirmed_request}
""".strip()

    return call_text_model(
        prompt,
        instructions="You are an expert children's story editor. Return only the revised Korean story."
    )


def revise_pages_from_confirmed_request(
    page_texts: List[str],
    edited_page_number: int,
    selected_text: str,
    confirmed_request: str,
) -> List[str]:
    if edited_page_number < 1 or edited_page_number > len(page_texts):
        raise RuntimeError(
            f"edited_page_number 범위 오류: {edited_page_number}, total_pages={len(page_texts)}"
        )

    pages_block = "\n".join(
        [f"{idx + 1}. {text}" for idx, text in enumerate(page_texts)]
    )

    prompt = f"""
너는 아동용 동화를 페이지 단위로 수정하는 편집자다.

입력된 동화는 총 {len(page_texts)}페이지로 구성되어 있다.
사용자는 {edited_page_number}페이지의 특정 내용을 수정하고자 한다.

가장 중요한 규칙:
1. {edited_page_number}페이지 이전 페이지들은 절대 수정하지 마라.
2. {edited_page_number}페이지는 사용자의 요청을 반영해 수정하라.
3. {edited_page_number}페이지 이후의 페이지들은 최소 수정이 아니라,
   수정된 사건과 자연스럽게 이어지도록 서사 연결성을 중심으로 다시 작성하라.
4. 이후 페이지들은 앞 장면에서 바뀐 설정, 사건, 감정, 행동의 결과를 반영해야 한다.
5. 전체 페이지 수는 유지하라.
6. 각 페이지는 원래 페이지와 비슷한 분량으로 작성하라.
7. 각 페이지 내용은 해당 페이지에 들어갈 정도의 분량으로만 작성하라.
8. 한 페이지에 전체 이야기 내용을 몰아넣지 마라.
9. 수정 전 페이지의 내용은 그대로 유지하고, 수정 이후 페이지는 새 흐름에 맞게 자연스럽게 이어지게 써라.
10. 출력은 반드시 페이지별 JSON 배열만 반환하라.

출력 예시:
["1페이지 내용", "2페이지 내용", "3페이지 내용"]

[수정 대상 페이지 번호]
{edited_page_number}

[변경 대상 텍스트]
{selected_text}

[사용자 요청]
{confirmed_request}

[원래 페이지들]
{pages_block}
""".strip()

    raw_text = call_text_model(
        prompt,
        instructions=(
            "You are an expert children's story editor. "
            "Return only a JSON array of Korean page texts. "
            "Pages before the edited page must remain unchanged. "
            "Pages after the edited page must be rewritten mainly for narrative continuity. "
            "Do not include markdown or explanations."
        )
    )

    return _extract_json_list(raw_text, len(page_texts))


# =========================
# 3. 플롯 재배치 / 본문 생성
# =========================
def rearrange_plots(
    story_content: str,
    plot_count: int,
    required_changes: Optional[str] = None,
    style_request: Optional[str] = None
) -> List[str]:
    extra_style = style_request if style_request else "각 플롯은 이미지 한 장으로 대표 가능한 단일 장면이어야 한다."
    must_keep = required_changes if required_changes else "없음"

    prompt = f"""
너는 아동용 동화를 이미지 생성용 장면 단위로 분해하는 편집자다.

목표:
전체 동화를 정확히 {plot_count}개의 플롯 요약으로 나눈다.

가장 중요한 규칙:
- 각 플롯은 이미지 한 장으로 표현 가능한 '하나의 장면'이어야 한다.
- 한 플롯 안에 여러 사건을 넣지 않는다.
- 시간 순서대로 나눈다.
- 앞 플롯과 뒤 플롯이 겹치지 않게 한다.
- 한 플롯에는 한 장소, 한 순간, 한 핵심 행동만 담는다.
- 절대로 전체 동화 내용을 한 플롯에 몰아넣지 않는다.
- 각 플롯 요약은 1문장 또는 최대 2문장으로 아주 짧게 쓴다.
- 각 플롯은 대표 삽화 한 장을 만들 수 있을 정도로 간단해야 한다.
- 반드시 정확히 {plot_count}개를 만들어라.

반드시 유지할 변경 사항:
{must_keep}

추가 스타일 요청:
{extra_style}

출력 형식:
- 설명 없이 JSON 배열만 출력한다.
- 각 원소는 짧은 한국어 문자열이다.
- 예시:
["플롯1 요약", "플롯2 요약", "플롯3 요약"]

전체 줄거리:
{story_content}
""".strip()

    raw_text = call_text_model(
        prompt,
        instructions=(
            "You are an expert children's story scene planner. "
            "Return only a JSON array of short Korean plot summaries. "
            "Each plot must describe a single scene that can be illustrated with one image. "
            "Do not include markdown or explanations."
        )
    )

    return _extract_json_list(raw_text, plot_count)


def generate_plot_contents(
    plot_summaries: List[str],
    required_changes: Optional[str] = None,
    style_request: Optional[str] = None
) -> List[str]:
    must_keep = required_changes if required_changes else "없음"
    extra_style = style_request if style_request else "각 플롯을 동화책 본문처럼 2~4문장으로 작성하라."

    joined_plots = "\n".join(
        [f"{idx + 1}. {summary}" for idx, summary in enumerate(plot_summaries)]
    )

    prompt = f"""
너는 아동용 동화책 작가다.

아래에 {len(plot_summaries)}개의 플롯 요약이 있다.
각 플롯 요약에 대응하는 본문을 각각 따로 작성하라.

중요:
- 각 본문은 해당 플롯 요약에 해당하는 장면만 써야 한다.
- 전체 동화를 반복해서 쓰면 안 된다.
- 다른 플롯 내용이 섞이면 안 된다.
- 각 플롯 본문은 2~4문장으로 작성한다.
- 앞뒤 플롯과 겹치지 않게 한다.
- 정확히 {len(plot_summaries)}개의 본문을 만들어라.
- 한 플롯 본문 안에 너무 많은 사건을 넣지 않는다.

반드시 유지할 변경 사항:
{must_keep}

추가 스타일 요청:
{extra_style}

플롯 요약 목록:
{joined_plots}

출력 형식:
- 설명 없이 JSON 배열만 출력한다.
- 각 원소는 문자열이다.
- 예시:
["플롯1 본문", "플롯2 본문", "플롯3 본문"]
""".strip()

    raw_text = call_text_model(
        prompt,
        instructions=(
            "You are an expert children's story writer. "
            "Return only a JSON array of Korean plot contents. "
            "Each item should describe only its corresponding plot summary. "
            "Do not include markdown or explanations."
        )
    )

    return _extract_json_list(raw_text, len(plot_summaries))


# =========================
# 4. 이미지용 일반화된 안전 변환
# =========================
def _normalize_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def soften_risky_image_text(text: str) -> str:
    """
    텍스트 자체는 유지하되, 이미지용 묘사에서는 더 부드럽고 안전한 표현으로 변환한다.
    특정 동화/플롯 번호 하드코딩이 아니라 표현 유형 기반으로 일반화.
    """
    if not text:
        return ""

    result = text

    # 독/위험 물질 계열
    replacements = [
        ("독이 든", "수상한 마법이 걸린"),
        ("독이든", "수상한 마법이 걸린"),
        ("독이 묻은", "신비한 마법이 스며든"),
        ("독사과", "마법이 걸린 사과"),
        ("독 오렌지", "마법이 걸린 오렌지"),
        ("독이 든 오렌지", "수상한 마법이 걸린 오렌지"),
        ("독이 든 사과", "수상한 마법이 걸린 사과"),
    ]

    # 쓰러짐 / 기절 / 죽음 유사
    replacements += [
        ("먹고 쓰러진", "먹은 뒤 눈을 감고 조용히 누워 있는"),
        ("먹은 뒤 쓰러진", "먹은 뒤 눈을 감고 조용히 누워 있는"),
        ("쓰러지고 말았어요", "눈을 감고 조용히 누워 있었어요"),
        ("쓰러지고 말았다", "눈을 감고 조용히 누워 있었다"),
        ("쓰러졌다", "눈을 감고 조용히 누워 있었다"),
        ("쓰러진다", "눈을 감고 조용히 누워 있다"),
        ("기절했다", "눈을 감고 조용히 누워 있었다"),
        ("깨어나지 못했다", "깊은 잠에 빠진 듯 보였다"),
        ("죽은 듯", "깊이 잠든 듯"),
        ("죽은 것처럼", "깊이 잠든 것처럼"),
        ("죽었다", "깊은 잠에 빠진 듯 보였다"),
        ("죽음", "긴 잠"),
        ("시체", "잠든 모습"),
    ]

    # 관/유리관
    replacements += [
        ("유리관", "투명한 관"),
        ("관 속", "투명한 관 안"),
        ("관안", "투명한 관 안"),
    ]

    # 직접적인 접촉
    replacements += [
        ("키스", "다정하게 가까이 다가감"),
        ("입맞춤", "다정한 인사"),
    ]

    # 강한 종결/처벌
    replacements += [
        ("비참한 최후", "모든 마법이 사라진 뒤 이야기에서 멀어짐"),
        ("잔인한 최후", "이야기에서 멀어짐"),
    ]

    for old, new in replacements:
        result = result.replace(old, new)

    return _normalize_spaces(result)


def detect_risk_categories(text: str) -> Dict[str, bool]:
    text = text or ""

    return {
        "poison": any(k in text for k in ["독", "중독", "독사과", "독이 든", "독이든"]),
        "collapse": any(k in text for k in ["쓰러", "기절", "넘어졌", "의식", "깊은 잠", "깨어나지"]),
        "coffin": any(k in text for k in ["유리관", "관 속", "관안", "관"]),
        "kiss": any(k in text for k in ["키스", "입맞춤"]),
        "death_like": any(k in text for k in ["죽", "시체", "최후"]),
    }


def build_safe_image_scene_description(plot_summary: str, plot_content: str) -> str:
    """
    원문 텍스트는 유지하되, 이미지 프롬프트에 들어갈 장면 설명만 안전하게 만든다.
    핵심 사건은 살리되, 직접적 위험 장면은 더 부드럽고 아동용 동화 스타일로 완화.
    """
    original = _normalize_spaces(f"{plot_summary}. {plot_content}")
    softened_summary = soften_risky_image_text(plot_summary)
    softened_content = soften_risky_image_text(plot_content)
    softened = _normalize_spaces(f"{softened_summary}. {softened_content}")
    risks = detect_risk_categories(original)

    # 여러 위험 요소가 있으면 "직전/직후의 안전한 순간"을 강조
    if risks["poison"] and risks["collapse"]:
        return (
            "숲속 오두막에서 수상한 마법이 걸린 과일을 들고 있는 인물과 "
            "그 과일을 바라보는 주인공이 등장하고, "
            "이후 주인공은 눈을 감고 조용히 누워 있는 모습으로 표현되는 "
            "긴장감 있지만 부드러운 아동용 동화책 장면"
        )

    if risks["coffin"] and risks["kiss"]:
        return (
            "밝은 햇살이 비치는 숲속에서 깊은 잠에서 깨어난 듯한 주인공이 "
            "주변 인물들과 다시 만나 미소 짓는 따뜻하고 평화로운 결말 장면"
        )

    if risks["coffin"]:
        return (
            "꽃으로 둘러싸인 투명한 관 안에서 주인공이 눈을 감고 평온하게 누워 있고, "
            "주변 인물들이 조용히 바라보는 동화책 장면"
        )

    if risks["kiss"]:
        return (
            "두 인물이 서로에게 다정하게 가까이 다가가며 다시 만나는 "
            "따뜻하고 평화로운 동화책 장면"
        )

    if risks["collapse"]:
        return (
            "주인공이 눈을 감고 조용히 누워 있고 주변 장면은 부드럽고 평온하게 표현된 "
            "아동용 동화책 장면. "
            + softened
        )

    return softened


# =========================
# 5. 장면 이미지 생성
# =========================
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
    safe_page_text = soften_risky_image_text(page_text)
    safe_request = soften_risky_image_text(interpreted_request)

    return f"""
Create a child-safe illustrated storybook scene.

Important:
- Match the visual style of the reference images as closely as possible.
- Keep the same line quality, coloring style, character proportions, facial style, and overall atmosphere.
- The first reference image is the original scene. Create a revised version of that scene.
- Preserve the meaning of the scene, but describe risky moments in a softer and gentler visual way.

Story info:
- Title: {story_title}
- Current page text: {safe_page_text}

Requested revision:
- Selected original text: {selected_text}
- Intended change: {safe_request}

Style:
- {style_line}

Safety requirements:
- This must look like a gentle children's picture book illustration.
- All characters must appear safe, awake or peacefully resting, calm, and comfortable.
- Characters should be fully clothed and non-sexualized.
- Do not depict graphic danger, fear, drowning, injury, death, suffering, unconsciousness, or distress directly.
- If the original scene includes danger-like elements, depict them in a softer fairy-tale way.
- Use a warm, magical, peaceful fantasy atmosphere.
- No text, captions, speech bubbles, or watermark.

Composition requirements:
- Show a clear, friendly, child-safe fairy tale moment.
- Bright, soft lighting.
- Peaceful facial expressions.
- Whimsical and gentle picture-book mood.
""".strip()


def build_scene_preview_prompt_safe_fallback(
    story_title: str,
    page_text: str,
    selected_text: str,
    interpreted_request: str,
    style_request: Optional[str] = None,
) -> str:
    style_line = style_request or "기존 동화책 삽화와 동일하거나 매우 유사한 그림체"
    safe_page_text = soften_risky_image_text(page_text)
    safe_request = soften_risky_image_text(interpreted_request)

    return f"""
Create a warm, peaceful, child-safe fairy tale illustration in the same style as the reference images.

Scene requirements:
- A calm magical storybook moment
- Bright and soft colors
- Gentle expressions
- Safe, awake, relaxed, or peacefully resting characters
- Friendly fantasy environment
- No direct danger, no visible suffering, no injury, no death, no water emergency, no rescue scene
- No realism, no graphic detail, no scary mood
- Fully clothed characters only
- Keep the same storybook art style as the reference images

Story title:
{story_title}

Scene goal:
Create a safe and gentle revised version of the original scene based on this change:
{safe_request}

Selected text:
{selected_text}

Current page text:
{safe_page_text}

Style:
{style_line}
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
    client = _get_openai_client()

    primary_prompt = build_scene_preview_prompt(
        story_title=story_title,
        page_text=page_text,
        selected_text=selected_text,
        interpreted_request=interpreted_request,
        style_request=style_request,
    )

    fallback_prompt = build_scene_preview_prompt_safe_fallback(
        story_title=story_title,
        page_text=page_text,
        selected_text=selected_text,
        interpreted_request=interpreted_request,
        style_request=style_request,
    )

    temp_paths: List[str] = []
    opened_files = []

    try:
        base_path = _bytes_to_temp_file(base_image_bytes, base_image_mime_type)
        temp_paths.append(base_path)
        opened_files.append(open(base_path, "rb"))

        if reference_images:
            for ref in reference_images[:3]:
                if not ref.get("image_data"):
                    continue
                ref_path = _bytes_to_temp_file(ref["image_data"], ref.get("mime_type"))
                temp_paths.append(ref_path)
                opened_files.append(open(ref_path, "rb"))

        try:
            result = client.images.edit(
                model=OPENAI_IMAGE_MODEL,
                image=opened_files,
                prompt=primary_prompt,
                size="1024x1024",
            )
            used_prompt = primary_prompt
        except Exception as e:
            print("Primary image prompt blocked or failed:", repr(e))
            result = client.images.edit(
                model=OPENAI_IMAGE_MODEL,
                image=opened_files,
                prompt=fallback_prompt,
                size="1024x1024",
            )
            used_prompt = fallback_prompt

        image_b64 = result.data[0].b64_json
        if not image_b64:
            raise RuntimeError("OpenAI 이미지 응답에 b64_json이 없습니다.")

        image_bytes = base64.b64decode(image_b64)
        return image_bytes, "image/png", used_prompt

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


# =========================
# 6. 플롯 이미지 생성
# =========================
def generate_plot_image_prompt(
    story_title: str,
    plot_number: int,
    plot_summary: str,
    plot_content: str,
    style_reference_hint: str,
    style_request: Optional[str] = None
) -> str:
    style_text = style_request if style_request else "기존 동화 삽화와 유사한 따뜻하고 귀여운 2D 아동용 동화책 그림체"
    safe_scene_description = build_safe_image_scene_description(
        plot_summary=plot_summary,
        plot_content=plot_content,
    )

    prompt = f"""
Create a child-safe picture book illustration prompt.

Important rules:
- Keep the original story meaning and major event.
- However, express risky moments in a softer and visually safer way.
- Focus on one single scene only.
- Do not combine multiple events into one image.
- Match the reference storybook style closely.
- Keep the same overall linework, coloring, facial style, and atmosphere.
- All characters must appear safe, calm, fully clothed, and child-appropriate.
- If a scene involves poison, collapse, a glass coffin, a kiss, or death-like expressions,
  describe the same moment in a gentler fairy-tale way rather than directly.
- No graphic injury, no visible suffering, no frightening realism.
- No dark horror mood.

Story title:
{story_title}

Plot number:
{plot_number}

Original plot summary:
{plot_summary}

Original plot content:
{plot_content}

Safe visual scene description:
{safe_scene_description}

Style reference:
{style_reference_hint}

Style:
{style_text}

Return only a single clean image-generation prompt paragraph.
""".strip()

    return call_text_model(
        prompt,
        instructions=(
            "You write safe, high-quality prompts for children's storybook illustration generation. "
            "Preserve the story scene, but phrase it in a softer and child-safe visual way."
        )
    )


def _extract_image_bytes_from_image_generation_result(result) -> tuple[bytes, str]:
    image_b64 = result.data[0].b64_json
    if not image_b64:
        raise RuntimeError("OpenAI 이미지 응답에 b64_json이 없습니다.")
    return base64.b64decode(image_b64), "image/png"


def generate_plot_image_bytes(
    image_prompt: str,
    plot_number: int,
    reference_images: List[dict]
) -> tuple[bytes, str, str]:
    client = _get_openai_client()

    temp_paths: List[str] = []
    opened_files = []

    try:
        if reference_images:
            for ref in reference_images[:3]:
                if not ref.get("image_data"):
                    continue
                ref_path = _bytes_to_temp_file(ref["image_data"], ref.get("mime_type"))
                temp_paths.append(ref_path)
                opened_files.append(open(ref_path, "rb"))

        try:
            if opened_files:
                result = client.images.edit(
                    model=OPENAI_IMAGE_MODEL,
                    image=opened_files,
                    prompt=image_prompt,
                    size="1024x1024",
                )
            else:
                result = client.images.generate(
                    model=OPENAI_IMAGE_MODEL,
                    prompt=image_prompt,
                    size="1024x1024",
                )
        except Exception as e:
            print("Plot image prompt blocked or failed:", repr(e))

            safer_prompt = (
                f"{image_prompt}\n\n"
                "Make the image clearly child-safe, peaceful, magical, and gentle. "
                "Represent only one simple fairy-tale scene. "
                "If the story implies danger, express it softly rather than directly. "
                "All characters must appear safe, calm, fully clothed, and child-appropriate. "
                "Avoid graphic harm, visible suffering, fear, or dark realistic mood."
            )

            if opened_files:
                result = client.images.edit(
                    model=OPENAI_IMAGE_MODEL,
                    image=opened_files,
                    prompt=safer_prompt,
                    size="1024x1024",
                )
            else:
                result = client.images.generate(
                    model=OPENAI_IMAGE_MODEL,
                    prompt=safer_prompt,
                    size="1024x1024",
                )

        image_bytes, mime_type = _extract_image_bytes_from_image_generation_result(result)
        return image_bytes, mime_type, f"plot_{plot_number}.png"

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