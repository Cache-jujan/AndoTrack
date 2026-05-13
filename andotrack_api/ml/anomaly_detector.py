def determine_reason(features: list[float]) -> str:
    speed, acceleration, direction_change, dist_from_route, dist_from_last = features

    if speed > 4.5:
        return "vehicle_speed"
    if dist_from_last > 200:
        return "gps_jump"
    # ML flagged something we don't act on → suppress
    return ""

def run_anomaly_detection(model, features: list[float]) -> tuple[bool, str, float]:
    """
    Returns (is_anomaly, reason, score).
    The ML model (IsolationForest) gates detection; determine_reason() maps the
    flagged feature vector to an actionable label.  If the reason is empty the
    anomaly is suppressed — is_anomaly is returned as False so the caller skips
    saving/pushing.
    """
    import numpy as np
    X = np.array(features).reshape(1, -1)
    prediction = model.predict(X)[0]   # -1 = anomaly, 1 = normal
    score = model.decision_function(X)[0]

    is_anomaly = prediction == -1
    reason = determine_reason(features) if is_anomaly else ""

    # Suppress if ML fired but no actionable reason matched
    return (is_anomaly and reason != ""), reason, float(score)