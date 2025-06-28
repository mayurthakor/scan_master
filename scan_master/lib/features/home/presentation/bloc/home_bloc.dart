// lib/features/home/presentation/bloc/home_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

// Import the repository interface (we'll need to create this)
import '../../domain/repositories/home_repository.dart';

// Events
abstract class HomeEvent extends Equatable {
  const HomeEvent();
  
  @override
  List<Object?> get props => [];
}

class HomeStarted extends HomeEvent {}

class UploadFileRequested extends HomeEvent {}

class DocumentDeleteRequested extends HomeEvent {
  final String documentId;
  
  const DocumentDeleteRequested(this.documentId);
  
  @override
  List<Object> get props => [documentId];
}

class ChatPreparationRequested extends HomeEvent {
  final String documentId;
  
  const ChatPreparationRequested(this.documentId);
  
  @override
  List<Object> get props => [documentId];
}

class SubscriptionOrderRequested extends HomeEvent {}

class PaymentSuccessReceived extends HomeEvent {
  final String orderId;
  final String paymentId;
  final String signature;
  
  const PaymentSuccessReceived({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });
  
  @override
  List<Object> get props => [orderId, paymentId, signature];
}

class PaymentErrorReceived extends HomeEvent {
  final String error;
  
  const PaymentErrorReceived(this.error);
  
  @override
  List<Object> get props => [error];
}

class FileUploadProgress extends HomeEvent {
  final String fileName;
  final double progress;
  
  const FileUploadProgress(this.fileName, this.progress);
  
  @override
  List<Object> get props => [fileName, progress];
}

class ScannedDocumentUpload extends HomeEvent {
  final String imagePath;
  
  const ScannedDocumentUpload(this.imagePath);
  
  @override
  List<Object> get props => [imagePath];
}

// States
abstract class HomeState extends Equatable {
  const HomeState();
  
  @override
  List<Object?> get props => [];
}

class HomeInitial extends HomeState {}

class HomeLoading extends HomeState {}

class HomeLoaded extends HomeState {
  final List<Map<String, dynamic>> documents;
  final UploadTask? uploadTask;
  final Map<String, bool> preparingChat;
  final bool isSubscribed;
  final int uploadCount;
  final int uploadLimit;
  
  const HomeLoaded({
    this.documents = const [],
    this.uploadTask,
    this.preparingChat = const {},
    this.isSubscribed = false,
    this.uploadCount = 0,
    this.uploadLimit = 5,
  });
  
  @override
  List<Object?> get props => [
    documents, 
    uploadTask, 
    preparingChat, 
    isSubscribed,
    uploadCount,
    uploadLimit,
  ];
  
  HomeLoaded copyWith({
    List<Map<String, dynamic>>? documents,
    UploadTask? uploadTask,
    Map<String, bool>? preparingChat,
    bool? isSubscribed,
    int? uploadCount,
    int? uploadLimit,
  }) {
    return HomeLoaded(
      documents: documents ?? this.documents,
      uploadTask: uploadTask ?? this.uploadTask,
      preparingChat: preparingChat ?? this.preparingChat,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      uploadCount: uploadCount ?? this.uploadCount,
      uploadLimit: uploadLimit ?? this.uploadLimit,
    );
  }
}

class HomeError extends HomeState {
  final String message;
  
  const HomeError(this.message);
  
  @override
  List<Object> get props => [message];
}

class ChatPreparationLoading extends HomeState {
  final String documentId;
  
  const ChatPreparationLoading(this.documentId);
  
  @override
  List<Object> get props => [documentId];
}

class PaymentProcessing extends HomeState {}

class UploadLimitReached extends HomeState {}

class DocumentDeleted extends HomeState {
  final String message;
  
  const DocumentDeleted(this.message);
  
  @override
  List<Object> get props => [message];
}

