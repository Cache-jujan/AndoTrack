"""
routes/route_generator.py  ─  AndoTrack
────────────────────────────────────────────────────────────────────────────
Smart Route Generation API

POST /route/generate
    → Calls OSRM (free, no API key) to build a realistic road route
      that approximates the requested distance.
    → Falls back to haversine-based geometric loop if OSRM is unreachable.
    → Auto-generates evenly-spaced checkpoint positions along the route.
    → Returns:  polyline, actual_distance_m, checkpoints, accuracy_pct
────────────────────────────────────────────────────────────────────────────
"""

import math
import requests
from typing import Optional, List, Tuple
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, field_validator

router = APIRouter()

# ── Constants ─────────────────────────────────────────────────────────────────

OSRM_BASE = "https://router.project-osrm.org"
OSRM_TIMEOUT = 10
EARTH_RADIUS_M = 6_371_000
MAX_ITER = 4
TOLERANCE_PCT = 3.0
MIN_CHECKPOINT_INTERVAL_M = 200.0


# ── Request / Response models ─────────────────────────────────────────────────

class RouteRequest(BaseModel):
    start_lat: float
    start_lng: float
    end_lat: Optional[float] = None
    end_lng: Optional[float] = None
    target_distance_m: float
    checkpoint_interval_m: float = 1_000.0
    is_loop: bool = True

    @field_validator("target_distance_m")
    @classmethod
    def target_positive(cls, v: float) -> float:
        if v < 500:
            raise ValueError("target_distance_m must be ≥ 500 m")
        if v > 200_000:
            raise ValueError("target_distance_m must be ≤ 200 km")
        return v

    @field_validator("checkpoint_interval_m")
    @classmethod
    def interval_positive(cls, v: float) -> float:
        if v < MIN_CHECKPOINT_INTERVAL_M:
            raise ValueError(f"checkpoint_interval_m must be ≥ {MIN_CHECKPOINT_INTERVAL_M} m")
        return v


class RouteCheckpoint(BaseModel):
    order_number: int
    name: str
    lat: float
    lng: float
    radius_meters: int = 20
    distance_from_start_m: float


class RouteResponse(BaseModel):
    polyline: List[List[float]]
    actual_distance_m: float
    actual_distance_km: float
    target_distance_m: float
    accuracy_pct: float
    checkpoints: List[RouteCheckpoint]
    source: str
    warning: Optional[str] = None


# ── Public endpoint ───────────────────────────────────────────────────────────

@router.post("/generate", response_model=RouteResponse, summary="Generate a smart race route")
def generate_route(body: RouteRequest) -> RouteResponse:
    try:
        if body.is_loop or body.end_lat is None or body.end_lng is None:
            polyline, source = _build_loop_route(
                body.start_lat, body.start_lng, body.target_distance_m
            )
        else:
            # end_lat and end_lng are guaranteed non-None here
            polyline, source = _build_p2p_route(
                body.start_lat, body.start_lng,
                body.end_lat, body.end_lng,   # both confirmed float at this point
                body.target_distance_m,
            )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Route generation failed: {exc}")

    if len(polyline) < 2:
        raise HTTPException(status_code=422, detail="Could not build a valid route for this area.")

    actual_m = _measure_distance_m(polyline)
    accuracy = 100.0 - abs(actual_m - body.target_distance_m) / body.target_distance_m * 100

    warning: Optional[str] = None
    if accuracy < 90:
        warning = (
            f"Route is {actual_m / 1000:.2f} km — "
            f"target was {body.target_distance_m / 1000:.1f} km. "
            "The road network may not support the exact distance in this area."
        )

    checkpoints = _auto_checkpoints(polyline, body.checkpoint_interval_m)

    return RouteResponse(
        polyline=polyline,
        actual_distance_m=round(actual_m, 1),
        actual_distance_km=round(actual_m / 1000, 3),
        target_distance_m=body.target_distance_m,
        accuracy_pct=round(max(accuracy, 0), 1),
        checkpoints=checkpoints,
        source=source,
        warning=warning,
    )


