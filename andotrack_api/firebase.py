import firebase_admin
from firebase_admin import credentials, db
import os, json, base64

def _load_firebase_cred():
    # 1. Plain JSON string (Railway: set FIREBASE_SERVICE_ACCOUNT_JSON)
    plain = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    if plain:
        return credentials.Certificate(json.loads(plain))

    # 2. Base64-encoded JSON (legacy env var)
    b64 = os.getenv("FIREBASE_CREDENTIALS_BASE64")
    if b64:
        return credentials.Certificate(json.loads(base64.b64decode(b64).decode()))

    # 3. Local dev fallback — file is gitignored and will not exist on Railway
    return credentials.Certificate("serviceAccountKey.json")

firebase_admin.initialize_app(_load_firebase_cred(), {
    "databaseURL": "https://andotrack-b0347-default-rtdb.asia-southeast1.firebasedatabase.app/"
})