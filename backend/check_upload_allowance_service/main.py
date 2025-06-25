import firebase_admin
from firebase_admin import auth, firestore
from flask import jsonify
import functions_framework
from datetime import datetime, timedelta
import time
import os

# Initialize Firebase Admin SDK
firebase_admin.initialize_app()
db = firestore.client()

@functions_framework.http
def check_upload_allowance(request):
    """
    An HTTPS Callable function that checks if a user is permitted to upload a file.
    It now ALSO creates a user profile on-demand if one doesn't exist.
    """
    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}

    try:
        # START TIMING
        start_time = time.time()
        print(f"🕐 Function started at: {start_time}")
        
        # --- 1. Authenticate the user ---
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            raise ValueError("Unauthorized")
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        uid = decoded_token['uid']
        email = decoded_token.get('email', '') # Get user's email

        # TIMING: After auth
        auth_time = time.time()
        print(f"🔐 Auth completed in: {(auth_time - start_time)*1000:.0f}ms")

        # --- 2. Check if the user's profile document exists ---
        user_doc_ref = db.collection('users').document(uid)
        user_doc = user_doc_ref.get()

        # TIMING: After user doc fetch
        user_doc_time = time.time()
        print(f"👤 User doc fetch took: {(user_doc_time - auth_time)*1000:.0f}ms")

        # --- NEW LOGIC: If the document does NOT exist, create it on-demand ---
        if not user_doc.exists:
            print(f"User profile for {uid} not found. Creating one on-demand.")
            user_doc_ref.set({
                'email': email,
                'isSubscribed': False,
                'subscriptionType': 'free',
                'accountCreated': firestore.SERVER_TIMESTAMP
            })
            
            # TIMING: After user creation
            create_time = time.time()
            print(f"👤 User creation took: {(create_time - user_doc_time)*1000:.0f}ms")
            print(f"⏱️ TOTAL TIME (new user): {(create_time - start_time)*1000:.0f}ms")
            
            # Since this is a new user, they are under the limit. Allow the upload.
            return (jsonify({"data": {"allow": True, "reason": "New user profile created."}}), 200, headers)

        # --- Logic continues as before for existing users ---
        user_data = user_doc.to_dict()
        if user_data.get('isSubscribed') is True:
            # TIMING: Subscription check
            sub_time = time.time()
            print(f"💳 Subscription check took: {(sub_time - user_doc_time)*1000:.0f}ms")
            print(f"⏱️ TOTAL TIME (subscribed): {(sub_time - start_time)*1000:.0f}ms")
            
            return (jsonify({"data": {"allow": True, "reason": "User is subscribed"}}), 200, headers)

        # --- 3. Count uploads in the last 7 days ---
        print(f"📊 Starting file count query for user {uid}")
        query_start_time = time.time()
        
        # --- 4. Enforce the free tier limit ---
        # Get free tier limit from environment variable (default: 5)
        FREE_TIER_LIMIT = int(os.environ.get('FREE_TIER_LIMIT', '5'))
        print(f"🎯 Using FREE_TIER_LIMIT: {FREE_TIER_LIMIT}")

        one_week_ago = datetime.now() - timedelta(days=7)
        # OPTIMIZED: Only get what we need to check the limit
        files_query = db.collection('files')\
            .where('userId', '==', uid)\
            .where('uploadTimestamp', '>=', one_week_ago)\
            .limit(FREE_TIER_LIMIT + 1)\
            .select([])  # Only get document IDs, not full documents

        # TIMING: After Firestore query
        query_end_time = time.time()
        print(f"🔍 Firestore query took: {(query_end_time - query_start_time)*1000:.0f}ms")

        # Count documents without downloading full data
        upload_count = len([doc.id for doc in files_query.stream()])
        print(f"📁 Found {upload_count} files for user {uid}")

        if upload_count < FREE_TIER_LIMIT:
            final_time = time.time()
            print(f"✅ Allow response prep took: {(final_time - query_end_time)*1000:.0f}ms")
            print(f"⏱️ TOTAL TIME (allowed): {(final_time - start_time)*1000:.0f}ms")
            
            return (jsonify({"data": {"allow": True, "reason": f"Usage ({upload_count}/{FREE_TIER_LIMIT}) is within the free limit."}}), 200, headers)
        else:
            final_time = time.time()
            print(f"❌ Deny response prep took: {(final_time - query_end_time)*1000:.0f}ms")
            print(f"⏱️ TOTAL TIME (denied): {(final_time - start_time)*1000:.0f}ms")
            
            return (jsonify({"data": {"allow": False, "reason": f"Weekly upload limit of {FREE_TIER_LIMIT} files has been reached."}}), 200, headers)     
    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT: {error_message}")
        return (jsonify({"error": {"status": "INTERNAL", "message": error_message}}), 500, headers)  