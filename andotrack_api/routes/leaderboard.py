# andotrack_api/routes/leaderboard.py

from fastapi import APIRouter, HTTPException
import firebase_admin.db as firebase_db

router = APIRouter()

@router.get("/leaderboard/{race_id}")
def get_leaderboard(race_id: int):
    try:
        ref = firebase_db.reference(f"/races/{race_id}/runners")
        runners_data = ref.get()
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Leaderboard temporarily unavailable: {str(e)}"
        )

    if not runners_data:
        return {"leaderboard": []}

    leaderboard = []
    for runner_id, data in runners_data.items():
        leaderboard.append({
            "runner_id": runner_id,
            "speed": data.get("speed", 0),
            # add other fields your app expects
        })

    # Sort by speed descending
    leaderboard.sort(key=lambda x: x["speed"], reverse=True)
    return {"leaderboard": leaderboard}