"""
simulate_race.py — AndoTrack organizer dashboard demo
  10 runners · 3 checkpoints · round-based GPS · anomaly injection
"""

import requests
import time
import random
import math
import sys

BASE = "https://andotrack-production.up.railway.app"
PASS = 0
FAIL = 0


# ═══════════════════════════════════════════════════════════════════
# Utility helpers
# ═══════════════════════════════════════════════════════════════════

def check(label, condition, got=None):
    global PASS, FAIL
    if condition:
        print(f"  ✅  {label}")
        PASS += 1
    else:
        print(f"  ❌  {label}")
        if got is not None:
            print(f"       → got: {got}")
        FAIL += 1


def header(title):
    print(f"\n── {title} {'─' * max(1, 52 - len(title))}")


def auth_headers(token):
    return {"Authorization": f"Bearer {token}"}


def safe_json(r):
    try:
        return r.json()
    except Exception:
        return None


# ═══════════════════════════════════════════════════════════════════
# Route geometry  (R. Palma Street, Cebu City — straight one-way)
# ═══════════════════════════════════════════════════════════════════

def haversine_m(lat1, lng1, lat2, lng2):
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lng2 - lng1)
    a = (math.sin(dphi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(min(a, 1.0)))


WAYPOINTS = [
    (10.297289, 123.907564),  # 0 — Start Line
    (10.297469, 123.906618),  # 1 — Checkpoint 2
    (10.297559, 123.905890),  # 2 — Finish Line
]

_CUM = [0.0]
for _i in range(1, len(WAYPOINTS)):
    _CUM.append(_CUM[-1] + haversine_m(*WAYPOINTS[_i - 1], *WAYPOINTS[_i]))

ROUTE_LEN_M = _CUM[-1]


def pos_at(cum_m: float) -> tuple:
    """Linearly interpolate (lat, lng) at cumulative metres along route."""
    cum_m = max(0.0, min(cum_m, ROUTE_LEN_M))
    for i in range(1, len(WAYPOINTS)):
        if cum_m <= _CUM[i]:
            t = (cum_m - _CUM[i - 1]) / (_CUM[i] - _CUM[i - 1])
            lat = WAYPOINTS[i - 1][0] + t * (WAYPOINTS[i][0] - WAYPOINTS[i - 1][0])
            lng = WAYPOINTS[i - 1][1] + t * (WAYPOINTS[i][1] - WAYPOINTS[i - 1][1])
            return round(lat, 6), round(lng, 6)
    return WAYPOINTS[-1]


print("\n" + "═" * 57)
print(f"  AndoTrack Live Demo — Route  (R. Palma St, Cebu)")
print("═" * 57)
_CP_LABELS = ["Start Line", "Checkpoint 2", "Finish Line"]
for i, ((lat, lng), cum, label) in enumerate(zip(WAYPOINTS, _CUM, _CP_LABELS)):
    print(f"  {label:<14}  ({lat}, {lng})  cum={cum:.1f} m")
print(f"\n  Total route length: {ROUTE_LEN_M:.1f} m")


# ═══════════════════════════════════════════════════════════════════
# Seed and runner profiles
# ═══════════════════════════════════════════════════════════════════

random.seed(42)

ORGANIZER = {
    "name":     "Race Director",
    "email":    f"director_{random.randint(1000, 9999)}@andotrack.com",
    "password": "test123",
    "role":     "organizer",
}

_COMP_NAMES = ["Carlos Reyes", "Mark Santos"]
_REC_NAMES  = ["Ana Garcia", "Beth Torres", "Chloe Lim", "Diana Uy", "Edgar Ramos"]
_CAS_NAMES  = ["Felix Chan", "Grace Tan", "Hugo Dela Cruz"]

# (profile_type, speed_m/s, dist_per_round_m, display_name)
_RUNNER_DEFS = (
    [("Competitive",  round(4.8 + random.uniform(0.0, 0.4), 2), 40, n) for n in _COMP_NAMES]
  + [("Recreational", round(2.8 + random.uniform(0.0, 0.5), 2), 22, n) for n in _REC_NAMES]
  + [("Casual",       round(1.5 + random.uniform(0.0, 0.4), 2), 13, n) for n in _CAS_NAMES]
)

_CP_NAMES = ["Start Line", "Checkpoint 2", "Finish Line"]
CHECKPOINT_DEFS = [
    {"name": _CP_NAMES[i], "lat": WAYPOINTS[i][0], "lng": WAYPOINTS[i][1],
     "order": i + 1, "cum_dist": _CUM[i], "id": None}
    for i in range(len(WAYPOINTS))
]

ROUNDS      = 10
ROUND_SLEEP = 2   # seconds between rounds


# ═══════════════════════════════════════════════════════════════════
# Step 1 — Organizer setup
# ═══════════════════════════════════════════════════════════════════
header("Step 1 — Organizer Setup")

r = requests.post(f"{BASE}/auth/register", json=ORGANIZER)
if r.status_code == 400 and "already" in r.text.lower():
    r = requests.post(f"{BASE}/auth/login", json={
        "email": ORGANIZER["email"], "password": ORGANIZER["password"],
    })
check("Organizer registered/logged in", r.status_code == 200, r.text[:100])
org_token   = r.json()["access_token"]
org_headers = auth_headers(org_token)


# ═══════════════════════════════════════════════════════════════════
# Step 2 — Create race
# ═══════════════════════════════════════════════════════════════════
header("Step 2 — Create Race")

r = requests.post(f"{BASE}/races/", json={
    "name":              "AndoTrack Live Demo",
    "distance_km":       round(ROUTE_LEN_M / 1000, 2),
    "category":          "Fun Run",
    "location":          "R. Palma Street, Cebu City",
    "status":            "upcoming",
    "max_participants":  15,
}, headers=org_headers)
check("Race created", r.status_code == 200, r.text[:100])
race_id = r.json()["id"]
print(f"       race_id = {race_id}  ({round(ROUTE_LEN_M / 1000, 2)} km route)")


# ═══════════════════════════════════════════════════════════════════
# Step 3 — Create 3 checkpoints
# ═══════════════════════════════════════════════════════════════════
header("Step 3 — Create 3 Checkpoints")

for cp in CHECKPOINT_DEFS:
    r = requests.post(f"{BASE}/checkpoints/", json={
        "race_id":      race_id,
        "name":         cp["name"],
        "lat":          cp["lat"],
        "lng":          cp["lng"],
        "order_number": cp["order"],
    })
    if r.status_code == 200:
        cp["id"] = r.json()["id"]
        print(f"       ✔ #{cp['order']} {cp['name']:<14}  id={cp['id']}  @{cp['cum_dist']:.1f} m")
    else:
        print(f"  ⚠️  Failed to create {cp['name']}: {r.text[:80]}")

check("All 3 checkpoints created", all(cp["id"] is not None for cp in CHECKPOINT_DEFS))


# ═══════════════════════════════════════════════════════════════════
# Step 4 — Register 10 runners
# ═══════════════════════════════════════════════════════════════════
header("Step 4 — Register 10 Runners (2 competitive / 5 recreational / 3 casual)")

runners = []

for profile_type, speed, dist_per_round, name in _RUNNER_DEFS:
    # Name-based email: always the same account for the same runner name across runs
    email    = f"runner.{name.lower().replace(' ', '.')}@andotrack.com"
    password = "runner123"

    r = requests.post(f"{BASE}/auth/register", json={
        "name": name, "email": email, "password": password, "role": "runner",
    })
    if r.status_code not in (200, 400):
        print(f"  ⚠️  Failed to register {name}: {r.text[:80]}")
        continue

    r = requests.post(f"{BASE}/auth/login", json={"email": email, "password": password})
    if r.status_code != 200:
        print(f"  ⚠️  Failed to login {name}")
        continue
    run_token = r.json()["access_token"]
    runner_id = r.json()["user_id"]

    r = requests.post(f"{BASE}/races/{race_id}/register", json={
        "city":              "Cebu City",
        "email":             email,
        "contact_number":    f"0917{random.randint(1_000_000, 9_999_999)}",
        "is_first_marathon": False,
        "emergency_contact": "Emergency - 09179999999",
        "sex":               random.choice(["male", "female"]),
        "shirt_size":        random.choice(["S", "M", "L", "XL"]),
    }, headers=auth_headers(run_token))
    if r.status_code != 200:
        print(f"  ⚠️  Race registration failed for {name}: {r.text[:80]}")
        continue

    qr_token = r.json()["qr_token"]
    runners.append({
        "runner_id":      runner_id,
        "token":          run_token,
        "qr_token":       qr_token,
        "name":           name,
        "profile_type":   profile_type,
        "speed":          speed,
        "dist_per_round": dist_per_round,
        "cum_dist":       0.0,
        "finished":       False,
        "dnf":            False,
    })
    print(f"       ✔ {name:<22} [{profile_type}]  {speed} m/s  {dist_per_round} m/round")

check("All 10 runners registered", len(runners) == 10, f"got {len(runners)}")

if len(runners) < 3:
    print("  ❌ Not enough runners — aborting")
    sys.exit(1)

# Runner A = first competitive (vehicle_speed injection, round 3)
# Runner B = first recreational (gps_jump injection, round 6)
runner_a_id = runners[0]["runner_id"]   # Carlos Reyes
runner_b_id = runners[2]["runner_id"]   # Ana Garcia
print(f"\n       Runner A (vehicle_speed, round 3):  {runners[0]['name']}")
print(f"       Runner B (gps_jump,      round 6):  {runners[2]['name']}")


# ═══════════════════════════════════════════════════════════════════
# Step 5 — Check in all runners
# ═══════════════════════════════════════════════════════════════════
header("Step 5 — Check In All Runners (organizer scans QR)")

checked_in = 0
for runner in runners:
    r = requests.post(
        f"{BASE}/races/{race_id}/checkin",
        json={"qr_token": runner["qr_token"]},
        headers=org_headers,
    )
    if r.status_code == 200:
        checked_in += 1
    else:
        print(f"  ⚠️  Check-in failed for {runner['name']}: {r.text[:60]}")

check("All runners checked in", checked_in == len(runners),
      f"{checked_in}/{len(runners)}")


# ═══════════════════════════════════════════════════════════════════
# Step 6 — Start race
# ═══════════════════════════════════════════════════════════════════
header("Step 6 — Start Race")

r = requests.post(f"{BASE}/races/{race_id}/start", headers=org_headers)
check("Race started",  r.status_code == 200, r.text[:100])
check("Status active", (safe_json(r) or {}).get("status") == "active")


# ═══════════════════════════════════════════════════════════════════
# Step 7 — GPS rounds loop
# ═══════════════════════════════════════════════════════════════════
header(f"Step 7 — GPS Rounds ({ROUNDS} rounds, {ROUND_SLEEP} s between rounds)")

org_email = ORGANIZER["email"]
print(f"\n  ┌─────────────────────────────────────────────────────┐")
print(f"  │  Open the organizer dashboard now:                  │")
print(f"  │  Login: {org_email:<44} │")
print(f"  │  Password: test123                                  │")
print(f"  │  Navigate to race ID: {race_id:<32} │")
print(f"  └─────────────────────────────────────────────────────┘")
input("\n  Press Enter when you're on the live dashboard to start GPS pings...")

passed_checkpoints: set = set()   # (runner_id, cp_id)
ping_errors = 0

for round_num in range(1, ROUNDS + 1):
    print(f"\n  ── Round {round_num:2d}/{ROUNDS} {'─' * 40}")

    # ── GPS pings ────────────────────────────────────────────────────
    for runner in runners:
        if runner["finished"] or runner["dnf"]:
            status = "[done]" if runner["finished"] else "[DNF]"
            print(f"     · {runner['name']:<22}  {status}")
            continue

        rid = runner["runner_id"]

        if rid == runner_a_id and round_num == 3:
            # Anomaly: vehicle speed — normal position, impossible speed
            lat, lng = pos_at(runner["cum_dist"])
            speed    = 22.0
            runner["cum_dist"] = min(runner["cum_dist"] + runner["dist_per_round"], ROUTE_LEN_M)
            print(f"     🚨 ANOMALY  vehicle_speed  {runner['name']}  speed={speed} m/s")

        elif rid == runner_b_id and round_num == 6:
            # Anomaly: GPS jump — 0.003° north (~333 m off-route, >> 200 m threshold)
            cur_lat, cur_lng = pos_at(runner["cum_dist"])
            lat  = round(cur_lat + 0.003, 6)
            lng  = cur_lng
            speed = runner["speed"]
            runner["cum_dist"] = min(runner["cum_dist"] + runner["dist_per_round"], ROUTE_LEN_M)
            print(f"     🚨 ANOMALY  gps_jump       {runner['name']}  +333 m off-route")

        else:
            runner["cum_dist"] = min(runner["cum_dist"] + runner["dist_per_round"], ROUTE_LEN_M)
            lat, lng = pos_at(runner["cum_dist"])
            speed    = runner["speed"] + random.uniform(-0.1, 0.1)

        r = requests.post(
            f"{BASE}/runners/{rid}/location",
            json={"lat": lat, "lng": lng, "speed": round(speed, 2), "race_id": race_id},
        )
        if r.status_code != 200:
            ping_errors += 1
            print(f"     ⚠️  Ping error {runner['name']}: {r.text[:60]}")
        else:
            data = safe_json(r) or {}
            anom = data.get("anomaly")
            km   = (data.get("distance") or {}).get("km", "?")
            if anom:
                print(f"     ⚡ {runner['name']:<22}  {anom['reason'].upper():<16}  "
                      f"score={anom['score']:.3f}")
            else:
                print(f"     · {runner['name']:<22}  {km:.3f} km  {speed:.1f} m/s")

    # ── Checkpoint threshold check ────────────────────────────────────
    for runner in runners:
        if runner["dnf"]:
            continue
        for cp in CHECKPOINT_DEFS:
            if cp["id"] is None:
                continue
            pair = (runner["runner_id"], cp["id"])
            if pair in passed_checkpoints:
                continue
            if runner["cum_dist"] >= cp["cum_dist"]:
                r = requests.post(
                    f"{BASE}/checkpoints/{cp['id']}/arrive",
                    params={"runner_id": runner["runner_id"]},
                )
                if r.status_code in (200, 400):
                    passed_checkpoints.add(pair)
                    print(f"       ✔ {runner['name']:<22}  passed {cp['name']}")
                else:
                    print(f"       ⚠️  arrive failed {runner['name']} @ {cp['name']}: "
                          f"{r.text[:60]}")

        if runner["cum_dist"] >= ROUTE_LEN_M and not runner["finished"]:
            runner["finished"] = True

    # ── Round summary ─────────────────────────────────────────────────
    active   = sum(1 for rr in runners if not rr["finished"] and not rr["dnf"])
    finished = sum(1 for rr in runners if rr["finished"])
    print(f"\n     Active={active}  Finished={finished}")

    if round_num < ROUNDS:
        time.sleep(ROUND_SLEEP)

check("GPS pings without errors", ping_errors == 0, f"{ping_errors} errors")


# ═══════════════════════════════════════════════════════════════════
# Step 8 — Mark 1 casual runner as DNF
# ═══════════════════════════════════════════════════════════════════
header("Step 8 — Mark 1 Casual Runner as DNF")

dnf_runners = [rr for rr in runners if rr["profile_type"] == "Casual"][-1:]
for runner in dnf_runners:
    runner["dnf"] = True
    r = requests.patch(
        f"{BASE}/races/{race_id}/runners/{runner['runner_id']}/status?status=dnf",
        headers=org_headers,
    )
    if r.status_code == 200:
        print(f"       → DNF: {runner['name']}")
    else:
        print(f"  ⚠️  DNF failed for {runner['name']}: {r.text[:80]}")


# ═══════════════════════════════════════════════════════════════════
# Step 9 — Finish race (bulk result save)
# ═══════════════════════════════════════════════════════════════════
header("Step 9 — Finish Race")

r = requests.post(f"{BASE}/races/{race_id}/finish", headers=org_headers)
check("Finish race 200", r.status_code == 200, r.text[:200])
finish_data = safe_json(r)
check("Finish has body",     finish_data is not None)
check("Total finishers > 0", (finish_data or {}).get("total", 0) > 0)

if finish_data:
    print(f"\n       Total finishers: {finish_data.get('total')}")
    print(f"\n       Top 5:")
    for row in finish_data.get("results", [])[:5]:
        print(f"         #{row.get('rank', 0):2d}  {row.get('name', '?'):<22}"
              f"  {row.get('distance_formatted', '?'):<10}"
              f"  {row.get('pace_formatted', '?')}")


# ═══════════════════════════════════════════════════════════════════
# Step 10 — Results with segments
# ═══════════════════════════════════════════════════════════════════
header("Step 10 — Results with Segments")

r = requests.get(f"{BASE}/races/{race_id}/results",
                 headers=auth_headers(runners[0]["token"]))
check("Results load", r.status_code == 200, r.text[:200])
results_data = safe_json(r)
rows = (results_data or {}).get("results", [])
check("Results not empty",  len(rows) > 0)
check("All have segment",   all(row.get("segment") for row in rows))

if rows:
    comp = [row for row in rows if row.get("segment") == "competitive"]
    rec  = [row for row in rows if row.get("segment") == "recreational"]
    cas  = [row for row in rows if row.get("segment") == "casual"]
    print(f"\n       Segment breakdown:")
    print(f"         Competitive:   {len(comp)}")
    print(f"         Recreational:  {len(rec)}")
    print(f"         Casual:        {len(cas)}")
    print(f"\n       Full standings:")
    for row in rows:
        tag = {"competitive": "🏆", "recreational": "🏃", "casual": "🚶"}.get(
            row.get("segment"), "?")
        print(f"         {tag} #{row.get('rank', 0):2d}  {row.get('name', '?'):<22}"
              f"  {row.get('distance_formatted', '?'):<10}"
              f"  {row.get('pace_formatted', '-'):<14}"
              f"  [{row.get('segment', '?')}]")


# ═══════════════════════════════════════════════════════════════════
# Step 11 — Analytics
# ═══════════════════════════════════════════════════════════════════
header("Step 11 — Analytics")

r = requests.get(f"{BASE}/races/{race_id}/analytics", headers=org_headers)
check("Analytics loads", r.status_code == 200, r.text[:200])

if r.status_code == 200:
    data   = safe_json(r) or {}
    funnel = data.get("participation_funnel", {})
    segs   = data.get("segments", {})
    anom   = data.get("anomaly_summary", {})

    check("Registered = 10",  funnel.get("registered") == 10, funnel)
    check("Checked in = 10",  funnel.get("checked_in") == 10, funnel)
    check("Finishers > 0",    funnel.get("finishers", 0) > 0)
    check("DNF = 1",          funnel.get("dnf") == 1, funnel)
    check("Competitive > 0",  segs.get("competitive",  {}).get("count", 0) > 0)
    check("Recreational > 0", segs.get("recreational", {}).get("count", 0) > 0)
    check("Casual > 0",       segs.get("casual",       {}).get("count", 0) > 0)

    def _s(val, width=27):
        return str(val)[:width].ljust(width)

    print(f"""
       ┌──────────────────────────────────────────────┐
       │          RACE ANALYTICS SUMMARY              │
       ├──────────────────────────────────────────────┤
       │ Race:        {_s(data.get('race_name',''))} │
       │ Status:      {_s(data.get('status',''))} │
       ├──────────────────────────────────────────────┤
       │ PARTICIPATION FUNNEL                         │
       │   Registered:   {_s(funnel.get('registered',0))} │
       │   Checked in:   {_s(funnel.get('checked_in',0))} │
       │   Finishers:    {_s(funnel.get('finishers',0))} │
       │   DNF:          {_s(funnel.get('dnf',0))} │
       │   DNS:          {_s(funnel.get('dns',0))} │
       │   DNF rate:     {_s(str(funnel.get('dnf_rate',0)) + '%')} │
       ├──────────────────────────────────────────────┤
       │ SEGMENTS                                     │
       │   🏆 Competitive  ({segs.get('competitive',{}).get('count',0)} runners)            │
       │      Avg pace: {_s(segs.get('competitive',{}).get('avg_pace_formatted') or 'N/A')} │
       │   🏃 Recreational ({segs.get('recreational',{}).get('count',0)} runners)           │
       │      Avg pace: {_s(segs.get('recreational',{}).get('avg_pace_formatted') or 'N/A')} │
       │   🚶 Casual       ({segs.get('casual',{}).get('count',0)} runners)                 │
       │      Avg pace: {_s(segs.get('casual',{}).get('avg_pace_formatted') or 'N/A')} │
       ├──────────────────────────────────────────────┤
       │ ANOMALIES                                    │
       │   Total:     {_s(anom.get('total_detected',0))} │
       │   Resolved:  {_s(anom.get('resolved',0))} │
       │   Unresolved:{_s(anom.get('unresolved',0))} │
       └──────────────────────────────────────────────┘""")

    if anom.get("by_type"):
        print("       By type:")
        for atype, count in anom["by_type"].items():
            print(f"         • {atype}: {count}")


# ═══════════════════════════════════════════════════════════════════
# Step 12 — Verify anomaly detection
# ═══════════════════════════════════════════════════════════════════
header("Step 12 — Verify Anomaly Detection")

r = requests.get(f"{BASE}/races/{race_id}/anomalies", headers=org_headers)
check("Anomalies endpoint loads", r.status_code == 200, r.text[:100])

anomaly_list = safe_json(r)
if not isinstance(anomaly_list, list):
    anomaly_list = []

vehicle_speed_count = sum(1 for a in anomaly_list if a.get("reason") == "vehicle_speed")
gps_jump_count      = sum(1 for a in anomaly_list if a.get("reason") == "gps_jump")

check("vehicle_speed detected (≥1)", vehicle_speed_count >= 1, f"got {vehicle_speed_count}")
check("gps_jump detected (≥1)",      gps_jump_count >= 1,      f"got {gps_jump_count}")

if anomaly_list:
    print(f"\n       Anomalies ({len(anomaly_list)} total):")
    for a in anomaly_list:
        name = a.get("runner_name") or f"Runner #{a.get('runner_id')}"
        print(f"         • [{a.get('reason','?').upper():<16}]  "
              f"{name:<22}  score={a.get('score', 0):.3f}")


# ═══════════════════════════════════════════════════════════════════
# Step 13 — Analytics export per segment
# ═══════════════════════════════════════════════════════════════════
header("Step 13 — Analytics Export per Segment")

for seg in ("competitive", "recreational", "casual", "all"):
    r = requests.get(
        f"{BASE}/races/{race_id}/analytics/export?segment={seg}",
        headers=org_headers,
    )
    check(f"Export {seg} (200 or 404)", r.status_code in (200, 404), r.text[:80])
    if r.status_code == 200:
        data  = safe_json(r) or {}
        count = data.get("count", 0)
        print(f"       → {seg:<14}: {count} runners")
        if data.get("runners") and seg != "all":
            for row in data["runners"][:2]:
                print(f"         #{row.get('rank',0):2d}  {row.get('name','?'):<22}"
                      f"  {row.get('pace_formatted','?')}")
    else:
        print(f"       → {seg:<14}: empty / no segment")


# ═══════════════════════════════════════════════════════════════════
# Step 14 — Leaderboard
# ═══════════════════════════════════════════════════════════════════
header("Step 14 — Leaderboard")

r = requests.get(f"{BASE}/leaderboard/{race_id}",
                 headers=auth_headers(runners[0]["token"]))
check("Leaderboard loads", r.status_code == 200)
lb = safe_json(r) or {}
print(f"       Finished: {len(lb.get('finished', []))}")
print(f"       Racing:   {len(lb.get('racing', []))}")
for row in lb.get("finished", [])[:5]:
    print(f"         #{row.get('rank', 0):2d}  {row.get('name', '?')}")


# ═══════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════
print(f"\n{'═' * 57}")
print(f"  {PASS}/{PASS + FAIL} checks passed  "
      f"{'✅ All good!' if FAIL == 0 else f'❌ {FAIL} failed'}")
print(f"  Race ID {race_id} — open the organizer dashboard to see live data")
print(f"{'═' * 57}\n")

sys.exit(1 if FAIL else 0)
