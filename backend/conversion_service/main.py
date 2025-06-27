# backend/conversion_service/main.py

import os
import subprocess
from google.cloud import firestore, storage, vision
from io import BytesIO
from PIL import Image
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
import functions_framework

# Initialize Google Cloud clients
storage_client = storage.Client()
vision_client = vision.ImageAnnotatorClient()
db = firestore.Client()


def _handle_office_conversion(download_path, temp_dir):
    soffice_path = '/usr/bin/soffice'
    command = [
        soffice_path, '--headless', '--convert-to', 'pdf',
        '--outdir', temp_dir, download_path
    ]
    print(f"Attempting to execute LibreOffice command: {' '.join(command)}")
    try:
        subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    except FileNotFoundError:
        print(f"CRITICAL ERROR: The command '{soffice_path}' was not found.")
        raise
    except subprocess.CalledProcessError as e:
        print(f"LibreOffice conversion failed. Stderr: {e.stderr.decode('utf-8') if e.stderr else 'N/A'}")
        raise
    except subprocess.TimeoutExpired:
        print("LibreOffice command timed out after 60 seconds.")
        raise

    pdf_filename = os.path.splitext(os.path.basename(download_path))[0] + '.pdf'
    output_pdf_path = os.path.join(temp_dir, pdf_filename)
    if not os.path.exists(output_pdf_path):
        raise FileNotFoundError(f"Conversion failed: Output PDF not found at {output_pdf_path}")

    with open(output_pdf_path, 'rb') as f:
        pdf_buffer = BytesIO(f.read())
    pdf_buffer.seek(0)
    os.remove(output_pdf_path)
    return pdf_buffer

def _handle_image_conversion_with_ocr(download_path, temp_dir):
    print(f"Starting OCR processing for image: {download_path}")
    with open(download_path, 'rb') as image_file:
        content = image_file.read()
    
    image = vision.Image(content=content)
    response = vision_client.document_text_detection(image=image)
    document = response.full_text_annotation
    
    if response.error.message:
        raise Exception(f'Vision API Error: {response.error.message}')

    pil_image = Image.open(download_path)
    img_width, img_height = pil_image.size
    pdf_buffer = BytesIO()
    c = canvas.Canvas(pdf_buffer, pagesize=(img_width, img_height))
    c.drawImage(ImageReader(pil_image), 0, 0, width=img_width, height=img_height)
    
    text = c.beginText()
    text.setTextRenderMode(3)
    
    for page in document.pages:
        for block in page.blocks:
            for paragraph in block.paragraphs:
                for word in paragraph.words:
                    for symbol in word.symbols:
                        v = symbol.bounding_box.vertices
                        x = v[0].x
                        y = img_height - v[2].y
                        text.setFont("Helvetica", v[2].y - v[0].y)
                        text.setTextOrigin(x, y)
                        text.textLine(symbol.text)

    c.drawText(text)
    c.showPage()
    c.save()
    
    pdf_buffer.seek(0)
    print(f"Successfully created searchable PDF for {download_path}")
    return pdf_buffer

FILE_HANDLERS = {
    '.jpeg': _handle_image_conversion_with_ocr,
    '.jpg': _handle_image_conversion_with_ocr,
    '.png': _handle_image_conversion_with_ocr,
    '.txt': _handle_office_conversion,
    '.docx': _handle_office_conversion,
    '.csv': _handle_office_conversion,
    '.xlsx': _handle_office_conversion,
    '.pptx': _handle_office_conversion,
}

@functions_framework.cloud_event
def process_file_to_pdf(cloud_event):
    data = cloud_event.data
    bucket_name = data['bucket']
    file_path = data['name']
    
    if 'processed/' in file_path or not file_path.startswith('uploads/'):
        print(f"Ignoring file: {file_path}")
        return

    source_bucket = storage_client.bucket(bucket_name)
    source_blob = source_bucket.blob(file_path)
    
    source_blob.reload()
    metadata = source_blob.metadata or {}
    doc_id = metadata.get('firestoreDocId')

    if not doc_id:
        print(f"Error: Missing 'firestoreDocId' in metadata for file {file_path}. Aborting.") 
        return

    # ADD: Check if document exists before processing
    doc_ref = db.collection('files').document(doc_id)
    try:
        doc_snapshot = doc_ref.get()
        if not doc_snapshot.exists:
            print(f"Document {doc_id} no longer exists, skipping processing")
            return
    except Exception as check_error:
        print(f"Error checking document existence for {doc_id}: {check_error}")
        return

    file_name_only = os.path.basename(file_path)
    _, file_extension = os.path.splitext(file_name_only)
    handler = FILE_HANDLERS.get(file_extension.lower())
    
    if not handler:
        try:
            doc_ref.update({'status': 'Unsupported file type'})
        except Exception as update_error:
            print(f"Could not update document {doc_id} (unsupported type): {update_error}")
        return

    print(f"Processing file: {file_path} for document ID: {doc_id} using handler: {handler.__name__}")
    
    temp_download_path = f"/tmp/{file_name_only}"
    temp_dir = "/tmp"

    try:
        source_blob.download_to_filename(temp_download_path)
        pdf_buffer = handler(temp_download_path, temp_dir)

        new_pdf_name = os.path.splitext(file_name_only)[0] + '.pdf'
        user_id = file_path.split('/')[1]
        destination_blob_name = f"processed/{user_id}/{new_pdf_name}"
        
        destination_blob = source_bucket.blob(destination_blob_name)
        destination_blob.upload_from_file(pdf_buffer, content_type='application/pdf')

        try:
            doc_ref.update({
                'status': 'Completed',
                'pdfPath': destination_blob_name,
                'processedTimestamp': firestore.SERVER_TIMESTAMP
            })
        except Exception as update_error:
            print(f"Could not update document {doc_id} with completion status: {update_error}")
            
    except Exception as e:
        print(f"An error occurred during processing of {file_path}: {e}")
        try:
            doc_ref.update({'status': 'Error', 'errorMessage': str(e)})
        except Exception as update_error:
            print(f"Could not update document {doc_id} with error status: {update_error}")
    finally:
        if os.path.exists(temp_download_path):
            os.remove(temp_download_path)

@functions_framework.http
def health_check(request):
    return 'OK', 200