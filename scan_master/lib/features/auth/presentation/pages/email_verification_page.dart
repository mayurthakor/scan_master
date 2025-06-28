import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/services/auth_service.dart';
import 'dart:async';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final AuthService _authService = AuthService();
  bool _isResendLoading = false;
  bool _canResend = true;
  bool _userDeleted = false; // Add this flag
  int _resendCountdown = 0;
  Timer? _timer;
  Timer? _checkVerificationTimer;

  @override
  void initState() {
    super.initState();
    _startVerificationCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _checkVerificationTimer?.cancel();
    super.dispose();
  }

  void _startVerificationCheck() {
    // Check verification status every 3 seconds
    _checkVerificationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        await _authService.reloadUser();
        if (_authService.isEmailVerified) {
          timer.cancel();
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        }
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-deleted') {
          timer.cancel();
          if (mounted) {
            _handleUserDeleted();
          }
        } else {
          print('Error checking verification status: $e');
          // Continue checking for other errors
        }
      } catch (e) {
        print('Error checking verification status: $e');
        // Continue checking even if there's an error
      }
    });
  }

  Future<void> _resendVerification() async {
    if (!_canResend || _isResendLoading || !mounted) return;

    setState(() {
      _isResendLoading = true;
    });

    try {
      await _authService.resendEmailVerification();
      if (mounted) {
        _showSnackBar('Verification email sent successfully!', isError: false);
        
        // Start countdown
        setState(() {
          _canResend = false;
          _resendCountdown = 60;
        });

        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          
          setState(() {
            _resendCountdown--;
          });

          if (_resendCountdown == 0) {
            timer.cancel();
            if (mounted) {
              setState(() {
                _canResend = true;
              });
            }
          }
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'user-deleted') {
          _handleUserDeleted();
        } else {
          _showSnackBar('Failed to send verification email. Please try again.', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to send verification email. Please try again.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResendLoading = false;
        });
      }
    }
  }

  void _handleUserDeleted() {
    setState(() {
      _userDeleted = true;
    });
    
    // Cancel all timers
    _timer?.cancel();
    _checkVerificationTimer?.cancel();
    
    // Navigate to login after showing the message for 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _authService.signOut().then((_) {
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        });
      }
    });
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }

  Future<void> _checkVerificationManually() async {
    if (!mounted) return;
    
    try {
      await _authService.reloadUser();
      if (_authService.isEmailVerified) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        if (mounted) {
          _showSnackBar('Email not verified yet. Please check your email.', isError: true);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'user-deleted') {
          _handleUserDeleted();
        } else {
          _showSnackBar('Error checking verification status. Please try again.', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error checking verification status. Please try again.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    
    // If user was deleted, show a different UI
    if (_userDeleted) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Account Removed'),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 80,
                  color: Colors.red,
                ),
                SizedBox(height: 24),
                Text(
                  'Account Removed',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Your account has been removed from the system. Please create a new account to continue.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                Text(
                  'You will be redirected to the login page shortly...',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () async {
              await _authService.signOut();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.mark_email_unread,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            
            const Text(
              'Verify Your Email',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              'We sent a verification email to:',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            
            Text(
              user?.email ?? '',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            const Text(
              'Please check your email and click the verification link to continue.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            
            // Check Verification Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _checkVerificationManually,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: const Text(
                  'I\'ve Verified My Email',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Resend Email Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _canResend ? _resendVerification : null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _canResend ? Colors.blue : Colors.grey),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: _isResendLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _canResend 
                            ? 'Resend Verification Email'
                            : 'Resend in ${_resendCountdown}s',
                        style: TextStyle(
                          fontSize: 16,
                          color: _canResend ? Colors.blue : Colors.grey,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            
            Text(
              'Didn\'t receive the email? Check your spam folder.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}