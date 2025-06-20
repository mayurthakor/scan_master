// lib/services/enhanced_edge_detection_service.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class EdgeDetectionResult {
  final List<Offset> corners;
  final double confidence;
  final String method;
  final bool requiresManualAdjustment;
  final DocumentType documentType;
  final bool isReadyForAutoCapture;
  final String positioningFeedback;

  EdgeDetectionResult({
    required this.corners,
    required this.confidence,
    required this.method,
    this.requiresManualAdjustment = false,
    this.documentType = DocumentType.unknown,
    this.isReadyForAutoCapture = false,
    this.positioningFeedback = '',
  });
}

enum DocumentType {
  unknown,
  a4Document,
  receipt,
  businessCard,
  idCard,
  photo,
  book,
  whiteboard,
}

class AutoCaptureSettings {
  final double minConfidenceThreshold;
  final double stabilityThreshold;
  final Duration stabilityDuration;
  final bool enableAutoCapture;
  final DocumentType? preferredDocumentType;

  const AutoCaptureSettings({
    this.minConfidenceThreshold = 0.85,
    this.stabilityThreshold = 0.95,
    this.stabilityDuration = const Duration(milliseconds: 1500),
    this.enableAutoCapture = true,
    this.preferredDocumentType,
  });
}

class EnhancedEdgeDetectionService {
  static const double _minConfidenceThreshold = 0.6;
  static const double _aspectRatioTolerance = 0.3;
  static const double _minAreaRatio = 0.1;
  static const double _maxAreaRatio = 0.9;

  // Auto-capture tracking
  final List<EdgeDetectionResult> _recentResults = [];
  final int _maxRecentResults = 10;
  DateTime? _lastStableDetection;
  AutoCaptureSettings _autoCaptureSettings = const AutoCaptureSettings();

  // Document type aspect ratios (width/height)
  static const Map<DocumentType, List<double>> _documentAspectRatios = {
    DocumentType.a4Document: [0.707, 1.414], // A4 and A4 rotated
    DocumentType.receipt: [0.3, 0.8], // Typical receipt ratios
    DocumentType.businessCard: [1.586, 0.63], // Standard business card ratios
    DocumentType.idCard: [1.586, 0.63], // Similar to business card
    DocumentType.photo: [0.75, 1.33, 1.0], // 4:3, 3:4, square
    DocumentType.book: [0.6, 0.8], // Typical book ratios
    DocumentType.whiteboard: [1.33, 1.77], // 4:3, 16:9
  };

  void updateAutoCaptureSettings(AutoCaptureSettings settings) {
    _autoCaptureSettings = settings;
  }

