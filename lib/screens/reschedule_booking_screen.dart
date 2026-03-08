import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../widgets/app_header.dart';

/// Screen for users to request a new date/time for an existing training booking.
/// Creates a new pending booking linked to the original; admin approves the new one
/// and the original is then cancelled.
class RescheduleBookingScreen extends StatefulWidget {
  final String originalBookingId;
  final String currentVenue;
  final String currentTime;
  final String currentDate;
  final String currentCoach;
  final String userId;
  /// For recurring private (4 sessions): allow user to pick which of the 4 sessions to reschedule.
  final bool isRecurring;
  final List<String> recurringDays;
  final bool isPrivate;
  /// True when rescheduling an approved bundle session (Session 1, 2, 3, 4). Admin approval updates that session's slot.
  final bool isBundleSession;
  final String? bundleSessionId;
  final String? bundleId;

  const RescheduleBookingScreen({
    super.key,
    required this.originalBookingId,
    required this.currentVenue,
    required this.currentTime,
    required this.currentDate,
    required this.currentCoach,
    required this.userId,
    this.isRecurring = false,
    this.recurringDays = const [],
    this.isPrivate = false,
    this.isBundleSession = false,
    this.bundleSessionId,
    this.bundleId,
  });

  @override
  State<RescheduleBookingScreen> createState() => _RescheduleBookingScreenState();
}

class _RescheduleBookingScreenState extends State<RescheduleBookingScreen> {
  DateTime? _selectedDate;
  bool _submitting = false;
  /// When rescheduling one of 4 recurring private sessions, which occurrence date was selected.
  String? _selectedOccurrenceDate;

  String _getDayName(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  /// Next 4 occurrence dates for recurring (day of week in recurringDays), starting from startDateStr.
  List<String> _getNext4OccurrenceDates(String startDateStr, List<String> recurringDays) {
    if (recurringDays.isEmpty) return [];
    final start = _parseDateFromStr(startDateStr);
    if (start == null) return [];
    final weekdays = <int>{};
    const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    for (final d in recurringDays) {
      final i = dayNames.indexWhere((n) => n.toLowerCase() == d.trim().toLowerCase());
      if (i >= 0) weekdays.add(i + 1);
    }
    if (weekdays.isEmpty) return [];
    final out = <String>[];
    var d = DateTime(start.year, start.month, start.day);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    while (out.length < 4) {
      if (d.isAfter(todayDate) || d.isAtSameMomentAs(todayDate)) {
        if (weekdays.contains(d.weekday)) {
          out.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
        }
      }
      d = d.add(const Duration(days: 1));
      if (d.difference(start).inDays > 365) break;
    }
    return out;
  }

  DateTime? _parseDateFromStr(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    } catch (e) {}
    return null;
  }

  String _getBookingKey(String venue, String time, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$dateStr|$venue|$time';
  }

