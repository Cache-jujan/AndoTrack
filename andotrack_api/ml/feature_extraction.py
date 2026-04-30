import math

def extract_features(
    current_lat: float,
    current_lng: float,
    current_speed: float,
    prev_lat: float,
    prev_lng: float,
    prev_speed: float,
    route_lat: float,   # nearest point on race route
    route_lng: float,
    time_delta: float   # seconds between updates
) -> list[float]:
    """
    Returns [speed, acceleration, direction_change, dist_from_route, dist_from_last]
    """
    from utils.haversine import haversine

    speed = max(current_speed, 0)

    acceleration = abs(current_speed - prev_speed) / max(time_delta, 1)

    # Direction change in degrees
    def bearing(lat1, lng1, lat2, lng2):
        dlng = math.radians(lng2 - lng1)
        lat1, lat2 = math.radians(lat1), math.radians(lat2)
        x = math.sin(dlng) * math.cos(lat2)
        y = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dlng)
        return math.degrees(math.atan2(x, y)) % 360

    prev_bearing = bearing(prev_lat, prev_lng, current_lat, current_lng)
    curr_bearing = bearing(current_lat, current_lng, route_lat, route_lng)
    direction_change = abs(curr_bearing - prev_bearing) % 180

    dist_from_route = haversine(current_lat, current_lng, route_lat, route_lng)
    dist_from_last = haversine(prev_lat, prev_lng, current_lat, current_lng)

    return [speed, acceleration, direction_change, dist_from_route, dist_from_last]