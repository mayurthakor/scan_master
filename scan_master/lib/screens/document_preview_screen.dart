// lib/screens/enhanced_document_preview_screen.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/document_type_recognition_service.dart';
import '../services/image_processing_service.dart';
import '../services/edge_detection_service.dart';

class EnhancedDocumentPreviewScreen extends StatefulWidget {
  final String imagePath;
  final Function(String processedImagePath) onDocumentProcessed;

  const EnhancedDocumentPreviewScreen({
    super.key,
    required this.imagePath,
    required this.onDocumentProcessed,
  });

  @override
  State<EnhancedDocumentPreviewScreen> createState() =>
      _EnhancedDocumentPreviewScreenState();
}

class _EnhancedDocumentPreviewScreenState
    extends State<EnhancedDocumentPreviewScreen> {
  ui.Image? _decodedImage;
  EdgeDetectionResult? _detectionResult;
  List<Offset> _currentCorners = [];
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isManualMode = false;
  int? _selectedCornerIndex;
  
  final EdgeDetectionService _edgeDetectionService = EdgeDetectionService();
  
  // Transform matrix for coordinate mapping
  late Matrix4 _imageToScreenTransform;
  late Matrix4 _screenToImageTransform;
  late Size _imageDisplaySize;
  late Offset _imageDisplayOffset;

  @override
  void initState() {
    super.initState();
    _initializePreview();
  }

  Future<void> _initializePreview() async {
    try {
      await _loadImage();
      await _performEdgeDetection();
    } catch (e) {
      print('Error initializing preview: $e');
      _showErrorDialog('Failed to load image: $e');
    }
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    
    setState(() {
      _decodedImage = frame.image;
    });
  }

  Future<void> _performEdgeDetection() async {
    if (_decodedImage == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final imageSize = Size(
        _decodedImage!.width.toDouble(),
        _decodedImage!.height.toDouble(),
      );

      _detectionResult = await _edgeDetectionService.detectDocumentEdges(
        imagePath: widget.imagePath,
        imageSize: imageSize,
      );

      setState(() {
        _currentCorners = _detectionResult!.corners;
        _isManualMode = _detectionResult!.requiresManualAdjustment;
        _isLoading = false;
      });

      // Show detection result info
      _showDetectionInfo();
    } catch (e) {
      print('Edge detection error: $e');
      setState(() {
        _isLoading = false;
        _isManualMode = true;
        _currentCorners = _getDefaultCorners();
      });
      _showErrorDialog('Edge detection failed. You can adjust corners manually.');
    }
  }

  List<Offset> _getDefaultCorners() {
    if (_decodedImage == null) return [];
    
    final imageSize = Size(
      _decodedImage!.width.toDouble(),
      _decodedImage!.height.toDouble(),
    );
    
    final margin = 0.1;
    return [
      Offset(imageSize.width * margin, imageSize.height * margin),
      Offset(imageSize.width * (1 - margin), imageSize.height * margin),
      Offset(imageSize.width * (1 - margin), imageSize.height * (1 - margin)),
      Offset(imageSize.width * margin, imageSize.height * (1 - margin)),
    ];
  }

  void _showDetectionInfo() {
    if (_detectionResult == null) return;
    
    final result = _detectionResult!;
    String message = 'Detection Method: ${result.method}\n'
                    'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%';
    
    if (result.requiresManualAdjustment) {
      message += '\n\nLow confidence detected. Please adjust corners manually.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        backgroundColor: result.confidence > 0.6 ? Colors.green : Colors.orange,
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _calculateTransformMatrices(Size screenSize) {
    if (_decodedImage == null) return;

    final imageSize = Size(
      _decodedImage!.width.toDouble(),
      _decodedImage!.height.toDouble(),
    );

    // Calculate how the image fits in the screen
    final screenAspectRatio = screenSize.width / screenSize.height;
    final imageAspectRatio = imageSize.width / imageSize.height;

    double scale;
    if (imageAspectRatio > screenAspectRatio) {
      // Image is wider than screen ratio
      scale = screenSize.width / imageSize.width;
      _imageDisplaySize = Size(screenSize.width, imageSize.height * scale);
    } else {
      // Image is taller than screen ratio
      scale = screenSize.height / imageSize.height;
      _imageDisplaySize = Size(imageSize.width * scale, screenSize.height);
    }

    // Calculate offset to center the image
    _imageDisplayOffset = Offset(
      (screenSize.width - _imageDisplaySize.width) / 2,
      (screenSize.height - _imageDisplaySize.height) / 2,
    );

    // Create transformation matrices
    _imageToScreenTransform = Matrix4.identity()
      ..translate(_imageDisplayOffset.dx, _imageDisplayOffset.dy)
      ..scale(scale, scale);

    _screenToImageTransform = Matrix4.identity()
      ..scale(1 / scale, 1 / scale)
      ..translate(-_imageDisplayOffset.dx / scale, -_imageDisplayOffset.dy / scale);
  }

  Offset _imageToScreen(Offset imagePoint) {
    final transformedX = _imageDisplayOffset.dx + imagePoint.dx * (_imageDisplaySize.width / _decodedImage!.width);
    final transformedY = _imageDisplayOffset.dy + imagePoint.dy * (_imageDisplaySize.height / _decodedImage!.height);
    return Offset(transformedX, transformedY);
  }

  Offset _screenToImage(Offset screenPoint) {
    final adjustedPoint = Offset(
      screenPoint.dx - _imageDisplayOffset.dx,
      screenPoint.dy - _imageDisplayOffset.dy,
    );
    
    final scale = _imageDisplaySize.width / _decodedImage!.width;
    final imageX = adjustedPoint.dx / scale;
    final imageY = adjustedPoint.dy / scale;
    
    return Offset(imageX, imageY);
  }

  void _onPanStart(DragStartDetails details) {
    if (!_isManualMode) return;

    final screenPoint = details.localPosition;
    final imagePoint = _screenToImage(screenPoint);

    // Find the closest corner
    double minDistance = double.infinity;
    int? closestCornerIndex;

    for (int i = 0; i < _currentCorners.length; i++) {
      final cornerScreen = _imageToScreen(_currentCorners[i]);
      final distance = (cornerScreen - screenPoint).distance;
      
      if (distance < 50.0 && distance < minDistance) { // 50 pixel touch tolerance
        minDistance = distance;
        closestCornerIndex = i;
      }
    }

    setState(() {
      _selectedCornerIndex = closestCornerIndex;
    });

    if (_selectedCornerIndex != null) {
      HapticFeedback.lightImpact();
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_isManualMode || _selectedCornerIndex == null) return;

    final screenPoint = details.localPosition;
    final imagePoint = _screenToImage(screenPoint);

    // Clamp to image boundaries
    final clampedImagePoint = Offset(
      imagePoint.dx.clamp(0.0, _decodedImage!.width.toDouble()),
      imagePoint.dy.clamp(0.0, _decodedImage!.height.toDouble()),
    );

    setState(() {
      _currentCorners[_selectedCornerIndex!] = clampedImagePoint;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _selectedCornerIndex = null;
    });
  }

  Future<void> _processDocument() async {
    if (_currentCorners.length != 4) {
      _showErrorDialog('Please ensure all four corners are properly positioned.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final processedPath = await _perspectiveCorrection();
      widget.onDocumentProcessed(processedPath);
      
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Document processing error: $e');
      _showErrorDialog('Failed to process document: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<String> _perspectiveCorrection() async {
    // Implementation for perspective correction
    // This would use image processing libraries to:
    // 1. Apply perspective transformation
    // 2. Enhance the document image
    // 3. Save the processed image
    
    // For now, return the original path
    // In production, implement actual perspective correction
    return widget.imagePath;
  }

  void _retryDetection() async {
    await _performEdgeDetection();
  }

  void _toggleManualMode() {
    setState(() {
      _isManualMode = !_isManualMode;
      if (!_isManualMode && _currentCorners.isEmpty) {
        _currentCorners = _getDefaultCorners();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Document Preview'),
        actions: [
          if (_detectionResult != null)
            IconButton(
              icon: Icon(_isManualMode ? Icons.auto_fix_high : Icons.edit),
              onPressed: _toggleManualMode,
              tooltip: _isManualMode ? 'Auto Mode' : 'Manual Mode',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _retryDetection,
            tooltip: 'Retry Detection',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Detecting document edges...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _buildImagePreview(),
                ),
                _buildBottomControls(),
              ],
            ),
    );
  }

  Widget _buildImagePreview() {
    if (_decodedImage == null) {
      return const Center(
        child: Text(
          'Failed to load image',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _calculateTransformMatrices(constraints.biggest);
        
        return GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: CustomPaint(
            size: constraints.biggest,
            painter: DocumentPreviewPainter(
              image: _decodedImage!,
              corners: _currentCorners,
              imageDisplaySize: _imageDisplaySize,
              imageDisplayOffset: _imageDisplayOffset,
              selectedCornerIndex: _selectedCornerIndex,
              isManualMode: _isManualMode,
              confidence: _detectionResult?.confidence ?? 0.0,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.black87,
        border: Border(
          top: BorderSide(color: Colors.grey, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isManualMode) ...[
              const Text(
                'Drag corners to adjust document boundaries',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
            if (_detectionResult != null) ...[
              Text(
                'Method: ${_detectionResult!.method} | '
                'Confidence: ${(_detectionResult!.confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _detectionResult!.confidence > 0.6 
                      ? Colors.green 
                      : Colors.orange,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _processDocument,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Use Document'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DocumentPreviewPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> corners;
  final Size imageDisplaySize;
  final Offset imageDisplayOffset;
  final int? selectedCornerIndex;
  final bool isManualMode;
  final double confidence;

  DocumentPreviewPainter({
    required this.image,
    required this.corners,
    required this.imageDisplaySize,
    required this.imageDisplayOffset,
    this.selectedCornerIndex,
    required this.isManualMode,
    required this.confidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the image
    final imageRect = Rect.fromLTWH(
      imageDisplayOffset.dx,
      imageDisplayOffset.dy,
      imageDisplaySize.width,
      imageDisplaySize.height,
    );
    
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    // Draw overlay if corners are detected
    if (corners.length == 4) {
      _drawDocumentOverlay(canvas, size);
    }
  }

  void _drawDocumentOverlay(Canvas canvas, Size size) {
    final scale = imageDisplaySize.width / image.width;
    
    // Convert corners to screen coordinates
    final screenCorners = corners.map((corner) {
      return Offset(
        imageDisplayOffset.dx + corner.dx * scale,
        imageDisplayOffset.dy + corner.dy * scale,
      );
    }).toList();

    // Draw document boundary
    final boundaryPaint = Paint()
      ..color = _getBoundaryColor()
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (screenCorners.isNotEmpty) {
      path.moveTo(screenCorners[0].dx, screenCorners[0].dy);
      for (int i = 1; i < screenCorners.length; i++) {
        path.lineTo(screenCorners[i].dx, screenCorners[i].dy);
      }
      path.close();
    }
    
    canvas.drawPath(path, boundaryPaint);

    // Draw corner handles if in manual mode
    if (isManualMode) {
      _drawCornerHandles(canvas, screenCorners);
    }

    // Draw corner numbers
    _drawCornerNumbers(canvas, screenCorners);
  }

  Color _getBoundaryColor() {
    if (confidence > 0.8) return Colors.green;
    if (confidence > 0.6) return Colors.blue;
    if (confidence > 0.3) return Colors.orange;
    return Colors.red;
  }

  void _drawCornerHandles(Canvas canvas, List<Offset> screenCorners) {
    for (int i = 0; i < screenCorners.length; i++) {
      final corner = screenCorners[i];
      final isSelected = selectedCornerIndex == i;
      
      // Outer circle
      final outerPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.blue
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(corner, isSelected ? 12 : 10, outerPaint);
      
      // Inner circle
      final innerPaint = Paint()
        ..color = isSelected ? Colors.blue : Colors.white
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(corner, isSelected ? 8 : 6, innerPaint);
    }
  }

  void _drawCornerNumbers(Canvas canvas, List<Offset> screenCorners) {
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < screenCorners.length; i++) {
      final corner = screenCorners[i];
      
      textPainter.text = TextSpan(
        text: '${i + 1}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      
      textPainter.layout();
      
      // Draw background circle for number
      final backgroundPaint = Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(
        Offset(corner.dx + 20, corner.dy - 20),
        12,
        backgroundPaint,
      );
      
      // Draw number
      textPainter.paint(
        canvas,
        Offset(
          corner.dx + 20 - textPainter.width / 2,
          corner.dy - 20 - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(DocumentPreviewPainter oldDelegate) {
    return oldDelegate.corners != corners ||
           oldDelegate.selectedCornerIndex != selectedCornerIndex ||
           oldDelegate.isManualMode != isManualMode ||
           oldDelegate.confidence != confidence;
  }
}