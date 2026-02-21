import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of applying a promo code.
class PromoResult {
  final bool isValid;
  final String? code;
  final String? message;
  /// Discount as positive number: either percent (0-100) or fixed EGP amount.
  final double? discountValue;
  final bool isPercent;

  const PromoResult({
    required this.isValid,
    this.code,
    this.message,
    this.discountValue,
    this.isPercent = true,
  });

  double applyTo(double subtotal) {
    if (!isValid || discountValue == null) return subtotal;
    if (isPercent) {
      return (subtotal * (1 - discountValue! / 100)).clamp(0.0, double.infinity);
    } else {
      return (subtotal - discountValue!).clamp(0.0, double.infinity);
    }
  }

  double discountAmount(double subtotal) {
    if (!isValid || discountValue == null) return 0.0;
    final finalAmount = applyTo(subtotal);
    return subtotal - finalAmount;
  }
}

/// Validates promo codes. Supports a built-in test code and optional Firestore promoCodes collection.
class PromoCodeService {
  PromoCodeService._();
  static final PromoCodeService instance = PromoCodeService._();

  /// Test promo code: 20% off. Code: TEST20
  static const String testCode = 'TEST20';
  static const double testDiscountPercent = 20.0;

  /// Validate a promo code. Returns [PromoResult].
  Future<PromoResult> validate(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) {
      return const PromoResult(isValid: false, message: 'Enter a promo code');
    }

    // Built-in test code
    if (code == testCode) {
      return PromoResult(
        isValid: true,
        code: code,
        message: '$testDiscountPercent% off',
        discountValue: testDiscountPercent,
        isPercent: true,
      );
    }

    // Optional: check Firestore promoCodes collection
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('promoCodes')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final type = data['type'] as String? ?? 'percent';
        final value = (data['value'] as num?)?.toDouble() ?? 0.0;
        final active = data['active'] as bool? ?? true;
        final expiry = data['expiry'] as Timestamp?;

        if (!active) {
          return const PromoResult(isValid: false, message: 'This code is no longer active');
        }
        if (expiry != null && DateTime.now().isAfter(expiry.toDate())) {
          return const PromoResult(isValid: false, message: 'This code has expired');
        }
        if (value <= 0) {
          return const PromoResult(isValid: false, message: 'Invalid code');
        }

        final isPercent = type == 'percent';
        if (isPercent && value > 100) {
          return const PromoResult(isValid: false, message: 'Invalid code');
        }

        return PromoResult(
          isValid: true,
          code: code,
          message: isPercent ? '$value% off' : '${value.toStringAsFixed(0)} EGP off',
          discountValue: value,
          isPercent: isPercent,
        );
      }
    } catch (e) {
      // If Firestore fails, only the test code is available
    }

    return const PromoResult(isValid: false, message: 'Invalid promo code');
  }
}
