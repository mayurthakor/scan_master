// lib/services/enhanced_camera_service.dart
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'enhanced_edge_detection_service.dart';
import 'batch_scanning_service.dart';

// Enum declaration at top level (outside class)
enum AutoCapturePhase {
  detecting,
  notificationShown,
  countingDown,
  capturing,
  completed
}

class EnhancedCameraService {
  static EnhancedCameraService? _instance;
  static EnhancedCameraService get instance => 
      _instance ??= EnhancedCameraService._();
  
  EnhancedCameraService._();

  List<CameraDescription>? _cameras;
  CameraController? _controller;
  bool _isInitialized = false;

  // Auto-capture functionality
  Timer? _detectionTimer;
  bool _isAutoDetecting = false;
  bool _isCaptureInProgress = false;
  EdgeDetectionResult? _lastDetectionResult;
  final EnhancedEdgeDetectionService _edgeDetectionService = EnhancedEdgeDetectionService();

  // New auto-capture phase tracking
  AutoCapturePhase _autoCapturePhase = AutoCapturePhase.detecting;
  Timer? _countdownTimer;
  double _countdownSeconds = 2.0;
  List<Offset> _lastStableCorners = [];
  DateTime? _lastMovementTime;

  List<CameraDescription>? get cameras => _cameras;
  CameraController? get controller => _controller;
  bool get isInitialized => _isInitialized;
  bool get isAutoDetecting => _isAutoDetecting;

