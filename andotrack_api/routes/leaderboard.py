from fastapi import APIRouter
from firebase_admin import db

router = APIRouter()

@router.get("/{race_id}")
def get_leaderboard(race_id: int):

    ref = db.reference(f"races/{race_id}/runners")
    runners = ref.get()

    if not runners:
        return {"leaderboard": []}

    leaderboard = []

    for runner_id, data in runners.items():
        leaderboard.append({
            "runner_id": runner_id,
            "speed": data.get("speed", 0),
            "lat": data.get("lat"),
            "lng": data.get("lng"),
            "timestamp": data.get("timestamp")
        })

    leaderboard.sort(key=lambda x: x["speed"], reverse=True)

    return {"leaderboard": leaderboard}