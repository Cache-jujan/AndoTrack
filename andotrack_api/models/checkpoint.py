from sqlalchemy import Column, Integer, String, Float, UniqueConstraint
from database import Base

class Checkpoint(Base):
    __tablename__ = "checkpoints"
    id = Column(Integer, primary_key=True, index=True)
    race_id = Column(Integer)
    name = Column(String(100))
    lat = Column(Float)
    lng = Column(Float)
    radius_meters = Column(Integer, default=20)
    order_number = Column(Integer)

class RunnerCheckpoint(Base):
    __tablename__ = "runner_checkpoints"
    id = Column(Integer, primary_key=True, index=True)
    runner_id = Column(Integer)
    checkpoint_id = Column(Integer)
    __table_args__ = (UniqueConstraint("runner_id", "checkpoint_id"),)