// lib/screens/document_scanner_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:scan_master/services/edge_detection_service.dart';
import 'package:scan_master/screens/document_preview_screen.dart';

class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({super.key});

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  bool _isFlashOn = false;
  bool _isCapturing = false;
  bool _isAutoDetectEnabled = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission
      final cameraStatus = await Permission.camera.request();
      if (cameraStatus != PermissionStatus.granted) {
        setState(() {
          _error = 'Camera permission is required to scan documents';
        });
        return;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'No cameras found on this device';
        });
        return;
      }

      // Initialize camera controller with back camera (preferred for documents)
      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      setState(() {
        _isCameraInitialized = true;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null) return;
    
    try {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
      
      await _cameraController!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      print('Error toggling flash: $e');
    }
  }

  Future<void> _captureDocument() async {
    if (_cameraController == null || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      // Turn off flash before capture
      if (_isFlashOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
      }

      final image = await _cameraController!.takePicture();
      
      if (mounted) {
        // Show captured image with edge detection
        await _showDocumentPreview(image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to capture image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isCapturing = false;
      });
      
      // Restore flash state
      if (_isFlashOn && _cameraController != null) {
        await _cameraController!.setFlashMode(FlashMode.torch);
      }
    }
  }

  Future<void> _showDocumentPreview(String imagePath) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => DocumentPreviewScreen(
          imagePath: imagePath,
          autoDetectEnabled: _isAutoDetectEnabled,
        ),
      ),
    );

    if (result != null) {
      // Return the processed image path to the previous screen
      Navigator.of(context).pop(result);
    }
  }

  Future<String> _processImage(String imagePath) async {
    try {
      // Read the image
      final imageFile = File(imagePath);
      final bytes = await imageFile.readAsBytes();
      
      // Decode image
      img.Image? image = img.decodeImage(bytes);
      if (image == null) throw Exception('Could not decode image');

      // Basic image processing
      // 1. Auto-rotate based on EXIF data
      image = img.bakeOrientation(image);
      
      // 2. Enhance contrast and brightness for document scanning
      image = _enhanceDocumentImage(image);
      
      // 3. Resize if too large (max 2048px on longer side)
      final maxDimension = 2048;
      if (image.width > maxDimension || image.height > maxDimension) {
        if (image.width > image.height) {
          image = img.copyResize(image, width: maxDimension);
        } else {
          image = img.copyResize(image, height: maxDimension);
        }
      }

      // Save processed image
      final directory = await getTemporaryDirectory();
      final processedPath = '${directory.path}/scanned_doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final processedFile = File(processedPath);
      await processedFile.writeAsBytes(img.encodeJpg(image, quality: 90));
      
      return processedPath;
    } catch (e) {
      print('Error processing image: $e');
      // Return original path if processing fails
      return imagePath;
    }
  }

  img.Image _enhanceDocumentImage(img.Image image) {
    // Simple document enhancement without complex convolution
    // Adjust contrast and brightness for better document readability
    image = img.adjustColor(image, 
      contrast: 1.3,        // Increase contrast for sharper text
      brightness: 1.1,      // Slight brightness boost
      saturation: 0.7,      // Desaturate for document-like appearance
    );
    
    return image;
  }

  Widget _buildCameraPreview() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.red),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isCameraInitialized || _cameraController == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing camera...'),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // Camera preview
        Positioned.fill(
          child: CameraPreview(_cameraController!),
        ),
        
        // Document frame overlay
        Positioned.fill(
          child: CustomPaint(
            painter: DocumentFramePainter(),
          ),
        ),
        
        // Instructions overlay
        Positioned(
          top: 50,
          left: 20,
          right: 20,
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _isAutoDetectEnabled 
                ? 'Auto-detect: ON\nPosition document within frame for automatic detection'
                : 'Auto-detect: OFF\nPosition document and tap capture',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Scan Document'),
        actions: [
          if (_isCameraInitialized)
            IconButton(
              icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
              onPressed: _toggleFlash,
            ),
          if (_isCameraInitialized)
            IconButton(
              icon: Icon(_isAutoDetectEnabled 
                ? Icons.auto_awesome 
                : Icons.auto_awesome_outlined),
              onPressed: () {
                setState(() {
                  _isAutoDetectEnabled = !_isAutoDetectEnabled;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_isAutoDetectEnabled 
                      ? 'Auto-detect enabled' 
                      : 'Auto-detect disabled'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
        ],
      ),
      body: _buildCameraPreview(),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(20),
        color: Colors.black,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Gallery button
            IconButton(
              onPressed: () async {
                // Fallback to image picker
                Navigator.of(context).pop('use_gallery');
              },
              icon: Icon(Icons.photo_library, color: Colors.white, size: 32),
            ),
            
            // Capture button
            GestureDetector(
              onTap: _isCapturing ? null : _captureDocument,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isCapturing ? Colors.grey : Colors.white,
                  border: Border.all(color: Colors.grey, width: 3),
                ),
                child: _isCapturing
                    ? Center(child: CircularProgressIndicator())
                    : Icon(Icons.camera_alt, size: 32, color: Colors.black),
              ),
            ),
            
            // Settings/Help button
            IconButton(
              onPressed: () {
                _showHelpDialog();
              },
              icon: Icon(Icons.help_outline, color: Colors.white, size: 32),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Scanning Tips'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Ensure good lighting'),
            Text('• Keep the document flat'),
            Text('• Avoid shadows and reflections'),
            Text('• Position the document within the frame'),
            Text('• Hold the device steady'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// Custom painter for document frame overlay
class DocumentFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Calculate frame dimensions (A4-like ratio)
    final frameWidth = size.width * 0.8;
    final frameHeight = frameWidth * 1.4; // Roughly A4 ratio
    
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;

    // Draw corner brackets
    final cornerLength = 30.0;
    
    // Top-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top)
        ..lineTo(left + cornerLength, top),
      paint,
    );
    
    // Top-right corner
    canvas.drawPath(
      Path()
        ..moveTo(left + frameWidth - cornerLength, top)
        ..lineTo(left + frameWidth, top)
        ..lineTo(left + frameWidth, top + cornerLength),
      paint,
    );
    
    // Bottom-left corner
    canvas.drawPath(
      Path()
        ..moveTo(left, top + frameHeight - cornerLength)
        ..lineTo(left, top + frameHeight)
        ..lineTo(left + cornerLength, top + frameHeight),
      paint,
    );
    
    // Bottom-right corner
    canvas.drawPath(
      Path()
        ..moveTo(left + frameWidth - cornerLength, top + frameHeight)
        ..lineTo(left + frameWidth, top + frameHeight)
        ..lineTo(left + frameWidth, top + frameHeight - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}