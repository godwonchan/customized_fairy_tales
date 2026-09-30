# storybook_server/routers/lumi_chat.py
import asyncio
import base64
import os
from fastapi import APIRouter, HTTPException
from openai import OpenAI
from pydantic import BaseModel

router = APIRouter(prefix="/api/chat", tags=["Lumi Chat"])
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

class LumiChatRequest(BaseModel):
    question: str
    category_title: str = "주인공"

class LumiChatResponse(BaseModel):
    reply: str
    audio_base64: str | None = None

class LumiTtsRequest(BaseModel):
    text: str

class LumiTtsResponse(BaseModel):
    audio_base64: str

# 🧚 OpenAI tts-1 요정 루미 목소리 생성 함수
async def generate_lumi_voice(text: str) -> str:
    """
    OpenAI tts-1 모델을 사용하여 감정이 풍부한 한국어 음성을 생성합니다.
    - voice: 'nova' (귀엽고 발랄한 요정 톤, 'shimmer'로 변경 가능)
    - speed: 1.05 (지루하지 않고 통통 튀는 템포)
    """
    try:
        # 이모지는 음성 합성 시 어색할 수 있으므로 간단히 정제
        cleaned_text = text.replace("✨", "").replace("🎨", "").replace("🌟", "").replace("👂", "").replace("📖", "").strip()
        if not cleaned_text:
            return ""

        # 동기 호출을 비동기 스레드로 넘겨 서버 병목 방지
        def _call_openai_tts():
            response = client.audio.speech.create(
                model="tts-1",
                voice="shimmer",  # 👈 'nova'(추천: 발랄하고 맑은 톤) 또는 'shimmer'(차분하고 따뜻한 톤)
                input=cleaned_text,
                speed=1.05,
                response_format="mp3",
            )
            return response.content

        audio_bytes = await asyncio.to_thread(_call_openai_tts)
        return base64.b64encode(audio_bytes).decode("utf-8")

    except Exception as e:
        print(f"❌ OpenAI TTS 음성 생성 실패: {e}")
        return ""

# 💡 1. 텍스트를 루미 목소리로 변환해주는 전용 엔드포인트
@router.post("/tts", response_model=LumiTtsResponse)
async def text_to_speech(req: LumiTtsRequest):
    if not req.text.strip():
        raise HTTPException(status_code=400, detail="텍스트가 비어있습니다.")

    audio_b64 = await generate_lumi_voice(req.text)
    return LumiTtsResponse(audio_base64=audio_b64)

# 💡 2. GPT 대화 답변 생성 + 루미 목소리 동시 합성 엔드포인트
@router.post("/lumi", response_model=LumiChatResponse)
async def chat_with_lumi(req: LumiChatRequest):
    if not req.question.strip():
        raise HTTPException(status_code=400, detail="질문이 비어있습니다.")

    # 💡 "우와!", "와!" 감탄사 금지 및 자연스러운 친구 같은 말투 규칙 적용
    system_prompt = f"""
    너는 6~8세 아이의 상상력을 북돋아 주는 다정하고 친근한 이야기 요정 '루미'야.
    현재 아이는 동화의 [{req.category_title}]을(를) 그리고 있어.

    [대화 규칙]
    1. '우와!', '와!', '대박!' 같은 과장되고 반복적인 감탄사로 문장을 절대 시작하지 마.
    2. 영혼 없는 기계적 칭찬 대신, 아이가 질문한 핵심에 친구처럼 바로 다정하게 맞장구쳐 줘.
    3. 아이가 듣기 편한 부드럽고 자연스러운 반말로 2문장 이내로 짧게 대답해.
    4. 그림에 넣을 만한 기발하고 아기자기한 아이디어를 하나 건네줘.
    """

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": req.question}
            ],
            max_tokens=120,
            temperature=0.7,
        )
        reply_text = response.choices[0].message.content.strip()

        # 생성된 답변 텍스트로 OpenAI tts-1 음성 합성
        audio_b64 = await generate_lumi_voice(reply_text)

        return LumiChatResponse(reply=reply_text, audio_base64=audio_b64)

    except Exception as e:
        print(f"루미 응답 생성 실패: {e}")
        fallback_text = "정말 좋은 생각이야! 네가 상상한 그대로 캔버스에 자유롭게 그려봐! ✨"
        fallback_audio = await generate_lumi_voice(fallback_text)
        return LumiChatResponse(reply=fallback_text, audio_base64=fallback_audio)