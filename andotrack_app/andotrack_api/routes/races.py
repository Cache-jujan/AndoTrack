from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
import datetime

from database import get_db
from models.race import Race, RaceRunner
from models.user import User
from models.anomaly import Anomaly
from utils.dependencies import get_current_user
from schemas.race import (
    RaceCreate,
    RaceResponse,
    RunnerRegistrationRequest,
    RunnerRegistrationResponse,
    CheckInRequest,
    CheckInResponse,
)
from utils.qr_generator import generate_registration_qr

router = APIRouter()


# ── Helper ────────────────────────────────────────────────────────────────────

def _race_to_response(race: Race, db: Session) -> RaceResponse:
    """Attach computed fields (participant_count, slots_remaining) to a race."""
    count = db.query(func.count(RaceRunner.id)).filter(
        RaceRunner.race_id == race.id
    ).scalar() or 0

    slots = (
        (race.max_participants - count)
        if race.max_participants
        else None
    )

    data = RaceResponse.model_validate(race)
    data.participant_count = count
    data.slots_remaining   = slots
    return data


# ── Race CRUD ─────────────────────────────────────────────────────────────────

@router.get("/", response_model=list[RaceResponse])
def get_races(
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Return all races.
    Runners see this as their race browser.
    Organizers see it as their race management list.
    """
    races = db.query(Race).order_by(Race.scheduled_start.asc()).all()
    return [_race_to_response(r, db) for r in races]


@router.get("/{race_id}", response_model=RaceResponse)
def get_race(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """Single race detail — used by race_detail_screen.dart."""
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")
    return _race_to_response(race, db)


@router.post("/", response_model=RaceResponse)
def create_race(
    body: RaceCreate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Organizer creates a race with all fields.
    After creation the organizer is taken directly to the race dashboard.
    """
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can create races.")

    race = Race(
        name             = body.name,
        distance_km      = body.distance_km,
        category         = body.category,
        description      = body.description,
        location         = body.location,
        sponsors         = body.sponsors,
        max_participants = body.max_participants,
        scheduled_start  = body.scheduled_start,
        registration_fee = body.registration_fee or 0.0,
        banner_url       = body.banner_url,
        status           = body.status or "upcoming",
    )
    db.add(race)
    db.commit()
    db.refresh(race)
    return _race_to_response(race, db)


@router.put("/{race_id}", response_model=RaceResponse)
def update_race(
    race_id: int,
    body: RaceCreate,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """Organizer edits an existing race."""
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can edit races.")

    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(race, field, value)

    db.commit()
    db.refresh(race)
    return _race_to_response(race, db)


# ── Race lifecycle ────────────────────────────────────────────────────────────

@router.post("/{race_id}/start")
def start_race(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")
    if race.status == "finished":
        raise HTTPException(status_code=400, detail="Race is already finished.")

    race.status = "active"
    db.commit()
    db.refresh(race)
    return {"message": f"Race '{race.name}' has started!", "status": race.status}


@router.post("/{race_id}/stop")
def stop_race(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")
    if race.status == "finished":
        raise HTTPException(status_code=400, detail="Race is already finished.")

    race.status = "finished"
    db.commit()
    db.refresh(race)
    return {"message": f"Race '{race.name}' has finished!", "status": race.status}


# ── Runner registration ───────────────────────────────────────────────────────

@router.post("/{race_id}/register", response_model=RunnerRegistrationResponse)
def register_for_race(
    race_id: int,
    body: RunnerRegistrationRequest,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Runner fills out the registration form and gets a QR code back.
    The QR code is a base64 PNG — Flutter renders it with Image.memory().
    """
    runner_id = int(user["sub"])

    # Race must exist
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    # Race must be open
    if race.status not in ("upcoming", "registration_open", "race_day"):
        raise HTTPException(
            status_code=400,
            detail=f"Registration is closed. Race status: {race.status}."
        )

    # Check max participants
    if race.max_participants:
        count = db.query(func.count(RaceRunner.id)).filter(
            RaceRunner.race_id == race_id
        ).scalar() or 0
        if count >= race.max_participants:
            raise HTTPException(status_code=400, detail="Race is full.")

    # No double registration
    existing = db.query(RaceRunner).filter(
        RaceRunner.race_id  == race_id,
        RaceRunner.runner_id == runner_id,
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="You are already registered for this race.")

    # Validate sex value
    valid_sex = {"male", "female", "prefer_not_to_say"}
    if body.sex not in valid_sex:
        raise HTTPException(
            status_code=422,
            detail=f"sex must be one of: {', '.join(valid_sex)}"
        )

    # Generate QR token + image
    qr_token, qr_image_b64 = generate_registration_qr(race_id, runner_id)

    # Save registration
    registration = RaceRunner(
        race_id            = race_id,
        runner_id          = runner_id,
        city               = body.city,
        contact_number     = body.contact_number,
        is_first_marathon  = body.is_first_marathon,
        emergency_contact  = body.emergency_contact,
        sex                = body.sex,
        qr_token           = qr_token,
        is_present         = False,
    )
    db.add(registration)
    db.commit()
    db.refresh(registration)

    # Get runner name for the response
    runner = db.query(User).filter(User.id == runner_id).first()

    return RunnerRegistrationResponse(
        message          = "Registered successfully! Please save your QR code.",
        race_id          = race_id,
        runner_id        = runner_id,
        runner_name      = runner.name if runner else "Runner",
        race_name        = race.name,
        qr_token         = qr_token,
        qr_image_base64  = qr_image_b64,
    )


# ── QR check-in (organizer scans runner QR) ───────────────────────────────────

@router.post("/{race_id}/checkin", response_model=CheckInResponse)
def checkin_runner(
    race_id: int,
    body: CheckInRequest,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Organizer scans a runner's QR code.
    Marks the runner as present and records check-in time.
    """
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can check in runners.")

    # Look up the registration by QR token
    registration = db.query(RaceRunner).filter(
        RaceRunner.qr_token == body.qr_token,
        RaceRunner.race_id  == race_id,
    ).first()

    if not registration:
        raise HTTPException(
            status_code=404,
            detail="QR code not recognised for this race. Check that the runner registered for this specific race."
        )

    if registration.is_present:
        runner = db.query(User).filter(User.id == registration.runner_id).first()
        raise HTTPException(
            status_code=400,
            detail=f"{runner.name if runner else 'Runner'} is already checked in."
        )

    # Mark present
    now = datetime.datetime.utcnow()
    registration.is_present    = True
    registration.checked_in_at = now
    db.commit()

    runner = db.query(User).filter(User.id == registration.runner_id).first()

    return CheckInResponse(
        message        = f"✓ {runner.name if runner else 'Runner'} checked in successfully!",
        runner_id      = registration.runner_id,
        runner_name    = runner.name if runner else "Unknown",
        race_id        = race_id,
        checked_in_at  = now,
    )


# ── Participant list (organizer view) ─────────────────────────────────────────

@router.get("/{race_id}/runners")
def get_race_runners(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Returns all registered runners with their registration details
    and present/absent status. Used in organizer_race_dashboard.
    """
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    race_runners = db.query(RaceRunner).filter(RaceRunner.race_id == race_id).all()

    result = []
    for rr in race_runners:
        runner = db.query(User).filter(User.id == rr.runner_id).first()
        if runner:
            result.append({
                "user_id":           runner.id,
                "name":              runner.name,
                "email":             runner.email,
                "role":              runner.role,
                "registered_at":     rr.registered_at,
                "city":              rr.city,
                "contact_number":    rr.contact_number,
                "is_first_marathon": rr.is_first_marathon,
                "emergency_contact": rr.emergency_contact,
                "sex":               rr.sex,
                "is_present":        rr.is_present,
                "checked_in_at":     rr.checked_in_at,
            })

    return result


# ── Anomalies ─────────────────────────────────────────────────────────────────

@router.get("/{race_id}/anomalies")
def get_anomalies(
    race_id: int,
    runner_id: int = None,
    resolved: bool = None,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    query = db.query(Anomaly).filter(Anomaly.race_id == race_id)
    if runner_id:
        query = query.filter(Anomaly.runner_id == runner_id)
    if resolved is not None:
        query = query.filter(Anomaly.resolved == resolved)
    return query.all()