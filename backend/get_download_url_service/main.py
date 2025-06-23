import os
import datetime
from google.cloud import firestore, storage
from google.oauth2 import service_account # Import this
import functions_framework
from flask import jsonify
import firebase_admin
from firebase_admin import auth

# --- USE ENVIRONMENT CREDENTIALS FOR CI/CD ---
# Use default credentials provided by the environment (GitHub Actions)
storage_client = storage.Client()

# Firestore and Auth can still use the default environment credentials.
firebase_admin.initialize_app()
db = firestore.Client()
# --- END OF NEW SETUP ---


@functions_framework.http
def get_download_url(request):
    """
    Final version using explicit service account key for signing URLs.
    """
    # Set CORS headers
    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization', 'Access-Control-Max-Age': '3600'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}

    try:
        # --- Authentication remains the same ---
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            raise ValueError("Missing or invalid Authorization header.")
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        user_id = decoded_token['uid']

        data = request.get_json()['data']
        doc_id = data['documentId']
        
        doc_ref = db.collection('files').document(doc_id)
        document = doc_ref.get()

        if not document.exists:
            raise FileNotFoundError("File record not found.")

        doc_data = document.to_dict()
        if doc_data.get('userId') != user_id:
            raise PermissionError("User does not own this file.")

        pdf_path = doc_data.get('pdfPath')
        if not pdf_path:
            raise ValueError("Record is missing 'pdfPath'.")

        # --- Generate the Signed URL using the key-based client ---
        bucket_name = os.environ.get('GCS_BUCKET')
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(pdf_path)

        # We no longer need to specify service_account_email because the client
        # itself was created with the key and knows how to sign.
        signed_url = blob.generate_signed_url(
            version="v4",
            expiration=datetime.timedelta(minutes=15),
            method="GET",
        )
        
        return (jsonify({"data": {"url": signed_url}}), 200, headers)

    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT SIDE: {error_message}")
        error_payload = {"error": {"status": "INTERNAL", "message": error_message}}
        return (jsonify(error_payload), 500, headers)