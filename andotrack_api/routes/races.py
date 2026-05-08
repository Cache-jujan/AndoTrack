from models.result import RaceResult
from utils.pace import get_runner_pace_summary
from utils.distance_tracker import get_all_runners_distance
from utils.auth import hash_password
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
import datetime
import secrets
import string
from database import get_db
from models.race import Race, RaceRunner
from models.user import User
from models.checkpoint import Checkpoint, RunnerCheckpoint
from models.anomaly import Anomaly
from models.staff_assignment import StaffAssignment
from models.race_checkin_qr import RaceCheckinQR
from utils.dependencies import get_current_user
from utils.distance_tracker import get_distance
from utils.eta import calculate_eta
from utils.pace import get_pace_min_per_km, format_pace
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
    
    valid_shirt_sizes = {"XS", "S", "M", "L", "XL", "XXL"}
    if body.shirt_size not in valid_shirt_sizes:
        raise HTTPException(
            status_code=422,
            detail=f"shirt_size must be one of: {', '.join(sorted(valid_shirt_sizes))}"
        )

# Auto-assign bib_number
    max_bib = db.query(func.max(RaceRunner.bib_number)).filter(
        RaceRunner.race_id == race_id
    ).scalar()
    bib_number = (max_bib or 0) + 1

    # Generate QR token + image
    qr_token, qr_image_b64 = generate_registration_qr(race_id, runner_id)

    # Save registration
    registration = RaceRunner(
        race_id           = race_id,
        runner_id         = runner_id,
        city              = body.city,
        contact_number    = body.contact_number,
        is_first_marathon = body.is_first_marathon,
        emergency_contact = body.emergency_contact,
        sex               = body.sex,
        qr_token          = qr_token,
        shirt_size        = body.shirt_size,
        bib_number        = bib_number,
        is_present        = False,
    )
    db.add(registration)
    db.commit()
    db.refresh(registration)

    # Get runner name for the response
    runner = db.query(User).filter(User.id == runner_id).first()

    return RunnerRegistrationResponse(
        message         = "Registered successfully! Please save your QR code.",
        race_id         = race_id,
        runner_id       = runner_id,
        runner_name     = runner.name if runner else "Runner",
        race_name       = race.name,
        qr_token        = qr_token,
        qr_image_base64 = qr_image_b64,
        bib_number      = registration.bib_number,
        shirt_size      = registration.shirt_size,
    )