  Future<int> _getMaxUsersPerSlot() async {
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('bookingSettings')
          .get();
      if (configDoc.exists) {
        final data = configDoc.data();
        return data?['maxUsersPerSlot'] as int? ?? 4;
      }
    } catch (e) {}
    return 4;
  }

  Future<bool> _isSlotBlocked(String venue, String time, String dayName) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('blockedSlots')
        .where('venue', isEqualTo: venue)
        .where('time', isEqualTo: time)
        .where('day', isEqualTo: dayName)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<Map<String, int>> _getSlotCountsForDate(DateTime date) async {
    final slotCounts = <String, int>{};
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final bookings = await FirebaseFirestore.instance.collection('bookings').get();
    for (var doc in bookings.docs) {
      final data = doc.data();
      if ((data['status'] as String? ?? 'pending') == 'rejected') continue;
      if ((data['status'] as String? ?? 'pending') == 'cancelled') continue;
      if ((data['date'] as String? ?? '') != dateStr) continue;
      final key = _getBookingKey(
        data['venue'] as String? ?? '',
        data['time'] as String? ?? '',
        date,
      );
      slotCounts[key] = (slotCounts[key] ?? 0) + (data['slotsReserved'] as int? ?? 1);
    }
    return slotCounts;
  }

  Future<void> _submitReschedule({
    required String venue,
    required String time,
    required String coach,
  }) async {
    if (_selectedDate == null) return;
    final dateStr = '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
    final dayName = _getDayName(_selectedDate!);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm reschedule request'),
        content: Text(
          'Request to move your booking to:\n\n$venue\n$time\n${DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!)}\nCoach: $coach\n\nAdmin will review and approve the new time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit request', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != widget.userId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in again'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final phone = userData?['phone'] as String? ?? user.phoneNumber ?? '';
      final firstName = userData?['firstName'] as String? ?? '';
      final lastName = userData?['lastName'] as String? ?? '';
      final fullName = (userData?['fullName'] as String?)?.trim();
      final userName = (fullName?.isNotEmpty == true)
          ? fullName!
          : '$firstName $lastName'.trim().isEmpty
              ? (user.phoneNumber ?? 'User')
              : '$firstName $lastName'.trim();

      final maxUsersPerSlot = await _getMaxUsersPerSlot();
      final existingBookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .get();

      int totalReserved = 0;
      for (var doc in existingBookings.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'pending';
        if (status == 'rejected') continue;
        final bookDate = data['date'] as String? ?? '';
        if (bookDate == dateStr) {
          totalReserved += data['slotsReserved'] as int? ?? 1;
        }
      }

      if (totalReserved >= maxUsersPerSlot) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This slot is no longer available. Please choose another.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final bookingData = <String, dynamic>{
        'userId': user.uid,
        'phone': phone,
        'venue': venue,
        'time': time,
        'coach': coach,
        'date': dateStr,
        'bookingType': 'Training',
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'rescheduleOf': widget.originalBookingId,
        'slotsReserved': 1,
      };
      final bool isRecurringReschedule = widget.isRecurring && widget.isPrivate && _selectedOccurrenceDate != null;
      if (isRecurringReschedule) {
        bookingData['rescheduleOccurrenceDate'] = _selectedOccurrenceDate;
        bookingData['isRescheduleOfRecurring'] = true;
      }
      if (widget.isBundleSession && widget.bundleSessionId != null) {
        bookingData['rescheduleOfBundleSessionId'] = widget.bundleSessionId;
        if (widget.bundleId != null) bookingData['bundleId'] = widget.bundleId;
      }
      // So admin can show old vs new timing in Approvals
      final oldDateForStorage = isRecurringReschedule && _selectedOccurrenceDate != null
          ? _selectedOccurrenceDate!
          : widget.currentDate;
      bookingData['oldDate'] = oldDateForStorage;
      bookingData['oldTime'] = widget.currentTime;

      final ref = await FirebaseFirestore.instance.collection('bookings').add(bookingData);

      // For single-session reschedule (booking), hide original until admin decides. For recurring (one of 4) or bundle session, keep original visible.
      final bool hideOriginal = !isRecurringReschedule && !widget.isBundleSession;
      if (hideOriginal && widget.originalBookingId.isNotEmpty) {
        try {
          final orig = await FirebaseFirestore.instance.collection('bookings').doc(widget.originalBookingId).get();
          if (orig.exists) {
            await FirebaseFirestore.instance
                .collection('bookings')
                .doc(widget.originalBookingId)
                .update({'pendingRescheduleBookingId': ref.id});
          }
        } catch (_) {}
      }

      final oldDateForNotification = isRecurringReschedule && _selectedOccurrenceDate != null
          ? _selectedOccurrenceDate!
          : widget.currentDate;
      await NotificationService().notifyAdminForRescheduleRequest(
        bookingId: ref.id,
        originalBookingId: widget.originalBookingId,
        userId: user.uid,
        userName: userName,
        phone: phone,
        venue: venue,
        time: time,
        date: dateStr,
        oldDate: oldDateForNotification,
        oldTime: widget.currentTime,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reschedule request submitted. Admin will approve the new time.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting reschedule: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _formatCurrentDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        return DateFormat('EEEE, MMM d, yyyy').format(d);
      }
    } catch (e) {}
    return dateStr;
  }

  /// Parse time string (e.g. "9:00 AM - 10:00 AM") to sort slots morning to evening.
  DateTime? _parseTimeString(String timeStr) {
    try {
      final parts = timeStr.split(' - ');
      if (parts.isEmpty) return null;
      final startTimeStr = parts[0].trim();
      final timeParts = startTimeStr.split(' ');
      if (timeParts.length < 2) return null;
      final timeValue = timeParts[0];
      final period = timeParts[1].toUpperCase();
      final hourMinute = timeValue.split(':');
      if (hourMinute.length != 2) return null;
      int hour = int.parse(hourMinute[0]);
      final minute = int.parse(hourMinute[1]);
      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  /// Sort time slots chronologically (morning to evening).
  List<Map<String, String>> _sortSlotsByTime(List<Map<String, String>> slots) {
    final sorted = List<Map<String, String>>.from(slots);
    sorted.sort((a, b) {
      final timeA = a['time'] ?? '';
      final timeB = b['time'] ?? '';
      final parsedA = _parseTimeString(timeA);
      final parsedB = _parseTimeString(timeB);
      if (parsedA == null && parsedB == null) return 0;
      if (parsedA == null) return 1;
      if (parsedB == null) return -1;
      return parsedA.compareTo(parsedB);
    });
    return sorted;
  }

  static const Color _bgDark = Color(0xFF0A0E27);
  static const Color _cardGradientStart = Color(0xFF6B46C1);
  static const Color _cardGradientEnd = Color(0xFF1E3A8A);

  @override
  Widget build(BuildContext context) {
    final bool showOccurrenceStep = widget.isRecurring &&
        widget.isPrivate &&
        widget.recurringDays.isNotEmpty;
    final occurrenceDates = showOccurrenceStep
        ? _getNext4OccurrenceDates(widget.currentDate, widget.recurringDays)
        : <String>[];
    final bool showOccurrencePicker = showOccurrenceStep &&
        occurrenceDates.isNotEmpty &&
        _selectedOccurrenceDate == null;

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: const AppHeader(title: 'Reschedule Booking'),
      body: _submitting
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current booking card – same theme as booking page
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _cardGradientStart.withOpacity(0.4),
                          _cardGradientEnd.withOpacity(0.4),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current booking',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.currentVenue,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.currentTime} · ${_formatCurrentDate(widget.currentDate)}',
                            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)),
                          ),
                          Text(
                            'Coach: ${widget.currentCoach}',
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.75)),
                          ),
                          if (showOccurrenceStep) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Private recurring · ${occurrenceDates.length} sessions',
                              style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Step 1 for recurring private: which session to reschedule
                  if (showOccurrencePicker) ...[
                    Text(
                      'Select which session to reschedule',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    ...occurrenceDates.asMap().entries.map((e) {
                      final sessionNum = e.key + 1;
                      final dateStr = e.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              _cardGradientEnd.withOpacity(0.5),
                              const Color(0xFF3B82F6).withOpacity(0.5),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          title: Text(
                            'Session $sessionNum · ${_formatCurrentDate(dateStr)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            '${widget.currentTime} · ${widget.currentVenue}',
                            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                          onTap: () => setState(() => _selectedOccurrenceDate = dateStr),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                  if (!showOccurrencePicker) ...[
                  Text(
                    'Choose new date and time',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: _cardGradientEnd.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      title: Text(
                        _selectedDate == null
                            ? 'Select date'
                            : DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                      trailing: const Icon(Icons.calendar_today, color: Colors.white),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null && mounted) setState(() => _selectedDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('slots').snapshots(),
                    builder: (context, slotsSnapshot) {
                      if (slotsSnapshot.connectionState == ConnectionState.waiting) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: CircularProgressIndicator(color: Colors.white.withOpacity(0.9)),
                          ),
                        );
                      }
                      if (slotsSnapshot.hasError || !slotsSnapshot.hasData) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load slots. Try again later.',
                            style: TextStyle(color: Colors.white.withOpacity(0.8)),
                          ),
                        );
                      }
                      Map<String, List<Map<String, String>>> venuesMap = {};
                      for (var doc in slotsSnapshot.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final venue = data['venue'] as String? ?? '';
                        final time = data['time'] as String? ?? '';
                        final coach = data['coach'] as String? ?? '';
                        if (venue.isNotEmpty) {
                          venuesMap.putIfAbsent(venue, () => []).add({'time': time, 'coach': coach});
                        }
                      }
                      // Sort each venue's slots morning to evening
                      for (final key in venuesMap.keys.toList()) {
                        venuesMap[key] = _sortSlotsByTime(venuesMap[key]!);
                      }
                      if (venuesMap.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No venues available.',
                            style: TextStyle(color: Colors.white.withOpacity(0.8)),
                          ),
                        );
                      }
                      return _selectedDate == null
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Select a date above to see available slots.',
                                style: TextStyle(color: Colors.white.withOpacity(0.8)),
                              ),
                            )
                          : FutureBuilder<Map<String, int>>(
                              key: ValueKey(_selectedDate),
                              future: _getSlotCountsForDate(_selectedDate!),
                              builder: (context, countSnapshot) {
                                final slotCounts = countSnapshot.data ?? {};
                                final dayName = _getDayName(_selectedDate!);
                                const maxUsersPerSlot = 4;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: venuesMap.entries.map((entry) {
                                    final venueName = entry.key;
                                    final timeSlots = entry.value;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            _cardGradientStart.withOpacity(0.3),
                                            _cardGradientEnd.withOpacity(0.3),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.3),
                                            blurRadius: 10,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                                            child: Row(
                                              children: [
                                                Icon(Icons.location_on, color: Colors.white, size: 22),
                                                const SizedBox(width: 8),
                                                Text(
                                                  venueName,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                            child: Column(
                                              children: timeSlots.map<Widget>((slot) {
                                                final time = slot['time'] ?? '';
                                                final coach = slot['coach'] ?? '';
                                                final key = _getBookingKey(venueName, time, _selectedDate!);
                                                final count = slotCounts[key] ?? 0;
                                                return FutureBuilder<bool>(
                                                  future: _isSlotBlocked(venueName, time, dayName),
                                                  builder: (context, blockedSnap) {
                                                    final blocked = blockedSnap.data ?? false;
                                                    final full = blocked || count >= maxUsersPerSlot;
                                                    return Container(
                                                      margin: const EdgeInsets.only(bottom: 12),
                                                      padding: const EdgeInsets.all(16),
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          begin: Alignment.topLeft,
                                                          end: Alignment.bottomRight,
                                                          colors: full
                                                              ? [
                                                                  const Color(0xFF1A1F3A),
                                                                  const Color(0xFF2D1B3D),
                                                                ]
                                                              : [
                                                                  _cardGradientEnd,
                                                                  const Color(0xFF3B82F6),
                                                                ],
                                                        ),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                Text(
                                                                  time,
                                                                  style: const TextStyle(
                                                                      fontSize: 16,
                                                                      fontWeight: FontWeight.bold,
                                                                      color: Colors.white),
                                                                ),
                                                                const SizedBox(height: 4),
                                                                Text(
                                                                  coach,
                                                                  style: TextStyle(
                                                                      fontSize: 13,
                                                                      color: Colors.white.withOpacity(0.9)),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: full
                                                                ? null
                                                                : () => _submitReschedule(
                                                                      venue: venueName,
                                                                      time: time,
                                                                      coach: coach,
                                                                    ),
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor: Colors.green,
                                                              foregroundColor: Colors.white,
                                                            ),
                                                            child: const Text('Select'),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            );
                    },
                  ),
                  ], // end if (!showOccurrencePicker)
                ],
              ),
            ),
    );
  }
}
