# backend/prepare_chat_service/main.py
import os
import functions_framework
import firebase_admin
from firebase_admin import firestore, app_check # <-- Import app_check
from google.cloud import storage, secretmanager
import google.generativeai as genai
from pypdf import PdfReader
from io import BytesIO

firebase_admin.initialize_app()
db = firestore.Client()
# ... (rest of the initialization code is the same)
storage_client = storage.Client()
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
def prepare_chat_session(request):
    # --- NEW: App Check verification ---
    app_check_token = request.headers.get('X-Firebase-AppCheck')
    if not app_check_token:
        # Throw a 401 error if no token is provided
        return "Unauthorized", 401
    try:
        app_check.verify_token(app_check_token)
    except Exception as e:
        # Throw a 401 error if token is invalid
        return f"Unauthorized: {e}", 401
    # --- End of App Check verification ---

    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}
    
    # The rest of your function logic remains exactly the same...
    doc_id = ""
    try:
        request_data = request.get_json()['data']
        doc_id = request_data['documentId']
        # ... (the entire try/except block for PDF processing)
        file_doc_ref = db.collection('files').document(doc_id)
        file_doc = file_doc_ref.get()
        if not file_doc.exists: raise FileNotFoundError(f"File document {doc_id} not found.")
        file_data = file_doc.to_dict()
        if file_data.get('isChatReady') is True:
            return ({"data": {"summary": file_data.get('summary', 'Summary not found.')}}, 200, headers)
        pdf_path = file_data.get('pdfPath')
        if not pdf_path: raise ValueError("PDF path not found.")
        bucket_name = os.environ.get('GCS_BUCKET')
        if not bucket_name: raise ValueError("GCS_BUCKET env var not set.")
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(pdf_path)
        pdf_content = blob.download_as_bytes()
        reader = PdfReader(BytesIO(pdf_content))
        full_text = "".join(page.extract_text() + "\n" for page in reader.pages)
        if not full_text.strip():
            summary = "No text could be extracted from this document."
            db.collection('document_content').document(doc_id).set({'full_text': ''})
            file_doc_ref.update({'summary': summary, 'isChatReady': True, 'chatStatus': 'ready'})
            return ({"data": {"summary": summary}}, 200, headers)
        model = genai.GenerativeModel('gemini-1.5-pro-latest')
        prompt = f"Provide a concise, one-paragraph summary of the following document:\n\n{full_text}"
        response = model.generate_content(prompt)
        summary = response.text
        db.collection('document_content').document(doc_id).set({'full_text': full_text})
        file_doc_ref.update({'summary': summary, 'isChatReady': True, 'chatStatus': 'ready' })
        return ({"data": {"summary": summary}}, 200, headers)
    except Exception as e:
        print(f"ERROR processing document {doc_id}: {e}")
        if doc_id:
            db.collection('files').document(doc_id).update({'chatStatus': 'failed'})
        return ({"error": {"message": str(e)}}, 500, headers)