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

def validate_checkpoint_order(
    db: Session,
    runner_id: int,
    checkpoint_order: int,
    race_id: int
) -> bool:
    """
    Returns True if runner has passed all previous checkpoints.
    """
    if checkpoint_order == 1:
        return True  # First checkpoint, no previous needed

    checkpoints = db.query(Checkpoint).filter(
        Checkpoint.race_id == race_id,
        Checkpoint.order_number < checkpoint_order
    ).all()

    for cp in checkpoints:
        already_passed = db.query(RunnerCheckpoint).filter_by(
            runner_id=runner_id,
            checkpoint_id=cp.id
        ).first()
        if not already_passed:
            return False  # Skipped a checkpoint

    return True
