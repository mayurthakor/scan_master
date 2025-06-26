// lib/screens/realtime_camera_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';
import '../services/edge_detection_service.dart';

/// Real-time camera screen with live edge detection
/// Phase 4.1 Implementation: Real-time Detection Foundation
class RealtimeCameraScreen extends StatefulWidget {
  final Function(String imagePath) onImageCaptured;
  final bool enableAutoCapture;
  final DocumentType? preferredDocumentType;

  const RealtimeCameraScreen({
    super.key,
    required this.onImageCaptured,
    this.enableAutoCapture = true,
    this.preferredDocumentType,
  });

  @override
  State<RealtimeCameraScreen> createState() => _RealtimeCameraScreenState();
}

class _RealtimeCameraScreenState extends State<RealtimeCameraScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  
  final CameraService _cameraService = CameraService.instance;
  
  // State management
  bool _isLoading = true;
  bool _isCapturing = false;
  bool _isRealTimeDetectionActive = false;
  String? _error;
  
  // Detection state
  EdgeDetectionResult? _currentDetection;
  String _statusMessage = "Position document in frame";
  
  // Animation controllers for smooth UI transitions
  late AnimationController _cornerAnimationController;
  late AnimationController _statusAnimationController;
  late Animation<double> _cornerPulseAnimation;
  late Animation<double> _statusFadeAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize animations
    _cornerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    
    _statusAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _cornerPulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _cornerAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _statusFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _statusAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _initializeCamera();
  }

  @override
  void dispose() {
    _cornerAnimationController.dispose();
    _statusAnimationController.dispose();
    _stopRealTimeDetection();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopRealTimeDetection();
      _cameraService.disposeController();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      await _cameraService.initializeController(
        resolution: ResolutionPreset.high,
      );
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // Start real-time detection
        if (widget.enableAutoCapture) {
          await _startRealTimeDetection();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _startRealTimeDetection() async {
    if (_isRealTimeDetectionActive) return;
    
    try {
      final settings = AutoCaptureSettings(
        enableAutoCapture: widget.enableAutoCapture,
        minConfidenceThreshold: 0.75,
        stabilityDuration: const Duration(milliseconds: 2000),
        preferredDocumentType: widget.preferredDocumentType,
      );

      await _cameraService.startRealTimeDetection(
        onDetectionUpdate: _onDetectionUpdate,
        onAutoCapture: _onAutoCapture,
        settings: settings,
      );
      
      setState(() {
        _isRealTimeDetectionActive = true;
      });
      
      debugPrint('Real-time detection started successfully');
      
    } catch (e) {
      debugPrint('Failed to start real-time detection: $e');
      _showError('Failed to start camera detection: $e');
    }
  }

  Future<void> _stopRealTimeDetection() async {
    if (!_isRealTimeDetectionActive) return;
    
    try {
      await _cameraService.stopRealTimeDetection();
      setState(() {
        _isRealTimeDetectionActive = false;
        _currentDetection = null;
      });
    } catch (e) {
      debugPrint('Error stopping real-time detection: $e');
    }
  }

  void _onDetectionUpdate(EdgeDetectionResult result) {
    if (!mounted) return;
    
    setState(() {
      _currentDetection = result;
      _statusMessage = _generateStatusMessage(result);
    });
    
    // Trigger status animation
    _statusAnimationController.forward().then((_) {
      if (mounted) {
        _statusAnimationController.reverse();
      }
    });
  }

  String _generateStatusMessage(EdgeDetectionResult result) {
    final phase = _cameraService.currentPhase;
    
    switch (phase) {
      case AutoCapturePhase.countingDown:
        final countdown = _cameraService.countdownSeconds.ceil();
        return "Capturing in $countdown...";
        
      case AutoCapturePhase.capturing:
        return "Capturing...";
        
      case AutoCapturePhase.completed:
        return "Captured!";
        
      default:
        if (result.corners.isEmpty) {
          return "Position document in frame";
        }
        
        if (result.confidence < 0.4) {
          return "Move closer to document";
        }
        
        if (result.confidence < 0.6) {
          return "Improve lighting or focus";
        }
        
        final status = _cameraService.autoCaptureStatus;
        switch (status) {
          case AutoCaptureStatus.stabilizing:
            return "Hold steady...";
          case AutoCaptureStatus.ready:
            return "Perfect! Hold position";
          default:
            return "Position document clearly";
        }
    }
  }

  void _onAutoCapture() {
    _captureImage();
  }

  Future<void> _captureImage() async {
    if (_isCapturing) return;
    
    setState(() {
      _isCapturing = true;
    });
    
    try {
      // Haptic feedback
      HapticFeedback.mediumImpact();
      
      final imagePath = await _cameraService.captureImage();
      if (imagePath != null) {
        widget.onImageCaptured(imagePath);
      } else {
        _showError('Failed to capture image');
      }
      
    } catch (e) {
      _showError('Capture failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          _buildCameraPreview(),
          
          // Detection overlay
          if (_currentDetection != null)
            _buildDetectionOverlay(),
          
          // UI Controls
          _buildTopControls(),
          _buildBottomControls(),
          
          // Loading overlay
          if (_isLoading)
            _buildLoadingOverlay(),
          
          // Error overlay
          if (_error != null)
            _buildErrorOverlay(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraService.controller;
    
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: controller.value.previewSize?.height ?? 0,
          height: controller.value.previewSize?.width ?? 0,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildDetectionOverlay() {
    return CustomPaint(
      size: Size.infinite,
      painter: RealtimeDetectionPainter(
        detection: _currentDetection!,
        phase: _cameraService.currentPhase,
        countdownSeconds: _cameraService.countdownSeconds,
        cornerAnimation: _cornerPulseAnimation,
      ),
    );
  }

  Widget _buildTopControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Top row controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildControlButton(
                  icon: Icons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                _buildControlButton(
                  icon: _getFlashIcon(),
                  onPressed: _cameraService.toggleFlashMode,
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Status message
            AnimatedBuilder(
              animation: _statusFadeAnimation,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, 
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.8),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Detection toggle
              _buildControlButton(
                icon: _isRealTimeDetectionActive 
                    ? Icons.auto_awesome 
                    : Icons.auto_awesome_outlined,
                onPressed: _toggleRealTimeDetection,
                isActive: _isRealTimeDetectionActive,
              ),
              
              // Capture button
              _buildCaptureButton(),
              
              // Manual focus (tap to focus anywhere)
              _buildControlButton(
                icon: Icons.center_focus_strong,
                onPressed: () {
                  // Enable tap-to-focus mode
                  _showTapToFocusHint();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _isCapturing ? null : _captureImage,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: _isCapturing ? Colors.grey : Colors.white,
            width: 4,
          ),
        ),
        child: _isCapturing
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.black,
                ),
              )
            : const Icon(
                Icons.camera,
                color: Colors.black,
                size: 32,
              ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Colors.blue : Colors.black.withOpacity(0.6),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: Colors.white,
          size: 24,
        ),
        onPressed: onPressed,
      ),
    );
  }

  IconData _getFlashIcon() {
    switch (_cameraService.currentFlashMode) {
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.off:
      default:
        return Icons.flash_off;
    }
  }

  void _toggleRealTimeDetection() async {
    if (_isRealTimeDetectionActive) {
      await _stopRealTimeDetection();
    } else {
      await _startRealTimeDetection();
    }
  }

  void _showTapToFocusHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tap anywhere on screen to focus'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Initializing Camera...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera Error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                  _initializeCamera();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter for real-time detection overlay - CLEAN CORNER DOTS ONLY
class RealtimeDetectionPainter extends CustomPainter {
  final EdgeDetectionResult detection;
  final AutoCapturePhase phase;
  final double countdownSeconds;
  final Animation<double> cornerAnimation;

  RealtimeDetectionPainter({
    required this.detection,
    required this.phase,
    required this.countdownSeconds,
    required this.cornerAnimation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detection.corners.length == 4) {
      _drawDetectedDocument(canvas, size);
    } else {
      _drawFrameGuides(canvas, size);
    }
    
    if (phase == AutoCapturePhase.countingDown) {
      _drawCountdown(canvas, size);
    }
  }

  /// Draw only clean corner dots - NO RED LINES as requested
  void _drawDetectedDocument(Canvas canvas, Size size) {
    final corners = detection.corners;
    final confidence = detection.confidence;
    
    // REMOVED: No more red boundary lines - clean interface as requested
    // Only draw corner dots without boundary lines or numbers
    
    for (int i = 0; i < corners.length; i++) {
      _drawCleanCornerDot(canvas, corners[i], confidence);
    }
  }

  /// Draw clean corner dots without numbers or red lines
  void _drawCleanCornerDot(Canvas canvas, Offset corner, double confidence) {
    final color = _getCornerColor(confidence);
    final animationValue = cornerAnimation.value;
    
    // Draw subtle pulsing outer ring
    final outerRingPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    
    final outerRadius = 12.0 * animationValue;
    canvas.drawCircle(corner, outerRadius, outerRingPaint);
    
    // Draw main dot with white border for visibility
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(corner, 8.0, borderPaint);
    
    // Draw colored center dot
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(corner, 6.0, dotPaint);
  }

  void _drawFrameGuides(Canvas canvas, Size size) {
    // Draw document frame guides when no detection
    final frameRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.8,
      height: size.height * 0.6,
    );
    
    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    // Draw dashed rectangle
    _drawDashedRect(canvas, frameRect, guidePaint);
    
    // Draw corner markers
    const cornerSize = 20.0;
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    // Top-left corner
    canvas.drawLine(
      frameRect.topLeft,
      frameRect.topLeft + const Offset(cornerSize, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frameRect.topLeft,
      frameRect.topLeft + const Offset(0, cornerSize),
      cornerPaint,
    );
    
    // Top-right corner
    canvas.drawLine(
      frameRect.topRight,
      frameRect.topRight + const Offset(-cornerSize, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frameRect.topRight,
      frameRect.topRight + const Offset(0, cornerSize),
      cornerPaint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      frameRect.bottomLeft,
      frameRect.bottomLeft + const Offset(cornerSize, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frameRect.bottomLeft,
      frameRect.bottomLeft + const Offset(0, -cornerSize),
      cornerPaint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      frameRect.bottomRight,
      frameRect.bottomRight + const Offset(-cornerSize, 0),
      cornerPaint,
    );
    canvas.drawLine(
      frameRect.bottomRight,
      frameRect.bottomRight + const Offset(0, -cornerSize),
      cornerPaint,
    );
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashWidth = 10.0;
    const dashSpace = 5.0;
    
    // Top edge
    double startX = rect.left;
    while (startX < rect.right) {
      final endX = math.min(startX + dashWidth, rect.right);
      canvas.drawLine(
        Offset(startX, rect.top),
        Offset(endX, rect.top),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
    
    // Right edge
    double startY = rect.top;
    while (startY < rect.bottom) {
      final endY = math.min(startY + dashWidth, rect.bottom);
      canvas.drawLine(
        Offset(rect.right, startY),
        Offset(rect.right, endY),
        paint,
      );
      startY += dashWidth + dashSpace;
    }
    
    // Bottom edge
    startX = rect.right;
    while (startX > rect.left) {
      final endX = math.max(startX - dashWidth, rect.left);
      canvas.drawLine(
        Offset(startX, rect.bottom),
        Offset(endX, rect.bottom),
        paint,
      );
      startX -= dashWidth + dashSpace;
    }
    
    // Left edge
    startY = rect.bottom;
    while (startY > rect.top) {
      final endY = math.max(startY - dashWidth, rect.top);
      canvas.drawLine(
        Offset(rect.left, startY),
        Offset(rect.left, endY),
        paint,
      );
      startY -= dashWidth + dashSpace;
    }
  }

  void _drawCountdown(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final countdown = countdownSeconds.ceil();
    
    // Draw countdown background
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, 50, bgPaint);
    
    // Draw countdown number
    final textPainter = TextPainter(
      text: TextSpan(
        text: countdown.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
    
    // Draw progress ring
    final progressPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    final progress = (3.0 - countdownSeconds) / 3.0;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 45),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  Color _getCornerColor(double confidence) {
    if (confidence > 0.7) return Colors.green;
    if (confidence > 0.4) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(RealtimeDetectionPainter oldDelegate) {
    return oldDelegate.detection != detection ||
           oldDelegate.phase != phase ||
           oldDelegate.countdownSeconds != countdownSeconds ||
           oldDelegate.cornerAnimation.value != cornerAnimation.value;
  }
}
