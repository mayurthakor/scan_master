// lib/services/batch_scanning_service.dart
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'enhanced_edge_detection_service.dart';
import 'document_type_recognition_service.dart';

class BatchScanningService {
  static BatchScanningService? _instance;
  static BatchScanningService get instance => 
      _instance ??= BatchScanningService._();
  
  BatchScanningService._();

  BatchScanSession? _currentSession;
  final List<BatchScanSession> _recentSessions = [];
  final int _maxRecentSessions = 10;

  /// Start a new batch scanning session
  Future<BatchScanSession> startBatchSession({
    String? sessionName,
    DocumentType? preferredDocumentType,
    BatchScanMode mode = BatchScanMode.multiPage,
    int? maxPages,
  }) async {
    // End current session if exists
    if (_currentSession != null) {
      await endCurrentSession();
    }

    final sessionId = _generateSessionId();
    final sessionDirectory = await _createSessionDirectory(sessionId);
    
    _currentSession = BatchScanSession(
      sessionId: sessionId,
      sessionName: sessionName ?? 'Scan ${DateTime.now().day}/${DateTime.now().month}',
      mode: mode,
      preferredDocumentType: preferredDocumentType,
      maxPages: maxPages,
      sessionDirectory: sessionDirectory,
      startTime: DateTime.now(),
      pages: [],
      status: BatchScanStatus.active,
    );

    return _currentSession!;
  }

  /// Add a captured page to the current batch session
  Future<ScannedPage> addPageToSession({
    required String imagePath,
    required List<Offset> corners,
    required Size imageSize,
    DocumentType? detectedType,
    String? userNote,
  }) async {
    if (_currentSession == null) {
      throw Exception('No active batch session');
    }

    // Check session limits
    if (_currentSession!.maxPages != null && 
        _currentSession!.pages.length >= _currentSession!.maxPages!) {
      throw Exception('Maximum pages limit reached for this session');
    }

    final pageNumber = _currentSession!.pages.length + 1;
    final pageId = '${_currentSession!.sessionId}_page_$pageNumber';
    
    // Copy image to session directory
    final sessionImagePath = await _copyImageToSession(imagePath, pageId);
    
    // Analyze document if type detection is enabled
    DocumentAnalysisResult? analysis;
    if (detectedType != null) {
      try {
        analysis = await DocumentTypeRecognitionService.instance.analyzeDocument(
          imagePath: sessionImagePath,
          corners: corners,
          imageSize: imageSize,
        );
      } catch (e) {
        print('Document analysis failed for page $pageNumber: $e');
      }
    }

    final scannedPage = ScannedPage(
      pageId: pageId,
      pageNumber: pageNumber,
      imagePath: sessionImagePath,
      originalImagePath: imagePath,
      corners: corners,
      imageSize: imageSize,
      documentType: detectedType ?? DocumentType.unknown,
      analysis: analysis,
      captureTime: DateTime.now(),
      userNote: userNote,
      processingStatus: PageProcessingStatus.captured,
    );

    _currentSession!.pages.add(scannedPage);
    _currentSession!.lastModified = DateTime.now();

    // Auto-detect session document type if not set
    if (_currentSession!.preferredDocumentType == null && detectedType != null) {
      _currentSession!.preferredDocumentType = detectedType;
    }

    return scannedPage;
  }

  /// Remove a page from the current session
  Future<void> removePageFromSession(String pageId) async {
    if (_currentSession == null) {
      throw Exception('No active batch session');
    }

    final pageIndex = _currentSession!.pages.indexWhere((p) => p.pageId == pageId);
    if (pageIndex == -1) {
      throw Exception('Page not found in current session');
    }

    final page = _currentSession!.pages[pageIndex];
    
    // Delete the image file
    try {
      await File(page.imagePath).delete();
    } catch (e) {
      print('Failed to delete page image: $e');
    }

    // Remove from session
    _currentSession!.pages.removeAt(pageIndex);
    
    // Renumber remaining pages
    for (int i = pageIndex; i < _currentSession!.pages.length; i++) {
      _currentSession!.pages[i].pageNumber = i + 1;
    }
    
    _currentSession!.lastModified = DateTime.now();
  }

