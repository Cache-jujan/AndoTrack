"""
generate_data.py — Enhanced synthetic GPS training data for AndoTrack ML model.

Simulates realistic running patterns across multiple runner profiles:
  - Casual joggers (slow, steady pace)
  - Competitive runners (fast, consistent)
  - Interval runners (alternating fast/slow)
  - Tired runners (slowing pace, erratic direction)
  - Race-day stress patterns (crowded start, pace variation)

Anomaly types modeled:
  - Vehicle use (very high speed + high dist_from_last)
  - GPS device jumps (normal speed + extreme dist_from_last)
  - Off-route runners (high dist_from_route)
  - Sudden acceleration (high acceleration)
  - Erratic movement (high direction_change)

NOTE: GPS jump and off-route anomalies are also caught by upstream threshold
checks in determine_reason() before the ML model runs. These are included in
training data so the model can recognise combined-feature anomaly patterns.
"""

import numpy as np
import pandas as pd
import os

np.random.seed(42)

# ── 1. Normal running profiles ────────────────────────────────────────────────

def make_casual_joggers(n: int) -> pd.DataFrame:
    """Slow pace 2.0–3.0 m/s, relaxed direction changes, minor route deviation."""
    return pd.DataFrame({
        'speed':            np.random.normal(2.4, 0.3, n).clip(1.5, 3.2),
        'acceleration':     np.random.normal(0.08, 0.04, n).clip(0, 0.3),
        'direction_change': np.random.normal(6,  4,    n).clip(0, 20),
        'dist_from_route':  np.random.normal(2,  1,    n).clip(0, 8),
        'dist_from_last':   np.random.normal(7,  1.5,  n).clip(3, 12),
        'label': 0,
    })

def make_competitive_runners(n: int) -> pd.DataFrame:
    """Fast pace 4.0–5.0 m/s, tight route following, quick steps."""
    return pd.DataFrame({
        'speed':            np.random.normal(4.3, 0.4, n).clip(3.5, 5.0),
        'acceleration':     np.random.normal(0.12, 0.05, n).clip(0, 0.4),
        'direction_change': np.random.normal(3,  2,    n).clip(0, 12),
        'dist_from_route':  np.random.normal(1,  0.5,  n).clip(0, 4),
        'dist_from_last':   np.random.normal(10, 1.5,  n).clip(6, 15),
        'label': 0,
    })

def make_interval_runners(n: int) -> pd.DataFrame:
    """Alternating fast/slow bursts — higher acceleration variance."""
    speeds = np.where(
        np.random.rand(n) > 0.5,
        np.random.normal(4.0, 0.3, n).clip(3.0, 5.0),
        np.random.normal(2.5, 0.3, n).clip(1.5, 3.5),
    )
    return pd.DataFrame({
        'speed':            speeds,
        'acceleration':     np.random.normal(0.18, 0.08, n).clip(0, 0.5),
        'direction_change': np.random.normal(5,   3,    n).clip(0, 18),
        'dist_from_route':  np.random.normal(2,   1,    n).clip(0, 7),
        'dist_from_last':   np.random.normal(8,   2,    n).clip(3, 15),
        'label': 0,
    })

def make_tired_runners(n: int) -> pd.DataFrame:
    """Late-race fatigue — slower, more direction wobble, slightly off route."""
    return pd.DataFrame({
        'speed':            np.random.normal(2.0, 0.4, n).clip(1.5, 3.0),
        'acceleration':     np.random.normal(0.06, 0.03, n).clip(0, 0.25),
        'direction_change': np.random.normal(9,   4,    n).clip(0, 20),
        'dist_from_route':  np.random.normal(3,   1.2,  n).clip(0, 8),
        'dist_from_last':   np.random.normal(6,   1.5,  n).clip(3, 12),
        'label': 0,
    })

def make_crowded_start(n: int) -> pd.DataFrame:
    """Race start — packed field, slow and stop-start movement."""
    return pd.DataFrame({
        'speed':            np.random.normal(1.8, 0.4, n).clip(1.5, 3.0),
        'acceleration':     np.random.normal(0.15, 0.07, n).clip(0, 0.5),
        'direction_change': np.random.normal(8,   4,    n).clip(0, 20),
        'dist_from_route':  np.random.normal(1.5, 0.8,  n).clip(0, 5),
        'dist_from_last':   np.random.normal(5,   1.5,  n).clip(3, 10),
        'label': 0,
    })

