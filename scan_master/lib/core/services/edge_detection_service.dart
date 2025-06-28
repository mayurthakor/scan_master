// lib/services/edge_detection_service.dart - Optimized for Real-time Processing
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Edge detection service optimized for real-time processing
/// Performance optimizations for Phase 4.1:
/// - 480p frame processing instead of full resolution
/// - Frame skipping (every 3rd frame)
/// - Coordinate scaling from detection space to screen space
/// - Multi-algorithm approach with fallback system
class EdgeDetectionService {
  static const int kTargetDetectionWidth = 640;   // 480p width for processing
  static const int kTargetDetectionHeight = 480;  // 480p height for processing
  static const int kFrameSkipInterval = 3;        // Process every 3rd frame
  
  int _frameCounter = 0;
  List<EdgeDetectionResult> _recentResults = [];
  DateTime? _lastStableDetection;
  AutoCaptureSettings _autoCaptureSettings = const AutoCaptureSettings();

  /// Process camera frame with real-time optimizations
  Future<EdgeDetectionResult> detectEdgesFromCameraFrame({
    required Uint8List imageData,
    required int originalWidth,
    required int originalHeight,
    required Size previewSize,
    bool skipFrameOptimization = false,
  }) async {
    // Frame skipping optimization - only process every 3rd frame
    if (!skipFrameOptimization) {
      _frameCounter++;
      if (_frameCounter % kFrameSkipInterval != 0) {
        // Return last known result for skipped frames
        return _recentResults.isNotEmpty 
            ? _recentResults.last.copyWith(isSkippedFrame: true)
            : _getDefaultResult(previewSize);
      }
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Create image from RGB data for processing
      final processedImage = _createImageFromRGB(
        imageData, 
        originalWidth, 
        originalHeight,
      );
      
      if (processedImage == null) {
        return _getDefaultResult(previewSize);
      }

      // Resize to 480p for faster processing
      final optimizedImage = _resizeForDetection(processedImage);
      
      // Calculate scaling factors for coordinate transformation
      final scaleX = previewSize.width / optimizedImage.width;
      final scaleY = previewSize.height / optimizedImage.height;

      // Perform optimized edge detection
      final detectionResult = await _performOptimizedDetection(
        optimizedImage,
        Size(optimizedImage.width.toDouble(), optimizedImage.height.toDouble()),
      );

      // Scale coordinates back to preview size
      final scaledCorners = detectionResult.corners.map((corner) => Offset(
        corner.dx * scaleX,
        corner.dy * scaleY,
      )).toList();

      final result = EdgeDetectionResult(
        corners: scaledCorners,
        confidence: detectionResult.confidence,
        method: detectionResult.method,
        processingTimeMs: stopwatch.elapsedMilliseconds,
        isRealtime: true,
        originalSize: Size(originalWidth.toDouble(), originalHeight.toDouble()),
        detectionSize: Size(optimizedImage.width.toDouble(), optimizedImage.height.toDouble()),
        previewSize: previewSize,
      );

      // Update stability tracking
      _updateStabilityTracking(result);

      return result;

    } catch (e) {
      debugPrint('Real-time edge detection error: $e');
      return _getDefaultResult(previewSize);
    }
  }

  /// Create image from RGB byte array
  img.Image? _createImageFromRGB(Uint8List rgbData, int width, int height) {
    try {
      // Create image with reduced resolution for speed
      final targetWidth = math.min(width, kTargetDetectionWidth);
      final targetHeight = math.min(height, kTargetDetectionHeight);
      
      final image = img.Image(width: targetWidth, height: targetHeight);
      
      // Sample RGB data to create image
      int rgbIndex = 0;
      for (int y = 0; y < targetHeight && rgbIndex < rgbData.length - 2; y++) {
        for (int x = 0; x < targetWidth && rgbIndex < rgbData.length - 2; x++) {
          final r = rgbData[rgbIndex++];
          final g = rgbData[rgbIndex++];
          final b = rgbData[rgbIndex++];
          
          image.setPixelRgb(x, y, r, g, b);
        }
      }
      
      return image;
    } catch (e) {
      debugPrint('Error creating image from RGB: $e');
      return null;
    }
  }

