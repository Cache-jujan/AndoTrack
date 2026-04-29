"""
accuracy_test.py — Day 36 ML Accuracy Test for AndoTrack Isolation Forest model.

Tests detection rate against known anomaly scenarios.
Acceptance threshold: 80% detection rate on anomalies.

Architecture note:
  determine_reason() applies threshold checks BEFORE the ML model runs:
    - speed > 10 m/s        → "Vehicle speed detected"
    - dist_from_last > 100  → "GPS jump detected"
    - dist_from_route > 50  → "Runner off route"
  The ML model is the SECOND line of defence for subtle combined-feature
  anomalies that don't trigger simple thresholds.

This test covers BOTH layers — threshold-caught and ML-caught anomalies.

Run with:
    python ml/accuracy_test.py
"""

import pickle
import os
import pandas as pd
import numpy as np
import sys

# ── Load model ────────────────────────────────────────────────────────────────

BASE_DIR = os.path.dirname(__file__)
model_path = os.path.join(BASE_DIR, "anomaly_model.pkl")

if not os.path.exists(model_path):
    print("❌ anomaly_model.pkl not found.")
    print("   Run: python ml/train_model.py")
    sys.exit(1)

with open(model_path, "rb") as f:
    model = pickle.load(f)

FEATURES = ["speed", "acceleration", "direction_change", "dist_from_route", "dist_from_last"]


# ── determine_reason() — mirrors the actual pipeline ─────────────────────────

def determine_reason(features: list) -> str:
    speed, acceleration, direction_change, dist_from_route, dist_from_last = features
    if speed > 10:
        return "Vehicle speed detected"
    if dist_from_last > 100:
        return "GPS jump detected"
    if dist_from_route > 50:
        return "Runner off route"
    if acceleration > 3:
        return "Sudden speed spike"
    if direction_change > 120:
        return "Erratic movement detected"
    return "Unusual pattern detected"


def full_pipeline_predict(features: list) -> tuple:
    """
    Mirrors the actual detection pipeline:
    1. determine_reason() threshold check first
    2. ML model as second layer
    Returns (is_anomaly, reason, source)
    """
    speed, acceleration, direction_change, dist_from_route, dist_from_last = features

    # Layer 1: threshold checks
    if speed > 10:
        return True, "Vehicle speed detected", "threshold"
    if dist_from_last > 100:
        return True, "GPS jump detected", "threshold"
    if dist_from_route > 50:
        return True, "Runner off route", "threshold"

    # Layer 2: ML model
    X = pd.DataFrame([features], columns=FEATURES)
    pred = model.predict(X)[0]
    score = model.decision_function(X)[0]

    if pred == -1:
        reason = determine_reason(features)
        return True, reason, f"ML (score={score:+.4f})"
    return False, "", f"ML (score={score:+.4f})"


# ── Test cases ────────────────────────────────────────────────────────────────
# Format: (description, [speed, accel, dir_change, dist_route, dist_last], is_anomaly)

NORMAL_CASES = [
    ("Casual jogger 2.4 m/s",        [2.4,  0.08, 6.0,  2.0,  7.0],  False),
    ("Competitive runner 4.3 m/s",   [4.3,  0.12, 3.0,  1.0,  10.0], False),
    ("Interval runner fast phase",   [4.0,  0.18, 5.0,  2.0,  9.0],  False),
    ("Tired runner late race",       [2.0,  0.06, 9.0,  3.0,  6.0],  False),
    ("Crowded start slow pace",      [1.8,  0.15, 8.0,  1.5,  5.0],  False),
    ("Normal 3 m/s steady",         [3.0,  0.10, 5.0,  2.0,  8.0],  False),
    ("Slight direction wobble",      [3.2,  0.09, 12.0, 3.0,  8.5],  False),
    ("Slightly off route < 8m",     [2.9,  0.08, 4.0,  7.5,  8.0],  False),
]

