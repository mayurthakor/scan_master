// lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../features/home/presentation/pages/home_page.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/email_verification_page.dart';
import '../core/theme/app_theme.dart';
import '../core/di/injection_container.dart';
import 'router/app_router.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final router = getIt<AppRouter>().router;
    
    return MaterialApp.router(
      title: 'Scan Master',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routeInformationProvider: router.routeInformationProvider,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData) {
          final user = snapshot.data!;
          
          // Check if user has verified email (only for email/password users)
          if (user.providerData.any((info) => info.providerId == 'password')) {
            if (!user.emailVerified) {
              return const EmailVerificationPage();
            }
          }
          
          // User is signed in and verified
          return const HomePage();
        }
        
        // User is not signed in
        return const LoginPage();
      },
    );
  }
}