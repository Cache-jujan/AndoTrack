from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from database import get_db
from models.race import Race, RaceRunner
from models.user import User
from utils.dependencies import get_current_user
from pydantic import BaseModel

router = APIRouter()

class RaceRequest(BaseModel):
    name: str
    distance_km: float

@router.get("/")
def get_races(db: Session = Depends(get_db), user = Depends(get_current_user)):
    races = db.query(Race).all()
    return races

@router.post("/")
def create_race (body: RaceRequest, db:Session = Depends(get_db), user = Depends(get_current_user)):
    race = Race(
        name=body.name,
        distance_km=body.distance_km,
        status="upcoming"
    )
    db.add(race)
    db.commit()
    db.refresh(race)
    return race

@router.get("/{race_id}/runners")
def get_race_runners(race_id: int, db:Session = Depends(get_db), user = Depends(get_current_user)):
    #Check race exists
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found")
    
    race_runners = db.query(RaceRunner).filter(RaceRunner.race_id == race_id).all()

    result= []
    for rr in race_runners:
        runner = db.query(User).filter(User.id == rr.runner_id).first()
        if runner:
            result.append({
                "user_id": runner.id,
                "name": runner.name,
                "email": runner.email,
                "role": runner.role,
                "registered_at": rr.registered_at
            })
        
    return result

@router.post("/{race_id}/start")
def start_race(race_id: int, db: Session = Depends(get_db), user = Depends (get_current_user)):
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail = "Race not found")
    if race.status == "finished":
        raise HTTPException(status_code=400, detail = "Race is already in progress")
    
    race.status = "active"
    db.commit()
    db.refresh(race)
    return {"message": f"Race '{race.name}' has started!", "status": race.status}

@router.post("/{race_id}/stop")
def stop_race(race_id: int, db: Session = Depends(get_db), user = Depends (get_current_user)):
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail = "Race not found")
    if race.status == "finished":
        raise HTTPException(status_code=400, detail = "Race is already finished!")
    
    race.status = "finished"
    db.commit()
    db.refresh(race)
    return {"message": f"Race '{race.name}' has finished!", "status": race.status}

@router.get("/{race_id}/anomalies")
def get_anomalies(
    race_id: int,
    runner_id: int = None,
    resolved: bool = None,
    db: Session = Depends(get_db),
    user = Depends(get_current_user)
):
    from models.anomaly import Anomaly

    query = db.query(Anomaly).filter(Anomaly.race_id == race_id)

    if runner_id:
        query = query.filter(Anomaly.runner_id == runner_id)
    if resolved is not None:
        query = query.filter(Anomaly.resolved == resolved)

    return query.all()