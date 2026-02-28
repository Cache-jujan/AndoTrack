from fastapi import APIRouter
router = APIRouter()

@router.get("/")
def get_runners():
    return {"message": "get runners — coming soon"}

@router.post("/{runner_id}/location")
def update_location(runner_id: int):
    return {"message": f"location update for runner {runner_id} — coming soon"}