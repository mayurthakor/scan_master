// lib/services/document_type_recognition_service.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'enhanced_edge_detection_service.dart';

class DocumentTypeRecognitionService {
  static DocumentTypeRecognitionService? _instance;
  static DocumentTypeRecognitionService get instance => 
      _instance ??= DocumentTypeRecognitionService._();
  
  DocumentTypeRecognitionService._();

  /// Analyze document type with advanced classification
  Future<DocumentAnalysisResult> analyzeDocument({
    required String imagePath,
    required List<Offset> corners,
    required Size imageSize,
  }) async {
    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Extract document region
      final documentRegion = await _extractDocumentRegion(image, corners);
      
      // Perform multi-level analysis
      final primaryType = await _classifyPrimaryType(documentRegion);
      final detailedAnalysis = await _performDetailedAnalysis(documentRegion, primaryType);
      final qualityMetrics = await _analyzeQuality(documentRegion, primaryType);
      final optimizationSettings = _getOptimizationSettings(primaryType, detailedAnalysis);
      
      return DocumentAnalysisResult(
        documentType: primaryType,
        confidence: detailedAnalysis.confidence,
        subType: detailedAnalysis.subType,
        textRegions: detailedAnalysis.textRegions,
        logoRegions: detailedAnalysis.logoRegions,
        qualityMetrics: qualityMetrics,
        optimizationSettings: optimizationSettings,
        processingRecommendations: detailedAnalysis.recommendations,
      );
    } catch (e) {
      print('Document analysis error: $e');
      return DocumentAnalysisResult.unknown();
    }
  }

  /// Extract document region from full image using detected corners
  Future<img.Image> _extractDocumentRegion(img.Image image, List<Offset> corners) async {
    if (corners.length != 4) {
      return image; // Return original if corners are invalid
    }

    // Calculate bounding rectangle
    final boundingRect = _calculateBoundingRect(corners);
    
    // Extract region with some padding
    final padding = 10;
    final left = math.max(0, boundingRect.left.toInt() - padding);
    final top = math.max(0, boundingRect.top.toInt() - padding);
    final right = math.min(image.width, boundingRect.right.toInt() + padding);
    final bottom = math.min(image.height, boundingRect.bottom.toInt() + padding);
    
    return img.copyCrop(image, 
      x: left, 
      y: top, 
      width: right - left, 
      height: bottom - top
    );
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

  /// Primary document type classification
  Future<DocumentType> _classifyPrimaryType(img.Image documentRegion) async {
    final aspectRatio = documentRegion.width / documentRegion.height;
    final features = await _extractDocumentFeatures(documentRegion);
    
    // Multi-criteria classification
    final scores = <DocumentType, double>{};
    
    // Aspect ratio scoring
    scores[DocumentType.a4Document] = _scoreAspectRatio(aspectRatio, [0.707, 1.414]);
    scores[DocumentType.receipt] = _scoreAspectRatio(aspectRatio, [0.3, 0.8]);
    scores[DocumentType.businessCard] = _scoreAspectRatio(aspectRatio, [1.586, 0.63]);
    scores[DocumentType.idCard] = _scoreAspectRatio(aspectRatio, [1.586, 0.63]);
    scores[DocumentType.photo] = _scoreAspectRatio(aspectRatio, [0.75, 1.33, 1.0]);
    scores[DocumentType.book] = _scoreAspectRatio(aspectRatio, [0.6, 0.8]);
    scores[DocumentType.whiteboard] = _scoreAspectRatio(aspectRatio, [1.33, 1.77]);
    
    // Feature-based scoring
    _applyFeatureScoring(scores, features);
    
    // Size-based scoring
    _applySizeScoring(scores, documentRegion);
    
    // Return type with highest score
    var bestType = DocumentType.unknown;
    var bestScore = 0.0;
    
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestType = entry.key;
      }
    }
    
    return bestScore > 0.5 ? bestType : DocumentType.unknown;
  }

  double _scoreAspectRatio(double actualRatio, List<double> expectedRatios) {
    double bestScore = 0.0;
    for (final expectedRatio in expectedRatios) {
      final score = 1.0 - math.min(1.0, (actualRatio - expectedRatio).abs() / expectedRatio);
      bestScore = math.max(bestScore, score);
    }
    return bestScore;
  }

  /// Extract document features for classification
  Future<DocumentFeatures> _extractDocumentFeatures(img.Image image) async {
    // Convert to grayscale for analysis
    final grayImage = img.grayscale(image);
    
    // Analyze text content
    final textDensity = _analyzeTextDensity(grayImage);
    final lineStructure = _analyzeLineStructure(grayImage);
    
    // Analyze visual elements
    final logoPresence = _detectLogoRegions(grayImage);
    final colorProfile = _analyzeColorProfile(image);
    
    // Analyze layout
    final layoutStructure = _analyzeLayoutStructure(grayImage);
    
    return DocumentFeatures(
      textDensity: textDensity,
      lineStructure: lineStructure,
      logoPresence: logoPresence,
      colorProfile: colorProfile,
      layoutStructure: layoutStructure,
    );
  }

  double _analyzeTextDensity(img.Image grayImage) {
    // Apply edge detection to find text-like regions
    final edges = img.sobel(grayImage);
    
    int edgePixels = 0;
    final totalPixels = edges.width * edges.height;
    
    for (int y = 0; y < edges.height; y++) {
      for (int x = 0; x < edges.width; x++) {
        final pixel = edges.getPixel(x, y);
        final intensity = img.getLuminance(pixel);
        if (intensity > 128) edgePixels++;
      }
    }
    
    return edgePixels / totalPixels;
  }

  LineStructure _analyzeLineStructure(img.Image grayImage) {
    // Detect horizontal and vertical lines using projection
    final horizontalProjection = _calculateHorizontalProjection(grayImage);
    final verticalProjection = _calculateVerticalProjection(grayImage);
    
    final horizontalLines = _detectLinesInProjection(horizontalProjection);
    final verticalLines = _detectLinesInProjection(verticalProjection);
    
    return LineStructure(
      horizontalLineCount: horizontalLines.length,
      verticalLineCount: verticalLines.length,
      hasTableStructure: horizontalLines.length > 2 && verticalLines.length > 1,
      textLineSpacing: _calculateAverageSpacing(horizontalLines),
    );
  }

  List<double> _calculateHorizontalProjection(img.Image image) {
    final projection = <double>[];
    
    for (int y = 0; y < image.height; y++) {
      double sum = 0.0;
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        sum += 255 - img.getLuminance(pixel); // Invert for dark text on light background
      }
      projection.add(sum / image.width);
    }
    
    return projection;
  }

  List<double> _calculateVerticalProjection(img.Image image) {
    final projection = <double>[];
    
    for (int x = 0; x < image.width; x++) {
      double sum = 0.0;
      for (int y = 0; y < image.height; y++) {
        final pixel = image.getPixel(x, y);
        sum += 255 - img.getLuminance(pixel);
      }
      projection.add(sum / image.height);
    }
    
    return projection;
  }

  List<int> _detectLinesInProjection(List<double> projection) {
    final lines = <int>[];
    final threshold = _calculateProjectionThreshold(projection);
    bool inLine = false;
    
    for (int i = 0; i < projection.length; i++) {
      if (projection[i] > threshold && !inLine) {
        lines.add(i);
        inLine = true;
      } else if (projection[i] <= threshold && inLine) {
        inLine = false;
      }
    }
    
    return lines;
  }

  double _calculateProjectionThreshold(List<double> projection) {
    final sorted = List<double>.from(projection)..sort();
    final percentile75 = sorted[(sorted.length * 0.75).floor()];
    return percentile75 * 0.3; // 30% of 75th percentile
  }

  double _calculateAverageSpacing(List<int> lines) {
    if (lines.length < 2) return 0.0;
    
    double totalSpacing = 0.0;
    for (int i = 1; i < lines.length; i++) {
      totalSpacing += lines[i] - lines[i - 1];
    }
    
    return totalSpacing / (lines.length - 1);
  }

  LogoPresence _detectLogoRegions(img.Image grayImage) {
    // Simplified logo detection based on connected components
    final connectedComponents = _findConnectedComponents(grayImage);
    
    // Filter components by size and shape to identify potential logos
    final logoComponents = connectedComponents.where((component) {
      final area = component.points.length;
      final boundingBox = _getComponentBoundingBox(component);
      final aspectRatio = boundingBox.width / boundingBox.height;
      
      // Logo characteristics: medium size, not extremely elongated
      return area > 100 && 
             area < (grayImage.width * grayImage.height * 0.1) &&
             aspectRatio > 0.3 && 
             aspectRatio < 3.0;
    }).toList();
    
    return LogoPresence(
      hasLogo: logoComponents.isNotEmpty,
      logoCount: logoComponents.length,
      logoRegions: logoComponents.map((c) => _getComponentBoundingBox(c)).toList(),
    );
  }

  List<ConnectedComponent> _findConnectedComponents(img.Image image) {
    // Simplified connected component analysis
    final visited = List.generate(
      image.height,
      (y) => List.filled(image.width, false),
    );
    
    final components = <ConnectedComponent>[];
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        if (!visited[y][x] && _isPixelOfInterest(image, x, y)) {
          final component = _traceComponent(image, x, y, visited);
          if (component.points.length > 10) { // Minimum component size
            components.add(component);
          }
        }
      }
    }
    
    return components;
  }

  bool _isPixelOfInterest(img.Image image, int x, int y) {
    final pixel = image.getPixel(x, y);
    final luminance = img.getLuminance(pixel);
    return luminance < 128; // Dark pixels (potential text/graphics)
  }

  ConnectedComponent _traceComponent(
    img.Image image,
    int startX,
    int startY,
    List<List<bool>> visited,
  ) {
    final points = <Offset>[];
    final stack = <Offset>[Offset(startX.toDouble(), startY.toDouble())];
    
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final x = current.dx.toInt();
      final y = current.dy.toInt();
      
      if (x < 0 || x >= image.width || y < 0 || y >= image.height || visited[y][x]) {
        continue;
      }
      
      if (!_isPixelOfInterest(image, x, y)) continue;
      
      visited[y][x] = true;
      points.add(current);
      
      // Add 8-connected neighbors
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          stack.add(Offset((x + dx).toDouble(), (y + dy).toDouble()));
        }
      }
    }
    
    return ConnectedComponent(points: points);
  }

  Rect _getComponentBoundingBox(ConnectedComponent component) {
    if (component.points.isEmpty) return Rect.zero;
    
    double minX = component.points.first.dx;
    double maxX = component.points.first.dx;
    double minY = component.points.first.dy;
    double maxY = component.points.first.dy;
    
    for (final point in component.points) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  ColorProfile _analyzeColorProfile(img.Image image) {
    final colorCounts = <int, int>{};
    int totalPixels = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel).round();
        colorCounts[luminance] = (colorCounts[luminance] ?? 0) + 1;
        totalPixels++;
      }
    }
    
    // Calculate color distribution metrics
    final sortedLuminances = colorCounts.keys.toList()..sort();
    final darkPixels = colorCounts.entries
        .where((e) => e.key < 85)
        .map((e) => e.value)
        .fold(0, (a, b) => a + b);
    final lightPixels = colorCounts.entries
        .where((e) => e.key > 170)
        .map((e) => e.value)
        .fold(0, (a, b) => a + b);
    
    return ColorProfile(
      isDarkOnLight: darkPixels < lightPixels,
      contrast: _calculateContrast(colorCounts),
      colorComplexity: colorCounts.length / 256.0,
      backgroundLuminance: _estimateBackgroundLuminance(colorCounts),
    );
  }

  double _calculateContrast(Map<int, int> colorCounts) {
    if (colorCounts.isEmpty) return 0.0;
    
    final luminances = colorCounts.keys.toList();
    final minLum = luminances.reduce(math.min);
    final maxLum = luminances.reduce(math.max);
    
    return (maxLum - minLum) / 255.0;
  }

  double _estimateBackgroundLuminance(Map<int, int> colorCounts) {
    // Find the most common luminance value (likely background)
    var maxCount = 0;
    var backgroundLuminance = 255.0;
    
    for (final entry in colorCounts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        backgroundLuminance = entry.key.toDouble();
      }
    }
    
    return backgroundLuminance / 255.0;
  }

  LayoutStructure _analyzeLayoutStructure(img.Image grayImage) {
    // Divide image into regions and analyze content distribution
    final regions = _divideIntoRegions(grayImage, 3, 3); // 3x3 grid
    final regionDensities = regions.map(_calculateRegionDensity).toList();
    
    return LayoutStructure(
      hasHeader: regionDensities[0] > regionDensities[3] && regionDensities[0] > regionDensities[6],
      hasFooter: regionDensities[6] > regionDensities[3] && regionDensities[6] > regionDensities[0],
      isCentered: regionDensities[4] > _averageOuterRegions(regionDensities),
      contentDistribution: regionDensities,
    );
  }

  List<img.Image> _divideIntoRegions(img.Image image, int rows, int cols) {
    final regions = <img.Image>[];
    final regionWidth = image.width ~/ cols;
    final regionHeight = image.height ~/ rows;
    
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final x = col * regionWidth;
        final y = row * regionHeight;
        final width = (col == cols - 1) ? image.width - x : regionWidth;
        final height = (row == rows - 1) ? image.height - y : regionHeight;
        
        final region = img.copyCrop(image, x: x, y: y, width: width, height: height);
        regions.add(region);
      }
    }
    
    return regions;
  }

  double _calculateRegionDensity(img.Image region) {
    int darkPixels = 0;
    final totalPixels = region.width * region.height;
    
    for (int y = 0; y < region.height; y++) {
      for (int x = 0; x < region.width; x++) {
        final pixel = region.getPixel(x, y);
        final luminance = img.getLuminance(pixel);
        if (luminance < 128) darkPixels++;
      }
    }
    
    return darkPixels / totalPixels;
  }

  double _averageOuterRegions(List<double> regionDensities) {
    // Average of regions 0,1,2,3,5,6,7,8 (excluding center region 4)
    final outerRegions = [0,1,2,3,5,6,7,8];
    double sum = 0.0;
    for (final index in outerRegions) {
      if (index < regionDensities.length) {
        sum += regionDensities[index];
      }
    }
    return sum / outerRegions.length;
  }

  void _applyFeatureScoring(Map<DocumentType, double> scores, DocumentFeatures features) {
    // Receipt scoring
    scores[DocumentType.receipt] = (scores[DocumentType.receipt] ?? 0.0) + 
        (features.lineStructure.horizontalLineCount > 5 ? 0.3 : 0.0) +
        (features.textDensity > 0.1 ? 0.2 : 0.0);
    
    // Business card scoring
    scores[DocumentType.businessCard] = (scores[DocumentType.businessCard] ?? 0.0) + 
        (features.logoPresence.hasLogo ? 0.4 : 0.0) +
        (features.textDensity < 0.15 ? 0.2 : 0.0);
    
    // A4 document scoring
    scores[DocumentType.a4Document] = (scores[DocumentType.a4Document] ?? 0.0) + 
        (features.layoutStructure.hasHeader ? 0.2 : 0.0) +
        (features.lineStructure.textLineSpacing > 10 ? 0.2 : 0.0);
    
    // Whiteboard scoring
    scores[DocumentType.whiteboard] = (scores[DocumentType.whiteboard] ?? 0.0) + 
        (features.colorProfile.backgroundLuminance > 0.8 ? 0.3 : 0.0) +
        (features.textDensity < 0.05 ? 0.2 : 0.0);
  }

  void _applySizeScoring(Map<DocumentType, double> scores, img.Image documentRegion) {
    final area = documentRegion.width * documentRegion.height;
    
    // Small documents (business cards, ID cards)
    if (area < 50000) {
      scores[DocumentType.businessCard] = (scores[DocumentType.businessCard] ?? 0.0) + 0.2;
      scores[DocumentType.idCard] = (scores[DocumentType.idCard] ?? 0.0) + 0.2;
    }
    
    // Large documents (A4, whiteboards)
    if (area > 200000) {
      scores[DocumentType.a4Document] = (scores[DocumentType.a4Document] ?? 0.0) + 0.2;
      scores[DocumentType.whiteboard] = (scores[DocumentType.whiteboard] ?? 0.0) + 0.2;
    }
  }

  /// Perform detailed analysis based on primary type
  Future<DetailedAnalysis> _performDetailedAnalysis(
    img.Image documentRegion,
    DocumentType primaryType,
  ) async {
    switch (primaryType) {
      case DocumentType.receipt:
        return _analyzeReceipt(documentRegion);
      case DocumentType.businessCard:
        return _analyzeBusinessCard(documentRegion);
      case DocumentType.a4Document:
        return _analyzeA4Document(documentRegion);
      case DocumentType.idCard:
        return _analyzeIdCard(documentRegion);
      default:
        return _analyzeGenericDocument(documentRegion);
    }
  }

  Future<DetailedAnalysis> _analyzeReceipt(img.Image documentRegion) async {
    // Receipt-specific analysis
    final textRegions = _detectReceiptTextRegions(documentRegion);
    final totalSection = _detectReceiptTotalSection(documentRegion);
    
    return DetailedAnalysis(
      confidence: 0.8,
      subType: 'retail_receipt',
      textRegions: textRegions,
      logoRegions: [],
      recommendations: [
        'Ensure the total amount is clearly visible',
        'Check that receipt header is not cut off',
        'Verify all text lines are readable',
      ],
    );
  }

  Future<DetailedAnalysis> _analyzeBusinessCard(img.Image documentRegion) async {
    // Business card specific analysis
    final logoRegions = _detectBusinessCardLogos(documentRegion);
    final contactRegions = _detectContactInformation(documentRegion);
    
    return DetailedAnalysis(
      confidence: 0.85,
      subType: 'professional_card',
      textRegions: contactRegions,
      logoRegions: logoRegions,
      recommendations: [
        'Ensure all contact details are clearly visible',
        'Check logo clarity and color accuracy',
        'Verify card orientation is correct',
      ],
    );
  }

  Future<DetailedAnalysis> _analyzeA4Document(img.Image documentRegion) async {
    // A4 document analysis
    final textRegions = _detectDocumentTextBlocks(documentRegion);
    final headerFooter = _detectHeaderFooterRegions(documentRegion);
    
    return DetailedAnalysis(
      confidence: 0.75,
      subType: 'standard_document',
      textRegions: textRegions,
      logoRegions: [],
      recommendations: [
        'Ensure document is properly aligned',
        'Check that margins are not cut off',
        'Verify text is sharp and readable',
      ],
    );
  }

  Future<DetailedAnalysis> _analyzeIdCard(img.Image documentRegion) async {
    // ID card analysis
    final photoRegion = _detectIdCardPhoto(documentRegion);
    final textRegions = _detectIdCardTextFields(documentRegion);
    
    return DetailedAnalysis(
      confidence: 0.9,
      subType: 'identification_card',
      textRegions: textRegions,
      logoRegions: photoRegion != null ? [photoRegion] : [],
      recommendations: [
        'Ensure photo is clearly visible',
        'Check that all text fields are readable',
        'Verify card security features are captured',
      ],
    );
  }

  Future<DetailedAnalysis> _analyzeGenericDocument(img.Image documentRegion) async {
    return DetailedAnalysis(
      confidence: 0.5,
      subType: 'unknown',
      textRegions: [],
      logoRegions: [],
      recommendations: [
        'Position document clearly in frame',
        'Ensure adequate lighting',
        'Check focus and stability',
      ],
    );
  }

  List<Rect> _detectReceiptTextRegions(img.Image image) {
    // Simplified receipt text detection
    final horizontalProjection = _calculateHorizontalProjection(image);
    final textLines = _detectLinesInProjection(horizontalProjection);
    
    return textLines.map((lineY) => Rect.fromLTWH(
      0, 
      lineY.toDouble() - 5, 
      image.width.toDouble(), 
      10,
    )).toList();
  }

  Rect? _detectReceiptTotalSection(img.Image image) {
    // Look for total section in bottom third of receipt
    final bottomThird = image.height * 2 ~/ 3;
    return Rect.fromLTWH(
      0, 
      bottomThird.toDouble(), 
      image.width.toDouble(), 
      (image.height - bottomThird).toDouble(),
    );
  }

  List<Rect> _detectBusinessCardLogos(img.Image image) {
    // Detect potential logo regions (usually in corners or center)
    final logoRegions = <Rect>[];
    
    // Check corners and center for logo-like regions
    final regions = [
      Rect.fromLTWH(0, 0, image.width * 0.3, image.height * 0.3), // Top-left
      Rect.fromLTWH(image.width * 0.7, 0, image.width * 0.3, image.height * 0.3), // Top-right
      Rect.fromLTWH(image.width * 0.35, image.height * 0.35, image.width * 0.3, image.height * 0.3), // Center
    ];
    
    for (final region in regions) {
      if (_hasLogoLikeContent(image, region)) {
        logoRegions.add(region);
      }
    }
    
    return logoRegions;
  }

  bool _hasLogoLikeContent(img.Image image, Rect region) {
    // Simplified logo detection based on color variance
    final colors = <int, int>{};
    int pixelCount = 0;
    
    for (int y = region.top.toInt(); y < region.bottom.toInt() && y < image.height; y++) {
      for (int x = region.left.toInt(); x < region.right.toInt() && x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel).round();
        colors[luminance] = (colors[luminance] ?? 0) + 1;
        pixelCount++;
      }
    }
    
    // Logo regions typically have more color variation than text regions
    return colors.length > (pixelCount * 0.1);
  }

  List<Rect> _detectContactInformation(img.Image image) {
    // Detect text regions that likely contain contact info
    return [
      Rect.fromLTWH(0, image.height * 0.6, image.width.toDouble(), image.height * 0.4),
    ];
  }

  List<Rect> _detectDocumentTextBlocks(img.Image image) {
    // Detect main content areas in document
    return [
      Rect.fromLTWH(image.width * 0.1, image.height * 0.1, image.width * 0.8, image.height * 0.8),
    ];
  }

  List<Rect> _detectHeaderFooterRegions(img.Image image) {
    return [
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height * 0.15), // Header
      Rect.fromLTWH(0, image.height * 0.85, image.width.toDouble(), image.height * 0.15), // Footer
    ];
  }

  Rect? _detectIdCardPhoto(img.Image image) {
    // Look for photo region (typically left side of ID card)
    return Rect.fromLTWH(0, image.height * 0.2, image.width * 0.4, image.height * 0.6);
  }

  List<Rect> _detectIdCardTextFields(img.Image image) {
    // Detect text field regions in ID card
    return [
      Rect.fromLTWH(image.width * 0.5, image.height * 0.2, image.width * 0.5, image.height * 0.6),
    ];
  }

  /// Analyze document quality metrics
  Future<QualityMetrics> _analyzeQuality(img.Image documentRegion, DocumentType documentType) async {
    final sharpness = _calculateSharpness(documentRegion);
    final brightness = _calculateBrightness(documentRegion);
    final contrast = _calculateImageContrast(documentRegion);
    final skew = _calculateSkew(documentRegion);
    
    return QualityMetrics(
      sharpness: sharpness,
      brightness: brightness,
      contrast: contrast,
      skew: skew,
      overallScore: _calculateOverallQualityScore(sharpness, brightness, contrast, skew),
      isAcceptable: _isQualityAcceptable(sharpness, brightness, contrast, skew, documentType),
    );
  }

  double _calculateSharpness(img.Image image) {
    // Use Laplacian variance to measure sharpness
    final grayImage = img.grayscale(image);
    double variance = 0.0;
    int count = 0;
    
    for (int y = 1; y < grayImage.height - 1; y++) {
      for (int x = 1; x < grayImage.width - 1; x++) {
        // Apply Laplacian kernel
        final center = img.getLuminance(grayImage.getPixel(x, y));
        final top = img.getLuminance(grayImage.getPixel(x, y - 1));
        final bottom = img.getLuminance(grayImage.getPixel(x, y + 1));
        final left = img.getLuminance(grayImage.getPixel(x - 1, y));
        final right = img.getLuminance(grayImage.getPixel(x + 1, y));
        
        final laplacian = (4 * center - top - bottom - left - right).abs();
        variance += laplacian * laplacian;
        count++;
      }
    }
    
    return math.sqrt(variance / count) / 255.0; // Normalize to 0-1
  }

  double _calculateBrightness(img.Image image) {
    double totalBrightness = 0.0;
    int pixelCount = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        totalBrightness += img.getLuminance(pixel);
        pixelCount++;
      }
    }
    
    return (totalBrightness / pixelCount) / 255.0; // Normalize to 0-1
  }

  double _calculateImageContrast(img.Image image) {
    final luminances = <double>[];
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        luminances.add(img.getLuminance(pixel).toDouble());
      }
    }
    
    luminances.sort();
    final p5 = luminances[(luminances.length * 0.05).floor()];
    final p95 = luminances[(luminances.length * 0.95).floor()];
    
    return (p95 - p5) / 255.0; // Normalize to 0-1
  }

  double _calculateSkew(img.Image image) {
    // Simplified skew detection using line analysis
    final grayImage = img.grayscale(image);
    final edges = img.sobel(grayImage);
    
    // Use Hough transform to detect dominant line angles
    final angles = _detectDominantAngles(edges);
    
    if (angles.isEmpty) return 0.0;
    
    // Find the angle closest to horizontal
    double minDeviation = double.infinity;
    for (final angle in angles) {
      final deviation = (angle % (math.pi / 2)).abs();
      minDeviation = math.min(minDeviation, deviation);
    }
    
    return minDeviation / (math.pi / 2); // Normalize to 0-1
  }

  List<double> _detectDominantAngles(img.Image edges) {
    // Simplified angle detection
    final angleVotes = <int, int>{}; // angle in degrees -> vote count
    
    for (int y = 1; y < edges.height - 1; y++) {
      for (int x = 1; x < edges.width - 1; x++) {
        final pixel = edges.getPixel(x, y);
        final intensity = img.getLuminance(pixel);
        
        if (intensity > 128) { // Edge pixel
          // Calculate gradient direction
          final gx = img.getLuminance(edges.getPixel(x + 1, y)) - 
                    img.getLuminance(edges.getPixel(x - 1, y));
          final gy = img.getLuminance(edges.getPixel(x, y + 1)) - 
                    img.getLuminance(edges.getPixel(x, y - 1));
          
          if (gx != 0 || gy != 0) {
            final angle = math.atan2(gy, gx);
            final angleDegrees = (angle * 180 / math.pi).round();
            angleVotes[angleDegrees] = (angleVotes[angleDegrees] ?? 0) + 1;
          }
        }
      }
    }
    
    // Return top angles by vote count
    final sortedAngles = angleVotes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedAngles
        .take(3)
        .map((e) => e.key * math.pi / 180)
        .toList();
  }

  double _calculateOverallQualityScore(
    double sharpness,
    double brightness,
    double contrast,
    double skew,
  ) {
    // Weighted quality score
    const sharpnessWeight = 0.4;
    const brightnessWeight = 0.2;
    const contrastWeight = 0.3;
    const skewWeight = 0.1;
    
    final brightnessScore = 1.0 - (brightness - 0.5).abs() * 2; // Prefer mid-range brightness
    final contrastScore = contrast; // Higher contrast is better
    final sharpnessScore = math.min(1.0, sharpness * 2); // Scale sharpness
    final skewScore = 1.0 - skew; // Lower skew is better
    
    return sharpnessWeight * sharpnessScore +
           brightnessWeight * brightnessScore +
           contrastWeight * contrastScore +
           skewWeight * skewScore;
  }

  bool _isQualityAcceptable(
    double sharpness,
    double brightness,
    double contrast,
    double skew,
    DocumentType documentType,
  ) {
    // Different quality thresholds for different document types
    final thresholds = _getQualityThresholds(documentType);
    
    return sharpness >= thresholds.minSharpness &&
           brightness >= thresholds.minBrightness &&
           brightness <= thresholds.maxBrightness &&
           contrast >= thresholds.minContrast &&
           skew <= thresholds.maxSkew;
  }

  QualityThresholds _getQualityThresholds(DocumentType documentType) {
    switch (documentType) {
      case DocumentType.businessCard:
        return QualityThresholds(
          minSharpness: 0.3,
          minBrightness: 0.3,
          maxBrightness: 0.8,
          minContrast: 0.4,
          maxSkew: 0.1,
        );
      case DocumentType.idCard:
        return QualityThresholds(
          minSharpness: 0.4,
          minBrightness: 0.3,
          maxBrightness: 0.8,
          minContrast: 0.5,
          maxSkew: 0.05,
        );
      case DocumentType.receipt:
        return QualityThresholds(
          minSharpness: 0.25,
          minBrightness: 0.2,
          maxBrightness: 0.9,
          minContrast: 0.3,
          maxSkew: 0.15,
        );
      default:
        return QualityThresholds(
          minSharpness: 0.2,
          minBrightness: 0.2,
          maxBrightness: 0.9,
          minContrast: 0.3,
          maxSkew: 0.2,
        );
    }
  }

  /// Get optimization settings for document type
  OptimizationSettings _getOptimizationSettings(
    DocumentType documentType,
    DetailedAnalysis analysis,
  ) {
    switch (documentType) {
      case DocumentType.receipt:
        return OptimizationSettings(
          enhanceContrast: true,
          sharpenText: true,
          adjustBrightness: true,
          removeBackground: false,
          preserveColors: false,
          ocrOptimization: true,
          compressionLevel: 0.8,
        );
      case DocumentType.businessCard:
        return OptimizationSettings(
          enhanceContrast: true,
          sharpenText: true,
          adjustBrightness: false,
          removeBackground: false,
          preserveColors: true,
          ocrOptimization: true,
          compressionLevel: 0.9,
        );
      case DocumentType.idCard:
        return OptimizationSettings(
          enhanceContrast: false,
          sharpenText: true,
          adjustBrightness: false,
          removeBackground: false,
          preserveColors: true,
          ocrOptimization: true,
          compressionLevel: 0.95,
        );
      case DocumentType.photo:
        return OptimizationSettings(
          enhanceContrast: false,
          sharpenText: false,
          adjustBrightness: false,
          removeBackground: false,
          preserveColors: true,
          ocrOptimization: false,
          compressionLevel: 0.9,
        );
      default:
        return OptimizationSettings(
          enhanceContrast: true,
          sharpenText: true,
          adjustBrightness: true,
          removeBackground: true,
          preserveColors: false,
          ocrOptimization: true,
          compressionLevel: 0.85,
        );
    }
  }
}

