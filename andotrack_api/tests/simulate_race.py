"""
simulate_race.py — Simulates a full race with 25 runners
"""

import requests
import time
import random
import sys

BASE = "http://localhost:8000"
PASS = 0
FAIL = 0

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
    print(f"\n── {title} {'─' * (50 - len(title))}")

def auth_headers(token):
    return {"Authorization": f"Bearer {token}"}

def safe_json(r):
    try:
        return r.json()
    except Exception:
        return None

random.seed(42)

# Clearly separated distances so segments split correctly:
# Competitive:  12 pings × 0.003° step × ~111m = ~3996m each
# Recreational:  7 pings × 0.001° step × ~111m =  ~777m each
# Casual:        4 pings × 0.0004° step × ~111m = ~177m each
RUNNER_PROFILES = (
    [("Competitive",  round(4.5 + random.uniform(0, 0.5), 2), 12, 0.003)  for _ in range(5)]  +
    [("Recreational", round(3.0 + random.uniform(-0.3, 0.3), 2), 7, 0.001) for _ in range(12)] +
    [("Casual",       round(1.8 + random.uniform(-0.2, 0.2), 2), 4, 0.0004) for _ in range(8)]
)

ORGANIZER = {
    "name": "Race Director",
    "email": f"director_{random.randint(1000,9999)}@andotrack.com",
    "password": "test123",
    "role": "organizer"
}


# ══════════════════════════════════════════════════════
# Step 1 — Register organizer
# ══════════════════════════════════════════════════════
header("Step 1 — Organizer Setup")

r = requests.post(f"{BASE}/auth/register", json=ORGANIZER)
if r.status_code == 400 and "already registered" in r.text:
    r = requests.post(f"{BASE}/auth/login", json={
        "email": ORGANIZER["email"], "password": ORGANIZER["password"]
    })
check("Organizer registered/logged in", r.status_code == 200, r.text)
org_token   = r.json()["access_token"]
org_headers = auth_headers(org_token)

# ══════════════════════════════════════════════════════
# Step 2 — Create race
# ══════════════════════════════════════════════════════
header("Step 2 — Create Race (25 runners, 10km)")

r = requests.post(f"{BASE}/races/", json={
    "name":        "AndoTrack Simulation 10K",
    "distance_km": 10.0,
    "category":    "10K",
    "location":    "Cebu City",
    "status":      "upcoming",
    "max_participants": 30,
}, headers=org_headers)
check("Race created", r.status_code == 200, r.text)
race_id = r.json()["id"]
print(f"       race_id = {race_id}")

# ══════════════════════════════════════════════════════
# Step 3 — Register 25 runners
# ══════════════════════════════════════════════════════
header("Step 3 — Register 25 Runners")

runners = []   # list of {runner_id, token, qr_token, profile}

for i, (profile_type, speed, pings, lat_step) in enumerate(RUNNER_PROFILES):
    uid = random.randint(10000, 99999)
    email    = f"runner_{uid}@andotrack.com"
    password = "runner123"

    # Register user
    r = requests.post(f"{BASE}/auth/register", json={
        "name":     f"{profile_type} Runner {i+1:02d}",
        "email":    email,
        "password": password,
        "role":     "runner"
    })
    if r.status_code not in (200, 400):
        print(f"  ⚠️  Failed to register runner {i+1}: {r.text[:100]}")
        continue

    # Login
    r = requests.post(f"{BASE}/auth/login", json={"email": email, "password": password})
    if r.status_code != 200:
        print(f"  ⚠️  Failed to login runner {i+1}")
        continue

    run_token = r.json()["access_token"]
    runner_id = r.json()["user_id"]

    # Register for race
    r = requests.post(f"{BASE}/races/{race_id}/register", json={
        "city":              "Cebu City",
        "email":             email,
        "contact_number":    f"0917{random.randint(1000000,9999999)}",
        "is_first_marathon": i > 18,
        "emergency_contact": f"Contact {i+1} - 09179999999",
        "sex":               random.choice(["male", "female"]),
        "shirt_size":        random.choice(["S", "M", "L", "XL"]),
    }, headers=auth_headers(run_token))

    if r.status_code != 200:
        print(f"  ⚠️  Runner {i+1} registration failed: {r.text[:100]}")
        continue

    qr_token = r.json()["qr_token"]
    runners.append({
        "runner_id":    runner_id,
        "token":        run_token,
        "qr_token":     qr_token,
        "profile_type": profile_type,
        "speed":        speed,
        "pings":        pings,
        "lat_step":     lat_step,
        "name":         f"{profile_type} Runner {i+1:02d}",
    })

