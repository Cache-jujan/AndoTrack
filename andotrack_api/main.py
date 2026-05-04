from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from database import engine, Base

# ── Routers — all inside your `routes/` folder ────────────────────────────────
from routes.auth import router as auth_router
from routes.races import router as races_router
from routes.runners import router as runners_router
from routes.checkpoints import router as checkpoints_router
from routes.leaderboard import router as leaderboard_router
from routes.route_generator import router as route_router   # ← NEW

# ── Models (needed so Base.metadata.create_all sees them) ─────────────────────
import models.user
import models.race
import models.checkpoint
import models.anomaly
from models.result import RaceResult

# ── Firebase ───────────────────────────────────────────────────────────────────
import firebase

# ── ML anomaly model ───────────────────────────────────────────────────────────
import pickle

try:
    with open("ml/anomaly_model.pkl", "rb") as f:
        anomaly_model = pickle.load(f)
    print("✅ Isolation Forest model loaded")
except FileNotFoundError:
    anomaly_model = None
    print("⚠️  anomaly_model.pkl not found — run ml/train_model.py first")

# ── DB init ────────────────────────────────────────────────────────────────────
Base.metadata.create_all(bind=engine)

# ── App ────────────────────────────────────────────────────────────────────────
app = FastAPI(title="AndoTrack API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Route registration (each prefix appears ONCE) ──────────────────────────────
app.include_router(auth_router,        prefix="/auth",        tags=["Auth"])
app.include_router(races_router,       prefix="/races",       tags=["Races"])
app.include_router(runners_router,     prefix="/runners",     tags=["Runners"])
app.include_router(checkpoints_router, prefix="/checkpoints", tags=["Checkpoints"])
app.include_router(leaderboard_router, prefix="/leaderboard", tags=["Leaderboard"])
app.include_router(route_router,       prefix="/route",       tags=["Route Generation"]) 

# ── Health check ───────────────────────────────────────────────────────────────
@app.get("/")
def root():
    return {"message": "AndoTrack API is running"}

# ── WebSocket ──────────────────────────────────────────────────────────────────
@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            await websocket.send_text(f"Echo: {data}")
    except WebSocketDisconnect:
        print("Client disconnected")