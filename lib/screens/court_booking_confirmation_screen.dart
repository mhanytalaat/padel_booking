import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../utils/map_launcher.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../services/spark_api_service.dart';
import '../services/promo_code_service.dart';
import '../services/profile_completion_service.dart';
import 'required_profile_update_screen.dart';
import 'login_screen.dart';

class CourtBookingConfirmationScreen extends StatefulWidget {
  final String locationId;
  final String locationName;
  final String locationAddress;
  final DateTime selectedDate;
  final Map<String, List<String>> selectedSlots; // courtId -> [time slots]
  final double totalCost;
  final double pricePer30Min;
  final String? locationLogoUrl;
  /// End time for midnight play (e.g. 4:00 AM). Slots before this in the early AM are "midnight" (next-day booking). Default 4:00 AM.
  final String? midnightPlayEndTime;

  const CourtBookingConfirmationScreen({
    super.key,
    required this.locationId,
    required this.locationName,
    required this.locationAddress,
    required this.selectedDate,
    required this.selectedSlots,
    required this.totalCost,
    required this.pricePer30Min,
    this.locationLogoUrl,
    this.midnightPlayEndTime,
  });

  @override
  State<CourtBookingConfirmationScreen> createState() => _CourtBookingConfirmationScreenState();
}

class _CourtBookingConfirmationScreenState extends State<CourtBookingConfirmationScreen> {
  bool _agreedToTerms = false;
  bool _isSubmitting = false;
  double? _locationLat;
  double? _locationLng;
  final TextEditingController _promoController = TextEditingController();
  PromoResult? _appliedPromo;
  bool _isApplyingPromo = false;

  double get _finalCost {
    if (_appliedPromo != null && _appliedPromo!.isValid) {
      return _appliedPromo!.applyTo(widget.totalCost);
    }
    return widget.totalCost;
  }

  double get _discountAmount {
    if (_appliedPromo != null && _appliedPromo!.isValid) {
      return _appliedPromo!.discountAmount(widget.totalCost);
    }
    return 0.0;
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLocationCoordinates();
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) {
      setState(() => _appliedPromo = null);
      return;
    }
    setState(() => _isApplyingPromo = true);
    final result = await PromoCodeService.instance.validate(code);
    if (mounted) {
      setState(() {
        _appliedPromo = result.isValid ? result : null;
        _isApplyingPromo = false;
      });
      if (result.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Promo applied: ${result.message}'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Invalid code'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _loadLocationCoordinates() async {
    try {
      final locationDoc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(widget.locationId)
          .get();
      
      if (locationDoc.exists) {
        final data = locationDoc.data();
        if (mounted) {
          setState(() {
            _locationLat = (data?['lat'] as num?)?.toDouble();
            _locationLng = (data?['lng'] as num?)?.toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading location coordinates: $e');
    }
  }

  String _getTimeRange() {
    if (widget.selectedSlots.isEmpty) return '';
    
    final allSlots = <String>[];
    for (var slots in widget.selectedSlots.values) {
      allSlots.addAll(slots);
    }
    allSlots.sort();
    
    if (allSlots.isEmpty) return '';
    final start = allSlots.first;
    final end = allSlots.last;
    
    // Calculate end time (add 30 minutes to last slot)
    try {
      final format = DateFormat('h:mm a');
      final endTime = format.parse(end);
      final actualEnd = endTime.add(const Duration(minutes: 30));
      return '$start - ${format.format(actualEnd)}';
    } catch (e) {
      return '$start - ${end}';
    }
  }

  /// Parse courtId -> Spark spaceId from Firestore (e.g. { "court_1": 1, "court_2": 2 }).
  /// Accepts map values as number or numeric string (Firestore may store as string).
  Map<String, int>? _parseCourtToSpaceId(dynamic value) {
    if (value is! Map) return null;
    final result = <String, int>{};
    for (final e in value.entries) {
      final k = e.key.toString();
      final v = e.value;
      if (v is int) {
        result[k] = v;
      } else if (v is num) {
        result[k] = v.toInt();
      } else if (v != null) {
        final parsed = int.tryParse(v.toString());
        if (parsed != null) result[k] = parsed;
      }
    }
    return result.isEmpty ? null : result;
  }

  /// Start time of the first booked slot on the given date (for cancellation deadline).
  DateTime? _getFirstSlotStartOn(DateTime bookingDate) {
    final allSlots = <String>[];
    for (var slots in widget.selectedSlots.values) {
      allSlots.addAll(slots);
    }
    if (allSlots.isEmpty) return null;
    allSlots.sort();
    try {
      final format = DateFormat('h:mm a');
      final parsed = format.parse(allSlots.first);
      return DateTime(
        bookingDate.year,
        bookingDate.month,
        bookingDate.day,
        parsed.hour,
        parsed.minute,
      );
    } catch (_) {
      return null;
    }
  }

  double _getDuration() {
    int totalSlots = 0;
    for (var slots in widget.selectedSlots.values) {
      totalSlots += slots.length;
    }
    return (totalSlots * 30) / 60; // Convert to hours
  }

  String _getCourtNames() {
    final courtNames = <String>[];
    for (var courtId in widget.selectedSlots.keys) {
      // Extract court number from ID or use the ID
      final match = RegExp(r'Court\s*(\d+)', caseSensitive: false).firstMatch(courtId);
      if (match != null) {
        courtNames.add('Court ${match.group(1)}');
      } else {
        courtNames.add(courtId);
      }
    }
    return courtNames.join(', ');
  }

  Future<void> _confirmBooking() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the terms and conditions'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Push login without awaiting so auth rebuild doesn't leave us stuck; refresh when they return
      Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      ).then((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    setState(() => _isSubmitting = true);

    // ── Force Firebase auth token refresh before ANY Firestore call ─────────
    // After a fresh login (especially when pushed mid-flow), Firestore blocks
    // all operations internally until it gets a valid token. Calling
    // getIdToken(true) pre-warms it so every subsequent call goes through
    // immediately instead of hanging for 10-30 seconds.
    try {
      await user.getIdToken(true).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Token refresh failed or timed out — proceed anyway; Firestore will
      // retry on its own, just possibly slower.
    }

    // Profile completion check — on any error assume complete so user is never blocked
    if (await ProfileCompletionService.needsServiceProfileCompletion(user)) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RequiredProfileUpdateScreen()),
      );
      return;
    }

    // ── Pre-flight reads: each in its own try/catch so a slow Firestore on iOS
    //    never aborts the booking itself ──────────────────────────────────────

    // 1. Phone check (non-fatal — if it fails, skip the prompt and proceed)
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 8));
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final phoneNumber = userData['phone'] as String? ?? '';
        if (phoneNumber.isEmpty && mounted) {
          setState(() => _isSubmitting = false);
          final result = await _showPhoneNumberDialog(
            initialPhone: FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
          );
          if (result != true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Phone number is required to complete booking.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            return;
          }
          if (mounted) setState(() => _isSubmitting = true);
        }
      }
    } catch (_) {
      // Firestore slow / timeout — phone check skipped, proceed with booking
    }

