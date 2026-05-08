import datetime
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from database import Base

class RaceResult(Base):
    __tablename__ = "race_results"

    id = Column(Integer, primary_key=True, index=True)
    race_id = Column(Integer, ForeignKey("races.id"), nullable=False)
    runner_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    rank = Column(Integer, nullable=False)
    distance_metres = Column(Float, default=0.0)
    distance_km = Column(Float, default=0.0)
    pace_min_per_km = Column(Float, nullable=True) #None if runner never moved
    pace_formatted = Column(String(20), nullable=True) #for final pace eg. "5:42/km"
    finished_at = Column(DateTime(timezone=True), default=lambda: datetime.datetime.now(datetime.timezone.utc))