// Data classes
class DocumentAnalysisResult {
  final DocumentType documentType;
  final double confidence;
  final String subType;
  final List<Rect> textRegions;
  final List<Rect> logoRegions;
  final QualityMetrics qualityMetrics;
  final OptimizationSettings optimizationSettings;
  final List<String> processingRecommendations;

  DocumentAnalysisResult({
    required this.documentType,
    required this.confidence,
    required this.subType,
    required this.textRegions,
    required this.logoRegions,
    required this.qualityMetrics,
    required this.optimizationSettings,
    required this.processingRecommendations,
  });

  factory DocumentAnalysisResult.unknown() {
    return DocumentAnalysisResult(
      documentType: DocumentType.unknown,
      confidence: 0.0,
      subType: 'unknown',
      textRegions: [],
      logoRegions: [],
      qualityMetrics: QualityMetrics.poor(),
      optimizationSettings: OptimizationSettings.defaultSettings(),
      processingRecommendations: ['Position document clearly in frame'],
    );
  }
}

class DocumentFeatures {
  final double textDensity;
  final LineStructure lineStructure;
  final LogoPresence logoPresence;
  final ColorProfile colorProfile;
  final LayoutStructure layoutStructure;

  DocumentFeatures({
    required this.textDensity,
    required this.lineStructure,
    required this.logoPresence,
    required this.colorProfile,
    required this.layoutStructure,
  });
}

