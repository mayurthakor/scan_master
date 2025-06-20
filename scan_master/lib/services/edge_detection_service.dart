// lib/services/edge_detection_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

class EdgeDetectionService {
  /// Detect document edges and return corner points
  static Future<List<Point>?> detectDocumentEdges(String imagePath) async {
    try {
      // Read and prepare image
      final imageFile = File(imagePath);
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      
      if (image == null) return null;
      
      // Resize for faster processing (keep aspect ratio)
      final processingImage = _resizeForProcessing(image);
      
      // Convert to grayscale for edge detection
      final grayImage = img.grayscale(processingImage);
      
      // Apply Gaussian blur to reduce noise
      final blurredImage = img.gaussianBlur(grayImage, radius: 2);
      
      // Enhance contrast for better edge detection
      final enhancedImage = img.adjustColor(blurredImage, contrast: 1.5);
      
      // Apply edge detection
      final edges = _detectEdgesSimple(enhancedImage);
      
      // Find document corners using contour approximation
      final corners = _findDocumentCorners(edges, processingImage);
      
      if (corners != null && corners.length == 4) {
        // Scale corners back to original image size
        final scaleX = image.width / processingImage.width;
        final scaleY = image.height / processingImage.height;
        
        return corners.map((point) => Point(
          (point.x * scaleX).round(),
          (point.y * scaleY).round(),
        )).toList();
      }
      
      return null;
    } catch (e) {
      print('Edge detection error: $e');
      return null;
    }
  }

  /// Crop and perspective correct the document
  static Future<String?> cropDocument(String imagePath, List<Point> corners) async {
    try {
      final imageFile = File(imagePath);
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      
      if (image == null) return null;
      
      // Order corners: top-left, top-right, bottom-right, bottom-left
      final orderedCorners = _orderCorners(corners);
      
      // Calculate target dimensions based on detected document
      final dimensions = _calculateTargetDimensions(orderedCorners);
      
      // Apply simple crop and perspective correction
      final croppedImage = _perspectiveTransformSimple(
        image, 
        orderedCorners, 
        dimensions.width, 
        dimensions.height
      );
      
      // Enhance the cropped document
      final enhancedImage = _enhanceDocument(croppedImage);
      
      // Save the result
      final directory = Directory.systemTemp;
      final outputPath = '${directory.path}/cropped_doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(enhancedImage, quality: 92));
      
      return outputPath;
    } catch (e) {
      print('Document cropping error: $e');
      return null;
    }
  }

  // Helper methods

