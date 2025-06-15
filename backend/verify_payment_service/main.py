import os
import firebase_admin
from firebase_admin import auth, firestore
from google.cloud import secretmanager
import razorpay
import functions_framework
from flask import jsonify
from datetime import datetime, timedelta

# Initialize Firebase Admin SDK
firebase_admin.initialize_app()
db = firestore.client()

def access_secret_version(secret_id, version_id="latest"):
    """Accesses a secret version with a hardcoded project ID."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/scan-master-app/secrets/{secret_id}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def verify_payment(request):
    """
    HTTPS Callable function to verify a Razorpay payment and update user subscription.
    """
    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # --- 1. Authenticate the user who is claiming the payment ---
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            raise ValueError("Unauthorized")
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        uid = decoded_token['uid']

        # --- 2. Get payment details sent from the Flutter app ---
        data = request.get_json()['data']
        order_id = data['order_id']
        razorpay_payment_id = data['razorpay_payment_id']
        razorpay_signature = data['razorpay_signature']
        
        # --- 3. Get Razorpay credentials securely ---
        key_id = os.environ.get('RAZORPAY_KEY_ID')
        key_secret = access_secret_version('razorpay-key-secret')
        razorpay_client = razorpay.Client(auth=(key_id, key_secret))

        # --- 4. Verify the payment signature (CRITICAL SECURITY STEP) ---
        params_dict = {
            'razorpay_order_id': order_id,
            'razorpay_payment_id': razorpay_payment_id,
            'razorpay_signature': razorpay_signature
        }
        razorpay_client.utility.verify_payment_signature(params_dict)
        print(f"Successfully verified signature for order {order_id}")

        # --- 5. Update user's profile in Firestore ---
        user_ref = db.collection('users').document(uid)
        
        # For this example, we'll grant a 1-year subscription
        subscription_end_date = datetime.now() + timedelta(days=365)
        
        user_ref.set({
            'isSubscribed': True,
            'subscriptionType': 'premium_yearly',
            'paymentOrderId': order_id,
            'paymentId': razorpay_payment_id,
            'subscriptionStartDate': firestore.SERVER_TIMESTAMP,
            'subscriptionEndDate': subscription_end_date
        }, merge=True)
        
        print(f"Successfully updated subscription for user {uid}")
        
        return (jsonify({"data": {"status": "success", "message": "Subscription activated successfully."}}), 200, headers)

    except razorpay.errors.SignatureVerificationError:
        # This error is caught if the signature is invalid
        print(f"!!! SIGNATURE VERIFICATION FAILED FOR ORDER {order_id}")
        return (jsonify({"error": {"status": "UNAUTHENTICATED", "message": "Payment signature verification failed."}}), 403, headers)
    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT: {error_message}")
        return (jsonify({"error": {"status": "INTERNAL", "message": error_message}}), 500, headers)