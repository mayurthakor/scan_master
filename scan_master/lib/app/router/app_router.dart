// lib/app/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injection_container.dart' as di;
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/email_verification_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';

// Router configuration
final appRouter = GoRouter(
  initialLocation: '/auth',
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuthRoute = state.matchedLocation.startsWith('/auth') || 
                       state.matchedLocation == '/login' ||
                       state.matchedLocation == '/email-verification';
    
    // Debug auth state
    print('🔍 ROUTER - User: ${user?.email}');
    print('🔍 ROUTER - Current route: ${state.matchedLocation}');
    print('🔍 ROUTER - Is auth route: $isAuthRoute');
    
    if (user == null) {
      // No user, redirect to login unless already on auth route
      if (!isAuthRoute) {
        print('🔍 ROUTER - Redirecting to /login');
        return '/login';
      }
      return null; // Stay on current auth route
    }
    
    // User exists, check email verification for email/password users
    final isEmailPasswordUser = user.providerData.any((info) => info.providerId == 'password');
    
    if (isEmailPasswordUser && !user.emailVerified) {
      // Email not verified, redirect to verification unless already there
      if (state.matchedLocation != '/email-verification') {
        print('🔍 ROUTER - Redirecting to /email-verification');
        return '/email-verification';
      }
      return null;
    }
    
    // User is authenticated and verified, redirect to home unless already there
    if (isAuthRoute || state.matchedLocation == '/') {
      print('🔍 ROUTER - Redirecting to /home');
      return '/home';
    }
    
    return null; // Stay on current route
  },
  routes: [
    // Auth routes
    GoRoute(
      path: '/auth',
      redirect: (context, state) => '/login',
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => BlocProvider(
        create: (context) => di.sl<AuthBloc>(),
        child: const LoginPage(),
      ),
    ),
    GoRoute(
      path: '/email-verification',
      builder: (context, state) => BlocProvider(
        create: (context) => di.sl<AuthBloc>(),
        child: const EmailVerificationPage(),
      ),
    ),
    
    // App routes
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomePage(),
    ),
  ],
);