  /// Resize image to optimal size for detection
  img.Image _resizeForDetection(img.Image original) {
    // If already small enough, return as-is
    if (original.width <= kTargetDetectionWidth && 
        original.height <= kTargetDetectionHeight) {
      return original;
    }
    
    // Calculate aspect ratio preserving resize
    final aspectRatio = original.width / original.height;
    
    int targetWidth, targetHeight;
    if (aspectRatio > 1.0) {
      // Landscape
      targetWidth = kTargetDetectionWidth;
      targetHeight = (kTargetDetectionWidth / aspectRatio).round();
    } else {
      // Portrait
      targetHeight = kTargetDetectionHeight;
      targetWidth = (kTargetDetectionHeight * aspectRatio).round();
    }

    return img.copyResize(
      original,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear, // Fast interpolation
    );
  }

  /// Optimized detection pipeline for real-time performance
  Future<EdgeDetectionResult> _performOptimizedDetection(
    img.Image image,
    Size imageSize,
  ) async {
    // Multi-algorithm approach with performance priority
    EdgeDetectionResult? bestResult;
    
    try {
      // Primary: Fast contour-based detection
      final contourResult = await _fastContourDetection(image, imageSize);
      if (contourResult.confidence > 0.3) {
        bestResult = contourResult;
      }
    } catch (e) {
      debugPrint('Fast contour detection failed: $e');
    }

    // Fallback: Edge-based detection if contour fails
    if (bestResult == null || bestResult.confidence < 0.3) {
      try {
        final edgeResult = await _fastEdgeDetection(image, imageSize);
        if (edgeResult.confidence > (bestResult?.confidence ?? 0.0)) {
          bestResult = edgeResult;
        }
      } catch (e) {
        debugPrint('Fast edge detection failed: $e');
      }
    }

    return bestResult ?? _getDefaultRectangle(imageSize);
  }

  /// Fast contour-based detection optimized for mobile
  Future<EdgeDetectionResult> _fastContourDetection(
    img.Image image,
    Size imageSize,
  ) async {
    // Optimized preprocessing for speed
    var processed = _fastPreprocessing(image);
    
    // Fast threshold
    processed = _fastThreshold(processed);
    
    // Simplified contour detection
    final contours = _findFastContours(processed);
    
    // Find best rectangular contour
    final corners = _findBestRectangle(contours, imageSize);
    
    final confidence = _calculateFastConfidence(corners, imageSize);
    
    return EdgeDetectionResult(
      corners: corners,
      confidence: confidence,
      method: 'fast_contour',
    );
  }

  /// Fast edge-based detection
  Future<EdgeDetectionResult> _fastEdgeDetection(
    img.Image image,
    Size imageSize,
  ) async {
    // Simple Sobel edge detection
    final edges = img.sobel(image);
    
    // Basic line detection
    final lines = _detectFastLines(edges);
    
    // Find rectangle from lines
    final corners = _rectangleFromLines(lines, imageSize);
    
    final confidence = corners.length == 4 ? 0.4 : 0.0;
    
    return EdgeDetectionResult(
      corners: corners,
      confidence: confidence,
      method: 'fast_edge',
    );
  }

  /// Optimized preprocessing - minimal operations for speed
  img.Image _fastPreprocessing(img.Image image) {
    // Convert to grayscale with fast luminance
    final gray = img.grayscale(image);
    
    // Light gaussian blur for noise reduction
    return img.gaussianBlur(gray, radius: 1);
  }

