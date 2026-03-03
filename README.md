# 🏃 &DoTrack — Real-Time Marathon Tracking System

> A project for &DOTSports Events — built with Flutter, FastAPI, Firebase, and Machine Learning.

---

## 📌 Project Overview

**&DoTrack** is a real-time marathon tracking system designed for &DOTSports running events in the Philippines. It eliminates manual timing and participant monitoring by providing live GPS tracking, automated checkpoint detection, anomaly detection using machine learning, and a live leaderboard — all accessible from a mobile app and web dashboards.

### The Problem
- Event organizers rely on manual timing and have no live visibility of runners
- Runners receive no real-time performance feedback during races
- Safety is compromised with no way to monitor participant locations
- Post-event analytics are time-consuming and incomplete

### The Solution
- **Runners** get a mobile app that tracks their GPS, shows their pace, distance, and ETA to finish
- **Organizers** get a live dashboard showing all runners on a map with anomaly alerts
- **The public** gets a live leaderboard showing real-time rankings
- **Safety** is handled by an Isolation Forest ML model that detects unusual runner behavior

---

## ✨ Features

- 🗺️ Real-time GPS tracking with Firebase Realtime Database sync
- 📍 Checkpoint detection using Haversine geofencing
- 🤖 Anomaly detection using Isolation Forest machine learning
- 🏆 Live leaderboard with pace, distance, and ETA
- 🔐 JWT-based authentication with role-based access (runner / organizer)
- 📡 Offline GPS queue — stores location data when internet is unavailable and syncs on reconnect
- 🔋 Foreground service — keeps GPS running when phone screen is locked
- 📊 Post-race results and analytics

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIENT LAYER                         │
│                                                             │
│   Runner App          Organizer Dashboard   Public Board    │
│   (Flutter/Dart)      (Flutter Web)         (Flutter Web)   │
└──────────┬────────────────────┬─────────────────┬───────────┘
           │                    │                 │
     ┌─────▼────────────────────▼─────────────────▼──────┐
     │                  FIREBASE (Cloud)                  │
     │         Realtime DB — live GPS coordinates         │
     │         Authentication — login and roles           │
     └─────────────────────────┬──────────────────────────┘
                               │
     ┌─────────────────────────▼──────────────────────────┐
     │              FASTAPI BACKEND (Python)               │
     │   Auth · Race Management · Checkpoint Detection     │
     │   Leaderboard · Isolation Forest ML Model           │
     └─────────────────────────┬──────────────────────────┘
                               │
     ┌─────────────────────────▼──────────────────────────┐
     │                  MYSQL DATABASE                     │
     │   Users · Races · Checkpoints · Results · Anomalies │
     └────────────────────────────────────────────────────┘
```

### Data Flow

```
Runner Phone (geolocator)
  → GPS every 2-3 seconds
  → Foreground service keeps GPS alive when screen locks
  → connectivity_plus checks internet status
  → Online: writes to Firebase Realtime DB instantly
  → Offline: stores in local queue, syncs on reconnect

Firebase Realtime DB
  → Organizer dashboard sees all runners as live moving dots
  → Public leaderboard updates rankings in real time

FastAPI (background processing)
  → Reads new GPS coordinates
  → Runs Isolation Forest anomaly detection
  → Runs Haversine checkpoint detection
  → Updates MySQL with results
  → Pushes anomaly flags back to Firebase
