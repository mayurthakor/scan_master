import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:scan_master/screens/home_screen.dart';
import 'package:scan_master/screens/login_screen.dart';
import 'package:scan_master/screens/email_verification_screen.dart';
import 'package:scan_master/services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Scan Master',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/email-verification': (context) => const EmailVerificationScreen(),
        '/home': (context) => const UpdatedHomeScreen(),
      },
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
              body: Center(child: CircularProgressIndicator()));
        }
        
        if (snapshot.hasData) {
          final user = snapshot.data!;
          
          // Check if user has verified email (only for email/password users)
          if (user.providerData.any((info) => info.providerId == 'password')) {
            if (!user.emailVerified) {
              return const EmailVerificationScreen();
            }
          }
          
          // User is signed in and verified (or using Google)
          return const UpdatedHomeScreen();
        }
        
        // User is not signed in
        return const LoginScreen();
      },
    );
  }
}