  /// Initialize camera service
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras?.isEmpty ?? true) {
        throw Exception('No cameras available');
      }
    } catch (e) {
      print('Camera initialization error: $e');
      rethrow;
    }
  }

  /// Initialize camera controller with specified camera
  Future<void> initializeController({
    CameraDescription? camera,
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    if (_cameras?.isEmpty ?? true) {
      await initialize();
    }

    final selectedCamera = camera ?? _cameras!.first;

    try {
      _controller = CameraController(
        selectedCamera,
        resolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      _isInitialized = true;
    } catch (e) {
      print('Camera controller initialization error: $e');
      _isInitialized = false;
      rethrow;
    }
  }

  /// Start auto-detection for documents with new phase-based approach
  void startAutoDetection({
    AutoCaptureSettings? settings,
    required Function(EdgeDetectionResult) onDetectionUpdate,
    required Function(String imagePath) onAutoCapture,
  }) {
    if (!_isInitialized || _isAutoDetecting) return;

    _isAutoDetecting = true;
    _autoCapturePhase = AutoCapturePhase.detecting;
    _lastMovementTime = DateTime.now();
    
    _edgeDetectionService.updateAutoCaptureSettings(
      settings ?? const AutoCaptureSettings(),
    );

    // Lightweight detection every 500ms (no takePicture during detection)
    _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!_isInitialized || !_isAutoDetecting) {
        timer.cancel();
        return;
      }

      if (_isCaptureInProgress) {
        print('Skipping detection - capture in progress');
        return;
      }

      try {
        // Generate mock detection result (lightweight, no camera calls)
        final mockResult = _generateMockDetectionResult();
        
        _lastDetectionResult = mockResult;
        onDetectionUpdate(mockResult);

        // Check if we found good edges and should start notification phase
        if (_autoCapturePhase == AutoCapturePhase.detecting && 
            mockResult.corners.length == 4 && 
            mockResult.confidence > 0.8) {
          _startNotificationPhase(onAutoCapture);
        }
        
      } catch (e) {
        print('Auto-detection error: $e');
      }
    });
  }

  /// Stop auto-detection
  void stopAutoDetection() {
    _isAutoDetecting = false;
    _isCaptureInProgress = false;
    _autoCapturePhase = AutoCapturePhase.detecting;
    _countdownSeconds = 0.4;
    _detectionTimer?.cancel();
    _countdownTimer?.cancel();
    _detectionTimer = null;
    _countdownTimer = null;
    _edgeDetectionService.resetAutoCaptureTracking();
  }

  /// Switch between front and back camera
  Future<void> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      throw Exception('Cannot switch camera - only one camera available');
    }

    final currentCamera = _controller?.description;
    CameraDescription newCamera;

    if (currentCamera?.lensDirection == CameraLensDirection.back) {
      newCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
    } else {
      newCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
    }

    await disposeController();
    await initializeController(camera: newCamera);
  }

  /// Toggle flash mode
  Future<void> toggleFlash() async {
    if (_controller == null || !_isInitialized) {
      throw Exception('Camera not initialized');
    }

    final currentFlashMode = _controller!.value.flashMode;
    FlashMode newFlashMode;

    switch (currentFlashMode) {
      case FlashMode.off:
        newFlashMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        newFlashMode = FlashMode.always;
        break;
      case FlashMode.always:
      case FlashMode.torch:
        newFlashMode = FlashMode.off;
        break;
    }

    await _controller!.setFlashMode(newFlashMode);
  }

  /// Get current flash mode
  FlashMode get currentFlashMode {
    return _controller?.value.flashMode ?? FlashMode.off;
  }

  /// Set focus point
  Future<void> setFocusPoint(Offset point) async {
    if (_controller == null || !_isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      await _controller!.setFocusPoint(point);
      await _controller!.setExposurePoint(point);
    } catch (e) {
      print('Focus setting error: $e');
      // Don't throw - some devices don't support manual focus
    }
  }

  /// Capture image and save to temporary directory
  Future<String> captureImage() async {
    if (_controller == null || !_isInitialized) {
      throw Exception('Camera not initialized');
    }

    try {
      // Add haptic feedback
      await HapticFeedback.lightImpact();

      final XFile image = await _controller!.takePicture();
      
      // Create a unique filename
      final directory = await getTemporaryDirectory();
      final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = path.join(directory.path, fileName);
      
      // Copy to permanent location
      await File(image.path).copy(savedPath);
      
      return savedPath;
    } catch (e) {
      print('Image capture error: $e');
      rethrow;
    }
  }

  /// Get camera preview size
  Size? get previewSize {
    if (_controller == null || !_isInitialized) return null;
    return _controller!.value.previewSize;
  }

  /// Get aspect ratio
  double get aspectRatio {
    if (_controller == null || !_isInitialized) return 1.0;
    return _controller!.value.aspectRatio;
  }

  /// Check if camera supports flash
  bool get hasFlash {
    return _controller?.description.lensDirection == CameraLensDirection.back;
  }

  /// Get current detection result
  EdgeDetectionResult? get lastDetectionResult => _lastDetectionResult;

  /// Get auto-capture status
  AutoCaptureStatus get autoCaptureStatus => _edgeDetectionService.getAutoCaptureStatus();

  /// Get current auto-capture phase
  AutoCapturePhase get currentPhase => _autoCapturePhase;

  /// Get countdown seconds
  double get countdownSeconds => _countdownSeconds;

  /// Dispose camera controller
  Future<void> disposeController() async {
    stopAutoDetection();
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
      _isInitialized = false;
    }
  }

  /// Clean up temporary files
  Future<void> cleanupTempFiles() async {
    try {
      final directory = await getTemporaryDirectory();
      final files = directory.listSync();
      
      for (final file in files) {
        if (file is File && file.path.contains('scan_')) {
          final stat = await file.stat();
          final age = DateTime.now().difference(stat.modified);
          
          // Delete files older than 24 hours
          if (age.inHours > 24) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      print('Cleanup error: $e');
      // Don't throw - cleanup is not critical
    }
  }

  // PRIVATE METHODS FOR AUTO-CAPTURE FLOW

  /// Generate mock detection result (replace with real lightweight detection later)
  EdgeDetectionResult _generateMockDetectionResult() {
    // Simulate finding corners after some time
    final now = DateTime.now();
    final timeSinceStart = now.difference(_lastMovementTime ?? now).inSeconds;
    
    if (timeSinceStart > 3) { // Simulate finding corners after 3 seconds
      final corners = [
        const Offset(100, 100),
        const Offset(300, 120),
        const Offset(280, 400),
        const Offset(80, 380),
      ];
      
      _lastStableCorners = corners;
      
      return EdgeDetectionResult(
        corners: corners,
        confidence: 0.85,
        method: 'mock',
        requiresManualAdjustment: false,
        documentType: DocumentType.a4Document,
        isReadyForAutoCapture: true,
        positioningFeedback: _getPhaseMessage(),
      );
    }
    
    return EdgeDetectionResult(
      corners: [],
      confidence: 0.3,
      method: 'mock',
      requiresManualAdjustment: true,
      documentType: DocumentType.unknown,
      isReadyForAutoCapture: false,
      positioningFeedback: 'Position document in frame',
    );
  }

  /// Get message based on current phase
  String _getPhaseMessage() {
    switch (_autoCapturePhase) {
      case AutoCapturePhase.detecting:
        return 'Position document in frame';
      case AutoCapturePhase.notificationShown:
        return 'Document detected! Hold steady for auto-capture';
      case AutoCapturePhase.countingDown:
        return 'Hold steady: ${_countdownSeconds.toStringAsFixed(1)}s';
      case AutoCapturePhase.capturing:
        return 'Capturing...';
      case AutoCapturePhase.completed:
        return 'Photo captured!';
    }
  }

  /// Start notification phase
  void _startNotificationPhase(Function(String) onAutoCapture) {
    _autoCapturePhase = AutoCapturePhase.notificationShown;
    _lastMovementTime = DateTime.now();
    
    // After showing notification for a brief moment, start countdown
    Timer(const Duration(milliseconds: 500), () {
      if (_autoCapturePhase == AutoCapturePhase.notificationShown) {
        _startCountdown(onAutoCapture);
      }
    });
  }

  /// Start 0.8-second countdown with milliseconds
  void _startCountdown(Function(String) onAutoCapture) {
    _autoCapturePhase = AutoCapturePhase.countingDown;
    _countdownSeconds = 0.4;
    
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _countdownSeconds -= 0.1;
      
      // Check for movement during countdown
      if (_hasMovementDetected()) {
        _cancelCountdown();
        return;
      }
      
      if (_countdownSeconds <= 0) {
        timer.cancel();
        _executeAutoCapture(onAutoCapture);
      }
    });
  }

  /// Check if significant movement detected
  bool _hasMovementDetected() {
    // Check if corners have moved significantly since last stable position
    if (_lastDetectionResult?.corners.length != 4 || _lastStableCorners.length != 4) {
      return true;
    }
    
    for (int i = 0; i < 4; i++) {
      final distance = (_lastDetectionResult!.corners[i] - _lastStableCorners[i]).distance;
      if (distance > 20.0) { // 20 pixel movement threshold
        return true;
      }
    }
    return false;
  }

  /// Cancel countdown due to movement
  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _autoCapturePhase = AutoCapturePhase.detecting;
    _countdownSeconds = 0.4;
    print('Auto-capture cancelled - movement detected');
  }

  /// Execute the actual auto-capture
  Future<void> _executeAutoCapture(Function(String) onAutoCapture) async {
    _autoCapturePhase = AutoCapturePhase.capturing;
    
    try {
      // Flash/haptic before capture
      await HapticFeedback.heavyImpact();
      
      // Take actual photo
      final imagePath = await captureImage();
      
      _autoCapturePhase = AutoCapturePhase.completed;
      onAutoCapture(imagePath);
      
      // Auto-stop detection after successful capture
      stopAutoDetection();
      
    } catch (e) {
      print('Auto-capture execution failed: $e');
      _autoCapturePhase = AutoCapturePhase.detecting;
    }
  }
}

