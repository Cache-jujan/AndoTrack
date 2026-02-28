from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db

router = APIRouter()

@router.get("/")
def get_races(db: Session = Depends(get_db)):
    return {"message": "get races — coming soon"}

@router.post("/")
def create_race(db: Session = Depends(get_db)):
    return {"message": "create race — coming soon"}