  static img.Image _resizeForProcessing(img.Image image) {
    const maxDimension = 600; // Reduced for better performance
    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        return img.copyResize(image, width: maxDimension);
      } else {
        return img.copyResize(image, height: maxDimension);
      }
    }
    return image;
  }

  static img.Image _detectEdgesSimple(img.Image grayImage) {
    final width = grayImage.width;
    final height = grayImage.height;
    final edgeImage = img.Image(width: width, height: height);
    
    // Simple edge detection using gradient magnitude
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        // Calculate horizontal and vertical gradients
        final center = grayImage.getPixel(x, y).r;
        final left = grayImage.getPixel(x - 1, y).r;
        final right = grayImage.getPixel(x + 1, y).r;
        final top = grayImage.getPixel(x, y - 1).r;
        final bottom = grayImage.getPixel(x, y + 1).r;
        
        final gx = (right - left).abs();
        final gy = (bottom - top).abs();
        
        // Calculate gradient magnitude
        final magnitude = math.sqrt(gx * gx + gy * gy);
        
        // Apply threshold (adjust this value to fine-tune edge detection)
        final edgeValue = magnitude > 30 ? 255 : 0;
        edgeImage.setPixel(x, y, img.ColorRgba8(edgeValue, edgeValue, edgeValue, 255));
      }
    }
    
    return edgeImage;
  }

  static List<Point>? _findDocumentCorners(img.Image edgeImage, img.Image originalImage) {
    final width = edgeImage.width;
    final height = edgeImage.height;
    
    // Find edge points
    List<Point> edgePoints = [];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = edgeImage.getPixel(x, y);
        if (pixel.r > 128) { // White pixel = edge
          edgePoints.add(Point(x, y));
        }
      }
    }
    
    if (edgePoints.length < 50) return null; // Not enough edge points
    
    // Use Douglas-Peucker-like approach to find corner candidates
    final corners = _findCornerCandidates(edgePoints, width, height);
    
    // Validate corners form a reasonable quadrilateral
    if (corners.length == 4 && _isValidQuadrilateral(corners, width, height)) {
      return corners;
    }
    
    // Fallback: return image corners with margin
    final margin = math.min(width, height) * 0.1;
    return [
      Point(margin.toInt(), margin.toInt()),
      Point((width - margin).toInt(), margin.toInt()),
      Point((width - margin).toInt(), (height - margin).toInt()),
      Point(margin.toInt(), (height - margin).toInt()),
    ];
  }

  static List<Point> _findCornerCandidates(List<Point> edgePoints, int width, int height) {
    // Divide image into quadrants and find extreme points
    final centerX = width / 2;
    final centerY = height / 2;
    
    Point? topLeft, topRight, bottomLeft, bottomRight;
    double tlDist = double.infinity, trDist = double.infinity;
    double blDist = double.infinity, brDist = double.infinity;
    
    for (final point in edgePoints) {
      // Top-left quadrant
      if (point.x < centerX && point.y < centerY) {
        final dist = math.sqrt(point.x * point.x + point.y * point.y);
        if (dist < tlDist) {
          tlDist = dist;
          topLeft = point;
        }
      }
      // Top-right quadrant
      else if (point.x >= centerX && point.y < centerY) {
        final dist = math.sqrt((width - point.x) * (width - point.x) + point.y * point.y);
        if (dist < trDist) {
          trDist = dist;
          topRight = point;
        }
      }
      // Bottom-left quadrant
      else if (point.x < centerX && point.y >= centerY) {
        final dist = math.sqrt(point.x * point.x + (height - point.y) * (height - point.y));
        if (dist < blDist) {
          blDist = dist;
          bottomLeft = point;
        }
      }
      // Bottom-right quadrant
      else {
        final dist = math.sqrt((width - point.x) * (width - point.x) + (height - point.y) * (height - point.y));
        if (dist < brDist) {
          brDist = dist;
          bottomRight = point;
        }
      }
    }
    
    List<Point> corners = [];
    if (topLeft != null) corners.add(topLeft);
    if (topRight != null) corners.add(topRight);
    if (bottomRight != null) corners.add(bottomRight);
    if (bottomLeft != null) corners.add(bottomLeft);
    
    return corners;
  }

  static bool _isValidQuadrilateral(List<Point> corners, int width, int height) {
    if (corners.length != 4) return false;
    
    // Check minimum area
    final area = _calculatePolygonArea(corners);
    final imageArea = width * height;
    final minAreaRatio = 0.1; // At least 10% of image area
    
    if (area < imageArea * minAreaRatio) return false;
    
    // Check that corners are reasonably spread out
    final orderedCorners = _orderCorners(corners);
    final minDistance = math.min(width, height) * 0.2;
    
    for (int i = 0; i < 4; i++) {
      final current = orderedCorners[i];
      final next = orderedCorners[(i + 1) % 4];
      final distance = math.sqrt(
        math.pow(current.x - next.x, 2) + math.pow(current.y - next.y, 2)
      );
      if (distance < minDistance) return false;
    }
    
    return true;
  }

  static double _calculatePolygonArea(List<Point> corners) {
    double area = 0;
    for (int i = 0; i < corners.length; i++) {
      final current = corners[i];
      final next = corners[(i + 1) % corners.length];
      area += (current.x * next.y) - (next.x * current.y);
    }
    return area.abs() / 2;
  }

  static List<Point> _orderCorners(List<Point> corners) {
    if (corners.length != 4) return corners;
    
    // Sort by sum (x + y) to find top-left and bottom-right
    corners.sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));
    final topLeft = corners[0];
    final bottomRight = corners[3];
    
    // Sort by difference (x - y) to find top-right and bottom-left
    corners.sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));
    final topRight = corners[3];
    final bottomLeft = corners[0];
    
    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  static ({int width, int height}) _calculateTargetDimensions(List<Point> orderedCorners) {
    // Calculate width from top and bottom edges
    final topWidth = math.sqrt(
      math.pow(orderedCorners[1].x - orderedCorners[0].x, 2) +
      math.pow(orderedCorners[1].y - orderedCorners[0].y, 2)
    );
    final bottomWidth = math.sqrt(
      math.pow(orderedCorners[2].x - orderedCorners[3].x, 2) +
      math.pow(orderedCorners[2].y - orderedCorners[3].y, 2)
    );
    final width = ((topWidth + bottomWidth) / 2).round();
    
    // Calculate height from left and right edges
    final leftHeight = math.sqrt(
      math.pow(orderedCorners[3].x - orderedCorners[0].x, 2) +
      math.pow(orderedCorners[3].y - orderedCorners[0].y, 2)
    );
    final rightHeight = math.sqrt(
      math.pow(orderedCorners[2].x - orderedCorners[1].x, 2) +
      math.pow(orderedCorners[2].y - orderedCorners[1].y, 2)
    );
    final height = ((leftHeight + rightHeight) / 2).round();
    
    return (width: width, height: height);
  }

  static img.Image _perspectiveTransformSimple(
    img.Image source, 
    List<Point> corners, 
    int targetWidth, 
    int targetHeight
  ) {
    final result = img.Image(width: targetWidth, height: targetHeight);
    final orderedCorners = _orderCorners(corners);
    
    // Simple bilinear transformation (approximation of perspective)
    for (int y = 0; y < targetHeight; y++) {
      for (int x = 0; x < targetWidth; x++) {
        final normalizedX = x / targetWidth;
        final normalizedY = y / targetHeight;
        
        // Bilinear interpolation to map target coordinates to source
        final sourceX = _bilinearInterpolate(
          orderedCorners[0].x.toDouble(), orderedCorners[1].x.toDouble(),
          orderedCorners[3].x.toDouble(), orderedCorners[2].x.toDouble(),
          normalizedX, normalizedY
        ).clamp(0, source.width - 1);
        
        final sourceY = _bilinearInterpolate(
          orderedCorners[0].y.toDouble(), orderedCorners[1].y.toDouble(),
          orderedCorners[3].y.toDouble(), orderedCorners[2].y.toDouble(),
          normalizedX, normalizedY
        ).clamp(0, source.height - 1);
        
        final sourcePixel = source.getPixel(sourceX.toInt(), sourceY.toInt());
        result.setPixel(x, y, sourcePixel);
      }
    }
    
    return result;
  }

  static double _bilinearInterpolate(double tl, double tr, double bl, double br, double x, double y) {
    final top = tl + (tr - tl) * x;
    final bottom = bl + (br - bl) * x;
    return top + (bottom - top) * y;
  }

  static img.Image _enhanceDocument(img.Image image) {
    // Apply document-specific enhancements
    var enhanced = img.adjustColor(image,
      contrast: 1.4,
      brightness: 1.15,
      saturation: 0.7,
    );
    
    // Optional: Apply slight sharpening by adjusting contrast in a second pass
    enhanced = img.adjustColor(enhanced, contrast: 1.1);
    
    return enhanced;
  }
}

class Point {
  final int x;
  final int y;
  
  Point(this.x, this.y);
  
  @override
  String toString() => 'Point($x, $y)';
}