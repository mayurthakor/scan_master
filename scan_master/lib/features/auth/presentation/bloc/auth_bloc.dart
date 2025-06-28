// lib/features/auth/presentation/bloc/auth_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:scan_master/core/services/auth_service.dart';

// Events
abstract class AuthEvent extends Equatable {
  const AuthEvent();
  
  @override
  List<Object?> get props => [];
}

class AuthStarted extends AuthEvent {}

class AuthSignInRequested extends AuthEvent {
  final String email;
  final String password;
  
  const AuthSignInRequested({
    required this.email,
    required this.password,
  });
  
  @override
  List<Object> get props => [email, password];
}

class AuthSignUpRequested extends AuthEvent {
  final String email;
  final String password;
  
  const AuthSignUpRequested({
    required this.email,
    required this.password,
  });
  
  @override
  List<Object> get props => [email, password];
}

class AuthGoogleSignInRequested extends AuthEvent {}

class AuthSignOutRequested extends AuthEvent {}

class AuthEmailVerificationRequested extends AuthEvent {}

class AuthEmailVerificationResendRequested extends AuthEvent {}

class AuthUserReloadRequested extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  const AuthState();
  
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final User user;
  
  const AuthAuthenticated(this.user);
  
  @override
  List<Object> get props => [user];
}

class AuthUnauthenticated extends AuthState {}

class AuthEmailVerificationRequired extends AuthState {
  final User user;
  
  const AuthEmailVerificationRequired(this.user);
  
  @override
  List<Object> get props => [user];
}

class AuthSignUpSuccess extends AuthState {
  final User user;
  
  const AuthSignUpSuccess(this.user);
  
  @override
  List<Object> get props => [user];
}

class AuthError extends AuthState {
  final String message;
  
  const AuthError(this.message);
  
  @override
  List<Object> get props => [message];
}

class AuthEmailVerificationSent extends AuthState {}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService;

  AuthBloc({
    required AuthService authService,
  }) : _authService = authService,
       super(AuthInitial()) {
    on<AuthStarted>(_onAuthStarted);
    on<AuthSignInRequested>(_onAuthSignInRequested);
    on<AuthSignUpRequested>(_onAuthSignUpRequested);
    on<AuthGoogleSignInRequested>(_onAuthGoogleSignInRequested);
    on<AuthSignOutRequested>(_onAuthSignOutRequested);
    on<AuthEmailVerificationRequested>(_onAuthEmailVerificationRequested);
    on<AuthEmailVerificationResendRequested>(_onAuthEmailVerificationResendRequested);
    on<AuthUserReloadRequested>(_onAuthUserReloadRequested);
  }
  
  void _onAuthStarted(AuthStarted event, Emitter<AuthState> emit) {
    final user = _authService.currentUser;
    if (user != null) {
      // Check email verification for email/password users
      final isEmailPasswordUser = user.providerData.any((info) => info.providerId == 'password');
      if (isEmailPasswordUser && !user.emailVerified) {
        emit(AuthEmailVerificationRequired(user));
      } else {
        emit(AuthAuthenticated(user));
      }
    } else {
      emit(AuthUnauthenticated());
    }
  }
  
  void _onAuthSignInRequested(AuthSignInRequested event, Emitter<AuthState> emit) async {
    try {
      emit(AuthLoading());
      
      final credential = await _authService.signInWithEmailAndPassword(
        email: event.email,
        password: event.password,
      );
      
      final user = credential.user!;
      
      // Check email verification
      if (!user.emailVerified) {
        emit(AuthEmailVerificationRequired(user));
      } else {
        emit(AuthAuthenticated(user));
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-not-verified') {
        final user = _authService.currentUser;
        if (user != null) {
          emit(AuthEmailVerificationRequired(user));
        } else {
          emit(const AuthError('Please verify your email before signing in.'));
        }
      } else {
        emit(AuthError(e.message ?? 'Sign in failed. Please check your credentials.'));
      }
    } catch (e) {
      emit(AuthError('An unexpected error occurred: ${e.toString()}'));
    }
  }
  
  void _onAuthSignUpRequested(AuthSignUpRequested event, Emitter<AuthState> emit) async {
    try {
      emit(AuthLoading());
      
      final credential = await _authService.createUserWithEmailAndPassword(
        email: event.email,
        password: event.password,
      );
      
      final user = credential.user!;
      
      // Send verification email
      await _authService.sendEmailVerification();
      
      emit(AuthSignUpSuccess(user));
    } on FirebaseAuthException catch (e) {
      emit(AuthError(e.message ?? 'Sign up failed. Please try again.'));
    } catch (e) {
      emit(AuthError('An unexpected error occurred: ${e.toString()}'));
    }
  }
  
  void _onAuthGoogleSignInRequested(AuthGoogleSignInRequested event, Emitter<AuthState> emit) async {
    try {
      emit(AuthLoading());
      
      final credential = await _authService.signInWithGoogle();
      
      if (credential == null) {
        emit(AuthUnauthenticated());
        return;
      }
      
      final user = credential.user!;
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError('Google sign in failed: ${e.toString()}'));
    }
  }
  
  void _onAuthSignOutRequested(AuthSignOutRequested event, Emitter<AuthState> emit) async {
    try {
      await _authService.signOut();
      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthError('Sign out failed: ${e.toString()}'));
    }
  }
  
  void _onAuthEmailVerificationRequested(AuthEmailVerificationRequested event, Emitter<AuthState> emit) async {
    try {
      await _authService.sendEmailVerification();
      emit(AuthEmailVerificationSent());
    } catch (e) {
      emit(AuthError('Failed to send verification email: ${e.toString()}'));
    }
  }
  
  void _onAuthEmailVerificationResendRequested(AuthEmailVerificationResendRequested event, Emitter<AuthState> emit) async {
    try {
      await _authService.resendEmailVerification();
      emit(AuthEmailVerificationSent());
    } catch (e) {
      emit(AuthError('Failed to resend verification email: ${e.toString()}'));
    }
  }
  
  void _onAuthUserReloadRequested(AuthUserReloadRequested event, Emitter<AuthState> emit) async {
    try {
      await _authService.reloadUser();
      final user = _authService.currentUser;
      
      if (user != null && user.emailVerified) {
        emit(AuthAuthenticated(user));
      } else if (user != null) {
        emit(AuthEmailVerificationRequired(user));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthError('Failed to check verification status: ${e.toString()}'));
    }
  }
}