check(f"All 25 runners registered", len(runners) == 25, f"got {len(runners)}")
print(f"       → {len(runners)} runners ready")

# ══════════════════════════════════════════════════════
# Step 4 — Check in all runners (organizer scans QR)
# ══════════════════════════════════════════════════════
header("Step 4 — Check In All Runners")

checked_in = 0
for runner in runners:
    r = requests.post(f"{BASE}/races/{race_id}/checkin",
        json={"qr_token": runner["qr_token"]},
        headers=org_headers)
    if r.status_code == 200:
        checked_in += 1
    else:
        print(f"  ⚠️  Check-in failed for {runner['name']}: {r.text[:80]}")

check(f"All runners checked in", checked_in == 25, f"checked in: {checked_in}/25")

# ══════════════════════════════════════════════════════
# Step 5 — Start race
# ══════════════════════════════════════════════════════
header("Step 5 — Start Race")

r = requests.post(f"{BASE}/races/{race_id}/start", headers=org_headers)
check("Race started", r.status_code == 200, r.text)
check("Status active", r.json().get("status") == "active")

# ══════════════════════════════════════════════════════
# Step 6 — Send GPS pings for each runner
# Competitive runners get more pings + larger steps = more distance
# ══════════════════════════════════════════════════════
header("Step 6 — GPS Pings for All 25 Runners")

BASE_LAT = 10.3157
BASE_LNG = 123.8854

ping_errors = 0
for runner in runners:
    lat = BASE_LAT
    # Stagger starting position slightly per runner
    lat_offset = random.uniform(-0.0005, 0.0005)
    lat = BASE_LAT + lat_offset

    for ping_num in range(runner["pings"]):
        lat += runner["lat_step"]
        r = requests.post(
            f"{BASE}/runners/{runner['runner_id']}/location",
            json={
                "lat":     round(lat, 6),
                "lng":     BASE_LNG,
                "speed":   runner["speed"],
                "race_id": race_id,
            }
        )
        if r.status_code != 200:
            ping_errors += 1

check("GPS pings sent without errors", ping_errors == 0,
      f"{ping_errors} ping errors")
print(f"       → {sum(r['pings'] for r in runners)} total pings sent")

# Quick distance check
r = requests.get(
    f"{BASE}/runners/race/{race_id}/distances",
    headers=auth_headers(runners[0]["token"]))
distances = safe_json(r)
if distances:
    print(f"       → {len(distances.get('runners', []))} runners have GPS data")
    top = distances["runners"][0] if distances["runners"] else {}
    print(f"       → furthest: {top.get('distance_formatted')} "
          f"(runner {top.get('runner_id')})")

# ══════════════════════════════════════════════════════
# Step 7 — Mark 2 runners as DNF (organizer)
# ══════════════════════════════════════════════════════
header("Step 7 — Mark 2 Casual Runners as DNF")

dnf_runners = [r for r in runners if r["profile_type"] == "Casual"][:2]
for runner in dnf_runners:
    r = requests.patch(
        f"{BASE}/races/{race_id}/runners/{runner['runner_id']}/status?status=dnf",
        headers=org_headers)
    if r.status_code == 200:
        print(f"       → DNF: {runner['name']}")
    else:
        print(f"  ⚠️  DNF failed: {r.text[:80]}")

