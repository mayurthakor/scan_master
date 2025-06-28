// lib/features/home/domain/repositories/home_repository.dart
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

/// Repository interface for home feature
/// This defines the contract that HomeRepositoryImpl must implement
abstract class HomeRepository {
  
  // Document Management
  Future<List<Map<String, dynamic>>> getUserDocuments();
  Future<bool> deleteDocument(String documentId);
  
  // File Upload
  Future<UploadTask> uploadFile(File file, String fileName);
  Future<UploadTask> uploadScannedDocument(String imagePath);
  
  // User Statistics
  Future<Map<String, dynamic>> getUserStats();
  Future<bool> checkUploadLimit();
  Future<void> incrementUploadCount();
  
  // Chat Preparation
  Future<bool> prepareChatForDocument(String documentId);
  Future<String> getChatPreparationStatus(String documentId);
  
  // Subscription & Payment
  Future<Map<String, dynamic>> createSubscriptionOrder();
  Future<bool> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  });
  Future<bool> updateSubscriptionStatus(bool isSubscribed);
  
  // Helper Methods
  Future<bool> isUserSubscribed();
  Future<String> generateFileName(String originalName);
  Future<void> updateDocumentMetadata(String documentId, Map<String, dynamic> metadata);
}