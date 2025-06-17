# backend/chat_service/main.py
import os
import functions_framework
import firebase_admin
from firebase_admin import firestore, app_check # <-- Import app_check
from google.cloud import secretmanager
import google.generativeai as genai

firebase_admin.initialize_app()
db = firestore.Client()
# ... (rest of the initialization code is the same)
secrets_client = secretmanager.SecretManagerServiceClient()
PROJECT_ID = os.environ.get('GCLOUD_PROJECT')
def access_secret_version(secret_id, version_id="latest"):
    if not PROJECT_ID: raise ValueError("GCLOUD_PROJECT env var not set.")
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/{version_id}"
    response = secrets_client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")
GOOGLE_API_KEY = access_secret_version("gemini-api-key")
genai.configure(api_key=GOOGLE_API_KEY)

@functions_framework.http
def chat_with_document(request):
    # --- NEW: App Check verification ---
    app_check_token = request.headers.get('X-Firebase-AppCheck')
    if not app_check_token:
        return "Unauthorized", 401
    try:
        app_check.verify_token(app_check_token)
    except Exception as e:
        return f"Unauthorized: {e}", 401
    # --- End of App Check verification ---

    if request.method == 'OPTIONS':
        headers = {'Access-control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}
    
    # The rest of your function logic remains exactly the same...
    try:
        request_data = request.get_json()['data']
        doc_id = request_data['documentId']
        user_question = request_data['question']
        # ... (the entire try/except block for getting the answer)
        if not doc_id or not user_question: raise ValueError("Missing 'documentId' or 'question'.")
        content_doc_ref = db.collection('document_content').document(doc_id)
        content_doc = content_doc_ref.get()
        if not content_doc.exists: raise FileNotFoundError(f"No content for {doc_id}.")
        full_text = content_doc.to_dict().get('full_text', '')
        if not full_text: return ({"data": {"answer": "I could not find any text content for this document."}}, 200, headers)
        model = genai.GenerativeModel('gemini-1.5-pro-latest')
        prompt = f"""
        Based *only* on the content of the document provided below, answer the user's question.
        If the answer cannot be found in the document, say "I could not find an answer to that in this document."
        DOCUMENT CONTENT:---{full_text}---
        USER'S QUESTION:{user_question}
        """
        response = model.generate_content(prompt)
        return ({"data": {"answer": response.text}}, 200, headers)
    except Exception as e:
        print(f"ERROR: {e}")
        return ({"error": {"message": str(e)}}, 500, headers)