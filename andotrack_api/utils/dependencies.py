from fastapi import Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from utils.auth import decode_token
from jose import JWTError
from sqlalchemy.orm import Session
from database import get_db
from models.staff_assignment import StaffAssignment

security = HTTPBearer()

def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        payload = decode_token(credentials.credentials)
        return payload
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    

STAFF_ROLES = {"kit_staff", "checkin_staff"}

def get_staff_user(race_id: int, credentials: HTTPAuthorizationCredentials = Depends(security), db: Session = Depends(get_db)):
    try:
        payload = decode_token(credentials.credentials)
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    role = payload.get("role")

    # Organizers have full access — no assignment check needed
    if role == "organizer":
        return payload

    if role not in STAFF_ROLES:
        raise HTTPException(status_code=403, detail="Staff access required")

    user_id = int(payload.get("sub"))
    assignment = db.query(StaffAssignment).filter(
        StaffAssignment.user_id == user_id,
        StaffAssignment.race_id == race_id,
        StaffAssignment.is_active == True
    ).first()

    if not assignment:
        raise HTTPException(status_code=403, detail="You are not assigned to this race")

    return payload