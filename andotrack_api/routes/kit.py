import datetime
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from database import get_db
from models.race import RaceRunner
from models.user import User
from utils.dependencies import get_staff_user, security
from jose import JWTError

router = APIRouter()

# ── shared staff auth helper ──────────────────────────────
def _require_staff(race_id: int, credentials: HTTPAuthorizationCredentials, db: Session):
    return get_staff_user(race_id=race_id, credentials=credentials, db=db)

# ── GET /kit/{race_id}/runners ────────────────────────────

@router.get("/{race_id}/runners")
def get_kit_runners(
    race_id: int,
    status: str = "unclaimed",
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    user = _require_staff(race_id, credentials, db)
    query = db.query(RaceRunner).filter(RaceRunner.race_id == race_id)

    if status == "unclaimed":
        query = query.filter(RaceRunner.claimed == False)
    elif status == "claimed":
        query = query.filter(RaceRunner.claimed == True)
    # "all" returns everything

    runners = query.all()
    result = []
    for rr in runners:
        runner = db.query(User).filter(User.id == rr.runner_id).first()
        result.append({
            "runner_id":      rr.runner_id,
            "name":           runner.name if runner else "Unknown",
            "bib_number":     rr.bib_number,
            "shirt_size":     rr.shirt_size,
            "claimed":        rr.claimed,
            "claimed_at":     rr.claimed_at,
            "contact_number": rr.contact_number,
        })
    return result


# ── PATCH /kit/{race_id}/runners/{runner_id}/claim ────────

@router.patch("/{race_id}/runners/{runner_id}/claim")
def claim_kit(
    race_id: int,
    runner_id: int,
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    user = _require_staff(race_id, credentials, db)
    rr = db.query(RaceRunner).filter(
        RaceRunner.race_id == race_id,
        RaceRunner.runner_id == runner_id
    ).first()

    if not rr:
        raise HTTPException(status_code=404, detail="Runner not found in this race")
    if rr.claimed:
        raise HTTPException(status_code=400, detail="Kit already claimed for this runner")

    rr.claimed    = True
    rr.claimed_at = datetime.datetime.now(datetime.timezone.utc)
    db.commit()

    return {
        "runner_id":  runner_id,
        "bib_number": rr.bib_number,
        "claimed":    rr.claimed,
        "claimed_at": rr.claimed_at,
    }


# ── POST /kit/{race_id}/walkin ────────────────────────────

@router.post("/{race_id}/walkin")
def walkin_assign(
    race_id: int,
    name: str,
    contact_number: str,
    db: Session = Depends(get_db),
    credentials: HTTPAuthorizationCredentials = Depends(security),
):
    user = _require_staff(race_id, credentials, db)
    # Find lowest unclaimed non-walkin bib
    available = db.query(RaceRunner).filter(
        RaceRunner.race_id   == race_id,
        RaceRunner.claimed   == False,
        RaceRunner.is_walkin == False,
        RaceRunner.race_status == "registered"
    ).order_by(RaceRunner.bib_number.asc()).first()

    if not available:
        raise HTTPException(status_code=400, detail="No bibs available for walk-in")

    available.is_walkin      = True
    available.walkin_name    = name
    available.walkin_contact = contact_number
    available.claimed        = True
    available.claimed_at     = datetime.datetime.now(datetime.timezone.utc)
    db.commit()

    return {
        "bib_number":     available.bib_number,
        "walkin_name":    available.walkin_name,
        "walkin_contact": available.walkin_contact,
        "claimed":        available.claimed,
        "claimed_at":     available.claimed_at,
    }