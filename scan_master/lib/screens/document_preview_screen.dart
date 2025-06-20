// lib/screens/document_preview_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:scan_master/services/edge_detection_service.dart';

class DocumentPreviewScreen extends StatefulWidget {
  final String imagePath;
  final bool autoDetectEnabled;

  const DocumentPreviewScreen({
    super.key,
    required this.imagePath,
    required this.autoDetectEnabled,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  List<Point>? _detectedCorners;
  bool _isProcessing = false;
  bool _isEdgeDetectionDone = false;
  String? _croppedImagePath;

  @override
  void initState() {
    super.initState();
    if (widget.autoDetectEnabled) {
      _performEdgeDetection();
    }
  }

  Future<void> _performEdgeDetection() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final corners = await EdgeDetectionService.detectDocumentEdges(widget.imagePath);
      
      setState(() {
        _detectedCorners = corners;
        _isProcessing = false;
        _isEdgeDetectionDone = true;
      });

      if (corners != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document edges detected! Adjust if needed.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not detect edges automatically. Use manual mode.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _isEdgeDetectionDone = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Edge detection failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cropDocument() async {
    if (_detectedCorners == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No corners detected. Please try manual selection.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final croppedPath = await EdgeDetectionService.cropDocument(
        widget.imagePath,
        _detectedCorners!,
      );

      setState(() {
        _croppedImagePath = croppedPath;
        _isProcessing = false;
      });

      if (croppedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document cropped successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cropping failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _useOriginalImage() {
    Navigator.of(context).pop(widget.imagePath);
  }

  void _useCroppedImage() {
    if (_croppedImagePath != null) {
      Navigator.of(context).pop(_croppedImagePath);
    }
  }

  void _retakePhoto() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Document Preview'),
        actions: [
          if (!_isProcessing)
            TextButton(
              onPressed: widget.autoDetectEnabled && !_isEdgeDetectionDone
                  ? _performEdgeDetection
                  : null,
              child: Text(
                'Detect',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Image preview area
          Expanded(
            child: Container(
              width: double.infinity,
              child: _isProcessing
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            _isEdgeDetectionDone ? 'Processing document...' : 'Detecting edges...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        // Display current image (original or cropped)
                        Positioned.fill(
                          child: Image.file(
                            File(_croppedImagePath ?? widget.imagePath),
                            fit: BoxFit.contain,
                          ),
                        ),
                        
                        // Corner overlay for original image
                        if (_croppedImagePath == null && _detectedCorners != null)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: CornerOverlayPainter(_detectedCorners!),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          
          // Status information
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                if (_detectedCorners != null && _croppedImagePath == null)
                  Text(
                    'Document edges detected. Tap "Crop" to extract the document.',
                    style: TextStyle(color: Colors.green, fontSize: 14),
                    textAlign: TextAlign.center,
                  )
                else if (_croppedImagePath != null)
                  Text(
                    'Document cropped and enhanced. Ready to upload!',
                    style: TextStyle(color: Colors.green, fontSize: 14),
                    textAlign: TextAlign.center,
                  )
                else if (_isEdgeDetectionDone)
                  Text(
                    'Could not detect document edges automatically. You can still use the original image.',
                    style: TextStyle(color: Colors.orange, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
          
          // Action buttons
          Container(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Retake button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _retakePhoto,
                      icon: Icon(Icons.camera_alt, color: Colors.white, size: 32),
                    ),
                    Text('Retake', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
                
                // Crop button
                if (_detectedCorners != null && _croppedImagePath == null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _isProcessing ? null : _cropDocument,
                        icon: Icon(Icons.crop, color: Colors.blue, size: 32),
                      ),
                      Text('Crop', style: TextStyle(color: Colors.blue, fontSize: 12)),
                    ],
                  ),
                
                // Use original button
                if (_croppedImagePath == null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _useOriginalImage,
                        icon: Icon(Icons.check_circle, color: Colors.green, size: 32),
                      ),
                      Text('Use Original', style: TextStyle(color: Colors.green, fontSize: 12)),
                    ],
                  ),
                
                // Use cropped button
                if (_croppedImagePath != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: _useCroppedImage,
                        icon: Icon(Icons.check_circle, color: Colors.green, size: 32),
                      ),
                      Text('Use Cropped', style: TextStyle(color: Colors.green, fontSize: 12)),
                    ],
                  ),
                
                // Manual adjust button (placeholder for future feature)
                if (_detectedCorners != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Manual adjustment coming soon!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: Icon(Icons.tune, color: Colors.orange, size: 32),
                      ),
                      Text('Adjust', style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Custom painter to draw corner overlays
class CornerOverlayPainter extends CustomPainter {
  final List<Point> corners;

  CornerOverlayPainter(this.corners);

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    // Get image widget bounds
    final imageAspectRatio = size.width / size.height;
    
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final cornerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.red.withOpacity(0.8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Draw lines connecting corners
    final path = Path();
    
    // Scale corners to fit the display area
    final scaledCorners = corners.map((corner) {
      // Assume the image fills the available space proportionally
      return Offset(
        corner.x * size.width / 1000, // Approximate scaling
        corner.y * size.height / 1000,
      );
    }).toList();

    if (scaledCorners.isNotEmpty) {
      path.moveTo(scaledCorners[0].dx, scaledCorners[0].dy);
      for (int i = 1; i < scaledCorners.length; i++) {
        path.lineTo(scaledCorners[i].dx, scaledCorners[i].dy);
      }
      path.close();
      
      canvas.drawPath(path, linePaint);

      // Draw corner circles
      for (int i = 0; i < scaledCorners.length; i++) {
        canvas.drawCircle(scaledCorners[i], 12, cornerPaint);
        
        // Draw white center
        canvas.drawCircle(scaledCorners[i], 8, Paint()..color = Colors.white);
        
        // Draw corner number
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            scaledCorners[i].dx - textPainter.width / 2,
            scaledCorners[i].dy - textPainter.height / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}