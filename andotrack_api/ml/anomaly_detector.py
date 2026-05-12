def determine_reason(features: list[float]) -> str:
    speed, acceleration, direction_change, dist_from_route, dist_from_last = features

    if speed > 4.5:
        return "Vehicle speed detected"
    if dist_from_last > 200:
        return "GPS jump detected"
    if dist_from_route > 50:
        return "Runner off route"
    if acceleration > 3:
        return "Sudden speed spike"
    if direction_change > 120:
        return "Erratic movement detected"
    return "Unusual pattern detected"

def run_anomaly_detection(model, features: list[float]) -> tuple[bool, str, float]:
    """
    Returns (is_anomaly, reason, score)
    """
    import numpy as np
    X = np.array(features).reshape(1, -1)
    prediction = model.predict(X)[0]   # -1 = anomaly, 1 = normal
    score = model.decision_function(X)[0]

    is_anomaly = prediction == -1
    reason = determine_reason(features) if is_anomaly else ""

    return is_anomaly, reason, float(score)