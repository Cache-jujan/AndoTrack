from sqlalchemy.orm import Session
from models.anomaly import Anomaly
from firebase_admin import db as firebase_db

def save_and_push_anomaly(
    db: Session,
    runner_id: int,
    race_id: int,
    reason: str,
    score: float,
    lat: float,
    lng: float
):
    # Save to MySQL
    anomaly = Anomaly(
        runner_id=runner_id,
        race_id=race_id,
        reason=reason,
        score=score,
        lat=lat,
        lng=lng
    )
    db.add(anomaly)
    db.commit()

    # Push to Firebase so organizer sees it instantly
    try:
        firebase_db.reference(f"races/{race_id}/anomalies/{runner_id}").set({
            "reason": reason,
            "score": score,
            "lat": lat,
            "lng": lng,
            "resolved": False
        })
    except Exception as e:
        print(f"FIREBASE ERROR: {e}")