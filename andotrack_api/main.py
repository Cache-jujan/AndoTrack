from fastapi import FastAPI
from database import engine, Base
from routes import auth, races, runners, checkpoints, leaderboard

import models.user
import models.race
import models.checkpoint
import models.anomaly

Base.metadata.create_all(bind=engine)

app = FastAPI(title="AndoTrack API")

app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(races.router, prefix="/races", tags=["Races"])
app.include_router(runners.router, prefix="/runners", tags=["Runners"])
app.include_router(checkpoints.router, prefix="/checkpoints", tags=["Checkpoints"])
app.include_router(leaderboard.router, prefix="/leaderboard", tags=["Leaderboard"])

@app.get("/")
def root():
    return {"message": "AndoTrack API is running"}