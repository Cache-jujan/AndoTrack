from fastapi import APIRouter
router = APIRouter()

@router.get("/{race_id}")
def get_leaderboard(race_id: int):
    return {"message": f"leaderboard for race {race_id} — coming soon"}