  /// Reorder pages in the current session
  Future<void> reorderPages(List<String> newPageOrder) async {
    if (_currentSession == null) {
      throw Exception('No active batch session');
    }

    final reorderedPages = <ScannedPage>[];
    
    for (int i = 0; i < newPageOrder.length; i++) {
      final pageId = newPageOrder[i];
      final page = _currentSession!.pages.firstWhere((p) => p.pageId == pageId);
      page.pageNumber = i + 1;
      reorderedPages.add(page);
    }
    
    _currentSession!.pages = reorderedPages;
    _currentSession!.lastModified = DateTime.now();
  }

  /// Update page information
  Future<void> updatePage({
    required String pageId,
    List<Offset>? newCorners,
    String? userNote,
    DocumentType? documentType,
  }) async {
    if (_currentSession == null) {
      throw Exception('No active batch session');
    }

    final pageIndex = _currentSession!.pages.indexWhere((p) => p.pageId == pageId);
    if (pageIndex == -1) {
      throw Exception('Page not found in current session');
    }

    final page = _currentSession!.pages[pageIndex];
    
    if (newCorners != null) {
      page.corners = newCorners;
      page.processingStatus = PageProcessingStatus.modified;
    }
    
    if (userNote != null) {
      page.userNote = userNote;
    }
    
    if (documentType != null) {
      page.documentType = documentType;
    }
    
    _currentSession!.lastModified = DateTime.now();
  }

  /// Process all pages in the current session
  Future<BatchProcessingResult> processCurrentSession({
    bool enhanceImages = true,
    bool generatePdf = true,
    String? outputFileName,
  }) async {
    if (_currentSession == null) {
      throw Exception('No active batch session');
    }

    if (_currentSession!.pages.isEmpty) {
      throw Exception('No pages to process in current session');
    }

    _currentSession!.status = BatchScanStatus.processing;
    
    final processingResults = <PageProcessingResult>[];
    final failedPages = <String>[];
    
    try {
      // Process each page
      for (int i = 0; i < _currentSession!.pages.length; i++) {
        final page = _currentSession!.pages[i];
        
        try {
          page.processingStatus = PageProcessingStatus.processing;
          
          final result = await _processPage(page, enhanceImages);
          processingResults.add(result);
          
          page.processingStatus = PageProcessingStatus.completed;
          page.processedImagePath = result.processedImagePath;
          
        } catch (e) {
          print('Failed to process page ${page.pageNumber}: $e');
          failedPages.add(page.pageId);
          page.processingStatus = PageProcessingStatus.failed;
          page.processingError = e.toString();
        }
      }

      // Generate combined PDF if requested
      String? pdfPath;
      if (generatePdf && processingResults.isNotEmpty) {
        try {
          pdfPath = await _generateCombinedPdf(
            processingResults,
            outputFileName ?? _currentSession!.sessionName,
          );
        } catch (e) {
          print('Failed to generate PDF: $e');
        }
      }

      final batchResult = BatchProcessingResult(
        sessionId: _currentSession!.sessionId,
        sessionName: _currentSession!.sessionName,
        totalPages: _currentSession!.pages.length,
        successfulPages: processingResults.length,
        failedPages: failedPages.length,
        processingResults: processingResults,
        failedPageIds: failedPages,
        pdfPath: pdfPath,
        processingTime: DateTime.now().difference(_currentSession!.startTime),
        outputDirectory: _currentSession!.sessionDirectory,
      );

      _currentSession!.status = failedPages.isEmpty 
          ? BatchScanStatus.completed 
          : BatchScanStatus.partiallyCompleted;
      _currentSession!.processingResult = batchResult;

      return batchResult;
      
    } catch (e) {
      _currentSession!.status = BatchScanStatus.failed;
      rethrow;
    }
  }

