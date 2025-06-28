// lib/features/home/data/repositories/home_repository_impl.dart
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path/path.dart' as path;

import '../../domain/repositories/home_repository.dart';

/// Real implementation of HomeRepository using Firebase
class HomeRepositoryImpl implements HomeRepository {
  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  HomeRepositoryImpl({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _storage = storage ?? FirebaseStorage.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  // Helper to get current user ID
  String get _userId {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  @override
  Future<List<Map<String, dynamic>>> getUserDocuments() async {
    try {
      final snapshot = await _firestore
          .collection('files')  // Use 'files' collection as per your rules
          .where('userId', isEqualTo: _userId)  // Filter by userId field
          .orderBy('uploadedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? data['filename'] ?? 'Unknown',
          'url': data['url'] ?? data['downloadUrl'] ?? '',
          'type': data['type'] ?? data['fileType'] ?? 'unknown',
          'size': data['size'] ?? data['fileSize'] ?? 0,
          'uploadedAt': data['uploadedAt']?.toDate() ?? 
                       data['createdAt']?.toDate() ?? DateTime.now(),
          'thumbnailUrl': data['thumbnailUrl'],
          'status': data['status'] ?? 'completed',
        };
      }).toList();
    } catch (e) {
      throw Exception('Failed to load documents: $e');
    }
  }

  @override
  Future<bool> deleteDocument(String documentId) async {
    try {
      // Get document info first
      final docRef = _firestore.collection('files').doc(documentId);
      
      final doc = await docRef.get();
      if (!doc.exists) return false;
      
      final data = doc.data()!;
      
      // Check if user owns this document
      if (data['userId'] != _userId) {
        throw Exception('Not authorized to delete this document');
      }
      
      final url = data['url'] as String? ?? data['downloadUrl'] as String?;
      
      // Delete from Storage if URL exists
      if (url != null && url.isNotEmpty) {
        try {
          final ref = _storage.refFromURL(url);
          await ref.delete();
        } catch (e) {
          print('Warning: Could not delete file from storage: $e');
        }
      }
      
      // Delete from Firestore
      await docRef.delete();
      
      // Decrement upload count for the user
      try {
        await _firestore
            .collection('users')
            .doc(_userId)
            .update({
          'uploadCount': FieldValue.increment(-1),
        });
      } catch (e) {
        print('Warning: Could not update upload count: $e');
      }
      
      return true;
    } catch (e) {
      throw Exception('Failed to delete document: $e');
    }
  }

  @override
  Future<UploadTask> uploadFile(File file, String fileName) async {
    try {
      final ref = _storage
          .ref()
          .child('documents')
          .child(_userId)
          .child(fileName);
      
      final uploadTask = ref.putFile(file);
      
      // Create document record in Firestore when upload completes
      uploadTask.then((snapshot) async {
        final downloadUrl = await snapshot.ref.getDownloadURL();
        await _saveDocumentMetadata(
          fileName: fileName,
          downloadUrl: downloadUrl,
          fileSize: file.lengthSync(),
          fileType: _getFileType(fileName),
        );
      });
      
      return uploadTask;
    } catch (e) {
      throw Exception('Failed to start upload: $e');
    }
  }

  @override
  Future<UploadTask> uploadScannedDocument(String imagePath) async {
    try {
      final file = File(imagePath);
      final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      return uploadFile(file, fileName);
    } catch (e) {
      throw Exception('Failed to upload scanned document: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getUserStats() async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(_userId)
          .get();
      
      if (!userDoc.exists) {
        // Create user document if it doesn't exist
        await _firestore.collection('users').doc(_userId).set({
          'uploadCount': 0,
          'uploadLimit': 5,
          'isSubscribed': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        return {
          'uploadCount': 0,
          'uploadLimit': 5,
          'isSubscribed': false,
        };
      }
      
      final data = userDoc.data()!;
      return {
        'uploadCount': data['uploadCount'] ?? 0,
        'uploadLimit': data['uploadLimit'] ?? 5,
        'isSubscribed': data['isSubscribed'] ?? false,
      };
    } catch (e) {
      throw Exception('Failed to get user stats: $e');
    }
  }

  @override
  Future<bool> checkUploadLimit() async {
    try {
      final stats = await getUserStats();
      final uploadCount = stats['uploadCount'] as int;
      final uploadLimit = stats['uploadLimit'] as int;
      final isSubscribed = stats['isSubscribed'] as bool;
      
      // Subscribed users have unlimited uploads
      if (isSubscribed) return true;
      
      // Free users have limited uploads
      return uploadCount < uploadLimit;
    } catch (e) {
      throw Exception('Failed to check upload limit: $e');
    }
  }

  @override
  Future<void> incrementUploadCount() async {
    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .update({
        'uploadCount': FieldValue.increment(1),
      });
    } catch (e) {
      throw Exception('Failed to increment upload count: $e');
    }
  }

  @override
  Future<bool> prepareChatForDocument(String documentId) async {
    try {
      // This would typically call your backend service
      // For now, we'll just mark it as prepared
      await _firestore
          .collection('files')  // Use 'files' collection
          .doc(documentId)
          .update({
        'chatPrepared': true,
        'chatPreparedAt': FieldValue.serverTimestamp(),
      });
      
      return true;
    } catch (e) {
      throw Exception('Failed to prepare chat: $e');
    }
  }

  @override
  Future<String> getChatPreparationStatus(String documentId) async {
    try {
      final doc = await _firestore
          .collection('files')  // Use 'files' collection
          .doc(documentId)
          .get();
      
      if (!doc.exists) return 'not_found';
      
      final data = doc.data()!;
      final isPrepared = data['chatPrepared'] ?? false;
      
      return isPrepared ? 'ready' : 'pending';
    } catch (e) {
      return 'error';
    }
  }

  @override
  Future<Map<String, dynamic>> createSubscriptionOrder() async {
    try {
      // This would typically call Razorpay API
      // For now, return mock data
      return {
        'orderId': 'order_${DateTime.now().millisecondsSinceEpoch}',
        'amount': 99900, // ₹999 in paise
        'currency': 'INR',
      };
    } catch (e) {
      throw Exception('Failed to create subscription order: $e');
    }
  }

  @override
  Future<bool> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      // This would typically call your backend to verify payment
      // For now, we'll assume it's successful
      await _firestore
          .collection('users')
          .doc(_userId)
          .update({
        'isSubscribed': true,
        'subscriptionStartedAt': FieldValue.serverTimestamp(),
        'uploadLimit': 999999, // Unlimited for subscribers
      });
      
      return true;
    } catch (e) {
      throw Exception('Failed to verify payment: $e');
    }
  }

  @override
  Future<bool> updateSubscriptionStatus(bool isSubscribed) async {
    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .update({
        'isSubscribed': isSubscribed,
        'uploadLimit': isSubscribed ? 999999 : 5,
      });
      
      return true;
    } catch (e) {
      throw Exception('Failed to update subscription: $e');
    }
  }

