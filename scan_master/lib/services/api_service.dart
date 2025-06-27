// lib/services/api_service.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

class ApiService {
  // Singleton pattern for consistency with other services
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();
  
  // Private constructor
  ApiService._();
  
  // Firebase Functions fallback
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: ApiConfig.fallbackRegion);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Generic method to call either load balancer or Firebase Functions
  Future<Map<String, dynamic>> _callService(String serviceName, Map<String, dynamic> data) async {
    if (ApiConfig.shouldUseLoadBalancer(serviceName)) {
      return await _callLoadBalancer(serviceName, data);
    } else {
      return await _callFirebaseFunction(serviceName, data);
    }
  }

  /// Call service via load balancer
  Future<Map<String, dynamic>> _callLoadBalancer(String serviceName, Map<String, dynamic> data) async {
    try {
      final url = ApiConfig.getLoadBalancerUrl(serviceName);
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdToken();

      if (ApiConfig.enableDebugLogs) {
        print('🌍 Calling load balancer: $url');
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'data': data}),
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (ApiConfig.enableDebugLogs) {
          print('✅ Load balancer response: ${response.statusCode}');
        }
        
        return responseData;
      } else {
        throw Exception('Load balancer error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (ApiConfig.enableDebugLogs) {
        print('🚨 Load balancer failed: $e');
        print('⬇️ Falling back to Firebase Functions...');
      }
      // Fallback to Firebase Functions
      return await _callFirebaseFunction(serviceName, data);
    }
  }

  /// Call service via Firebase Functions (fallback)
  Future<Map<String, dynamic>> _callFirebaseFunction(String serviceName, Map<String, dynamic> data) async {
    try {
      final callable = _functions.httpsCallable(serviceName);
      final response = await callable.call<Map<String, dynamic>>(data);
      
      if (ApiConfig.enableDebugLogs) {
        print('🔥 Firebase Functions response for $serviceName');
      }
      
      return response.data;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Firebase Functions error: ${e.message}');
    }
  }

  /// Prepares a document for chat by generating a summary
  Future<String> prepareChatSession(String documentId) async {
    try {
      final response = await _callService('generate-doc-summary', {
        'documentId': documentId,
      });

      // Check if response has error
      if (response.containsKey('error')) {
        final error = response['error'] as Map<String, dynamic>;
        throw Exception('Backend error: ${error['message']}');
      }

      // Get summary from data object
      final data = response['data'] as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Invalid response format: missing data object');
      }

      final summary = data['summary'] as String?;
      if (summary == null) {
        throw Exception('Failed to get summary from response.');
      }
      
      return summary;
    } catch (e) {
      throw Exception('Failed to prepare chat session: $e');
    }
  }

  /// Asks a question about a document that has been prepared for chat
  Future<String> askQuestion(String documentId, String question) async {
    try {
      final response = await _callService('chat-with-document', {
        'documentId': documentId,
        'question': question,
      });
      
      final answer = response['answer'] as String?;
      if (answer == null) {
        throw Exception('Failed to get answer from response.');
      }
      return answer;
      
    } catch (e) {
      throw Exception('Failed to get answer: $e');
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
      await _callService('delete-chat-history', {
        'documentId': documentId,
      });
    } catch (e) {
      throw Exception('Failed to delete chat history: $e');
    }
  }

  
  /// Check if user can upload more files (upload allowance) - DEBUG VERSION
  Future<bool> checkUploadAllowance(String userId) async {
    try {
      final response = await _callService('check-upload-allowance', {
        'userId': userId,
      });
      
      // EXTENSIVE DEBUG LOGGING
      print('🔍 === UPLOAD ALLOWANCE DEBUG ===');
      print('🔍 Raw response: $response');
      print('🔍 Response type: ${response.runtimeType}');
      print('🔍 Response keys: ${response.keys.toList()}');
      
      // Check each possible location for the allow field
      if (response.containsKey('data')) {
        print('📋 Found "data" key');
        final data = response['data'];
        print('📋 data content: $data');
        print('📋 data type: ${data.runtimeType}');
        
        if (data is Map<String, dynamic>) {
          print('📋 data keys: ${data.keys.toList()}');
          if (data.containsKey('allow')) {
            final allowValue = data['allow'];
            print('📋 Found data.allow: $allowValue (type: ${allowValue.runtimeType})');
            return allowValue as bool? ?? false;
          }
          if (data.containsKey('allowed')) {
            final allowedValue = data['allowed'];
            print('📋 Found data.allowed: $allowedValue (type: ${allowedValue.runtimeType})');
            return allowedValue as bool? ?? false;
          }
        }
      }
      
      if (response.containsKey('allow')) {
        final allowValue = response['allow'];
        print('📋 Found direct allow: $allowValue (type: ${allowValue.runtimeType})');
        return allowValue as bool? ?? false;
      }
      
      if (response.containsKey('allowed')) {
        final allowedValue = response['allowed'];
        print('📋 Found direct allowed: $allowedValue (type: ${allowedValue.runtimeType})');
        return allowedValue as bool? ?? false;
      }
      
      print('❌ No allow/allowed field found anywhere!');
      print('🔍 Full response structure: ${response.toString()}');
      
      return false;
             
    } catch (e) {
      print('🚨 Exception in checkUploadAllowance: $e');
      return false;
    }
  }

  /// Create subscription order for Razorpay
  Future<Map<String, dynamic>> createSubscriptionOrder(String userId) async {
    try {
      final response = await _callService('create-subscription-order', {
        'userId': userId,
      });
      
      return response;
    } catch (e) {
      throw Exception('Failed to create subscription order: $e');
    }
  }

  /// Verify payment after successful Razorpay payment
  Future<void> verifyPayment(Map<String, dynamic> paymentData) async {
    try {
      await _callService('verify-payment', paymentData);
    } catch (e) {
      throw Exception('Failed to verify payment: $e');
    }
  }

  Future<String> getDownloadUrl(String documentId) async {
    try {
      final response = await _callService('get-download-url', {
        'documentId': documentId,
      });
      
      // Check if response has error
      if (response.containsKey('error')) {
        final error = response['error'] as Map<String, dynamic>;
        throw Exception('Backend error: ${error['message']}');
      }
      
      // Get URL from result object
      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) {
        throw Exception('Invalid response format: missing result object');
      }
      
      final url = result['url'] as String?;
      if (url == null) {
        throw Exception('Failed to get download URL from response.');
      }
      
      return url;
    } catch (e) {
      throw Exception('Failed to get download URL: $e');
    }
  }

  /// Delete a file and its associated data
  Future<void> deleteFile(String documentId) async {
    try {
      await _callService('delete-file', {
        'documentId': documentId,
      });
    } catch (e) {
      throw Exception('Failed to delete file: $e');
    }
  }
}