import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import '../screens/login_screen.dart';

/// Use when the user must be logged in to proceed (e.g. booking, my bookings, profile).
/// If already logged in, returns true. If guest, pushes [LoginScreen]; when the route
/// is popped, returns whether the user is now logged in so the caller can navigate to the service.
Future<bool> requireLogin(BuildContext context) async {
  try {
    if (FirebaseAuth.instance.currentUser != null) return true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    return FirebaseAuth.instance.currentUser != null;
  } catch (e, stack) {
    debugPrint('requireLogin error: $e');
    debugPrint('$stack');
    return false;
  }
}
