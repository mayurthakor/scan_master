import os
import datetime
from google.cloud import firestore, storage
from google.oauth2 import service_account
import functions_framework
from flask import jsonify
import firebase_admin
from firebase_admin import auth

# Initialize Firebase Admin (only if not already initialized)
if not firebase_admin._apps:
    firebase_admin.initialize_app()

# Load credentials from the service account key file for URL signing
credentials = service_account.Credentials.from_service_account_file('service-account-key.json')

# Initialize clients with the signing credentials
storage_client = storage.Client(credentials=credentials)
db = firestore.Client()

@functions_framework.http
def get_download_url(request):
    """
    Generate a signed download URL for a PDF document.
    Requires the service account key file for URL signing.
    """
    # Set CORS headers
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}

    try:
        # Authentication - verify Firebase Auth token
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return jsonify({
                'error': {
                    'message': 'Missing or invalid Authorization header',
                    'status': 'UNAUTHORIZED'
                }
            }), 401, headers

        # Extract and verify the ID token
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        user_id = decoded_token['uid']

        # Get request data
        request_json = request.get_json()
        if not request_json or 'data' not in request_json:
            return jsonify({
                'error': {
                    'message': 'Invalid request format. Expected {"data": {"documentId": "..."}}',
                    'status': 'BAD_REQUEST'
                }
            }), 400, headers

        data = request_json['data']
        document_id = data.get('documentId')
        
        if not document_id:
            return jsonify({
                'error': {
                    'message': 'Missing documentId parameter',
                    'status': 'BAD_REQUEST'
                }
            }), 400, headers

        # Get document metadata from Firestore
        doc_ref = db.collection('files').document(document_id)
        document = doc_ref.get()

        if not document.exists:
            return jsonify({
                'error': {
                    'message': 'Document not found',
                    'status': 'NOT_FOUND'
                }
            }), 404, headers

        doc_data = document.to_dict()
        
        # Verify the user owns this document
        if doc_data.get('userId') != user_id:
            return jsonify({
                'error': {
                    'message': 'Access denied. User does not own this document.',
                    'status': 'FORBIDDEN'
                }
            }), 403, headers

        # Get the PDF path from the document
        pdf_path = doc_data.get('pdfPath')
        if not pdf_path:
            return jsonify({
                'error': {
                    'message': 'PDF path not found in document metadata',
                    'status': 'NOT_FOUND'
                }
            }), 404, headers

        # Get bucket name from environment variable
        bucket_name = os.environ.get('GCS_BUCKET', 'scan-master-app.firebasestorage.app')
        
        # Generate signed URL using the service account credentials
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(pdf_path)

        # Check if the file exists
        if not blob.exists():
            return jsonify({
                'error': {
                    'message': f'File not found in storage: {pdf_path}',
                    'status': 'NOT_FOUND'
                }
            }), 404, headers

        # Generate signed URL (valid for 1 hour)
        expiration = datetime.datetime.utcnow() + datetime.timedelta(hours=1)
        
        signed_url = blob.generate_signed_url(
            expiration=expiration,
            method='GET',
            version='v4'
        )

        # Return the signed URL
        return jsonify({
            'result': {
                'url': signed_url,
                'expires': expiration.isoformat() + 'Z',
                'filename': doc_data.get('originalFileName', 'document.pdf')
            }
        }), 200, headers

    except auth.InvalidIdTokenError:
        return jsonify({
            'error': {
                'message': 'Invalid authentication token',
                'status': 'UNAUTHORIZED'
            }
        }), 401, headers
    
    except Exception as e:
        print(f"!!! RETURNING ERROR TO CLIENT SIDE LAYER: Backend Error: {type(e).__name__} - {str(e)}")
        return jsonify({
            'error': {
                'message': f'Backend Error: {type(e).__name__} - {str(e)}',
                'status': 'INTERNAL'
            }
        }), 500, headers