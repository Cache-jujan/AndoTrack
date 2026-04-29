from utils.dependencies import get_current_user
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from database import get_db
from models.checkpoint import Checkpoint, RunnerCheckpoint

router = APIRouter()

# ── Inline models (no separate schema file needed) ────────

class CheckpointCreate(BaseModel):
    race_id: int
    name: str
    lat: float
    lng: float
    radius_meters: Optional[int] = 20
    order_number: int

# ── Routes ────────────────────────────────────────────────

@router.get("/{race_id}")
def get_checkpoints(race_id: int, db: Session = Depends(get_db)):
    return db.query(Checkpoint).filter(
        Checkpoint.race_id == race_id
    ).order_by(Checkpoint.order_number).all()


@router.post("/")
def create_checkpoint(body: CheckpointCreate, db: Session = Depends(get_db)):
    existing = db.query(Checkpoint).filter(
        Checkpoint.race_id == body.race_id,
        Checkpoint.order_number == body.order_number
    ).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Order number {body.order_number} already exists in this race."
        )
    checkpoint = Checkpoint(**body.model_dump())
    db.add(checkpoint)
    db.commit()
    db.refresh(checkpoint)
    return checkpoint


@router.post("/{checkpoint_id}/arrive")
def runner_arrive(checkpoint_id: int, runner_id: int, db: Session = Depends(get_db)):
    checkpoint = db.query(Checkpoint).filter(Checkpoint.id == checkpoint_id).first()
    if not checkpoint:
        raise HTTPException(status_code=404, detail="Checkpoint not found.")
    existing = db.query(RunnerCheckpoint).filter(
        RunnerCheckpoint.runner_id == runner_id,
        RunnerCheckpoint.checkpoint_id == checkpoint_id
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Runner already recorded at this checkpoint.")
    record = RunnerCheckpoint(runner_id=runner_id, checkpoint_id=checkpoint_id)
    db.add(record)
    db.commit()
    db.refresh(record)
    return {"message": "Checkpoint arrival recorded.", "record_id": record.id}


@router.get("/{race_id}/runner/{runner_id}/progress")
def runner_progress(race_id: int, runner_id: int, db: Session = Depends(get_db)):
    total = db.query(Checkpoint).filter(Checkpoint.race_id == race_id).count()
    completed = db.query(RunnerCheckpoint).join(
        Checkpoint, RunnerCheckpoint.checkpoint_id == Checkpoint.id
    ).filter(
        Checkpoint.race_id == race_id,
        RunnerCheckpoint.runner_id == runner_id
    ).count()
    return {
        "runner_id": runner_id,
        "race_id": race_id,
        "completed": completed,
        "total": total,
        "percent": round((completed / total) * 100, 1) if total > 0 else 0.0
    }


@router.delete("/{checkpoint_id}")
def delete_checkpoint(
    checkpoint_id: int, 
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can delete checkpoints.")

    checkpoint = db.query(Checkpoint).filter(Checkpoint.id == checkpoint_id).first()
    if not checkpoint:
        raise HTTPException(status_code=404, detail="Checkpoint not found.")
    
    # Also delete any runner checkpoint records tied to this checkpoint
    db.query(RunnerCheckpoint).filter(
        RunnerCheckpoint.checkpoint_id == checkpoint_id
    ).delete()
    
    db.delete(checkpoint)
    db.commit()
    return {"message": f"Checkpoint {checkpoint_id} deleted."}  