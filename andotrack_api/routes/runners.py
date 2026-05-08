from datetime import date
from unittest import runner

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
import pickle
import os

from models.race import Race, RaceRunner
from models.user import User
from models.anomaly import Anomaly
from database import get_db
from utils.dependencies import get_current_user
from utils.pace import record_speed, get_runner_pace_summary, get_pace_min_per_km, format_pace
from utils.distance_tracker import (
    record_position,
    get_distance_summary,
    get_all_runners_distance,
    reset_runner,
    reset_race,
    get_last_position,
)
from utils.qr_generator import token_to_base64_png
from models.race import RaceRunner
from ml.anomaly_detector import run_anomaly_detection
from ml.feature_extraction import extract_features
from routes.anomaly_handler import save_and_push_anomaly

# ── Load ML model once at startup ────────────────────────────────────────────
_MODEL_PATH = os.path.join(os.path.dirname(__file__), "..","ml", "anomaly_model.pkl")
_anomaly_model = None
if os.path.exists(_MODEL_PATH):
    with open(_MODEL_PATH, "rb") as _f:
        _anomaly_model = pickle.load(_f)
else:
    print(f"⚠️ Model not found at: {os.path.abspath(_MODEL_PATH)}")
router = APIRouter()


# ── Request schemas ───────────────────────────────────────────────────────────
class ProfileUpdate(BaseModel):
    name: str = None
    email: str = None
    date_of_birth: date = None

class LocationUpdate(BaseModel):
    lat: float
    lng: float
    speed: float
    race_id: int
    accuracy: float = None  # GPS accuracy in metres from geolocator


# ── Location + pace + distance ────────────────────────────────────────────────

@router.get("/")
def get_runners(db: Session = Depends(get_db), user=Depends(get_current_user)):
    return {"message": "get runners — coming soon"}


@router.post("/{runner_id}/location")
def update_location(
    runner_id: int,
    body: LocationUpdate,
    db: Session = Depends(get_db)
):
    """
    Accept a GPS ping from a runner.
    Records speed (rolling pace) and position (cumulative distance).
    Returns both in a single response.
    """
    runner_key = str(runner_id)

    record_speed(runner_key, body.speed)
    pace = get_runner_pace_summary(runner_key)

    # Get previous position BEFORE updating
    prev = get_last_position(body.race_id, runner_key)

    delta    = record_position(body.race_id, runner_key, body.lat, body.lng)
    distance = get_distance_summary(body.race_id, runner_key)

    # ── Anomaly detection ─────────────────────────────────────────────────
    anomaly_result = None
    if _anomaly_model is not None and prev is not None:
        prev_lat, prev_lng = prev
        features = extract_features(
            current_lat=body.lat,
            current_lng=body.lng,
            current_speed=body.speed,
            prev_lat=prev_lat,
            prev_lng=prev_lng,
            prev_speed=body.speed,
            route_lat=body.lat,
            route_lng=body.lng,
            time_delta=5.0,
        )
        is_anomaly, reason, score = run_anomaly_detection(_anomaly_model, features)
        if is_anomaly:
            try:
                save_and_push_anomaly(
                    db=db,
                    runner_id=runner_id,
                    race_id=body.race_id,
                    reason=reason,
                    score=score,
                    lat=body.lat,
                    lng=body.lng,
                )
                anomaly_result = {"detected": True, "reason": reason, "score": round(score, 4)}
            except Exception as e:
                print(f"ANOMALY ERROR: {e}")
                import traceback
                traceback.print_exc()

    return {
        "runner_id":  runner_id,
        "race_id":    body.race_id,
        "lat":        body.lat,
        "lng":        body.lng,
        "speed_ms":   body.speed,
        "speed_kmh":  round(body.speed * 3.6, 2),
        "pace": {
            "min_per_km":    pace["pace_min_per_km"],
            "formatted":     pace["pace_formatted"],
            "samples_used":  pace["sample_count"],
            "avg_speed_ms":  pace["avg_speed_ms"],
            "avg_speed_kmh": pace["avg_speed_kmh"],
        },
        "distance": {
            "metres":               distance["distance_metres"],
            "km":                   distance["distance_km"],
            "formatted":            distance["distance_formatted"],
            "delta_metres":         round(delta, 2),
            "gps_points_recorded":  distance["gps_points_recorded"],
        },
        "anomaly": anomaly_result,
    }


