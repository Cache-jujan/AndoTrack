from collections import defaultdict, deque

# In-memory store: runner_id → deque of last N speed readings (m/s)
_speed_history: dict[str, deque] = defaultdict(lambda: deque(maxlen=5))


def record_speed(runner_id: str, speed_ms: float) -> None:
    """Push a new speed reading (m/s) into the runner's rolling window."""
    if speed_ms >= 0:
        _speed_history[runner_id].append(speed_ms)


def get_pace_min_per_km(runner_id: str) -> float | None:
    """
    Returns rolling-average pace in min/km for the given runner.

    Returns None if there are no readings yet.
    Pace = 1 / (avg_speed_m_s × 60 / 1000)
         = 1000 / (avg_speed_m_s × 60)
    """
    readings = _speed_history.get(runner_id)
    if not readings:
        return None

    avg_speed_ms = sum(readings) / len(readings)

    if avg_speed_ms < 0.1:          # essentially stationary — avoid ÷0
        return None

    pace_min_per_km = 1000 / (avg_speed_ms * 60)
    return round(pace_min_per_km, 2)


def format_pace(pace_min_per_km: float | None) -> str:
    """Formats pace as  MM:SS /km  e.g. '5:42 /km'. Returns '—' if unavailable."""
    if pace_min_per_km is None:
        return "—"

    minutes = int(pace_min_per_km)
    seconds = round((pace_min_per_km - minutes) * 60)
    if seconds == 60:
        minutes += 1
        seconds = 0
    return f"{minutes}:{seconds:02d} /km"


def get_runner_pace_summary(runner_id: str) -> dict:
    """Returns a full pace summary dict ready to include in API responses."""
    readings = _speed_history.get(runner_id)
    pace = get_pace_min_per_km(runner_id)

    avg_speed_ms = (
        sum(readings) / len(readings) if readings else None
    )

    return {
        "runner_id": runner_id,
        "sample_count": len(readings) if readings else 0,
        "avg_speed_ms": round(avg_speed_ms, 3) if avg_speed_ms is not None else None,
        "avg_speed_kmh": round(avg_speed_ms * 3.6, 2) if avg_speed_ms is not None else None,
        "pace_min_per_km": pace,
        "pace_formatted": format_pace(pace),
    }


def clear_runner_history(runner_id: str) -> None:
    """Wipe a runner's speed history (e.g. when a race ends)."""
    _speed_history.pop(runner_id, None)