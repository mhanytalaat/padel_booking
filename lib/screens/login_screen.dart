import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'home_screen.dart';
import 'required_profile_update_screen.dart';
import '../services/profile_completion_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum AuthMethod { phone, email, google, apple }

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final phoneNumberController = TextEditingController(); // For signup phone number
  final ageController = TextEditingController();

  String verificationId = "";
  bool otpSent = false;
  bool isLoading = false;
  int? resendToken;
  bool isNewUser = false;
  bool agreedToTerms = false;
  bool isSignUpMode = false; // Toggle between login and signup
  String? selectedGender; // 'male' or 'female' (for signup)
  AuthMethod selectedAuthMethod = AuthMethod.email; // Default to email (phone hidden)

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    passwordController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    phoneNumberController.dispose();
    ageController.dispose();
    super.dispose();
  }

  /// When login/signup succeeds: if this screen was pushed (e.g. from guest Home),
  /// pop with true so the caller can navigate to the requested service; otherwise
  /// replace stack with Home (e.g. when opened as root).
  void _navigateAfterAuth() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  /// Schedules stop-loading, snackbar and navigation for the next frame.
  /// Fixes iOS where native sign-in returns and immediate navigation can be ignored.
  void _scheduleAuthSuccess(String message) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      _navigateAfterAuth();
    });
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // Must start with +2 (Egypt country code)
    if (!value.startsWith('+2')) {
      return 'Phone number must start with +2 (Egypt country code)';
    }
    // Remove +2 and check remaining digits
    final remainingDigits = value.substring(2);
    
    // Must be exactly 11 digits after +2
    if (!RegExp(r'^\d{11}$').hasMatch(remainingDigits)) {
      if (!RegExp(r'^\d+$').hasMatch(remainingDigits)) {
        return 'Phone number must contain only digits after +2';
      } else if (remainingDigits.length < 11) {
        return 'Phone number must be 11 digits after +2 (e.g., +201012345678)';
      } else {
        return 'Phone number must be exactly 11 digits after +2 (e.g., +201012345678)';
      }
    }
    return null;
  }

  String? _validateOTP(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter the OTP code';
    }
    if (value.length < 6) {
      return 'OTP code must be 6 digits';
    }
    return null;
  }

  String? _validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'First name is required';
    }
    if (value.trim().length < 2) {
      return 'First name must be at least 2 characters';
    }
    return null;
  }

  String? _validateLastName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Last name is required';
    }
    if (value.trim().length < 2) {
      return 'Last name must be at least 2 characters';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateAge(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Age is required';
    }
    final age = int.tryParse(value.trim());
    if (age == null) {
      return 'Please enter a valid number';
    }
    if (age < 13) {
      return 'You must be at least 13 years old';
    }
    if (age > 120) {
      return 'Please enter a valid age';
    }
    return null;
  }

  Future<void> sendOTP() async {
    // Check if running on web - Phone Auth requires reCAPTCHA on web
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone authentication is not available on web. Please test on Android device or emulator.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }
    
    // Validate phone number
    if (!_formKey.currentState!.validate()) return;
    
    // For signup, validate all required fields including terms agreement
    if (isSignUpMode) {
      if (firstNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your first name'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (lastNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your last name'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (ageController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your age'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (selectedGender == null || (selectedGender != 'male' && selectedGender != 'female')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select your gender (Male or Female)'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (!agreedToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please agree to the terms and conditions'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }
    // For login, no additional validation needed - just phone number

    setState(() {
      isLoading = true;
    });

    try {
      final phoneNumber = phoneController.text.trim();
      
      // If in signup mode, check if phone number already exists
      if (isSignUpMode) {
        final existingPhoneUser = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: phoneNumber)
            .limit(1)
            .get();
        
        if (existingPhoneUser.docs.isNotEmpty) {
          if (mounted) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This phone number is already registered. Please login instead.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }
      
    await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
          try {
            await _checkAndCreateUserProfile();
          } catch (_) {}
          if (mounted) {
            _scheduleAuthSuccess('Login successful!');
          }
      },
      verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              isLoading = false;
            });
            String errorMessage = 'Verification failed. Please try again.';
            if (e.code == 'invalid-phone-number') {
              errorMessage = 'Invalid phone number. Please check and try again.';
            } else if (e.code == 'too-many-requests') {
              errorMessage = 'Too many requests. Please wait a moment and try again.';
            } else if (e.code == 'quota-exceeded') {
              errorMessage = 'SMS quota exceeded. Please try again later.';
            } else if (e.code == 'app-not-authorized') {
              errorMessage = 'App not authorized. Please contact support.';
            } else if (e.message != null) {
              errorMessage = e.message!;
            }
        ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        },
        codeSent: (String verId, int? token) {
          if (mounted) {
        setState(() {
          verificationId = verId;
          otpSent = true;
              isLoading = false;
              resendToken = token;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('OTP code sent! Please check your phone.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
      },
      codeAutoRetrievalTimeout: (String verId) {
        verificationId = verId;
      },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> verifyOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    try {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
        smsCode: otpController.text.trim(),
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      // Check if this is a new user
      isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      
      // Check if user profile exists in Firestore
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        // If user is trying to login (not signup) but profile doesn't exist
        if (!isNewUser && !isSignUpMode && !userDoc.exists) {
          // Sign out the user
          await FirebaseAuth.instance.signOut();
          
          if (mounted) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your account is not registered. Please sign up first.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }
      
      try {
        await _checkAndCreateUserProfile();
      } catch (_) {}

      if (mounted) {
        _scheduleAuthSuccess(isNewUser
            ? 'Welcome! Account created successfully.'
            : 'Login successful!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid OTP code. Please try again.'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Email/Password Sign Up
  Future<void> signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate signup fields
    if (firstNameController.text.trim().isEmpty ||
        lastNameController.text.trim().isEmpty ||
        phoneNumberController.text.trim().isEmpty ||
        ageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // Validate phone number format
    final phoneValidation = _validatePhone(phoneNumberController.text.trim());
    if (phoneValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(phoneValidation),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (selectedGender == null || (selectedGender != 'male' && selectedGender != 'female')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your gender (Male or Female)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the terms and conditions'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final email = emailController.text.trim();
      final phoneNumber = phoneNumberController.text.trim();
      
      // Create Firebase Auth account first (this will fail if email already exists in Auth)
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: passwordController.text.trim(),
      );

      isNewUser = true;
      try {
        await _checkAndCreateUserProfile();
        
        if (mounted) {
          _scheduleAuthSuccess('Account created successfully! Welcome!');
        }
      } catch (profileError) {
        // If profile creation fails, sign out the user and show error
        debugPrint('═══════════════════════════════════════');
        debugPrint('Profile Creation Error:');
        debugPrint('Error Type: ${profileError.runtimeType}');
        debugPrint('Error: $profileError');
        debugPrint('Stack Trace: ${StackTrace.current}');
        debugPrint('═══════════════════════════════════════');
        
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          setState(() {
            isLoading = false;
          });
          String profileErrorMessage = 'Account created but profile setup failed. Please try again.';
          final errorString = profileError.toString().toLowerCase();
          if (errorString.contains('phone') && (errorString.contains('already') || errorString.contains('registered'))) {
            profileErrorMessage = 'This phone number is already registered. Please login instead.';
          } else if (errorString.contains('email') && (errorString.contains('already') || errorString.contains('registered'))) {
            profileErrorMessage = 'This email is already registered. Please login instead.';
          } else {
            // Show the actual error for debugging
            profileErrorMessage = 'Profile setup failed: ${profileError.toString()}. Please try again.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(profileErrorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        
        // Log the full error for debugging
        debugPrint('═══════════════════════════════════════');
        debugPrint('Signup Error Details:');
        debugPrint('Error Type: ${e.runtimeType}');
        debugPrint('Error: $e');
        if (e is FirebaseAuthException) {
          debugPrint('Error Code: ${e.code}');
          debugPrint('Error Message: ${e.message}');
        }
        debugPrint('Stack Trace: ${StackTrace.current}');
        debugPrint('═══════════════════════════════════════');
        
        String errorMessage = 'Sign up failed. Please try again.';
        if (e is FirebaseAuthException) {
          if (e.code == 'email-already-in-use') {
            errorMessage = 'This email is already registered. Please login instead.';
          } else if (e.code == 'weak-password') {
            errorMessage = 'Password is too weak. Please use a stronger password.';
          } else if (e.code == 'invalid-email') {
            errorMessage = 'Invalid email address. Please enter a valid email.';
          } else if (e.code == 'operation-not-allowed') {
            errorMessage = 'Email/password accounts are not enabled. Please contact support.';
          } else if (e.code == 'network-request-failed') {
            errorMessage = 'Network error. Please check your internet connection and try again.';
          } else {
            // For other Firebase errors, show the error code and message for debugging
            errorMessage = 'Sign up failed (${e.code}): ${e.message ?? 'Unknown error'}. Please try again.';
          }
        } else {
          // For non-Firebase errors, check if it's a duplicate-related error
          final errorString = e.toString().toLowerCase();
          debugPrint('Non-Firebase error string: $errorString');
          if (errorString.contains('email') && errorString.contains('already')) {
            errorMessage = 'This email is already registered. Please login instead.';
          } else if (errorString.contains('phone') && errorString.contains('already')) {
            errorMessage = 'This phone number is already registered. Please login instead.';
          } else {
            // Show the actual error for debugging - truncate if too long
            final errorText = e.toString();
            errorMessage = errorText.length > 100 
                ? 'Sign up failed: ${errorText.substring(0, 100)}... Please check console for details.'
                : 'Sign up failed: $errorText. Please try again.';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Password Reset
  Future<void> resetPassword() async {
    if (!mounted) return;
    
    // Show dialog to enter email
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Password'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your email address and we\'ll send you a link to reset your password.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email address';
                    }
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'your.email@example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }
              
              final email = emailController.text.trim();
              if (email.isEmpty) {
                return;
              }
              
              // Close the input dialog first
              Navigator.pop(dialogContext);
              
              // Show loading dialog
              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (loadingContext) => const AlertDialog(
                  content: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Text('Sending reset link...'),
                    ],
                  ),
                ),
              );
              
              try {
                // Send password reset email with action code settings for mobile
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                  actionCodeSettings: ActionCodeSettings(
                    url: 'https://padelcore-app.firebaseapp.com/__/auth/action',
                    handleCodeInApp: false,
                    androidPackageName: 'com.padelcore.app',
                    iOSBundleId: 'com.padelcore.app',
                  ),
                );
                
                // Close loading dialog
                if (mounted) {
                  Navigator.pop(context);
                  
                  // Show success message with troubleshooting info
                  showDialog(
                    context: context,
                    barrierDismissible: true,
                    builder: (successContext) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 28),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Email Sent'),
                          ),
                        ],
                      ),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'We\'ve sent a password reset link to:\n\n$email',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Please check:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '• Your inbox (wait 1-2 minutes)\n'
                              '• Spam/Junk folder\n'
                              '• Promotions folder (Gmail)',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.info_outline, color: Colors.orange, size: 18),
                                      SizedBox(width: 8),
                                      Text(
                                        'Not receiving emails?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'This may be a Firebase email configuration issue. '
                                    'Check FIX_PASSWORD_RESET_EMAIL.md for setup instructions.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(successContext),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Password reset error: $e');
                
                // Close loading dialog
                if (mounted) {
                  Navigator.pop(context);
                  
                  String errorMessage = 'Failed to send password reset email. Please try again.';
                  if (e is FirebaseAuthException) {
                    if (e.code == 'user-not-found') {
                      errorMessage = 'No account found with this email address. Please sign up first.';
                    } else if (e.code == 'invalid-email') {
                      errorMessage = 'Invalid email address. Please check and try again.';
                    } else if (e.code == 'too-many-requests') {
                      errorMessage = 'Too many requests. Please wait a few minutes before trying again.';
                    } else {
                      errorMessage = 'Error: ${e.message ?? e.code}';
                    }
                  }
                  
                  // Show error dialog instead of snackbar for better visibility on mobile
                  showDialog(
                    context: context,
                    builder: (errorContext) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 28),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('Error'),
                          ),
                        ],
                      ),
                      content: Text(errorMessage),
                      actions: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(errorContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }

  // Email/Password Login
  Future<void> loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    try {
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      isNewUser = false;
      
      // Check and create user profile if it doesn't exist (non-blocking: don't fail login if Firestore errors)
      try {
        await _checkAndCreateUserProfile();
      } catch (profileError) {
        debugPrint('Profile check failed (continuing anyway): $profileError');
        // Still proceed to app; user can update profile later
      }

      if (mounted) {
        _scheduleAuthSuccess('Login successful!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        String errorMessage = 'Login failed. Please try again.';
        if (e is FirebaseAuthException) {
          if (e.code == 'user-not-found') {
            errorMessage = 'No account found with this email. Please sign up first.';
          } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
            errorMessage = 'Wrong password. Please check your password and try again.';
          } else if (e.code == 'invalid-email') {
            errorMessage = 'Invalid email address.';
          } else if (e.code == 'user-disabled') {
            errorMessage = 'This account has been disabled. Please contact support.';
          } else if (e.code == 'too-many-requests') {
            errorMessage = 'Too many failed login attempts. Please try again later.';
          } else if (e.code == 'network-request-failed') {
            errorMessage = 'Network error. Please check your internet connection.';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Google Sign-In
  Future<void> signInWithGoogle() async {
    setState(() {
      isLoading = true;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      // Check if this is a new user
      isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Check for duplicate email if this is a new user
      if (isNewUser && user.email != null) {
        final existingEmailUser = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email)
            .where(FieldPath.documentId, isNotEqualTo: user.uid)
            .limit(1)
            .get();
        
        if (existingEmailUser.docs.isNotEmpty) {
          // Email already exists for another user - sign out and show error
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This email is already registered by another account. Please login instead.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }
      
      // Check if user profile exists in Firestore (for existing Google accounts)
      if (!isNewUser) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        // If user profile doesn't exist, they need to signup
        if (!userDoc.exists) {
          // Sign out the user
          await FirebaseAuth.instance.signOut();
          
          if (mounted) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your account is not registered. Please sign up first.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }
      
      // For Google sign-in, extract name from Google account
      if (isNewUser && googleUser.displayName != null) {
        final nameParts = googleUser.displayName!.split(' ');
        firstNameController.text = nameParts.isNotEmpty ? nameParts[0] : '';
        lastNameController.text = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
        // Age is not available from Google, user can update later
      }
      
      try {
        await _checkAndCreateUserProfile();
      } catch (_) {}
      
      if (mounted) {
        _scheduleAuthSuccess(isNewUser
            ? 'Welcome! Account created successfully.'
            : 'Login successful!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        
        String errorMessage = 'Google sign-in failed. Please try again.';
        
        // Check for specific error codes
        if (e.toString().contains('ApiException: 10') || 
            e.toString().contains('DEVELOPER_ERROR') ||
            e.toString().contains('sign_in_failed')) {
          errorMessage = 'Google sign-in configuration error.\n\n'
              'This usually means the app\'s SHA-1 fingerprint needs to be added to Firebase.\n\n'
              'Please contact support or check FIX_GOOGLE_SIGN_IN_ERROR_10.md for instructions.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  // Sign in with Apple
  Future<void> signInWithApple() async {
    // Check if Sign in with Apple is available (iOS 13+ or macOS 10.15+)
    final isAvailable = await SignInWithApple.isAvailable();
    debugPrint('Apple Sign In Available: $isAvailable');
    
    if (!isAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sign in with Apple is not available on this device.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Log before attempting Apple Sign In
      debugPrint('═══════════════════════════════════════');
      debugPrint('Attempting Apple Sign In...');
      debugPrint('Platform: iOS');
      debugPrint('Bundle ID: com.padelcore.app');
      debugPrint('Scopes: email, fullName');
      debugPrint('═══════════════════════════════════════');
      
      // Request email and name from Apple (only provided on first auth; compliant with App Review)
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      debugPrint('✅ Apple credential obtained successfully');
      debugPrint('User ID: ${appleCredential.userIdentifier}');
      debugPrint('Has identity token: ${appleCredential.identityToken != null}');

      // Verify we have the required token
      if (appleCredential.identityToken == null) {
        throw Exception('Apple Sign In failed: identityToken is null');
      }
      
      debugPrint('Creating Firebase OAuth credential...');
      
      // Create an OAuth credential from the Apple ID credential
      // For Apple Sign In with Firebase, we can pass authorizationCode as accessToken
      // or use null - Firebase documentation shows both approaches work
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode, // Use authorizationCode as accessToken
      );
      
      debugPrint('✅ OAuth credential created');

      // Sign in to Firebase with the OAuth credential
      final userCredential = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      
      // Check if this is a new user
      isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      // Ensure user doc exists in Firestore immediately (Apple users always have a record)
      final initialEmail = user.email ?? appleCredential.email?.trim() ?? '';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'email': initialEmail,
        if (appleCredential.givenName != null && appleCredential.givenName!.trim().isNotEmpty)
          'firstName': appleCredential.givenName!.trim(),
        if (appleCredential.familyName != null && appleCredential.familyName!.trim().isNotEmpty)
          'lastName': appleCredential.familyName!.trim(),
      }, SetOptions(merge: true));
      
      // Check for duplicate email if this is a new user
      if (isNewUser && user.email != null) {
        final existingEmailUser = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email)
            .where(FieldPath.documentId, isNotEqualTo: user.uid)
            .limit(1)
            .get();
        
        if (existingEmailUser.docs.isNotEmpty) {
          // Email already exists for another user - sign out and show error
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This email is already registered by another account. Please login instead.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }
      }
      
      // For Apple sign-in, use name/email from credential (name only on first sign-in)
      if (isNewUser) {
        if (appleCredential.givenName != null || appleCredential.familyName != null) {
          firstNameController.text = appleCredential.givenName ?? '';
          lastNameController.text = appleCredential.familyName ?? '';
        }
      }
      
      // Check and create user profile (will create if doesn't exist); don't fail login if Firestore errors
      try {
        await _checkAndCreateUserProfile();
      } catch (_) {}
      
      // Persist email/name from Apple when we have them (Firebase may not set user.email).
      try {
        final appleUpdates = <String, dynamic>{};
        if (appleCredential.email != null && appleCredential.email!.trim().isNotEmpty) {
          appleUpdates['email'] = appleCredential.email!.trim();
        }
        if (appleCredential.givenName != null && appleCredential.givenName!.trim().isNotEmpty) {
          appleUpdates['firstName'] = appleCredential.givenName!.trim();
        }
        if (appleCredential.familyName != null && appleCredential.familyName!.trim().isNotEmpty) {
          appleUpdates['lastName'] = appleCredential.familyName!.trim();
        }
        if (appleUpdates.isNotEmpty) {
          final first = appleUpdates['firstName'] as String? ?? '';
          final last = appleUpdates['lastName'] as String? ?? '';
          if (first.isNotEmpty || last.isNotEmpty) {
            appleUpdates['fullName'] = '$first $last'.trim();
          }
          appleUpdates['updatedAt'] = FieldValue.serverTimestamp();
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set(appleUpdates, SetOptions(merge: true));
        }
      } catch (_) {}
      
      // Per Apple: do not ask for user info at Sign in with Apple.
      // Profile (phone, name, gender, age) is required only when using a service
      // (booking court, training bundle, joining tournament).

      if (mounted) {
        _scheduleAuthSuccess(isNewUser
            ? 'Welcome! Account created successfully.'
            : 'Login successful!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        String errorMessage = 'Apple sign-in failed. Please try again.';
        if (e is SignInWithAppleAuthorizationException) {
          if (e.code == AuthorizationErrorCode.canceled) {
            // User cancelled - don't show error
            return;
          } else {
            // Log detailed error for debugging
            final errorDetails = '''
═══════════════════════════════════════
Apple Sign In Error Details:
Error Code: ${e.code}
Error Message: ${e.message}
Error Type: ${e.runtimeType}
Full Error: $e
═══════════════════════════════════════
''';
            debugPrint(errorDetails);
            
            // Also show in UI for TestFlight users who can't see console
            final errorSummary = 'Error ${e.code}: ${e.message ?? "Unknown error"}';
            
            // Provide more specific error message for error 1000
            if (e.code == AuthorizationErrorCode.unknown && 
                (e.message?.contains('1000') == true || e.toString().contains('1000'))) {
              errorMessage = 'Apple Sign In error 1000.\n\n'
                  'Verified:\n'
                  '✅ iCloud signed in\n'
                  '✅ 2FA enabled\n'
                  '✅ Configurations correct\n\n'
                  'Possible causes:\n'
                  '• Service ID Return URL mismatch\n'
                  '• Provisioning profile issue\n'
                  '• App entitlements not in release build\n\n'
                  'Error: $errorSummary';
            } else {
              errorMessage = 'Apple sign-in error: $errorSummary';
            }
          }
        } else {
          // Log non-Apple-specific errors
          debugPrint('Sign in with Apple error: $e');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _checkAndCreateUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      // Create profile if it doesn't exist, or update if it's a new user or signup mode
      if (!userDoc.exists || isNewUser || isSignUpMode) {
        if (isSignUpMode || isNewUser) {
          // Signup mode or new user - use the provided information
          final firstName = firstNameController.text.trim();
          final lastName = lastNameController.text.trim();
          final phoneNumber = phoneNumberController.text.trim();
          final email = user.email ?? '';
          final age = int.tryParse(ageController.text.trim()) ?? 0;
          final fullName = firstName.isNotEmpty && lastName.isNotEmpty 
              ? '$firstName $lastName' 
              : (user.displayName ?? user.email?.split('@')[0] ?? 'User');

          // Double-check for duplicates before creating profile
          if (phoneNumber.isNotEmpty) {
            final existingPhoneUser = await FirebaseFirestore.instance
                .collection('users')
                .where('phone', isEqualTo: phoneNumber)
                .where(FieldPath.documentId, isNotEqualTo: user.uid)
                .limit(1)
                .get();
            
            if (existingPhoneUser.docs.isNotEmpty) {
              // Phone already exists for another user - sign out and show error
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This phone number is already registered by another account.'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 4),
                  ),
                );
              }
              return;
            }
          }

          if (email.isNotEmpty) {
            final existingEmailUser = await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: email)
                .where(FieldPath.documentId, isNotEqualTo: user.uid)
                .limit(1)
                .get();
            
            if (existingEmailUser.docs.isNotEmpty) {
              // Email already exists for another user - sign out and show error
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('This email is already registered by another account.'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 4),
                  ),
                );
              }
              return;
            }
          }

          final profileData = <String, dynamic>{
            'phone': phoneNumber.isNotEmpty ? phoneNumber : (user.phoneNumber ?? ''),
            'email': email,
            'firstName': firstName.isNotEmpty ? firstName : (user.displayName != null && user.displayName!.split(' ').isNotEmpty ? user.displayName!.split(' ').first : ''),
            'lastName': lastName.isNotEmpty ? lastName : (user.displayName != null && user.displayName!.split(' ').length > 1 ? user.displayName!.split(' ').sublist(1).join(' ') : ''),
            'fullName': fullName,
            'age': age,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (selectedGender == 'male' || selectedGender == 'female') {
            profileData['gender'] = selectedGender;
          }
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set(profileData, SetOptions(merge: true));
        } else {
          // Login mode - create basic profile if it doesn't exist, or update existing
          if (!userDoc.exists) {
            // Profile doesn't exist - create a basic one with email/phone
            final emailName = user.email?.split('@')[0] ?? 'User';
            final displayName = user.displayName;
            final nameParts = displayName != null ? displayName.split(' ') : <String>[];
            final firstName = nameParts.isNotEmpty ? nameParts.first : emailName;
            final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
            
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
              'phone': user.phoneNumber ?? '',
              'email': user.email ?? '',
              'firstName': firstName,
              'lastName': lastName,
              'fullName': displayName ?? emailName,
              'age': 0, // Will need to be updated later
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            // Profile exists - just update phone/email if needed
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .set({
              'phone': user.phoneNumber ?? '',
              'email': user.email ?? '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }
    } catch (e) {
      // Re-throw the error so it can be handled by the caller
      debugPrint('Error in _checkAndCreateUserProfile: $e');
      rethrow;
    }
  }

  Future<void> _showPhoneNumberDialog() async {
    final dialogPhoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Phone Number Required'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Please provide your phone number to complete your profile. This is required for booking confirmations.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: dialogPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+201012345678 (11 digits after +2)',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: _validatePhone,
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }
              
              final phoneNumber = dialogPhoneController.text.trim();
              final user = FirebaseAuth.instance.currentUser;
              
              if (user != null && phoneNumber.isNotEmpty) {
                try {
                  // Check for duplicate phone number
                  final existingPhoneUser = await FirebaseFirestore.instance
                      .collection('users')
                      .where('phone', isEqualTo: phoneNumber)
                      .where(FieldPath.documentId, isNotEqualTo: user.uid)
                      .limit(1)
                      .get();
                  
                  if (existingPhoneUser.docs.isNotEmpty) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('This phone number is already registered by another account.'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                    return;
                  }
                  
                  // Update user profile with phone number
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .update({
                    'phone': phoneNumber,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Phone number saved successfully!'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving phone number: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> resendOTP() async {
    if (phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your phone number first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneController.text.trim(),
        forceResendingToken: resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
    await FirebaseAuth.instance.signInWithCredential(credential);
          try {
            await _checkAndCreateUserProfile();
          } catch (_) {}
          if (mounted) {
            _scheduleAuthSuccess('Login successful!');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.message ?? 'Failed to resend OTP'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        codeSent: (String verId, int? token) {
          if (mounted) {
            setState(() {
              verificationId = verId;
              resendToken = token;
              isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('OTP code resent!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verId) {
          verificationId = verId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _resetForm() {
    setState(() {
      otpSent = false;
      otpController.clear();
      verificationId = "";
      resendToken = null;
    });
  }

  Widget _buildAuthMethodButton(AuthMethod method, IconData icon, String label) {
    final isSelected = selectedAuthMethod == method;
    return GestureDetector(
      onTap: isLoading ? null : () {
        setState(() {
          selectedAuthMethod = method;
          // Reset OTP state when switching methods
          if (method != AuthMethod.phone) {
            otpSent = false;
            otpController.clear();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A8A) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTermsAndConditions() async {
    final url = Uri.parse(
      'https://1drv.ms/b/c/087e33f99fc23140/IQC--FE1rga5Qa5s-HLmLOAvAcSRm01OwSKAziTbXNTdYew?e=eSPGjV',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Terms and Conditions'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final url = Uri.parse(
      'https://1drv.ms/b/c/087e33f99fc23140/IQCKIjXCYM2vSYuUW3ouxDVOAZ51bAetIcxGdV9BiUiv-z0?e=hseaQY',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Privacy Policy'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                const SizedBox(height: 40),
                // Logo
                Image.asset(
                  'assets/images/logo.png',
                  height: 80,
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  otpSent 
                      ? 'Verify OTP' 
                      : (isSignUpMode ? 'Create Account' : 'Welcome Back'),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  otpSent 
                      ? 'Enter the 6-digit code sent to ${phoneController.text}'
                      : (isSignUpMode 
                          ? 'Sign up to book your padel court' 
                          : 'Login to continue booking'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                
                // Toggle between Login and Signup
                if (!otpSent) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: isLoading ? null : () {
                          setState(() {
                            isSignUpMode = false;
                            // Clear signup fields when switching to login
                            firstNameController.clear();
                            lastNameController.clear();
                            phoneNumberController.clear();
                            ageController.clear();
                            agreedToTerms = false;
                            selectedGender = null;
                          });
                        },
                        child: Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSignUpMode ? FontWeight.normal : FontWeight.bold,
                            color: isSignUpMode ? Colors.grey : const Color(0xFF1E3A8A),
                            decoration: isSignUpMode ? null : TextDecoration.underline,
                          ),
                        ),
                      ),
                      Text(
                        ' | ',
                        style: TextStyle(color: Colors.grey[400], fontSize: 16),
                      ),
                      TextButton(
                        onPressed: isLoading ? null : () {
                          setState(() {
                            isSignUpMode = true;
                          });
                        },
                        child: Text(
                          'Sign Up',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSignUpMode ? FontWeight.bold : FontWeight.normal,
                            color: isSignUpMode ? const Color(0xFF1E3A8A) : Colors.grey,
                            decoration: isSignUpMode ? TextDecoration.underline : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Authentication Method Selector
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
          children: [
                        // Phone login hidden for now (keeping code for future use)
                        // Expanded(
                        //   child: _buildAuthMethodButton(
                        //     AuthMethod.phone,
                        //     Icons.phone,
                        //     'Phone',
                        //   ),
                        // ),
                        // const SizedBox(width: 8),
                        Expanded(
                          child: _buildAuthMethodButton(
                            AuthMethod.email,
                            Icons.email,
                            'Email',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAuthMethodButton(
                            AuthMethod.google,
                            Icons.g_mobiledata,
                            'Google',
                          ),
                        ),
                        if (!kIsWeb && Platform.isIOS) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildAuthMethodButton(
                              AuthMethod.apple,
                              Icons.phone_iphone,
                              'Apple',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                
                // Phone Number Field (only for phone auth)
                if (!otpSent && selectedAuthMethod == AuthMethod.phone) ...[
                  TextFormField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number *',
                      hintText: '+201012345678 (11 digits after +2)',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: _validatePhone,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                ],
                
                // Email and Password Fields (only for email auth)
                if (!otpSent && selectedAuthMethod == AuthMethod.email) ...[
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email *',
                      hintText: 'your.email@example.com',
                      prefixIcon: const Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: _validateEmail,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      hintText: 'Enter your password',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: _validatePassword,
                    enabled: !isLoading,
                  ),
                  // Forgot Password link (only shown in login mode)
                  if (!isSignUpMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isLoading ? null : resetPassword,
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                
                // Signup fields (only shown in signup mode for phone and email)
                if (!otpSent && isSignUpMode && selectedAuthMethod != AuthMethod.google) ...[
                    // First Name Field (Mandatory for signup)
                    TextFormField(
                      controller: firstNameController,
                      decoration: InputDecoration(
                        labelText: 'First Name *',
                        hintText: 'Enter your first name',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: isSignUpMode ? _validateFirstName : null,
                      enabled: !isLoading,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // Last Name Field (Mandatory for signup)
                    TextFormField(
                      controller: lastNameController,
                      decoration: InputDecoration(
                        labelText: 'Last Name *',
                        hintText: 'Enter your last name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: isSignUpMode ? _validateLastName : null,
                      enabled: !isLoading,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    
                    // Phone Number Field (Mandatory for signup, before age)
                    TextFormField(
                      controller: phoneNumberController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number *',
                        hintText: '+201012345678 (11 digits after +2)',
                        prefixIcon: const Icon(Icons.phone),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: isSignUpMode ? _validatePhone : null,
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 16),
                    
                    // Age Field (Mandatory for signup)
                    TextFormField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Age *',
                        hintText: 'Enter your age',
                        prefixIcon: const Icon(Icons.calendar_today),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: isSignUpMode ? _validateAge : null,
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 16),
                    // Gender (Mandatory for signup)
                    const Text(
                      'Gender *',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<String?>(
                            segments: const [
                              ButtonSegment(value: 'male', label: Text('Male'), icon: Icon(Icons.male)),
                              ButtonSegment(value: 'female', label: Text('Female'), icon: Icon(Icons.female)),
                            ],
                            selected: selectedGender != null ? {selectedGender} : {},
                            emptySelectionAllowed: true,
                            onSelectionChanged: isLoading
                                ? null
                                : (Set<String?> newSelection) {
                                    setState(() {
                                      selectedGender = newSelection.isEmpty ? null : newSelection.first;
                                    });
                                  },
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Terms and Conditions Agreement (only for signup)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: agreedToTerms,
                          onChanged: isLoading
                              ? null
                              : (value) {
                                  setState(() {
                                    agreedToTerms = value ?? false;
                                  });
                                },
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[800],
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'I agree to the ',
                                  ),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: isLoading ? null : _openTermsAndConditions,
                                      child: Text(
                                        'Terms and Conditions',
                                        style: TextStyle(
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Colors.blue[700],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const TextSpan(
                                    text: ' and ',
                                  ),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: isLoading ? null : _openPrivacyPolicy,
                                      child: Text(
                                        'Privacy Policy',
                                        style: TextStyle(
                                          color: Colors.blue[700],
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Colors.blue[700],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const TextSpan(
                                    text: ' *',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Helper text
                    Padding(
                      padding: const EdgeInsets.only(left: 48),
                      child: Text(
                        'Tap the links above to read the full documents',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                
                // OTP Field (only for phone auth when OTP is sent)
                if (otpSent && selectedAuthMethod == AuthMethod.phone) ...[
                  TextFormField(
                controller: otpController,
                keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'OTP Code',
                      hintText: '000000',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: _validateOTP,
                    enabled: !isLoading,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Resend OTP
                  TextButton(
                    onPressed: isLoading ? null : resendOTP,
                    child: const Text('Resend OTP'),
                  ),
                  
                  // Change Phone Number
                  TextButton(
                    onPressed: isLoading ? null : _resetForm,
                    child: const Text('Change Phone Number'),
                  ),
                ],
                
                const SizedBox(height: 32),
                
                // Google Sign-In Button (only when Google is selected)
                if (!otpSent && selectedAuthMethod == AuthMethod.google) ...[
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : signInWithGoogle,
                    icon: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : Image.asset(
                            'assets/images/google_logo.png',
                            height: 20,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata),
                          ),
                    label: Text(
                      isLoading ? 'Signing in...' : 'Continue with Google',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Info for Google sign-in
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sign in with your Google account. Your name and email will be used to create your profile.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] 
                // Sign in with Apple Button (only when Apple is selected and on iOS)
                else if (!otpSent && selectedAuthMethod == AuthMethod.apple && !kIsWeb && Platform.isIOS) ...[
                  SignInWithAppleButton(
                    onPressed: isLoading ? () {} : () {
                      signInWithApple();
                    },
                    height: 50,
                    text: isLoading ? 'Signing in...' : 'Continue with Apple',
                    style: SignInWithAppleButtonStyle.black,
                  ),
                  const SizedBox(height: 16),
                  // Info for Apple sign-in
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sign in with Apple protects your privacy. You can choose to hide your email address.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Submit Button (for Phone and Email)
            ElevatedButton(
                    onPressed: isLoading 
                        ? null 
                        : () {
                            if (selectedAuthMethod == AuthMethod.phone) {
                              if (otpSent) {
                                verifyOTP();
                              } else {
                                sendOTP();
                              }
                            } else if (selectedAuthMethod == AuthMethod.email) {
                              if (isSignUpMode) {
                                signUpWithEmail();
                              } else {
                                loginWithEmail();
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : Text(
                            selectedAuthMethod == AuthMethod.phone
                                ? (otpSent 
                                    ? 'Verify & ${isSignUpMode ? "Sign Up" : "Login"}' 
                                    : (isSignUpMode ? 'Send OTP & Sign Up' : 'Send OTP & Login'))
                                : (isSignUpMode ? 'Sign Up' : 'Login'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Info Text (only for Phone and Email)
                  if (selectedAuthMethod == AuthMethod.phone || selectedAuthMethod == AuthMethod.email)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedAuthMethod == AuthMethod.phone
                                  ? (otpSent
                                      ? 'Enter the 6-digit verification code sent to your phone via SMS.'
                                      : 'We\'ll send you a verification code via SMS. Make sure your phone number includes the country code (e.g., +20 for Egypt).')
                                  : 'Use your email and password to sign in or create a new account.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                ],
                
                // Sign in with Apple button (ALWAYS visible on iOS, as required by Apple guidelines)
                if (!otpSent && !kIsWeb && Platform.isIOS && selectedAuthMethod != AuthMethod.apple) ...[
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SignInWithAppleButton(
                    onPressed: isLoading ? () {} : () {
                      signInWithApple();
                    },
                    height: 50,
                    text: isLoading ? 'Signing in...' : 'Continue with Apple',
                    style: SignInWithAppleButtonStyle.black,
                  ),
                  const SizedBox(height: 16),
                  // Info for Apple sign-in
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sign in with Apple protects your privacy. You can choose to hide your email address.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[900],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
