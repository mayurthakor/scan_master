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

@functions_framework.http
def generate_pdf_thumbnail(request):
    """
    Cloud Function to generate PDF thumbnails 
    Triggered after PDF conversion is complete
    """
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    }
    
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        data = request.get_json()
        document_id = data.get('documentId')
        pdf_url = data.get('pdfUrl')  # Firebase Storage URL
        
        if not document_id or not pdf_url:
            return (jsonify({'error': 'Missing documentId or pdfUrl'}), 400, headers)
        
        print(f"Generating thumbnail for document: {document_id}")
        
        # Download PDF from Firebase Storage
        pdf_blob_path = _extract_blob_path_from_url(pdf_url)
        bucket = storage_client.bucket(BUCKET_NAME)
        pdf_blob = bucket.blob(pdf_blob_path)
        
        # Download PDF to temporary file
        with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as temp_pdf:
            pdf_blob.download_to_filename(temp_pdf.name)
            temp_pdf_path = temp_pdf.name
        
        try:
            # Generate thumbnail from first page of PDF
            thumbnail_data = _generate_thumbnail_from_pdf(temp_pdf_path)
            
            # Upload thumbnail to Firebase Storage
            thumbnail_url = _upload_thumbnail_to_storage(document_id, thumbnail_data)
            
            # Update Firestore document with thumbnail URL
            _update_document_with_thumbnail(document_id, thumbnail_url)
            
            print(f"Successfully generated thumbnail for {document_id}")
            return (jsonify({
                'success': True,
                'thumbnailUrl': thumbnail_url,
                'documentId': document_id
            }), 200, headers)
            
        finally:
            # Cleanup temporary file
            if os.path.exists(temp_pdf_path):
                os.unlink(temp_pdf_path)
                
    except Exception as e:
        print(f"Error generating thumbnail: {e}")
        return (jsonify({'error': str(e)}), 500, headers)


def _extract_blob_path_from_url(firebase_url):
    """Extract blob path from Firebase Storage URL"""
    # Example URL: https://firebasestorage.googleapis.com/v0/b/bucket/o/path%2Fto%2Ffile.pdf
    import urllib.parse
    
    try:
        # Parse the URL to get the object path
        parts = firebase_url.split('/o/')
        if len(parts) > 1:
            encoded_path = parts[1].split('?')[0]  # Remove query parameters
            return urllib.parse.unquote(encoded_path)
        else:
            raise ValueError("Invalid Firebase Storage URL format")
    except Exception as e:
        raise ValueError(f"Failed to parse Firebase URL: {e}")


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
        mat = fitz.Matrix(zoom, zoom)
        print(f"   🎯 Transformation matrix: {mat}")
        
        # Render page to image
        print(f"🖼️ Rendering page to image...")
        start_time = time.time()
        
        pix = first_page.get_pixmap(matrix=mat, alpha=False)
        img_data = pix.tobytes("png")
        
        render_time = time.time() - start_time
        print(f"   ⏱️ Render time: {render_time:.3f}s")
        print(f"   📏 Raw image size: {len(img_data):,} bytes")
        
        # Open with PIL for final processing
        print(f"🎨 Processing with PIL...")
        img = Image.open(BytesIO(img_data))
        
        img_width, img_height = img.size
        print(f"   📐 Rendered dimensions: {img_width} x {img_height}")
        
        # Create final thumbnail with white background
        print(f"🎭 Creating final thumbnail...")
        thumbnail = Image.new('RGB', THUMBNAIL_SIZE, 'white')
        
        # Center the image on the thumbnail
        x_offset = (THUMBNAIL_SIZE[0] - img_width) // 2
        y_offset = (THUMBNAIL_SIZE[1] - img_height) // 2
        
        print(f"   📍 Centering offset: ({x_offset}, {y_offset})")
        
        thumbnail.paste(img, (x_offset, y_offset))
        
        # Add subtle border (like Adobe Scan)
        print(f"🖊️ Adding border...")
        draw = ImageDraw.Draw(thumbnail)
        draw.rectangle(
            [(0, 0), (THUMBNAIL_SIZE[0]-1, THUMBNAIL_SIZE[1]-1)], 
            outline='#E0E0E0', 
            width=1
        )
        
        # Convert to bytes
        print(f"💾 Converting to JPEG...")
        output_buffer = BytesIO()
        thumbnail.save(output_buffer, format='JPEG', quality=THUMBNAIL_QUALITY, optimize=True)
        
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