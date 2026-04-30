from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime
from database import Base
import datetime

class Anomaly(Base):
    __tablename__ = "anomalies"
    id = Column(Integer, primary_key=True, index=True)
    race_id = Column(Integer)
    runner_id = Column(Integer)
    detected_at = Column(DateTime, default=datetime.datetime.utcnow)
    reason = Column(String(255))
    score = Column(Float)
    lat = Column(Float)
    lng = Column(Float)
    resolved = Column(Boolean, default=False)