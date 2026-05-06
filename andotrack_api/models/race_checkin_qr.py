import datetime
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from database import Base


class RaceCheckinQR(Base):
    __tablename__ = "race_checkin_qr"

    id          = Column(Integer, primary_key=True, index=True)
    race_id     = Column(Integer, ForeignKey("races.id"), nullable=False, unique=True)
    qr_payload  = Column(String(255), nullable=False)
    created_at  = Column(DateTime, default=datetime.datetime.utcnow)