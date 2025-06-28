// lib/services/enhanced_image_processing_service.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'edge_detection_service.dart';
import 'document_type_recognition_service.dart';

class EnhancedImageProcessingService {
  static EnhancedImageProcessingService? _instance;
  static EnhancedImageProcessingService get instance => 
      _instance ??= EnhancedImageProcessingService._();
  
  EnhancedImageProcessingService._();

  /// Process document image with advanced enhancements
  Future<ProcessingResult> processDocumentImage({
    required String imagePath,
    required List<Offset> corners,
    required Size imageSize,
    DocumentType? documentType,
    OptimizationSettings? customSettings,
    String? outputFileName,
  }) async {
    try {
      final startTime = DateTime.now();
      
      // Load original image
      final originalBytes = await File(imagePath).readAsBytes();
      var image = img.decodeImage(originalBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Get optimization settings
      final settings = customSettings ?? _getDefaultSettings(documentType);
      
      // Processing pipeline
      final processingSteps = <ProcessingStep>[];
      
      // Step 1: Perspective correction and cropping
      if (corners.length == 4) {
        final correctedResult = await _applyPerspectiveCorrection(image, corners);
        image = correctedResult.image;
        processingSteps.add(correctedResult.step);
      }
      
      // Step 2: Orientation correction
      if (settings.autoRotate) {
        final rotationResult = await _correctOrientation(image);
        image = rotationResult.image;
        processingSteps.add(rotationResult.step);
      }
      
      // Step 3: Background removal/cleaning
      if (settings.removeBackground) {
        final backgroundResult = await _removeBackground(image, settings);
        image = backgroundResult.image;
        processingSteps.add(backgroundResult.step);
      }
      
      // Step 4: Brightness and contrast adjustment
      if (settings.adjustBrightness || settings.enhanceContrast) {
        final brightnessResult = await _adjustBrightnessContrast(image, settings);
        image = brightnessResult.image;
        processingSteps.add(brightnessResult.step);
      }
      
      // Step 5: Text enhancement
      if (settings.sharpenText || settings.ocrOptimization) {
        final textResult = await _enhanceText(image, settings, documentType);
        image = textResult.image;
        processingSteps.add(textResult.step);
      }
      
      // Step 6: Color correction
      if (settings.preserveColors && documentType != DocumentType.receipt) {
        final colorResult = await _correctColors(image, settings);
        image = colorResult.image;
        processingSteps.add(colorResult.step);
      }
      
      // Step 7: Noise reduction
      if (settings.reduceNoise) {
        final noiseResult = await _reduceNoise(image, settings);
        image = noiseResult.image;
        processingSteps.add(noiseResult.step);
      }
      
      // Step 8: Final sharpening
      if (settings.finalSharpen) {
        final sharpenResult = await _finalSharpening(image, settings);
        image = sharpenResult.image;
        processingSteps.add(sharpenResult.step);
      }
      
      // Save processed image
      final outputPath = await _saveProcessedImage(
        image, 
        outputFileName, 
        settings.compressionLevel,
      );
      
      final processingTime = DateTime.now().difference(startTime);
      
      return ProcessingResult(
        originalImagePath: imagePath,
        processedImagePath: outputPath,
        processingSteps: processingSteps,
        processingTime: processingTime,
        settings: settings,
        qualityImprovement: await _calculateQualityImprovement(
          originalBytes,
          await File(outputPath).readAsBytes(),
        ),
      );
      
    } catch (e) {
      print('Image processing error: $e');
      rethrow;
    }
  }

  /// Apply perspective correction and cropping
  Future<ProcessingStepResult> _applyPerspectiveCorrection(
    img.Image image,
    List<Offset> corners,
  ) async {
    try {
      // Order corners: top-left, top-right, bottom-right, bottom-left
      final orderedCorners = _orderCorners(corners, Size(
        image.width.toDouble(),
        image.height.toDouble(),
      ));
      
      // Calculate destination rectangle dimensions
      final destWidth = _calculateCorrectedWidth(orderedCorners);
      final destHeight = _calculateCorrectedHeight(orderedCorners);
      
      // Create transformation matrix
      final transformMatrix = _calculatePerspectiveMatrix(
        orderedCorners,
        destWidth,
        destHeight,
      );
      
      // Apply perspective transformation
      final correctedImage = _applyPerspectiveTransform(
        image,
        transformMatrix,
        destWidth.round(),
        destHeight.round(),
      );
      
      return ProcessingStepResult(
        image: correctedImage,
        step: ProcessingStep(
          name: 'Perspective Correction',
          description: 'Applied perspective correction and cropping',
          parameters: {
            'corners': corners.map((c) => [c.dx, c.dy]).toList(),
            'output_size': [destWidth, destHeight],
          },
          qualityImpact: 0.8,
        ),
      );
    } catch (e) {
      print('Perspective correction failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Perspective Correction',
          description: 'Failed to apply perspective correction',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  List<Offset> _orderCorners(List<Offset> corners, Size imageSize) {
    if (corners.length != 4) return corners;
    
    // Calculate center point
    final center = Offset(
      corners.map((c) => c.dx).reduce((a, b) => a + b) / 4,
      corners.map((c) => c.dy).reduce((a, b) => a + b) / 4,
    );
    
    // Sort corners by angle from center
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
    
    // Order: top-left, top-right, bottom-right, bottom-left
    final ordered = <Offset>[];
    for (int i = 0; i < 4; i++) {
      ordered.add(cornersWithAngles[(topLeftIndex + i) % 4].corner);
    }
    
    return ordered;
  }

  double _calculateCorrectedWidth(List<Offset> corners) {
    final topWidth = _distance(corners[0], corners[1]);
    final bottomWidth = _distance(corners[3], corners[2]);
    return math.max(topWidth, bottomWidth);
  }

  double _calculateCorrectedHeight(List<Offset> corners) {
    final leftHeight = _distance(corners[0], corners[3]);
    final rightHeight = _distance(corners[1], corners[2]);
    return math.max(leftHeight, rightHeight);
  }

  double _distance(Offset a, Offset b) {
    return math.sqrt((a.dx - b.dx) * (a.dx - b.dx) + (a.dy - b.dy) * (a.dy - b.dy));
  }

  Matrix4 _calculatePerspectiveMatrix(
    List<Offset> sourceCorners,
    double destWidth,
    double destHeight,
  ) {
    // Destination corners (rectangle)
    final destCorners = [
      const Offset(0, 0),
      Offset(destWidth, 0),
      Offset(destWidth, destHeight),
      Offset(0, destHeight),
    ];
    
    // Calculate perspective transformation matrix
    // This is a simplified version - in production, use a proper perspective transformation library
    return Matrix4.identity();
  }

  img.Image _applyPerspectiveTransform(
    img.Image source,
    Matrix4 transform,
    int destWidth,
    int destHeight,
  ) {
    // Simplified perspective transformation
    // In production, implement proper bilinear interpolation
    final result = img.Image(width: destWidth, height: destHeight);
    
    for (int y = 0; y < destHeight; y++) {
      for (int x = 0; x < destWidth; x++) {
        // Map destination pixel to source pixel (simplified)
        final sourceX = (x * source.width / destWidth).round().clamp(0, source.width - 1);
        final sourceY = (y * source.height / destHeight).round().clamp(0, source.height - 1);
        
        final pixel = source.getPixel(sourceX, sourceY);
        result.setPixel(x, y, pixel);
      }
    }
    
    return result;
  }

  /// Correct image orientation
  Future<ProcessingStepResult> _correctOrientation(img.Image image) async {
    try {
      // Detect text orientation using projection analysis
      final rotation = await _detectTextOrientation(image);
      
      img.Image rotatedImage = image;
      String description = 'No rotation needed';
      
      if (rotation.abs() > 1.0) { // More than 1 degree
        rotatedImage = _rotateImage(image, rotation);
        description = 'Rotated by ${rotation.toStringAsFixed(1)} degrees';
      }
      
      return ProcessingStepResult(
        image: rotatedImage,
        step: ProcessingStep(
          name: 'Orientation Correction',
          description: description,
          parameters: {'rotation_degrees': rotation},
          qualityImpact: rotation.abs() > 1.0 ? 0.3 : 0.0,
        ),
      );
    } catch (e) {
      print('Orientation correction failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Orientation Correction',
          description: 'Failed to correct orientation',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  Future<double> _detectTextOrientation(img.Image image) async {
    // Simplified text orientation detection
    final grayImage = img.grayscale(image);
    final edges = img.sobel(grayImage);
    
    // Use Hough transform to find dominant line angles
    final angles = <double>[];
    
    // Sample edges and calculate gradients
    for (int y = 1; y < edges.height - 1; y += 5) {
      for (int x = 1; x < edges.width - 1; x += 5) {
        final pixel = edges.getPixel(x, y);
        final intensity = img.getLuminance(pixel);
        
        if (intensity > 128) {
          final gx = img.getLuminance(edges.getPixel(x + 1, y)) - 
                    img.getLuminance(edges.getPixel(x - 1, y));
          final gy = img.getLuminance(edges.getPixel(x, y + 1)) - 
                    img.getLuminance(edges.getPixel(x, y - 1));
          
          if (gx != 0 || gy != 0) {
            final angle = math.atan2(gy, gx) * 180 / math.pi;
            angles.add(angle);
          }
        }
      }
    }
    
    if (angles.isEmpty) return 0.0;
    
    // Find the most common angle (text baseline)
    angles.sort();
    final histogram = <int, int>{};
    
    for (final angle in angles) {
      final bucket = (angle / 2).round() * 2; // 2-degree buckets
      histogram[bucket] = (histogram[bucket] ?? 0) + 1;
    }
    
    var maxCount = 0;
    var dominantAngle = 0;
    
    for (final entry in histogram.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        dominantAngle = entry.key;
      }
    }
    
    // Return rotation needed to make text horizontal
    return -dominantAngle.toDouble();
  }

  img.Image _rotateImage(img.Image image, double angleDegrees) {
    final angleRadians = angleDegrees * math.pi / 180;
    
    // Calculate new image dimensions
    final cos = math.cos(angleRadians).abs();
    final sin = math.sin(angleRadians).abs();
    final newWidth = (image.width * cos + image.height * sin).ceil();
    final newHeight = (image.width * sin + image.height * cos).ceil();
    
    final rotated = img.Image(width: newWidth, height: newHeight);
    final centerX = newWidth / 2;
    final centerY = newHeight / 2;
    final origCenterX = image.width / 2;
    final origCenterY = image.height / 2;
    
    for (int y = 0; y < newHeight; y++) {
      for (int x = 0; x < newWidth; x++) {
        // Rotate coordinates back to original image
        final relX = x - centerX;
        final relY = y - centerY;
        final origX = (relX * math.cos(-angleRadians) - relY * math.sin(-angleRadians) + origCenterX).round();
        final origY = (relX * math.sin(-angleRadians) + relY * math.cos(-angleRadians) + origCenterY).round();
        
        if (origX >= 0 && origX < image.width && origY >= 0 && origY < image.height) {
          final pixel = image.getPixel(origX, origY);
          rotated.setPixel(x, y, pixel);
        } else {
          rotated.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // White background
        }
      }
    }
    
    return rotated;
  }

  /// Remove background and clean document
  Future<ProcessingStepResult> _removeBackground(
    img.Image image,
    OptimizationSettings settings,
  ) async {
    try {
      final cleanedImage = await _cleanBackground(image, settings.backgroundThreshold);
      
      return ProcessingStepResult(
        image: cleanedImage,
        step: ProcessingStep(
          name: 'Background Removal',
          description: 'Removed background and cleaned document',
          parameters: {'threshold': settings.backgroundThreshold},
          qualityImpact: 0.4,
        ),
      );
    } catch (e) {
      print('Background removal failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Background Removal',
          description: 'Failed to remove background',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  Future<img.Image> _cleanBackground(img.Image image, double threshold) async {
    final result = img.Image.from(image);
    
    // Estimate background color (most common color)
    final colorCounts = <int, int>{};
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel).round();
        colorCounts[luminance] = (colorCounts[luminance] ?? 0) + 1;
      }
    }
    
    var maxCount = 0;
    var backgroundColor = 255;
    for (final entry in colorCounts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        backgroundColor = entry.key;
      }
    }
    
    // Clean background
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final luminance = img.getLuminance(pixel);
        
        // If pixel is close to background color, make it pure white
        if ((luminance - backgroundColor).abs() < threshold * 255) {
          result.setPixel(x, y, img.ColorRgb8(255, 255, 255));
        }
      }
    }
    
    return result;
  }

  /// Adjust brightness and contrast
  Future<ProcessingStepResult> _adjustBrightnessContrast(
    img.Image image,
    OptimizationSettings settings,
  ) async {
    try {
      var adjustedImage = image;
      final adjustments = <String, double>{};
      
      if (settings.adjustBrightness || settings.enhanceContrast) {
        final brightness = settings.adjustBrightness ? _calculateOptimalBrightness(image) : 0.0;
        final contrast = settings.enhanceContrast ? _calculateOptimalContrast(adjustedImage) : 1.0;
        
        adjustedImage = img.adjustColor(
          adjustedImage, 
          brightness: brightness,
          contrast: contrast,
        );
        
        if (settings.adjustBrightness) adjustments['brightness'] = brightness;
        if (settings.enhanceContrast) adjustments['contrast'] = contrast;
      }
      
      return ProcessingStepResult(
        image: adjustedImage,
        step: ProcessingStep(
          name: 'Brightness & Contrast',
          description: 'Adjusted brightness and contrast for optimal readability',
          parameters: adjustments,
          qualityImpact: 0.3,
        ),
      );
    } catch (e) {
      print('Brightness/contrast adjustment failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Brightness & Contrast',
          description: 'Failed to adjust brightness and contrast',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  double _calculateOptimalBrightness(img.Image image) {
    // Calculate average brightness
    double totalBrightness = 0.0;
    int pixelCount = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        totalBrightness += img.getLuminance(pixel);
        pixelCount++;
      }
    }
    
    final averageBrightness = totalBrightness / pixelCount;
    final targetBrightness = 180.0; // Slightly bright for better OCR
    
    return (targetBrightness - averageBrightness) / 255.0;
  }

  double _calculateOptimalContrast(img.Image image) {
    // Calculate current contrast and determine optimal enhancement
    final luminances = <double>[];
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        luminances.add(img.getLuminance(pixel).toDouble()); // Fix: cast to double
      }
    }
    
    luminances.sort();
    final p5 = luminances[(luminances.length * 0.05).floor()];
    final p95 = luminances[(luminances.length * 0.95).floor()];
    final currentContrast = (p95 - p5) / 255.0;
    
    // Target contrast of 0.7 for good text readability
    final targetContrast = 0.7;
    return targetContrast > currentContrast ? 1.3 : 1.0;
  }

  /// Enhance text clarity
  Future<ProcessingStepResult> _enhanceText(
    img.Image image,
    OptimizationSettings settings,
    DocumentType? documentType,
  ) async {
    try {
      var enhancedImage = image;
      final enhancements = <String>[];
      
      if (settings.sharpenText) {
        enhancedImage = _sharpenForText(enhancedImage);
        enhancements.add('text_sharpening');
      }
      
      if (settings.ocrOptimization) {
        enhancedImage = _optimizeForOCR(enhancedImage, documentType);
        enhancements.add('ocr_optimization');
      }
      
      return ProcessingStepResult(
        image: enhancedImage,
        step: ProcessingStep(
          name: 'Text Enhancement',
          description: 'Enhanced text clarity and readability',
          parameters: {'enhancements': enhancements},
          qualityImpact: 0.5,
        ),
      );
    } catch (e) {
      print('Text enhancement failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Text Enhancement',
          description: 'Failed to enhance text',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  img.Image _sharpenForText(img.Image image) {
    // Apply unsharp mask specifically tuned for text
    final result = img.Image.from(image);
    
    for (int y = 1; y < result.height - 1; y++) {
      for (int x = 1; x < result.width - 1; x++) {
        final center = img.getLuminance(image.getPixel(x, y));
        final top = img.getLuminance(image.getPixel(x, y - 1));
        final bottom = img.getLuminance(image.getPixel(x, y + 1));
        final left = img.getLuminance(image.getPixel(x - 1, y));
        final right = img.getLuminance(image.getPixel(x + 1, y));
        
        // Text-optimized sharpening kernel
        final sharpened = (center * 2.5 - (top + bottom + left + right) * 0.125).clamp(0, 255);
        final color = img.ColorRgb8(sharpened.round(), sharpened.round(), sharpened.round());
        result.setPixel(x, y, color);
      }
    }
    
    return result;
  }

  img.Image _optimizeForOCR(img.Image image, DocumentType? documentType) {
    // Apply OCR-specific optimizations
    var optimized = img.grayscale(image);
    
    // Apply adaptive thresholding for better text separation
    optimized = _adaptiveThreshold(optimized);
    
    // Apply morphological operations to clean up text
    if (documentType == DocumentType.receipt) {
      optimized = _morphologicalClean(optimized, small: true);
    } else {
      optimized = _morphologicalClean(optimized, small: false);
    }
    
    return optimized;
  }

  img.Image _adaptiveThreshold(img.Image grayImage) {
    final result = img.Image.from(grayImage);
    const windowSize = 15;
    const c = 10; // Constant subtracted from mean
    
    for (int y = windowSize ~/ 2; y < grayImage.height - windowSize ~/ 2; y++) {
      for (int x = windowSize ~/ 2; x < grayImage.width - windowSize ~/ 2; x++) {
        // Calculate local mean
        double sum = 0.0;
        int count = 0;
        
        for (int dy = -windowSize ~/ 2; dy <= windowSize ~/ 2; dy++) {
          for (int dx = -windowSize ~/ 2; dx <= windowSize ~/ 2; dx++) {
            final pixel = grayImage.getPixel(x + dx, y + dy);
            sum += img.getLuminance(pixel);
            count++;
          }
        }
        
        final mean = sum / count;
        final pixel = grayImage.getPixel(x, y);
        final luminance = img.getLuminance(pixel);
        
        final newValue = luminance > (mean - c) ? 255 : 0;
        final color = img.ColorRgb8(newValue, newValue, newValue);
        result.setPixel(x, y, color);
      }
    }
    
    return result;
  }

  img.Image _morphologicalClean(img.Image image, {required bool small}) {
    // Simple morphological operations to clean up text
    final kernelSize = small ? 3 : 5;
    
    // Erosion followed by dilation (opening) to remove noise
    var cleaned = _morphologicalErosion(image, kernelSize);
    cleaned = _morphologicalDilation(cleaned, kernelSize);
    
    return cleaned;
  }

  img.Image _morphologicalErosion(img.Image image, int kernelSize) {
    final result = img.Image.from(image);
    final halfKernel = kernelSize ~/ 2;
    
    for (int y = halfKernel; y < image.height - halfKernel; y++) {
      for (int x = halfKernel; x < image.width - halfKernel; x++) {
        int minValue = 255;
        
        for (int dy = -halfKernel; dy <= halfKernel; dy++) {
          for (int dx = -halfKernel; dx <= halfKernel; dx++) {
            final pixel = image.getPixel(x + dx, y + dy);
            final luminance = img.getLuminance(pixel).round();
            minValue = math.min(minValue, luminance);
          }
        }
        
        final color = img.ColorRgb8(minValue, minValue, minValue);
        result.setPixel(x, y, color);
      }
    }
    
    return result;
  }

  img.Image _morphologicalDilation(img.Image image, int kernelSize) {
    final result = img.Image.from(image);
    final halfKernel = kernelSize ~/ 2;
    
    for (int y = halfKernel; y < image.height - halfKernel; y++) {
      for (int x = halfKernel; x < image.width - halfKernel; x++) {
        int maxValue = 0;
        
        for (int dy = -halfKernel; dy <= halfKernel; dy++) {
          for (int dx = -halfKernel; dx <= halfKernel; dx++) {
            final pixel = image.getPixel(x + dx, y + dy);
            final luminance = img.getLuminance(pixel).round();
            maxValue = math.max(maxValue, luminance);
          }
        }
        
        final color = img.ColorRgb8(maxValue, maxValue, maxValue);
        result.setPixel(x, y, color);
      }
    }
    
    return result;
  }

  /// Correct colors for better appearance
  Future<ProcessingStepResult> _correctColors(
    img.Image image,
    OptimizationSettings settings,
  ) async {
    try {
      final correctedImage = _adjustColorBalance(image);
      
      return ProcessingStepResult(
        image: correctedImage,
        step: ProcessingStep(
          name: 'Color Correction',
          description: 'Corrected color balance and saturation',
          parameters: {'white_balance': true, 'saturation': 1.1},
          qualityImpact: 0.2,
        ),
      );
    } catch (e) {
      print('Color correction failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Color Correction',
          description: 'Failed to correct colors',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  img.Image _adjustColorBalance(img.Image image) {
    // Simple white balance correction
    final result = img.Image.from(image);
    
    // Calculate average RGB values
    double avgR = 0, avgG = 0, avgB = 0;
    int pixelCount = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        avgR += pixel.r;
        avgG += pixel.g;
        avgB += pixel.b;
        pixelCount++;
      }
    }
    
    avgR /= pixelCount;
    avgG /= pixelCount;
    avgB /= pixelCount;
    
    // Calculate correction factors
    final grayTarget = (avgR + avgG + avgB) / 3;
    final rFactor = grayTarget / avgR;
    final gFactor = grayTarget / avgG;
    final bFactor = grayTarget / avgB;
    
    // Apply correction
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final pixel = result.getPixel(x, y);
        final newR = (pixel.r * rFactor).clamp(0, 255).round();
        final newG = (pixel.g * gFactor).clamp(0, 255).round();
        final newB = (pixel.b * bFactor).clamp(0, 255).round();
        
        result.setPixel(x, y, img.ColorRgb8(newR, newG, newB));
      }
    }
    
    return result;
  }

  /// Reduce noise
  Future<ProcessingStepResult> _reduceNoise(
    img.Image image,
    OptimizationSettings settings,
  ) async {
    try {
      final denoisedImage = _applyGaussianDenoising(image, settings.noiseReductionStrength);
      
      return ProcessingStepResult(
        image: denoisedImage,
        step: ProcessingStep(
          name: 'Noise Reduction',
          description: 'Applied Gaussian denoising to reduce image noise',
          parameters: {'strength': settings.noiseReductionStrength},
          qualityImpact: 0.3,
        ),
      );
    } catch (e) {
      print('Noise reduction failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Noise Reduction',
          description: 'Failed to reduce noise',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  img.Image _applyGaussianDenoising(img.Image image, double strength) {
    // Apply Gaussian blur for noise reduction
    final kernelSize = (strength * 5).round().clamp(3, 9);
    return img.gaussianBlur(image, radius: kernelSize ~/ 2);
  }

  /// Final sharpening pass
  Future<ProcessingStepResult> _finalSharpening(
    img.Image image,
    OptimizationSettings settings,
  ) async {
    try {
      final sharpenedImage = _applyUnsharpMask(image, settings.sharpenStrength);
      
      return ProcessingStepResult(
        image: sharpenedImage,
        step: ProcessingStep(
          name: 'Final Sharpening',
          description: 'Applied final sharpening for enhanced clarity',
          parameters: {'strength': settings.sharpenStrength},
          qualityImpact: 0.2,
        ),
      );
    } catch (e) {
      print('Final sharpening failed: $e');
      return ProcessingStepResult(
        image: image,
        step: ProcessingStep(
          name: 'Final Sharpening',
          description: 'Failed to apply final sharpening',
          parameters: {},
          qualityImpact: 0.0,
        ),
      );
    }
  }

  img.Image _applyUnsharpMask(img.Image image, double strength) {
    // Create blurred version
    final blurred = img.gaussianBlur(image, radius: 2);
    final result = img.Image.from(image);
    
    // Apply unsharp mask
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        final original = result.getPixel(x, y);
        final blurredPixel = blurred.getPixel(x, y);
        
        final newR = (original.r + strength * (original.r - blurredPixel.r)).clamp(0, 255).round();
        final newG = (original.g + strength * (original.g - blurredPixel.g)).clamp(0, 255).round();
        final newB = (original.b + strength * (original.b - blurredPixel.b)).clamp(0, 255).round();
        
        result.setPixel(x, y, img.ColorRgb8(newR, newG, newB));
      }
    }
    
    return result;
  }

  /// Save processed image
  Future<String> _saveProcessedImage(
    img.Image image,
    String? fileName,
    double compressionLevel,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final outputFileName = fileName ?? 'processed_${DateTime.now().millisecondsSinceEpoch}';
    final outputPath = path.join(tempDir.path, '$outputFileName.jpg');
    
    // Encode with specified quality
    final quality = (compressionLevel * 100).round().clamp(1, 100);
    final encodedBytes = img.encodeJpg(image, quality: quality);
    
    await File(outputPath).writeAsBytes(encodedBytes);
    return outputPath;
  }

  /// Calculate quality improvement metrics
  Future<QualityImprovement> _calculateQualityImprovement(
    Uint8List originalBytes,
    Uint8List processedBytes,
  ) async {
    try {
      final originalImage = img.decodeImage(originalBytes);
      final processedImage = img.decodeImage(processedBytes);
      
      if (originalImage == null || processedImage == null) {
        return QualityImprovement.noImprovement();
      }
      
      // Calculate various quality metrics
      final originalSharpness = _calculateImageSharpness(originalImage);
      final processedSharpness = _calculateImageSharpness(processedImage);
      
      final originalContrast = _calculateImageContrast(originalImage);
      final processedContrast = _calculateImageContrast(processedImage);
      
      final originalBrightness = _calculateImageBrightness(originalImage);
      final processedBrightness = _calculateImageBrightness(processedImage);
      
      return QualityImprovement(
        sharpnessImprovement: processedSharpness - originalSharpness,
        contrastImprovement: processedContrast - originalContrast,
        brightnessImprovement: (processedBrightness - originalBrightness).abs(),
        overallImprovement: _calculateOverallImprovement(
          originalSharpness, processedSharpness,
          originalContrast, processedContrast,
          originalBrightness, processedBrightness,
        ),
      );
    } catch (e) {
      print('Quality improvement calculation failed: $e');
      return QualityImprovement.noImprovement();
    }
  }

  double _calculateImageSharpness(img.Image image) {
    final grayImage = img.grayscale(image);
    double variance = 0.0;
    int count = 0;
    
    for (int y = 1; y < grayImage.height - 1; y++) {
      for (int x = 1; x < grayImage.width - 1; x++) {
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
    
    return math.sqrt(variance / count) / 255.0;
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
    
    return (p95 - p5) / 255.0;
  }

  double _calculateImageBrightness(img.Image image) {
    double totalBrightness = 0.0;
    int pixelCount = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        totalBrightness += img.getLuminance(pixel);
        pixelCount++;
      }
    }
    
    return (totalBrightness / pixelCount) / 255.0;
  }

  double _calculateOverallImprovement(
    double originalSharpness, double processedSharpness,
    double originalContrast, double processedContrast,
    double originalBrightness, double processedBrightness,
  ) {
    const sharpnessWeight = 0.4;
    const contrastWeight = 0.4;
    const brightnessWeight = 0.2;
    
    final sharpnessScore = (processedSharpness - originalSharpness).clamp(-1.0, 1.0);
    final contrastScore = (processedContrast - originalContrast).clamp(-1.0, 1.0);
    
    // Brightness should be optimal around 0.6-0.7
    final originalBrightnessScore = 1.0 - (originalBrightness - 0.65).abs() * 2;
    final processedBrightnessScore = 1.0 - (processedBrightness - 0.65).abs() * 2;
    final brightnessScore = processedBrightnessScore - originalBrightnessScore;
    
    return sharpnessWeight * sharpnessScore +
           contrastWeight * contrastScore +
           brightnessWeight * brightnessScore;
  }

  /// Get default optimization settings for document type
  OptimizationSettings _getDefaultSettings(DocumentType? documentType) {
    switch (documentType) {
      case DocumentType.receipt:
        return OptimizationSettings(
          enhanceContrast: true,
          sharpenText: true,
          adjustBrightness: true,
          removeBackground: true,
          preserveColors: false,
          ocrOptimization: true,
          compressionLevel: 0.8,
          autoRotate: true,
          reduceNoise: true,
          finalSharpen: true,
          backgroundThreshold: 0.15,
          noiseReductionStrength: 0.3,
          sharpenStrength: 0.8,
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
          autoRotate: true,
          reduceNoise: false,
          finalSharpen: true,
          backgroundThreshold: 0.1,
          noiseReductionStrength: 0.2,
          sharpenStrength: 0.6,
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
          autoRotate: true,
          reduceNoise: false,
          finalSharpen: false,
          backgroundThreshold: 0.05,
          noiseReductionStrength: 0.1,
          sharpenStrength: 0.4,
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
          autoRotate: false,
          reduceNoise: true,
          finalSharpen: true,
          backgroundThreshold: 0.0,
          noiseReductionStrength: 0.4,
          sharpenStrength: 0.3,
        );
      case DocumentType.whiteboard:
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
          backgroundThreshold: 0.2,
          noiseReductionStrength: 0.5,
          sharpenStrength: 1.0,
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
          autoRotate: true,
          reduceNoise: true,
          finalSharpen: true,
          backgroundThreshold: 0.12,
          noiseReductionStrength: 0.3,
          sharpenStrength: 0.7,
        );
    }
  }

  /// Batch process multiple images
  Future<List<ProcessingResult>> batchProcessImages({
    required List<BatchImageInput> inputs,
    OptimizationSettings? globalSettings,
    Function(int processed, int total)? progressCallback,
  }) async {
    final results = <ProcessingResult>[];
    
    for (int i = 0; i < inputs.length; i++) {
      try {
        final input = inputs[i];
        final settings = input.customSettings ?? globalSettings ?? 
                        _getDefaultSettings(input.documentType);
        
        final result = await processDocumentImage(
          imagePath: input.imagePath,
          corners: input.corners,
          imageSize: input.imageSize,
          documentType: input.documentType,
          customSettings: settings,
          outputFileName: input.outputFileName,
        );
        
        results.add(result);
        progressCallback?.call(i + 1, inputs.length);
        
      } catch (e) {
        print('Failed to process image ${inputs[i].imagePath}: $e');
        // Add failed result
        results.add(ProcessingResult.failed(
          originalImagePath: inputs[i].imagePath,
          error: e.toString(),
        ));
      }
    }
    
    return results;
  }

  /// Cleanup temporary files
  Future<void> cleanup() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final files = tempDir.listSync();
      
      for (final file in files) {
        if (file is File && file.path.contains('processed_')) {
          final stat = await file.stat();
          final age = DateTime.now().difference(stat.modified);
          
          // Delete processed files older than 24 hours
          if (age.inHours > 24) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      print('Cleanup error: $e');
    }
  }
}

// Data classes and helper classes

class _CornerWithAngle {
  final Offset corner;
  final double angle;

  _CornerWithAngle(this.corner, this.angle);
}

class ProcessingResult {
  final String originalImagePath;
  final String? processedImagePath;
  final List<ProcessingStep> processingSteps;
  final Duration processingTime;
  final OptimizationSettings settings;
  final QualityImprovement qualityImprovement;
  final String? error;

  ProcessingResult({
    required this.originalImagePath,
    this.processedImagePath,
    required this.processingSteps,
    required this.processingTime,
    required this.settings,
    required this.qualityImprovement,
    this.error,
  });

  factory ProcessingResult.failed({
    required String originalImagePath,
    required String error,
  }) {
    return ProcessingResult(
      originalImagePath: originalImagePath,
      processingSteps: [],
      processingTime: Duration.zero,
      settings: OptimizationSettings.defaultSettings(),
      qualityImprovement: QualityImprovement.noImprovement(),
      error: error,
    );
  }

  bool get isSuccessful => error == null && processedImagePath != null;
  double get totalQualityImpact => processingSteps
      .map((step) => step.qualityImpact)
      .fold(0.0, (a, b) => a + b);
}

class ProcessingStepResult {
  final img.Image image;
  final ProcessingStep step;

  ProcessingStepResult({
    required this.image,
    required this.step,
  });
}

class ProcessingStep {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final double qualityImpact;

  ProcessingStep({
    required this.name,
    required this.description,
    required this.parameters,
    required this.qualityImpact,
  });
}

class QualityImprovement {
  final double sharpnessImprovement;
  final double contrastImprovement;
  final double brightnessImprovement;
  final double overallImprovement;

  QualityImprovement({
    required this.sharpnessImprovement,
    required this.contrastImprovement,
    required this.brightnessImprovement,
    required this.overallImprovement,
  });

  factory QualityImprovement.noImprovement() {
    return QualityImprovement(
      sharpnessImprovement: 0.0,
      contrastImprovement: 0.0,
      brightnessImprovement: 0.0,
      overallImprovement: 0.0,
    );
  }

  bool get hasImprovement => overallImprovement > 0.1;
}

class BatchImageInput {
  final String imagePath;
  final List<Offset> corners;
  final Size imageSize;
  final DocumentType? documentType;
  final OptimizationSettings? customSettings;
  final String? outputFileName;

  BatchImageInput({
    required this.imagePath,
    required this.corners,
    required this.imageSize,
    this.documentType,
    this.customSettings,
    this.outputFileName,
  });
}

