// lib/services/enhanced_api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../config/api_config.dart';

class EnhancedApiService {
  static EnhancedApiService? _instance;
  static EnhancedApiService get instance => _instance ??= EnhancedApiService._();
  
  EnhancedApiService._();
  
  // HTTP client for load balancer requests
  final http.Client _httpClient = http.Client();
  
  // Firebase Functions client for fallback
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: ApiConfig.fallbackRegion,
  );
  
  // 🔐 AUTHENTICATION
  
  /// Get Firebase Auth token for requests
  Future<String> _getAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Failed to get auth token');
    }
    return token;
  }
  
  // 🏥 HEALTH CHECKING
  
  Future<bool> _checkLoadBalancerHealth() async {
    try {
      if (ApiConfig.enableDebugLogs) {
        print('🔍 Checking load balancer health...');
      }
      
      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.loadBalancerBaseUrl}/upload-check'),
        headers: {
          'Content-Type': 'application/json',
          // Don't include Authorization header for health check
        },
      ).timeout(ApiConfig.healthCheckTimeout);
      
      // Load balancer is healthy if it responds (even with 401/500 errors)
      // We just want to confirm the routing and SSL are working
      final isHealthy = response.statusCode >= 200 && response.statusCode < 600;
      
      if (ApiConfig.enableDebugLogs) {
        print('🏥 Load balancer health: ${isHealthy ? "✅ Healthy" : "❌ Unhealthy"} (Status: ${response.statusCode})');
      }
      
      return isHealthy;
    } catch (e) {
      if (ApiConfig.enableDebugLogs) {
        print('🚨 Load balancer health check failed: $e');
      }
      return false;
    }
  }
  
  // 🔄 REQUEST ROUTING
  
  /// Make request with automatic fallback logic
  Future<Map<String, dynamic>> _makeRequest(
    String serviceName,
    Map<String, dynamic> data,
  ) async {
    final shouldUseLB = ApiConfig.shouldUseLoadBalancer(serviceName);
    
    if (ApiConfig.enableDebugLogs) {
      print('📡 Making request to $serviceName (LoadBalancer: $shouldUseLB)');
    }
    
    if (shouldUseLB) {
      try {
        // First check if load balancer is healthy
        final isHealthy = await _checkLoadBalancerHealth();
        if (isHealthy) {
          final result = await _makeLoadBalancerRequest(serviceName, data);
          if (ApiConfig.enableDebugLogs) {
            print('✅ Load balancer request successful for $serviceName');
          }
          return result;
        } else {
          if (ApiConfig.enableDebugLogs) {
            print('⚠️ Load balancer unhealthy, falling back to Firebase Functions');
          }
        }
      } catch (e) {
        if (ApiConfig.enableDebugLogs) {
          print('🚨 Load balancer failed for $serviceName, falling back: $e');
        }
        // Continue to fallback
      }
    }
    
    // Fallback to Firebase Functions
    if (ApiConfig.enableDebugLogs) {
      print('🔄 Using Firebase Functions fallback for $serviceName');
    }
    return await _makeFirebaseFunctionRequest(serviceName, data);
  }
  
  // 🌍 LOAD BALANCER REQUESTS
  
  /// Make HTTP request to load balancer
  Future<Map<String, dynamic>> _makeLoadBalancerRequest(
    String serviceName,
    Map<String, dynamic> data,
  ) async {
    final url = ApiConfig.getLoadBalancerUrl(serviceName);
    
    if (ApiConfig.enableDebugLogs) {
      print('🌍 Load balancer request: $url');
    }
    
    final response = await _httpClient.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await _getAuthToken()}',
      },
      body: jsonEncode({'data': data}),
    ).timeout(ApiConfig.requestTimeout);
    
    if (ApiConfig.enableDebugLogs) {
      print('📨 Load balancer response: ${response.statusCode}');
    }
    
    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      
      // FIX: Handle nested response structure
      // Load balancer returns: {"data": {"allow": true}}
      // Firebase Functions returns: {"allow": true}
      if (result.containsKey('data') && result['data'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(result['data']);
      }
      
      // Fallback for direct response format
      return result['result'] ?? result;
    } else {
      throw HttpException(
        'Load balancer error: ${response.statusCode} - ${response.body}',
        uri: Uri.parse(url),
      );
    }
  }
  
  // 🔥 FIREBASE FUNCTIONS FALLBACK
  
  /// Make request to Firebase Functions (current method)
  Future<Map<String, dynamic>> _makeFirebaseFunctionRequest(
    String serviceName,
    Map<String, dynamic> data,
  ) async {
    if (ApiConfig.enableDebugLogs) {
      print('🔥 Firebase Functions request: $serviceName');
    }
    
    final callable = _functions.httpsCallable(serviceName);
    final response = await callable.call<Map<String, dynamic>>(data);
    
    if (ApiConfig.enableDebugLogs) {
      print('✅ Firebase Functions response received for $serviceName');
    }
    
    return response.data;
  }
  
  // 📋 SERVICE-SPECIFIC METHODS
  
  /// Check if user can upload more files
  Future<Map<String, dynamic>> checkUploadAllowance() async {
    final result = await _makeRequest('check-upload-allowance', {});
    
    // DEBUG: Log the raw response to compare formats
    if (ApiConfig.enableDebugLogs) {
      print('🔍 Raw upload allowance response: $result');
      print('🔍 Response type: ${result.runtimeType}');
      print('🔍 Allow field: ${result['allow']}');
      print('🔍 Allow field type: ${result['allow'].runtimeType}');
    }
    
    return result;
  }
  
  /// Get download URL for a document
  Future<Map<String, dynamic>> getDownloadUrl(String documentId) async {
    return await _makeRequest('get-download-url', {'documentId': documentId});
  }
  
  /// Delete a file and its metadata
  Future<Map<String, dynamic>> deleteFile(String documentId) async {
    return await _makeRequest('delete-file', {'documentId': documentId});
  }
  
  /// Generate document summary for chat preparation
  Future<Map<String, dynamic>> generateDocSummary(String documentId) async {
    final result = await _makeRequest('generate-doc-summary', {'documentId': documentId});
    
    // DEBUG: Log the raw response for chat summary
    if (ApiConfig.enableDebugLogs) {
      print('🔍 Raw generate-doc-summary response: $result');
      print('🔍 Summary field: ${result['summary']}');
    }
    
    return result;
  }
  
  /// Chat with a document
  Future<Map<String, dynamic>> chatWithDocument(
    String documentId,
    String message,
  ) async {
    return await _makeRequest('chat-with-document', {
      'documentId': documentId,
      'question': message, // Note: backend expects 'question', not 'message'
    });
  }
  
  /// Create subscription order with Razorpay
  Future<Map<String, dynamic>> createSubscriptionOrder() async {
    return await _makeRequest('create-subscription-order', {});
  }
  
  /// Verify payment with Razorpay
  Future<Map<String, dynamic>> verifyPayment(String paymentId) async {
    return await _makeRequest('verify-payment', {'paymentId': paymentId});
  }
  
  // 🧹 CLEANUP
  
  /// Dispose resources
  void dispose() {
    _httpClient.close();
  }
}