  @override
  Future<bool> isUserSubscribed() async {
    try {
      final stats = await getUserStats();
      return stats['isSubscribed'] as bool;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<String> generateFileName(String originalName) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(originalName);
    final nameWithoutExt = path.basenameWithoutExtension(originalName);
    
    return '${nameWithoutExt}_$timestamp$extension';
  }

  @override
  Future<void> updateDocumentMetadata(String documentId, Map<String, dynamic> metadata) async {
    try {
      await _firestore
          .collection('files')  // Use 'files' collection
          .doc(documentId)
          .update(metadata);
    } catch (e) {
      throw Exception('Failed to update document metadata: $e');
    }
  }

  // Helper method to save document metadata after upload
  Future<void> _saveDocumentMetadata({
    required String fileName,
    required String downloadUrl,
    required int fileSize,
    required String fileType,
  }) async {
    try {
      await _firestore
          .collection('files')  // Use 'files' collection
          .add({
        'userId': _userId,
        'name': fileName,
        'filename': fileName,
        'url': downloadUrl,
        'downloadUrl': downloadUrl,
        'type': fileType,
        'fileType': fileType,
        'size': fileSize,
        'fileSize': fileSize,
        'status': 'completed',
        'uploadedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'chatPrepared': false,
      });
    } catch (e) {
      print('Warning: Failed to save document metadata: $e');
    }
  }

  // Helper method to determine file type
  String _getFileType(String fileName) {
    final extension = path.extension(fileName).toLowerCase();
    switch (extension) {
      case '.pdf':
        return 'pdf';
      case '.doc':
      case '.docx':
        return 'document';
      case '.jpg':
      case '.jpeg':
      case '.png':
        return 'image';
      case '.txt':
        return 'text';
      default:
        return 'unknown';
    }
  }
}