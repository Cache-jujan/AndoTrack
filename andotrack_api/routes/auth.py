from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models.user import User
from schemas.user import RegisterRequest, LoginRequest, TokenResponse
from utils.auth import hash_password, verify_password, create_token

router = APIRouter()

@router.post("/register", response_model=TokenResponse)
def register(body: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == body.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        name=body.name,
        email=body.email,
        password=hash_password(body.password),
        role=body.role
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_token({"sub": str(user.id), "role": user.role})
    return TokenResponse(
        access_token=token,
        role=user.role,
        user_id=user.id,
        name=user.name
    )

@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    if not verify_password(body.password, user.password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    # Get race_id from staff assignment if user is staff
    race_id = None
    if user.role in ("kit_staff", "checkin_staff"):
        from models.staff_assignment import StaffAssignment
        assignment = db.query(StaffAssignment).filter(
            StaffAssignment.user_id == user.id,
            StaffAssignment.is_active == True
        ).first()
        if assignment:
            race_id = assignment.race_id

    token = create_token({"sub": str(user.id), "role": user.role}, race_id=race_id)
    return TokenResponse(
        access_token=token,
        role=user.role,
        user_id=user.id,
        name=user.name
    )