  /// End the current session and save it to recent sessions
  Future<void> endCurrentSession() async {
    if (_currentSession == null) return;

    _currentSession!.endTime = DateTime.now();
    
    // Add to recent sessions
    _recentSessions.insert(0, _currentSession!);
    
    // Keep only recent sessions
    if (_recentSessions.length > _maxRecentSessions) {
      final oldSession = _recentSessions.removeLast();
      await _cleanupOldSession(oldSession);
    }

    _currentSession = null;
  }

  /// Get current session information
  BatchScanSession? get currentSession => _currentSession;

  /// Get recent sessions
  List<BatchScanSession> get recentSessions => List.unmodifiable(_recentSessions);

  /// Resume a previous session
  Future<void> resumeSession(String sessionId) async {
    final session = _recentSessions.firstWhere(
      (s) => s.sessionId == sessionId,
      orElse: () => throw Exception('Session not found'),
    );

    if (session.status == BatchScanStatus.completed) {
      throw Exception('Cannot resume completed session');
    }

    // End current session if exists
    if (_currentSession != null) {
      await endCurrentSession();
    }

    _currentSession = session;
    _currentSession!.status = BatchScanStatus.active;
  }

  /// Delete a session and its files
  Future<void> deleteSession(String sessionId) async {
    // Remove from recent sessions
    final sessionIndex = _recentSessions.indexWhere((s) => s.sessionId == sessionId);
    if (sessionIndex != -1) {
      final session = _recentSessions.removeAt(sessionIndex);
      await _cleanupOldSession(session);
    }

    // End current session if it's the one being deleted
    if (_currentSession?.sessionId == sessionId) {
      _currentSession = null;
    }
  }

  /// Get session statistics
  BatchScanStatistics getSessionStatistics(String sessionId) {
    final session = sessionId == _currentSession?.sessionId 
        ? _currentSession 
        : _recentSessions.firstWhere((s) => s.sessionId == sessionId);

    if (session == null) {
      throw Exception('Session not found');
    }

    final documentTypeCounts = <DocumentType, int>{};
    final qualityScores = <double>[];
    int processedPages = 0;

    for (final page in session.pages) {
      // Count document types
      documentTypeCounts[page.documentType] = 
          (documentTypeCounts[page.documentType] ?? 0) + 1;

      // Collect quality scores
      if (page.analysis?.qualityMetrics != null) {
        qualityScores.add(page.analysis!.qualityMetrics.overallScore);
      }

      // Count processed pages
      if (page.processingStatus == PageProcessingStatus.completed) {
        processedPages++;
      }
    }

    final averageQuality = qualityScores.isNotEmpty 
        ? qualityScores.reduce((a, b) => a + b) / qualityScores.length 
        : 0.0;

    return BatchScanStatistics(
      sessionId: sessionId,
      sessionName: session.sessionName,
      totalPages: session.pages.length,
      processedPages: processedPages,
      documentTypeCounts: documentTypeCounts,
      averageQuality: averageQuality,
      sessionDuration: session.endTime?.difference(session.startTime) ?? 
                      DateTime.now().difference(session.startTime),
      status: session.status,
    );
  }

  /// Auto-organize pages by document type
  Future<void> autoOrganizeByDocumentType() async {
    if (_currentSession == null || _currentSession!.pages.isEmpty) return;

    // Group pages by document type
    final groups = <DocumentType, List<ScannedPage>>{};
    
    for (final page in _currentSession!.pages) {
      final type = page.documentType;
      groups[type] = (groups[type] ?? [])..add(page);
    }

    // Reorder pages: group by type, maintain original order within groups
    final reorderedPages = <ScannedPage>[];
    int pageNumber = 1;

    // Prioritize order: A4 documents, business cards, receipts, others
    final typeOrder = [
      DocumentType.a4Document,
      DocumentType.businessCard,
      DocumentType.receipt,
      DocumentType.idCard,
      DocumentType.photo,
      DocumentType.book,
      DocumentType.whiteboard,
      DocumentType.unknown,
    ];

    for (final type in typeOrder) {
      if (groups.containsKey(type)) {
        for (final page in groups[type]!) {
          page.pageNumber = pageNumber++;
          reorderedPages.add(page);
        }
      }
    }

    _currentSession!.pages = reorderedPages;
    _currentSession!.lastModified = DateTime.now();
  }

