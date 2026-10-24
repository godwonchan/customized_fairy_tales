from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel
from typing import Optional
from sqlmodel import SQLModel, Field, Session, select
from app_core import engine
import hashlib
import secrets
import jwt
from datetime import datetime, timedelta

router = APIRouter(prefix="/auth", tags=["auth"])

SECRET_KEY = "fairytale_super_secret_key_change_in_production"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 30

# 정식 DB 테이블 모델 정의
class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(index=True, unique=True)
    password_hash: str
    nickname: str
    created_at: datetime = Field(default_factory=datetime.utcnow)

# Pydantic 스키마
class UserAuthRequest(BaseModel):
    username: str
    password: str
    nickname: Optional[str] = None

class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    username: str
    nickname: str

# 암호화 및 JWT
def get_password_hash(password: str) -> str:
    salt = secrets.token_hex(16)
    key = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt.encode('utf-8'), 100000)
    return f"{salt}${key.hex()}"

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        salt, key = hashed_password.split('$')
        new_key = hashlib.pbkdf2_hmac('sha256', plain_password.encode('utf-8'), salt.encode('utf-8'), 100000)
        return secrets.compare_digest(key, new_key.hex())
    except Exception:
        return False

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

# 1. 회원가입 (DB에 저장)
@router.post("/signup", response_model=TokenResponse)
def signup(request: UserAuthRequest):
    with Session(engine) as session:
        # 중복 아이디 검사
        existing_user = session.exec(select(User).where(User.username == request.username)).first()
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="이미 존재하는 아이디입니다."
            )

        hashed_pw = get_password_hash(request.password)
        nickname = request.nickname.strip() if request.nickname and request.nickname.strip() else request.username

        new_user = User(
            username=request.username,
            password_hash=hashed_pw,
            nickname=nickname,
        )
        session.add(new_user)
        session.commit()
        session.refresh(new_user)

        token = create_access_token({"sub": new_user.username})
        return {
            "access_token": token,
            "token_type": "bearer",
            "username": new_user.username,
            "nickname": new_user.nickname
        }

# 2. 로그인 (DB에서 조회)
@router.post("/login", response_model=TokenResponse)
def login(request: UserAuthRequest):
    with Session(engine) as session:
        user = session.exec(select(User).where(User.username == request.username)).first()
        if not user or not verify_password(request.password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="아이디 또는 비밀번호가 올바르지 않습니다."
            )

        token = create_access_token({"sub": user.username})
        return {
            "access_token": token,
            "token_type": "bearer",
            "username": user.username,
            "nickname": user.nickname
        }

# Pydantic 모델 추가
class UpdateNicknameRequest(BaseModel):
    username: str
    new_nickname: str

# 3. 닉네임 변경 API
@router.put("/nickname")
def update_nickname(request: UpdateNicknameRequest):
    with Session(engine) as session:
        user = session.exec(select(User).where(User.username == request.username)).first()
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="사용자를 찾을 수 없습니다."
            )

        clean_nick = request.new_nickname.strip()
        if not clean_nick:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="닉네임은 비워둘 수 없습니다."
            )

        user.nickname = clean_nick
        session.add(user)
        session.commit()
        session.refresh(user)

        return {
            "username": user.username,
            "nickname": user.nickname,
            "message": "닉네임이 성공적으로 변경되었습니다."
        }