  /// Fast binary threshold using Otsu's method
  img.Image _fastThreshold(img.Image image) {
    // Calculate optimal threshold
    final threshold = _calculateOtsuThreshold(image);
    
    // Apply threshold
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel);
        
        image.setPixel(x, y, luminance > threshold 
            ? img.ColorRgb8(255, 255, 255) 
            : img.ColorRgb8(0, 0, 0));
      }
    }
    
    return image;
  }

  /// Fast Otsu threshold calculation
  int _calculateOtsuThreshold(img.Image image) {
    // Build histogram
    final histogram = List<int>.filled(256, 0);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel).toInt();
        histogram[luminance]++;
      }
    }
    
    // Otsu's method
    int total = image.width * image.height;
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }
    
    double sumB = 0;
    int wB = 0;
    double maximum = 0.0;
    int threshold = 0;
    
    for (int t = 0; t < 256; t++) {
      wB += histogram[t];
      if (wB == 0) continue;
      
      int wF = total - wB;
      if (wF == 0) break;
      
      sumB += t * histogram[t];
      double mB = sumB / wB;
      double mF = (sum - sumB) / wF;
      
      double between = wB * wF * (mB - mF) * (mB - mF);
      
      if (between > maximum) {
        maximum = between;
        threshold = t;
      }
    }
    
    return threshold;
  }

  /// Fast contour finding
  List<List<Offset>> _findFastContours(img.Image image) {
    final contours = <List<Offset>>[];
    final visited = List.generate(
      image.height, 
      (_) => List<bool>.filled(image.width, false),
    );
    
    // Simple contour tracing
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        if (!visited[y][x] && _isEdgePixel(image, x, y)) {
          final contour = _traceContour(image, x, y, visited);
          if (contour.length > 20) { // Minimum contour size
            contours.add(contour);
          }
        }
      }
    }
    
    return contours;
  }

  bool _isEdgePixel(img.Image image, int x, int y) {
    final center = img.getLuminance(image.getPixel(x, y));
    if (center < 128) return false; // Only look for white edges
    
    // Check 4-connectivity
    final neighbors = [
      img.getLuminance(image.getPixel(x - 1, y)),
      img.getLuminance(image.getPixel(x + 1, y)),
      img.getLuminance(image.getPixel(x, y - 1)),
      img.getLuminance(image.getPixel(x, y + 1)),
    ];
    
    return neighbors.any((n) => (center - n).abs() > 64);
  }

  List<Offset> _traceContour(img.Image image, int startX, int startY, List<List<bool>> visited) {
    final contour = <Offset>[];
    final stack = <Offset>[Offset(startX.toDouble(), startY.toDouble())];
    
    while (stack.isNotEmpty && contour.length < 500) { // Limit for speed
      final point = stack.removeLast();
      final x = point.dx.toInt();
      final y = point.dy.toInt();
      
      if (x < 0 || x >= image.width || y < 0 || y >= image.height || visited[y][x]) {
        continue;
      }
      
      visited[y][x] = true;
      contour.add(point);
      
      // Add neighbors (4-connectivity for speed)
      const directions = [
        [-1, 0], [1, 0], [0, -1], [0, 1]
      ];
      
      for (final dir in directions) {
        final nx = x + dir[0];
        final ny = y + dir[1];
        
        if (nx >= 0 && nx < image.width && ny >= 0 && ny < image.height &&
            !visited[ny][nx] && _isEdgePixel(image, nx, ny)) {
          stack.add(Offset(nx.toDouble(), ny.toDouble()));
        }
      }
    }
    
    return contour;
  }

  /// Find best rectangle from contours
  List<Offset> _findBestRectangle(List<List<Offset>> contours, Size imageSize) {
    List<Offset> bestRectangle = [];
    double bestScore = 0.0;
    
    for (final contour in contours) {
      if (contour.length < 50) continue; // Skip small contours
      
      // Approximate polygon
      final approx = _approximatePolygon(contour, 0.02);
      
      if (approx.length == 4) {
        final score = _scoreRectangle(approx, imageSize);
        if (score > bestScore) {
          bestScore = score;
          bestRectangle = approx;
        }
      }
    }
    
    return bestRectangle;
  }

  /// Simplified polygon approximation using Douglas-Peucker
  List<Offset> _approximatePolygon(List<Offset> contour, double epsilon) {
    if (contour.length < 3) return contour;
    
    return _douglasPeucker(contour, epsilon * _perimeter(contour));
  }

  List<Offset> _douglasPeucker(List<Offset> points, double epsilon) {
    if (points.length < 3) return points;
    
    // Find the point with maximum distance
    double maxDistance = 0;
    int index = 0;
    
    for (int i = 1; i < points.length - 1; i++) {
      final distance = _pointToLineDistance(
        points[i], 
        points.first, 
        points.last,
      );
      
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    
    // If max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
      final rec1 = _douglasPeucker(points.sublist(0, index + 1), epsilon);
      final rec2 = _douglasPeucker(points.sublist(index), epsilon);
      
      return [...rec1.sublist(0, rec1.length - 1), ...rec2];
    }
    
    return [points.first, points.last];
  }

  double _pointToLineDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final A = lineEnd.dy - lineStart.dy;
    final B = lineStart.dx - lineEnd.dx;
    final C = lineEnd.dx * lineStart.dy - lineStart.dx * lineEnd.dy;
    
    return (A * point.dx + B * point.dy + C).abs() / 
           math.sqrt(A * A + B * B);
  }

  double _perimeter(List<Offset> points) {
    double perimeter = 0;
    for (int i = 0; i < points.length; i++) {
      final next = (i + 1) % points.length;
      perimeter += _distance(points[i], points[next]);
    }
    return perimeter;
  }

  double _scoreRectangle(List<Offset> corners, Size imageSize) {
    if (corners.length != 4) return 0.0;
    
    // Basic scoring based on area and corner angles
    final area = _calculatePolygonArea(corners);
    final imageArea = imageSize.width * imageSize.height;
    final areaRatio = area / imageArea;
    
    // Prefer rectangles that cover reasonable portion of image
    if (areaRatio < 0.1 || areaRatio > 0.9) return 0.0;
    
    // Check corner angles
    final angles = _calculateCornerAngles(corners);
    final rightAngleScore = angles.where((angle) => 
      (angle - math.pi / 2).abs() < math.pi / 6 // 30 degrees tolerance
    ).length / 4.0;
    
    return areaRatio * 0.6 + rightAngleScore * 0.4;
  }

  double _calculatePolygonArea(List<Offset> corners) {
    if (corners.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < corners.length; i++) {
      final j = (i + 1) % corners.length;
      area += corners[i].dx * corners[j].dy;
      area -= corners[j].dx * corners[i].dy;
    }
    
    return area.abs() / 2.0;
  }

  /// Fast line detection (simplified for now)
  List<_FastLine> _detectFastLines(img.Image edges) {
    // Placeholder for Hough line detection
    // In a full implementation, this would detect lines in the edge image
    return [];
  }

  List<Offset> _rectangleFromLines(List<_FastLine> lines, Size imageSize) {
    // Placeholder for line-to-rectangle conversion
    // In a full implementation, this would find intersections of lines
    return [];
  }

  /// Fast confidence calculation
  double _calculateFastConfidence(List<Offset> corners, Size imageSize) {
    if (corners.length != 4) return 0.0;
    
    // Quick confidence based on area and corner angles
    final area = _calculatePolygonArea(corners);
    final imageArea = imageSize.width * imageSize.height;
    final areaScore = (area / imageArea).clamp(0.0, 1.0);
    
    // Simple angle check
    final angles = _calculateCornerAngles(corners);
    final angleScore = angles.where((angle) => 
      (angle - math.pi / 2).abs() < math.pi / 6
    ).length / 4.0;
    
    return (areaScore * 0.4 + angleScore * 0.6).clamp(0.0, 1.0);
  }

  List<double> _calculateCornerAngles(List<Offset> corners) {
    final angles = <double>[];
    for (int i = 0; i < corners.length; i++) {
      final prev = corners[(i - 1 + corners.length) % corners.length];
      final curr = corners[i];
      final next = corners[(i + 1) % corners.length];

      final ba = Offset(prev.dx - curr.dx, prev.dy - curr.dy);
      final bc = Offset(next.dx - curr.dx, next.dy - curr.dy);

      final dotProduct = ba.dx * bc.dx + ba.dy * bc.dy;
      final magnitudeBA = math.sqrt(ba.dx * ba.dx + ba.dy * ba.dy);
      final magnitudeBC = math.sqrt(bc.dx * bc.dx + bc.dy * bc.dy);

      if (magnitudeBA == 0 || magnitudeBC == 0) {
        angles.add(0.0);
      } else {
        final cosAngle = dotProduct / (magnitudeBA * magnitudeBC);
        angles.add(math.acos(cosAngle.clamp(-1.0, 1.0)));
      }
    }
    return angles;
  }

  /// Update stability tracking for auto-capture
  void _updateStabilityTracking(EdgeDetectionResult result) {
    _recentResults.add(result);
    
    // Keep only recent results
    const maxHistory = 5;
    if (_recentResults.length > maxHistory) {
      _recentResults.removeAt(0);
    }
    
    // Check stability
    if (_isDetectionStable() && result.confidence > _autoCaptureSettings.minConfidenceThreshold) {
      _lastStableDetection ??= DateTime.now();
    } else {
      _lastStableDetection = null;
    }
  }

  bool _isDetectionStable() {
    if (_recentResults.length < 3) return false;
    
    const double maxMovement = 15.0; // pixels
    final recent = _recentResults.length > 3 
        ? _recentResults.sublist(_recentResults.length - 3)
        : _recentResults;
    
    for (int i = 1; i < recent.length; i++) {
      final current = recent[i];
      final previous = recent[i - 1];
      
      if (current.corners.length != 4 || previous.corners.length != 4) {
        return false;
      }
      
      for (int j = 0; j < 4; j++) {
        final distance = _distance(current.corners[j], previous.corners[j]);
        if (distance > maxMovement) return false;
      }
    }
    
    return true;
  }

  double _distance(Offset a, Offset b) {
    return math.sqrt((a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy));
  }

  EdgeDetectionResult _getDefaultResult(Size previewSize) {
    return EdgeDetectionResult(
      corners: [],
      confidence: 0.0,
      method: 'none',
      processingTimeMs: 0,
      isRealtime: true,
      previewSize: previewSize,
    );
  }

  EdgeDetectionResult _getDefaultRectangle(Size imageSize) {
    final margin = 0.15;
    final corners = [
      Offset(imageSize.width * margin, imageSize.height * margin),
      Offset(imageSize.width * (1 - margin), imageSize.height * margin),
      Offset(imageSize.width * (1 - margin), imageSize.height * (1 - margin)),
      Offset(imageSize.width * margin, imageSize.height * (1 - margin)),
    ];

    return EdgeDetectionResult(
      corners: corners,
      confidence: 0.2,
      method: 'default',
      isRealtime: true,
    );
  }

  // Configure auto-capture settings
  void configureAutoCapture(AutoCaptureSettings settings) {
    _autoCaptureSettings = settings;
  }

  // Get auto-capture status
  AutoCaptureStatus getAutoCaptureStatus() {
    if (_recentResults.isEmpty) return AutoCaptureStatus.searching;
    
    final latest = _recentResults.last;
    if (latest.confidence < _autoCaptureSettings.minConfidenceThreshold) {
      return AutoCaptureStatus.lowConfidence;
    }
    
    if (_isDetectionStable()) {
      return AutoCaptureStatus.ready;
    }
    
    return AutoCaptureStatus.stabilizing;
  }

  // Check if ready for auto-capture
  bool isReadyForAutoCapture() {
    if (_lastStableDetection == null) return false;
    
    final stableDuration = DateTime.now().difference(_lastStableDetection!);
    return stableDuration >= _autoCaptureSettings.stabilityDuration;
  }

  // Reset detection history
  void resetDetectionHistory() {
    _recentResults.clear();
    _lastStableDetection = null;
    _frameCounter = 0;
  }

  /// Legacy method for backward compatibility with existing screens
  Future<EdgeDetectionResult> detectDocumentEdges({
    required String imagePath,
    Size? imageSize,
  }) async {
    try {
      // Load image from file
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        return EdgeDetectionResult(
          corners: [],
          confidence: 0.0,
          method: 'file_load_failed',
        );
      }

      // Use the provided imageSize or derive from image
      final size = imageSize ?? Size(image.width.toDouble(), image.height.toDouble());
      
      // Use the optimized detection on the full image
      return await _performOptimizedDetection(image, size);
      
    } catch (e) {
      debugPrint('Error detecting edges from file: $e');
      return EdgeDetectionResult(
        corners: [],
        confidence: 0.0,
        method: 'error',
      );
    }
  }
}