```

---

## 🛠️ Tech Stack

### Frontend
| Technology | Purpose |
|---|---|
| Flutter (Dart) | Runner app + Organizer dashboard + Public leaderboard |
| Firebase SDK | Real-time GPS sync listener |
| geolocator | GPS location tracking |
| flutter_foreground_task | Background GPS when screen is locked |
| connectivity_plus | Online/offline detection |
| Riverpod | State management |
| http | REST API calls to FastAPI |

### Backend
| Technology | Purpose |
|---|---|
| FastAPI (Python) | REST API framework |
| Uvicorn | ASGI server |
| SQLAlchemy | ORM for MySQL |
| python-jose | JWT authentication |
| passlib | Password hashing |
| firebase-admin | Read/write Firebase from backend |
| scikit-learn | Isolation Forest ML model |
| numpy + pandas | Data processing |

### Database
| Technology | Purpose |
|---|---|
| Firebase Realtime DB | Live GPS sync between all devices |
| Firebase Auth | User login and role management |
| MySQL | Users, races, checkpoints, results, anomalies |

### Infrastructure
| Technology | Purpose |
|---|---|
| Railway | FastAPI + MySQL hosting |
| Firebase Spark | Free tier — Realtime DB + Auth |
| GitHub | Version control |

---

## 🚀 Setup Instructions

### Prerequisites

Make sure you have the following installed:

| Tool | Version |
|---|---|
| Flutter SDK | 3.27.1+ |
| Python | 3.11+ |
| Git | Latest |
| Android Studio | Latest (for Android SDK) |
| MySQL | Latest |

---

### 1. Clone the Repository

```bash
git clone https://github.com/YOURUSERNAME/andotrack.git
cd andotrack
```

---

### 2. Backend Setup (FastAPI)

```bash
cd andotrack_api

# Create and activate virtual environment
python -m venv venv
venv\Scripts\activate       # Windows
source venv/bin/activate    # Mac/Linux

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp .env.example .env
# Open .env and fill in your MySQL credentials and JWT secret
```

**Create the MySQL database:**
```sql
CREATE DATABASE andotrack;
```

**Run the server:**
```bash
uvicorn main:app --reload
```

API will be running at `http://127.0.0.1:8000`
API docs available at `http://127.0.0.1:8000/docs`

---

### 3. Frontend Setup (Flutter)

```bash
cd andotrack_app

# Install dependencies
flutter pub get

# Configure Firebase
dart pub global activate flutterfire_cli
dart pub global run flutterfire_cli:flutterfire configure
# Select your Firebase project when prompted
# Select android and web platforms only

# Run the app
flutter run -d chrome        # Web (organizer/leaderboard)
flutter run                  # Android (runner app)
```

---

### 4. Environment Variables

Copy `.env.example` to `.env` in the `andotrack_api` folder and fill in your values:

```
DATABASE_URL=mysql+pymysql://root:yourpassword@localhost/andotrack
JWT_SECRET=your-secret-key-here
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=60
```

---

### 5. Firebase Setup

1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. Create a project named `andotrack`
3. Enable **Realtime Database** (start in test mode)
4. Enable **Authentication** (Email/Password)
5. Run `flutterfire configure` as shown above — this auto-generates `lib/firebase_options.dart`

---

## 📁 Project Structure

```
andotrack/
├── andotrack_api/              ← FastAPI Backend
│   ├── main.py
│   ├── database.py
│   ├── requirements.txt
│   ├── .env.example
│   ├── ml/
│   │   └── train_model.py
│   ├── models/
│   │   ├── user.py
│   │   ├── race.py
│   │   ├── checkpoint.py
│   │   └── anomaly.py
│   └── routes/
│       ├── auth.py
│       ├── races.py
│       ├── runners.py
│       ├── checkpoints.py
│       └── leaderboard.py
│
└── andotrack_app/              ← Flutter Frontend
    └── lib/
        ├── main.dart
        ├── firebase_options.dart
        ├── screens/
        │   ├── login_screen.dart
        │   └── map_screen.dart
        └── services/
            ├── firebase_service.dart
            ├── api_service.dart
            └── location_service.dart
```

---

## 🤖 ML Model — Isolation Forest

&DoTrack uses an **Isolation Forest unsupervised machine learning model** to detect real-time runner anomalies.

The model monitors these features per GPS update:
- Speed — detects vehicle use
- Acceleration — detects sudden speed spikes
- Direction change — detects erratic movement
- Distance from route — detects off-route runners
- Distance from last point — detects GPS jumps

When an anomaly is detected, the organizer dashboard receives an instant alert with the runner's name, location, and reason.

To train the model:
```bash
cd andotrack_api
python ml/train_model.py
```

---

## 📜 License

This project is developed as a capstone project for academic purposes.

---

> Built with ❤️ for &DOTSports — Cebu, Philippines