# Debug — check tracker contents before finish
r = requests.get(f"{BASE}/runners/race/{race_id}/distances",
                 headers=auth_headers(runners[0]["token"]))
dist_data = safe_json(r)
print(f"\n  DEBUG: runners with GPS data = {len(dist_data.get('runners', []))}")
for d in dist_data.get("runners", [])[:5]:
    print(f"    runner {d['runner_id']}: {d['distance_formatted']}")
    
# ══════════════════════════════════════════════════════
# Step 8 — Finish race
# ══════════════════════════════════════════════════════
header("Step 8 — Finish Race")

r = requests.post(f"{BASE}/races/{race_id}/finish", headers=org_headers)
check("Finish race 200", r.status_code == 200, r.text[:200])
finish_data = safe_json(r)
check("Finish has body",    finish_data is not None)
check("Total finishers > 0", finish_data.get("total", 0) > 0 if finish_data else False,
      finish_data)

if finish_data:
    print(f"       → total finishers: {finish_data.get('total')}")
    print(f"\n       Top 5 finishers:")
    for row in finish_data.get("results", [])[:5]:
        print(f"         #{row['rank']:2d}  {row['name']:<28} "
              f"{row['distance_formatted']:<10} {row['pace_formatted']}")

# ══════════════════════════════════════════════════════
# Step 9 — Results with segments
# ══════════════════════════════════════════════════════
header("Step 9 — Results with Segments")

r = requests.get(f"{BASE}/races/{race_id}/results",
                 headers=auth_headers(runners[0]["token"]))
check("Results load", r.status_code == 200, r.text[:200])
results_data = safe_json(r)
rows = results_data.get("results", []) if results_data else []
check("Results not empty", len(rows) > 0)
check("All have segment", all(row.get("segment") for row in rows), rows[:1])

if rows:
    comp = [r for r in rows if r["segment"] == "competitive"]
    rec  = [r for r in rows if r["segment"] == "recreational"]
    cas  = [r for r in rows if r["segment"] == "casual"]
    print(f"\n       Segment breakdown:")
    print(f"         competitive:  {len(comp)} runners")
    print(f"         recreational: {len(rec)} runners")
    print(f"         casual:       {len(cas)} runners")
    print(f"\n       Full standings:")
    for row in rows:
        seg_tag = {"competitive": "🏆", "recreational": "🏃", "casual": "🚶"}.get(
            row["segment"], "?")
        print(f"         {seg_tag} #{row['rank']:2d}  {row['name']:<28} "
              f"{row.get('distance_formatted','?'):<10} "
              f"{row.get('pace_formatted','-'):<12} [{row['segment']}]")

# ══════════════════════════════════════════════════════
# Step 10 — Analytics
# ══════════════════════════════════════════════════════
header("Step 10 — Analytics")

r = requests.get(f"{BASE}/races/{race_id}/analytics", headers=org_headers)
check("Analytics loads", r.status_code == 200, r.text[:300])

