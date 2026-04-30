from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from utils.dependencies import get_current_user
from utils.distance_tracker import get_all_runners_distance
from utils.pace import get_runner_pace_summary
from utils.eta import calculate_eta
from models.race import Race, RaceRunner
from models.user import User

router = APIRouter()


@router.get("/{race_id}/leaderboard")
def get_leaderboard(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    GET /races/{race_id}/leaderboard

    Returns runners sorted by distance covered descending (furthest = rank 1).
    Uses in-memory distance_tracker and pace utils — same source of truth
    as the /runners endpoints.
    """

    # ── 1. Verify race exists ─────────────────────────────────────────────
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    # ── 2. Get all runners registered for this race ───────────────────────
    registrations = db.query(RaceRunner).filter(
        RaceRunner.race_id == race_id
    ).all()

    if not registrations:
        return {
            "race_id":     race_id,
            "race_name":   race.name,
            "status":      race.status,
            "total":       0,
            "leaderboard": [],
        }

    # ── 3. Build a lookup: runner_id (str) → display name ────────────────
    users = db.query(User).filter(
        User.id.in_([r.runner_id for r in registrations])
    ).all()
    name_map: dict[str, str] = {str(u.id): u.name for u in users}
    runner_ids = [str(r.runner_id) for r in registrations]

    # ── 4. Distance map from in-memory tracker ────────────────────────────
    # get_all_runners_distance only returns runners who have sent at least
    # one GPS ping — we merge with the full registration list so runners
    # who haven't moved yet still appear (distance = 0).
    distance_map: dict[str, dict] = {
        d["runner_id"]: d
        for d in get_all_runners_distance(race_id)
    }

    # ── 5. Build leaderboard entries ──────────────────────────────────────
    entries = []
    for runner_id_str in runner_ids:
        dist = distance_map.get(runner_id_str, {
            "distance_metres":     0.0,
            "distance_km":         0.0,
            "distance_formatted":  "0 m",
            "gps_points_recorded": 0,
        })

        pace = get_runner_pace_summary(runner_id_str)
        pace_min_per_km = pace["pace_min_per_km"]

        # eta.py takes pace in seconds/km; pace.py returns min/km
        pace_sec_per_km = (pace_min_per_km * 60) if pace_min_per_km else 0

        eta_str = calculate_eta(
            pace_seconds_per_km=pace_sec_per_km,
            distance_covered_km=dist["distance_km"],
            total_race_km=race.distance_km,
        ) if pace_sec_per_km > 0 else "—"

        entries.append({
            "runner_id":           runner_id_str,
            "name":                name_map.get(runner_id_str, "Unknown"),
            "distance_metres":     dist["distance_metres"],
            "distance_km":         dist["distance_km"],
            "distance_formatted":  dist["distance_formatted"],
            "pace_min_per_km":     pace_min_per_km,
            "pace_formatted":      pace["pace_formatted"],
            "eta":                 eta_str,
            "gps_points_recorded": dist["gps_points_recorded"],
        })

    # ── 6. Sort by distance descending ────────────────────────────────────
    entries.sort(key=lambda e: e["distance_metres"], reverse=True)

    # ── 7. Assign ranks (ties share the same rank) ────────────────────────
    ranked = []
    rank = 1
    for i, entry in enumerate(entries):
        if i > 0 and entry["distance_metres"] < entries[i - 1]["distance_metres"]:
            rank = i + 1
        ranked.append({"rank": rank, **entry})

    return {
        "race_id":     race_id,
        "race_name":   race.name,
        "distance_km": race.distance_km,
        "status":      race.status,
        "total":       len(ranked),
        "leaderboard": ranked,
    }
