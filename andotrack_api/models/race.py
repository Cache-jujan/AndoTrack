from sqlalchemy import Column, Integer, String, Float, DateTime
from database import Base

class Race(Base):
    __tablename__ = "races"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100))
    distance_km = Column(Float)
    status = Column(String(20), default="upcoming")