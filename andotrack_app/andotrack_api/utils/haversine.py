import math

def haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """
    Returns distance in meters between two GPS coordinates.
    """
    R = 6371000  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)

    a = math.sin(dphi / 2) ** 2 + \
        math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2

    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))