# ── Loop route builder ────────────────────────────────────────────────────────

def _build_loop_route(
    start_lat: float, start_lng: float, target_m: float
) -> Tuple[list, str]:
    offset_m = target_m / 4.0
    bearings = [0.0, 90.0, 180.0, 270.0]

    # Initialize with fallback so they are always bound
    polyline: list = _geometric_loop(start_lat, start_lng, target_m)
    source: str = "geometric_fallback"

    for _ in range(MAX_ITER):
        waypoints = [_offset_point(start_lat, start_lng, offset_m, b) for b in bearings]
        waypoints_with_ends: list = [
            (start_lat, start_lng),
            *waypoints,
            (start_lat, start_lng),
        ]

        osrm_result, osrm_source = _osrm_route(waypoints_with_ends)
        if osrm_result is None:
            # OSRM unavailable — return geometric fallback immediately
            return _geometric_loop(start_lat, start_lng, target_m), "geometric_fallback"

        polyline = osrm_result
        source = osrm_source

        actual_m = _measure_distance_m(polyline)
        if actual_m == 0:
            return _geometric_loop(start_lat, start_lng, target_m), "geometric_fallback"

        error_pct = abs(actual_m - target_m) / target_m * 100
        if error_pct <= TOLERANCE_PCT:
            break

        offset_m *= target_m / actual_m

    return polyline, source


# ── Point-to-point route builder ──────────────────────────────────────────────

def _build_p2p_route(
    start_lat: float, start_lng: float,
    end_lat: float, end_lng: float,     # always float — caller checks None before calling
    target_m: float,
) -> Tuple[list, str]:
    direct_m = _haversine_m(start_lat, start_lng, end_lat, end_lng)
    mid_lat = (start_lat + end_lat) / 2
    mid_lng = (start_lng + end_lng) / 2

    # Initialize so these are always bound even if the if-branch isn't taken
    needed_extra_m: float = 0.0
    perp_bearing: float = 0.0

    if direct_m >= target_m * 0.9:
        waypoints: list = [(start_lat, start_lng), (end_lat, end_lng)]
    else:
        needed_extra_m = target_m - direct_m
        perp_bearing = _bearing(start_lat, start_lng, end_lat, end_lng) + 90
        detour_pt = _offset_point(mid_lat, mid_lng, needed_extra_m / 2, perp_bearing)
        waypoints = [
            (start_lat, start_lng),
            detour_pt,
            (end_lat, end_lng),
        ]

    # Initialize with fallback so always bound
    polyline: list = [list(wp) for wp in waypoints]
    source: str = "geometric_fallback"

    for _ in range(MAX_ITER):
        osrm_result, osrm_source = _osrm_route(waypoints)
        if osrm_result is None:
            return [list(wp) for wp in waypoints], "geometric_fallback"

        polyline = osrm_result
        source = osrm_source

        actual_m = _measure_distance_m(polyline)
        if actual_m == 0:
            break

        error_pct = abs(actual_m - target_m) / target_m * 100
        if error_pct <= TOLERANCE_PCT or len(waypoints) < 3:
            break

        # Scale the detour — only reached when needed_extra_m & perp_bearing are set
        scale = target_m / actual_m
        detour_pt = _offset_point(
            mid_lat, mid_lng,
            (needed_extra_m / 2) * scale,
            perp_bearing,
        )
        waypoints[1] = detour_pt

    return polyline, source


# ── OSRM helper ───────────────────────────────────────────────────────────────

def _osrm_route(waypoints: list) -> Tuple[Optional[list], str]:
    coords = ";".join(f"{lng},{lat}" for lat, lng in waypoints)
    url = f"{OSRM_BASE}/route/v1/foot/{coords}?overview=full&geometries=geojson"

    try:
        resp = requests.get(url, timeout=OSRM_TIMEOUT)
        if resp.status_code != 200:
            return None, "osrm_failed"

        data = resp.json()
        if data.get("code") != "Ok" or not data.get("routes"):
            return None, "osrm_failed"

        geojson_coords = data["routes"][0]["geometry"]["coordinates"]
        polyline = [[c[1], c[0]] for c in geojson_coords]
        return polyline, "osrm"

    except requests.RequestException:
        return None, "osrm_failed"


