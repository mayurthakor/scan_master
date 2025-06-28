// lib/features/home/presentation/bloc/home_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

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

// BLoC
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc() : super(HomeInitial()) {
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
  
  void _onHomeStarted(HomeStarted event, Emitter<HomeState> emit) {
    emit(HomeLoading());
    // TODO: Load user data and documents
    emit(const HomeLoaded());
  }
  
  void _onUploadFileRequested(UploadFileRequested event, Emitter<HomeState> emit) {
    // TODO: Implement file upload logic
  }
  
  void _onDocumentDeleteRequested(DocumentDeleteRequested event, Emitter<HomeState> emit) {
    // TODO: Implement document deletion
  }
  
  void _onChatPreparationRequested(ChatPreparationRequested event, Emitter<HomeState> emit) {
    emit(ChatPreparationLoading(event.documentId));
    // TODO: Implement chat preparation
  }
  
  void _onSubscriptionOrderRequested(SubscriptionOrderRequested event, Emitter<HomeState> emit) {
    emit(PaymentProcessing());
    // TODO: Implement subscription order creation
  }
  
  void _onPaymentSuccessReceived(PaymentSuccessReceived event, Emitter<HomeState> emit) {
    // TODO: Handle payment success
  }
  
  void _onPaymentErrorReceived(PaymentErrorReceived event, Emitter<HomeState> emit) {
    emit(HomeError('Payment failed: ${event.error}'));
  }
  
  void _onFileUploadProgress(FileUploadProgress event, Emitter<HomeState> emit) {
    // TODO: Handle upload progress
  }
  
  void _onScannedDocumentUpload(ScannedDocumentUpload event, Emitter<HomeState> emit) {
    // TODO: Handle scanned document upload
  }
}