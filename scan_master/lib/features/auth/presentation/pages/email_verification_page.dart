// lib/features/auth/presentation/pages/email_verification_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:async';

import '../../../../core/di/injection_container.dart' as di;
import '../bloc/auth_bloc.dart';

class EmailVerificationPage extends StatelessWidget {
  const EmailVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmailVerificationView();
  }
}

class EmailVerificationView extends StatefulWidget {
  const EmailVerificationView({super.key});

  @override
  State<EmailVerificationView> createState() => _EmailVerificationViewState();
}

class _EmailVerificationViewState extends State<EmailVerificationView> {
  Timer? _checkVerificationTimer;
  bool _canResend = true;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startVerificationCheck();
  }

  @override
  void dispose() {
    _checkVerificationTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startVerificationCheck() {
    // Check verification status every 3 seconds
    _checkVerificationTimer = Timer.periodic(
      const Duration(seconds: 3),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        context.read<AuthBloc>().add(AuthUserReloadRequested());
      },
    );
  }

  void _startResendCountdown() {
    setState(() {
      _canResend = false;
      _resendCountdown = 60;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () {
              context.read<AuthBloc>().add(AuthSignOutRequested());
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is AuthAuthenticated) {
            // Email verified, router will navigate to home
            _checkVerificationTimer?.cancel();
            print('🔍 EMAIL_VERIFICATION - User authenticated: ${state.user.email}');
          } else if (state is AuthUnauthenticated) {
            // Signed out, router will navigate to login
            _checkVerificationTimer?.cancel();
            print('🔍 EMAIL_VERIFICATION - User signed out');
          } else if (state is AuthEmailVerificationSent) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Verification email sent successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            _startResendCountdown();
          }
        },
        builder: (context, state) {
          // Get user email for display
          String userEmail = '';
          if (state is AuthEmailVerificationRequired) {
            userEmail = state.user.email ?? '';
          }

          return Padding(
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
                  userEmail,
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
                    onPressed: () {
                      context.read<AuthBloc>().add(AuthUserReloadRequested());
                    },
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
                    onPressed: _canResend
                        ? () {
                            context.read<AuthBloc>().add(
                              AuthEmailVerificationResendRequested(),
                            );
                          }
                        : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _canResend ? Colors.blue : Colors.grey,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: state is AuthLoading
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
          );
        },
      ),
    );
  }
}