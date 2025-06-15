import firebase_admin
from firebase_admin import auth, firestore
from flask import jsonify
import functions_framework
from datetime import datetime, timedelta

# Initialize Firebase Admin SDK
firebase_admin.initialize_app()
db = firestore.client()

@functions_framework.http
def check_upload_allowance(request):
    """
    An HTTPS Callable function that checks if a user is permitted to upload a file.
    """
    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}

    try:
        # --- 1. Authenticate the user ---
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            raise ValueError("Unauthorized")
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        uid = decoded_token['uid']

        # --- 2. Check if the user has an active subscription ---
        user_doc_ref = db.collection('users').document(uid)
        user_doc = user_doc_ref.get()
        if user_doc.exists:
            user_data = user_doc.to_dict()
            if user_data.get('isSubscribed') is True:
                # If subscribed, always allow upload
                return (jsonify({"data": {"allow": True, "reason": "User is subscribed"}}), 200, headers)

        # --- 3. If not subscribed, count uploads in the last 7 days ---
        one_week_ago = datetime.now() - timedelta(days=7)
        files_query = db.collection('files').where('userId', '==', uid).where('uploadTimestamp', '>=', one_week_ago)
        
        # Get the count of documents in the query result
        upload_count = len(list(files_query.stream()))

        # --- 4. Enforce the free tier limit ---
        FREE_TIER_LIMIT = 5
        if upload_count < FREE_TIER_LIMIT:
            # Allow upload if the user is under the limit
            return (jsonify({"data": {"allow": True, "reason": f"Usage ({upload_count}/{FREE_TIER_LIMIT}) is within the free limit."}}), 200, headers)
        else:
            # Deny upload if the user has reached the limit
            return (jsonify({"data": {"allow": False, "reason": f"Weekly upload limit of {FREE_TIER_LIMIT} files has been reached."}}), 200, headers)

    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT: {error_message}")
        return (jsonify({"error": {"status": "INTERNAL", "message": error_message}}), 500, headers)