// BLoC
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final HomeRepository _homeRepository;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Constructor now accepts repository through dependency injection
  HomeBloc({
    required HomeRepository homeRepository,
  }) : _homeRepository = homeRepository,
       super(HomeInitial()) {
    on<HomeStarted>(_onHomeStarted);
    on<UploadFileRequested>(_onUploadFileRequested);
    on<DocumentDeleteRequested>(_onDocumentDeleteRequested);
    on<ChatPreparationRequested>(_onChatPreparationRequested);
    on<SubscriptionOrderRequested>(_onSubscriptionOrderRequested);
    on<PaymentSuccessReceived>(_onPaymentSuccessReceived);
    on<PaymentErrorReceived>(_onPaymentErrorReceived);
    on<FileUploadProgress>(_onFileUploadProgress);
    on<ScannedDocumentUpload>(_onScannedDocumentUpload);
  }
  
  void _onHomeStarted(HomeStarted event, Emitter<HomeState> emit) async {
    try {
      emit(HomeLoading());
      
      // Debug: Check auth status
      final user = _auth.currentUser;
      print('🔍 DEBUG - User: ${user?.email}');
      print('🔍 DEBUG - User ID: ${user?.uid}');
      print('🔍 DEBUG - Email verified: ${user?.emailVerified}');
      
      // If no user, show not authenticated state
      if (user == null) {
        print('🔍 DEBUG - No user logged in');
        emit(const HomeError('Not authenticated. Please log in.'));
        return;
      }
      
      print('🔍 DEBUG - Provider: ${user.providerData.first.providerId}');
      
      // Load user data and documents from repository
      final documents = await _homeRepository.getUserDocuments();
      print('🔍 DEBUG - Documents found: ${documents.length}');
      for (var doc in documents) {
        print('🔍 DEBUG - Document: ${doc['name']} (${doc['id']})');
      }
      
      final userStats = await _homeRepository.getUserStats();
      print('🔍 DEBUG - User stats: $userStats');
      
      emit(HomeLoaded(
        documents: documents,
        isSubscribed: userStats['isSubscribed'] ?? false,
        uploadCount: userStats['uploadCount'] ?? 0,
        uploadLimit: userStats['uploadLimit'] ?? 5,
      ));
    } catch (e) {
      print('🔍 DEBUG - Error in _onHomeStarted: $e');
      if (e.toString().contains('User not authenticated')) {
        emit(const HomeError('Not authenticated. Please log in.'));
      } else {
        emit(HomeError('Failed to load home data: ${e.toString()}'));
      }
    }
  }
  
  void _onUploadFileRequested(UploadFileRequested event, Emitter<HomeState> emit) async {
    try {
      final currentState = state;
      if (currentState is! HomeLoaded) return;
      
      // Check upload limit first
      final canUpload = await _homeRepository.checkUploadLimit();
      if (!canUpload) {
        // Don't change the main state, just emit a temporary error
        emit(HomeError('Upload limit reached! Please subscribe for unlimited uploads.'));
        // Then immediately return to the loaded state
        await Future.delayed(const Duration(milliseconds: 100));
        emit(currentState);
        return;
      }
      
      // Pick file using file picker
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
      );
      
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileName = await _homeRepository.generateFileName(result.files.single.name);
        
        // Start upload
        final uploadTask = await _homeRepository.uploadFile(file, fileName);
        
        // Update state with upload task
        emit(currentState.copyWith(uploadTask: uploadTask));
        
        // Listen to upload progress
        uploadTask.snapshotEvents.listen(
          (TaskSnapshot snapshot) {
            final progress = snapshot.bytesTransferred / snapshot.totalBytes;
            add(FileUploadProgress(fileName, progress));
          },
          onError: (error) {
            add(PaymentErrorReceived('Upload failed: $error'));
          },
        );
        
        // Wait for upload completion
        await uploadTask;
        
        // Increment upload count and refresh documents
        await _homeRepository.incrementUploadCount();
        final updatedDocuments = await _homeRepository.getUserDocuments();
        final updatedStats = await _homeRepository.getUserStats();
        
        emit(currentState.copyWith(
          documents: updatedDocuments,
          uploadTask: null,
          uploadCount: updatedStats['uploadCount'] ?? 0,
        ));
        
      }
    } catch (e) {
      emit(HomeError('Upload failed: ${e.toString()}'));
    }
  }
  
  void _onDocumentDeleteRequested(DocumentDeleteRequested event, Emitter<HomeState> emit) async {
    try {
      final currentState = state;
      if (currentState is! HomeLoaded) return;
      
      // Delete the document
      final success = await _homeRepository.deleteDocument(event.documentId);
      
      if (success) {
        // Show success message first
        emit(const DocumentDeleted('Document deleted successfully'));
        
        // Then refresh both documents list AND user stats to update upload count
        final updatedDocuments = await _homeRepository.getUserDocuments();
        final updatedStats = await _homeRepository.getUserStats();
        
        emit(currentState.copyWith(
          documents: updatedDocuments,
          uploadCount: updatedStats['uploadCount'] ?? 0,
          uploadLimit: updatedStats['uploadLimit'] ?? 5,
          isSubscribed: updatedStats['isSubscribed'] ?? false,
        ));
      } else {
        emit(const HomeError('Failed to delete document'));
      }
    } catch (e) {
      emit(HomeError('Failed to delete document: ${e.toString()}'));
    }
  }
  
  void _onChatPreparationRequested(ChatPreparationRequested event, Emitter<HomeState> emit) async {
    try {
      final currentState = state;
      if (currentState is! HomeLoaded) return;
      
      // Update the preparing chat state
      final updatedPreparingChat = Map<String, bool>.from(currentState.preparingChat);
      updatedPreparingChat[event.documentId] = true;
      
      emit(currentState.copyWith(preparingChat: updatedPreparingChat));
      
      // Prepare chat for document
      final success = await _homeRepository.prepareChatForDocument(event.documentId);
      
      // Remove from preparing state
      updatedPreparingChat.remove(event.documentId);
      
      if (success) {
        // Refresh documents to get updated chat status
        final updatedDocuments = await _homeRepository.getUserDocuments();
        emit(currentState.copyWith(
          documents: updatedDocuments,
          preparingChat: updatedPreparingChat,
        ));
      } else {
        emit(currentState.copyWith(preparingChat: updatedPreparingChat));
        emit(const HomeError('Failed to prepare chat'));
      }
    } catch (e) {
      final currentState = state;
      if (currentState is HomeLoaded) {
        final updatedPreparingChat = Map<String, bool>.from(currentState.preparingChat);
        updatedPreparingChat.remove(event.documentId);
        emit(currentState.copyWith(preparingChat: updatedPreparingChat));
      }
      emit(HomeError('Failed to prepare chat: ${e.toString()}'));
    }
  }
  
  void _onSubscriptionOrderRequested(SubscriptionOrderRequested event, Emitter<HomeState> emit) {
    emit(PaymentProcessing());
    // TODO: Implement subscription order creation with repository
  }
  
  void _onPaymentSuccessReceived(PaymentSuccessReceived event, Emitter<HomeState> emit) {
    // TODO: Handle payment success with repository
  }
  
  void _onPaymentErrorReceived(PaymentErrorReceived event, Emitter<HomeState> emit) {
    emit(HomeError('Payment failed: ${event.error}'));
  }
  
  void _onFileUploadProgress(FileUploadProgress event, Emitter<HomeState> emit) {
    final currentState = state;
    if (currentState is HomeLoaded) {
      // For now, we're handling progress in the upload methods themselves
      // This could be used for UI updates if needed
      // You could emit a state with progress information here
    }
  }
  
  void _onScannedDocumentUpload(ScannedDocumentUpload event, Emitter<HomeState> emit) async {
    try {
      final currentState = state;
      if (currentState is! HomeLoaded) return;
      
      // Check upload limit
      final canUpload = await _homeRepository.checkUploadLimit();
      if (!canUpload) {
        emit(UploadLimitReached());
        return;
      }
      
      // Upload scanned document
      final uploadTask = await _homeRepository.uploadScannedDocument(event.imagePath);
      
      // Update state with upload task
      emit(currentState.copyWith(uploadTask: uploadTask));
      
      // Listen to upload progress
      uploadTask.snapshotEvents.listen(
        (TaskSnapshot snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          final fileName = 'scanned_${DateTime.now().millisecondsSinceEpoch}.jpg';
          add(FileUploadProgress(fileName, progress));
        },
        onError: (error) {
          add(PaymentErrorReceived('Scanned upload failed: $error'));
        },
      );
      
      // Wait for completion and refresh
      await uploadTask;
      await _homeRepository.incrementUploadCount();
      
      final updatedDocuments = await _homeRepository.getUserDocuments();
      final updatedStats = await _homeRepository.getUserStats();
      
      emit(currentState.copyWith(
        documents: updatedDocuments,
        uploadTask: null,
        uploadCount: updatedStats['uploadCount'] ?? 0,
      ));
      
    } catch (e) {
      emit(HomeError('Scanned upload failed: ${e.toString()}'));
    }
  }
}