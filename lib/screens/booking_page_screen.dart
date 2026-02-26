import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';
import '../utils/map_launcher.dart';
import 'required_profile_update_screen.dart';
import '../services/notification_service.dart';
import '../services/profile_completion_service.dart';
import '../services/bundle_service.dart';
import '../models/bundle_model.dart';
import '../widgets/bundle_selector_dialog.dart';
import '../utils/auth_required.dart';

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

  // Check if slot is blocked for the selected day (using StreamBuilder for real-time updates)
  Stream<bool> _isSlotBlockedStream(String venue, String time, String dayName) {
    return FirebaseFirestore.instance
        .collection('blockedSlots')
        .where('venue', isEqualTo: venue)
        .where('time', isEqualTo: time)
        .where('day', isEqualTo: dayName)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty);
  }

  String _getBookingKey(String venue, String time, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$dateStr|$venue|$time';
  }

  Future<void> _handleBooking(String venue, String time, String coach) async {
    // Require login only when user tries to book (guests can view the page)
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final loggedIn = await requireLogin(context);
      if (!loggedIn || !mounted) return;
      user = FirebaseAuth.instance.currentUser;
    }
    final result = await _showBookingConfirmation(venue, time, coach);
    if (result != null) {
      if (user != null &&
          await ProfileCompletionService.needsServiceProfileCompletion(user)) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RequiredProfileUpdateScreen()),
          );
        }
        return;
      }
      await _processBooking(venue, time, coach, result);
    }
  }

  // Check if user has phone number, if not prompt them to enter it
  Future<String?> _checkAndGetPhoneNumber(String userId) async {
    try {
      // Get user document from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        final phone = userData['phone'] as String? ?? '';
        
        // If phone exists and is not empty, return it
        if (phone.isNotEmpty) {
          return phone;
        }
      }

      // Phone is missing, show dialog to enter it (pre-fill from Firebase Auth if available)
      if (!mounted) return null;
      String initialPhone = '';
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        initialPhone = data?['phone'] as String? ?? '';
      }
      if (initialPhone.isEmpty) {
        initialPhone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
      }
      final phoneController = TextEditingController(text: initialPhone);
      final formKey = GlobalKey<FormState>();

      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false, // User must provide phone number
        builder: (context) => AlertDialog(
          title: const Text('Phone Number Required'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please enter your phone number to complete the booking.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+1234567890',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Phone number is required';
                    }
                    // Basic validation - at least 10 digits
                    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
                    if (digitsOnly.length < 10) {
                      return 'Please enter a valid phone number';
                    }
                    return null;
                  },
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
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, phoneController.text.trim());
                }
              },
              child: const Text('Save & Continue'),
            ),
          ],
        ),
      );

      if (result == null || result.isEmpty) {
        // User cancelled
        return null;
      }

      // Save phone number to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({'phone': result}, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone number saved successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }

      return result;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking phone number: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<Map<String, dynamic>?> _showBookingConfirmation(
      String venue, String time, String coach) async {
    if (selectedDate == null) return null;

    final dayName = _getDayName(selectedDate!);
    
    // Get user's active bundles
    final user = FirebaseAuth.instance.currentUser;
    List<TrainingBundle> activeBundles = [];
    if (user != null) {
      activeBundles = await BundleService().getActiveBundlesForUser(user.uid);
    }

    // STEP 1: Show bundle selector dialog directly
    Map<String, dynamic>? bundleConfig;
    String? selectedBundleId;
    
    // Open bundle selector dialog directly
    final dateStr = '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}';
    bundleConfig = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => BundleSelectorDialog(
        venue: venue,
        date: dateStr,
        day: dayName,
        time: time,
      ),
    );

    // If user cancelled, return null
    if (bundleConfig == null) return null;

    // STEP 2: Extract schedule from bundle config (already set in dialog)
    final dayTimeSchedule = bundleConfig['dayTimeSchedule'] as Map<String, String>? ?? {};
    final sessions = bundleConfig['sessions'] as int;
    final isRecurring = sessions > 1 && dayTimeSchedule.isNotEmpty;
    
    // STEP 2.5: Check if ANY day/time in the schedule is blocked
    for (var entry in dayTimeSchedule.entries) {
      final dayToCheck = entry.key;
      final timeToCheck = entry.value;
      
      final blockedCheck = await FirebaseFirestore.instance
          .collection('blockedSlots')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: timeToCheck)
          .where('day', isEqualTo: dayToCheck)
          .get();
      
      if (blockedCheck.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$dayToCheck at $timeToCheck has been blocked by admin'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
    }
    
    // Convert map to lists for backward compatibility
    Set<String> selectedDays = dayTimeSchedule.keys.toSet();

    // STEP 3: Show final confirmation with schedule
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Booking'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Training Details:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Venue: $venue')),
                    TextButton.icon(
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('Map', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      onPressed: () async {
                        try {
                          final locationSnapshot = await FirebaseFirestore.instance
                              .collection('courtLocations')
                              .where('name', isEqualTo: venue)
                              .limit(1)
                              .get();
                          if (!context.mounted) return;
                          if (locationSnapshot.docs.isNotEmpty) {
                            final locationData = locationSnapshot.docs.first.data();
                            final lat = (locationData['lat'] as num?)?.toDouble();
                            final lng = (locationData['lng'] as num?)?.toDouble();
                            final address = locationData['address'] as String? ?? venue;
                            await MapLauncher.openLocation(
                              context: context,
                              lat: lat,
                              lng: lng,
                              addressQuery: '$venue, $address',
                            );
                          } else {
                            // Fallback: open map with venue name as search (e.g. name mismatch in Firestore)
                            await MapLauncher.openLocation(
                              context: context,
                              addressQuery: venue,
                            );
                          }
                        } catch (e) {
                          debugPrint('Error opening map: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Could not open map: $e'), backgroundColor: Colors.orange),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
                Text('Time: $time'),
                Text('Coach: $coach'),
                const SizedBox(height: 16),
                const Text(
                  'Bundle:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (bundleConfig != null) ...[
                  Text('${bundleConfig!['sessions']} Sessions - ${bundleConfig!['players']} Player${bundleConfig!['players'] > 1 ? 's' : ''}'),
                  Text('Price: ${bundleConfig!['price']} EGP'),
                ] else if (selectedBundleId != null) ...[
                  FutureBuilder<TrainingBundle?>(
                    future: BundleService().getBundleById(selectedBundleId!),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final bundle = snapshot.data!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${bundle.bundleType} Sessions - ${bundle.playerCount} Player${bundle.playerCount > 1 ? 's' : ''}'),
                            Text('Remaining: ${bundle.remainingSessions} sessions'),
                          ],
                        );
                      }
                      return const Text('Loading bundle info...');
                    },
                  ),
                ],
                if (isRecurring) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Schedule:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...dayTimeSchedule.entries.map((entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${entry.key}: ${entry.value}'),
                        )),
                        const SizedBox(height: 8),
                        Text('Start date: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'),
                        if (bundleConfig != null) ...[
                          Text('Duration: ${bundleConfig!['sessions'] == 4 ? '4 weeks' : '4 weeks'}'),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text('Single session on: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm Booking'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return null;

    return {
      'confirmed': true,
      'isRecurring': isRecurring,
      'recurringDays': selectedDays.toList(),
      'dayTimeSchedule': dayTimeSchedule, // Map of day -> time
      'bundleConfig': bundleConfig,
      'selectedBundleId': selectedBundleId,
    };
  }

  Future<void> _showRecurringDaysTimeDialog(Map<String, String> dayTimeSchedule, int sessions, String venue) async {
    final daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final availableTimes = [
      '8:00 AM - 9:00 AM', '9:00 AM - 10:00 AM', '10:00 AM - 11:00 AM', '11:00 AM - 12:00 PM',
      '12:00 PM - 1:00 PM', '1:00 PM - 2:00 PM', '2:00 PM - 3:00 PM', '3:00 PM - 4:00 PM',
      '4:00 PM - 5:00 PM', '5:00 PM - 6:00 PM', '6:00 PM - 7:00 PM', '7:00 PM - 8:00 PM',
      '8:00 PM - 9:00 PM', '9:00 PM - 10:00 PM', '10:00 PM - 11:00 PM',
    ];
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final currentDays = dayTimeSchedule.keys.toList();
            
            return AlertDialog(
              title: Text('Select Training Schedule (${sessions} sessions)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select ${sessions == 4 ? '1-2' : '2-3'} days per week with specific times:',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    
                    // Show current schedule
                    if (currentDays.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Current Schedule:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            ...currentDays.map((day) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('$day: ${dayTimeSchedule[day]}'),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      setState(() {
                                        dayTimeSchedule.remove(day);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    
                    // Add new day/time
                    const Text('Add More Days:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...daysOfWeek.where((day) => !dayTimeSchedule.containsKey(day)).map((day) => 
                      ExpansionTile(
                        title: Text(day),
                        children: availableTimes.map((timeSlot) => ListTile(
                          title: Text(timeSlot, style: const TextStyle(fontSize: 14)),
                          onTap: () {
                            // Check max days
                            if ((sessions == 4 && dayTimeSchedule.length >= 2) ||
                                (sessions == 8 && dayTimeSchedule.length >= 3)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Maximum ${sessions == 4 ? '2' : '3'} days allowed'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            setState(() {
                              dayTimeSchedule[day] = timeSlot;
                            });
                          },
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final minDays = sessions == 4 ? 1 : 2;
                    if (dayTimeSchedule.length < minDays) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Please select at least $minDays day(s) for ${sessions} sessions'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _processBooking(
      String venue, String time, String coach, Map<String, dynamic> result) async {
    if (result['confirmed'] != true) return;

    final isRecurring = result['isRecurring'] as bool? ?? false;
    final recurringDays = (result['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
    final dayTimeSchedule = result['dayTimeSchedule'] as Map<String, String>? ?? {};
    final Map<String, dynamic>? bundleConfig = result['bundleConfig'];
    final String? selectedBundleId = result['selectedBundleId'];
    
    // Determine if private/group based on bundle config or player count
    int playerCount = 1;
    bool isPrivate = false;
    
    if (bundleConfig != null) {
      playerCount = bundleConfig['players'] as int;
      // Get isPrivate from bundle config (1 session always private, 4/8 sessions user choice)
      isPrivate = bundleConfig['isPrivate'] as bool? ?? false;
    } else if (selectedBundleId != null) {
      // Get player count from existing bundle
      final bundle = await BundleService().getBundleById(selectedBundleId);
      if (bundle != null) {
        playerCount = bundle.playerCount;
        // For existing bundles, use previous logic
        isPrivate = playerCount == 1;
      }
    }
    
    final bookingType = 'Bundle'; // All bookings through this flow are bundles

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

      // Check if user has phone number
      final userPhone = await _checkAndGetPhoneNumber(user.uid);
      if (userPhone == null) {
        // User cancelled or didn't provide phone number
        return;
      }

      final dateStr = '${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}';
      final dayName = _getDayName(selectedDate!);

      // Check if this time slot is blocked by admin
      final blockedSlotsQuery = await FirebaseFirestore.instance
          .collection('blockedSlots')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .where('day', isEqualTo: dayName)
          .get();
      
      if (blockedSlotsQuery.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This time slot has been blocked by admin'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final allBookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .get();

      final existingBookings = allBookings.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'pending';
        // Count both pending and approved bookings (not rejected)
        if (status == 'rejected') return false;
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

      // Calculate total slots reserved (sum of slotsReserved field)
      int totalSlotsReserved = 0;
      for (var booking in existingBookings) {
        final data = booking.data() as Map<String, dynamic>;
        final slotsReserved = data['slotsReserved'] as int? ?? 1; // Default to 1 for old bookings
        totalSlotsReserved += slotsReserved;
      }

      // Check if requesting private booking when slots are partially booked
      if (isPrivate && totalSlotsReserved > 0) {
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

      // Check if slots are full
      final slotsNeeded = isPrivate ? maxUsersPerSlot : playerCount;
      if (totalSlotsReserved + slotsNeeded > maxUsersPerSlot) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Not enough slots available. ${maxUsersPerSlot - totalSlotsReserved} slot(s) remaining.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final bookingData = {
        'userId': user.uid,
        'phone': userPhone, // Use validated phone number
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

      // Add slots reserved field (maxUsersPerSlot for private, playerCount for shared)
      bookingData['slotsReserved'] = isPrivate ? maxUsersPerSlot : playerCount;

      // Get user name for notification
      final userProfile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userProfile.data() as Map<String, dynamic>?;
      final firstName = userData?['firstName'] as String? ?? '';
      final lastName = userData?['lastName'] as String? ?? '';
      final userName = '$firstName $lastName'.trim().isEmpty 
          ? (user.phoneNumber ?? 'User') 
          : '$firstName $lastName';

      // Handle bundle bookings (all bookings are bundle-based now)
      String? bundleId;
      
      if (bundleConfig != null) {
          // Request new bundle with schedule details
          String scheduleNotes;
          if (isRecurring && dayTimeSchedule.isNotEmpty) {
            // Build schedule from day/time map
            final scheduleLines = dayTimeSchedule.entries.map((e) => '${e.key}: ${e.value}').join('\n');
            scheduleNotes = 'Recurring Schedule:\n$scheduleLines\nVenue: $venue\nCoach: $coach\nStart Date: $dateStr';
          } else {
            scheduleNotes = 'Single session at $venue on $dateStr at $time with $coach';
          }
          
          bundleId = await BundleService().createBundleRequest(
            userId: user.uid,
            userName: userName,
            userPhone: userPhone,
            bundleType: bundleConfig['sessions'],
            playerCount: bundleConfig['players'],
            notes: scheduleNotes,
            scheduleDetails: {
              'venue': venue,
              'coach': coach,
              'startDate': dateStr,
              'time': time,
              'isRecurring': isRecurring,
              'recurringDays': recurringDays,
              'dayTimeSchedule': dayTimeSchedule, // Include full schedule
            },
          );
          
          // Notify admin about bundle request
          await NotificationService().notifyAdminForBundleRequest(
            bundleId: bundleId,
            userId: user.uid,
            userName: userName,
            phone: userPhone,
            sessions: bundleConfig['sessions'],
            players: bundleConfig['players'],
            price: bundleConfig['price'].toDouble(),
          );
        } else if (selectedBundleId != null) {
          // Use existing bundle
          bundleId = selectedBundleId;
        }

      // Add bundle info to booking data (only if bundleId exists)
      if (bundleId != null) {
        bookingData['bundleId'] = bundleId;
        bookingData['isBundle'] = true;
      }

      // Create single booking request
      final bookingRef = await FirebaseFirestore.instance.collection('bookings').add(bookingData);

      // If using existing bundle, create bundle session record
      if (bundleId != null && result['selectedBundleId'] != null) {
        final bundle = await BundleService().getBundleById(bundleId);
        if (bundle != null) {
          final sessionNumber = bundle.totalSessions - bundle.remainingSessions + 1;
          await BundleService().createBundleSession(
            bundleId: bundleId,
            userId: user.uid,
            sessionNumber: sessionNumber,
            date: dateStr,
            time: time,
            venue: venue,
            coach: coach,
            playerCount: bundle.playerCount,
            bookingId: bookingRef.id,
          );
        }
      }

      // Notify admin about the booking request
      // Only notify for existing bundle usage (new bundle requests already notified)
      if (selectedBundleId != null) {
        await NotificationService().notifyAdminForBookingRequest(
          bookingId: bookingRef.id,
          userId: user.uid,
          userName: userName,
          phone: userPhone,
          venue: venue,
          time: time,
          date: dateStr,
        );
      }

      if (mounted) {
        final bundleMessage = bundleConfig != null
            ? 'Bundle request submitted! Admin will review and approve.'
            : 'Booking from bundle submitted! Waiting for admin approval.';
        final screenContext = context; // Use for map after dialog is closed
        // Show success dialog with option to get directions
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
                    'Request Submitted!',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bundleMessage, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                Text(venue, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(time, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(dateStr, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Close'),
              ),
              ElevatedButton.icon(
                  onPressed: () async {
                  Navigator.pop(dialogContext);
                  try {
                    var locationSnapshot = await FirebaseFirestore.instance
                        .collection('courtLocations')
                        .where('name', isEqualTo: venue)
                        .limit(1)
                        .get();
                    if (locationSnapshot.docs.isEmpty) {
                      locationSnapshot = await FirebaseFirestore.instance
                          .collection('venues')
                          .where('name', isEqualTo: venue)
                          .limit(1)
                          .get();
                    }
                    if (!screenContext.mounted) return;
                    if (locationSnapshot.docs.isNotEmpty) {
                      final locationData = locationSnapshot.docs.first.data();
                      final lat = (locationData['lat'] as num?)?.toDouble();
                      final lng = (locationData['lng'] as num?)?.toDouble();
                      final address = locationData['address'] as String? ?? venue;
                      await MapLauncher.openLocation(
                        context: screenContext,
                        lat: lat,
                        lng: lng,
                        addressQuery: '$venue, $address',
                      );
                    } else {
                      await MapLauncher.openLocation(
                        context: screenContext,
                        addressQuery: venue,
                      );
                    }
                  } catch (e) {
                    debugPrint('Error opening map: $e');
                    if (screenContext.mounted) {
                      ScaffoldMessenger.of(screenContext).showSnackBar(
                        SnackBar(content: Text('Could not open map: $e'), backgroundColor: Colors.orange),
                      );
                    }
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
              // Count both pending and approved bookings (not rejected)
              if (status == 'rejected') continue;
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
                final slotsReserved = data['slotsReserved'] as int? ?? 1; // Get actual slots reserved
                slotCounts[key] = (slotCounts[key] ?? 0) + slotsReserved;
              }
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('slots').snapshots(),
            builder: (context, slotsSnapshot) {
              if (slotsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (slotsSnapshot.hasError) {
                final err = slotsSnapshot.error.toString();
                final isPermission = err.contains('permission-denied') || err.contains('Permission');
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 64, color: Colors.orange),
                        const SizedBox(height: 16),
                        Text(
                          'Could not load venues',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPermission
                              ? 'Data may be restricted. Try logging in or ask the admin to deploy Firestore rules that allow guest read for slots/venues.'
                              : 'Check your connection and try again.',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
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
                      const SizedBox(height: 8),
                      Text(
                        'Add slots in the admin panel, or check Firestore rules if you expect data.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
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

      return StreamBuilder<bool>(
        stream: selectedDate != null 
            ? _isSlotBlockedStream(venueName, time, _getDayName(selectedDate!))
            : Stream.value(false),
        builder: (context, blockedSnapshot) {
          final isBlocked = blockedSnapshot.hasData ? blockedSnapshot.data! : false;
          
          return FutureBuilder<int>(
            future: _getMaxUsersPerSlot(),
            builder: (context, maxSnapshot) {
              int maxUsersPerSlot = 4;
              if (maxSnapshot.hasData) {
                maxUsersPerSlot = maxSnapshot.data!;
              }

              // If blocked, set maxUsersPerSlot to 0
              if (isBlocked) {
                maxUsersPerSlot = 0;
              }

              final isFull = isBlocked || bookingCount >= maxUsersPerSlot;
              final spotsAvailable = isBlocked ? 0 : (maxUsersPerSlot - bookingCount);

          List<Color> gradientColors;
          String statusText;
          Color statusColor;

          if (isBlocked) {
            gradientColors = [const Color(0xFF1A1F3A), const Color(0xFF2D1B3D)];
            statusText = 'Booked';
            statusColor = Colors.red;
          } else if (isFull) {
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
                            ? (isBlocked
                                ? 'Booked - Not available on ${_getDayName(selectedDate!)}'
                                : isFull
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
                    if (isBlocked || isFull)
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
                    if (!isBlocked && !isFull)
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
