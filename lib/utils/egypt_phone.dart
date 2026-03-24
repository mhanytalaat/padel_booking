/// Egypt mobile numbers: fixed [e164Prefix] (+20). Users enter exactly [localDigitsLength] digits;
/// full E.164 is [e164Prefix] + those digits (e.g. +201006500500).
class EgyptPhone {
  EgyptPhone._();

  static const String e164Prefix = '+20';
  static const int localDigitsLength = 10;

  static String e164(String localDigits) {
    final d = localDigits.replaceAll(RegExp(r'\D'), '');
    return '$e164Prefix$d';
  }

  /// Validates the editable local part only (no +20).
  static String? validateLocal(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    final d = value.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d+$').hasMatch(d)) {
      return 'Use digits only';
    }
    if (d.length < localDigitsLength) {
      return 'Enter $localDigitsLength digits after +20 (e.g. 1006500500)';
    }
    if (d.length > localDigitsLength) {
      return 'Must be exactly $localDigitsLength digits after +20';
    }
    return null;
  }

  /// Prefill the local field from a stored E.164 or legacy +2… value.
  static String localPartForField(String? stored) {
    if (stored == null || stored.isEmpty) return '';
    final t = stored.trim();
    if (t.startsWith(e164Prefix)) {
      final d = t.substring(e164Prefix.length).replaceAll(RegExp(r'\D'), '');
      if (d.length <= localDigitsLength) return d;
      return d.substring(d.length - localDigitsLength);
    }
    if (t.startsWith('+2')) {
      final d = t.substring(2).replaceAll(RegExp(r'\D'), '');
      if (d.length <= localDigitsLength) return d;
      return d.substring(d.length - localDigitsLength);
    }
    return '';
  }

  /// Accept +20 + 10 digits (standard), +20 + 11 digits (legacy), or +2 + 11 digits (legacy).
  static bool isValidStored(String phone) {
    final t = phone.trim();
    if (t.startsWith(e164Prefix)) {
      final rest = t.substring(e164Prefix.length).replaceAll(RegExp(r'\D'), '');
      return rest.length == localDigitsLength ||
          rest.length == localDigitsLength + 1;
    }
    if (t.startsWith('+2')) {
      final rest = t.substring(2).replaceAll(RegExp(r'\D'), '');
      return rest.length == 11;
    }
    return false;
  }
}
