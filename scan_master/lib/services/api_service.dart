// lib/services/api_service.dart

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ApiService {
  // --- THIS LINE IS NOW CORRECTED ---
  // We must specify the region to match where our functions are deployed.
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> prepareChatSession(String documentId) async {
    try {
      final callable = _functions.httpsCallable('prepare-chat-session');
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
    }
  }
}