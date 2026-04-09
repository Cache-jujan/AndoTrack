from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from database import get_db
from utils.dependencies import get_current_user
from utils.pace import record_speed, get_runner_pace_summary
from utils.distance_tracker import (
    record_position,
    get_distance_summary,
    get_all_runners_distance,
    reset_runner,
    reset_race,
)

router = APIRouter()


# ── Request schema ────────────────────────────────────────

class LocationUpdate(BaseModel):
    race_id: int
    lat: float
    lng: float
    speed: float            # m/s from geolocator
    accuracy: float = 0.0   # GPS accuracy in metres (optional)


# ── Routes ────────────────────────────────────────────────

@router.get("/")
def get_runners(db: Session = Depends(get_db), user=Depends(get_current_user)):
    return {"message": "get runners — coming soon"}


@router.post("/{runner_id}/location")
def update_location(
    runner_id: int,
    body: LocationUpdate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Accept a GPS ping from a runner.

    Records:
      - Speed reading into a 5-point rolling window  →  pace (min/km)
      - GPS position into cumulative Haversine distance (metres / km)

    Returns both pace and distance in a single response so the Flutter
    app only needs one POST per GPS ping.
    """
    runner_key = str(runner_id)

    # Pace (rolling average of last 5 speeds)
    record_speed(runner_key, body.speed)
    pace = get_runner_pace_summary(runner_key)

    # Distance (cumulative Haversine sum)
    delta = record_position(body.race_id, runner_key, body.lat, body.lng)
    distance = get_distance_summary(body.race_id, runner_key)

    return {
        "runner_id": runner_id,
        "race_id": body.race_id,
        "lat": body.lat,
        "lng": body.lng,
        "speed_ms": body.speed,
        "speed_kmh": round(body.speed * 3.6, 2),
        "pace": {
            "min_per_km": pace["pace_min_per_km"],
            "formatted": pace["pace_formatted"],
            "samples_used": pace["sample_count"],
            "avg_speed_ms": pace["avg_speed_ms"],
            "avg_speed_kmh": pace["avg_speed_kmh"],
        },
        "distance": {
            "metres": distance["distance_metres"],
            "km": distance["distance_km"],
            "formatted": distance["distance_formatted"],
            "delta_metres": round(delta, 2),
            "gps_points_recorded": distance["gps_points_recorded"],
        },
    }


@router.get("/{runner_id}/pace")
def get_pace(runner_id: int, user=Depends(get_current_user)):
    """Return the current rolling-average pace without a new location ping."""
    pace = get_runner_pace_summary(str(runner_id))
    if pace["sample_count"] == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No speed data recorded yet for runner {runner_id}.",
        )
    return pace


@router.get("/{runner_id}/distance")
def get_distance(runner_id: int, race_id: int, user=Depends(get_current_user)):
    """
    Return the cumulative distance covered by a runner in a specific race.
    Query param: ?race_id=1
    """
    summary = get_distance_summary(race_id, str(runner_id))
    if summary["gps_points_recorded"] == 0:
        raise HTTPException(
            status_code=404,
            detail=f"No GPS data recorded yet for runner {runner_id} in race {race_id}.",
        )
    return summary


@router.get("/race/{race_id}/distances")
def get_race_distances(race_id: int, user=Depends(get_current_user)):
    """
    Return distance summaries for all runners in a race, sorted furthest-first.
    """
    runners = get_all_runners_distance(race_id)
    return {"race_id": race_id, "runners": runners}


@router.delete("/{runner_id}/distance")
def reset_runner_distance(runner_id: int, race_id: int, user=Depends(get_current_user)):
    """Reset a single runner's distance data (e.g. after a false start)."""
    reset_runner(race_id, str(runner_id))
    return {"message": f"Distance reset for runner {runner_id} in race {race_id}."}


@router.delete("/race/{race_id}/distances")
def reset_race_distances(race_id: int, user=Depends(get_current_user)):
    """Reset ALL runners' distance data for a race."""
    reset_race(race_id)
    return {"message": f"All distance data reset for race {race_id}."}