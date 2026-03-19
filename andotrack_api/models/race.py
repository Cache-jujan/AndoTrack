import datetime
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey
from database import Base

class Race(Base):
    __tablename__ = "races"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100))
    distance_km = Column(Float)
    status = Column(String(20), default="upcoming")

class RaceRunner(Base):
    __tablename__ = "race_runners"
    id = Column(Integer, primary_key=True, index=True)
    race_id = Column(Integer, ForeignKey("races.id"))
    runner_id = Column(Integer, ForeignKey("users.id"))
    registered_at = Column(DateTime ,default=datetime.datetime.utcnow)