    // 2. Sub-admin / location check (non-fatal — if it fails, assume regular user)
    bool isSubAdmin = false;
    Map<String, dynamic>? locData;
    try {
      final locationDoc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(widget.locationId)
          .get()
          .timeout(const Duration(seconds: 8));
      locData = locationDoc.data();
      final subAdmins = (locData?['subAdmins'] as List?)?.cast<String>() ?? [];
      isSubAdmin = subAdmins.contains(user.uid);
    } catch (_) {
      // Firestore slow / timeout — treat as regular user
    }

    final isMainAdmin = user.phoneNumber == '+201006500506' || user.email == 'admin@padelcore.com';
    String targetUserId = user.uid;
    if (isSubAdmin || isMainAdmin) {
      final selectedUserId = await _showUserSelectionDialog();
      if (selectedUserId != null) targetUserId = selectedUserId;
    }

    // ── Actual booking write — this is the critical path ────────────────────
    try {
      // Determine actual booking date (next day if midnight slots selected)
      final actualBookingDate = _hasMidnightSlots() 
          ? widget.selectedDate.add(const Duration(days: 1))
          : widget.selectedDate;

      // Cancellation deadline: 5 hours before the first slot start
      final slotStart = _getFirstSlotStartOn(actualBookingDate);
      var cancellationDeadline = slotStart != null
          ? slotStart.subtract(const Duration(hours: 5))
          : actualBookingDate.subtract(const Duration(hours: 5));
      final now = DateTime.now();
      if (cancellationDeadline.isBefore(now)) cancellationDeadline = now;

      final bookingData = {
        'userId': targetUserId,
        'locationId': widget.locationId,
        'locationName': widget.locationName,
        'locationAddress': widget.locationAddress,
        'date': DateFormat('yyyy-MM-dd').format(actualBookingDate),
        'selectedDate': Timestamp.fromDate(actualBookingDate),
        'courts': widget.selectedSlots.map((key, value) => MapEntry(key, value)),
        'totalCost': _finalCost,
        'pricePer30Min': widget.pricePer30Min,
        'duration': _getDuration(),
        'timeRange': _getTimeRange(),
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'cancellationDeadline': Timestamp.fromDate(cancellationDeadline),
        'bookedBy': user.uid,
        'isSubAdminBooking': isSubAdmin && targetUserId != user.uid,
        if (_appliedPromo != null && _appliedPromo!.isValid) ...{
          'promoCode': _appliedPromo!.code,
          'discountAmount': _discountAmount,
          'subtotalBeforePromo': widget.totalCost,
        },
      };

      final bookingRef = await FirebaseFirestore.instance
          .collection('courtBookings')
          .add(bookingData);

      // 3. Target user profile (for Spark API — non-fatal if it fails)
      String targetPhone = user.phoneNumber ?? '';
      String firstName = '';
      String lastName = '';
      try {
        final targetUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(targetUserId)
            .get()
            .timeout(const Duration(seconds: 6));
        final targetData = targetUserDoc.data();
        targetPhone = targetData?['phone'] as String? ??
            (targetUserId == user.uid ? user.phoneNumber : null) ?? '';
        firstName = (targetData?['firstName'] as String?)?.trim() ?? '';
        lastName = (targetData?['lastName'] as String?)?.trim() ?? '';
        if (firstName.isEmpty || lastName.isEmpty) {
          final targetName = targetData?['displayName'] as String? ?? user.displayName ?? '';
          final nameParts = targetName.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
          if (firstName.isEmpty) firstName = nameParts.isNotEmpty ? nameParts.first : '';
          if (lastName.isEmpty) lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
        }
      } catch (_) {
        // Firestore slow / timeout — use Auth display name fallback
        final nameParts = (user.displayName ?? '').trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        firstName = nameParts.isNotEmpty ? nameParts.first : '';
        lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
      }
      if (firstName.isEmpty) firstName = 'Guest';
      if (lastName.isEmpty) lastName = 'User';
      debugPrint('[Spark] Sending name: firstName="$firstName" lastName="$lastName"');

      final sparkLocationId = (locData?['sparkLocationId'] as num?)?.toInt();

      // --- Spark integration troubleshooting: log to terminal when booking ---
      debugPrint('[Spark] API configured: ${SparkApiService.instance.isEnabled}');
      debugPrint('[Spark] Location sparkLocationId: ${sparkLocationId ?? "not set (add in Firestore courtLocations doc)"}');

      List<String> sparkSlotIds = [];
      if (sparkLocationId != null) {
        sparkSlotIds = await SparkApiService.instance.resolveSlotIds(
          sparkLocationId: sparkLocationId,
          date: DateFormat('yyyy-MM-dd').format(actualBookingDate),
          selectedSlots: widget.selectedSlots,
          courtToSpaceId: _parseCourtToSpaceId(locData?['sparkCourtToSpaceId']),
        );
        final slotPreview = sparkSlotIds.isEmpty
            ? 'check sparkCourtToSpaceId and slot time match'
            : '${sparkSlotIds.take(3).join(", ")}${sparkSlotIds.length > 3 ? "..." : ""}';
        debugPrint('[Spark] Resolved slotIds: ${sparkSlotIds.length} ($slotPreview)');
      }

      final sparkResult = await SparkApiService.instance.createBooking(
        slotIds: sparkSlotIds,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: targetPhone,
      );

      if (sparkResult.isSkipped) {
        debugPrint('[Spark] Sync skipped: ${sparkResult.message}');
      } else if (sparkResult.isFailure) {
        debugPrint(
          '[Spark] API sync failed: ${sparkResult.statusCode} ${sparkResult.message}',
        );
      } else if (sparkResult.isSuccess && sparkResult.data != null) {
        final externalId = SparkApiService.externalBookingIdFromCreateResponse(sparkResult.data);
        if (externalId != null && externalId.isNotEmpty) {
          await bookingRef.update({'sparkExternalBookingId': externalId});
          debugPrint('[Spark] Success: sparkExternalBookingId=$externalId saved to Firestore');
        } else {
          debugPrint('[Spark] Success but no id in response: ${sparkResult.data}');
        }
      }

      // Log sub-admin action if applicable
      if (isSubAdmin && targetUserId != user.uid) {
        await _logSubAdminAction(
          locationId: widget.locationId,
          action: 'booking_created',
          performedBy: user.uid,
          targetUserId: targetUserId,
          bookingId: bookingRef.id,
          details: 'Booking created on behalf of user',
        );
      }

      if (mounted) {
        final screenContext = context;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Booking Confirmed!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your court booking has been confirmed successfully.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.locationName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.locationAddress,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  _getTimeRange(),
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.popUntil(screenContext, (route) => route.isFirst);
                },
                child: const Text('Back to Home'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await MapLauncher.openLocation(
                    context: screenContext,
                    lat: _locationLat,
                    lng: _locationLng,
                    addressQuery: '${widget.locationName}, ${widget.locationAddress}',
                  );
                  if (screenContext.mounted) {
                    Navigator.popUntil(screenContext, (route) => route.isFirst);
                  }
                },
                icon: const Icon(Icons.map),
                label: const Text('Get Directions'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final isFirestoreAssertion = e.toString().contains('INTERNAL ASSERTION FAILED') ||
            e.toString().contains('Unexpected state');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFirestoreAssertion
                  ? 'Booking may have gone through. Please check My Bookings; if you don\'t see it, try again.'
                  : 'Error confirming booking: $e',
            ),
            backgroundColor: isFirestoreAssertion ? Colors.orange : Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  bool _hasMidnightSlots() {
    // Midnight play end is configurable (default 4:00 AM). Slots before this in early AM are "midnight" (next-day booking).
    final endStr = widget.midnightPlayEndTime ?? '4:00 AM';
    DateTime midnightEndTime;
    try {
      midnightEndTime = DateFormat('h:mm a').parse(endStr);
    } catch (_) {
      midnightEndTime = DateTime(0, 1, 1, 4, 0); // default 4:00 AM
    }
    final endMinutes = midnightEndTime.hour * 60 + midnightEndTime.minute;

    for (var slots in widget.selectedSlots.values) {
      for (var slot in slots) {
        try {
          final slotTime = DateFormat('h:mm a').parse(slot);
          // Early AM: 12:00 AM = 0h0, 4:00 AM = 4h0. Slot is midnight if in [0, midnightEndTime)
          final slotMinutes = slotTime.hour * 60 + slotTime.minute;
          if (slotTime.hour < 6 && slotMinutes < endMinutes) {
            return true;
          }
        } catch (e) {
          // Fallback: treat known midnight-style labels as midnight
          if (slot.contains('12:00 AM') || slot.contains('12:30 AM') ||
              slot.contains('1:00 AM') || slot.contains('1:30 AM') ||
              slot.contains('2:00 AM') || slot.contains('2:30 AM') ||
              slot.contains('3:00 AM') || slot.contains('3:30 AM') ||
              (endMinutes > 4 * 60 && (slot.contains('4:00 AM') || slot.contains('4:30 AM')))) {
            return true;
          }
        }
      }
    }
    return false;
  }

  DateTime _getActualBookingDate() {
    // If midnight slots are selected, the booking is for the next day
    if (_hasMidnightSlots()) {
      return widget.selectedDate.add(const Duration(days: 1));
    }
    return widget.selectedDate;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final duration = _getDuration();
    final timeRange = _getTimeRange();
    final actualBookingDate = _getActualBookingDate();
    final isTomorrow = actualBookingDate.difference(DateTime.now()).inDays == 1;
    final hasMidnight = _hasMidnightSlots();

    // Guest: show simple "Log in to continue" so they don't hit loading/unstable flow on CONFIRM
    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        appBar: const AppHeader(title: 'Booking Confirmation'),
        bottomNavigationBar: const AppFooter(),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBookingDetailsCard(
                timeRange: timeRange,
                duration: duration,
                isTomorrow: isTomorrow,
                hasMidnight: hasMidnight,
                actualDate: actualBookingDate,
              ),
              const SizedBox(height: 32),
              const Text(
                'Log in to confirm this court booking.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ).then((_) {
                    if (mounted) setState(() {});
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Log in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: const AppHeader(title: 'Booking Confirmation'),
      bottomNavigationBar: const AppFooter(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Booking Details Card
            _buildBookingDetailsCard(
              timeRange: timeRange,
              duration: duration,
              isTomorrow: isTomorrow,
              hasMidnight: hasMidnight,
              actualDate: actualBookingDate,
            ),
            
            const SizedBox(height: 24),

            // Terms and Conditions
            _buildTermsAndConditions(),

            const SizedBox(height: 24),

            // Promo code
            _buildPromoCodeSection(),

            const SizedBox(height: 24),

            // Amount Summary
            _buildAmountSummary(),

            const SizedBox(height: 32),

            // Confirm Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _confirmBooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'CONFIRM BOOKING',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingDetailsCard({
    required String timeRange,
    required double duration,
    required bool isTomorrow,
    required bool hasMidnight,
    required DateTime actualDate,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Top Row - Logo and Location Name
          Row(
            children: [
              // Location Logo
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: widget.locationLogoUrl != null && widget.locationLogoUrl!.isNotEmpty
                    ? Image.network(
                        widget.locationLogoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Text(
                            widget.locationName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          widget.locationName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.locationName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getCourtNames(),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.locationAddress,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1),
          // Booking Details
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hasMidnight 
                                ? 'Tomorrow, ${_formatDate(actualDate)}'
                                : (isTomorrow ? 'Tomorrow' : _formatDate(widget.selectedDate)),
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            timeRange,
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          '${duration.toStringAsFixed(1)} hour${duration != 1 ? 's' : ''}',
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 1),
          // Total Amount - Larger and prominent
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                '${_finalCost.toStringAsFixed(0)} EGP',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCodeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Promo code',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promoController,
                  decoration: InputDecoration(
                    hintText: 'Enter code',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _applyPromo(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isApplyingPromo ? null : _applyPromo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isApplyingPromo
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
          if (_appliedPromo != null && _appliedPromo!.isValid) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.local_offer, size: 18, color: Colors.green.shade300),
                const SizedBox(width: 6),
                Text(
                  '${_appliedPromo!.code}: ${_appliedPromo!.message} (-${_discountAmount.toStringAsFixed(0)} EGP)',
                  style: TextStyle(color: Colors.green.shade300, fontSize: 14),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermsAndConditions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Important Notes',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please cancel at least 5 hours before the session starts.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Late cancellations or no-shows will be noted, and a fee may be applied to your next booking.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Checkbox(
              value: _agreedToTerms,
              onChanged: (value) {
                setState(() {
                  _agreedToTerms = value ?? false;
                });
              },
              activeColor: const Color(0xFF1E3A8A),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _agreedToTerms = !_agreedToTerms;
                  });
                },
                child: const Text(
                  'I agree to the terms and conditions',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAmountSummary() {
    final hasDiscount = _discountAmount > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                '${widget.totalCost.toStringAsFixed(1)} EGP',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          if (hasDiscount) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Discount${_appliedPromo?.code != null ? ' (${_appliedPromo!.code})' : ''}',
                  style: TextStyle(color: Colors.green.shade300, fontSize: 14),
                ),
                Text(
                  '-${_discountAmount.toStringAsFixed(1)} EGP',
                  style: TextStyle(color: Colors.green.shade300, fontSize: 14),
                ),
              ],
            ),
          ],
          const Divider(color: Colors.white30, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total amount',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_finalCost.toStringAsFixed(1)} EGP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  Future<String?> _showUserSelectionDialog() async {
    final phoneController = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Book Court'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Book for myself button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context, user?.uid);
                },
                icon: const Icon(Icons.person),
                label: const Text('Book for myself'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Or book on behalf of another user:'),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+201234567890',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final userId = await _findUserByPhone(phoneController.text.trim());
              if (userId != null && context.mounted) {
                Navigator.pop(context, userId);
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('User not found'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Future<String?> _findUserByPhone(String phone) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.id;
      }
      return null;
    } catch (e) {
      debugPrint('Error finding user: $e');
      return null;
    }
  }

  Future<bool?> _showPhoneNumberDialog({String initialPhone = ''}) async {
    final dialogPhoneController = TextEditingController(text: initialPhone);
    final formKey = GlobalKey<FormState>();
    
    String? validatePhone(String? value) {
      if (value == null || value.isEmpty) {
        return 'Please enter your phone number';
      }
      if (!value.startsWith('+')) {
        return 'Phone number must start with country code (e.g., +20 for Egypt)';
      }
      final digits = value.substring(1);
      if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
        return 'Phone number must contain only digits after the country code';
      }
      if (value.length < 10 || value.length > 16) {
        return 'Phone number is too short or too long. Example: +201012345678';
      }
      return null;
    }
    
    return showDialog<bool>(
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
                'Please provide your phone number to complete your booking. This is required for booking confirmations.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: dialogPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+201012345678',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: validatePhone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
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
                    Navigator.pop(dialogContext, true);
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

  Future<void> _logSubAdminAction({
    required String locationId,
    required String action,
    required String performedBy,
    required String targetUserId,
    required String bookingId,
    required String details,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('subAdminLogs').add({
        'locationId': locationId,
        'action': action,
        'performedBy': performedBy,
        'targetUserId': targetUserId,
        'bookingId': bookingId,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error logging sub-admin action: $e');
    }
  }
}
