import firebase_admin
from firebase_admin import credentials, db
import os, json, base64

firebase_creds = os.getenv("FIREBASE_CREDENTIALS_BASE64")

if firebase_creds:
    cred_dict = json.loads(base64.b64decode(firebase_creds).decode())
    cred = credentials.Certificate(cred_dict)
else:
    cred = credentials.Certificate("serviceAccountKey.json")

firebase_admin.initialize_app(cred, {
    "databaseURL": "https://andotrack-b0347-default-rtdb.asia-southeast1.firebasedatabase.app/"
})