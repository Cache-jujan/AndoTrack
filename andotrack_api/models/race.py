import datetime
from sqlalchemy import (
    Column, Integer, String, Float, DateTime,
    ForeignKey, Boolean, Text, Enum
)
from database import Base


class Race(Base):
    __tablename__ = "races"

    id              = Column(Integer, primary_key=True, index=True)
    name            = Column(String(100), nullable=False)
    distance_km     = Column(Float, nullable=False)
    category        = Column(String(20))            # e.g. "6K", "12K", "21K", "42K"
    status          = Column(
                        String(20),
                        default="upcoming"
                      )
    # status values:
    #   upcoming          → race created, registration not yet open
    #   registration_open → runners can register
    #   race_day          → event day, organizer can start
    #   active            → race is live / GPS tracking on
    #   finished          → race ended

    # New fields
    description         = Column(Text)
    location            = Column(String(255))
    sponsors            = Column(Text)              # JSON string: ["Brand A","Brand B"]
    max_participants    = Column(Integer)
    scheduled_start     = Column(DateTime)          # for countdown display
    registration_fee    = Column(Float, default=0.0)
    banner_url          = Column(String(500))       # optional poster/image URL

    created_at          = Column(DateTime, default=datetime.datetime.utcnow)


class RaceRunner(Base):
    __tablename__ = "race_runners"

    id              = Column(Integer, primary_key=True, index=True)
    race_id         = Column(Integer, ForeignKey("races.id"), nullable=False)
    runner_id       = Column(Integer, ForeignKey("users.id"), nullable=False)
    registered_at   = Column(DateTime, default=datetime.datetime.utcnow)

    # Registration form fields
    city                = Column(String(100))
    contact_number      = Column(String(30))
    is_first_marathon   = Column(Boolean, default=False)
    emergency_contact   = Column(String(100))       # "Name – Number"
    sex                 = Column(
                            Enum("male", "female", "prefer_not_to_say"),
                            default="prefer_not_to_say"
                          )

    # Check-in / QR
    qr_token        = Column(String(100), unique=True, index=True)
    is_present      = Column(Boolean, default=False)
    checked_in_at   = Column(DateTime, nullable=True)
    race_status     = Column(String(20), default="registered")  # registered → active → finished
    bib_number      = Column(Integer, nullable=True)
