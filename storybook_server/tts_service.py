import edge_tts
import urllib.request
import urllib.parse
import json
import re

# 1. 아동 동화용 뉴럴 보이스 설정
VOICE_KO = "ko-KR-SunHiNeural"   # 따뜻한 선생님 톤의 한국어 음성
VOICE_EN = "en-US-AnaNeural"      # 발음이 또렷한 어린이용 영어 음성

# 한글 포함 여부 검사
def has_korean(text: str) -> bool:
    return bool(re.search(r'[\uac00-\ud7a3]', text))

# 2. 구글 공식 무료 GTX 다이렉트 번역 함수 (차단/429 없음)
def translate_korean_to_english(korean_text: str) -> str:
    if not korean_text or not korean_text.strip():
        return ""
    try:
        url = "https://translate.googleapis.com/translate_a/single"
        params = {
            "client": "gtx",
            "sl": "ko",
            "tl": "en",
            "dt": "t",
            "q": korean_text.strip()
        }
        full_url = f"{url}?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(
            full_url,
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
        )

        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode("utf-8"))
            # 구글이 쪼개서 번역해 준 문장 조각들을 하나로 결합
            translated_segments = [item[0] for item in data[0] if item and item[0]]
            translated = "".join(translated_segments)
            print(f"[Translation Success]: {translated[:35]}...")
            return translated
    except Exception as e:
        print(f"[Translation Error]: {e}")
        return korean_text

# 3. 비동기 고품질 음성(MP3) 생성 함수
async def generate_speech_audio(text: str, language: str = "ko") -> bytes:
    clean_text = text.replace("\n", " ").strip()
    if not clean_text:
        raise Exception("읽을 텍스트가 비어있습니다.")

    # 영어 모드인데 아직 한글이 섞여있다면 에러 방지를 위해 한국어 음성으로 자동 안전 전환
    if language.lower() in ["en", "english"]:
        voice = VOICE_KO if has_korean(clean_text) else VOICE_EN
    else:
        voice = VOICE_KO

    communicate = edge_tts.Communicate(text=clean_text, voice=voice, rate="-5%")

    audio_data = bytearray()
    async for chunk in communicate.stream():
        if chunk["type"] == "audio":
            audio_data.extend(chunk["data"])

    # 만약 음성 생성이 비어있을 경우 한국어 음성으로 2차 재시도
    if not audio_data:
        communicate = edge_tts.Communicate(text=clean_text, voice=VOICE_KO, rate="-5%")
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_data.extend(chunk["data"])

    return bytes(audio_data)