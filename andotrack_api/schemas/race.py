from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


# ── Race schemas ──────────────────────────────────────────────────────────────

class RaceCreate(BaseModel):
    """Used by organizer to create a race — all new fields included."""
    name                : str
    distance_km         : float
    category            : Optional[str] = None          # "6K", "12K", "21K", "42K"
    description         : Optional[str] = None
    location            : Optional[str] = None
    sponsors            : Optional[str] = None          # JSON string or comma-sep
    max_participants    : Optional[int] = None
    scheduled_start     : Optional[datetime] = None     # ISO 8601 datetime
    registration_fee    : Optional[float] = 0.0
    banner_url          : Optional[str] = None
    status              : Optional[str] = "upcoming"


class RaceResponse(BaseModel):
    """Returned when listing or fetching a race."""
    id                  : int
    name                : str
    distance_km         : float
    category            : Optional[str]
    status              : str
    description         : Optional[str]
    location            : Optional[str]
    sponsors            : Optional[str]
    max_participants    : Optional[int]
    scheduled_start     : Optional[datetime]
    registration_fee    : Optional[float]
    banner_url          : Optional[str]
    created_at          : Optional[datetime]

    # Derived — computed in the endpoint, not stored directly
    participant_count   : Optional[int] = None
    slots_remaining     : Optional[int] = None

    class Config:
        from_attributes = True


# ── Registration schemas ──────────────────────────────────────────────────────

class RunnerRegistrationRequest(BaseModel):
    """Form the runner fills out when registering for a race."""
    city                : str   = Field(..., example="Cebu City")
    email               : str   = Field(..., example="runner@email.com")
    contact_number      : str   = Field(..., example="09171234567")
    is_first_marathon   : bool  = Field(False)
    emergency_contact   : str   = Field(..., example="Juan Dela Cruz – 09179999999")
    sex                 : str   = Field(..., example="male")   # male | female | prefer_not_to_say


class RunnerRegistrationResponse(BaseModel):
    """Returned after successful registration — includes QR data."""
    message             : str
    race_id             : int
    runner_id           : int
    runner_name         : str
    race_name           : str
    qr_token            : str
    qr_image_base64     : str   # base64-encoded PNG — Flutter renders this directly


# ── Check-in schemas ──────────────────────────────────────────────────────────

class CheckInRequest(BaseModel):
    """Organizer submits the scanned QR token."""
    qr_token: str


class CheckInResponse(BaseModel):
    message         : str
    runner_id       : int
    runner_name     : str
    race_id         : int
    checked_in_at   : datetime