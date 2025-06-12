
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:scan_master/screens/home_screen.dart'; // Import your HomeScreen
import 'package:scan_master/screens/login_screen.dart'; // Make sure this import is here

Future<void> main() async {
  // Ensure that all the widgets are ready before Firebase starts.
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase using the auto-generated options file.
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
      home: const AuthGate(), // Use AuthGate to manage authentication state
      // The AuthGate widget will handle showing either the HomeScreen or LoginScreen
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder listens to a stream and rebuilds the UI
    // every time new data arrives.
    return StreamBuilder<User?>(
      // This is the authentication state stream from Firebase.
      // It emits a User object if logged in, or null if logged out.
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        
        // While waiting for the first auth event, show a loading spinner.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // If the snapshot has data (i.e., a User object),
        // it means the user is logged in.
        if (snapshot.hasData) {
          // Show the HomeScreen.
          return const HomeScreen();
        }

        // Otherwise, the user is logged out.
        // Show the LoginScreen.
        return const LoginScreen();
      },
    );
  }
}