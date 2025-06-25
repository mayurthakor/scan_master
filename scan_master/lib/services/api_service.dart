// lib/services/api_service.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ApiService {
  // Singleton pattern for consistency with other services
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();
  
  // Private constructor
  ApiService._();
  
  // Specify the region to match where your functions are deployed
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Prepares a document for chat by generating a summary
  /// This calls the new generate-doc-summary function
  Future<String> prepareChatSession(String documentId) async {
    try {
      final callable = _functions.httpsCallable('generate-doc-summary');
      final response = await callable.call<Map<String, dynamic>>({
        'documentId': documentId,
      });

      final summary = response.data['summary'] as String?;
      if (summary == null) {
        throw Exception('Failed to get summary from response.');
      }
      return summary;

    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to prepare chat session: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Asks a question about a document that has been prepared for chat
  Future<String> askQuestion(String documentId, String question) async {
    try {
      final callable = _functions.httpsCallable('chat-with-document');
      final response = await callable.call<Map<String, dynamic>>({
        'documentId': documentId,
        'question': question,
      });
      
      final answer = response.data['answer'] as String?;
      if (answer == null) {
        throw Exception('Failed to get answer from response.');
      }
      return answer;
      
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to get answer: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Saves user feedback (thumbs up/down) for AI responses
  Future<void> saveFeedback(String documentId, String messageId, String feedback) async {
    try {
      await _firestore
          .collection('files')
          .doc(documentId)
          .collection('chat_messages')
          .doc(messageId)
          .update({'feedback': feedback});
    } catch (e) {
      print("Failed to save feedback: $e");
      // Don't throw here as feedback is not critical
    }
  }

  /// Optional: Method to delete chat history for a document
  Future<void> deleteChatHistory(String documentId) async {
    try {
      final callable = _functions.httpsCallable('delete-chat-history');
      await callable.call<Map<String, dynamic>>({
        'documentId': documentId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to delete chat history: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Check if user can upload more files (upload allowance)
  Future<bool> checkUploadAllowance(String userId) async {
    try {
      final callable = _functions.httpsCallable('check-upload-allowance');
      final response = await callable.call<Map<String, dynamic>>({
        'userId': userId,
      });
      
      return response.data['allow'] as bool? ?? false;
    } on FirebaseFunctionsException catch (e) {
      print('Failed to check upload allowance: ${e.message}');
      return false; // Default to not allowed if error
    } catch (e) {
      print('An unexpected error occurred: $e');
      return false;
    }
  }

  /// Create subscription order for Razorpay
  Future<Map<String, dynamic>> createSubscriptionOrder(String userId) async {
    try {
      final callable = _functions.httpsCallable('create-subscription-order');
      final response = await callable.call<Map<String, dynamic>>({
        'userId': userId,
      });
      
      return response.data;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to create subscription order: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Verify payment after successful Razorpay payment
  Future<void> verifyPayment(Map<String, dynamic> paymentData) async {
    try {
      final callable = _functions.httpsCallable('verify-payment');
      await callable.call<Map<String, dynamic>>(paymentData);
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to verify payment: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Get download URL for a file
  Future<String> getDownloadUrl(String documentId) async {
    try {
      final callable = _functions.httpsCallable('get-download-url');
      final response = await callable.call<Map<String, dynamic>>({
        'documentId': documentId,
      });
      
      final url = response.data['url'] as String?;
      if (url == null) {
        throw Exception('Failed to get download URL from response.');
      }
      return url;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to get download URL: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Delete a file and its associated data
  Future<void> deleteFile(String documentId) async {
    try {
      final callable = _functions.httpsCallable('delete-file');
      await callable.call<Map<String, dynamic>>({
        'documentId': documentId,
      });
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Failed to delete file: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }
}