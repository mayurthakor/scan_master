# backend/pdf_thumbnail_service/main.py

import os
import tempfile
from io import BytesIO
from google.cloud import storage, firestore
from PIL import Image, ImageDraw
import fitz  # PyMuPDF for PDF processing
import functions_framework

# Initialize clients
storage_client = storage.Client()
db = firestore.Client()

# Configuration
THUMBNAIL_SIZE = (200, 280)  # Similar to Adobe Scan aspect ratio
THUMBNAIL_QUALITY = 85
BUCKET_NAME = 'scan-master-app.firebasestorage.app'

@functions_framework.cloud_event
def generate_pdf_thumbnail(cloud_event):
    """
    Event-driven Cloud Function triggered by PDF upload
    Automatically generates thumbnails when PDFs are created in processed/ folder
    """
    try:
        data = cloud_event.data
        bucket_name = data['bucket']
        file_path = data['name']
        
        print(f"Cloud Storage event received for: {file_path}")
        
        # Only process PDFs in the processed/ folder
        if not file_path.startswith('processed/') or not file_path.endswith('.pdf'):
            print(f"Ignoring file (not a processed PDF): {file_path}")
            return
        
        # Extract document ID from file metadata
        source_bucket = storage_client.bucket(bucket_name)
        pdf_blob = source_bucket.blob(file_path)
        
        # Reload to get latest metadata
        pdf_blob.reload()
        metadata = pdf_blob.metadata or {}
        doc_id = metadata.get('firestoreDocId')
        
        if not doc_id:
            print(f"No firestoreDocId found in metadata for {file_path}")
            return
        
        print(f"Generating thumbnail for document: {doc_id}")
        
        # Check if document still exists in Firestore
        doc_ref = db.collection('files').document(doc_id)
        try:
            doc_snapshot = doc_ref.get()
            if not doc_snapshot.exists:
                print(f"Document {doc_id} no longer exists, skipping thumbnail generation")
                return
        except Exception as check_error:
            print(f"Error checking document existence for {doc_id}: {check_error}")
            return
        
        # Download PDF to temporary file
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as temp_pdf:
            pdf_blob.download_to_filename(temp_pdf.name)
            temp_pdf_path = temp_pdf.name
        
        try:
            # Generate thumbnail from first page of PDF
            thumbnail_data = _generate_thumbnail_from_pdf(temp_pdf_path)
            
            # Upload thumbnail to Firebase Storage
            thumbnail_url = _upload_thumbnail_to_storage(doc_id, thumbnail_data)
            
            # Update Firestore document with thumbnail URL
            _update_document_with_thumbnail(doc_id, thumbnail_url)
            
            print(f"Successfully generated thumbnail for {doc_id}")
            
        finally:
            # Cleanup temporary file
            if os.path.exists(temp_pdf_path):
                os.unlink(temp_pdf_path)
                
    except Exception as e:
        print(f"Error in thumbnail generation: {e}")
        # Don't raise exception - let other processes continue


def _generate_thumbnail_from_pdf(pdf_path):
    """Generate thumbnail image from first page of PDF"""
    try:
        # Open PDF with PyMuPDF
        pdf_document = fitz.open(pdf_path)
        
        if pdf_document.page_count == 0:
            raise ValueError("PDF has no pages")
        
        # Get first page
        first_page = pdf_document[0]
        
        # Calculate zoom factor to fit thumbnail size
        page_rect = first_page.rect
        zoom_x = THUMBNAIL_SIZE[0] / page_rect.width
        zoom_y = THUMBNAIL_SIZE[1] / page_rect.height
        zoom = min(zoom_x, zoom_y)  # Maintain aspect ratio
        
        # Create transformation matrix
        mat = fitz.Matrix(zoom, zoom)
        
        # Render page to image
        pix = first_page.get_pixmap(matrix=mat, alpha=False)
        img_data = pix.tobytes("png")
        
        # Open with PIL for final processing
        img = Image.open(BytesIO(img_data))
        
        # Create final thumbnail with white background
        thumbnail = Image.new('RGB', THUMBNAIL_SIZE, 'white')
        
        # Center the image on the thumbnail
        img_width, img_height = img.size
        x_offset = (THUMBNAIL_SIZE[0] - img_width) // 2
        y_offset = (THUMBNAIL_SIZE[1] - img_height) // 2
        
        thumbnail.paste(img, (x_offset, y_offset))
        
        # Add subtle border (like Adobe Scan)
        draw = ImageDraw.Draw(thumbnail)
        draw.rectangle(
            [(0, 0), (THUMBNAIL_SIZE[0]-1, THUMBNAIL_SIZE[1]-1)], 
            outline='#E0E0E0', 
            width=1
        )
        
        # Convert to bytes
        output_buffer = BytesIO()
        thumbnail.save(output_buffer, format='JPEG', quality=THUMBNAIL_QUALITY, optimize=True)
        
        pdf_document.close()
        return output_buffer.getvalue()
        
    except Exception as e:
        raise Exception(f"Failed to generate thumbnail: {e}")


def _upload_thumbnail_to_storage(document_id, thumbnail_data):
    """Upload thumbnail to Firebase Storage"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Create blob path for thumbnail
        thumbnail_path = f"thumbnails/{document_id}_thumbnail.jpg"
        thumbnail_blob = bucket.blob(thumbnail_path)
        
        # Upload thumbnail
        thumbnail_blob.upload_from_string(
            thumbnail_data,
            content_type='image/jpeg'
        )
        
        # Make it publicly accessible
        thumbnail_blob.make_public()
        
        print(f"Uploaded thumbnail to: {thumbnail_path}")
        return thumbnail_blob.public_url
        
    except Exception as e:
        raise Exception(f"Failed to upload thumbnail: {e}")


def _update_document_with_thumbnail(document_id, thumbnail_url):
    """Update Firestore document with thumbnail URL"""
    try:
        doc_ref = db.collection('files').document(document_id)
        doc_ref.update({
            'thumbnailUrl': thumbnail_url,
            'hasThumbnail': True,
            'thumbnailGeneratedAt': firestore.SERVER_TIMESTAMP
        })
        print(f"Updated document {document_id} with thumbnail URL")
        
    except Exception as e:
        raise Exception(f"Failed to update Firestore: {e}")


# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """Health check endpoint"""
    return 'Thumbnail service OK', 200