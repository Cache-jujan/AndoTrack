import numpy as np
import pandas as pd

np.random.seed(42)

# Normal running data (3000 records)
normal = pd.DataFrame({
    'speed': np.random.normal(3.0, 0.5, 3000).clip(1.5, 5.0),       # 1.5–5 m/s normal running
    'acceleration': np.random.normal(0.1, 0.05, 3000).clip(0, 0.5),  # small acceleration changes
    'direction_change': np.random.normal(5, 3, 3000).clip(0, 20),     # degrees
    'dist_from_route': np.random.normal(2, 1, 3000).clip(0, 8),       # meters off route
    'dist_from_last': np.random.normal(8, 2, 3000).clip(3, 15),       # meters moved per update
    'label': 0  # 0 = normal
})

# Anomaly data (150 records — vehicle use, GPS jump, off-route)
anomalies = pd.DataFrame({
    'speed': np.random.choice([
        np.random.uniform(12, 30, 50),   # vehicle speed
        np.random.uniform(0, 0.3, 50),   # stopped (GPS jump)
        np.random.uniform(5, 8, 50),     # too fast for running
    ], replace=False).flatten(),
    'acceleration': np.random.uniform(1.5, 5.0, 150),
    'direction_change': np.random.uniform(80, 180, 150),
    'dist_from_route': np.random.uniform(30, 200, 150),
    'dist_from_last': np.random.uniform(50, 500, 150),
    'label': 1  # 1 = anomaly
})

df = pd.concat([normal, anomalies], ignore_index=True).sample(frac=1).reset_index(drop=True)
df.to_csv('ml/training_data.csv', index=False)
print(f"✅ Generated {len(df)} records → training_data.csv")