import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class CourtBookingConfirmationScreen extends StatefulWidget {
  final String locationId;
  final String locationName;
  final String locationAddress;
  final DateTime selectedDate;
  final Map<String, List<String>> selectedSlots; // courtId -> [time slots]
  final double totalCost;
  final double pricePer30Min;

  const CourtBookingConfirmationScreen({
    super.key,
    required this.locationId,
    required this.locationName,
    required this.locationAddress,
    required this.selectedDate,
    required this.selectedSlots,
    required this.totalCost,
    required this.pricePer30Min,
  });

  @override
  State<CourtBookingConfirmationScreen> createState() => _CourtBookingConfirmationScreenState();
}

class _CourtBookingConfirmationScreenState extends State<CourtBookingConfirmationScreen> {
  bool _agreedToTerms = false;
  bool _isSubmitting = false;

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

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Check if user is sub-admin for this location
      final locationDoc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(widget.locationId)
          .get();
      
      final subAdmins = (locationDoc.data()?['subAdmins'] as List?)?.cast<String>() ?? [];
      final isSubAdmin = subAdmins.contains(user.uid);
      final isMainAdmin = user.phoneNumber == '+201006500506' || user.email == 'admin@padelcore.com';
      
      String? targetUserId = user.uid; // Default to current user
      
      // If sub-admin, allow booking on behalf of another user or themselves
      if (isSubAdmin || isMainAdmin) {
        final selectedUserId = await _showUserSelectionDialog();
        if (selectedUserId != null) {
          targetUserId = selectedUserId;
        }
        // If dialog returns null (cancelled), targetUserId remains as user.uid (book for themselves)
      }

      // Determine actual booking date (next day if midnight slots selected)
      final actualBookingDate = _hasMidnightSlots() 
          ? widget.selectedDate.add(const Duration(days: 1))
          : widget.selectedDate;
      
      // Create booking document
      final bookingData = {
        'userId': targetUserId,
        'locationId': widget.locationId,
        'locationName': widget.locationName,
        'locationAddress': widget.locationAddress,
        'date': DateFormat('yyyy-MM-dd').format(actualBookingDate),
        'selectedDate': Timestamp.fromDate(actualBookingDate),
        'courts': widget.selectedSlots.map((key, value) => MapEntry(key, value)),
        'totalCost': widget.totalCost,
        'pricePer30Min': widget.pricePer30Min,
        'duration': _getDuration(),
        'timeRange': _getTimeRange(),
        'status': 'confirmed', // Court bookings are confirmed immediately, no admin approval needed
        'createdAt': FieldValue.serverTimestamp(),
        'cancellationDeadline': Timestamp.fromDate(
          actualBookingDate.subtract(const Duration(hours: 5)),
        ),
        'bookedBy': user.uid, // Track who created the booking
        'isSubAdminBooking': isSubAdmin && targetUserId != user.uid,
      };

      final bookingRef = await FirebaseFirestore.instance
          .collection('courtBookings')
          .add(bookingData);

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking confirmed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming booking: $e'),
            backgroundColor: Colors.red,
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
    // Check if any selected slots are midnight slots (12:00 AM - 4:00 AM)
    for (var slots in widget.selectedSlots.values) {
      for (var slot in slots) {
        try {
          final format = DateFormat('h:mm a');
          final slotTime = format.parse(slot);
          // Midnight slots are 12:00 AM (hour 0) to 4:00 AM (hour 4)
          if (slotTime.hour >= 0 && slotTime.hour < 4) {
            return true;
          }
        } catch (e) {
          // If parsing fails, check if it contains "12:00 AM" or "AM" with hour 0-3
          if (slot.contains('12:00 AM') || slot.contains('12:30 AM') || 
              slot.contains('1:00 AM') || slot.contains('1:30 AM') ||
              slot.contains('2:00 AM') || slot.contains('2:30 AM') ||
              slot.contains('3:00 AM') || slot.contains('3:30 AM')) {
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
    final duration = _getDuration();
    final timeRange = _getTimeRange();
    final actualBookingDate = _getActualBookingDate();
    final isTomorrow = actualBookingDate.difference(DateTime.now()).inDays == 1;
    final hasMidnight = _hasMidnightSlots();

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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Location Logo
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                widget.locationName.split(' ').first,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Booking Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getCourtNames(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      hasMidnight 
                          ? 'Tomorrow, ${_formatDate(actualDate)}'
                          : (isTomorrow ? 'Tomorrow' : _formatDate(widget.selectedDate)),
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      timeRange,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '${duration.toStringAsFixed(1)} hours',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Total Cost
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${widget.totalCost.toStringAsFixed(1)} EGP',
                style: const TextStyle(
                  fontSize: 20,
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
                'Total amount',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                '${widget.totalCost.toStringAsFixed(1)} EGP',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
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
                '${widget.totalCost.toStringAsFixed(1)} EGP',
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
