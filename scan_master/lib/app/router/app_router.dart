// lib/app/router/app_router.dart
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/email_verification_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/camera/presentation/pages/camera_page.dart';
import '../../features/document_preview/presentation/pages/document_preview_page.dart';

class AppRouter {
  static const String login = '/login';
  static const String emailVerification = '/email-verification';
  static const String home = '/home';
  static const String camera = '/camera';
  static const String documentPreview = '/document-preview';

  GoRouter get router => _router;

  late final GoRouter _router = GoRouter(
    initialLocation: '/login',
    redirect: _authGuard,
    refreshListenable: AuthStateNotifier(), // Add this line
    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/email-verification',
        name: 'email-verification',
        builder: (context, state) => const EmailVerificationPage(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/camera',
        name: 'camera',
        builder: (context, state) {
          final onImageCaptured = state.extra as Function(String)?;
          return CameraPage(
            onImageCaptured: onImageCaptured ?? (path) {},
          );
        },
      ),
      GoRoute(
        path: '/document-preview',
        name: 'document-preview',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;
          return DocumentPreviewPage(
            imagePath: args?['imagePath'] ?? '',
            onDocumentProcessed: args?['onDocumentProcessed'] ?? (path) {},
          );
        },
      ),
    ],
  );

  // Auth guard - handles authentication redirects
  static String? _authGuard(BuildContext context, GoRouterState state) {
    final user = FirebaseAuth.instance.currentUser;
    final isOnLoginPage = state.matchedLocation == '/login';
    final isOnEmailVerificationPage = state.matchedLocation == '/email-verification';

    // If user is not signed in and not on login page, redirect to login
    if (user == null && !isOnLoginPage) {
      return '/login';
    }

    // If user is signed in but email not verified (for email/password users)
    if (user != null && 
        user.providerData.any((info) => info.providerId == 'password') &&
        !user.emailVerified &&
        !isOnEmailVerificationPage) {
      return '/email-verification';
    }

    // If user is signed in and verified but on login/verification page, redirect to home
    if (user != null && 
        (user.emailVerified || !user.providerData.any((info) => info.providerId == 'password')) &&
        (isOnLoginPage || isOnEmailVerificationPage)) {
      return '/home';
    }

    // No redirect needed
    return null;
  }
}

// Auth state notifier to listen to Firebase Auth changes
class AuthStateNotifier extends ChangeNotifier {
  AuthStateNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
}