# ── 2. Anomaly profiles ───────────────────────────────────────────────────────

def make_vehicle_anomalies(n: int) -> pd.DataFrame:
    """Runner using a vehicle — very high speed and large step distances."""
    return pd.DataFrame({
        'speed':            np.random.uniform(12, 30, n),
        'acceleration':     np.random.uniform(2.0, 5.0, n),
        'direction_change': np.random.uniform(60, 180, n),
        'dist_from_route':  np.random.uniform(20, 200, n),
        'dist_from_last':   np.random.uniform(100, 500, n),
        'label': 1,
    })

def make_gps_jump_anomalies(n: int) -> pd.DataFrame:
    """GPS device glitch — normal speed but impossibly large step distance."""
    return pd.DataFrame({
        'speed':            np.random.normal(3.0, 0.5, n).clip(1.5, 5.0),
        'acceleration':     np.random.normal(0.1, 0.05, n).clip(0, 0.5),
        'direction_change': np.random.uniform(0, 180, n),
        'dist_from_route':  np.random.normal(2, 1, n).clip(0, 8),
        'dist_from_last':   np.random.uniform(150, 500, n),
        'label': 1,
    })

def make_off_route_anomalies(n: int) -> pd.DataFrame:
    """Runner significantly off the race course."""
    return pd.DataFrame({
        'speed':            np.random.normal(2.8, 0.5, n).clip(1.5, 5.0),
        'acceleration':     np.random.normal(0.1, 0.05, n).clip(0, 0.5),
        'direction_change': np.random.normal(15, 5, n).clip(0, 40),
        'dist_from_route':  np.random.uniform(60, 250, n),
        'dist_from_last':   np.random.normal(8, 2, n).clip(3, 15),
        'label': 1,
    })

def make_acceleration_anomalies(n: int) -> pd.DataFrame:
    """Sudden unexplained speed spike — possible cheating or device error."""
    return pd.DataFrame({
        'speed':            np.random.normal(3.5, 0.5, n).clip(2.5, 5.0),
        'acceleration':     np.random.uniform(3.5, 5.0, n),
        'direction_change': np.random.uniform(60, 150, n),
        'dist_from_route':  np.random.normal(2, 1, n).clip(0, 8),
        'dist_from_last':   np.random.normal(9, 2, n).clip(4, 15),
        'label': 1,
    })

def make_erratic_anomalies(n: int) -> pd.DataFrame:
    """Erratic movement — possible fall, phone dropped, or device issue."""
    return pd.DataFrame({
        'speed':            np.random.normal(2.5, 0.8, n).clip(1.5, 5.0),
        'acceleration':     np.random.uniform(1.0, 3.5, n),
        'direction_change': np.random.uniform(120, 180, n),
        'dist_from_route':  np.random.uniform(5, 60, n),
        'dist_from_last':   np.random.normal(10, 3, n).clip(4, 20),
        'label': 1,
    })

# ── 3. Assemble dataset ───────────────────────────────────────────────────────

normal_frames = [
    make_casual_joggers(600),
    make_competitive_runners(600),
    make_interval_runners(600),
    make_tired_runners(600),
    make_crowded_start(600),
]

anomaly_frames = [
    make_vehicle_anomalies(60),
    make_gps_jump_anomalies(60),
    make_off_route_anomalies(60),
    make_acceleration_anomalies(60),
    make_erratic_anomalies(60),
]

df = pd.concat(
    normal_frames + anomaly_frames,
    ignore_index=True,
).sample(frac=1, random_state=42).reset_index(drop=True)

# ── 4. Save ───────────────────────────────────────────────────────────────────

out_path = os.path.join(os.path.dirname(__file__), 'training_data.csv')
df.to_csv(out_path, index=False)

n_normal  = len(df[df.label == 0])
n_anomaly = len(df[df.label == 1])

print(f"✅ Generated {len(df)} records → training_data.csv")
print(f"   Normal:   {n_normal}  ({n_normal/len(df)*100:.1f}%)")
print(f"   Anomaly:  {n_anomaly}  ({n_anomaly/len(df)*100:.1f}%)")
print(f"   Contamination ratio: {n_anomaly/len(df):.4f}")
print()
print("   Normal profiles:  casual joggers, competitive, interval, tired, crowded start")
print("   Anomaly profiles: vehicle, GPS jump, off-route, sudden acceleration, erratic")
