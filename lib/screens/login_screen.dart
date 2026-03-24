import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'home_screen.dart';
import '../utils/egypt_phone.dart';

class LoginScreen extends StatefulWidget {
  /// When true (e.g. opened from the app header for guests), the form starts on sign-up;
  /// users can still switch to log in on the same screen.
  final bool initialSignUpMode;

  const LoginScreen({super.key, this.initialSignUpMode = false});

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
  final phoneNumberController = TextEditingController();
  final optionalSignupEmailController = TextEditingController();
  final ageController = TextEditingController();

  String verificationId = "";
  bool otpSent = false;
  bool isLoading = false;
  int? resendToken;
  bool isNewUser = false;
  bool agreedToTerms = false;
  bool isSignUpMode = false;
  String? selectedGender;
  late AuthMethod selectedAuthMethod;

  // Tracks whether the phone number was already in Firestore before OTP was sent
  bool _phoneAlreadyRegistered = false;

  /// Email/password auth in the method strip — web + desktop (phone OTP not available); hidden on Android/iOS apps.
  bool get _showEmailAuthOption => kIsWeb || _isPhoneAuthUnsupported;

  @override
  void initState() {
    super.initState();
    isSignUpMode = widget.initialSignUpMode;
    selectedAuthMethod = _isPhoneAuthUnsupported ? AuthMethod.email : AuthMethod.phone;
  }

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    passwordController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    phoneNumberController.dispose();
    optionalSignupEmailController.dispose();
    ageController.dispose();
    super.dispose();
  }

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

  void _scheduleAuthSuccess(String message) {
    if (!mounted) return;
    setState(() { isLoading = false; });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
      );
      _navigateAfterAuth();
    });
  }

  String? _validatePhone(String? value) => EgyptPhone.validateLocal(value);

  String? _validateOTP(String? value) {
    if (value == null || value.isEmpty) return 'Please enter the OTP code';
    if (value.length < 6) return 'OTP code must be 6 digits';
    return null;
  }

  String? _validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) return 'First name is required';
    if (value.trim().length < 2) return 'First name must be at least 2 characters';
    return null;
  }

  String? _validateLastName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Last name is required';
    if (value.trim().length < 2) return 'Last name must be at least 2 characters';
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Please enter a valid email address';
    return null;
  }

  String? _validateOptionalEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(v)) return 'Please enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateAge(String? value) {
    if (value == null || value.trim().isEmpty) return 'Age is required';
    final age = int.tryParse(value.trim());
    if (age == null) return 'Please enter a valid number';
    if (age < 13) return 'You must be at least 13 years old';
    if (age > 120) return 'Please enter a valid age';
    return null;
  }

  bool get _isPhoneAuthUnsupported {
    if (kIsWeb) return true;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  Future<void> sendOTP() async {
    if (_isPhoneAuthUnsupported) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone authentication is not available on this device. Please use the app on Android or iOS.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    // Validate signup-only fields
    if (isSignUpMode) {
      if (firstNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your first name'), backgroundColor: Colors.orange));
        return;
      }
      if (lastNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your last name'), backgroundColor: Colors.orange));
        return;
      }
      if (ageController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your age'), backgroundColor: Colors.orange));
        return;
      }
      if (selectedGender == null || (selectedGender != 'male' && selectedGender != 'female')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your gender (Male or Female)'), backgroundColor: Colors.orange));
        return;
      }
      if (!agreedToTerms) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to the terms and conditions'), backgroundColor: Colors.orange));
        return;
      }
    }

    setState(() { isLoading = true; });

    try {
      final phoneNumber = EgyptPhone.e164(phoneController.text.trim());

      // ── Check Firestore: is this phone already registered? ──
      // We check for both login and signup so we know what to do after OTP.
      bool phoneExistsInFirestore = false;
      try {
        final existingPhoneUser = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: phoneNumber)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 8));
        phoneExistsInFirestore = existingPhoneUser.docs.isNotEmpty;
      } catch (_) {
        // If Firestore check fails, proceed — Firebase Auth will handle it
      }

      // In signup mode: if phone already registered, block and switch to login
      if (isSignUpMode && phoneExistsInFirestore) {
        if (mounted) {
          setState(() {
            isLoading = false;
            isSignUpMode = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This number is already registered. Switched to Login — tap Send OTP & Login to sign in.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Store for use in verifyOTP / _handlePostPhoneAuth
      _phoneAlreadyRegistered = phoneExistsInFirestore;

      // ── Send OTP ──
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('✅ verificationCompleted (auto-sign-in)');
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _handlePostPhoneAuth();
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('❌ verificationFailed: ${e.code} - ${e.message}');
          if (mounted) {
            setState(() { isLoading = false; });
            String errorMessage = 'Verification failed. Please try again.';
            if (e.code == 'invalid-phone-number') errorMessage = 'Invalid phone number. Please check and try again.';
            else if (e.code == 'too-many-requests') errorMessage = 'Too many requests. Please wait a moment and try again.';
            else if (e.code == 'quota-exceeded') errorMessage = 'SMS quota exceeded. Please try again later.';
            else if (e.code == 'app-not-authorized') errorMessage = 'App not authorized. Please contact support.';
            else if (e.message != null) errorMessage = e.message!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
            );
          }
        },
        codeSent: (String verId, int? token) {
          debugPrint('✅ codeSent - verificationId: $verId');
          if (mounted) {
            setState(() {
              verificationId = verId;
              otpSent = true;
              isLoading = false;
              resendToken = token;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('OTP code sent! Please check your phone.'), backgroundColor: Colors.green, duration: Duration(seconds: 3)),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verId) {
          debugPrint('⏱ codeAutoRetrievalTimeout');
          verificationId = verId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      debugPrint('💥 sendOTP exception: $e');
      if (mounted) {
        setState(() { isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Called after a successful phone OTP sign-in (both auto and manual).
  ///
  /// Logic:
  /// - If phone was already in Firestore (login): just update + login.
  /// - If not in Firestore + signup mode: create full profile.
  /// - If not in Firestore + login mode: sign out and tell user to sign up.
  Future<void> _handlePostPhoneAuth() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Double-check Firestore profile by UID
      DocumentSnapshot? userDoc;
      try {
        userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        userDoc = null;
      }

      final profileExists = userDoc != null && userDoc.exists;

      if (_phoneAlreadyRegistered || profileExists) {
        // ── EXISTING USER: log them in, just refresh phone field ──
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'phone': user.phoneNumber ?? EgyptPhone.e164(phoneController.text.trim()),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
              .timeout(const Duration(seconds: 6));
        } catch (_) {}

        if (mounted) {
          _scheduleAuthSuccess('Login successful!');
        }
      } else {
        // ── NEW USER ──
        if (isSignUpMode) {
          // Create full profile from form fields
          await _createPhoneUserProfile(user);
          if (mounted) {
            _scheduleAuthSuccess('Welcome! Account created successfully.');
          }
        } else {
          // Login mode but no Firestore profile — not registered
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            setState(() { isLoading = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('This phone number is not registered. Please sign up first.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('_handlePostPhoneAuth error: $e');
      if (mounted) {
        setState(() { isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Creates a full Firestore profile for a brand-new phone-authenticated user.
  Future<void> _createPhoneUserProfile(User user) async {
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final phoneNumber = user.phoneNumber ?? EgyptPhone.e164(phoneController.text.trim());
    final age = int.tryParse(ageController.text.trim()) ?? 0;
    final fullName = firstName.isNotEmpty && lastName.isNotEmpty
        ? '$firstName $lastName'
        : (user.displayName ?? 'User');

    final optEmail = optionalSignupEmailController.text.trim();
    final profileData = <String, dynamic>{
      'phone': phoneNumber,
      'email': optEmail.isNotEmpty ? optEmail : (user.email ?? ''),
      'firstName': firstName,
      'lastName': lastName,
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
        .set(profileData, SetOptions(merge: true))
        .timeout(const Duration(seconds: 8));
  }

  Future<void> verifyOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { isLoading = true; });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otpController.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _handlePostPhoneAuth();
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid OTP code. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showOtpTroubleshootingDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Didn\'t receive the code?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Check these in order:', style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('1. Test number? In Firebase Console → Authentication → Sign-in method → Phone, remove your number from "Phone numbers for testing" if you want real SMS.'),
              SizedBox(height: 8),
              Text('2. Blaze plan? Real SMS requires Firebase Blaze (pay-as-you-go).'),
              SizedBox(height: 8),
              Text('3. SMS region? In Authentication → Settings, enable the SMS region for your country (e.g. Egypt).'),
              SizedBox(height: 8),
              Text('4. Number format: country code +20 is fixed in the app; enter exactly 10 digits after +20 (e.g. +201006500500).'),
              SizedBox(height: 8),
              Text('5. Wait 1–2 minutes and tap Resend OTP, or try another network.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    if (firstNameController.text.trim().isEmpty ||
        lastNameController.text.trim().isEmpty ||
        phoneNumberController.text.trim().isEmpty ||
        ageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields'), backgroundColor: Colors.orange));
      return;
    }

    final phoneValidation = _validatePhone(phoneNumberController.text.trim());
    if (phoneValidation != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(phoneValidation), backgroundColor: Colors.orange));
      return;
    }

    if (selectedGender == null || (selectedGender != 'male' && selectedGender != 'female')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your gender (Male or Female)'), backgroundColor: Colors.orange));
      return;
    }

    if (!agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please agree to the terms and conditions'), backgroundColor: Colors.orange));
      return;
    }

    setState(() { isLoading = true; });

    try {
      final email = emailController.text.trim();
      final phoneNumber = EgyptPhone.e164(phoneNumberController.text.trim());

      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: passwordController.text.trim(),
      );

      isNewUser = true;

      final user = userCredential.user;
      if (user != null) {
        try {
          final firstName = firstNameController.text.trim();
          final lastName = lastNameController.text.trim();
          final fullName = firstName.isNotEmpty && lastName.isNotEmpty
              ? '$firstName $lastName'
              : (user.displayName ?? email.split('@')[0]);
          final ageInt = int.tryParse(ageController.text.trim()) ?? 0;
          final profileData = <String, dynamic>{
            'email': email,
            'phone': phoneNumber,
            'firstName': firstName,
            'lastName': lastName,
            'fullName': fullName,
            'age': ageInt,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (selectedGender == 'male' || selectedGender == 'female') profileData['gender'] = selectedGender;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set(profileData, SetOptions(merge: true))
              .timeout(const Duration(seconds: 8));
        } catch (profileError) {
          debugPrint('Profile write failed (continuing): $profileError');
        }
      }

      if (mounted) _scheduleAuthSuccess('Account created successfully! Welcome!');
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; });
        debugPrint('Signup error: $e');
        String errorMessage = 'Sign up failed. Please try again.';
        if (e is FirebaseAuthException) {
          if (e.code == 'email-already-in-use') errorMessage = 'This email is already registered. Please login instead.';
          else if (e.code == 'weak-password') errorMessage = 'Password is too weak. Please use a stronger password.';
          else if (e.code == 'invalid-email') errorMessage = 'Invalid email address. Please enter a valid email.';
          else if (e.code == 'operation-not-allowed') errorMessage = 'Email/password accounts are not enabled. Please contact support.';
          else if (e.code == 'network-request-failed') errorMessage = 'Network error. Please check your internet connection and try again.';
          else errorMessage = 'Sign up failed (${e.code}): ${e.message ?? 'Unknown error'}. Please try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
        );
      }
    }
  }

  Future<void> resetPassword() async {
    if (!mounted) return;
    final resetEmailController = TextEditingController();
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
                const Text('Enter your email address and we\'ll send you a link to reset your password.', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your email address';
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value.trim())) return 'Please enter a valid email address';
                    return null;
                  },
                  decoration: const InputDecoration(labelText: 'Email', hintText: 'your.email@example.com', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final email = resetEmailController.text.trim();
              if (email.isEmpty) return;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (loadingContext) => const AlertDialog(
                  content: Row(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Sending reset link...')]),
                ),
              );
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                  actionCodeSettings: ActionCodeSettings(
                    url: 'https://padelcore-app.firebaseapp.com/__/auth/action',
                    handleCodeInApp: false,
                    androidPackageName: 'com.padelcore.app',
                    iOSBundleId: 'com.padelcore.app',
                  ),
                );
                if (mounted) {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    barrierDismissible: true,
                    builder: (successContext) => AlertDialog(
                      title: const Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 28), SizedBox(width: 8), Expanded(child: Text('Email Sent'))]),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('We\'ve sent a password reset link to:\n\n$email', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 16),
                            const Text('Please check:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            const Text('• Your inbox (wait 1-2 minutes)\n• Spam/Junk folder\n• Promotions folder (Gmail)', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(successContext), child: const Text('OK'))],
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  String errorMessage = 'Failed to send password reset email. Please try again.';
                  if (e is FirebaseAuthException) {
                    if (e.code == 'user-not-found') errorMessage = 'No account found with this email address. Please sign up first.';
                    else if (e.code == 'invalid-email') errorMessage = 'Invalid email address. Please check and try again.';
                    else if (e.code == 'too-many-requests') errorMessage = 'Too many requests. Please wait a few minutes before trying again.';
                    else errorMessage = 'Error: ${e.message ?? e.code}';
                  }
                  showDialog(
                    context: context,
                    builder: (errorContext) => AlertDialog(
                      title: const Row(children: [Icon(Icons.error, color: Colors.red, size: 28), SizedBox(width: 8), Expanded(child: Text('Error'))]),
                      content: Text(errorMessage),
                      actions: [ElevatedButton(onPressed: () => Navigator.pop(errorContext), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('OK'))],
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

  Future<void> loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { isLoading = true; });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
      isNewUser = false;
      _checkAndCreateUserProfile().catchError((e) => debugPrint('Profile sync failed: $e'));
      if (mounted) _scheduleAuthSuccess('Login successful!');
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; });
        String errorMessage = 'Login failed. Please try again.';
        if (e is FirebaseAuthException) {
          if (e.code == 'user-not-found') errorMessage = 'No account found with this email. Please sign up first.';
          else if (e.code == 'wrong-password' || e.code == 'invalid-credential') errorMessage = 'Wrong password. Please check your password and try again.';
          else if (e.code == 'invalid-email') errorMessage = 'Invalid email address.';
          else if (e.code == 'user-disabled') errorMessage = 'This account has been disabled. Please contact support.';
          else if (e.code == 'too-many-requests') errorMessage = 'Too many failed login attempts. Please try again later.';
          else if (e.code == 'network-request-failed') errorMessage = 'Network error. Please check your internet connection.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() { isLoading = true; });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() { isLoading = false; });
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (isNewUser && user.email != null) {
        try {
          final existingEmailUser = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: user.email)
              .where(FieldPath.documentId, isNotEqualTo: user.uid)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 6));
          if (existingEmailUser.docs.isNotEmpty) {
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              setState(() { isLoading = false; });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This email is already registered by another account. Please login instead.'), backgroundColor: Colors.red, duration: Duration(seconds: 4)));
            }
            return;
          }
        } catch (_) {}
      }

      if (!isNewUser) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get().timeout(const Duration(seconds: 6));
          if (!userDoc.exists) {
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              setState(() { isLoading = false; });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your account is not registered. Please sign up first.'), backgroundColor: Colors.orange, duration: Duration(seconds: 4)));
            }
            return;
          }
        } catch (_) {}
      }

      if (isNewUser && googleUser.displayName != null) {
        final nameParts = googleUser.displayName!.split(' ');
        firstNameController.text = nameParts.isNotEmpty ? nameParts[0] : '';
        lastNameController.text = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
      }

      _checkAndCreateUserProfile().catchError((_) {});
      if (mounted) _scheduleAuthSuccess(isNewUser ? 'Welcome! Account created successfully.' : 'Login successful!');
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; });
        String errorMessage = 'Google sign-in failed. Please try again.';
        if (e.toString().contains('ApiException: 10') || e.toString().contains('DEVELOPER_ERROR') || e.toString().contains('sign_in_failed')) {
          errorMessage = 'Google sign-in configuration error. The app\'s SHA-1 fingerprint may need to be added to Firebase.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.red, duration: const Duration(seconds: 6)));
      }
    }
  }

  Future<void> signInWithApple() async {
    final isAvailable = await SignInWithApple.isAvailable();
    if (!isAvailable) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in with Apple is not available on this device.'), backgroundColor: Colors.orange, duration: Duration(seconds: 3)));
      return;
    }

    setState(() { isLoading = true; });

    try {
      debugPrint('═══════════════════════════════════════');
      debugPrint('Attempting Apple Sign In...');
      debugPrint('═══════════════════════════════════════');

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );

      if (appleCredential.identityToken == null) throw Exception('Apple Sign In failed: identityToken is null');

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final initialEmail = user.email ?? appleCredential.email?.trim() ?? '';
      FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'email': initialEmail,
        if (appleCredential.givenName != null && appleCredential.givenName!.trim().isNotEmpty) 'firstName': appleCredential.givenName!.trim(),
        if (appleCredential.familyName != null && appleCredential.familyName!.trim().isNotEmpty) 'lastName': appleCredential.familyName!.trim(),
      }, SetOptions(merge: true)).catchError((_) {});

      if (isNewUser && user.email != null) {
        try {
          final existingEmailUser = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: user.email)
              .where(FieldPath.documentId, isNotEqualTo: user.uid)
              .limit(1)
              .get()
              .timeout(const Duration(seconds: 6));
          if (existingEmailUser.docs.isNotEmpty) {
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              setState(() { isLoading = false; });
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This email is already registered by another account. Please login instead.'), backgroundColor: Colors.red, duration: Duration(seconds: 4)));
            }
            return;
          }
        } catch (_) {}
      }

      if (isNewUser) {
        firstNameController.text = appleCredential.givenName ?? '';
        lastNameController.text = appleCredential.familyName ?? '';
      }

      _checkAndCreateUserProfile().catchError((_) {});
      Future(() async {
        try {
          final appleUpdates = <String, dynamic>{};
          if (appleCredential.email != null && appleCredential.email!.trim().isNotEmpty) appleUpdates['email'] = appleCredential.email!.trim();
          if (appleCredential.givenName != null && appleCredential.givenName!.trim().isNotEmpty) appleUpdates['firstName'] = appleCredential.givenName!.trim();
          if (appleCredential.familyName != null && appleCredential.familyName!.trim().isNotEmpty) appleUpdates['lastName'] = appleCredential.familyName!.trim();
          if (appleUpdates.isNotEmpty) {
            final first = appleUpdates['firstName'] as String? ?? '';
            final last = appleUpdates['lastName'] as String? ?? '';
            if (first.isNotEmpty || last.isNotEmpty) appleUpdates['fullName'] = '$first $last'.trim();
            appleUpdates['updatedAt'] = FieldValue.serverTimestamp();
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set(appleUpdates, SetOptions(merge: true));
          }
        } catch (_) {}
      });

      if (mounted) _scheduleAuthSuccess(isNewUser ? 'Welcome! Account created successfully.' : 'Login successful!');
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; });
        String errorMessage = 'Apple sign-in failed. Please try again.';
        if (e is SignInWithAppleAuthorizationException) {
          if (e.code == AuthorizationErrorCode.canceled) return;
          debugPrint('Apple Sign In Error: ${e.code} - ${e.message}');
          final errorSummary = 'Error ${e.code}: ${e.message ?? "Unknown error"}';
          if (e.code == AuthorizationErrorCode.unknown && (e.message?.contains('1000') == true || e.toString().contains('1000'))) {
            errorMessage = 'Apple Sign In error 1000. Possible causes: Service ID Return URL mismatch, provisioning profile issue, or App entitlements not in release build.\n\nError: $errorSummary';
          } else {
            errorMessage = 'Apple sign-in error: $errorSummary';
          }
        } else {
          debugPrint('Sign in with Apple error: $e');
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage), backgroundColor: Colors.red, duration: const Duration(seconds: 4)));
      }
    }
  }

  /// Used by email / Google / Apple sign-in flows to sync profile data.
  Future<void> _checkAndCreateUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 8));

      if (!userDoc.exists || isNewUser || isSignUpMode) {
        if (isSignUpMode || isNewUser) {
          final firstName = firstNameController.text.trim();
          final lastName = lastNameController.text.trim();
          final phoneToSave = (user.phoneNumber ?? '').trim().isNotEmpty
              ? (user.phoneNumber ?? '').trim()
              : EgyptPhone.e164(phoneNumberController.text.trim());
          final email = user.email ?? '';
          final age = int.tryParse(ageController.text.trim()) ?? 0;
          final fullName = firstName.isNotEmpty && lastName.isNotEmpty
              ? '$firstName $lastName'
              : (user.displayName ?? user.email?.split('@')[0] ?? 'User');

          final profileData = <String, dynamic>{
            'phone': phoneToSave,
            'email': email,
            'firstName': firstName.isNotEmpty ? firstName : (user.displayName?.split(' ').first ?? ''),
            'lastName': lastName.isNotEmpty ? lastName : (user.displayName != null && user.displayName!.split(' ').length > 1 ? user.displayName!.split(' ').sublist(1).join(' ') : ''),
            'fullName': fullName,
            'age': age,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (selectedGender == 'male' || selectedGender == 'female') profileData['gender'] = selectedGender;
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(profileData, SetOptions(merge: true));
        } else {
          if (!userDoc.exists) {
            final emailName = user.email?.split('@')[0] ?? 'User';
            final displayName = user.displayName;
            final nameParts = displayName != null ? displayName.split(' ') : <String>[];
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'phone': user.phoneNumber ?? '',
              'email': user.email ?? '',
              'firstName': nameParts.isNotEmpty ? nameParts.first : emailName,
              'lastName': nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
              'fullName': displayName ?? emailName,
              'age': 0,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'phone': user.phoneNumber ?? '',
              'email': user.email ?? '',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }
    } catch (e) {
      debugPrint('Error in _checkAndCreateUserProfile: $e');
      rethrow;
    }
  }

  Future<void> resendOTP() async {
    if (phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your phone number first'), backgroundColor: Colors.orange));
      return;
    }
    setState(() { isLoading = true; });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: EgyptPhone.e164(phoneController.text.trim()),
        forceResendingToken: resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _handlePostPhoneAuth();
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() { isLoading = false; });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Failed to resend OTP'), backgroundColor: Colors.red));
          }
        },
        codeSent: (String verId, int? token) {
          if (mounted) {
            setState(() { verificationId = verId; resendToken = token; isLoading = false; });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP code resent!'), backgroundColor: Colors.green));
          }
        },
        codeAutoRetrievalTimeout: (String verId) { verificationId = verId; },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      if (mounted) {
        setState(() { isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red));
      }
    }
  }

  void _resetForm() {
    setState(() {
      otpSent = false;
      otpController.clear();
      verificationId = "";
      resendToken = null;
      _phoneAlreadyRegistered = false;
    });
  }

  Widget _buildAuthMethodButton(AuthMethod method, IconData icon, String label) {
    final isSelected = selectedAuthMethod == method;
    return GestureDetector(
      onTap: isLoading ? null : () {
        setState(() {
          selectedAuthMethod = method;
          if (method != AuthMethod.phone) {
            otpSent = false;
            otpController.clear();
            optionalSignupEmailController.clear();
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
            Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.grey[700]),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Future<void> _openTermsAndConditions() async {
    final url = Uri.parse('https://1drv.ms/b/c/087e33f99fc23140/IQC--FE1rga5Qa5s-HLmLOAvAcSRm01OwSKAziTbXNTdYew?e=eSPGjV');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
    else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Terms and Conditions'), backgroundColor: Colors.red));
  }

  Future<void> _openPrivacyPolicy() async {
    final url = Uri.parse('https://1drv.ms/b/c/087e33f99fc23140/IQCKIjXCYM2vSYuUW3ouxDVOAZ51bAetIcxGdV9BiUiv-z0?e=hseaQY');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
    else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Privacy Policy'), backgroundColor: Colors.red));
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
                Image.asset('assets/images/logo.png', height: 80),
                const SizedBox(height: 20),
                Text(
                  otpSent ? 'Verify OTP' : (isSignUpMode ? 'Create Account' : 'Welcome Back'),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  otpSent
                      ? 'Enter the 6-digit code sent to ${EgyptPhone.e164(phoneController.text.trim())}'
                      : (isSignUpMode ? 'Sign up to book your padel court' : 'Login to continue booking'),
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                if (!otpSent) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: isLoading ? null : () { setState(() { isSignUpMode = true; }); },
                        child: Text('Sign up', style: TextStyle(fontSize: 16, fontWeight: isSignUpMode ? FontWeight.bold : FontWeight.normal, color: isSignUpMode ? const Color(0xFF1E3A8A) : Colors.grey, decoration: isSignUpMode ? TextDecoration.underline : null)),
                      ),
                      Text(' | ', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
                      TextButton(
                        onPressed: isLoading ? null : () {
                          setState(() {
                            isSignUpMode = false;
                            firstNameController.clear();
                            lastNameController.clear();
                            phoneNumberController.clear();
                            optionalSignupEmailController.clear();
                            ageController.clear();
                            agreedToTerms = false;
                            selectedGender = null;
                          });
                        },
                        child: Text('Log in', style: TextStyle(fontSize: 16, fontWeight: isSignUpMode ? FontWeight.normal : FontWeight.bold, color: isSignUpMode ? Colors.grey : const Color(0xFF1E3A8A), decoration: isSignUpMode ? null : TextDecoration.underline)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(child: _buildAuthMethodButton(AuthMethod.phone, Icons.phone, 'Phone')),
                        const SizedBox(width: 8),
                        if (_showEmailAuthOption) ...[
                          Expanded(child: _buildAuthMethodButton(AuthMethod.email, Icons.email, 'Email')),
                          const SizedBox(width: 8),
                        ],
                        Expanded(child: _buildAuthMethodButton(AuthMethod.google, Icons.g_mobiledata, 'Google')),
                        if (!kIsWeb && Platform.isIOS) ...[
                          const SizedBox(width: 8),
                          Expanded(child: _buildAuthMethodButton(AuthMethod.apple, Icons.phone_iphone, 'Apple')),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                if (!otpSent && selectedAuthMethod == AuthMethod.phone) ...[
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(EgyptPhone.localDigitsLength),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Phone Number *',
                      hintText: '10 digits after +20',
                      prefixText: '${EgyptPhone.e164Prefix} ',
                      prefixStyle: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w600),
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: _validatePhone,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                  if (isSignUpMode) ...[
                    TextFormField(
                      controller: optionalSignupEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email (optional)',
                        hintText: 'your.email@example.com',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: _validateOptionalEmail,
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 16),
                  ],
                ],

                if (!otpSent && selectedAuthMethod == AuthMethod.email) ...[
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: 'Email *', hintText: 'your.email@example.com', prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]),
                    validator: _validateEmail,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: 'Password *', hintText: 'Enter your password', prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]),
                    validator: _validatePassword,
                    enabled: !isLoading,
                  ),
                  if (!isSignUpMode)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(onPressed: isLoading ? null : resetPassword, child: const Text('Forgot Password?', style: TextStyle(fontSize: 14, decoration: TextDecoration.underline))),
                    ),
                  const SizedBox(height: 16),
                ],

                if (!otpSent && isSignUpMode && selectedAuthMethod != AuthMethod.google) ...[
                  TextFormField(
                    controller: firstNameController,
                    decoration: InputDecoration(labelText: 'First Name *', hintText: 'Enter your first name', prefixIcon: const Icon(Icons.person), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]),
                    validator: isSignUpMode ? _validateFirstName : null,
                    enabled: !isLoading,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: lastNameController,
                    decoration: InputDecoration(labelText: 'Last Name *', hintText: 'Enter your last name', prefixIcon: const Icon(Icons.person_outline), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]),
                    validator: isSignUpMode ? _validateLastName : null,
                    enabled: !isLoading,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  if (selectedAuthMethod != AuthMethod.phone) ...[
                    TextFormField(
                      controller: phoneNumberController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(EgyptPhone.localDigitsLength),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Phone Number *',
                        hintText: '10 digits after +20',
                        prefixText: '${EgyptPhone.e164Prefix} ',
                        prefixStyle: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.w600),
                        prefixIcon: const Icon(Icons.phone),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: isSignUpMode ? _validatePhone : null,
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Age *', hintText: 'Enter your age', prefixIcon: const Icon(Icons.calendar_today), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]),
                    validator: isSignUpMode ? _validateAge : null,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                  const Text('Gender *', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
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
                          onSelectionChanged: isLoading ? null : (Set<String?> newSelection) { setState(() { selectedGender = newSelection.isEmpty ? null : newSelection.first; }); },
                          style: ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 12))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(value: agreedToTerms, onChanged: isLoading ? null : (value) { setState(() { agreedToTerms = value ?? false; }); }),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                              children: [
                                const TextSpan(text: 'I agree to the '),
                                WidgetSpan(child: GestureDetector(onTap: isLoading ? null : _openTermsAndConditions, child: Text('Terms and Conditions', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Colors.blue[700])))),
                                const TextSpan(text: ' and '),
                                WidgetSpan(child: GestureDetector(onTap: isLoading ? null : _openPrivacyPolicy, child: Text('Privacy Policy', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold, decoration: TextDecoration.underline, decorationColor: Colors.blue[700])))),
                                const TextSpan(text: ' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 48),
                    child: Text('Tap the links above to read the full documents', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                  ),
                ],

                if (otpSent && selectedAuthMethod == AuthMethod.phone) ...[
                  TextFormField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(labelText: 'OTP Code', hintText: '000000', prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]),
                    validator: _validateOTP,
                    enabled: !isLoading,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextButton(onPressed: isLoading ? null : resendOTP, child: const Text('Resend OTP')),
                  TextButton(onPressed: isLoading ? null : _resetForm, child: const Text('Change Phone Number')),
                  TextButton.icon(onPressed: () => _showOtpTroubleshootingDialog(), icon: const Icon(Icons.help_outline, size: 18), label: const Text('Didn\'t receive the code?')),
                ],

                const SizedBox(height: 32),

                if (!otpSent && selectedAuthMethod == AuthMethod.google) ...[
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : signInWithGoogle,
                    icon: isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.black)))
                        : Image.asset('assets/images/google_logo.png', height: 20, errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata)),
                    label: Text(isLoading ? 'Signing in...' : 'Continue with Google', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Sign in with your Google account. Your name and email will be used to create your profile.', style: TextStyle(fontSize: 12, color: Colors.blue[900]))),
                      ],
                    ),
                  ),
                ] else if (!otpSent && selectedAuthMethod == AuthMethod.apple && !kIsWeb && Platform.isIOS) ...[
                  SignInWithAppleButton(
                    onPressed: isLoading ? () {} : () { signInWithApple(); },
                    height: 50,
                    text: isLoading ? 'Signing in...' : 'Continue with Apple',
                    style: SignInWithAppleButtonStyle.black,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Sign in with Apple protects your privacy. You can choose to hide your email address.', style: TextStyle(fontSize: 12, color: Colors.grey[900]))),
                      ],
                    ),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: isLoading ? null : () {
                      if (selectedAuthMethod == AuthMethod.phone) {
                        if (otpSent) verifyOTP(); else sendOTP();
                      } else if (selectedAuthMethod == AuthMethod.email) {
                        if (isSignUpMode) signUpWithEmail(); else loginWithEmail();
                      }
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.black)))
                        : Text(
                            selectedAuthMethod == AuthMethod.phone
                                ? (otpSent ? 'Verify & ${isSignUpMode ? "Sign Up" : "Login"}' : (isSignUpMode ? 'Send OTP & Sign Up' : 'Send OTP & Login'))
                                : (isSignUpMode ? 'Sign Up' : 'Login'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 24),
                  if (selectedAuthMethod == AuthMethod.phone || selectedAuthMethod == AuthMethod.email)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedAuthMethod == AuthMethod.phone
                                  ? (otpSent ? 'Enter the 6-digit verification code sent to your phone via SMS.' : 'We\'ll send you a verification code via SMS. +20 is fixed — enter your 10-digit Egyptian mobile number.')
                                  : 'Use your email and password to sign in or create a new account.',
                              style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                if (!otpSent && !kIsWeb && Platform.isIOS && selectedAuthMethod != AuthMethod.apple) ...[
                  const SizedBox(height: 24),
                  const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('OR')), Expanded(child: Divider())]),
                  const SizedBox(height: 24),
                  SignInWithAppleButton(
                    onPressed: isLoading ? () {} : () { signInWithApple(); },
                    height: 50,
                    text: isLoading ? 'Signing in...' : 'Continue with Apple',
                    style: SignInWithAppleButtonStyle.black,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[700], size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Sign in with Apple protects your privacy. You can choose to hide your email address.', style: TextStyle(fontSize: 12, color: Colors.grey[900]))),
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
