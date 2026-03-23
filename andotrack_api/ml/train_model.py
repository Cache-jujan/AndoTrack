import pandas as pd
from sklearn.ensemble import IsolationForest
import pickle
import os

df = pd.read_csv('ml/training_data.csv')
features = ['speed', 'acceleration', 'direction_change', 'dist_from_route', 'dist_from_last']
X = df[features]

model = IsolationForest(
    n_estimators=100,
    contamination=0.05,  # ~5% of data expected to be anomalies
    random_state=42
)
model.fit(X)

os.makedirs('ml', exist_ok=True)
with open('ml/anomaly_model.pkl', 'wb') as f:
    pickle.dump(model, f)

print("✅ Isolation Forest trained and saved → anomaly_model.pkl")