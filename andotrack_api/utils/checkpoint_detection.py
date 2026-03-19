from utils.haversine import haversine
from sqlalchemy.orm import Session
from models.checkpoint import Checkpoint, RunnerCheckpoint
from sqlalchemy.exc import IntegrityError

def detect_checkpoint(
    db: Session,
    runner_id: int,
    race_id: int,
    lat: float,
    lng: float
) -> dict | None:
    """
    Checks if runner is within any checkpoint radius.
    Returns checkpoint info if triggered, None otherwise.
    """
    checkpoints = db.query(Checkpoint).filter(
        Checkpoint.race_id == race_id
    ).order_by(Checkpoint.order_number).all()

    for cp in checkpoints:
        distance = haversine(lat, lng, cp.lat, cp.lng)
        if distance <= cp.radius_meters:
            # Try to save — UNIQUE KEY prevents duplicate saves
            try:
                passage = RunnerCheckpoint(
                    runner_id=runner_id,
                    checkpoint_id=cp.id
                )
                db.add(passage)
                db.commit()
                return {"checkpoint_id": cp.id, "name": cp.name, "order": cp.order_number}
            except IntegrityError:
                db.rollback()  # Already passed this checkpoint, skip
                return None

    return None