@router.get("/{runner_id}/pace")
def get_runner_pace(runner_id: int):
    pace = get_pace_min_per_km(str(runner_id))
    if pace is None:
        # Neutral response instead of 404 — runner hasn't moved yet
        return {
            "runner_id": runner_id,
            "pace_seconds_per_km": None,
            "pace_formatted": None,
            "status": "waiting_for_gps"
        }
    mins = int(pace // 60)
    secs = int(pace % 60)
    return {
        "runner_id": runner_id,
        "pace_seconds_per_km": pace,
        "pace_formatted": f"{mins}:{secs:02d} /km",
        "status": "active"
    }


@router.get("/{runner_id}/distance")
def get_runner_distance(runner_id: int, race_id: int):
    distance = get_distance(race_id, runner_id)
    if distance is None:
        # Neutral response instead of 404
        return {
            "runner_id": runner_id,
            "race_id": race_id,
            "distance_km": 0.0,
            "status": "waiting_for_gps"
        }
    return {
        "runner_id": runner_id,
        "race_id": race_id,
        "distance_km": round(distance / 1000, 3),
        "status": "active"
    }


@router.get("/race/{race_id}/distances")
def get_race_distances(race_id: int, user=Depends(get_current_user)):
    runners = get_all_runners_distance(race_id)
    return {"race_id": race_id, "runners": runners}


@router.delete("/{runner_id}/distance")
def reset_runner_distance(runner_id: int, race_id: int, user=Depends(get_current_user)):
    reset_runner(race_id, str(runner_id))
    return {"message": f"Distance reset for runner {runner_id} in race {race_id}."}


@router.delete("/race/{race_id}/distances")
def reset_race_distances(race_id: int, user=Depends(get_current_user)):
    reset_race(race_id)
    return {"message": f"All distance data reset for race {race_id}."}


# ── QR code fetch ─────────────────────────────────────────────────────────────

@router.get("/{runner_id}/qr")
def get_runner_qr(
    runner_id: int,
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Fetch the QR code for a runner's registration.
    Used by qr_screen.dart so runner can view/save their QR at any time.
    Query param: ?race_id=1
    """
    requesting_id = int(user["sub"])
    role          = user.get("role")

    if role != "organizer" and requesting_id != runner_id:
        raise HTTPException(status_code=403, detail="You can only view your own QR code.")

    registration = db.query(RaceRunner).filter(
        RaceRunner.runner_id == runner_id,
        RaceRunner.race_id   == race_id,
    ).first()

    if not registration:
        raise HTTPException(
            status_code=404,
            detail=f"Runner {runner_id} is not registered for race {race_id}.",
        )

    qr_image_b64 = token_to_base64_png(registration.qr_token)

    return {
        "runner_id":       runner_id,
        "race_id":         race_id,
        "qr_token":        registration.qr_token,
        "qr_image_base64": qr_image_b64,
        "is_present":      registration.is_present,
        "checked_in_at":   registration.checked_in_at,
    }

# ── Race history ──────────────────────────────────────────────────────────────
 
@router.get("/{runner_id}/results")
def get_runner_results(
    runner_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user)
):
    """
    Returns all completed race results for a runner — their full race history.
    Each entry includes race name, date, final rank, distance, pace, and splits.
    """
    # Check runner exists
    runner = db.query(User).filter(User.id == runner_id).first()
    if not runner:
        raise HTTPException(status_code=404, detail="Runner not found")
 
    # Pull all results for this runner, most recent first
    results = db.query(RaceResult).filter(
        RaceResult.runner_id == runner_id
    ).order_by(RaceResult.finished_at.desc()).all()
 
    if not results:
        return {
            "runner_id": runner_id,
            "runner_name": runner.name,
            "total_races": 0,
            "results": []
        }
 
    # Enrich each result with race info and checkpoint splits
    history = []
    for result in results:
        race = db.query(Race).filter(Race.id == result.race_id).first()
        splits = _get_splits(db, runner_id, result.race_id)
 
        history.append({
            "result_id": result.id,
            "race_id": result.race_id,
            "race_name": race.name if race else "Unknown Race",
            "race_distance_km": race.distance_km if race else None,
            "race_date": race.race_date if race else None,
            # Performance
            "rank": result.rank,
            "distance_km": result.distance_km,
            "pace_formatted": result.pace_formatted,
            "finished_at": result.finished_at,
            # Checkpoint splits
            "splits": splits,
        })
 
    return {
        "runner_id": runner_id,
        "runner_name": runner.name,
        "total_races": len(history),
        "results": history
    }
 
 
# ── Finish race ───────────────────────────────────────────────────────────────
 
@router.post("/{runner_id}/finish")
def finish_race(
    runner_id: int,
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user)
):
    """
    Called when a runner crosses the finish line.
    Saves their result to race_results, updates their race_status to 'finished',
    and assigns a rank based on finish order.
    """
    # Check race and registration exist
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found")
 
    registration = db.query(RaceRunner).filter(
        RaceRunner.race_id == race_id,
        RaceRunner.runner_id == runner_id
    ).first()
    if not registration:
        raise HTTPException(status_code=404, detail="Runner not registered in this race")
 
    # Don't double-save if they already finished
    existing = db.query(RaceResult).filter(
        RaceResult.race_id == race_id,
        RaceResult.runner_id == runner_id
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Result already recorded for this runner")
 
    # Get distance and pace from in-memory stores
    from utils.distance_tracker import get_distance
    from utils.pace import get_pace_min_per_km, format_pace
    import datetime
 
    raw_distance = get_distance(race_id, runner_id)
    distance_km = round(raw_distance / 1000, 3) if raw_distance else 0.0
 
    pace_min = get_pace_min_per_km(str(runner_id))
    pace_formatted = format_pace(pace_min)
 
    # Rank = how many results are already saved for this race + 1
    # (first to finish gets rank 1, second gets rank 2, etc.)
    finished_count = db.query(RaceResult).filter(
        RaceResult.race_id == race_id
    ).count()
    rank = finished_count + 1
 
    # Save result
    now = datetime.datetime.now(datetime.timezone.utc)
    result = RaceResult(
        race_id=race_id,
        runner_id=runner_id,
        rank=rank,
        distance_km=distance_km,
        pace_formatted=pace_formatted,
        finished_at=now
    )
    db.add(result)
 
    # Update runner's status in the race
    registration.race_status = "finished"
    db.commit()
    db.refresh(result)
 
    return {
        "message": "Finish recorded",
        "runner_id": runner_id,
        "race_id": race_id,
        "rank": rank,
        "distance_km": distance_km,
        "pace_formatted": pace_formatted,
        "finished_at": now,
    }

# ---ANOMALIES------------------------------
@router.get("/{runner_id}/anomalies")
def get_runner_anomalies(
    runner_id: int,
    race_id: int = None,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    query = db.query(Anomaly).filter(Anomaly.runner_id == runner_id)
    if race_id:
        query = query.filter(Anomaly.race_id == race_id)
    anomalies = query.order_by(Anomaly.detected_at.desc()).all()
    return {
        "runner_id": runner_id,
        "total": len(anomalies),
        "anomalies": anomalies,
    }
 
 #----------PROFILE UPDATE---


@router.patch("/{runner_id}/profile")
def update_profile(
    runner_id: int,
    body: ProfileUpdate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    # Runners can only edit their own profile
    if int(user["sub"]) != runner_id:
        raise HTTPException(status_code=403, detail="You can only edit your own profile.")

    runner = db.query(User).filter(User.id == runner_id).first()
    if not runner:
        raise HTTPException(status_code=404, detail="Runner not found.")

    # Check email not already taken by someone else
    if body.email and body.email != runner.email:
        existing = db.query(User).filter(User.email == body.email).first()
        if existing:
            raise HTTPException(status_code=400, detail="Email already in use.")

    if body.name:
        runner.name = body.name
    if body.email:
        runner.email = body.email
    if body.date_of_birth:
        runner.date_of_birth = body.date_of_birth

    db.commit()
    db.refresh(runner)

    return {
        "message": "Profile updated.",
        "runner_id": runner.id,
        "name": runner.name,
        "email": runner.email,
        "date_of_birth": runner.date_of_birth,
    }
 
# ── Helper: checkpoint splits ─────────────────────────────────────────────────
 
def _get_splits(db: Session, runner_id: int, race_id: int) -> list:
    """
    Returns checkpoint split times for a runner in a specific race,
    ordered by checkpoint order_number.
    """
    from models.checkpoint import Checkpoint, RunnerCheckpoint
 
    passages = db.query(RunnerCheckpoint, Checkpoint).join(
        Checkpoint, RunnerCheckpoint.checkpoint_id == Checkpoint.id
    ).filter(
        Checkpoint.race_id == race_id,
        RunnerCheckpoint.runner_id == runner_id
    ).order_by(Checkpoint.order_number).all()
 
    return [
        {
            "checkpoint_id": cp.id,
            "checkpoint_name": cp.name,
            "order_number": cp.order_number,
            "type": cp.type,
            "passed_at": rc.passed_at,
        }
        for rc, cp in passages
    ]
 
 