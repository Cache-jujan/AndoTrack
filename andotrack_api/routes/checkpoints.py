"""
routers/checkpoints.py  ─  AndoTrack
────────────────────────────────────────────────────────────────────────────
Fixes:
  • Adds PUT  /checkpoints/{checkpoint_id}   (full replace – Flutter PUT calls)
  • Expands PATCH /checkpoints/{checkpoint_id} to also accept lat/lng/order
  • Adds POST /checkpoints/bulk              (auto-checkpoint save after route gen)
  • Route-ordering fix: specific paths before wildcard /{race_id}
────────────────────────────────────────────────────────────────────────────
"""

from utils.dependencies import get_current_user
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, field_validator
from typing import Optional, List
from database import get_db
from models.checkpoint import Checkpoint, RunnerCheckpoint

router = APIRouter()


# ── Pydantic models ───────────────────────────────────────────────────────────

class CheckpointCreate(BaseModel):
    race_id: int
    name: str
    lat: float
    lng: float
    radius_meters: Optional[int] = 20
    order_number: int


class CheckpointBulkItem(BaseModel):
    """Single item inside a bulk-create request."""
    name: str
    lat: float
    lng: float
    radius_meters: Optional[int] = 20
    order_number: int


class CheckpointBulkCreate(BaseModel):
    race_id: int
    checkpoints: List[CheckpointBulkItem]
    replace_existing: bool = False  # wipe old checkpoints for this race first


class CheckpointUpdate(BaseModel):
    """PATCH – all fields optional; supply only what changes."""
    name: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    radius_meters: Optional[int] = None
    order_number: Optional[int] = None

    @field_validator("name")
    @classmethod
    def name_not_blank(cls, v):
        if v is not None and not v.strip():
            raise ValueError("name cannot be empty")
        return v.strip() if v else v

    @field_validator("radius_meters")
    @classmethod
    def radius_in_range(cls, v):
        if v is not None and not (10 <= v <= 500):
            raise ValueError("radius_meters must be between 10 and 500")
        return v


class CheckpointFullUpdate(BaseModel):
    """PUT – all fields required (full replacement)."""
    name: str
    lat: float
    lng: float
    radius_meters: int = 20
    order_number: int

    @field_validator("name")
    @classmethod
    def name_not_blank(cls, v):
        if not v.strip():
            raise ValueError("name cannot be empty")
        return v.strip()

    @field_validator("radius_meters")
    @classmethod
    def radius_in_range(cls, v):
        if not (10 <= v <= 500):
            raise ValueError("radius_meters must be between 10 and 500")
        return v


# ── Helper ────────────────────────────────────────────────────────────────────

def _require_organizer(user):
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can modify checkpoints.")


def _get_or_404(db: Session, checkpoint_id: int) -> Checkpoint:
    cp = db.query(Checkpoint).filter(Checkpoint.id == checkpoint_id).first()
    if not cp:
        raise HTTPException(status_code=404, detail="Checkpoint not found.")
    return cp


# ── Specific paths FIRST (before wildcard /{race_id}) ────────────────────────