ANOMALY_CASES = [
    # Threshold-caught
    ("Vehicle speed 25 m/s",         [25.0, 4.5,  160.0, 150.0, 400.0], True),
    ("Vehicle speed 15 m/s",         [15.0, 3.5,  100.0, 80.0,  200.0], True),
    ("Vehicle speed 12 m/s",         [12.0, 3.0,  90.0,  60.0,  180.0], True),
    ("GPS jump 200m step",           [3.0,  0.1,  5.0,   2.0,   200.0], True),
    ("GPS jump 150m step",           [2.8,  0.1,  5.0,   2.0,   150.0], True),
    ("Off route 100m",               [3.0,  0.1,  5.0,   100.0, 8.0],   True),
    ("Off route 80m",                [2.9,  0.1,  10.0,  80.0,  8.0],   True),
    # ML-caught
    ("Sudden acceleration spike",    [3.0,  4.8,  90.0,  2.0,   8.0],   True),
    ("Erratic movement",             [3.0,  0.5,  170.0, 5.0,   12.0],  True),
    ("Combined vehicle pattern",     [20.0, 3.0,  140.0, 90.0,  300.0], True),
    ("High speed + erratic",         [12.0, 4.0,  150.0, 70.0,  250.0], True),
    ("Acceleration + direction",     [3.5,  4.0,  130.0, 3.0,   9.0],   True),
]


# ── Run tests ─────────────────────────────────────────────────────────────────

def run_tests():
    print("=" * 65)
    print("  AndoTrack — Isolation Forest Accuracy Test  (Day 36)")
    print("=" * 65)
    print(f"  Model: {model_path}")
    print(f"  Full pipeline: determine_reason() + Isolation Forest")
    print()

    # Normal cases — check for false positives
    print("── Normal Cases (should NOT be flagged) ─────────────────────")
    fp = 0
    for name, vals, expected_anomaly in NORMAL_CASES:
        is_anomaly, reason, source = full_pipeline_predict(vals)
        ok = is_anomaly == expected_anomaly
        icon = "✅" if ok else "❌ FALSE POSITIVE"
        print(f"  {icon}  {name:<40} [{source}]")
        if not ok:
            fp += 1
    print()

    # Anomaly cases — check detection rate
    print("── Anomaly Cases (SHOULD be flagged) ────────────────────────")
    detected = 0
    for name, vals, expected_anomaly in ANOMALY_CASES:
        is_anomaly, reason, source = full_pipeline_predict(vals)
        ok = is_anomaly == expected_anomaly
        icon = "✅" if ok else "❌ MISSED"
        detail = f"  → {reason}" if is_anomaly else ""
        print(f"  {icon}  {name:<40} [{source}]{detail}")
        if ok:
            detected += 1
    print()

    # Results summary
    total_anomalies = len(ANOMALY_CASES)
    total_normals = len(NORMAL_CASES)
    detection_rate = detected / total_anomalies * 100
    fp_rate = fp / total_normals * 100

    print("=" * 65)
    print(f"  Detection rate:    {detected}/{total_anomalies} = {detection_rate:.0f}%"
          f"  {'✅ PASS' if detection_rate >= 80 else '❌ FAIL'} (threshold: 80%)")
    print(f"  False positives:   {fp}/{total_normals} = {fp_rate:.0f}%"
          f"  {'✅ GOOD' if fp_rate == 0 else '⚠️ REVIEW'}")
    print("=" * 65)
    print()

    # Architecture explanation
    print("  Pipeline architecture:")
    print("  ┌─────────────────────────────────────────────────────┐")
    print("  │  GPS update arrives                                  │")
    print("  │       ↓                                              │")
    print("  │  determine_reason() — threshold checks               │")
    print("  │  speed > 10, dist_from_last > 100, dist_route > 50  │")
    print("  │       ↓ (if not caught)                              │")
    print("  │  Isolation Forest — ML pattern detection             │")
    print("  │       ↓                                              │")
    print("  │  Anomaly saved to MySQL + pushed to Firebase         │")
    print("  └─────────────────────────────────────────────────────┘")
    print()

    if detection_rate >= 80:
        print("  ✅ Model meets the 80% detection threshold.")
    else:
        print("  ❌ Detection below 80%. Increase contamination in train_model.py")
        print("     and retrain: python ml/train_model.py")

    return detection_rate >= 80


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    passed = run_tests()
    sys.exit(0 if passed else 1)
