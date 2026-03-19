import numpy as np
import pandas as pd

np.random.seed(42)

# Normal running data (3000 records)
normal = pd.DataFrame({
    'speed': np.random.normal(3.0, 0.5, 3000).clip(1.5, 5.0),
    'acceleration': np.random.normal(0.1, 0.05, 3000).clip(0, 0.5),
    'direction_change': np.random.normal(5, 3, 3000).clip(0, 20),
    'dist_from_route': np.random.normal(2, 1, 3000).clip(0, 8),
    'dist_from_last': np.random.normal(8, 2, 3000).clip(3, 15),
    'label': 0
})

# Anomaly data (150 records)
vehicle_speed = np.random.uniform(12, 30, 50)
gps_jump = np.random.uniform(0, 0.3, 50)
too_fast = np.random.uniform(5, 8, 50)
all_speeds = np.concatenate([vehicle_speed, gps_jump, too_fast])

anomalies = pd.DataFrame({
    'speed': all_speeds,
    'acceleration': np.random.uniform(1.5, 5.0, 150),
    'direction_change': np.random.uniform(80, 180, 150),
    'dist_from_route': np.random.uniform(30, 200, 150),
    'dist_from_last': np.random.uniform(50, 500, 150),
    'label': 1
})

df = pd.concat([normal, anomalies], ignore_index=True).sample(frac=1).reset_index(drop=True)
df.to_csv('ml/training_data.csv', index=False)
print(f"✅ Generated {len(df)} records → training_data.csv")
print(f"   Normal records: {len(df[df.label==0])}")
print(f"   Anomaly records: {len(df[df.label==1])}")
