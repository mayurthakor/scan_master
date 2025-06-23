// lib/config/api_config.dart
import 'package:flutter/foundation.dart';

class ApiConfig {
  // 🎛️ FEATURE FLAGS - Control migration rollout
  
  // Master switch for load balancer usage
  static const bool useLoadBalancer = true; // RE-ENABLE to compare responses
  
  // Individual service flags (for granular control)
  static const Map<String, bool> serviceFlags = {
    'check-upload-allowance': true,  // ✅ MIGRATED SUCCESSFULLY
    'get-download-url': false,       // 🚨 BACKEND ISSUE - Service account signing
    'delete-file': true,             // ✅ MIGRATED SUCCESSFULLY  
    'generate-doc-summary': false,   // 🚨 BACKEND ISSUE - Missing GEMINI_API_KEY
    'chat-with-document': false,     // 🚨 BACKEND ISSUE - Missing GEMINI_API_KEY  
    'create-subscription-order': true, // 🆕 TRY PAYMENT SERVICE (no AI required)
    'verify-payment': false,
  };
  
  // 🌍 ENDPOINT CONFIGURATION
  
  // Load balancer endpoints
  static const String loadBalancerBaseUrl = 'https://api.scanmaster.cc';
  
  // Fallback to current Firebase Functions
  static const String fallbackRegion = 'us-central1';
  
  // Service endpoint mapping (Firebase Function Name → Load Balancer Path)
  static const Map<String, String> serviceEndpoints = {
    'check-upload-allowance': '/upload-check',
    'get-download-url': '/download',
    'delete-file': '/delete',
    'generate-doc-summary': '/summary',
    'chat-with-document': '/chat',
    'create-subscription-order': '/subscribe',
    'verify-payment': '/verify-payment',
  };
  
  // 🔧 CONFIGURATION HELPERS
  
  /// Check if a specific service should use load balancer
  static bool shouldUseLoadBalancer(String serviceName) {
    if (!useLoadBalancer) return false;
    return serviceFlags[serviceName] ?? false;
  }
  
  /// Get load balancer URL for a service
  static String getLoadBalancerUrl(String serviceName) {
    final endpoint = serviceEndpoints[serviceName];
    if (endpoint == null) {
      throw Exception('Unknown service: $serviceName');
    }
    return '$loadBalancerBaseUrl$endpoint';
  }
  
  // 📊 MONITORING & DEBUGGING
  
  /// Enable debug logging in development
  static bool get enableDebugLogs => kDebugMode;
  
  /// Request timeout configuration
  static const Duration requestTimeout = Duration(seconds: 30);
  
  /// Health check timeout (shorter for faster fallback)
  static const Duration healthCheckTimeout = Duration(seconds: 5);
  
  // 🔄 ROLLOUT HELPERS (for future use)
  
  /// Get rollout percentage for gradual deployment
  static int getRolloutPercentage(String serviceName) {
    // Future: implement gradual rollout based on user ID hash
    return shouldUseLoadBalancer(serviceName) ? 100 : 0;
  }
  
  /// Check if current user should get load balancer (for A/B testing)
  static bool shouldUserGetLoadBalancer(String serviceName, String? userId) {
    if (!shouldUseLoadBalancer(serviceName)) return false;
    if (userId == null) return false;
    
    // For now, all users get the same treatment
    // Future: implement user-based rollout
    return true;
  }
}