class LineStructure {
  final int horizontalLineCount;
  final int verticalLineCount;
  final bool hasTableStructure;
  final double textLineSpacing;

  LineStructure({
    required this.horizontalLineCount,
    required this.verticalLineCount,
    required this.hasTableStructure,
    required this.textLineSpacing,
  });
}

class LogoPresence {
  final bool hasLogo;
  final int logoCount;
  final List<Rect> logoRegions;

  LogoPresence({
    required this.hasLogo,
    required this.logoCount,
    required this.logoRegions,
  });
}

class ColorProfile {
  final bool isDarkOnLight;
  final double contrast;
  final double colorComplexity;
  final double backgroundLuminance;

  ColorProfile({
    required this.isDarkOnLight,
    required this.contrast,
    required this.colorComplexity,
    required this.backgroundLuminance,
  });
}

class LayoutStructure {
  final bool hasHeader;
  final bool hasFooter;
  final bool isCentered;
  final List<double> contentDistribution;

  LayoutStructure({
    required this.hasHeader,
    required this.hasFooter,
    required this.isCentered,
    required this.contentDistribution,
  });
}

class ConnectedComponent {
  final List<Offset> points;

  ConnectedComponent({required this.points});
}

class DetailedAnalysis {
  final double confidence;
  final String subType;
  final List<Rect> textRegions;
  final List<Rect> logoRegions;
  final List<String> recommendations;