  /// Private helper methods

  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(1000);
    return 'batch_${timestamp}_$random';
  }

  Future<String> _createSessionDirectory(String sessionId) async {
    final tempDir = await getTemporaryDirectory();
    final sessionDir = Directory(path.join(tempDir.path, 'batch_sessions', sessionId));
    
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }
    
    return sessionDir.path;
  }

  Future<String> _copyImageToSession(String originalPath, String pageId) async {
    if (_currentSession == null) {
      throw Exception('No active session');
    }

    final originalFile = File(originalPath);
    final sessionImagePath = path.join(
      _currentSession!.sessionDirectory,
      '$pageId.jpg',
    );
    
    await originalFile.copy(sessionImagePath);
    return sessionImagePath;
  }

  Future<PageProcessingResult> _processPage(
    ScannedPage page,
    bool enhanceImages,
  ) async {
    // This would integrate with the Enhanced Image Processing Service
    // For now, return a basic result
    
    String processedImagePath = page.imagePath;
    
    if (enhanceImages && page.analysis?.optimizationSettings != null) {
      // Apply image enhancements based on document type
      processedImagePath = await _enhanceImage(page);
    }

    return PageProcessingResult(
      pageId: page.pageId,
      pageNumber: page.pageNumber,
      originalImagePath: page.imagePath,
      processedImagePath: processedImagePath,
      documentType: page.documentType,
      processingTime: const Duration(milliseconds: 500), // Placeholder
      enhancementsApplied: enhanceImages,
    );
  }

  Future<String> _enhanceImage(ScannedPage page) async {
    // Placeholder for image enhancement
    // This would call the Enhanced Image Processing Service
    return page.imagePath; // Return original for now
  }

  Future<String> _generateCombinedPdf(
    List<PageProcessingResult> results,
    String fileName,
  ) async {
    // Placeholder for PDF generation
    // This would combine all processed images into a single PDF
    final outputPath = path.join(
      _currentSession!.sessionDirectory,
      '$fileName.pdf',
    );
    
    // TODO: Implement actual PDF generation
    // For now, just create an empty file
    await File(outputPath).create();
    
    return outputPath;
  }

  Future<void> _cleanupOldSession(BatchScanSession session) async {
    try {
      final sessionDir = Directory(session.sessionDirectory);
      if (await sessionDir.exists()) {
        await sessionDir.delete(recursive: true);
      }
    } catch (e) {
      print('Failed to cleanup session directory: $e');
    }
  }

  /// Cleanup all temporary files and sessions
  Future<void> cleanup() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final batchDir = Directory(path.join(tempDir.path, 'batch_sessions'));
      
      if (await batchDir.exists()) {
        await batchDir.delete(recursive: true);
      }
      
      _recentSessions.clear();
      _currentSession = null;
    } catch (e) {
      print('Cleanup failed: $e');
    }
  }
}

// Data classes and enums

enum BatchScanMode {
  multiPage,      // Multiple pages of the same document
  mixedDocuments, // Different document types in one batch
  receipt,        // Receipt-specific batch mode
  businessCard,   // Business card batch mode
}

enum BatchScanStatus {
  active,
  paused,
  processing,
  completed,
  partiallyCompleted,
  failed,
  cancelled,
}

enum PageProcessingStatus {
  captured,
  modified,
  processing,
  completed,
  failed,
}

class BatchScanSession {
  final String sessionId;
  String sessionName;
  final BatchScanMode mode;
  DocumentType? preferredDocumentType;
  final int? maxPages;
  final String sessionDirectory;
  final DateTime startTime;
  DateTime? endTime;
  DateTime lastModified;
  List<ScannedPage> pages;
  BatchScanStatus status;
  BatchProcessingResult? processingResult;

