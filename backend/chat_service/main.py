# backend/chat_service/main.py  
import os
import functions_framework
import firebase_admin
from firebase_admin import firestore, auth
import google.generativeai as genai

# Initialize Firebase Admin (only once)
if not firebase_admin._apps:
    firebase_admin.initialize_app()

@functions_framework.http
def chat_with_document(request):
    # Handle CORS
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Manual authentication check  (NO App Check)
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return ({"error": {"message": "Unauthorized"}}, 401, headers)
        
        id_token = auth_header.split('Bearer ')[1]
        decoded_token = auth.verify_id_token(id_token)
        user_id = decoded_token['uid']
        
        # Get request data
        request_data = request.get_json()['data']
        doc_id = request_data['documentId']
        user_question = request_data['question']
        
        if not doc_id or not user_question:
            raise ValueError("Missing 'documentId' or 'question'.")
        
        print(f"Chat request - User: {user_id}, Doc: {doc_id}, Question: {user_question[:50]}...")
        
        # Initialize Firestore
        db = firestore.Client()
        
        # Verify user owns the document
        file_doc_ref = db.collection('files').document(doc_id)
        file_doc = file_doc_ref.get()
        
        if not file_doc.exists:
            raise FileNotFoundError(f"Document {doc_id} not found.")
        
        file_data = file_doc.to_dict()
        if file_data.get('userId') != user_id:
            return ({"error": {"message": "Forbidden"}}, 403, headers)
        
        # Get the document content
        content_doc_ref = db.collection('document_content').document(doc_id)
        content_doc = content_doc_ref.get()
        
        if not content_doc.exists:
            raise FileNotFoundError(f"No content found for document {doc_id}.")
        
        full_text = content_doc.to_dict().get('full_text', '')
        
        if not full_text:
            return ({
                "data": {"answer": "I could not find any text content for this document."}
            }, 200, headers)
        
        # Get Gemini API key from environment variable
        api_key = os.environ.get('GEMINI_API_KEY')
        if not api_key:
            raise ValueError("GEMINI_API_KEY environment variable not set")
        
        # Configure Gemini
        genai.configure(api_key=api_key)
        model = genai.GenerativeModel('gemini-1.5-pro-latest')
        
        # Create prompt for answering question
        prompt = f"""
Based *only* on the content of the document provided below, answer the user's question.
If the answer cannot be found in the document, say "I could not find an answer to that in this document."

DOCUMENT CONTENT:
---
{full_text}
---

USER'S QUESTION: {user_question}

ANSWER:"""
        
        print("Generating answer with Gemini...")
        response = model.generate_content(prompt)
        answer = response.text
        
        answer_preview = answer[:50] + "..." if len(answer) > 50 else answer
        print(f"Generated answer: {answer_preview}")
        
        return ({"data": {"answer": answer}}, 200, headers)
        
    except Exception as e:
        print(f"ERROR in chat: {e}")
        return ({"error": {"message": str(e)}}, 500, headers)# Test change for environment variables
# Testing fixed conditionals
# Debug enhanced conditionals
# Testing clean matrix without secrets 14
# Testing fixed workflow final