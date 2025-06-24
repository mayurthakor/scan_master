import os
from google.cloud import firestore, storage
import functions_framework
from flask import jsonify
import firebase_admin
from firebase_admin import auth

# Initialize SDKs
firebase_admin.initialize_app()
storage_client = storage.Client()
db = firestore.Client()

@functions_framework.http
def delete_file(request):
    """
    An HTTPS Callable function to securely delete a Firestore document
    and its corresponding files in Cloud Storage.
    """
    # Standard CORS and auth handling
    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization', 'Access-Control-Max-Age': '3600'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}

    try:
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            raise ValueError("Unauthorized")
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        user_id = decoded_token['uid']

        data = request.get_json()['data']
        doc_id = data['documentId']
        
        # Get the document reference
        doc_ref = db.collection('files').document(doc_id)
        document = doc_ref.get()

        if not document.exists:
            raise FileNotFoundError("File record not found.")

        doc_data = document.to_dict()

        # Security Check: Ensure the user owns this file
        if doc_data.get('userId') != user_id:
            raise PermissionError("User does not have permission to delete this file.")

        # --- This is the robust deletion logic ---
        bucket_name = os.environ.get('GCS_BUCKET')
        bucket = storage_client.bucket(bucket_name)

        # 1. Delete the original uploaded image file (if path exists)
        original_file_path = doc_data.get('storagePath')
        if original_file_path:
            original_blob = bucket.blob(original_file_path)
            if original_blob.exists():
                original_blob.delete()
                print(f"Deleted original file: {original_file_path}")

        # 2. Delete the processed PDF file (if path exists)
        pdf_file_path = doc_data.get('pdfPath')
        if pdf_file_path:
            pdf_blob = bucket.blob(pdf_file_path)
            if pdf_blob.exists():
                pdf_blob.delete()
                print(f"Deleted PDF file: {pdf_file_path}")
        # --- End of deletion logic ---
        
        # 3. Finally, delete the Firestore document
        doc_ref.delete()
        print(f"Deleted Firestore document: {doc_id}")

        return (jsonify({"data": {"success": True, "message": "File deleted successfully."}}), 200, headers)

    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT: {error_message}")
        error_payload = {"error": {"status": "INTERNAL", "message": error_message}}
        return (jsonify(error_payload), 500, headers) 