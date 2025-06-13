import os
import firebase_admin
from firebase_admin import auth
from google.cloud import secretmanager
import razorpay
import functions_framework
from flask import jsonify

# Initialize Firebase Admin SDK
firebase_admin.initialize_app()

# Initialize Razorpay client. We will populate the keys inside the function.
razorpay_client = None

def access_secret_version(secret_id, project_id, version_id="latest"):
    """Accesses a secret version."""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{project_id}/secrets/{secret_id}/versions/{version_id}"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def create_subscription_order(request):
    """
    HTTPS Callable function to create a Razorpay Order for a subscription.
    """
    global razorpay_client

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
        # uid = decoded_token['uid'] # We have the user's ID if needed later

        # --- 2. Initialize Razorpay client if not already done ---
        if razorpay_client is None:
            project_id = os.environ.get('GCP_PROJECT')
            key_id = os.environ.get('RAZORPAY_KEY_ID')
            secret_name = os.environ.get('RAZORPAY_SECRET_NAME')
            
            key_secret = access_secret_version(secret_name, project_id)
            
            razorpay_client = razorpay.Client(auth=(key_id, key_secret))

        # --- 3. Create a Razorpay Order ---
        # For now, we hardcode the amount. This would come from your subscription plan.
        # Amount is in the smallest currency unit (e.g., paise for INR). 49900 paise = ₹499.
        order_amount = 49900 
        order_currency = 'INR'
        order_receipt = f'receipt_{decoded_token["uid"]}_{datetime.datetime.now().timestamp()}'

        order = razorpay_client.order.create({
            'amount': order_amount,
            'currency': order_currency,
            'receipt': order_receipt
        })

        print(f"Created Razorpay order {order['id']} for user {decoded_token['uid']}")

        # --- 4. Return the necessary details to the Flutter app ---
        return (jsonify({"data": {
            "orderId": order['id'],
            "amount": order['amount'],
            "currency": order['currency'],
            "razorpayKeyId": os.environ.get('RAZORPAY_KEY_ID') # Send the public key to the client
        }}), 200, headers)

    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT: {error_message}")
        return (jsonify({"error": {"status": "INTERNAL", "message": error_message}}), 500, headers)