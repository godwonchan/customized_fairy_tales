# AI 기반 아동 맞춤형 동화 생성 시스템

생성형 AI와 드로잉 입력을 결합하여,  
아동이 기존 동화에 직접 개입하고 이후 이야기를 새롭게 재구성할 수 있도록 하는 **참여형 동화 창작 시스템**입니다.

---

## 1. 프로젝트 소개

기존 AI 동화 생성 서비스는 대부분 텍스트 입력 기반으로 동작합니다.  
하지만 미취학 아동이나 초등 저학년의 경우, 긴 문장을 직접 입력하거나 논리적으로 줄거리를 구성하는 데 어려움이 있습니다.

본 프로젝트는 이러한 문제를 해결하기 위해,  
아동이 **텍스트 대신 그림으로 수정 의도**를 표현하면  
AI가 이를 바탕으로 **스토리와 삽화를 함께 재구성**하는 시스템을 구현했습니다.

즉, 단순히 AI가 동화를 대신 만들어주는 것이 아니라,  
아이가 직접 그림을 그리고 이야기 흐름을 바꾸는 **양방향 상호작용형 동화 서비스**를 목표로 합니다.

### 핵심 기능
- 기존 동화 읽기
- 수정할 장면 선택
- 그림 기반 수정 의도 입력
- AI 기반 스토리 및 이미지 재생성
- 결과 확인 후 제목 입력 저장
- 나의 책장에서 다시 열람 및 재수정

---

## 2. 기술 스택

### Frontend
- Flutter
- Dart

### Backend
- FastAPI
- Python

### Database
- MySQL

### AI
- OpenAI API
- 이미지 생성 모델(DALL·E 계열)

### Version Control
- Git
- GitHub

---

## 3. 프로젝트 구조

```bash
customized_fairy_tales/
├─ assets/
│  ├─ book_001_Snow_White/
│  │  ├─ cover.png
│  │  ├─ metadata.json
│  │  ├─ story_data.json
│  │  ├─ page_01.txt
│  │  ├─ page_01.png
│  │  └─ ...
│  └─ book_003_Cinderella/
│     ├─ cover.png
│     ├─ metadata.json
│     ├─ story_data.json
│     └─ ...
├─ lib/
│  ├─ data/
│  ├─ screens/
│  ├─ services/
│  ├─ utils/
│  └─ widgets/
├─ storybook_server/
│  ├─ main.py
│  ├─ ai_services.py
│  ├─ app_core.py
│  └─ ...
├─ pubspec.yaml
└─ README.md
