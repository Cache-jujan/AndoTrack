from dotenv import load_dotenv
load_dotenv()
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from database import engine, Base
from routes import auth, races, runners, checkpoints, leaderboard

import firebase 
import models.user
import models.race
import models.checkpoint
import models.anomaly

Base.metadata.create_all(bind=engine)

app = FastAPI(title="AndoTrack API")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(races.router, prefix="/races", tags=["Races"])
app.include_router(runners.router, prefix="/runners", tags=["Runners"])
app.include_router(checkpoints.router, prefix="/checkpoints", tags=["Checkpoints"])
app.include_router(leaderboard.router, prefix="/leaderboard", tags=["Leaderboard"])

@app.get("/")
def root():
    return {"message": "AndoTrack API is running"}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            await websocket.send_text(f"Echo: {data}")
    except WebSocketDisconnect:
        print("Client disconnected")