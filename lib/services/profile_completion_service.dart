import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service to check if social auth users (Google/Apple) need to complete their profile.
class ProfileCompletionService {
  /// Returns true if the user signed in with Google or Apple.
  static bool isSocialAuthUser(User? user) {
    if (user == null) return false;
    return user.providerData.any((info) =>
        info.providerId == 'google.com' || info.providerId == 'apple.com');
  }

  /// Returns true if the user's profile is incomplete (missing email, name, or phone).
  /// Used for social auth users who must complete their profile.
  static bool isProfileIncomplete(DocumentSnapshot? userDoc, User? user) {
    if (userDoc == null || !userDoc.exists || user == null) {
      return true;
    }

    final data = userDoc.data() as Map<String, dynamic>? ?? {};
    final email = (data['email'] as String?)?.trim() ?? user.email?.trim() ?? '';
    final firstName = (data['firstName'] as String?)?.trim() ?? '';
    final lastName = (data['lastName'] as String?)?.trim() ?? '';
    final phone = (data['phone'] as String?)?.trim() ?? '';

    // Email is required
    if (email.isEmpty) return true;

    // Name is required
    if (firstName.isEmpty || lastName.isEmpty) return true;

    // Phone must be valid Egypt format (+2 followed by 11 digits)
    if (phone.isEmpty) return true;
    if (!phone.startsWith('+2')) return true;
    final remainingDigits = phone.length > 2 ? phone.substring(2) : '';
    if (!RegExp(r'^\d{11}$').hasMatch(remainingDigits)) return true;

    return false;
  }

  /// Checks if a social auth user needs to complete their profile.
  /// Returns true if they should be shown the required profile update screen.
  static Future<bool> needsProfileCompletion(User? user) async {
    if (user == null || !isSocialAuthUser(user)) return false;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      return isProfileIncomplete(userDoc, user);
    } catch (_) {
      return true; // On error, assume incomplete to be safe
    }
  }
}
