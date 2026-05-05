"""
andotrack_api/utils/distance_tracker.py

Tracks cumulative distance covered by each runner in a race.

Strategy:
  - In-memory store keyed by (race_id, runner_id).
  - Each entry holds the last known position and the running total (metres).
  - On every GPS ping we call haversine(prev → current) and add it to the total.
  - Getters return distance in both metres and kilometres.
  - A minimum movement threshold (1 m) filters out GPS jitter so stationary
    noise does not inflate the total.
"""

from dataclasses import dataclass, field
from utils.haversine import haversine
from collections import defaultdict

# ── Minimum distance (metres) that counts as real movement ──────────────────
_MIN_MOVEMENT_METRES = 1.0


@dataclass
class _RunnerState:
    last_lat: float
    last_lng: float
    total_metres: float = 0.0
    point_count: int = 1        # number of GPS pings recorded (incl. the first)


# key: (race_id, runner_id)  →  _RunnerState
_tracker: dict[tuple[int, str], _RunnerState] = {}


# ── Public API ───────────────────────────────────────────────────────────────

def record_position(
    race_id: int,
    runner_id: str,
    lat: float,
    lng: float,
) -> float:
    """
    Record a new GPS position for a runner and return the incremental
    distance (metres) added by this ping.

    On the *first* call for a (race_id, runner_id) pair the function just
    stores the starting position and returns 0.0.
    """
    key = (race_id, runner_id)

    if key not in _tracker:
        _tracker[key] = _RunnerState(last_lat=lat, last_lng=lng)
        return 0.0

    state = _tracker[key]
    delta = haversine(state.last_lat, state.last_lng, lat, lng)

    # Ignore tiny jitter
    if delta >= _MIN_MOVEMENT_METRES:
        state.total_metres += delta
        state.last_lat = lat
        state.last_lng = lng

    state.point_count += 1
    return delta if delta >= _MIN_MOVEMENT_METRES else 0.0

def get_last_position(race_id: int, runner_id: str) -> tuple[float, float] | None:
    """
    Return the last known (lat, lng) for a runner, or None if no data yet.
    Used by the anomaly pipeline to compute acceleration and direction_change.
    """
    state = _tracker.get((race_id, runner_id))
    if state is None:
        return None
    return (state.last_lat, state.last_lng)

def get_distance_metres(race_id: int, runner_id: str) -> float:
    """Return total distance covered in metres. 0.0 if no data."""
    state = _tracker.get((race_id, runner_id))
    return round(state.total_metres, 2) if state else 0.0


def get_distance_km(race_id: int, runner_id: str) -> float:
    """Return total distance covered in kilometres."""
    return round(get_distance_metres(race_id, runner_id) / 1000, 4)


def get_distance_summary(race_id: int, runner_id: str) -> dict:
    """
    Return a full summary dict ready to embed in API responses.

    Example:
        {
            "race_id": 1,
            "runner_id": "42",
            "distance_metres": 3451.78,
            "distance_km": 3.4518,
            "distance_formatted": "3.45 km",
            "gps_points_recorded": 87
        }
    """
    state = _tracker.get((race_id, runner_id))
    metres = round(state.total_metres, 2) if state else 0.0
    km = round(metres / 1000, 4)
    points = state.point_count if state else 0

    return {
        "race_id": race_id,
        "runner_id": runner_id,
        "distance_metres": metres,
        "distance_km": km,
        "distance_formatted": _format_distance(metres),
        "gps_points_recorded": points,
    }


def get_all_runners_distance(race_id: int) -> list[dict]:
    """
    Return distance summaries for *all* runners in a race,
    sorted by distance descending (furthest first).
    Useful for the leaderboard.
    """
    runners = [
        get_distance_summary(race_id, runner_id)
        for (rid, runner_id) in _tracker
        if rid == race_id
    ]
    runners.sort(key=lambda r: r["distance_metres"], reverse=True)
    return runners


def reset_runner(race_id: int, runner_id: str) -> None:
    """Clear a single runner's distance data (e.g. race restart)."""
    _tracker.pop((race_id, runner_id), None)


def reset_race(race_id: int) -> None:
    """Clear ALL runners' distance data for a given race."""
    keys_to_delete = [k for k in _tracker if k[0] == race_id]
    for k in keys_to_delete:
        del _tracker[k]


# ── Internal helpers ─────────────────────────────────────────────────────────

def _format_distance(metres: float) -> str:
    """Human-readable distance string."""
    if metres < 1000:
        return f"{metres:.0f} m"
    return f"{metres / 1000:.2f} km"

distance_store: dict[tuple[int, int], float] = defaultdict(float)
 
# Tracks the last known position per (race_id, runner_id)
_last_position: dict[tuple[int, int], tuple[float, float]] = {}
 
JITTER_FILTER_METERS = 1  # ignore GPS pings that moved less than 1m
 
 
def record_position(race_id: int, runner_id: int, lat: float, lng: float) -> float:
    """
    Updates cumulative distance for this runner in this race.
    Applies a 1-metre jitter filter to ignore GPS noise.
    Returns the total distance in metres.
    """
    key = (race_id, runner_id)
 
    if key in _last_position:
        prev_lat, prev_lng = _last_position[key]
        delta = haversine(prev_lat, prev_lng, lat, lng)
        if delta > JITTER_FILTER_METERS:
            distance_store[key] += delta
            _last_position[key] = (lat, lng)
    else:
        # First ping — store position but don't add distance yet
        _last_position[key] = (lat, lng)
 
    return distance_store[key]
 
 
def get_distance(race_id: int, runner_id: int) -> float | None:
    """
    Returns cumulative distance in metres, or None if no data yet.
    """
    key = (race_id, runner_id)
    if key not in _last_position:
        return None
    return distance_store[key]