# backend/verify_payment_service/main.py
import os
import firebase_admin
from firebase_admin import auth, firestore
import razorpay
import functions_framework
from flask import jsonify
from datetime import datetime, timedelta

# Initialize Firebase Admin SDK (only once)
if not firebase_admin._apps:
    firebase_admin.initialize_app()

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
        
        # --- 3. Get Razorpay credentials from environment variables (FIXED) ---
        key_id = os.environ.get('RAZORPAY_KEY_ID')
        
        if not key_id:
            raise ValueError("Razorpay Key ID not configured")
            
        # Initialize Razorpay client with key ID only
        razorpay_client = razorpay.Client(auth=(key_id, ''))

        # --- 4. Verify payment using Razorpay API (SIMPLIFIED) ---
        # Since we only have key_id, we'll fetch payment details to verify
        razorpay_client = razorpay.Client(auth=(key_id, ''))
        
        try:
            # Fetch payment details to verify it exists and is successful
            payment_details = razorpay_client.payment.fetch(razorpay_payment_id)
            
            # Verify payment is captured/successful
            if payment_details['status'] != 'captured':
                raise ValueError(f"Payment status is {payment_details['status']}, expected 'captured'")
                
            # Verify the order_id matches
            if payment_details['order_id'] != order_id:
                raise ValueError("Order ID mismatch")
                
            print(f"Successfully verified payment {razorpay_payment_id} for order {order_id}")
            
        except razorpay.errors.BadRequestError as e:
            raise ValueError(f"Invalid payment ID: {str(e)}")
        except Exception as e:
            raise ValueError(f"Payment verification failed: {str(e)}")

        # --- 5. Update user's profile in Firestore ---
        db = firestore.client()
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

    except ValueError as e:
        # Handle payment verification errors
        print(f"!!! PAYMENT VERIFICATION FAILED: {str(e)}")
        return (jsonify({"error": {"status": "INVALID_ARGUMENT", "message": str(e)}}), 400, headers)
    except Exception as e:
        error_message = f"Backend Error: {type(e).__name__} - {str(e)}"
        print(f"!!! RETURNING ERROR TO CLIENT: {error_message}")
        return (jsonify({"error": {"status": "INTERNAL", "message": error_message}}), 500, headers)