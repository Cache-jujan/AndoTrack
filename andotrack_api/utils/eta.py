from datetime import datetime, timedelta

def calculate_eta(
    pace_seconds_per_km: float,  # from Judd's pace endpoint
    distance_covered_km: float,
    total_race_km: float
) -> str:
    """
    Returns estimated finish time as a formatted string.
    """
    remaining_km = max(total_race_km - distance_covered_km, 0)

    if pace_seconds_per_km <= 0 or remaining_km == 0:
        return "Finished"

    seconds_remaining = pace_seconds_per_km * remaining_km
    eta = datetime.now() + timedelta(seconds=seconds_remaining)

    return eta.strftime("%H:%M:%S")