/// Enhanced result class with real-time metadata
class EdgeDetectionResult {
  final List<Offset> corners;
  final double confidence;
  final String method;
  final bool requiresManualAdjustment;
  final int processingTimeMs;
  final bool isRealtime;
  final bool isSkippedFrame;
  final Size? originalSize;
  final Size? detectionSize;
  final Size? previewSize;

  const EdgeDetectionResult({
    required this.corners,
    required this.confidence,
    required this.method,
    this.requiresManualAdjustment = false,
    this.processingTimeMs = 0,
    this.isRealtime = false,
    this.isSkippedFrame = false,
    this.originalSize,
    this.detectionSize,
    this.previewSize,
  });

  EdgeDetectionResult copyWith({
    List<Offset>? corners,
    double? confidence,
    String? method,
    bool? requiresManualAdjustment,
    int? processingTimeMs,
    bool? isRealtime,
    bool? isSkippedFrame,
    Size? originalSize,
    Size? detectionSize,
    Size? previewSize,
  }) {
    return EdgeDetectionResult(
      corners: corners ?? this.corners,
      confidence: confidence ?? this.confidence,
      method: method ?? this.method,
      requiresManualAdjustment: requiresManualAdjustment ?? this.requiresManualAdjustment,
      processingTimeMs: processingTimeMs ?? this.processingTimeMs,
      isRealtime: isRealtime ?? this.isRealtime,
      isSkippedFrame: isSkippedFrame ?? this.isSkippedFrame,
      originalSize: originalSize ?? this.originalSize,
      detectionSize: detectionSize ?? this.detectionSize,
      previewSize: previewSize ?? this.previewSize,
    );
  }
}

/// Auto-capture configuration
class AutoCaptureSettings {
  final bool enableAutoCapture;
  final double minConfidenceThreshold;
  final Duration stabilityDuration;
  final DocumentType? preferredDocumentType;

  const AutoCaptureSettings({
    this.enableAutoCapture = true,
    this.minConfidenceThreshold = 0.8,
    this.stabilityDuration = const Duration(milliseconds: 2000),
    this.preferredDocumentType,
  });
}

enum AutoCaptureStatus {
  disabled,
  searching,
  lowConfidence,
  stabilizing,
  ready,
}

enum DocumentType {
  receipt,
  a4Document,
  businessCard,
  whiteboard,
  idCard,
  photo,
  book,
  unknown,
}

class _FastLine {
  final Offset start;
  final Offset end;
  final double angle;

  _FastLine(this.start, this.end, this.angle);
}