@router.delete("/{race_id}/register")
def unregister_from_race(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    runner_id = int(user["sub"])

    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    # Can't withdraw once race is active or finished
    if race.status in ("active", "finished"):
        raise HTTPException(
            status_code=400,
            detail="Cannot withdraw after race has started."
        )

    registration = db.query(RaceRunner).filter(
        RaceRunner.race_id == race_id,
        RaceRunner.runner_id == runner_id
    ).first()
    if not registration:
        raise HTTPException(status_code=404, detail="You are not registered for this race.")

    db.delete(registration)
    db.commit()

    return {"message": "Registration withdrawn successfully.", "race_id": race_id}

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
    now = datetime.datetime.now(datetime.timezone.utc)
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

@router.patch("/{race_id}/anomalies/{anomaly_id}/resolve")
def resolve_anomaly(
    race_id: int,
    anomaly_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can resolve anomalies.")

    anomaly = db.query(Anomaly).filter(
        Anomaly.id == anomaly_id,
        Anomaly.race_id == race_id
    ).first()
    if not anomaly:
        raise HTTPException(status_code=404, detail="Anomaly not found.")
    if anomaly.resolved:
        raise HTTPException(status_code=400, detail="Anomaly is already resolved.")

    anomaly.resolved = True
    db.commit()

    return {
        "message": "Anomaly resolved.",
        "anomaly_id": anomaly_id,
        "race_id": race_id,
    }

# ── Results-Finished Endpoints ─────────────────────────────────────────────────────────────────
# Endpoint for saving finished race in database

@router.post("/{race_id}/finish")
def finish_race(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Organizer finishes the race.
    - Sets race status to 'finished'
    - Snapshots the current leaderboard (from in-memory distance tracker)
      into the race_results table so rankings survive a server restart.
    - Returns the final saved standings.
    """
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can finish a race.")
    
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race is not found!")
    if race.status == "finished":
        raise HTTPException(status_code=400, detail="Race is already finished.")
    if race.status != "active":
        raise HTTPException(status_code=400, detail="Race must be active before it can be finished.")
    
    # Prevents duplicate when called multiple twice
    existing = db.query(RaceResult).filter(RaceResult.race_id == race_id).first()
    if existing:
        raise HTTPException(status_code=400, detail="Results are already saved for this race")
    

    standings = get_all_runners_distance(race_id)

    now = datetime.datetime.now(datetime.timezone.utc)
    saved = []

    for rank, entry in enumerate(standings, start=1):
        runner_id = int(entry["runner_id"])
        pace_data = get_runner_pace_summary(str(runner_id))
        
        result = RaceResult(
            race_id = race_id,
            runner_id = runner_id,
            rank = rank,
            distance_metres = entry["distance_metres"],
            distance_km = entry["distance_km"],
            pace_min_per_km = pace_data.get("pace_min_per_km"),
            pace_formatted = pace_data.get("pace_formatted"),
            finished_at = now,
        )
        db.add(result)

        #Look up runner name for the response
        runner = db.query(User).filter(User.id == runner_id).first()
        saved.append({
            "rank": rank,
            "runner_id": runner_id,
            "name": runner.name if runner else f"Runner #{runner_id}",
            "distance_metres": entry["distance_metres"],
            "distance_km": entry["distance_km"],
            "distance_formatted": entry["distance_formatted"],
            "pace_min_per_km": pace_data.get("pace_min_per_km"),
            "pace_formatted": pace_data.get("pace_formatted"),
            "finished_at": now.isoformat(),
        })
    race.status = "finished"
    db.commit()

    return{
        "message": f"Race '{race.name}' finished!. Results saved.",
        "race_id": race_id,
        "race_name": race.name,
        "total": len(saved),
        "results": saved,
    }


#Endpoint for fetching saved results of race

@router.get("/{race_id}/results")
def get_race_results(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Returns the persisted final results for a finished race.
    Used by final_results_screen.dart after race ends.
    Falls back to the live leaderboard if the race is still active.
    """
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")
    
    rows = (
        db.query(RaceResult)
        .filter(RaceResult.race_id == race_id)
        .order_by(RaceResult.rank)
        .all()
    )

    if not rows:
        raise HTTPException(
            status_code=404,
            detail="No results saved yet. Call Post /races/{race_id}/finish first."
        )
    
    results = []
    for row in rows:
        runner = db.query(User).filter(User.id == row.runner_id).first()
        results.append({
            "rank": row.rank,
            "runner_id": row.runner_id,
            "name": runner.name if runner else f"Runner #{row.runner_id}",
            "distance_metres": row.distance_metres,
            "distance_km": row.distance_km,
            "distance_formatted": (
                f"{row.distance_metres:.0f} m"
                if row.distance_metres < 1000
                else f"{row.distance_km:.2f} km"
            ),
            "pace_min_per_km": row.pace_min_per_km,
            "pace_formatted": row.pace_formatted or "-",
            "finished_at": row.finished_at.isoformat() if row.finished_at else None,
        })

    return {
        "race_id": race_id,
        "race_name": race.name,
        "status": race.status,
        "total": len(results),
        "results": results,
    }

#Runner Self-stats
@router.get("/{race_id}/runner/{runner_id}/stats")
def get_runner_stats(
    race_id: int,
    runner_id: int,
    db: Session = Depends(get_db)
):
    # 1. Check race exists
    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found")
 
    # 2. Check runner is registered in this race
    registration = db.query(RaceRunner).filter(
        RaceRunner.race_id == race_id,
        RaceRunner.runner_id == runner_id
    ).first()
    if not registration:
        raise HTTPException(status_code=404, detail="Runner not registered in this race")
 
    # 3. Distance — returns None if no GPS yet, we default to 0
    raw_distance = get_distance(race_id, runner_id)
    distance_km = round(raw_distance / 1000, 3) if raw_distance else 0.0
 
    # 4. Pace — returns None if no speed data yet
    pace_min = get_pace_min_per_km(str(runner_id))
    pace_formatted = format_pace(pace_min)
 
    # 5. ETA — only compute if we have pace and race has a set distance
    eta_wall_clock = None
    eta_seconds_remaining = None
    if pace_min and race.distance_km:
        remaining_km = max(race.distance_km - distance_km, 0)
        if remaining_km > 0:
            eta_seconds_remaining = int(pace_min * 60 * remaining_km)
            eta_wall_clock = calculate_eta(pace_min * 60, distance_km, race.distance_km)
        else:
            eta_seconds_remaining = 0
            eta_wall_clock = "Finished"
 
    # 6. Checkpoints — how many has this runner passed vs total in race
    total_checkpoints = db.query(Checkpoint).filter(
        Checkpoint.race_id == race_id
    ).count()
 
    passed_checkpoints = db.query(RunnerCheckpoint).join(
        Checkpoint, RunnerCheckpoint.checkpoint_id == Checkpoint.id
    ).filter(
        Checkpoint.race_id == race_id,
        RunnerCheckpoint.runner_id == runner_id
    ).count()
 
    # 7. Percentage complete
    percentage_complete = 0.0
    if race.distance_km and race.distance_km > 0:
        percentage_complete = round((distance_km / race.distance_km) * 100, 1)
        percentage_complete = min(percentage_complete, 100.0)
 
    # 8. Rank — compare this runner's distance against all others in the race
    rank = _calculate_rank(race_id, runner_id, distance_km)
 
    return {
        "runner_id": runner_id,
        "race_id": race_id,
        "bib_number": registration.bib_number,
        "race_status": registration.race_status,
        # Distance
        "distance_km": distance_km,
        "race_distance_km": race.distance_km,
        "percentage_complete": percentage_complete,
        # Pace
        "pace_seconds_per_km": pace_min * 60,
        "pace_formatted": pace_formatted,
        # ETA
        "eta_wall_clock": eta_wall_clock,
        "eta_seconds_remaining": eta_seconds_remaining,
        # Checkpoints
        "checkpoints_passed": passed_checkpoints,
        "checkpoints_total": total_checkpoints,
        # Rank
        "rank": rank,
    }
 
 
def _calculate_rank(race_id: int, runner_id: int, my_distance_km: float) -> int | None:
    """
    Pulls all distances from the in-memory distance_store and counts
    how many runners are ahead of this one. Returns 1 if leading.
    """
    try:
        from utils.distance_tracker import distance_store
 
        rank = 1
        for (r_id, u_id), dist_meters in distance_store.items():
            if r_id == race_id and u_id != runner_id:
                if (dist_meters / 1000) > my_distance_km:
                    rank += 1
        return rank
    except Exception:
        return None
    

# ── Staff Management ──────────────────────────────────────────────────────────

@router.post("/{race_id}/staff")
def create_staff(
    race_id: int,
    name: str,
    email: str,
    role: str,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    if user.get("role") not in ("organizer", "race_director"):
        raise HTTPException(status_code=403, detail="Only organizers can create staff.")

    if role not in ("kit_staff", "checkin_staff"):
        raise HTTPException(status_code=422, detail="role must be kit_staff or checkin_staff")

    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    # Generate temp password
    temp_pw = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(10))

    staff = User(
        name     = name,
        email    = email,
        password = hash_password(temp_pw),
        role     = role,
    )
    db.add(staff)
    db.commit()
    db.refresh(staff)

    assignment = StaffAssignment(user_id=staff.id, race_id=race_id)
    db.add(assignment)
    db.commit()

    return {
        "staff_id":     staff.id,
        "name":         staff.name,
        "email":        staff.email,
        "role":         staff.role,
        "temp_password": temp_pw,
        "race_id":      race_id,
    }


@router.get("/{race_id}/staff")
def get_staff(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    if user.get("role") not in ("organizer", "race_director", "checkin_staff", "kit_staff"):
        raise HTTPException(status_code=403, detail="Only organizers can view staff.")

    assignments = db.query(StaffAssignment).filter(
        StaffAssignment.race_id == race_id
    ).all()

    result = []
    for a in assignments:
        staff = db.query(User).filter(User.id == a.user_id).first()
        if staff:
            result.append({
                "staff_id":    staff.id,
                "name":        staff.name,
                "email":       staff.email,
                "role":        staff.role,
                "is_active":   a.is_active,
                "assigned_at": a.assigned_at,
            })
    return result


@router.patch("/{race_id}/staff/{staff_id}/deactivate")
def deactivate_staff(
    race_id: int,
    staff_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    if user.get("role") not in ("organizer", "race_director"):
        raise HTTPException(status_code=403, detail="Only organizers can deactivate staff.")

    assignment = db.query(StaffAssignment).filter(
        StaffAssignment.race_id == race_id,
        StaffAssignment.user_id == staff_id,
    ).first()

    if not assignment:
        raise HTTPException(status_code=404, detail="Staff assignment not found.")

    assignment.is_active = False
    db.commit()

    return {
        "message":  "Staff deactivated.",
        "staff_id": staff_id,
        "is_active": False,
    }


# ── Check-in QR (static, organizer/staff displays it) ────────────────────────

@router.get("/{race_id}/checkin-qr")
def get_checkin_qr(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    role = user.get("role")
    if role not in ("organizer", "kit_staff", "checkin_staff"):
        raise HTTPException(status_code=403, detail="Not authorized to view check-in QR.")

    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    # Return existing QR if already generated
    existing = db.query(RaceCheckinQR).filter(
        RaceCheckinQR.race_id == race_id
    ).first()

    if existing:
        qr_image_b64 = token_to_base64_png(existing.qr_payload)
        return {
            "race_id":        race_id,
            "qr_image_base64": qr_image_b64,
            "checkin_opens_at": race.scheduled_start,
        }

    # Generate and save new QR
    payload = f"andotrack://checkin/{race_id}"
    new_qr = RaceCheckinQR(race_id=race_id, qr_payload=payload)
    db.add(new_qr)
    db.commit()

    qr_image_b64 = token_to_base64_png(payload)

    return {
        "race_id":         race_id,
        "qr_image_base64": qr_image_b64,
        "checkin_opens_at": race.scheduled_start,
    }


# ── Runner Self Check-in (runner scans staff QR) ──────────────────────────────

@router.post("/{race_id}/checkin/self")
def self_checkin(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    runner_id = int(user["sub"])

    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    # Check window if scheduled_start is set
    if race.scheduled_start:
        now = datetime.datetime.now(datetime.timezone.utc)
        window_open  = race.scheduled_start - datetime.timedelta(hours=2)
        window_close = race.scheduled_start + datetime.timedelta(hours=1)
        if not (window_open <= now <= window_close):
            raise HTTPException(
                status_code=400,
                detail=f"Check-in is not open for this race."
            )

    registration = db.query(RaceRunner).filter(
        RaceRunner.race_id   == race_id,
        RaceRunner.runner_id == runner_id,
    ).first()

    if not registration:
        raise HTTPException(status_code=404, detail="You are not registered for this race.")

    if registration.is_present:
        raise HTTPException(status_code=400, detail="You are already checked in.")

    now = datetime.datetime.now(datetime.timezone.utc)
    registration.is_present    = True
    registration.checked_in_at = now
    registration.race_status   = "present"
    db.commit()

    runner = db.query(User).filter(User.id == runner_id).first()

    return CheckInResponse(
        message       = f"✓ {runner.name if runner else 'Runner'} checked in successfully!",
        runner_id     = runner_id,
        runner_name   = runner.name if runner else "Unknown",
        race_id       = race_id,
        checked_in_at = now,
    )


# ── Runner Status Manual Update ───────────────────────────────────────────────

@router.patch("/{race_id}/runners/{runner_id}/status")
def update_runner_status(
    race_id: int,
    runner_id: int,
    status: str,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can update runner status.")

    allowed_statuses = {"dnf", "dns", "racing"}
    if status not in allowed_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot manually set status to '{status}'. Allowed: dnf, dns, racing."
        )

    registration = db.query(RaceRunner).filter(
        RaceRunner.race_id   == race_id,
        RaceRunner.runner_id == runner_id,
    ).first()

    if not registration:
        raise HTTPException(status_code=404, detail="Runner not found in this race.")

    registration.race_status = status
    db.commit()

    return {
        "runner_id":   runner_id,
        "race_id":     race_id,
        "race_status": registration.race_status,
    }

# ── Payment Simulation ────────────────────────────────────────────────────────

@router.post("/{race_id}/pay")
def simulate_payment(
    race_id: int,
    db: Session = Depends(get_db),
    user=Depends(get_current_user),
):
    """
    Simulates payment confirmation for a registered runner.
    No real payment data — just confirms registration and returns bib + shirt info.
    """
    runner_id = int(user["sub"])

    race = db.query(Race).filter(Race.id == race_id).first()
    if not race:
        raise HTTPException(status_code=404, detail="Race not found.")

    registration = db.query(RaceRunner).filter(
        RaceRunner.race_id   == race_id,
        RaceRunner.runner_id == runner_id,
    ).first()

    if not registration:
        raise HTTPException(status_code=404, detail="You are not registered for this race.")

    # Ensure race_status is set to registered (payment confirmed)
    registration.race_status = "registered"
    db.commit()

    return {
        "message":    "Payment confirmed. You are registered!",
        "race_id":    race_id,
        "runner_id":  runner_id,
        "bib_number": registration.bib_number,
        "shirt_size": registration.shirt_size,
        "race_status": registration.race_status,
    }