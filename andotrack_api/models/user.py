from sqlalchemy import Column, Integer, String, Enum, Date
from database import Base

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100))
    email = Column(String(100), unique=True, index=True)
    password = Column(String(255))
    role = Column(Enum("runner", "organizer"), default="runner")
    date_of_birth = Column(Date, nullable=True)