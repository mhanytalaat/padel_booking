import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'home_screen.dart';

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

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your phone number';
    }
    // Basic validation - should start with + and have digits
    if (!value.startsWith('+')) {
      return 'Phone number must start with country code (e.g., +20 for Egypt)';
    }
    // Remove + and check if remaining are all digits
    final digits = value.substring(1);
    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
      return 'Phone number must contain only digits after the country code';
    }
    // Check length - E.164 format: +[country code][number], typically 10-15 digits total
    if (value.length < 10 || value.length > 16) {
      return 'Phone number is too short or too long. Example: +201012345678';
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
    await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneController.text.trim(),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
          await _checkAndCreateUserProfile();
          if (mounted) {
            setState(() {
              isLoading = false;
            });
          }
      },
      verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() {
              isLoading = false;
            });
        ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.message ?? 'Verification failed. Please try again.'),
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
      
      await _checkAndCreateUserProfile();
      
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNewUser 
                ? 'Welcome! Account created successfully.' 
                : 'Login successful!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
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
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      isNewUser = true;
      await _checkAndCreateUserProfile();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        String errorMessage = 'Sign up failed. Please try again.';
        if (e is FirebaseAuthException) {
          if (e.code == 'email-already-in-use') {
            errorMessage = 'This email is already registered. Please login instead.';
          } else if (e.code == 'weak-password') {
            errorMessage = 'Password is too weak. Please use a stronger password.';
          } else if (e.code == 'invalid-email') {
            errorMessage = 'Invalid email address.';
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

  // Password Reset
  Future<void> resetPassword() async {
    // Show dialog to enter email
    final emailController = TextEditingController();
    
    if (!context.mounted) return;
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your email address and we\'ll send you a link to reset your password.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'your.email@example.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter your email address'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return;
              }
              
              // Validate email format
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(email)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid email address'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return;
              }
              
              if (!context.mounted) return;
              Navigator.pop(context);
              
              // Show loading
              if (context.mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                
                if (context.mounted) {
                  Navigator.pop(context); // Close loading dialog
                  
                  // Show success message
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Password Reset Email Sent'),
                      content: Text(
                        'We\'ve sent a password reset link to $email. '
                        'Please check your email and follow the instructions to reset your password.',
                      ),
                      actions: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context); // Close loading dialog
                  
                  String errorMessage = 'Failed to send password reset email. Please try again.';
                  if (e is FirebaseAuthException) {
                    if (e.code == 'user-not-found') {
                      errorMessage = 'No account found with this email address. Please sign up first.';
                    } else if (e.code == 'invalid-email') {
                      errorMessage = 'Invalid email address. Please check and try again.';
                    } else {
                      errorMessage = 'Error: ${e.message}';
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
      
      // Check and create user profile if it doesn't exist
      // This handles cases where user reset password or profile wasn't created before
      await _checkAndCreateUserProfile();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login successful!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
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
          } else if (e.code == 'wrong-password') {
            errorMessage = 'Incorrect password. Please try again.';
          } else if (e.code == 'invalid-email') {
            errorMessage = 'Invalid email address.';
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
      
      // Check if user profile exists in Firestore (for existing Google accounts)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !isNewUser) {
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
      
      await _checkAndCreateUserProfile();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNewUser 
                ? 'Welcome! Account created successfully.' 
                : 'Login successful!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Sign in with Apple
  Future<void> signInWithApple() async {
    // Check if Sign in with Apple is available (iOS 13+ or macOS 10.15+)
    if (!await SignInWithApple.isAvailable()) {
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
      // Try with email and fullName scopes first
      // If this fails with error 1000, it's usually a configuration issue
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Create an OAuth credential from the Apple ID credential
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      // Sign in to Firebase with the OAuth credential
      final userCredential = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      
      // Check if this is a new user
      isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      
      // Check if user profile exists in Firestore (for existing Apple accounts)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !isNewUser) {
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
      
      // For Apple sign-in, extract name from Apple credential (only available on first sign-in)
      if (isNewUser) {
        if (appleCredential.givenName != null || appleCredential.familyName != null) {
          firstNameController.text = appleCredential.givenName ?? '';
          lastNameController.text = appleCredential.familyName ?? '';
        }
        // Note: Apple only provides name on first sign-in. Subsequent sign-ins won't have this info.
        // Age is not available from Apple, user can update later
      }
      
      await _checkAndCreateUserProfile();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNewUser 
                ? 'Welcome! Account created successfully.' 
                : 'Login successful!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
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
            debugPrint('Apple Sign In Error Code: ${e.code}');
            debugPrint('Apple Sign In Error Message: ${e.message}');
            debugPrint('Apple Sign In Error Details: $e');
            
            // Provide more specific error message for error 1000
            if (e.code == AuthorizationErrorCode.unknown && 
                e.message?.contains('1000') == true) {
              errorMessage = 'Apple Sign In configuration error (1000). '
                  'Please verify: Bundle ID matches, capability is enabled, '
                  'and you\'re testing on a real device.';
            } else {
              errorMessage = 'Apple sign-in error: ${e.message ?? e.code.toString()}';
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
          final age = int.tryParse(ageController.text.trim()) ?? 0;
          final fullName = firstName.isNotEmpty && lastName.isNotEmpty 
              ? '$firstName $lastName' 
              : (user.displayName ?? user.email?.split('@')[0] ?? 'User');

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'phone': phoneNumber.isNotEmpty ? phoneNumber : (user.phoneNumber ?? ''),
            'email': user.email ?? '',
            'firstName': firstName.isNotEmpty ? firstName : (user.displayName != null && user.displayName!.split(' ').isNotEmpty ? user.displayName!.split(' ').first : ''),
            'lastName': lastName.isNotEmpty ? lastName : (user.displayName != null && user.displayName!.split(' ').length > 1 ? user.displayName!.split(' ').sublist(1).join(' ') : ''),
            'fullName': fullName,
            'age': age,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
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
      // Silently fail - not critical
    }
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
          await _checkAndCreateUserProfile();
          if (mounted) {
            setState(() {
              isLoading = false;
            });
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
                      hintText: '+201012345678',
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
                        hintText: 'e.g., +201012345678',
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
