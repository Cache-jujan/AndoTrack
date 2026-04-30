# The GPS jump / off-route cases fail because the model sees them in isolation.
# In real usage, determine_reason() catches these with threshold checks BEFORE
# the ML model. The ML model is the last line of defence for patterns it has 
# been trained on. Let's verify what the actual scores are for those edge cases.

import pandas as pd
from sklearn.ensemble import IsolationForest
import pickle
import numpy as np
import os

np.random.seed(42)

# Normal running data
normal = pd.DataFrame({
    'speed': np.random.normal(3.0, 0.5, 3000).clip(1.5, 5.0),
    'acceleration': np.random.normal(0.1, 0.05, 3000).clip(0, 0.5),
    'direction_change': np.random.normal(5, 3, 3000).clip(0, 20),
    'dist_from_route': np.random.normal(2, 1, 3000).clip(0, 8),
    'dist_from_last': np.random.normal(8, 2, 3000).clip(3, 15),
    'label': 0
})

n = 300
anomalies = pd.DataFrame({
    'speed': np.concatenate([
        np.random.uniform(12, 30, 100),
        np.random.uniform(0, 0.5, 100),
        np.random.uniform(5, 8, 100),
    ]),
    'acceleration': np.random.uniform(1.5, 5.0, n),
    'direction_change': np.random.uniform(80, 180, n),
    'dist_from_route': np.random.uniform(30, 200, n),
    'dist_from_last': np.random.uniform(50, 500, n),
    'label': 1
})

df = pd.concat([normal, anomalies], ignore_index=True).sample(frac=1).reset_index(drop=True)
features = ["speed", "acceleration", "direction_change", "dist_from_route", "dist_from_last"]
X = df[features]
contamination = len(df[df.label==1]) / len(df)

model = IsolationForest(n_estimators=200, contamination=contamination, random_state=42, n_jobs=-1)
model.fit(X)

BASE_DIR = os.path.dirname(__file__)
model_path = os.path.join(BASE_DIR, "anomaly_model.pkl")

os.makedirs(BASE_DIR, exist_ok=True)
with open(model_path, "wb") as f:
    pickle.dump(model, f)
print(f"✅ Model saved → {model_path}  ({os.path.getsize(model_path)/1024:.0f} KB)")
print(f"   contamination={contamination:.3f}  |  {len(df)} training records")

# Full test including score (negative score = more anomalous)
def score(vals):
    s = pd.DataFrame([vals], columns=features)
    pred = model.predict(s)[0]
    sc = model.decision_function(s)[0]
    return pred, round(sc, 4)

tests = [
    ("Normal runner 3 m/s",           [3.0,  0.1,  5.0,   2.0,   8.0],    1),
    ("Normal runner 4 m/s",           [4.0,  0.08, 3.0,   1.5,   9.0],    1),
    ("Slow walker 1.5 m/s",           [1.5,  0.05, 3.0,   1.0,   6.0],    1),
    ("Vehicle speed 25 m/s",          [25.0, 4.5,  160.0, 150.0, 400.0],  -1),
    ("Vehicle speed 15 m/s",          [15.0, 3.5,  100.0, 80.0,  200.0],  -1),
    ("GPS jump 200m",                 [3.0,  0.1,  5.0,   2.0,   200.0],  -1),
    ("Off route 100m",                [3.0,  0.1,  5.0,   100.0, 8.0],    -1),
    ("Sudden acceleration",           [3.0,  4.8,  90.0,  2.0,   8.0],    -1),
    ("Erratic movement",              [3.0,  0.5,  170.0, 5.0,   12.0],   -1),
]

print(f"\n🧪 Sanity checks  (score: negative = anomalous, positive = normal):")
passed = 0
for name, vals, expected in tests:
    pred, sc = score(vals)
    ok = pred == expected
    icon = "✅" if ok else "❌"
    tag = "Normal" if expected==1 else "Anomaly"
    got = "Normal" if pred==1 else "Anomaly"
    note = "" if ok else f"  ← got {got}"
    print(f"   {icon}  {name:<38} [{tag}]  score={sc:+.4f}{note}")
    if ok: passed += 1

print(f"\n   {passed}/{len(tests)} checks passed")
print(f"\n   NOTE: GPS jump & off-route are caught by determine_reason()")
print(f"   thresholds BEFORE the ML model runs. The ML model focuses on")
print(f"   patterns that combine multiple features simultaneously.")
