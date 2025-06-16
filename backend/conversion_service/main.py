# backend/conversion_service/main.py

import os
import subprocess
from google.cloud import firestore, storage
from io import BytesIO

# Initialize Google Cloud clients
storage_client = storage.Client()
db = firestore.Client()


def _handle_office_conversion(download_path, temp_dir):
    """
    Converts a file to PDF using LibreOffice's core executable 'soffice'
    with an absolute path and improved error handling.
    """
    # Use the absolute path for the soffice executable
    soffice_path = '/usr/bin/soffice'
    
    command = [
        soffice_path,
        '--headless',
        '--convert-to',
        'pdf',
        '--outdir',
        temp_dir,
        download_path
    ]
    
    print(f"Attempting to execute command: {' '.join(command)}")
    
    try:
        # Execute the command with detailed error capturing
        subprocess.run(
            command, 
            check=True, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE,
            timeout=60 # Add a timeout
        )
    except FileNotFoundError:
        print(f"CRITICAL ERROR: The command '{soffice_path}' was not found. The container build likely failed to install LibreOffice correctly.")
        raise
    except subprocess.CalledProcessError as e:
        # This will print the specific error message from the LibreOffice command
        print(f"LibreOffice conversion failed with return code {e.returncode}")
        print(f"Stderr: {e.stderr.decode('utf-8') if e.stderr else 'N/A'}")
        raise
    except subprocess.TimeoutExpired:
        print("LibreOffice command timed out after 60 seconds.")
        raise

    # Construct the expected output path and read the converted PDF into memory
    pdf_filename = os.path.splitext(os.path.basename(download_path))[0] + '.pdf'
    output_pdf_path = os.path.join(temp_dir, pdf_filename)
    
    if not os.path.exists(output_pdf_path):
        raise FileNotFoundError(f"Conversion failed: Output PDF not found at {output_pdf_path}")

    with open(output_pdf_path, 'rb') as f:
        pdf_buffer = BytesIO(f.read())
    
    pdf_buffer.seek(0)
    os.remove(output_pdf_path) # Clean up the generated PDF from the temp directory
    return pdf_buffer


# The handlers map file extensions to the conversion function
FILE_HANDLERS = {
    '.jpeg': _handle_office_conversion,
    '.jpg': _handle_office_conversion,
    '.png': _handle_office_conversion,
    '.txt': _handle_office_conversion,
    '.docx': _handle_office_conversion,
    '.csv': _handle_office_conversion,
    '.xlsx': _handle_office_conversion,
    '.pptx': _handle_office_conversion,
}


def process_file_to_pdf(event, context):
    bucket_name = event['bucket']
    file_path = event['name']
    
    if 'processed/' in file_path or not file_path.startswith('uploads/'):
        print(f"Ignoring file: {file_path}")
        return

    metadata = event.get('metadata', {})
    doc_id = metadata.get('firestoreDocId')

    if not doc_id:
        print(f"Error: Missing 'firestoreDocId' in metadata for file {file_path}. Aborting.")
        return

    file_name_only = os.path.basename(file_path)
    _, file_extension = os.path.splitext(file_name_only)
    handler = FILE_HANDLERS.get(file_extension.lower())
    
    if not handler:
        print(f"Unsupported file type: {file_extension}. Ignoring.")
        return

    print(f"Processing file: {file_path} for document ID: {doc_id}")
    
    source_bucket = storage_client.bucket(bucket_name)
    source_blob = source_bucket.blob(file_path)
    temp_download_path = f"/tmp/{file_name_only}"
    temp_dir = "/tmp"

    try:
        source_blob.download_to_filename(temp_download_path)
        print(f"File downloaded to {temp_download_path}")
        
        pdf_buffer = handler(temp_download_path, temp_dir)

        new_pdf_name = os.path.splitext(file_name_only)[0] + '.pdf'
        user_id = file_path.split('/')[1]
        destination_blob_name = f"processed/{user_id}/{new_pdf_name}"
        
        destination_blob = source_bucket.blob(destination_blob_name)
        destination_blob.upload_from_file(pdf_buffer, content_type='application/pdf')
        print(f"Successfully converted and uploaded PDF to {destination_blob_name}.")

        doc_ref = db.collection('files').document(doc_id)
        doc_ref.update({
            'status': 'Completed',
            'pdfPath': destination_blob_name,
            'processedTimestamp': firestore.SERVER_TIMESTAMP
        })
        print(f"Successfully updated Firestore document: {doc_ref.id}")

    except Exception as e:
        print(f"An error occurred during processing of {file_path}: {e}")
    finally:
        if os.path.exists(temp_download_path):
            os.remove(temp_download_path)
            print(f"Cleaned up temporary file: {temp_download_path}")