# Multi-region deployment test 
# backend/generate_doc_summary_service/main.py
import os
import functions_framework
import firebase_admin
from firebase_admin import firestore, auth
from google.cloud import storage
import google.generativeai as genai
from pypdf import PdfReader
from io import BytesIO

# Only initialize Firebase Admin globally
if not firebase_admin._apps:
    firebase_admin.initialize_app()

@functions_framework.http
def generate_doc_summary(request):
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    doc_id = None
    
    try:
        # Get request data
        request_data = request.get_json()
        if not request_data or 'data' not in request_data:
            raise ValueError("Invalid request format")
        
        data = request_data['data']
        doc_id = data.get('documentId')
        if not doc_id:
            raise ValueError("Missing documentId")
        
        print(f"Processing document: {doc_id}")
        
        # Manual authentication check
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return ({"error": {"message": "Unauthorized"}}, 401, headers)
        
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        user_id = decoded_token['uid']
        print(f"User authenticated: {user_id}")
        
        # Initialize Firestore client
        print("Initializing Firestore...")
        db = firestore.Client()
        
        # Check document
        print("Checking document...")
        file_doc_ref = db.collection('files').document(doc_id)
        file_doc = file_doc_ref.get()
        
        if not file_doc.exists:
            raise FileNotFoundError(f"File document {doc_id} not found")
        
        file_data = file_doc.to_dict()
        
        # Verify ownership
        if file_data.get('userId') != user_id:
            return ({"error": {"message": "Forbidden"}}, 403, headers)
        
        # Return existing summary if available
        if file_data.get('isChatReady') is True:
            existing_summary = file_data.get('summary', 'Summary not found.')
            print(f"Returning existing summary for {doc_id}")
            return ({"data": {"summary": existing_summary}}, 200, headers)
        
        # Get PDF path
        pdf_path = file_data.get('pdfPath')
        if not pdf_path:
            raise ValueError("PDF path not found in document")
        
        print(f"Processing PDF: {pdf_path}")
        
        # Initialize Storage client
        print("Initializing Storage...")
        storage_client = storage.Client()
        bucket_name = os.environ.get('GCS_BUCKET', 'scan-master-app.firebasestorage.app')
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(pdf_path)
        
        # Download PDF
        print("Downloading PDF...")
        pdf_content = blob.download_as_bytes()
        reader = PdfReader(BytesIO(pdf_content))
        
        # Extract text
        print("Extracting text...")
        full_text = ""
        for page in reader.pages:
            full_text += page.extract_text() + "\n"
        
        if not full_text.strip():
            summary = "No text could be extracted from this document."
            print(f"No text extracted from {doc_id}")
            
            db.collection('document_content').document(doc_id).set({'full_text': ''})
            file_doc_ref.update({
                'summary': summary,
                'isChatReady': True,
                'chatStatus': 'ready'
            })
            return ({"data": {"summary": summary}}, 200, headers)
        
        print(f"Extracted {len(full_text)} characters of text")
        
        # Get Gemini API key from environment variable (no Secret Manager)
        api_key = os.environ.get('GEMINI_API_KEY')
        if not api_key:
            raise ValueError("GEMINI_API_KEY environment variable not set")
        
        # Configure Gemini
        print("Configuring Gemini...")
        genai.configure(api_key=api_key)
        
        # Generate summary
        print("Generating summary...")
        model = genai.GenerativeModel('gemini-1.5-pro-latest')
        prompt = f"Provide a concise, one-paragraph summary of the following document:\n\n{full_text[:4000]}"
        
        gemini_response = model.generate_content(prompt)
        summary = gemini_response.text
        
        print(f"Generated summary: {len(summary)} characters")
        
        # Save results
        print("Saving results...")
        db.collection('document_content').document(doc_id).set({'full_text': full_text})
        file_doc_ref.update({
            'summary': summary,
            'isChatReady': True,
            'chatStatus': 'ready'
        })
        
        print(f"Successfully processed document {doc_id}")
        return ({"data": {"summary": summary}}, 200, headers)
        
    except Exception as e:
        error_msg = str(e)
        print(f"ERROR processing document {doc_id if doc_id else 'unknown'}: {error_msg}")
        
        if doc_id:
            try:
                db = firestore.Client()
                db.collection('files').document(doc_id).update({'chatStatus': 'failed'})
            except Exception as update_error:
                print(f"Failed to update document status: {update_error}")
        
        return ({"error": {"message": error_msg}}, 500, headers)