  DetailedAnalysis({
    required this.confidence,
    required this.subType,
    required this.textRegions,
    required this.logoRegions,
    required this.recommendations,
  });
}

class QualityMetrics {
  final double sharpness;
  final double brightness;
  final double contrast;
  final double skew;
  final double overallScore;
  final bool isAcceptable;

  QualityMetrics({
    required this.sharpness,
    required this.brightness,
    required this.contrast,
    required this.skew,
    required this.overallScore,
    required this.isAcceptable,
  });

  factory QualityMetrics.poor() {
    return QualityMetrics(
      sharpness: 0.0,
      brightness: 0.0,
      contrast: 0.0,
      skew: 1.0,
      overallScore: 0.0,
      isAcceptable: false,
    );
  }
}

class QualityThresholds {
  final double minSharpness;
  final double minBrightness;
  final double maxBrightness;
  final double minContrast;
  final double maxSkew;

  QualityThresholds({
    required this.minSharpness,
    required this.minBrightness,
    required this.maxBrightness,
    required this.minContrast,
    required this.maxSkew,
  });
}

class OptimizationSettings {
  final bool enhanceContrast;
  final bool sharpenText;
  final bool adjustBrightness;
  final bool removeBackground;
  final bool preserveColors;
  final bool ocrOptimization;
  final double compressionLevel;
  final bool autoRotate;
  final bool reduceNoise;
  final bool finalSharpen;
  final double backgroundThreshold;
  final double noiseReductionStrength;
  final double sharpenStrength;

  OptimizationSettings({
    required this.enhanceContrast,
    required this.sharpenText,
    required this.adjustBrightness,
    required this.removeBackground,
    required this.preserveColors,
    required this.ocrOptimization,
    required this.compressionLevel,
    this.autoRotate = true,
    this.reduceNoise = true,
    this.finalSharpen = true,
    this.backgroundThreshold = 0.12,
    this.noiseReductionStrength = 0.3,
    this.sharpenStrength = 0.7,
  });

  factory OptimizationSettings.defaultSettings() {
    return OptimizationSettings(
      enhanceContrast: true,
      sharpenText: true,
      adjustBrightness: true,
      removeBackground: true,
      preserveColors: false,
      ocrOptimization: true,
      compressionLevel: 0.85,
      autoRotate: true,
      reduceNoise: true,
      finalSharpen: true,
      backgroundThreshold: 0.12,
      noiseReductionStrength: 0.3,
      sharpenStrength: 0.7,
    );
  }
}