  BatchScanSession({
    required this.sessionId,
    required this.sessionName,
    required this.mode,
    this.preferredDocumentType,
    this.maxPages,
    required this.sessionDirectory,
    required this.startTime,
    this.endTime,
    DateTime? lastModified,
    required this.pages,
    required this.status,
    this.processingResult,
  }) : lastModified = lastModified ?? DateTime.now();

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);
  
  bool get isActive => status == BatchScanStatus.active;
  bool get isComplete => status == BatchScanStatus.completed;
  bool get hasPages => pages.isNotEmpty;
  
  double get completionPercentage {
    if (pages.isEmpty) return 0.0;
    final completedPages = pages.where((p) => 
        p.processingStatus == PageProcessingStatus.completed).length;
    return completedPages / pages.length;
  }
}

class ScannedPage {
  final String pageId;
  int pageNumber;
  final String imagePath;
  final String originalImagePath;
  List<Offset> corners;
  final Size imageSize;
  DocumentType documentType;
  final DocumentAnalysisResult? analysis;
  final DateTime captureTime;
  String? userNote;
  PageProcessingStatus processingStatus;
  String? processedImagePath;
  String? processingError;

  ScannedPage({
    required this.pageId,
    required this.pageNumber,
    required this.imagePath,
    required this.originalImagePath,
    required this.corners,
    required this.imageSize,
    required this.documentType,
    this.analysis,
    required this.captureTime,
    this.userNote,
    required this.processingStatus,
    this.processedImagePath,
    this.processingError,
  });

  bool get isProcessed => processingStatus == PageProcessingStatus.completed;
  bool get hasFailed => processingStatus == PageProcessingStatus.failed;
  bool get isModified => processingStatus == PageProcessingStatus.modified;
  
  double get qualityScore => analysis?.qualityMetrics.overallScore ?? 0.0;
}

class BatchProcessingResult {
  final String sessionId;
  final String sessionName;
  final int totalPages;
  final int successfulPages;
  final int failedPages;
  final List<PageProcessingResult> processingResults;
  final List<String> failedPageIds;
  final String? pdfPath;
  final Duration processingTime;
  final String outputDirectory;

  BatchProcessingResult({
    required this.sessionId,
    required this.sessionName,
    required this.totalPages,
    required this.successfulPages,
    required this.failedPages,
    required this.processingResults,
    required this.failedPageIds,
    this.pdfPath,
    required this.processingTime,
    required this.outputDirectory,
  });

  bool get isFullySuccessful => failedPages == 0;
  double get successRate => totalPages > 0 ? successfulPages / totalPages : 0.0;
}

class PageProcessingResult {
  final String pageId;
  final int pageNumber;
  final String originalImagePath;
  final String processedImagePath;
  final DocumentType documentType;
  final Duration processingTime;
  final bool enhancementsApplied;

  PageProcessingResult({
    required this.pageId,
    required this.pageNumber,
    required this.originalImagePath,
    required this.processedImagePath,
    required this.documentType,
    required this.processingTime,
    required this.enhancementsApplied,
  });
}

class BatchScanStatistics {
  final String sessionId;
  final String sessionName;
  final int totalPages;
  final int processedPages;
  final Map<DocumentType, int> documentTypeCounts;
  final double averageQuality;
  final Duration sessionDuration;
  final BatchScanStatus status;

  BatchScanStatistics({
    required this.sessionId,
    required this.sessionName,
    required this.totalPages,
    required this.processedPages,
    required this.documentTypeCounts,
    required this.averageQuality,
    required this.sessionDuration,
    required this.status,
  });

  DocumentType? get mostCommonDocumentType {
    if (documentTypeCounts.isEmpty) return null;
    
    var maxCount = 0;
    DocumentType? mostCommon;
    
    for (final entry in documentTypeCounts.entries) {
      if (entry.value > maxCount) {
        maxCount = entry.value;
        mostCommon = entry.key;
      }
    }
    
    return mostCommon;
  }

  double get processingProgress => totalPages > 0 ? processedPages / totalPages : 0.0;
}