# ── Geometric fallback ────────────────────────────────────────────────────────

def _geometric_loop(start_lat: float, start_lng: float, target_m: float) -> list:
    radius_m = target_m / (2 * math.pi)
    points = []
    steps = 36
    for i in range(steps + 1):
        bearing = (360.0 / steps) * i
        lat, lng = _offset_point(start_lat, start_lng, radius_m, bearing)
        points.append([lat, lng])
    return points


# ── Auto-checkpoint generation ────────────────────────────────────────────────

def _auto_checkpoints(polyline: list, interval_m: float) -> List[RouteCheckpoint]:
    total_m = _measure_distance_m(polyline)
    if total_m == 0 or not polyline:
        return []

    interval_m = min(interval_m, total_m)
    checkpoints: List[RouteCheckpoint] = []
    order = 1

    checkpoints.append(RouteCheckpoint(
        order_number=order,
        name="Start",
        lat=round(polyline[0][0], 6),
        lng=round(polyline[0][1], 6),
        radius_meters=30,
        distance_from_start_m=0.0,
    ))
    order += 1

    cumulative = 0.0
    next_trigger = interval_m
    prev = polyline[0]

    for point in polyline[1:]:
        seg = _haversine_m(prev[0], prev[1], point[0], point[1])
        cumulative += seg

        while cumulative >= next_trigger and next_trigger < total_m - (interval_m * 0.5):
            overshoot = cumulative - next_trigger
            frac = 1.0 - (overshoot / seg) if seg > 0 else 1.0
            lat = prev[0] + frac * (point[0] - prev[0])
            lng = prev[1] + frac * (point[1] - prev[1])

            km_label = round(next_trigger / 1000, 1)
            checkpoints.append(RouteCheckpoint(
                order_number=order,
                name=f"KM {km_label}",
                lat=round(lat, 6),
                lng=round(lng, 6),
                radius_meters=20,
                distance_from_start_m=round(next_trigger, 1),
            ))
            order += 1
            next_trigger += interval_m

        prev = point

    last = polyline[-1]
    checkpoints.append(RouteCheckpoint(
        order_number=order,
        name="Finish",
        lat=round(last[0], 6),
        lng=round(last[1], 6),
        radius_meters=30,
        distance_from_start_m=round(total_m, 1),
    ))

    return checkpoints


# ── Geometry helpers ──────────────────────────────────────────────────────────

def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return EARTH_RADIUS_M * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _measure_distance_m(polyline: list) -> float:
    total = 0.0
    for i in range(len(polyline) - 1):
        total += _haversine_m(
            polyline[i][0], polyline[i][1],
            polyline[i + 1][0], polyline[i + 1][1],
        )
    return total


def _offset_point(lat: float, lng: float, distance_m: float, bearing_deg: float) -> Tuple[float, float]:
    bearing = math.radians(bearing_deg)
    lat_r = math.radians(lat)
    lng_r = math.radians(lng)
    d = distance_m / EARTH_RADIUS_M

    lat2 = math.asin(
        math.sin(lat_r) * math.cos(d)
        + math.cos(lat_r) * math.sin(d) * math.cos(bearing)
    )
    lng2 = lng_r + math.atan2(
        math.sin(bearing) * math.sin(d) * math.cos(lat_r),
        math.cos(d) - math.sin(lat_r) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lng2)


def _bearing(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    lat1_r, lat2_r = math.radians(lat1), math.radians(lat2)
    dlng = math.radians(lng2 - lng1)
    x = math.sin(dlng) * math.cos(lat2_r)
    y = math.cos(lat1_r) * math.sin(lat2_r) - math.sin(lat1_r) * math.cos(lat2_r) * math.cos(dlng)
    return (math.degrees(math.atan2(x, y)) + 360) % 360