from pydantic import BaseModel

class RegisterRequest(BaseModel):
    name: str
    email: str
    password: str
    role: str = "runner"

class LoginRequest(BaseModel):
    email: str
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: int
    name: str