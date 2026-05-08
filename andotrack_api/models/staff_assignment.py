import datetime
from sqlalchemy import Column, Integer, Boolean, DateTime, ForeignKey
from database import Base


class StaffAssignment(Base):
    __tablename__ = "staff_assignments"

    id          = Column(Integer, primary_key=True, index=True)
    user_id     = Column(Integer, ForeignKey("users.id"), nullable=False)
    race_id     = Column(Integer, ForeignKey("races.id"), nullable=False)
    assigned_at = Column(DateTime, default=lambda: datetime.datetime.now(datetime.timezone.utc))
    is_active   = Column(Boolean, default=True)