  /// Multi-algorithm edge detection with fallback strategies and auto-capture
  Future<EdgeDetectionResult> detectDocumentEdges({
    required String imagePath,
    required Size imageSize,
    AutoCaptureSettings? autoCaptureSettings,
  }) async {
    if (autoCaptureSettings != null) {
      _autoCaptureSettings = autoCaptureSettings;
    }

    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Method 1: Contour-based detection (primary)
      final contourResult = await _detectUsingContours(image, imageSize);
      if (contourResult.confidence >= _minConfidenceThreshold) {
        return _enhanceResultWithTypeAndAutoCapture(contourResult, imageSize);
      }

      // Method 2: Edge-based detection with Canny algorithm
      final edgeResult = await _detectUsingEdges(image, imageSize);
      if (edgeResult.confidence >= _minConfidenceThreshold) {
        return _enhanceResultWithTypeAndAutoCapture(edgeResult, imageSize);
      }

      // Method 3: Corner detection fallback
      final cornerResult = await _detectUsingCorners(image, imageSize);
      if (cornerResult.confidence >= _minConfidenceThreshold) {
        return _enhanceResultWithTypeAndAutoCapture(cornerResult, imageSize);
      }

      // Fallback: Return best available result with manual adjustment flag
      final bestResult = [contourResult, edgeResult, cornerResult]
          .reduce((a, b) => a.confidence > b.confidence ? a : b);

      return EdgeDetectionResult(
        corners: bestResult.corners,
        confidence: bestResult.confidence,
        method: '${bestResult.method} (fallback)',
        requiresManualAdjustment: true,
        documentType: DocumentType.unknown,
        isReadyForAutoCapture: false,
        positioningFeedback: 'Document edges unclear. Position document clearly in frame.',
      );
    } catch (e) {
      print('Edge detection error: $e');
      return _getDefaultRectangle(imageSize);
    }
  }

  /// Enhance detection result with document type classification and auto-capture logic
  EdgeDetectionResult _enhanceResultWithTypeAndAutoCapture(
    EdgeDetectionResult baseResult,
    Size imageSize,
  ) {
    // Classify document type
    final documentType = _classifyDocumentType(baseResult.corners, imageSize);
    
    // Generate positioning feedback
    final feedback = _generatePositioningFeedback(baseResult, documentType);
    
    // Check auto-capture readiness
    final isReadyForAutoCapture = _checkAutoCaptureReadiness(baseResult);
    
    final enhancedResult = EdgeDetectionResult(
      corners: baseResult.corners,
      confidence: baseResult.confidence,
      method: baseResult.method,
      requiresManualAdjustment: baseResult.requiresManualAdjustment,
      documentType: documentType,
      isReadyForAutoCapture: isReadyForAutoCapture,
      positioningFeedback: feedback,
    );

    // Track for stability analysis
    _trackDetectionResult(enhancedResult);

    return enhancedResult;
  }

  /// Classify document type based on detected corners and dimensions
  DocumentType _classifyDocumentType(List<Offset> corners, Size imageSize) {
    if (corners.length != 4) return DocumentType.unknown;

    final documentRect = _calculateBoundingRect(corners);
    final aspectRatio = documentRect.width / documentRect.height;
    final area = documentRect.width * documentRect.height;
    final imageArea = imageSize.width * imageSize.height;
    final areaRatio = area / imageArea;

    // Check against known document type ratios
    for (final entry in _documentAspectRatios.entries) {
      final documentType = entry.key;
      final ratios = entry.value;
      
      for (final expectedRatio in ratios) {
        if ((aspectRatio - expectedRatio).abs() / expectedRatio < 0.15) {
          // Additional validation based on size
          if (_validateDocumentTypeBySize(documentType, areaRatio, aspectRatio)) {
            return documentType;
          }
        }
      }
    }

    // Fallback classification based on size and ratio
    if (areaRatio > 0.6) {
      return DocumentType.a4Document;
    } else if (aspectRatio > 2.0 || aspectRatio < 0.5) {
      return DocumentType.receipt;
    } else if (areaRatio < 0.2) {
      return DocumentType.businessCard;
    }

    return DocumentType.unknown;
  }

  bool _validateDocumentTypeBySize(DocumentType type, double areaRatio, double aspectRatio) {
    switch (type) {
      case DocumentType.a4Document:
        return areaRatio > 0.4;
      case DocumentType.receipt:
        return areaRatio > 0.1 && areaRatio < 0.7;
      case DocumentType.businessCard:
        return areaRatio > 0.05 && areaRatio < 0.3;
      case DocumentType.idCard:
        return areaRatio > 0.05 && areaRatio < 0.4;
      case DocumentType.photo:
        return areaRatio > 0.2 && areaRatio < 0.8;
      case DocumentType.book:
        return areaRatio > 0.3 && areaRatio < 0.8;
      case DocumentType.whiteboard:
        return areaRatio > 0.5;
      default:
        return true;
    }
  }

  Rect _calculateBoundingRect(List<Offset> corners) {
    if (corners.isEmpty) return Rect.zero;
    
    double minX = corners.first.dx;
    double maxX = corners.first.dx;
    double minY = corners.first.dy;
    double maxY = corners.first.dy;

    for (final corner in corners) {
      minX = math.min(minX, corner.dx);
      maxX = math.max(maxX, corner.dx);
      minY = math.min(minY, corner.dy);
      maxY = math.max(maxY, corner.dy);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Generate helpful positioning feedback for users
  String _generatePositioningFeedback(EdgeDetectionResult result, DocumentType documentType) {
    if (result.confidence > 0.9) {
      return _getDocumentTypeMessage(documentType, 'Perfect! Hold steady...');
    } else if (result.confidence > 0.8) {
      return _getDocumentTypeMessage(documentType, 'Good positioning. Hold steady...');
    } else if (result.confidence > 0.6) {
      return 'Position document clearly in frame';
    } else {
      return 'Move closer and align document with frame';
    }
  }

  String _getDocumentTypeMessage(DocumentType type, String baseMessage) {
    final typeString = _getDocumentTypeDisplayName(type);
    return '$typeString detected. $baseMessage';
  }

  String _getDocumentTypeDisplayName(DocumentType type) {
    switch (type) {
      case DocumentType.a4Document:
        return 'Document';
      case DocumentType.receipt:
        return 'Receipt';
      case DocumentType.businessCard:
        return 'Business Card';
      case DocumentType.idCard:
        return 'ID Card';
      case DocumentType.photo:
        return 'Photo';
      case DocumentType.book:
        return 'Book Page';
      case DocumentType.whiteboard:
        return 'Whiteboard';
      default:
        return 'Document';
    }
  }

  /// Check if conditions are met for auto-capture
  bool _checkAutoCaptureReadiness(EdgeDetectionResult result) {
    if (!_autoCaptureSettings.enableAutoCapture) return false;
    
    // Check confidence threshold
    if (result.confidence < _autoCaptureSettings.minConfidenceThreshold) {
      return false;
    }

    // Check document type preference
    if (_autoCaptureSettings.preferredDocumentType != null &&
        result.documentType != _autoCaptureSettings.preferredDocumentType) {
      return false;
    }

    // Check stability
    return _isDetectionStable();
  }

  /// Track detection results for stability analysis
  void _trackDetectionResult(EdgeDetectionResult result) {
    _recentResults.add(result);
    
    // Keep only recent results
    if (_recentResults.length > _maxRecentResults) {
      _recentResults.removeAt(0);
    }
  }

  /// Check if detection has been stable for required duration
  bool _isDetectionStable() {
    if (_recentResults.length < 5) return false; // Need at least 5 results
    
    // Check if recent results are consistent
    final recentStableResults = _recentResults
        .where((r) => r.confidence >= _autoCaptureSettings.stabilityThreshold)
        .toList();
    
    if (recentStableResults.length < 3) {
      _lastStableDetection = null;
      return false;
    }

    // Check corner stability (corners shouldn't move much)
    if (!_areCornersStable(recentStableResults)) {
      _lastStableDetection = null;
      return false;
    }

    // Track stable detection timing
    final now = DateTime.now();
    _lastStableDetection ??= now;
    
    final stableDuration = now.difference(_lastStableDetection!);
    return stableDuration >= _autoCaptureSettings.stabilityDuration;
  }

  bool _areCornersStable(List<EdgeDetectionResult> results) {
    if (results.length < 2) return false;
    
    final firstCorners = results.first.corners;
    if (firstCorners.length != 4) return false;
    
    const maxMovement = 10.0; // pixels
    
    for (final result in results.skip(1)) {
      if (result.corners.length != 4) return false;
      
      for (int i = 0; i < 4; i++) {
        final distance = _distance(firstCorners[i], result.corners[i]);
        if (distance > maxMovement) return false;
      }
    }
    
    return true;
  }

  /// Reset auto-capture tracking
  void resetAutoCaptureTracking() {
    _recentResults.clear();
    _lastStableDetection = null;
  }

  /// Get current auto-capture status for UI feedback
  AutoCaptureStatus getAutoCaptureStatus() {
    if (!_autoCaptureSettings.enableAutoCapture) {
      return AutoCaptureStatus.disabled;
    }
    
    if (_recentResults.isEmpty) {
      return AutoCaptureStatus.searching;
    }
    
    final latestResult = _recentResults.last;
    
    if (latestResult.confidence < _autoCaptureSettings.minConfidenceThreshold) {
      return AutoCaptureStatus.lowConfidence;
    }
    
    if (_isDetectionStable()) {
      return AutoCaptureStatus.ready;
    }
    
    return AutoCaptureStatus.stabilizing;
  }

  /// Primary contour-based detection method
  Future<EdgeDetectionResult> _detectUsingContours(
    img.Image image,
    Size imageSize,
  ) async {
    try {
      // Enhanced preprocessing pipeline
      var processed = _enhancedPreprocessing(image);
      
      // Adaptive thresholding for better edge detection
      processed = _adaptiveThreshold(processed);
      
      // Find contours using connected component analysis
      final contours = _findContours(processed);
      
      // Filter and rank contours by document-like properties
      final documentContours = _filterDocumentContours(contours, image);
      
      if (documentContours.isEmpty) {
        return EdgeDetectionResult(
          corners: [],
          confidence: 0.0,
          method: 'contour',
        );
      }

      // Get the best contour and approximate to quadrilateral
      final bestContour = documentContours.first;
      final corners = _approximateToQuadrilateral(bestContour);
      
      if (corners.length != 4) {
        return EdgeDetectionResult(
          corners: [],
          confidence: 0.0,
          method: 'contour',
        );
      }

      // Validate and score the detected rectangle
      final confidence = _validateAndScoreRectangle(corners, imageSize);
      final orderedCorners = _orderCorners(corners, imageSize);

      return EdgeDetectionResult(
        corners: orderedCorners,
        confidence: confidence,
        method: 'contour',
      );
    } catch (e) {
      print('Contour detection error: $e');
      return EdgeDetectionResult(
        corners: [],
        confidence: 0.0,
        method: 'contour',
      );
    }
  }

  /// Enhanced preprocessing with multiple techniques
  img.Image _enhancedPreprocessing(img.Image image) {
    // Convert to grayscale
    var processed = img.grayscale(image);
    
    // Gaussian blur to reduce noise
    processed = img.gaussianBlur(processed, radius: 1);
    
    // Enhance contrast using CLAHE (Contrast Limited Adaptive Histogram Equalization)
    processed = _applyCLAHE(processed);
    
    // Sharpen the image to enhance edges
    processed = _sharpenImage(processed);
    
    return processed;
  }

  /// Apply Contrast Limited Adaptive Histogram Equalization
  img.Image _applyCLAHE(img.Image image) {
    // Simplified CLAHE implementation
    return img.contrast(image, contrast: 1.2);
  }

  /// Sharpen image to enhance edges
  img.Image _sharpenImage(img.Image image) {
    // Apply unsharp mask filter - simplified approach
    final result = img.Image.from(image);
    
    for (int y = 1; y < result.height - 1; y++) {
      for (int x = 1; x < result.width - 1; x++) {
        // Apply sharpening kernel manually
        final center = img.getLuminance(image.getPixel(x, y));
        final top = img.getLuminance(image.getPixel(x, y - 1));
        final bottom = img.getLuminance(image.getPixel(x, y + 1));
        final left = img.getLuminance(image.getPixel(x - 1, y));
        final right = img.getLuminance(image.getPixel(x + 1, y));
        
        final sharpened = (center * 5 - top - bottom - left - right).clamp(0, 255);
        final color = img.ColorRgb8(sharpened.round(), sharpened.round(), sharpened.round());
        result.setPixel(x, y, color);
      }
    }
    
    return result;
  }

  /// Adaptive thresholding for better edge detection
  img.Image _adaptiveThreshold(img.Image image) {
    // Implement adaptive thresholding based on local mean
    final threshold = _calculateAdaptiveThreshold(image);
    
    // Create a new image with thresholding applied
    final result = img.Image.from(image);
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final gray = img.getLuminance(pixel).round();
        final newColor = gray > threshold ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0);
        result.setPixel(x, y, newColor);
      }
    }
    return result;
  }

  int _calculateAdaptiveThreshold(img.Image image) {
    // Calculate optimal threshold using Otsu's method
    final histogram = List.filled(256, 0);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final gray = img.getLuminance(pixel).round();
        histogram[gray]++;
      }
    }
    
    return _otsuThreshold(histogram, image.width * image.height);
  }

  int _otsuThreshold(List<int> histogram, int totalPixels) {
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    double sumB = 0;
    int wB = 0;
    int wF = 0;
    double varMax = 0;
    int threshold = 0;

    for (int i = 0; i < 256; i++) {
      wB += histogram[i];
      if (wB == 0) continue;

      wF = totalPixels - wB;
      if (wF == 0) break;

      sumB += i * histogram[i];
      double mB = sumB / wB;
      double mF = (sum - sumB) / wF;
      double varBetween = wB * wF * (mB - mF) * (mB - mF);

      if (varBetween > varMax) {
        varMax = varBetween;
        threshold = i;
      }
    }

    return threshold;
  }

  /// Find contours in the processed image
  List<List<Offset>> _findContours(img.Image image) {
    // Simplified contour detection - in production, use a more robust algorithm
    final contours = <List<Offset>>[];
    final visited = List.generate(
      image.height,
      (y) => List.filled(image.width, false),
    );

    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        if (!visited[y][x] && _isEdgePixel(image, x, y)) {
          final contour = _traceContour(image, x, y, visited);
          if (contour.length > 50) { // Minimum contour length
            contours.add(contour);
          }
        }
      }
    }

    return contours;
  }

  bool _isEdgePixel(img.Image image, int x, int y) {
    final pixel = image.getPixel(x, y);
    final luminance = img.getLuminance(pixel);
    return luminance < 128; // Simple threshold check
  }

  List<Offset> _traceContour(
    img.Image image,
    int startX,
    int startY,
    List<List<bool>> visited,
  ) {
    final contour = <Offset>[];
    final directions = [
      Offset(-1, -1), Offset(0, -1), Offset(1, -1),
      Offset(-1, 0),                 Offset(1, 0),
      Offset(-1, 1),  Offset(0, 1),  Offset(1, 1),
    ];

    var x = startX;
    var y = startY;
    
    while (x >= 0 && x < image.width && y >= 0 && y < image.height) {
      if (visited[y][x]) break;
      
      visited[y][x] = true;
      contour.add(Offset(x.toDouble(), y.toDouble()));
      
      bool found = false;
      for (final dir in directions) {
        final newX = x + dir.dx.toInt();
        final newY = y + dir.dy.toInt();
        
        if (newX >= 0 && newX < image.width &&
            newY >= 0 && newY < image.height &&
            !visited[newY][newX] &&
            _isEdgePixel(image, newX, newY)) {
          x = newX;
          y = newY;
          found = true;
          break;
        }
      }
      
      if (!found) break;
    }

    return contour;
  }

  /// Filter contours to find document-like shapes
  List<List<Offset>> _filterDocumentContours(
    List<List<Offset>> contours,
    img.Image image,
  ) {
    final imageArea = image.width * image.height;
    final documentContours = <List<Offset>>[];

    for (final contour in contours) {
      if (contour.length < 4) continue;

      final area = _calculateContourArea(contour);
      final areaRatio = area / imageArea;

      // Filter by area ratio
      if (areaRatio < _minAreaRatio || areaRatio > _maxAreaRatio) continue;

      // Check if contour is roughly rectangular
      final hull = _convexHull(contour);
      if (hull.length < 4) continue;

      final approximation = _douglasPeucker(hull, 10.0);
      if (approximation.length == 4) {
        documentContours.add(approximation);
      }
    }

    // Sort by area (largest first)
    documentContours.sort((a, b) {
      final areaA = _calculateContourArea(a);
      final areaB = _calculateContourArea(b);
      return areaB.compareTo(areaA);
    });

    return documentContours;
  }

  double _calculateContourArea(List<Offset> contour) {
    if (contour.length < 3) return 0.0;

    double area = 0.0;
    for (int i = 0; i < contour.length; i++) {
      final j = (i + 1) % contour.length;
      area += contour[i].dx * contour[j].dy;
      area -= contour[j].dx * contour[i].dy;
    }
    return area.abs() / 2.0;
  }

  /// Convex hull using Graham scan algorithm
  List<Offset> _convexHull(List<Offset> points) {
    if (points.length < 3) return points;

    // Find the bottom-most point (or left most in case of tie)
    var bottom = points[0];
    for (final point in points) {
      if (point.dy > bottom.dy || 
          (point.dy == bottom.dy && point.dx < bottom.dx)) {
        bottom = point;
      }
    }

    // Sort points by polar angle with respect to bottom point
    final sortedPoints = points.where((p) => p != bottom).toList();
    sortedPoints.sort((a, b) {
      final angleA = _polarAngle(bottom, a);
      final angleB = _polarAngle(bottom, b);
      return angleA.compareTo(angleB);
    });

    final hull = <Offset>[bottom];
    for (final point in sortedPoints) {
      while (hull.length > 1 && 
             _crossProduct(hull[hull.length - 2], hull[hull.length - 1], point) <= 0) {
        hull.removeLast();
      }
      hull.add(point);
    }

    return hull;
  }

  double _polarAngle(Offset origin, Offset point) {
    return math.atan2(point.dy - origin.dy, point.dx - origin.dx);
  }

  double _crossProduct(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }

  /// Douglas-Peucker algorithm for polygon simplification
  List<Offset> _douglasPeucker(List<Offset> points, double epsilon) {
    if (points.length < 3) return points;

    // Find the point with maximum distance from line segment
    double maxDistance = 0.0;
    int maxIndex = 0;

    for (int i = 1; i < points.length - 1; i++) {
      final distance = _pointToLineDistance(
        points[i],
        points.first,
        points.last,
      );
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
      final leftPart = _douglasPeucker(
        points.sublist(0, maxIndex + 1),
        epsilon,
      );
      final rightPart = _douglasPeucker(
        points.sublist(maxIndex),
        epsilon,
      );

      return [...leftPart.sublist(0, leftPart.length - 1), ...rightPart];
    } else {
      return [points.first, points.last];
    }
  }

  double _pointToLineDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final A = lineEnd.dy - lineStart.dy;
    final B = lineStart.dx - lineEnd.dx;
    final C = lineEnd.dx * lineStart.dy - lineStart.dx * lineEnd.dy;

    return (A * point.dx + B * point.dy + C).abs() / 
           math.sqrt(A * A + B * B);
  }

  /// Approximate contour to quadrilateral
  List<Offset> _approximateToQuadrilateral(List<Offset> contour) {
    // Use iterative Douglas-Peucker with decreasing epsilon
    var epsilon = 20.0;
    List<Offset> approximation;

    do {
      approximation = _douglasPeucker(contour, epsilon);
      epsilon -= 2.0;
    } while (approximation.length > 4 && epsilon > 2.0);

    if (approximation.length == 4) {
      return approximation;
    } else if (approximation.length > 4) {
      // Take the 4 corners with maximum angles
      return _selectBestFourCorners(approximation);
    } else {
      return [];
    }
  }

  List<Offset> _selectBestFourCorners(List<Offset> points) {
    // Calculate angles at each point and select 4 points with largest angles
    final anglePoints = <_AnglePoint>[];

    for (int i = 0; i < points.length; i++) {
      final prev = points[(i - 1 + points.length) % points.length];
      final curr = points[i];
      final next = points[(i + 1) % points.length];

      final angle = _calculateAngle(prev, curr, next);
      anglePoints.add(_AnglePoint(curr, angle));
    }

    anglePoints.sort((a, b) => b.angle.compareTo(a.angle));
    return anglePoints.take(4).map((ap) => ap.point).toList();
  }

  double _calculateAngle(Offset a, Offset b, Offset c) {
    final ba = Offset(a.dx - b.dx, a.dy - b.dy);
    final bc = Offset(c.dx - b.dx, c.dy - b.dy);

    final dotProduct = ba.dx * bc.dx + ba.dy * bc.dy;
    final magnitudeBA = math.sqrt(ba.dx * ba.dx + ba.dy * ba.dy);
    final magnitudeBC = math.sqrt(bc.dx * bc.dx + bc.dy * bc.dy);

    if (magnitudeBA == 0 || magnitudeBC == 0) return 0.0;

    final cosAngle = dotProduct / (magnitudeBA * magnitudeBC);
    return math.acos(cosAngle.clamp(-1.0, 1.0));
  }

  /// Validate and score the detected rectangle
  double _validateAndScoreRectangle(List<Offset> corners, Size imageSize) {
    if (corners.length != 4) return 0.0;

    double score = 0.0;

    // Check area ratio
    final area = _calculateContourArea(corners);
    final imageArea = imageSize.width * imageSize.height;
    final areaRatio = area / imageArea;

    if (areaRatio >= _minAreaRatio && areaRatio <= _maxAreaRatio) {
      score += 0.3;
    }

    // Check aspect ratio (should be reasonable for documents)
    final width = _distance(corners[0], corners[1]);
    final height = _distance(corners[1], corners[2]);
    final aspectRatio = width / height;

    if (aspectRatio >= 0.5 && aspectRatio <= 2.0) {
      score += 0.2;
    }

    // Check if corners form a convex quadrilateral
    if (_isConvexQuadrilateral(corners)) {
      score += 0.2;
    }

    // Check angle regularity (corners should be roughly 90 degrees)
    final angles = _calculateCornerAngles(corners);
    double angleScore = 0.0;
    for (final angle in angles) {
      final deviationFromRightAngle = (angle - math.pi / 2).abs();
      if (deviationFromRightAngle < math.pi / 6) { // 30 degrees tolerance
        angleScore += 0.075; // 0.3 / 4 corners
      }
    }
    score += angleScore;

    return score.clamp(0.0, 1.0);
  }

  double _distance(Offset a, Offset b) {
    return math.sqrt((a.dx - b.dx) * (a.dx - b.dx) + 
                     (a.dy - b.dy) * (a.dy - b.dy));
  }

  bool _isConvexQuadrilateral(List<Offset> corners) {
    if (corners.length != 4) return false;

    // Check if all cross products have the same sign
    bool? isPositive;
    for (int i = 0; i < 4; i++) {
      final curr = corners[i];
      final next = corners[(i + 1) % 4];
      final nextNext = corners[(i + 2) % 4];

      final crossProduct = _crossProduct(curr, next, nextNext);
      if (crossProduct == 0) return false;

      if (isPositive == null) {
        isPositive = crossProduct > 0;
      } else if ((crossProduct > 0) != isPositive) {
        return false;
      }
    }

    return true;
  }

  List<double> _calculateCornerAngles(List<Offset> corners) {
    final angles = <double>[];
    for (int i = 0; i < corners.length; i++) {
      final prev = corners[(i - 1 + corners.length) % corners.length];
      final curr = corners[i];
      final next = corners[(i + 1) % corners.length];

      angles.add(_calculateAngle(prev, curr, next));
    }
    return angles;
  }

  /// Order corners in a consistent manner: top-left, top-right, bottom-right, bottom-left
  List<Offset> _orderCorners(List<Offset> corners, Size imageSize) {
    if (corners.length != 4) return corners;

    // Calculate center point
    final center = Offset(
      corners.map((c) => c.dx).reduce((a, b) => a + b) / 4,
      corners.map((c) => c.dy).reduce((a, b) => a + b) / 4,
    );

    // Sort by angle from center
    final cornersWithAngles = corners.map((corner) {
      final angle = math.atan2(corner.dy - center.dy, corner.dx - center.dx);
      return _CornerWithAngle(corner, angle);
    }).toList();

    cornersWithAngles.sort((a, b) => a.angle.compareTo(b.angle));

    // Find top-left corner (minimum x + y)
    var topLeft = cornersWithAngles[0].corner;
    int topLeftIndex = 0;
    for (int i = 1; i < 4; i++) {
      final corner = cornersWithAngles[i].corner;
      if (corner.dx + corner.dy < topLeft.dx + topLeft.dy) {
        topLeft = corner;
        topLeftIndex = i;
      }
    }

    // Reorder starting from top-left, going clockwise
    final ordered = <Offset>[];
    for (int i = 0; i < 4; i++) {
      ordered.add(cornersWithAngles[(topLeftIndex + i) % 4].corner);
    }

    return ordered;
  }

  /// Edge-based detection fallback method
  Future<EdgeDetectionResult> _detectUsingEdges(
    img.Image image,
    Size imageSize,
  ) async {
    // Implement Canny edge detection
    final edges = _cannyEdgeDetection(image);
    
    // Use Hough transform to find lines
    final lines = _houghLineTransform(edges);
    
    // Find intersections to form rectangles
    final corners = _findRectangleFromLines(lines, imageSize);
    
    final confidence = corners.length == 4 ? 0.5 : 0.0;
    
    return EdgeDetectionResult(
      corners: corners,
      confidence: confidence,
      method: 'edge',
    );
  }

  img.Image _cannyEdgeDetection(img.Image image) {
    // Simplified Canny edge detection
    // In production, implement full Canny algorithm
    return img.sobel(image);
  }

  List<_Line> _houghLineTransform(img.Image edges) {
    // Simplified Hough transform
    // In production, implement full Hough line detection
    return [];
  }

  List<Offset> _findRectangleFromLines(List<_Line> lines, Size imageSize) {
    // Find rectangle from detected lines
    // In production, implement line intersection logic
    return [];
  }

  /// Corner detection fallback method
  Future<EdgeDetectionResult> _detectUsingCorners(
    img.Image image,
    Size imageSize,
  ) async {
    // Implement Harris corner detection
    final corners = _harrisCornerDetection(image);
    
    // Filter and group corners into rectangles
    final rectangleCorners = _groupCornersIntoRectangle(corners, imageSize);
    
    final confidence = rectangleCorners.length == 4 ? 0.3 : 0.0;
    
    return EdgeDetectionResult(
      corners: rectangleCorners,
      confidence: confidence,
      method: 'corner',
    );
  }

  List<Offset> _harrisCornerDetection(img.Image image) {
    // Simplified Harris corner detection
    // In production, implement full Harris corner detector
    return [];
  }

  List<Offset> _groupCornersIntoRectangle(List<Offset> corners, Size imageSize) {
    // Group detected corners into a rectangle
    // In production, implement clustering and rectangle fitting
    return [];
  }

  /// Get default rectangle when detection fails
  EdgeDetectionResult _getDefaultRectangle(Size imageSize) {
    final margin = 0.1;
    final corners = [
      Offset(imageSize.width * margin, imageSize.height * margin),
      Offset(imageSize.width * (1 - margin), imageSize.height * margin),
      Offset(imageSize.width * (1 - margin), imageSize.height * (1 - margin)),
      Offset(imageSize.width * margin, imageSize.height * (1 - margin)),
    ];

    return EdgeDetectionResult(
      corners: corners,
      confidence: 0.1,
      method: 'default',
      requiresManualAdjustment: true,
    );
  }
}

// Helper classes
class _AnglePoint {
  final Offset point;
  final double angle;

  _AnglePoint(this.point, this.angle);
}

class _CornerWithAngle {
  final Offset corner;
  final double angle;

  _CornerWithAngle(this.corner, this.angle);
}

class _Line {
  final Offset start;
  final Offset end;

  _Line(this.start, this.end);
}

enum AutoCaptureStatus {
  disabled,
  searching,
  lowConfidence,
  stabilizing,
  ready,
}