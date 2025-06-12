import os
from google.cloud import firestore, storage
from PIL import Image
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from io import BytesIO

# Initialize the Google Cloud clients
storage_client = storage.Client()
db = firestore.Client()

def process_image_to_pdf(event, context):
    """
    A Cloud Function triggered by a new file upload to Cloud Storage.
    """
    bucket_name = event['bucket']
    file_path = event['name']
    
    # --- 1. Prevent infinite loops and process only new images ---
    if 'processed/' in file_path or not file_path.startswith('uploads/'):
        print(f"Ignoring file: {file_path}")
        return

    print(f"Processing file: {file_path} from bucket: {bucket_name}.")

    source_bucket = storage_client.bucket(bucket_name)
    source_blob = source_bucket.blob(file_path)
    
    # Create a unique temporary filename
    file_name_only = os.path.basename(file_path)
    temp_image_path = f"/tmp/{file_name_only}"

    try:
        # --- 2. Download the uploaded image to a temporary file ---
        source_blob.download_to_filename(temp_image_path)
        print(f"Image downloaded to {temp_image_path}")

        # --- 3. Create the PDF using the temporary file path ---
        image = Image.open(temp_image_path)
        img_width, img_height = image.size
        
        pdf_buffer = BytesIO()
        c = canvas.Canvas(pdf_buffer, pagesize=(img_width, img_height))
        
        # Draw the image using its file path, which reportlab handles correctly
        c.drawImage(temp_image_path, 0, 0, width=img_width, height=img_height)
        c.save()
        pdf_buffer.seek(0)

        # --- 4. Upload the new PDF ---
        new_pdf_name = os.path.splitext(file_name_only)[0] + '.pdf'
        user_id = file_path.split('/')[1]
        destination_blob_name = f"processed/{user_id}/{new_pdf_name}"
        
        destination_blob = source_bucket.blob(destination_blob_name)
        destination_blob.upload_from_file(pdf_buffer, content_type='application/pdf')
        
        print(f"Successfully converted and uploaded PDF to {destination_blob_name}.")

        # --- 5. Update the Firestore document ---
        docs_ref = db.collection('files').where('storagePath', '==', file_path).limit(1)
        docs = docs_ref.stream()

        document_to_update = next(docs, None)
        if document_to_update:
            doc_ref = document_to_update.reference
            doc_ref.update({
                'status': 'Completed',
                'pdfPath': destination_blob_name,
                'processedTimestamp': firestore.SERVER_TIMESTAMP
            })
            print(f"Updated Firestore document: {doc_ref.id}")
        else:
            print(f"Warning: Could not find Firestore document for {file_path}")

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # --- 6. Clean up the temporary file ---
        if os.path.exists(temp_image_path):
            os.remove(temp_image_path)
            print(f"Cleaned up temporary file: {temp_image_path}")