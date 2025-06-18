import os
import functions_framework
import firebase_admin
from firebase_admin import firestore, auth
from google.cloud import storage, secretmanager
import google.generativeai as genai
from pypdf import PdfReader
from io import BytesIO

# --- Global initializations (Clients are safe to initialize here) ---
firebase_admin.initialize_app()
db = firestore.Client()
storage_client = storage.Client()
secrets_client = secretmanager.SecretManagerServiceClient()
PROJECT_ID = os.environ.get('GCLOUD_PROJECT')

# --- Helper function remains global ---
def access_secret_version(secret_id, version_id="latest"):
    if not PROJECT_ID: raise ValueError("GCLOUD_PROJECT env var not set.")
    name = f"projects/{PROJECT_ID}/secrets/{secret_id}/versions/{version_id}"
    response = secrets_client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def generate_doc_summary(request):
    # --- MOVED and UPDATED LOGIC ---
    # Secret fetching and library configuration now happen inside the function.
    # This is more robust and only runs when the function is invoked.
    try:
        api_key = access_secret_version("gemini-api-key")
        genai.configure(api_key=api_key)
    except Exception as e:
        print(f"FATAL: Could not configure Gemini API. Error: {e}")
        return ("Server configuration error.", 500)
    # --- END OF MOVED LOGIC ---

    if request.method == 'OPTIONS':
        headers = {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type, Authorization'}
        return ('', 204, headers)
    headers = {'Access-Control-Allow-Origin': '*'}

    doc_id = ""
    try:
        # 1. Securely verify the user is authenticated.
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return ("Missing or invalid Authorization header.", 401)
        
        id_token = auth_header.split('Bearer ')[1]
        try:
            decoded_token = auth.verify_id_token(id_token)
            user_uid = decoded_token['uid']
        except Exception as e:
            return (f"Invalid authentication token: {e}", 403)

        # 2. Robustly parse the incoming JSON payload.
        request_json = request.get_json(silent=True)
        request_data = request_json.get('data') if request_json and 'data' in request_json else request_json

        if not request_data or 'documentId' not in request_data:
            raise ValueError("Request payload is invalid or missing 'documentId'")
        
        doc_id = request_data['documentId']
        file_doc_ref = db.collection('files').document(doc_id)
        file_doc = file_doc_ref.get()

        if not file_doc.exists:
            raise FileNotFoundError(f"File document {doc_id} not found.")
        
        file_data = file_doc.to_dict()

        # 3. Enforce ownership.
        if file_data.get('userId') != user_uid:
            return ("Permission denied: User does not own this file.", 403)

        # 4. Proceed with core logic.
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
        full_text = "".join(page.extract_text() + "\n" for page in reader.pages if page.extract_text())
        
        if not full_text.strip():
            summary = "No text could be extracted from this document."
        else:
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