from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database import get_db
from utils.dependencies import get_current_user
from utils.distance_tracker import get_all_runners_distance
from utils.pace import get_runner_pace_summary
from utils.eta import calculate_eta
from models.race import Race, RaceRunner
from models.result import RaceResult
from models.user import User

router = APIRouter()


@router.get("/{race_id}/leaderboard")
def get_leaderboard(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
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
            "finished":    [],
            "racing":      [],
        }

    # ── 3. Build lookups ──────────────────────────────────────────────────
    users = db.query(User).filter(
        User.id.in_([r.runner_id for r in registrations])
    ).all()
    name_map: dict[str, str] = {str(u.id): u.name for u in users}
    reg_map: dict[str, RaceRunner] = {str(r.runner_id): r for r in registrations}
    runner_ids = [str(r.runner_id) for r in registrations]

    # ── 4. Distance map from in-memory tracker ────────────────────────────
    distance_map: dict[str, dict] = {
        d["runner_id"]: d
        for d in get_all_runners_distance(race_id)
    }

    # ── 5. Pull finished runners from race_results ────────────────────────
    finished_results = db.query(RaceResult).filter(
        RaceResult.race_id == race_id
    ).order_by(RaceResult.rank).all()

    finished_ids = {str(r.runner_id) for r in finished_results}

    finished = []
    for result in finished_results:
        runner_id_str = str(result.runner_id)
        reg = reg_map.get(runner_id_str)
        finished.append({
            "runner_id":          runner_id_str,
            "name":               name_map.get(runner_id_str, "Unknown"),
            "bib_number":         reg.bib_number if reg else None,
            "race_status":        "finished",
            "rank":               result.rank,
            "distance_metres":    result.distance_metres,
            "distance_km":        result.distance_km,
            "distance_formatted": f"{result.distance_km:.2f} km",
            "pace_min_per_km":    result.pace_min_per_km,
            "pace_formatted":     result.pace_formatted or "—",
            "finished_at":        result.finished_at.isoformat() if result.finished_at else None,
            "percentage_complete": 100.0,
            "eta":                "Finished",
        })

    # ── 6. Build still-racing entries ─────────────────────────────────────
    entries = []
    for runner_id_str in runner_ids:
        # Skip finished and DNF/DNS runners
        if runner_id_str in finished_ids:
            continue

        reg = reg_map.get(runner_id_str)
        if reg and reg.race_status in ("dnf", "dns"):
            continue

        dist = distance_map.get(runner_id_str, {
            "distance_metres":     0.0,
            "distance_km":         0.0,
            "distance_formatted":  "0 m",
            "gps_points_recorded": 0,
        })

        pace = get_runner_pace_summary(runner_id_str)
        pace_min_per_km = pace["pace_min_per_km"]
        pace_sec_per_km = (pace_min_per_km * 60) if pace_min_per_km else 0

        eta_str = calculate_eta(
            pace_seconds_per_km=pace_sec_per_km,
            distance_covered_km=dist["distance_km"],
            total_race_km=race.distance_km,
        ) if pace_sec_per_km > 0 else "—"

        entries.append({
            "runner_id":           runner_id_str,
            "name":                name_map.get(runner_id_str, "Unknown"),
            "bib_number":          reg.bib_number if reg else None,
            "race_status":         reg.race_status if reg else None,
            "distance_metres":     dist["distance_metres"],
            "distance_km":         dist["distance_km"],
            "distance_formatted":  dist["distance_formatted"],
            "pace_min_per_km":     pace_min_per_km,
            "pace_formatted":      pace["pace_formatted"],
            "eta":                 eta_str,
            "gps_points_recorded": dist["gps_points_recorded"],
            "percentage_complete": round((dist["distance_km"] / race.distance_km) * 100, 1) if race.distance_km else 0.0,
        })

    # ── 7. Sort racing entries by distance descending ─────────────────────
    entries.sort(key=lambda e: e["distance_metres"], reverse=True)

    # ── 8. Assign ranks for still-racing runners ──────────────────────────
    racing_ranked = []
    rank = len(finished) + 1
    for i, entry in enumerate(entries):
        if i > 0 and entry["distance_metres"] < entries[i - 1]["distance_metres"]:
            rank = len(finished) + i + 1
        racing_ranked.append({"rank": rank, **entry})

    return {
        "race_id":     race_id,
        "race_name":   race.name,
        "distance_km": race.distance_km,
        "status":      race.status,
        "total":       len(finished) + len(racing_ranked),
        "finished":    finished,
        "racing":      racing_ranked,
    }