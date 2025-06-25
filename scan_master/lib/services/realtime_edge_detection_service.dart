// lib/services/realtime_edge_detection_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

class RealtimeEdgeDetectionService {
  static RealtimeEdgeDetectionService? _instance;
  factory RealtimeEdgeDetectionService() => _instance ??= RealtimeEdgeDetectionService._internal();
  RealtimeEdgeDetectionService._internal();

  Isolate? _detectionIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _isInitialized = false;

  // Real-time detection parameters
  static const int _targetFrameRate = 5; // Process 5 frames per second
  static const double _minConfidenceThreshold = 0.6;
  static const double _maxProcessingTime = 200; // ms
  
  // Stability tracking
  List<DetectionResult> _recentResults = [];
  static const int _stabilityHistorySize = 3;
  
  StreamController<DetectionResult>? _detectionStreamController;
  Stream<DetectionResult>? _detectionStream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    _receivePort = ReceivePort();
    _detectionStreamController = StreamController<DetectionResult>.broadcast();
    _detectionStream = _detectionStreamController!.stream;

    // Start detection isolate
    _detectionIsolate = await Isolate.spawn(
      _detectionIsolateEntryPoint,
      _receivePort!.sendPort,
    );

    // Listen for results from isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _isInitialized = true;
      } else if (message is DetectionResult) {
        _handleDetectionResult(message);
      }
    });

    // Wait for initialization
    while (!_isInitialized) {
      await Future.delayed(Duration(milliseconds: 10));
    }
  }

  Stream<DetectionResult> get detectionStream {
    if (_detectionStream == null) {
      throw StateError('RealtimeEdgeDetectionService not initialized');
    }
    return _detectionStream!;
  }

  Future<void> processFrame(CameraImage cameraImage, Size previewSize) async {
    if (!_isInitialized || _sendPort == null) return;

    try {
      // Convert camera image to processable format
      final imageData = await _convertCameraImage(cameraImage);
      
      final request = DetectionRequest(
        imageData: imageData,
        width: cameraImage.width,
        height: cameraImage.height,
        previewSize: previewSize,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      _sendPort!.send(request);
    } catch (e) {
      debugPrint('Error processing frame: $e');
    }
  }

  Future<Uint8List> _convertCameraImage(CameraImage cameraImage) async {
    // Convert YUV420 to RGB
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    
    final Uint8List yPlane = cameraImage.planes[0].bytes;
    final Uint8List uPlane = cameraImage.planes[1].bytes;
    final Uint8List vPlane = cameraImage.planes[2].bytes;
    
    final image = img.Image(width: width, height: height);
    
    int yIndex = 0;
    int uvIndex = 0;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yValue = yPlane[yIndex];
        final int uValue = uPlane[uvIndex ~/ 2];
        final int vValue = vPlane[uvIndex ~/ 2];
        
        // YUV to RGB conversion
        int r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
        int g = (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128)).round().clamp(0, 255);
        int b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
        
        image.setPixelRgb(x, y, r, g, b);
        yIndex++;
        if (x % 2 == 1) uvIndex++;
      }
      if (y % 2 == 1) uvIndex = (uvIndex ~/ 2) * 2;
    }
    
    return Uint8List.fromList(img.encodeJpg(image, quality: 70));
  }

  void _handleDetectionResult(DetectionResult result) {
    // Add to recent results for stability tracking
    _recentResults.add(result);
    if (_recentResults.length > _stabilityHistorySize) {
      _recentResults.removeAt(0);
    }

    // Calculate stability score
    final stabilityScore = _calculateStabilityScore();
    final enhancedResult = DetectionResult(
      corners: result.corners,
      confidence: result.confidence,
      isStable: stabilityScore > 0.8,
      stabilityScore: stabilityScore,
      processingTime: result.processingTime,
      feedback: _generateFeedback(result, stabilityScore),
    );

    _detectionStreamController?.add(enhancedResult);
  }

  double _calculateStabilityScore() {
    if (_recentResults.length < 2) return 0.0;

    double totalDeviation = 0.0;
    int comparisons = 0;

    for (int i = 1; i < _recentResults.length; i++) {
      final current = _recentResults[i];
      final previous = _recentResults[i - 1];

      if (current.corners.length == 4 && previous.corners.length == 4) {
        for (int j = 0; j < 4; j++) {
          final distance = _calculateDistance(current.corners[j], previous.corners[j]);
          totalDeviation += distance;
          comparisons++;
        }
      }
    }

    if (comparisons == 0) return 0.0;

    final averageDeviation = totalDeviation / comparisons;
    
    // Lower deviation means higher stability
    // Normalize to 0-1 scale (assuming max reasonable deviation is 50 pixels)
    return (1.0 - (averageDeviation / 50.0)).clamp(0.0, 1.0);
  }

  double _calculateDistance(Offset a, Offset b) {
    return math.sqrt((a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy));
  }

  String _generateFeedback(DetectionResult result, double stabilityScore) {
    if (result.corners.isEmpty) {
      return "Position document in frame";
    }
    
    if (result.confidence < 0.4) {
      return "Move closer to document";
    }
    
    if (result.confidence < 0.6) {
      return "Improve lighting or focus";
    }
    
    if (stabilityScore < 0.5) {
      return "Hold steady";
    }
    
    if (result.confidence >= 0.8 && stabilityScore >= 0.8) {
      return "Perfect! Ready to capture";
    }
    
    return "Position document clearly";
  }

  void dispose() {
    _detectionIsolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _detectionStreamController?.close();
    _isInitialized = false;
    _instance = null;
  }

  // Isolate entry point for background processing
  static void _detectionIsolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    isolateReceivePort.listen((message) {
      if (message is DetectionRequest) {
        final result = _processDetectionRequest(message);
        mainSendPort.send(result);
      }
    });
  }

  static DetectionResult _processDetectionRequest(DetectionRequest request) {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Decode image
      final image = img.decodeImage(request.imageData);
      if (image == null) {
        return DetectionResult(
          corners: [],
          confidence: 0.0,
          isStable: false,
          stabilityScore: 0.0,
          processingTime: stopwatch.elapsedMilliseconds,
          feedback: "Failed to process image",
        );
      }

      // Resize for faster processing
      final processedImage = _preprocessImageForDetection(image);
      
      // Perform edge detection
      final corners = _detectDocumentCorners(processedImage);
      
      // Scale corners back to original size
      final scaledCorners = _scaleCorners(
        corners, 
        processedImage, 
        Size(request.width.toDouble(), request.height.toDouble())
      );
      
      // Calculate confidence based on corner quality
      final confidence = _calculateConfidence(scaledCorners, Size(request.width.toDouble(), request.height.toDouble()));
      
      stopwatch.stop();
      
      return DetectionResult(
        corners: scaledCorners,
        confidence: confidence,
        isStable: false, // Will be calculated in main isolate
        stabilityScore: 0.0, // Will be calculated in main isolate
        processingTime: stopwatch.elapsedMilliseconds,
        feedback: "",
      );
      
    } catch (e) {
      stopwatch.stop();
      return DetectionResult(
        corners: [],
        confidence: 0.0,
        isStable: false,
        stabilityScore: 0.0,
        processingTime: stopwatch.elapsedMilliseconds,
        feedback: "Detection error: $e",
      );
    }
  }

  static img.Image _preprocessImageForDetection(img.Image image) {
    // Resize to reasonable size for real-time processing
    const maxDimension = 640;
    
    img.Image processed = image;
    
    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        processed = img.copyResize(image, width: maxDimension);
      } else {
        processed = img.copyResize(image, height: maxDimension);
      }
    }
    
    // Convert to grayscale for edge detection
    processed = img.grayscale(processed);
    
    // Apply Gaussian blur to reduce noise
    processed = img.gaussianBlur(processed, radius: 1);
    
    return processed;
  }

  static List<Offset> _detectDocumentCorners(img.Image image) {
    // Multi-step edge detection approach optimized for real-time
    
    // Step 1: Canny edge detection
    final edges = _fastCannyEdgeDetection(image);
    
    // Step 2: Find contours
    final contours = _findContours(edges);
    
    // Step 3: Filter for document-like shapes
    final documentContours = _filterDocumentContours(contours, image);
    
    // Step 4: Get best rectangle
    if (documentContours.isNotEmpty) {
      return _getBestRectangle(documentContours.first);
    }
    
    return [];
  }

  static img.Image _fastCannyEdgeDetection(img.Image image) {
    // Simplified Canny edge detection for speed
    final width = image.width;
    final height = image.height;
    final result = img.Image(width: width, height: height);
    
    // Sobel edge detection
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        // Get surrounding pixels
        final tl = image.getPixel(x - 1, y - 1).luminance;
        final tm = image.getPixel(x, y - 1).luminance;
        final tr = image.getPixel(x + 1, y - 1).luminance;
        final ml = image.getPixel(x - 1, y).luminance;
        final mr = image.getPixel(x + 1, y).luminance;
        final bl = image.getPixel(x - 1, y + 1).luminance;
        final bm = image.getPixel(x, y + 1).luminance;
        final br = image.getPixel(x + 1, y + 1).luminance;
        
        // Sobel X and Y gradients
        final gx = (tr + 2 * mr + br) - (tl + 2 * ml + bl);
        final gy = (bl + 2 * bm + br) - (tl + 2 * tm + tr);
        
        // Gradient magnitude
        final magnitude = math.sqrt(gx * gx + gy * gy);
        
        // Threshold
        final edgeValue = magnitude > 50 ? 255 : 0;
        result.setPixelRgb(x, y, edgeValue, edgeValue, edgeValue);
      }
    }
    
    return result;
  }

  static List<List<Offset>> _findContours(img.Image edges) {
    final width = edges.width;
    final height = edges.height;
    final visited = List.generate(height, (_) => List.filled(width, false));
    final contours = <List<Offset>>[];
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!visited[y][x] && edges.getPixel(x, y).luminance > 128) {
          final contour = _traceContour(edges, x, y, visited);
          if (contour.length > 20) { // Minimum contour size
            contours.add(contour);
          }
        }
      }
    }
    
    return contours;
  }

  static List<Offset> _traceContour(img.Image edges, int startX, int startY, List<List<bool>> visited) {
    final contour = <Offset>[];
    final directions = [
      Offset(-1, -1), Offset(0, -1), Offset(1, -1),
      Offset(-1, 0),                 Offset(1, 0),
      Offset(-1, 1),  Offset(0, 1),  Offset(1, 1),
    ];

    var x = startX;
    var y = startY;
    
    while (x >= 0 && x < edges.width && y >= 0 && y < edges.height && !visited[y][x]) {
      visited[y][x] = true;
      contour.add(Offset(x.toDouble(), y.toDouble()));
      
      bool found = false;
      for (final dir in directions) {
        final newX = x + dir.dx.toInt();
        final newY = y + dir.dy.toInt();
        
        if (newX >= 0 && newX < edges.width &&
            newY >= 0 && newY < edges.height &&
            !visited[newY][newX] &&
            edges.getPixel(newX, newY).luminance > 128) {
          x = newX;
          y = newY;
          found = true;
          break;
        }
      }
      
      if (!found) break;
      if (contour.length > 1000) break; // Prevent infinite loops
    }

    return contour;
  }

  static List<List<Offset>> _filterDocumentContours(List<List<Offset>> contours, img.Image image) {
    final imageArea = image.width * image.height;
    final documentContours = <List<Offset>>[];

    for (final contour in contours) {
      final area = _calculateContourArea(contour);
      final areaRatio = area / imageArea;

      // Filter by area ratio (document should occupy reasonable portion of image)
      if (areaRatio < 0.1 || areaRatio > 0.9) continue;

      // Approximate to polygon
      final approximation = _douglasPeucker(contour, 10.0);
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

  static double _calculateContourArea(List<Offset> contour) {
    if (contour.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < contour.length; i++) {
      final j = (i + 1) % contour.length;
      area += contour[i].dx * contour[j].dy;
      area -= contour[j].dx * contour[i].dy;
    }
    return area.abs() / 2.0;
  }

  static List<Offset> _douglasPeucker(List<Offset> points, double epsilon) {
    if (points.length <= 2) return points;

    double maxDistance = 0.0;
    int maxIndex = 0;
    
    final start = points.first;
    final end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final distance = _pointToLineDistance(points[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    if (maxDistance > epsilon) {
      final leftPart = _douglasPeucker(points.sublist(0, maxIndex + 1), epsilon);
      final rightPart = _douglasPeucker(points.sublist(maxIndex), epsilon);
      
      return [...leftPart.sublist(0, leftPart.length - 1), ...rightPart];
    } else {
      return [start, end];
    }
  }

  static double _pointToLineDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final a = lineEnd.dy - lineStart.dy;
    final b = lineStart.dx - lineEnd.dx;
    final c = lineEnd.dx * lineStart.dy - lineStart.dx * lineEnd.dy;
    
    return (a * point.dx + b * point.dy + c).abs() / math.sqrt(a * a + b * b);
  }

  static List<Offset> _getBestRectangle(List<Offset> contour) {
    if (contour.length != 4) return contour;
    
    // Order corners: top-left, top-right, bottom-right, bottom-left
    final center = Offset(
      contour.map((c) => c.dx).reduce((a, b) => a + b) / 4,
      contour.map((c) => c.dy).reduce((a, b) => a + b) / 4,
    );

    contour.sort((a, b) {
      final angleA = math.atan2(a.dy - center.dy, a.dx - center.dx);
      final angleB = math.atan2(b.dy - center.dy, b.dx - center.dx);
      return angleA.compareTo(angleB);
    });

    return contour;
  }

  static List<Offset> _scaleCorners(List<Offset> corners, img.Image processedImage, Size originalSize) {
    if (corners.isEmpty) return corners;
    
    final scaleX = originalSize.width / processedImage.width;
    final scaleY = originalSize.height / processedImage.height;
    
    return corners.map((corner) => Offset(
      corner.dx * scaleX,
      corner.dy * scaleY,
    )).toList();
  }

  static double _calculateConfidence(List<Offset> corners, Size imageSize) {
    if (corners.length != 4) return 0.0;

    double confidence = 0.0;

    // Check area coverage
    final area = _calculateContourArea(corners);
    final imageArea = imageSize.width * imageSize.height;
    final areaRatio = area / imageArea;
    
    if (areaRatio >= 0.2 && areaRatio <= 0.8) {
      confidence += 0.4;
    }

    // Check if roughly rectangular
    final angles = _calculateCornerAngles(corners);
    double angleScore = 0.0;
    for (final angle in angles) {
      final deviationFromRightAngle = (angle - math.pi / 2).abs();
      if (deviationFromRightAngle < math.pi / 6) { // 30 degrees tolerance
        angleScore += 0.15; // 0.6 / 4 corners
      }
    }
    confidence += angleScore;

    return confidence.clamp(0.0, 1.0);
  }

  static List<double> _calculateCornerAngles(List<Offset> corners) {
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
}

// Data classes for communication between isolates
class DetectionRequest {
  final Uint8List imageData;
  final int width;
  final int height;
  final Size previewSize;
  final int timestamp;

  DetectionRequest({
    required this.imageData,
    required this.width,
    required this.height,
    required this.previewSize,
    required this.timestamp,
  });
}

class DetectionResult {
  final List<Offset> corners;
  final double confidence;
  final bool isStable;
  final double stabilityScore;
  final int processingTime;
  final String feedback;

  DetectionResult({
    required this.corners,
    required this.confidence,
    required this.isStable,
    required this.stabilityScore,
    required this.processingTime,
    required this.feedback,
  });
}