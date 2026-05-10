from passlib.context import CryptContext
from jose import JWTError, jwt
from datetime import datetime, timedelta, timezone
import os

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)

def create_token(data: dict, race_id: int = None) -> str:
    payload = data.copy()
    if race_id is not None:
        payload["race_id"] = race_id
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=int(os.getenv("JWT_EXPIRE_MINUTES", 60))
    )
    payload.update({"exp": expire})
    return jwt.encode(
        payload,
        os.getenv("JWT_SECRET"),
        algorithm=os.getenv("JWT_ALGORITHM", "HS256")
    )

def decode_token(token: str) -> dict:
    return jwt.decode(
        token,
        os.getenv("JWT_SECRET"), # type: ignore
        algorithms=[os.getenv("JWT_ALGORITHM", "HS256")]
    )