@router.post("/bulk", summary="Bulk-create checkpoints (after route generation)")
def create_checkpoints_bulk(
    body: CheckpointBulkCreate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Saves an array of auto-generated checkpoints for a race in one request.
    If replace_existing=True, existing checkpoints for the race are deleted first.
    Used by SmartRouteScreen after generating a route.
    """
    _require_organizer(user)

    if body.replace_existing:
        # cascade: delete runner_checkpoints first, then checkpoints
        existing_ids = [
            row.id
            for row in db.query(Checkpoint.id)
            .filter(Checkpoint.race_id == body.race_id)
            .all()
        ]
        if existing_ids:
            db.query(RunnerCheckpoint).filter(
                RunnerCheckpoint.checkpoint_id.in_(existing_ids)
            ).delete(synchronize_session=False)
            db.query(Checkpoint).filter(
                Checkpoint.race_id == body.race_id
            ).delete(synchronize_session=False)

    created = []
    for item in body.checkpoints:
        # Skip if order_number already exists (idempotent re-save guard)
        dup = db.query(Checkpoint).filter(
            Checkpoint.race_id == body.race_id,
            Checkpoint.order_number == item.order_number,
        ).first()
        if dup:
            continue

        cp = Checkpoint(
            race_id=body.race_id,
            name=item.name,
            lat=item.lat,
            lng=item.lng,
            radius_meters=item.radius_meters or 20,
            order_number=item.order_number,
        )
        db.add(cp)
        created.append(cp)

    db.commit()
    for cp in created:
        db.refresh(cp)

    return {
        "message": f"{len(created)} checkpoint(s) saved.",
        "race_id": body.race_id,
        "checkpoints": [
            {
                "id": cp.id,
                "name": cp.name,
                "lat": cp.lat,
                "lng": cp.lng,
                "radius_meters": cp.radius_meters,
                "order_number": cp.order_number,
            }
            for cp in created
        ],
    }


@router.post("/", summary="Create a single checkpoint")
def create_checkpoint(
    body: CheckpointCreate,
    db: Session = Depends(get_db),
):
    existing = db.query(Checkpoint).filter(
        Checkpoint.race_id == body.race_id,
        Checkpoint.order_number == body.order_number,
    ).first()
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"Order number {body.order_number} already exists in this race.",
        )
    checkpoint = Checkpoint(**body.model_dump())
    db.add(checkpoint)
    db.commit()
    db.refresh(checkpoint)
    return checkpoint


# ── PUT  /checkpoints/{checkpoint_id}  ───────────────────────────────────────
# FIX: This is the endpoint that was missing (Flutter sent PUT, server only had PATCH → 405)

@router.put("/{checkpoint_id}", summary="Full update (replace) a checkpoint")
def replace_checkpoint(
    checkpoint_id: int,
    body: CheckpointFullUpdate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Full replacement of a checkpoint's editable fields.
    Used when the organizer drags a checkpoint to a new position on the map
    (SmartRouteScreen sends PUT with updated lat/lng).
    """
    _require_organizer(user)
    checkpoint = _get_or_404(db, checkpoint_id)

    # Check order_number uniqueness within the same race (excluding self)
    if body.order_number != checkpoint.order_number:
        conflict = db.query(Checkpoint).filter(
            Checkpoint.race_id == checkpoint.race_id,
            Checkpoint.order_number == body.order_number,
            Checkpoint.id != checkpoint_id,
        ).first()
        if conflict:
            raise HTTPException(
                status_code=400,
                detail=f"Order number {body.order_number} already used in this race.",
            )

    checkpoint.name = body.name
    checkpoint.lat = body.lat
    checkpoint.lng = body.lng
    checkpoint.radius_meters = body.radius_meters
    checkpoint.order_number = body.order_number

    db.commit()
    db.refresh(checkpoint)
    return checkpoint


# ── PATCH /checkpoints/{checkpoint_id}  ──────────────────────────────────────

@router.patch("/{checkpoint_id}", summary="Partial update a checkpoint")
def update_checkpoint(
    checkpoint_id: int,
    body: CheckpointUpdate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Partial update – supply only the fields that changed.
    Now also accepts lat/lng (needed when organizer drags a pin) and order_number.
    """
    _require_organizer(user)
    checkpoint = _get_or_404(db, checkpoint_id)

    if body.name is not None:
        checkpoint.name = body.name

    if body.lat is not None:
        checkpoint.lat = body.lat

    if body.lng is not None:
        checkpoint.lng = body.lng

    if body.radius_meters is not None:
        checkpoint.radius_meters = body.radius_meters

    if body.order_number is not None:
        # Check uniqueness
        conflict = db.query(Checkpoint).filter(
            Checkpoint.race_id == checkpoint.race_id,
            Checkpoint.order_number == body.order_number,
            Checkpoint.id != checkpoint_id,
        ).first()
        if conflict:
            raise HTTPException(
                status_code=400,
                detail=f"Order number {body.order_number} already used in this race.",
            )
        checkpoint.order_number = body.order_number

    db.commit()
    db.refresh(checkpoint)
    return checkpoint


# ── DELETE /checkpoints/{checkpoint_id}  ─────────────────────────────────────

@router.delete("/{checkpoint_id}", summary="Delete a checkpoint")
def delete_checkpoint(
    checkpoint_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    _require_organizer(user)
    checkpoint = _get_or_404(db, checkpoint_id)

    db.query(RunnerCheckpoint).filter(
        RunnerCheckpoint.checkpoint_id == checkpoint_id
    ).delete()
    db.delete(checkpoint)
    db.commit()
    return {"message": f"Checkpoint {checkpoint_id} deleted."}


# ── Checkpoint arrival  ───────────────────────────────────────────────────────

@router.post("/{checkpoint_id}/arrive", summary="Record runner arrival at checkpoint")
def runner_arrive(
    checkpoint_id: int,
    runner_id: int,
    db: Session = Depends(get_db),
):
    checkpoint = _get_or_404(db, checkpoint_id)
    existing = db.query(RunnerCheckpoint).filter(
        RunnerCheckpoint.runner_id == runner_id,
        RunnerCheckpoint.checkpoint_id == checkpoint_id,
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Runner already recorded at this checkpoint.")

    record = RunnerCheckpoint(runner_id=runner_id, checkpoint_id=checkpoint_id)
    db.add(record)
    db.commit()
    db.refresh(record)
    return {"message": "Checkpoint arrival recorded.", "record_id": record.id}


# ── Progress  ─────────────────────────────────────────────────────────────────

@router.get("/{race_id}/runner/{runner_id}/progress", summary="Runner checkpoint progress")
def runner_progress(race_id: int, runner_id: int, db: Session = Depends(get_db)):
    total = db.query(Checkpoint).filter(Checkpoint.race_id == race_id).count()
    completed = (
        db.query(RunnerCheckpoint)
        .join(Checkpoint, RunnerCheckpoint.checkpoint_id == Checkpoint.id)
        .filter(
            Checkpoint.race_id == race_id,
            RunnerCheckpoint.runner_id == runner_id,
        )
        .count()
    )
    return {
        "runner_id": runner_id,
        "race_id": race_id,
        "completed": completed,
        "total": total,
        "percent": round((completed / total) * 100, 1) if total > 0 else 0.0,
    }


# ── List checkpoints for a race (wildcard LAST to avoid shadowing above) ─────

@router.get("/{race_id}", summary="List checkpoints for a race")
def get_checkpoints(race_id: int, db: Session = Depends(get_db)):
    return (
        db.query(Checkpoint)
        .filter(Checkpoint.race_id == race_id)
        .order_by(Checkpoint.order_number)
        .all()
    )