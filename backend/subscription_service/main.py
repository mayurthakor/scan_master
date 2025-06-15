import os
import firebase_admin
from firebase_admin import auth
from google.cloud import secretmanager
import razorpay
import functions_framework
from flask import jsonify
import time

# Initialize Firebase Admin SDK
firebase_admin.initialize_app()

def access_secret_version(secret_id, version_id="latest"):
    """Accesses a secret version with a hardcoded project ID."""
    client = secretmanager.SecretManagerServiceClient()
    # HARDCODING the project ID to remove any ambiguity.
    name = f"projects/scan-master-app/secrets/{secret_id}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def create_subscription_order(request):
    """
    HTTPS Callable function to create a Razorpay Order for a subscription.
    """
    # Standard CORS preflight handling
    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # --- 1. Authenticate the user securely ---
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            raise ValueError("Unauthorized")
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        uid = decoded_token['uid']

        # --- 2. Get credentials ---
        key_id = os.environ.get('RAZORPAY_KEY_ID')
        
        # We now directly use the known secret name, project ID is hardcoded in the function
        key_secret = access_secret_version('razorpay-key-secret')
        
        razorpay_client = razorpay.Client(auth=(key_id, key_secret))

        # --- 3. Create a Razorpay Order ---
        order_amount = 49900 
        order_currency = 'INR'
        order_receipt = f'rcpt_{uid[-12:]}_{int(time.time())}'

        order = razorpay_client.order.create({
            'amount': order_amount,
            'currency': order_currency,
            'receipt': order_receipt
        })

        print(f"Created Razorpay order {order['id']} for user {uid}")

        # --- 4. Return the necessary details to the Flutter app ---
        return (jsonify({"data": {
            "orderId": order['id'],
            "amount": order['amount'],
            "currency": order['currency'],
            "razorpayKeyId": key_id
        }}), 200, headers)

    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT: {error_message}")
        return (jsonify({"error": {"status": "INTERNAL", "message": error_message}}), 500, headers)