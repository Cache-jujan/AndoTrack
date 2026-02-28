from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db

router = APIRouter()

@router.post("/register")
def register(db: Session = Depends(get_db)):
    return {"message": "register endpoint — coming soon"}

@router.post("/login")
def login(db: Session = Depends(get_db)):
    return {"message": "login endpoint — coming soon"}