if r.status_code == 200:
    data   = safe_json(r)
    funnel = data.get("participation_funnel", {})
    segs   = data.get("segments", {})
    anom   = data.get("anomaly_summary", {})

    check("Registered = 25",   funnel.get("registered") == 25, funnel)
    check("Checked in = 25",   funnel.get("checked_in") == 25, funnel)
    check("Finishers > 0",     funnel.get("finishers",  0) > 0)
    check("DNF = 2",           funnel.get("dnf") == 2, funnel)
    check("Competitive > 0",   segs.get("competitive",  {}).get("count", 0) > 0)
    check("Recreational > 0",  segs.get("recreational", {}).get("count", 0) > 0)
    check("Casual > 0",        segs.get("casual",       {}).get("count", 0) > 0)
    check("Anomaly summary",   bool(anom))

    print(f"""
       ┌─────────────────────────────────────────┐
       │         RACE ANALYTICS SUMMARY          │
       ├─────────────────────────────────────────┤
       │ Race:        {data.get('race_name',''):<27} │
       │ Status:      {data.get('status',''):<27} │
       ├─────────────────────────────────────────┤
       │ PARTICIPATION FUNNEL                    │
       │   Registered:   {funnel.get('registered',0):<24} │
       │   Checked in:   {funnel.get('checked_in',0):<24} │
       │   Finishers:    {funnel.get('finishers',0):<24} │
       │   DNF:          {funnel.get('dnf',0):<24} │
       │   DNS:          {funnel.get('dns',0):<24} │
       │   No-show rate: {funnel.get('no_show_rate',0):<23}% │
       │   DNF rate:     {funnel.get('dnf_rate',0):<23}% │
       ├─────────────────────────────────────────┤
       │ SEGMENTS                                │
       │   🏆 Competitive:                       │
       │      Count:  {segs.get('competitive',{}).get('count',0):<27} │
       │      Pace:   {segs.get('competitive',{}).get('avg_pace_formatted') or 'N/A':<27} │
       │   🏃 Recreational:                      │
       │      Count:  {segs.get('recreational',{}).get('count',0):<27} │
       │      Pace:   {segs.get('recreational',{}).get('avg_pace_formatted') or 'N/A':<27} │
       │   🚶 Casual:                            │
       │      Count:  {segs.get('casual',{}).get('count',0):<27} │
       │      Pace:   {segs.get('casual',{}).get('avg_pace_formatted') or 'N/A':<27} │
       ├─────────────────────────────────────────┤
       │ ANOMALIES                               │
       │   Total:     {anom.get('total_detected',0):<27} │
       │   Resolved:  {anom.get('resolved',0):<27} │
       │   Unresolved:{anom.get('unresolved',0):<27} │
       └─────────────────────────────────────────┘""")

    if anom.get("by_type"):
        print("       Anomaly types:")
        for atype, count in anom["by_type"].items():
            print(f"         • {atype}: {count}")

# ══════════════════════════════════════════════════════
# Step 11 — Export per segment
# ══════════════════════════════════════════════════════
header("Step 11 — Analytics Export per Segment")

for seg in ("competitive", "recreational", "casual", "all"):
    r = requests.get(
        f"{BASE}/races/{race_id}/analytics/export?segment={seg}",
        headers=org_headers)
    check(f"Export {seg} (200 or 404)",
          r.status_code in (200, 404), r.text[:100])
    if r.status_code == 200:
        data = safe_json(r)
        count = data.get("count", 0) if data else 0
        print(f"       → {seg}: {count} runners")
        if data and data.get("runners") and seg != "all":
            for row in data["runners"][:3]:
                print(f"         #{row['rank']:2d} {row['name']:<28} "
                      f"{row['pace_formatted']:<12} [{row['segment']}]")
    else:
        print(f"       → {seg}: empty segment")

# ══════════════════════════════════════════════════════
# Step 12 — Leaderboard
# ══════════════════════════════════════════════════════
header("Step 12 — Leaderboard (finished race)")

r = requests.get(f"{BASE}/leaderboard/{race_id}",
                 headers=auth_headers(runners[0]["token"]))
check("Leaderboard loads", r.status_code == 200)
lb = safe_json(r)
if lb:
    print(f"       → finished: {len(lb.get('finished', []))}")
    print(f"       → racing:   {len(lb.get('racing', []))}")

# ══════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════
print(f"\n{'=' * 55}")
print(f"  {PASS}/{PASS+FAIL} checks passed  "
      f"{'✅ All good!' if FAIL == 0 else f'❌ {FAIL} failed'}")
print(f"  Race ID {race_id} — check it in Swagger or MySQL Workbench")
print(f"{'=' * 55}\n")
sys.exit(1 if FAIL else 0)
