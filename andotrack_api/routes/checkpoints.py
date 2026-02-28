from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db

router = APIRouter()

@router.get("/{race_id}")
def get_checkpoints(race_id: int, db: Session = Depends(get_db)):
    return {"message": f"checkpoints for race {race_id} — coming soon"}

@router.post("/")
def create_checkpoint(db: Session = Depends(get_db)):
    return {"message": "create checkpoint — coming soon"}