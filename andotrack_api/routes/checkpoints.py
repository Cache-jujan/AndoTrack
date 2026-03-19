from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models.checkpoint import Checkpoint, RunnerCheckpoint
from utils.dependencies import get_current_user
from pydantic import BaseModel

router = APIRouter()

class CheckpointRequest(BaseModel):
    race_id: int
    name: str
    lat:float
    lng: float
    radius_meters: int = 20
    order_number: int

@router.get("/{race_id}")
def get_checkpoints(race_id: int, db: Session = Depends(get_db), user = Depends(get_current_user)):
    checkpoints = db.query(Checkpoint).filter(
        Checkpoint.race_id == race_id
    ).order_by(Checkpoint.order_number).all()
    return checkpoints

@router.post("/")
def create_checkpoint(body: CheckpointRequest, db: Session = Depends(get_db), user = Depends(get_current_user)):
    checkpoint = Checkpoint(
        race_id = body.race_id,
        name=body.name,
        lat=body.lat,
        lng = body.lng,
        radius_meters = body.radius_meters,
        order_number = body.order_number
    )
    db.add(checkpoint)
    db.commit()
    db.refresh(checkpoint)
    return checkpoint