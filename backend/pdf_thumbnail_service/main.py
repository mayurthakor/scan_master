# backend/pdf_thumbnail_service/main.py 

import os
import tempfile
import time
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
    Cloud Function triggered by Cloud Storage events
    Generates thumbnails when PDFs are uploaded to processed/ folder
    """
    print(f"🚀 PDF Thumbnail Service triggered!")
    print(f"📁 Event data: {cloud_event.data}")
    
    try:
        # Extract file information from Cloud Storage event
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        
        print(f"📂 Bucket: {bucket_name}")
        print(f"📄 File: {file_name}")
        
        # Only process PDF files in the processed/ folder
        if not file_name.startswith('processed/') or not file_name.endswith('.pdf'):
            print(f"⏭️ Ignoring file: {file_name} (not a processed PDF)")
            return
        
        print(f"✅ Processing PDF: {file_name}")
        
        # Extract document ID from file path
        # Expected format: processed/userId/timestamp_filename.pdf
        path_parts = file_name.split('/')
        if len(path_parts) < 3:
            print(f"❌ Invalid file path format: {file_name}")
            return
            
        # Get document ID from Firestore metadata or filename
        document_id = _extract_document_id_from_filename(file_name)
        if not document_id:
            print(f"❌ Could not extract document ID from: {file_name}")
            return
        
        print(f"🎯 Document ID: {document_id}")
        
        # Download PDF from Firebase Storage
        bucket = storage_client.bucket(bucket_name)
        pdf_blob = bucket.blob(file_name)
        
        # Download PDF to temporary file
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as temp_pdf:
            print(f"⬇️ Downloading PDF...")
            pdf_blob.download_to_filename(temp_pdf.name)
            temp_pdf_path = temp_pdf.name
            print(f"📁 Downloaded to: {temp_pdf_path}")
        
        try:
            # Generate thumbnail from first page of PDF
            print(f"🎨 Generating thumbnail...")
            thumbnail_data = _generate_thumbnail_from_pdf(temp_pdf_path)
            
            # Upload thumbnail to Firebase Storage
            print(f"☁️ Uploading thumbnail...")
            thumbnail_url = _upload_thumbnail_to_storage(document_id, thumbnail_data)
            
            # Update Firestore document with thumbnail URL
            print(f"💾 Updating Firestore...")
            _update_document_with_thumbnail(document_id, thumbnail_url)
            
            print(f"🎉 Successfully generated thumbnail for {document_id}")
            print(f"🔗 Thumbnail URL: {thumbnail_url}")
            
        finally:
            # Cleanup temporary file
            if os.path.exists(temp_pdf_path):
                os.unlink(temp_pdf_path)
                print(f"🗑️ Cleaned up temporary file")
                
    except Exception as e:
        print(f"❌ Error generating thumbnail: {e}")
        print(f"📍 Error type: {type(e).__name__}")
        # Don't raise exception to avoid function retries


def _extract_document_id_from_filename(file_name):
    """
    Extract document ID from the processed PDF filename
    Strategy: Look up in Firestore using the filename pattern
    """
    try:
        # Extract the filename part
        filename = file_name.split('/')[-1]  # Get last part after /
        print(f"🔍 Looking for document with filename pattern: {filename}")
        
        # Query Firestore to find document with matching filename pattern
        # Look for documents where the storagePath contains this filename
        files_ref = db.collection('files')
        
        # Search by original filename or storage path
        query = files_ref.where('storagePath', '>=', file_name).where('storagePath', '<=', file_name + '\uf8ff').limit(1)
        docs = query.stream()
        
        for doc in docs:
            print(f"✅ Found document: {doc.id}")
            return doc.id
        
        # Fallback: try to find by partial filename match
        query = files_ref.where('status', '==', 'Completed').limit(50)
        docs = query.stream()
        
        for doc in docs:
            doc_data = doc.to_dict()
            if 'pdfPath' in doc_data and filename in doc_data.get('pdfPath', ''):
                print(f"✅ Found document by pdfPath match: {doc.id}")
                return doc.id
        
        print(f"❌ No document found for filename: {filename}")
        return None
        
    except Exception as e:
        print(f"❌ Error extracting document ID: {e}")
        return None


def _generate_thumbnail_from_pdf(pdf_path):
    """Generate thumbnail image from first page of PDF"""
    print(f"🎨 Starting PDF thumbnail generation...")
    print(f"   📂 PDF path: {pdf_path}")
    
    try:
        # Open PDF with PyMuPDF
        print(f"📖 Opening PDF with PyMuPDF...")
        pdf_document = fitz.open(pdf_path)
        
        page_count = pdf_document.page_count
        print(f"   📄 Total pages: {page_count}")
        
        if page_count == 0:
            raise ValueError("PDF has no pages")
        
        # Get first page
        print(f"🎯 Processing first page...")
        first_page = pdf_document[0]
        
        # Get page dimensions
        page_rect = first_page.rect
        page_width = page_rect.width
        page_height = page_rect.height
        aspect_ratio = page_width / page_height
        
        print(f"   📐 Page dimensions: {page_width:.1f} x {page_height:.1f}")
        print(f"   📏 Aspect ratio: {aspect_ratio:.3f}")
        
        # Calculate zoom factor to fit thumbnail size
        zoom_x = THUMBNAIL_SIZE[0] / page_width
        zoom_y = THUMBNAIL_SIZE[1] / page_height
        zoom = min(zoom_x, zoom_y)  # Maintain aspect ratio
        
        print(f"   🔍 Zoom calculation:")
        print(f"      X zoom: {zoom_x:.3f}")
        print(f"      Y zoom: {zoom_y:.3f}")
        print(f"      Final zoom: {zoom:.3f}")
        
        # Create transformation matrix
        matrix = fitz.Matrix(zoom, zoom)
        
        # Render page as image
        print(f"🖼️ Rendering page to image...")
        pix = first_page.get_pixmap(matrix=matrix)
        img_data = pix.tobytes("png")
        
        print(f"   📏 Raw image size: {len(img_data):,} bytes")
        
        # Convert to PIL Image
        print(f"🔄 Converting to PIL Image...")
        pil_image = Image.open(BytesIO(img_data))
        
        print(f"   📐 PIL image size: {pil_image.size}")
        
        # Ensure proper aspect ratio and add professional styling
        print(f"🎨 Adding professional styling...")
        
        # Create a white background canvas
        canvas = Image.new('RGB', THUMBNAIL_SIZE, 'white')
        
        # Calculate positioning to center the image
        img_width, img_height = pil_image.size
        x_offset = (THUMBNAIL_SIZE[0] - img_width) // 2
        y_offset = (THUMBNAIL_SIZE[1] - img_height) // 2
        
        # Paste the image onto the canvas
        canvas.paste(pil_image, (x_offset, y_offset))
        
        # Add subtle border like Adobe Scan
        draw = ImageDraw.Draw(canvas)
        border_color = (200, 200, 200)  # Light gray border
        draw.rectangle([0, 0, THUMBNAIL_SIZE[0]-1, THUMBNAIL_SIZE[1]-1], outline=border_color, width=1)
        
        # Convert to JPEG with compression
        print(f"💾 Compressing to JPEG...")
        output_buffer = BytesIO()
        canvas.save(output_buffer, format='JPEG', quality=THUMBNAIL_QUALITY, optimize=True)
        
        final_size = len(output_buffer.getvalue())
        compression_ratio = (len(img_data) / final_size) if final_size > 0 else 0
        
        print(f"✅ Thumbnail generation completed")
        print(f"   📏 Final size: {final_size:,} bytes ({final_size/1024:.1f} KB)")
        print(f"   📊 Compression ratio: {compression_ratio:.1f}x")
        
        pdf_document.close()
        return output_buffer.getvalue()
        
    except Exception as e:
        print(f"❌ Thumbnail generation failed: {str(e)}")
        print(f"📍 Error type: {type(e).__name__}")
        raise Exception(f"Failed to generate thumbnail: {e}")


def _upload_thumbnail_to_storage(document_id, thumbnail_data):
    """Upload thumbnail to Firebase Storage"""
    print(f"☁️ Uploading thumbnail to Firebase Storage...")
    print(f"   🎯 Document ID: {document_id}")
    print(f"   📏 Data size: {len(thumbnail_data):,} bytes")
    
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        print(f"   📂 Target bucket: {BUCKET_NAME}")
        
        # Create blob path for thumbnail
        thumbnail_path = f"thumbnails/{document_id}_thumbnail.jpg"
        thumbnail_blob = bucket.blob(thumbnail_path)
        print(f"   📁 Thumbnail path: {thumbnail_path}")
        
        # Upload thumbnail
        print(f"⬆️ Starting upload...")
        start_time = time.time()
        
        thumbnail_blob.upload_from_string(
            thumbnail_data,
            content_type='image/jpeg'
        )
        
        upload_time = time.time() - start_time
        print(f"   ⏱️ Upload completed in {upload_time:.3f}s")
        
        # Make it publicly accessible
        print(f"🌐 Making thumbnail publicly accessible...")
        thumbnail_blob.make_public()
        
        public_url = thumbnail_blob.public_url
        print(f"✅ Thumbnail uploaded successfully")
        print(f"   🔗 Public URL: {public_url}")
        
        return public_url
        
    except Exception as e:
        print(f"❌ Upload failed: {str(e)}")
        print(f"📍 Error type: {type(e).__name__}")
        raise Exception(f"Failed to upload thumbnail: {e}")


def _update_document_with_thumbnail(document_id, thumbnail_url):
    """Update Firestore document with thumbnail URL"""
    print(f"💾 Updating Firestore document...")
    print(f"   🎯 Document ID: {document_id}")
    print(f"   🔗 Thumbnail URL: {thumbnail_url}")
    
    try:
        doc_ref = db.collection('files').document(document_id)
        
        print(f"📝 Preparing update data...")
        update_data = {
            'thumbnailUrl': thumbnail_url,
            'hasThumbnail': True,
            'thumbnailGeneratedAt': firestore.SERVER_TIMESTAMP
        }
        print(f"   📋 Update fields: {list(update_data.keys())}")
        
        print(f"⬆️ Executing Firestore update...")
        start_time = time.time()
        
        doc_ref.update(update_data)
        
        update_time = time.time() - start_time
        print(f"✅ Firestore update completed")
        print(f"   ⏱️ Update time: {update_time:.3f}s")
        print(f"   📄 Document {document_id} now has thumbnail URL")
        
    except Exception as e:
        print(f"❌ Firestore update failed: {str(e)}")
        print(f"📍 Error type: {type(e).__name__}")
        raise Exception(f"Failed to update Firestore: {e}")