/// Enhanced camera screen with Phase 2 features
class EnhancedCameraScreen extends StatefulWidget {
  final Function(String imagePath) onImageCaptured;
  final BatchScanSession? batchSession;
  final DocumentType? preferredDocumentType;
  final bool enableAutoCapture;

  const EnhancedCameraScreen({
    super.key,
    required this.onImageCaptured,
    this.batchSession,
    this.preferredDocumentType,
    this.enableAutoCapture = true,
  });

  @override
  State<EnhancedCameraScreen> createState() => _EnhancedCameraScreenState();
}

class _EnhancedCameraScreenState extends State<EnhancedCameraScreen>
    with WidgetsBindingObserver {
  final EnhancedCameraService _cameraService = EnhancedCameraService.instance;
  bool _isLoading = true;
  bool _isCapturing = false;
  bool _autoDetectionEnabled = false;
  String? _error;
  
  EdgeDetectionResult? _currentDetection;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _cameraService.stopAutoDetection();
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
      _cameraService.stopAutoDetection();
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

      await _cameraService.initializeController();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // Start auto-detection if enabled
        if (widget.enableAutoCapture) {
          _toggleAutoDetection();
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

  void _toggleAutoDetection() {
    if (_autoDetectionEnabled) {
      _cameraService.stopAutoDetection();
      setState(() {
        _autoDetectionEnabled = false;
        _currentDetection = null;
      });
    } else {
      final settings = AutoCaptureSettings(
        preferredDocumentType: widget.preferredDocumentType,
        enableAutoCapture: true,
        minConfidenceThreshold: 0.85,
        stabilityDuration: const Duration(milliseconds: 2000),
      );
      
      _cameraService.startAutoDetection(
        settings: settings,
        onDetectionUpdate: _onDetectionUpdate,
        onAutoCapture: _onAutoCapture,
      );
      
      setState(() {
        _autoDetectionEnabled = true;
      });
    }
  }

  void _onDetectionUpdate(EdgeDetectionResult result) {
    if (mounted) {
      setState(() {
        _currentDetection = result;
      });
    }
  }

  void _onAutoCapture(String imagePath) {
    if (mounted) {
      _handleCapturedImage(imagePath, isAutoCapture: true);
    }
  }

  Future<void> _captureImage() async {
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final imagePath = await _cameraService.captureImage();
      _handleCapturedImage(imagePath, isAutoCapture: false);
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
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _handleCapturedImage(String imagePath, {required bool isAutoCapture}) {
    // Add to batch session if available
    if (widget.batchSession != null && _currentDetection != null) {
      BatchScanningService.instance.addPageToSession(
        imagePath: imagePath,
        corners: _currentDetection!.corners,
        imageSize: Size(
          _cameraService.previewSize?.height ?? 1920,
          _cameraService.previewSize?.width ?? 1080,
        ),
        detectedType: _currentDetection!.documentType,
        userNote: isAutoCapture ? 'Auto-captured' : null,
      );
    }
    
    widget.onImageCaptured(imagePath);
  }

  Future<void> _switchCamera() async {
    try {
      final wasAutoDetecting = _autoDetectionEnabled;
      if (wasAutoDetecting) {
        _cameraService.stopAutoDetection();
      }
      
      await _cameraService.switchCamera();
      
      if (wasAutoDetecting) {
        _toggleAutoDetection();
      }
      
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to switch camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleFlash() async {
    try {
      await _cameraService.toggleFlash();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle flash: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onTapToFocus(TapUpDetails details) {
    if (_cameraService.controller == null) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    final size = renderBox.size;

    // Convert to camera coordinates (0.0 to 1.0)
    final focusPoint = Offset(
      localPosition.dx / size.width,
      localPosition.dy / size.height,
    );

    _cameraService.setFocusPoint(focusPoint);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Initializing camera...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              'Camera Error',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initializeCamera,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_cameraService.isInitialized) {
      return const Center(
        child: Text(
          'Camera not available',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return Stack(
      children: [
        _buildCameraPreview(),
        _buildDetectionOverlay(),
        _buildTopControls(),
        _buildBottomControls(),
        _buildFeedbackOverlay(),
      ],
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraService.controller!;
    
    return GestureDetector(
      onTapUp: _onTapToFocus,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 0,
            height: controller.value.previewSize?.width ?? 0,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionOverlay() {
    return CustomPaint(
      size: Size.infinite,
      painter: EnhancedDocumentOverlayPainter(
        detectionResult: _currentDetection,
        isAutoDetecting: _autoDetectionEnabled,
        autoCaptureStatus: _cameraService.autoCaptureStatus,
        currentPhase: _cameraService.currentPhase,
        countdownSeconds: _cameraService.countdownSeconds,
      ),
    );
  }

  Widget _buildTopControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildControlButton(
                  icon: Icons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _getTopMessage(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.batchSession != null)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade700,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Batch: ${widget.batchSession!.pages.length + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_cameraService.hasFlash)
                  _buildControlButton(
                    icon: _getFlashIcon(),
                    onPressed: _toggleFlash,
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
            if (_autoDetectionEnabled && _currentDetection != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getDetectionColor(),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _currentDetection!.positioningFeedback,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getTopMessage() {
    if (_autoDetectionEnabled) {
      return 'Auto-capture enabled';
    } else if (widget.batchSession != null) {
      return 'Batch scanning mode';
    } else {
      return 'Position document in frame';
    }
  }

  Color _getDetectionColor() {
    if (_currentDetection == null) return Colors.grey;
    
    switch (_cameraService.currentPhase) {
      case AutoCapturePhase.detecting:
        return Colors.blue;
      case AutoCapturePhase.notificationShown:
        return Colors.orange;
      case AutoCapturePhase.countingDown:
        return Colors.green;
      case AutoCapturePhase.capturing:
        return Colors.purple;
      case AutoCapturePhase.completed:
        return Colors.green;
    }
  }

  Widget _buildBottomControls() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Auto-detection toggle
              _buildControlButton(
                icon: _autoDetectionEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                onPressed: widget.enableAutoCapture ? _toggleAutoDetection : null,
                isSecondary: true,
                isActive: _autoDetectionEnabled,
              ),
              
              // Capture button
              GestureDetector(
                onTap: _captureImage,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getCaptureButtonColor(),
                    border: Border.all(
                      color: Colors.white,
                      width: 4,
                    ),
                  ),
                  child: _isCapturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : Icon(
                          _autoDetectionEnabled ? Icons.radio_button_checked : Icons.camera_alt,
                          size: 40,
                          color: Colors.black,
                        ),
                ),
              ),
              
              // Camera switch button
              if ((_cameraService.cameras?.length ?? 0) > 1)
                _buildControlButton(
                  icon: Icons.flip_camera_ios,
                  onPressed: _switchCamera,
                  isSecondary: true,
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCaptureButtonColor() {
    if (_autoDetectionEnabled) {
      switch (_cameraService.currentPhase) {
        case AutoCapturePhase.detecting:
          return Colors.orange;
        case AutoCapturePhase.notificationShown:
        case AutoCapturePhase.countingDown:
          return Colors.green;
        case AutoCapturePhase.capturing:
          return Colors.purple;
        case AutoCapturePhase.completed:
          return Colors.green;
      }
    }
    return Colors.white;
  }

  Widget _buildFeedbackOverlay() {
    if (!_autoDetectionEnabled || _currentDetection == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.only(bottom: 140),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Confidence: ${(_currentDetection!.confidence * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            if (_currentDetection!.documentType != DocumentType.unknown)
              Text(
                'Type: ${_getDocumentTypeName(_currentDetection!.documentType)}',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            if (_cameraService.currentPhase == AutoCapturePhase.countingDown)
              Text(
                'Countdown: ${_cameraService.countdownSeconds.toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  String _getDocumentTypeName(DocumentType type) {
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
        return 'Book';
      case DocumentType.whiteboard:
        return 'Whiteboard';
      default:
        return 'Unknown';
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    bool isSecondary = false,
    bool isActive = false,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive 
            ? Colors.blue
            : isSecondary 
                ? Colors.black54 
                : Colors.white24,
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
}

/// Enhanced overlay painter with detection feedback
class EnhancedDocumentOverlayPainter extends CustomPainter {
  final EdgeDetectionResult? detectionResult;
  final bool isAutoDetecting;
  final AutoCaptureStatus autoCaptureStatus;
  final AutoCapturePhase currentPhase;
  final double countdownSeconds;

  EnhancedDocumentOverlayPainter({
    this.detectionResult,
    required this.isAutoDetecting,
    required this.autoCaptureStatus,
    required this.currentPhase,
    required this.countdownSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detectionResult != null && detectionResult!.corners.length == 4) {
      _drawDetectedDocument(canvas, size);
    } else {
      _drawDocumentGuides(canvas, size);
    }
    
    if (isAutoDetecting) {
      _drawAutoDetectionIndicator(canvas, size);
    }

    // Draw countdown timer if in countdown phase
    if (currentPhase == AutoCapturePhase.countingDown) {
      _drawCountdownTimer(canvas, size);
    }
  }

  void _drawDetectedDocument(Canvas canvas, Size size) {
    final corners = detectionResult!.corners;
    final confidence = detectionResult!.confidence;
    
    // Scale corners to screen size (simplified scaling)
    final scaledCorners = corners.map((corner) => Offset(
      corner.dx * size.width / 1920, // Assuming default preview size
      corner.dy * size.height / 1080,
    )).toList();
    
    // Draw document boundary with phase-based color
    final paint = Paint()
      ..color = _getPhaseColor()
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    if (scaledCorners.isNotEmpty) {
      path.moveTo(scaledCorners[0].dx, scaledCorners[0].dy);
      for (int i = 1; i < scaledCorners.length; i++) {
        path.lineTo(scaledCorners[i].dx, scaledCorners[i].dy);
      }
      path.close();
    }
    
    canvas.drawPath(path, paint);
    
    // Draw corner indicators (dots)
    for (int i = 0; i < scaledCorners.length; i++) {
      _drawCornerDot(canvas, scaledCorners[i], i + 1);
    }
  }

  void _drawDocumentGuides(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw document frame guide
    final frameRect = _calculateFrameRect(size);
    
    // Draw corner guides
    _drawCornerGuides(canvas, frameRect, paint);
    
    // Draw center guidelines
    _drawCenterGuides(canvas, frameRect, paint);
  }

  void _drawAutoDetectionIndicator(Canvas canvas, Size size) {
    // Draw auto-detection status indicator
    final indicatorPaint = Paint()
      ..color = _getPhaseColor()
      ..style = PaintingStyle.fill;
    
    const indicatorSize = 12.0;
    final indicatorCenter = Offset(size.width - 30, 30);
    
    canvas.drawCircle(indicatorCenter, indicatorSize, indicatorPaint);
    
    // Pulsing effect for active phases
    if (currentPhase == AutoCapturePhase.countingDown ||
        currentPhase == AutoCapturePhase.notificationShown) {
      final pulsePaint = Paint()
        ..color = _getPhaseColor().withOpacity(0.3)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(indicatorCenter, indicatorSize * 1.5, pulsePaint);
    }
  }

  void _drawCountdownTimer(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 80.0;
    
    // Draw countdown circle background
    final backgroundPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, radius, backgroundPaint);
    
    // Draw countdown progress arc
    final progressPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    final progress = (0.4 - countdownSeconds) / 0.4;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 20),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
    
    // Draw countdown text
    final textPainter = TextPainter(
      text: TextSpan(
        text: countdownSeconds.toStringAsFixed(1),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  Color _getPhaseColor() {
    switch (currentPhase) {
      case AutoCapturePhase.detecting:
        return Colors.blue;
      case AutoCapturePhase.notificationShown:
        return Colors.orange;
      case AutoCapturePhase.countingDown:
        return Colors.green;
      case AutoCapturePhase.capturing:
        return Colors.purple;
      case AutoCapturePhase.completed:
        return Colors.green;
    }
  }

  void _drawCornerDot(Canvas canvas, Offset corner, int number) {
    // Draw corner dot
    final cornerPaint = Paint()
      ..color = _getPhaseColor()
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(corner, 8, cornerPaint);
    
    // Draw corner number
    final textPainter = TextPainter(
      text: TextSpan(
        text: number.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        corner.dx - textPainter.width / 2,
        corner.dy - textPainter.height / 2,
      ),
    );
  }

  Rect _calculateFrameRect(Size size) {
    const margin = 40.0;
    const aspectRatio = 1.4; // A4 ratio approximately
    
    final maxWidth = size.width - (margin * 2);
    final maxHeight = size.height - (margin * 4); // Extra margin for top/bottom
    
    double frameWidth, frameHeight;
    
    if (maxWidth / aspectRatio <= maxHeight) {
      frameWidth = maxWidth;
      frameHeight = maxWidth / aspectRatio;
    } else {
      frameHeight = maxHeight;
      frameWidth = maxHeight * aspectRatio;
    }
    
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;
    
    return Rect.fromLTWH(left, top, frameWidth, frameHeight);
  }

  void _drawCornerGuides(Canvas canvas, Rect frameRect, Paint paint) {
    const cornerLength = 30.0;
    
    // Top-left corner
    canvas.drawLine(
      frameRect.topLeft,
      frameRect.topLeft + const Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      frameRect.topLeft,
      frameRect.topLeft + const Offset(0, cornerLength),
      paint,
    );
    
    // Top-right corner
    canvas.drawLine(
      frameRect.topRight,
      frameRect.topRight + const Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      frameRect.topRight,
      frameRect.topRight + const Offset(0, cornerLength),
      paint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      frameRect.bottomRight,
      frameRect.bottomRight + const Offset(-cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      frameRect.bottomRight,
      frameRect.bottomRight + const Offset(0, -cornerLength),
      paint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      frameRect.bottomLeft,
      frameRect.bottomLeft + const Offset(cornerLength, 0),
      paint,
    );
    canvas.drawLine(
      frameRect.bottomLeft,
      frameRect.bottomLeft + const Offset(0, -cornerLength),
      paint,
    );
  }

  void _drawCenterGuides(Canvas canvas, Rect frameRect, Paint paint) {
    // Draw center crosshair
    final center = frameRect.center;
    const crosshairLength = 20.0;
    
    final crosshairPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(
      center + const Offset(-crosshairLength, 0),
      center + const Offset(crosshairLength, 0),
      crosshairPaint,
    );
    canvas.drawLine(
      center + const Offset(0, -crosshairLength),
      center + const Offset(0, crosshairLength),
      crosshairPaint,
    );
    
    // Draw grid lines for alignment
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    
    // Horizontal grid lines
    for (int i = 1; i < 3; i++) {
      final y = frameRect.top + (frameRect.height / 3) * i;
      canvas.drawLine(
        Offset(frameRect.left, y),
        Offset(frameRect.right, y),
        gridPaint,
      );
    }
    
    // Vertical grid lines
    for (int i = 1; i < 3; i++) {
      final x = frameRect.left + (frameRect.width / 3) * i;
      canvas.drawLine(
        Offset(x, frameRect.top),
        Offset(x, frameRect.bottom),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(EnhancedDocumentOverlayPainter oldDelegate) {
    return oldDelegate.detectionResult != detectionResult ||
           oldDelegate.isAutoDetecting != isAutoDetecting ||
           oldDelegate.autoCaptureStatus != autoCaptureStatus ||
           oldDelegate.currentPhase != currentPhase ||
           oldDelegate.countdownSeconds != countdownSeconds;
  }
}

/// Extension to add enhanced scanner functionality to existing screens
extension EnhancedScannerIntegration on Widget {
  /// Navigate to enhanced camera screen with Phase 2 features
  static void navigateToEnhancedScanner(
    BuildContext context, {
    required Function(String imagePath) onImageCaptured,
    BatchScanSession? batchSession,
    DocumentType? preferredDocumentType,
    bool enableAutoCapture = true,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EnhancedCameraScreen(
          onImageCaptured: onImageCaptured,
          batchSession: batchSession,
          preferredDocumentType: preferredDocumentType,
          enableAutoCapture: enableAutoCapture,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// Start a new batch scanning session
  static Future<void> startBatchScanning(
    BuildContext context, {
    String? sessionName,
    DocumentType? preferredDocumentType,
    int? maxPages,
    required Function(BatchScanSession session) onSessionCreated,
  }) async {
    try {
      final session = await BatchScanningService.instance.startBatchSession(
        sessionName: sessionName,
        preferredDocumentType: preferredDocumentType,
        maxPages: maxPages,
      );
      
      onSessionCreated(session);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start batch session: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}