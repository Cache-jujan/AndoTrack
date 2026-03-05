import firebase_admin
from firebase_admin import credentials, db

# Load your service account key JSON
cred = credentials.Certificate("serviceAccountKey.json")  # make sure this file is in the same folder

# Initialize Firebase app with your Realtime Database URL
firebase_admin.initialize_app(cred, {
    "databaseURL": "https://andotrack-b0347-default-rtdb.asia-southeast1.firebasedatabase.app/"
   
})

