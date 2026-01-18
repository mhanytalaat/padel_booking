import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';
import '../services/notification_service.dart';

class BookingPageScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? selectedVenue;

  const BookingPageScreen({
    super.key,
    this.initialDate,
    this.selectedVenue,
  });

  @override
  State<BookingPageScreen> createState() => _BookingPageScreenState();
}

class _BookingPageScreenState extends State<BookingPageScreen> {
  DateTime? selectedDate;
  Set<String> _expandedVenues = {};
  String? _selectedVenueFilter;

  @override
  void initState() {
    super.initState();
    // Set today's date as default
    selectedDate = widget.initialDate ?? DateTime.now();
    _selectedVenueFilter = widget.selectedVenue;
  }

  String _getDayName(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  String _getBookingKey(String venue, String time, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$dateStr|$venue|$time';
  }

  Future<void> _handleBooking(String venue, String time, String coach) async {
    // Navigate to home screen with booking context or show dialog
    final result = await _showBookingConfirmation(venue, time, coach);
    if (result != null) {
      await _processBooking(venue, time, coach, result);
    }
  }

  Future<Map<String, dynamic>?> _showBookingConfirmation(
      String venue, String time, String coach) async {
    if (selectedDate == null) return null;

    Set<String> selectedDays = {};
    bool isRecurring = false;
    String bookingType = 'Group';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Confirm Booking'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Venue: $venue'),
                    const SizedBox(height: 8),
                    Text('Date: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'),
                    const SizedBox(height: 8),
                    Text('Time: $time'),
                    const SizedBox(height: 16),
                    const Text(
                      'Booking Type:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      title: const Text('Group'),
                      subtitle: const Text('Share the court with others'),
                      value: 'Group',
                      groupValue: bookingType,
                      onChanged: (value) {
                        setState(() {
                          bookingType = value ?? 'Group';
                        });
                      },
                    ),
                    RadioListTile<String>(
                      title: const Text('Private'),
                      subtitle: const Text('Book all 4 slots for yourself'),
                      value: 'Private',
                      groupValue: bookingType,
                      onChanged: (value) {
                        setState(() {
                          bookingType = value ?? 'Private';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      title: const Text('Recurring Booking'),
                      value: isRecurring,
                      onChanged: (value) {
                        setState(() {
                          isRecurring = value ?? false;
                          if (!isRecurring) {
                            selectedDays.clear();
                          }
                        });
                      },
                    ),
                    if (isRecurring) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Select days for recurring booking:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
                          .map((day) => CheckboxListTile(
                                title: Text(day),
                                value: selectedDays.contains(day),
                                onChanged: (value) {
                                  setState(() {
                                    if (value ?? false) {
                                      selectedDays.add(day);
                                    } else {
                                      selectedDays.remove(day);
                                    }
                                  });
                                },
                                dense: true,
                              )),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (isRecurring && selectedDays.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select at least one day for recurring booking'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop({
                      'confirmed': true,
                      'bookingType': bookingType,
                      'isRecurring': isRecurring,
                      'recurringDays': selectedDays.toList(),
                    });
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _processBooking(
      String venue, String time, String coach, Map<String, dynamic> result) async {
    if (result['confirmed'] != true) return;

    final bookingType = result['bookingType'] as String? ?? 'Group';
    final isRecurring = result['isRecurring'] as bool? ?? false;
    final recurringDays = (result['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
    final isPrivate = bookingType == 'Private';

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please log in to book a slot'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final dateStr = '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}';
      final dayName = _getDayName(selectedDate!);

      final allBookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .get();

      final existingBookings = allBookings.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'pending';
        if (status != 'approved') return false;
        final isRecurring = data['isRecurring'] as bool? ?? false;
        if (isRecurring) {
          final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
          return recurringDays.contains(dayName);
        } else {
          final bookingDate = data['date'] as String? ?? '';
          return bookingDate == dateStr;
        }
      }).toList();

      int maxUsersPerSlot = 4;
      try {
        final configDoc = await FirebaseFirestore.instance
            .collection('config')
            .doc('bookingSettings')
            .get();
        if (configDoc.exists) {
          final data = configDoc.data();
          maxUsersPerSlot = data?['maxUsersPerSlot'] as int? ?? 4;
        }
      } catch (e) {}

      if (isPrivate && existingBookings.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Private booking requires all 4 slots to be available. This slot is already partially booked.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (!isPrivate && existingBookings.length >= maxUsersPerSlot) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('This slot is full ($maxUsersPerSlot/$maxUsersPerSlot users). Please select another time.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final bookingData = {
        'userId': user.uid,
        'phone': user.phoneNumber ?? '',
        'venue': venue,
        'time': time,
        'coach': coach,
        'date': dateStr,
        'bookingType': bookingType,
        'isPrivate': isPrivate,
        'isRecurring': isRecurring,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      };

      if (isRecurring) {
        bookingData['recurringDays'] = recurringDays;
        bookingData['dayOfWeek'] = dayName;
      }

      if (isPrivate) {
        for (int i = 0; i < maxUsersPerSlot; i++) {
          await FirebaseFirestore.instance.collection('bookings').add(bookingData);
        }
      } else {
        await FirebaseFirestore.instance.collection('bookings').add(bookingData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isPrivate
                ? 'Private booking request submitted! Waiting for admin approval.'
                : 'Booking request submitted! Waiting for admin approval.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error booking slot: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text('Book Session'),
        backgroundColor: const Color(0xFF0A0E27),
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          // Date selector in app bar
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              DateTime? picked = await showDatePicker(
                context: context,
                initialDate: selectedDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() {
                  selectedDate = picked;
                });
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Selected date display at the top
          if (selectedDate != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: Colors.white.withOpacity(0.8),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_getDayName(selectedDate!)} - ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          // Main content
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('bookings').snapshots(),
              builder: (context, bookingsSnapshot) {
          Map<String, int> slotCounts = {};
          if (bookingsSnapshot.hasData && selectedDate != null) {
            final dayName = _getDayName(selectedDate!);
            for (var doc in bookingsSnapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final status = data['status'] as String? ?? 'pending';
              if (status != 'approved') continue;
              final venue = data['venue'] as String? ?? '';
              final time = data['time'] as String? ?? '';
              final isRecurring = data['isRecurring'] as bool? ?? false;
              bool applies = false;
              if (isRecurring) {
                final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
                applies = recurringDays.contains(dayName);
              } else {
                final bookingDate = data['date'] as String? ?? '';
                final dateStr = '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}';
                applies = bookingDate == dateStr;
              }
              if (applies) {
                final key = _getBookingKey(venue, time, selectedDate!);
                slotCounts[key] = (slotCounts[key] ?? 0) + 1;
              }
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('slots').snapshots(),
            builder: (context, slotsSnapshot) {
              if (slotsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              Map<String, List<Map<String, String>>> venuesMap = {};
              if (slotsSnapshot.hasData) {
                for (var doc in slotsSnapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final venue = data['venue'] as String? ?? '';
                  final time = data['time'] as String? ?? '';
                  final coach = data['coach'] as String? ?? '';
                  if (venue.isNotEmpty) {
                    if (!venuesMap.containsKey(venue)) {
                      venuesMap[venue] = [];
                    }
                    venuesMap[venue]!.add({
                      'time': time,
                      'coach': coach,
                    });
                  }
                }
              }

              if (venuesMap.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_off, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'No venues available',
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                    ],
                  ),
                );
              }

              // Filter venues if venue filter is set
              final filteredVenuesMap = _selectedVenueFilter != null
                  ? Map.fromEntries(
                      venuesMap.entries.where((entry) => entry.key == _selectedVenueFilter))
                  : venuesMap;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredVenuesMap.length,
                itemBuilder: (context, index) {
                  final entry = filteredVenuesMap.entries.elementAt(index);
                  final venueName = entry.key;
                  final timeSlots = entry.value;
                  final isExpanded = _expandedVenues.contains(venueName);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF6B46C1).withOpacity(0.3),
                          const Color(0xFF1E3A8A).withOpacity(0.3),
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
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_expandedVenues.contains(venueName)) {
                                _expandedVenues.remove(venueName);
                              } else {
                                _expandedVenues.add(venueName);
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF6B46C1).withOpacity(0.5),
                                  const Color(0xFF1E3A8A).withOpacity(0.5),
                                ],
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(16),
                                topRight: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        venueName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${timeSlots.length} time slot${timeSlots.length != 1 ? 's' : ''} available',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isExpanded ? Icons.expand_less : Icons.expand_more,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0A0E27),
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                            child: Column(
                              children: _buildTimeSlots(venueName, timeSlots, slotCounts),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
          ),
          ],
        ),
    );
  }

  // Parse time string to extract start time for sorting
  DateTime? _parseTimeString(String timeStr) {
    try {
      // Extract the start time (e.g., "10:00 AM" from "10:00 AM - 11:00 AM")
      final parts = timeStr.split(' - ');
      if (parts.isEmpty) return null;
      
      final startTimeStr = parts[0].trim();
      // Parse time like "10:00 AM" or "9:00 AM"
      final timeParts = startTimeStr.split(' ');
      if (timeParts.length < 2) return null;
      
      final timeValue = timeParts[0]; // "10:00" or "9:00"
      final period = timeParts[1].toUpperCase(); // "AM" or "PM"
      
      final hourMinute = timeValue.split(':');
      if (hourMinute.length != 2) return null;
      
      int hour = int.parse(hourMinute[0]);
      final minute = int.parse(hourMinute[1]);
      
      // Convert to 24-hour format
      if (period == 'PM' && hour != 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }
      
      // Create a DateTime with today's date for comparison
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  List<Widget> _buildTimeSlots(
      String venueName, List<Map<String, String>> timeSlots, Map<String, int> slotCounts) {
    final sortedSlots = List<Map<String, String>>.from(timeSlots);
    sortedSlots.sort((a, b) {
      final timeA = a['time'] ?? '';
      final timeB = b['time'] ?? '';
      
      // Parse times for proper chronological sorting
      final parsedA = _parseTimeString(timeA);
      final parsedB = _parseTimeString(timeB);
      
      if (parsedA == null && parsedB == null) return 0;
      if (parsedA == null) return 1; // Put nulls at the end
      if (parsedB == null) return -1;
      
      return parsedA.compareTo(parsedB);
    });

    return sortedSlots.map((slot) {
      final time = slot['time'] ?? '';
      final coach = slot['coach'] ?? '';
      final bookingCount = selectedDate != null
          ? (slotCounts[_getBookingKey(venueName, time, selectedDate!)] ?? 0)
          : 0;

      return FutureBuilder<int>(
        future: _getMaxUsersPerSlot(),
        builder: (context, maxSnapshot) {
          int maxUsersPerSlot = 4;
          if (maxSnapshot.hasData) {
            maxUsersPerSlot = maxSnapshot.data!;
          }

          final isFull = bookingCount >= maxUsersPerSlot;
          final spotsAvailable = maxUsersPerSlot - bookingCount;

          List<Color> gradientColors;
          String statusText;
          Color statusColor;

          if (isFull) {
            gradientColors = [const Color(0xFF1A1F3A), const Color(0xFF2D1B3D)];
            statusText = 'Booked';
            statusColor = Colors.red;
          } else if (spotsAvailable <= 1 && spotsAvailable > 0) {
            gradientColors = [const Color(0xFF1E3A8A), const Color(0xFFFF9800)];
            statusText = 'Few Spots Left';
            statusColor = Colors.orange;
          } else if (bookingCount >= maxUsersPerSlot * 0.7) {
            gradientColors = [const Color(0xFF6B46C1), const Color(0xFF9333EA)];
            statusText = 'Popular';
            statusColor = Colors.purple;
          } else {
            gradientColors = [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)];
            statusText = 'Book';
            statusColor = Colors.green;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
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
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedDate != null
                            ? (isFull
                                ? 'Full ($bookingCount/$maxUsersPerSlot)'
                                : '$spotsAvailable spot${spotsAvailable != 1 ? 's' : ''} available ($bookingCount/$maxUsersPerSlot)')
                            : 'Select a date to see availability',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isFull)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: statusColor,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    if (!isFull)
                      ElevatedButton(
                        onPressed: () => _handleBooking(venueName, time, coach),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Book',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }).toList();
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
}
