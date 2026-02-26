import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/map_launcher.dart';
import '../utils/auth_required.dart';
import 'admin_screen.dart';
import 'my_bookings_screen.dart';
import 'my_tournaments_screen.dart';
import 'tournaments_screen.dart';
import 'tournament_join_screen.dart';
import 'tournament_dashboard_screen.dart';
import 'skills_screen.dart';
import 'edit_profile_screen.dart';
import 'notifications_screen.dart';
import 'booking_page_screen.dart';
import 'court_locations_screen.dart';
import 'login_screen.dart';
import '../services/notification_service.dart';
import '../services/bundle_service.dart';
import '../models/bundle_model.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/bundle_selector_dialog.dart';


class HomeScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialVenue;

  const HomeScreen({
    super.key,
    this.initialDate,
    this.initialVenue,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  final ValueNotifier<DateTime?> _selectedDateNotifier = ValueNotifier<DateTime?>(null);
  DateTime? get selectedDate => _selectedDateNotifier.value;
  int _selectedNavIndex = -1; // Track selected navigation item (-1 = none selected, on home screen)
  Set<String> _expandedVenues = {}; // Track which venues are expanded
  final ScrollController _scrollController = ScrollController();
  String? _selectedVenueFilter; // Filter by venue when booking from location card
  final Map<String, GlobalKey> _venueKeys = {}; // Keys for scrolling to specific venues
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com'; // Add admin email if needed

  @override
  bool get wantKeepAlive => true; // Keep the state alive when navigating away

  @override
  void initState() {
    super.initState();
    // Set today's date as default if no initial date is provided
    _selectedDateNotifier.value = widget.initialDate ?? DateTime.now();
    _selectedVenueFilter = widget.initialVenue;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _selectedDateNotifier.dispose();
    super.dispose();
  }

  // Check if current user is admin
  bool _isAdmin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.phoneNumber == adminPhone || user.email == adminEmail;
  }

  // Load bookings from Firestore for selected date (including recurring)
  // We need to get all bookings and filter by date or recurring days
  Stream<QuerySnapshot> _getBookingsStream() {
    // Always return all bookings - we filter by date in the builder
    // This prevents the stream from changing when date changes, so StreamBuilder won't rebuild
    return FirebaseFirestore.instance
        .collection('bookings')
        .snapshots();
  }

  // Helper method to get all bookings for a specific user (if needed later)
  Stream<QuerySnapshot> getUserBookings(String userId) {
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  // Generate unique key for a booking slot
  String _getBookingKey(String venue, String time, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$dateStr|$venue|$time';
  }

  // Get booking count for a slot
  int _getSlotBookingCount(String venue, String time, Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    if (currentSelectedDate == null) return 0;
    final key = _getBookingKey(venue, time, currentSelectedDate);
    return slotCounts[key] ?? 0;
  }

  // Check if date is today
  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  // Check if slot has recurring bookings on Sunday or Tuesday
  Future<Map<String, bool>> _getRecurringBookingDays(String venue, String time) async {
    Map<String, bool> recurringDays = {
      'Sunday': false,
      'Tuesday': false,
    };
    
    try {
      final bookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .where('isRecurring', isEqualTo: true)
          .where('status', isEqualTo: 'approved')
          .get();
      
      for (var doc in bookings.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final recurringDaysList = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
        if (recurringDaysList.contains('Sunday')) {
          recurringDays['Sunday'] = true;
        }
        if (recurringDaysList.contains('Tuesday')) {
          recurringDays['Tuesday'] = true;
        }
      }
    } catch (e) {
      // Silently fail
    }
    
    return recurringDays;
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

  // Get day name from date
  String _getDayName(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  // Check if a recurring booking applies to a specific date
  bool _doesRecurringBookingApply(Map<String, dynamic> booking, DateTime date) {
    if (booking['isRecurring'] != true) return false;
    final recurringDays = (booking['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
    final dayName = _getDayName(date);
    return recurringDays.contains(dayName);
  }

  // Get max users per slot from config
  Future<int> _getMaxUsersPerSlot() async {
    int maxUsersPerSlot = 4; // Default limit
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('bookingSettings')
          .get();
      
      if (configDoc.exists) {
        final data = configDoc.data();
        maxUsersPerSlot = data?['maxUsersPerSlot'] as int? ?? 4;
      }
    } catch (e) {
      // Use default if config doesn't exist
    }
    return maxUsersPerSlot;
  }

  // Show bundle selector dialog and handle schedule
  Future<Map<String, dynamic>?> _showBookingConfirmation(
      String venue, String time, String coach) async {
    if (_selectedDateNotifier.value == null) return null;

    final selectedDate = _selectedDateNotifier.value!;
    final dayName = _getDayName(selectedDate);
    
    // STEP 1: Show bundle selector dialog directly
    final dateStr = '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}';
    Map<String, dynamic>? bundleConfig = await showDialog<Map<String, dynamic>>(
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
                          if (locationSnapshot.docs.isNotEmpty && context.mounted) {
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
                          }
                        } catch (e) {
                          debugPrint('Error opening map: $e');
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
                  Text('${bundleConfig['sessions']} Sessions - ${bundleConfig['players']} Player${bundleConfig['players'] > 1 ? 's' : ''}'),
                  Text('Price: ${bundleConfig['price']} EGP'),
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
                        Text('Start date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                        if (bundleConfig != null) ...[
                          Text('Duration: ${bundleConfig['sessions'] == 4 ? '4 weeks' : '4 weeks'}'),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text('Single session on: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
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
      'dayTimeSchedule': dayTimeSchedule,
      'bundleConfig': bundleConfig,
      'selectedBundleId': null,
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

  // Process booking after confirmation
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
    
    final bookingType = 'Bundle'; // All bookings are bundle-based

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

        final dateStr = '${_selectedDateNotifier.value!.year}-${_selectedDateNotifier.value!.month.toString().padLeft(2, '0')}-${_selectedDateNotifier.value!.day.toString().padLeft(2, '0')}';
        final dayName = _getDayName(_selectedDateNotifier.value!);
        
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
        
        // Check how many users have already booked this specific slot
        // Need to check both regular bookings and recurring bookings
        
        // Get all bookings for this venue and time
        final allBookings = await FirebaseFirestore.instance
            .collection('bookings')
            .where('venue', isEqualTo: venue)
            .where('time', isEqualTo: time)
            .get();
        
        // Filter bookings that apply to this date (pending or approved, not rejected)
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

        // Get max users per slot from config (default to 4 if not set)
        int maxUsersPerSlot = 4; // Default limit
        try {
          final configDoc = await FirebaseFirestore.instance
              .collection('config')
              .doc('bookingSettings')
              .get();
          
          if (configDoc.exists) {
            final data = configDoc.data();
            maxUsersPerSlot = data?['maxUsersPerSlot'] as int? ?? 4;
          }
        } catch (e) {
          // Use default if config doesn't exist
        }

        // Calculate total slots reserved (sum of slotsReserved field)
        int totalSlotsReserved = 0;
        for (var booking in existingBookings) {
          final data = booking.data() as Map<String, dynamic>;
          final slotsReserved = data['slotsReserved'] as int? ?? 1; // Default to 1 for old bookings
          totalSlotsReserved += slotsReserved;
        }

        // For private bookings, check if slot is completely empty
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
        
        // Save booking to Firestore with pending status
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
          'status': 'pending', // Booking requires approval
          'timestamp': FieldValue.serverTimestamp(),
        };

        if (isRecurring) {
          bookingData['recurringDays'] = recurringDays;
          bookingData['dayOfWeek'] = _getDayName(_selectedDateNotifier.value!);
        }
        
        // Get user profile to check existence and get name for notification
        final userProfile = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (!userProfile.exists) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Your profile is not set up. Please sign out and sign up again to complete your profile.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return;
        }

        // Get user name for notification
        final userData = userProfile.data() as Map<String, dynamic>?;
        final firstName = userData?['firstName'] as String? ?? '';
        final lastName = userData?['lastName'] as String? ?? '';
        final userName = '$firstName $lastName'.trim().isEmpty 
            ? (user.phoneNumber ?? 'User') 
            : '$firstName $lastName';

        // Add slots reserved field (maxUsersPerSlot for private, playerCount for shared)
        bookingData['slotsReserved'] = isPrivate ? maxUsersPerSlot : playerCount;

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
            userPhone: user.phoneNumber ?? '',
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
            phone: user.phoneNumber ?? '',
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
        if (bundleId != null && selectedBundleId != null) {
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

        // If 1-session new bundle request, create the single bundle session so it appears in Training Bundles (payment, notes, attendance)
        if (bundleId != null && bundleConfig != null && (bundleConfig['sessions'] as int? ?? 0) == 1) {
          final players = bundleConfig['players'] as int? ?? 1;
          await BundleService().createBundleSession(
            bundleId: bundleId,
            userId: user.uid,
            sessionNumber: 1,
            date: dateStr,
            time: time,
            venue: venue,
            coach: coach,
            playerCount: players,
            bookingId: bookingRef.id,
            bookingStatus: 'pending',
          );
        }
        
        // Notify admin about the booking request
        // Only notify for existing bundle usage (new bundle requests already notified)
        if (selectedBundleId != null) {
          await NotificationService().notifyAdminForBookingRequest(
            bookingId: bookingRef.id,
            userId: user.uid,
            userName: userName,
            phone: user.phoneNumber ?? '',
            venue: venue,
            time: time,
            date: dateStr,
          );
        }

        if (mounted) {
          final bundleMessage = bundleConfig != null
              ? 'Bundle request submitted! Admin will review and approve.'
              : 'Booking from bundle submitted! Waiting for admin approval.';
          
          // Show success dialog with option to get directions
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
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
                    Navigator.pop(context);
                  },
                  child: const Text('Close'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Fetch location coordinates and open map
                    try {
                      debugPrint('🗺️ Opening map for venue: "$venue" (length: ${venue.length})');
                      
                      // Try courtLocations first
                      var locationSnapshot = await FirebaseFirestore.instance
                          .collection('courtLocations')
                          .where('name', isEqualTo: venue)
                          .limit(1)
                          .get();
                      
                      debugPrint('Found ${locationSnapshot.docs.length} in courtLocations');
                      if (locationSnapshot.docs.isEmpty) {
                        // Debug: Show all location names to help identify the mismatch
                        final allLocations = await FirebaseFirestore.instance
                            .collection('courtLocations')
                            .get();
                        debugPrint('Available courtLocations:');
                        for (var doc in allLocations.docs) {
                          final name = doc.data()['name'] as String?;
                          debugPrint('  - "$name" (length: ${name?.length ?? 0})');
                        }
                      }
                      
                      // If not found, try venues collection
                      if (locationSnapshot.docs.isEmpty) {
                        debugPrint('Trying venues collection...');
                        locationSnapshot = await FirebaseFirestore.instance
                            .collection('venues')
                            .where('name', isEqualTo: venue)
                            .limit(1)
                            .get();
                        debugPrint('Found ${locationSnapshot.docs.length} in venues');
                        
                        if (locationSnapshot.docs.isEmpty) {
                          // Debug: Show all venue names to help identify the mismatch
                          final allVenues = await FirebaseFirestore.instance
                              .collection('venues')
                              .get();
                          debugPrint('Available venues:');
                          for (var doc in allVenues.docs) {
                            final name = doc.data()['name'] as String?;
                            debugPrint('  - "$name" (length: ${name?.length ?? 0})');
                          }
                        }
                      }
                      
                      if (locationSnapshot.docs.isNotEmpty && context.mounted) {
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
                      } else if (locationSnapshot.docs.isEmpty) {
                        debugPrint('⚠️ Location not found in any collection');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Location "$venue" not found')),
                          );
                        }
                      }
                    } catch (e) {
                      debugPrint('❌ Error opening map: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error opening map: $e')),
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
        String errorMessage = 'Error booking slot: $e';
        
        // Provide more specific error messages
        if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permission denied. Please make sure you are logged in and try again. If the problem persists, please sign out and sign in again.';
        } else if (e.toString().contains('unavailable')) {
          errorMessage = 'Service temporarily unavailable. Please try again in a moment.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Main booking handler
  Future<void> _handleBooking(String venue, String time, String coach) async {
    final result = await _showBookingConfirmation(venue, time, coach);
    if (result != null) {
      await _processBooking(venue, time, coach, result);
    }
  }

  // Handle navigation item tap (guests must log in for services; Profile/Login goes to LoginScreen)
  void _onNavItemTapped(int index) {
    final isGuest = FirebaseAuth.instance.currentUser == null;
    setState(() {
      _selectedNavIndex = index;
    });

    void popAndReset() {
      setState(() {
        _selectedNavIndex = -1;
      });
    }

    switch (index) {
      case 0: // My Bookings — require login
        requireLogin(context).then((loggedIn) {
          if (loggedIn && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MyBookingsScreen()),
            ).then((_) => popAndReset());
          } else {
            popAndReset();
          }
        });
        break;
      case 1: // Tournaments — browse allowed
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TournamentsScreen()),
        ).then((_) => popAndReset());
        break;
      case 2: // Profile — guest goes to Login, else EditProfile
        if (isGuest) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          ).then((_) => popAndReset());
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditProfileScreen()),
          ).then((_) => popAndReset());
        }
        break;
      case 3: // Skills
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SkillsScreen()),
        ).then((_) => popAndReset());
        break;
      case 4: // Logout or Login (guest)
        if (isGuest) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          ).then((_) => popAndReset());
        } else {
          _handleLogout();
        }
        break;
    }
  }

  // Handle logout
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
      // AuthWrapper will automatically navigate to LoginScreen
    } else {
      // Reset selection if cancelled
      setState(() {
        _selectedNavIndex = -1;
      });
    }
  }

  // Build custom bottom navigation bar matching admin style
  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E27), // Dark background
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.bookmark,
                label: 'My Bookings',
                index: 0,
              ),
              _buildNavItem(
                icon: Icons.emoji_events,
                label: 'Tournaments',
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.person,
                label: 'Profile',
                index: 2,
              ),
              _buildNavItem(
                icon: Icons.radar,
                label: 'Skills',
                index: 3,
              ),
              _buildNavItem(
                icon: FirebaseAuth.instance.currentUser == null ? Icons.login : Icons.logout,
                label: FirebaseAuth.instance.currentUser == null ? 'Login' : 'Logout',
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build notification icon with badge
  Widget _buildNotificationIcon(int unreadCount) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications, size: 28),
          tooltip: 'Notifications',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => NotificationsScreen()),
            );
          },
        ),
        if (unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // Build individual navigation item
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedNavIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onNavItemTapped(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                ),
              ),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 2,
                  width: 30,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(1)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27), // Dark blue background
      appBar: const AppHeader(),
      bottomNavigationBar: const AppFooter(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getBookingsStream(),
        builder: (context, snapshot) {
          // Use ValueListenableBuilder inside StreamBuilder to isolate date changes
          return ValueListenableBuilder<DateTime?>(
            valueListenable: _selectedDateNotifier,
            builder: (context, currentSelectedDate, _) {
              // Count bookings per slot from Firestore (including recurring)
              Map<String, int> slotCounts = {};
              if (snapshot.hasData && currentSelectedDate != null) {
                final dayName = _getDayName(currentSelectedDate);
                
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] as String? ?? 'pending';
                  
                  // Only count approved bookings
                  if (status != 'approved') continue;
                  
                  final venue = data['venue'] as String? ?? '';
                  final time = data['time'] as String? ?? '';
                  final isRecurring = data['isRecurring'] as bool? ?? false;
                  
                  // Check if this booking applies to the selected date
                  bool applies = false;
                  if (isRecurring) {
                    // Check if recurring booking applies to this day
                    final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
                    applies = recurringDays.contains(dayName);
                  } else {
                    // Regular booking - check if date matches
                    final bookingDate = data['date'] as String? ?? '';
                    final dateStr = '${currentSelectedDate!.year}-${currentSelectedDate.month.toString().padLeft(2, '0')}-${currentSelectedDate.day.toString().padLeft(2, '0')}';
                    applies = bookingDate == dateStr;
                  }
                  
                  if (applies) {
                    final key = _getBookingKey(venue, time, currentSelectedDate!);
                    final slotsReserved = data['slotsReserved'] as int? ?? 1; // Get actual slots reserved
                    slotCounts[key] = (slotCounts[key] ?? 0) + slotsReserved;
                  }
                }
              }

              return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('slots')
                .snapshots(),
            builder: (context, slotsSnapshot) {
              if (slotsSnapshot.connectionState == ConnectionState.waiting) {
                return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDateDisplayWithCalendar(currentSelectedDate),
                    const Center(child: CircularProgressIndicator()),
                  ],
                );
              }

              // Group slots by venue
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

              return ListView(
                key: const PageStorageKey<String>('homeScreenListView'),
                controller: _scrollController,
                padding: EdgeInsets.zero,
                cacheExtent: 1000.0,
                physics: const ClampingScrollPhysics(),
                children: [
                  // Hero Section with Train/Compete/Improve
                  _buildHeroSection(),
                  
                  // Feature Cards (replacing action buttons)
                  _buildActionButtons(),
                  
                  Container(
                    color: const Color(0xFF0A0E27),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header text
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Book your training session today.',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          // Date display with calendar picker
                          _buildDateDisplayWithCalendar(currentSelectedDate),
                          const SizedBox(height: 20),
                          // Filter venues if venue filter is set
                          Builder(
                            builder: (context) {
                              final filteredVenuesMap = _selectedVenueFilter != null
                                  ? Map.fromEntries(
                                      venuesMap.entries.where((entry) => entry.key == _selectedVenueFilter))
                                  : venuesMap;

                              if (filteredVenuesMap.isEmpty) {
                                return const SizedBox(
                                  height: 40,
                                  child: Center(
                                    child: Text(
                                      'No slots available. Admin needs to add slots.',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  const SizedBox(height: 20),
                                  ...filteredVenuesMap.entries.map((entry) {
                                    // Create or get GlobalKey for this venue
                                    if (!_venueKeys.containsKey(entry.key)) {
                                      _venueKeys[entry.key] = GlobalKey();
                                    }
                                    return Padding(
                                      key: _venueKeys[entry.key],
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _buildExpandableVenue(
                                        entry.key,
                                        entry.value,
                                        slotCounts,
                                        currentSelectedDate,
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Tournaments Section
                  _buildTournamentsSection(),
                  
                  // Training Options Section (before How It Works)
                  _buildTrainingOptionsSection(),
                  
                  // How It Works Section
                  _buildHowItWorksSection(),
                ],
              );
            },
          );
            },
          );
        },
      ),
    );
  }

  // HOW IT WORKS SECTION
  Widget _buildHowItWorksSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How it works',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0A0E27),
            ),
          ),
          const SizedBox(height: 32),
          
          // Booking Training Sessions
          _buildHowItWorksStep(
            stepNumber: 1,
            title: 'Book Training Sessions',
            steps: [
              'Select a date from the calendar',
              'Choose your preferred location (Club 13 or Padel Avenue)',
              'Pick an available time slot',
              'Click "Book" to reserve your session',
              'Wait for admin approval',
            ],
            icon: Icons.calendar_today,
            color: const Color(0xFF60A5FA),
          ),
          
          const SizedBox(height: 32),
          
          // Book Courts
          _buildHowItWorksStep(
            stepNumber: 2,
            title: 'Book Courts',
            steps: [
              'Select a location from available courts',
              'Choose your preferred date',
              'Pick available time slots (30-minute increments)',
              'Review booking details and confirm',
              'Booking is confirmed immediately',
            ],
            icon: Icons.sports_tennis,
            color: const Color(0xFF10B981), // Green color
          ),
          
          const SizedBox(height: 32),
          
          // Tournaments
          _buildHowItWorksStep(
            stepNumber: 3,
            title: 'Join Tournaments',
            steps: [
              'Browse available tournaments',
              'Select a tournament and choose your skill level',
              'Find or add a partner',
              'Submit your registration',
              'Wait for admin approval',
              'Check standings and compete!',
            ],
            icon: Icons.emoji_events,
            color: const Color(0xFFFFC400),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksStep({
    required int stepNumber,
    required String title,
    required List<String> steps,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(12),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step $stepNumber: $title',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...steps.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // HERO SECTION
  Widget _buildHeroSection() {
    return Container(
      height: 350,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E3A8A),
            const Color(0xFF3B82F6),
            const Color(0xFF6B46C1),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background image (if available)
          _buildAssetImage(
            'assets/images/padel_court.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: 350,
          ),
          // Dark overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
          ),
          // Text overlay
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Train.',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const Text(
                  'Compete.',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const Text(
                  'Improve.',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Book your next padel session in seconds.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ACTION BUTTONS (Now Feature Cards)
  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      color: const Color(0xFF0A0E27),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Explore PadelCore Features',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildActionCard(
                  title: 'Train',
                  description: 'Certified coaches',
                  icon: Icons.fitness_center,
                  gradient: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                  imagePath: 'assets/images/train_today.jpg', // Training image
                  onTap: () async {
                    try {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => BookingPageScreen(
                              initialDate: picked,
                            ),
                          ),
                        );
                      }
                    } catch (e, stack) {
                      debugPrint('Train Today error: $e');
                      debugPrint('$stack');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Something went wrong. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  title: 'Book Court',
                  description: 'Get on game',
                  icon: Icons.emoji_events,
                  gradient: const [Color(0xFFFFC400), Color(0xFFFF9800)],
                  imagePath: 'assets/images/book_court.jpg', // Competition image - you can add a specific image later
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CourtLocationsScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  title: 'Compete',
                  description: 'Join tournaments',
                  icon: Icons.track_changes,
                  gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                  imagePath: 'assets/images/tournament.jpg', // Skills image - you can add a specific image later
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const TournamentsScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
    String? imagePath,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            if (imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildAssetImage(
                  imagePath,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 180,
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            // Gradient overlay from bottom for text readability
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                height: 80,
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Text at bottom
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FEATURE CARDS
  Widget _buildFeatureCards() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: const Color(0xFF0A0E27),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Explore PadelCore Features',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildFeatureCard(
                  title: 'Train',
                  description: 'With certified coaches',
                  icon: Icons.fitness_center,
                  gradient: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeatureCard(
                  title: 'Compete',
                  description: 'Join tournaments and compete',
                  icon: Icons.emoji_events,
                  gradient: const [Color(0xFFFFC400), Color(0xFFFF9800)],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeatureCard(
                  title: 'Track Skills',
                  description: 'See your progress and skills',
                  icon: Icons.track_changes,
                  gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradient,
  }) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  // UPCOMING SESSIONS SECTION
  Widget _buildUpcomingSessionsSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A), // Dark card background
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
          const Text(
            'Book padel training in the following locations',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          _buildSessionItem(
            title: 'Club 13',
            venue: 'Club13 Sheikh Zayed',
            onBook: () {
              if (!mounted) return;
              
              _selectedDateNotifier.value = DateTime.now();
              setState(() {
                _selectedVenueFilter = 'Club13 Sheikh Zayed';
              });
              
              // Scroll to venue smoothly without jumping to top
              if (mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final venueKey = _venueKeys['Club13 Sheikh Zayed'];
                  if (venueKey?.currentContext != null && _scrollController.hasClients) {
                    Scrollable.ensureVisible(
                      venueKey!.currentContext!,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                      alignment: 0.3, // Show venue at 30% from top
                      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                    );
                  }
                });
              }
            },
          ),
          const SizedBox(height: 16),
          _buildSessionItem(
            title: 'Padel Avenue',
            venue: 'Padel Avenue',
            onBook: () {
              _selectedDateNotifier.value = DateTime.now();
              setState(() {
                _selectedVenueFilter = 'Padel Avenue';
              });
              
              // Scroll to venue smoothly without jumping to top
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final venueKey = _venueKeys['Padel Avenue'];
                if (venueKey?.currentContext != null && _scrollController.hasClients) {
                  Scrollable.ensureVisible(
                    venueKey!.currentContext!,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    alignment: 0.3, // Show venue at 30% from top
                    alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                  );
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSessionItem({
    required String title,
    required String venue,
    required VoidCallback onBook,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: onBook,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            'Book Now',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // TRAINING OPTIONS SECTION
  Widget _buildTrainingOptionsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'We train all styles.',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildTrainingCard(
                  title: 'Group Training',
                  icon: Icons.people,
                  description1: 'Train with other players',
                  description2: 'Social & competitive',
                  color: const Color(0xFF3B82F6), // Blue
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTrainingCard(
                  title: 'Private Training',
                  icon: Icons.person,
                  description1: '1-on-1 coaching session',
                  description2: 'With a certified coach',
                  color: const Color(0xFF8B5CF6), // Purple
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTrainingCard(
                  title: 'Pro Training',
                  icon: Icons.emoji_events,
                  description1: 'Train like the pros',
                  description2: 'Elevate your game',
                  color: const Color(0xFFF59E0B), // Orange/Gold
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrainingCard({
    required String title,
    required IconData icon,
    required String description1,
    required String description2,
    required Color color,
  }) {
    return Container(
      height: 192,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Icon(
            icon,
            color: color,
            size: 32,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                description1,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.9),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                description2,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.9),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper method to build asset image with proper path handling
  Widget _buildAssetImage(String imagePath, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (imagePath.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFF1E3A8A),
        child: const Icon(
          Icons.emoji_events,
          color: Colors.white,
          size: 48,
        ),
      );
    }

    // Normalize the path - ensure it starts with 'assets/'
    String normalizedPath = imagePath.trim();
    
    // Remove leading slash if present
    if (normalizedPath.startsWith('/')) {
      normalizedPath = normalizedPath.substring(1);
    }
    
    // Ensure it starts with 'assets/'
    if (!normalizedPath.startsWith('assets/')) {
      // If it starts with 'images/', add 'assets/' prefix
      if (normalizedPath.startsWith('images/')) {
        normalizedPath = 'assets/$normalizedPath';
      } else {
        // Otherwise, assume it's in assets/images/
        normalizedPath = 'assets/images/$normalizedPath';
      }
    }
    
    return Image.asset(
      normalizedPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Failed to load asset image: $normalizedPath');
        debugPrint('Original path: $imagePath');
        debugPrint('Error: $error');
        return Container(
          width: width,
          height: height,
          color: const Color(0xFF1E3A8A),
          child: const Icon(
            Icons.emoji_events,
            color: Colors.white,
            size: 48,
          ),
        );
      },
    );
  }

  void _showWeeklyTournamentsFromHome(BuildContext context, String parentTournamentId, String parentName) async {
    try {
      final weeklySnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('parentTournamentId', isEqualTo: parentTournamentId)
          .get();
      if (!context.mounted) return;
      final weeklyTournaments = weeklySnapshot.docs;
      weeklyTournaments.sort((a, b) {
        final aDate = (a.data())['date'] as String? ?? '';
        final bDate = (b.data())['date'] as String? ?? '';
        return aDate.compareTo(bDate);
      });
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('$parentName - Weekly Tournaments'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: weeklyTournaments.isEmpty
                  ? const Center(child: Text('No weekly tournaments yet.'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: weeklyTournaments.length,
                      itemBuilder: (context, index) {
                        final doc = weeklyTournaments[index];
                        final data = doc.data();
                        final name = data['name'] as String? ?? 'Week ${index + 1}';
                        final date = data['date'] as String? ?? '';
                        final status = data['status'] as String? ?? 'upcoming';
                        final hasStarted = ['phase1', 'phase2', 'knockout', 'completed', 'groups'].contains(status);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.white,
                              child: Text('${index + 1}', style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            title: Text(date.isNotEmpty ? date : name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(status.toUpperCase()),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!hasStarted)
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.pop(dialogContext);
                                      final loggedIn = await requireLogin(context);
                                      if (loggedIn && context.mounted) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => TournamentJoinScreen(
                                              tournamentId: doc.id,
                                              tournamentName: name,
                                              tournamentImageUrl: data['imageUrl'] as String?,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text('Join'),
                                  ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    // Dashboard viewable without login
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TournamentDashboardScreen(
                                          tournamentId: doc.id,
                                          tournamentName: name,
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Results'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading weekly tournaments: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // TOURNAMENTS SECTION
  Widget _buildTournamentsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Upcoming Tournaments',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (_isAdmin())
                IconButton(
                  icon: const Icon(
                    Icons.edit,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () => _showManageTournamentsDialog(),
                  tooltip: 'Manage Visible Tournaments',
                ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tournaments')
                .orderBy('createdAt', descending: true)
                .limit(3)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox(
                  height: 100,
                  child: Center(
                    child: Text(
                      'No tournaments available',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              // Filter tournaments based on showOnHomePage field
              final allTournaments = snapshot.data!.docs;
              final tournaments = allTournaments.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final isArchived = data['isArchived'] as bool? ?? false;
                final isHidden = data['hidden'] as bool? ?? false;
                final showOnHomePage = data['showOnHomePage'] as bool? ?? true; // Default to true for existing tournaments
                
                // Always exclude archived and hidden tournaments
                if (isArchived || isHidden) return false;
                
                // Show only if showOnHomePage is true
                return showOnHomePage;
              }).toList();

              if (tournaments.isEmpty) {
                return const SizedBox(
                  height: 100,
                  child: Center(
                    child: Text(
                      'No tournaments available',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 360,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: tournaments.length,
                  itemBuilder: (context, index) {
                    final doc = tournaments[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['name'] as String? ?? 'Unknown Tournament';
                    final description = data['description'] as String? ?? '';
                    final imageUrl = data['imageUrl'] as String?;
                    final date = data['date'] as String? ?? '';
                    final time = data['time'] as String? ?? '';
                    final location = data['location'] as String? ?? '';
                    final entryFee = data['entryFee'] as int? ?? 0;
                    final prize = data['prize'] as int? ?? 0;
                    final maxParticipants = data['maxParticipants'] as int? ?? 12;
                    final participants = data['participants'] as int? ?? 0;
                    final tournamentType = data['type'] as String? ?? 'Single Elimination';
                    final isParentTournament = data['isParentTournament'] as bool? ?? false;
                    final parentTournamentId = data['parentTournamentId'] as String?;
                    final tournamentStatus = data['status'] as String? ?? 'upcoming';
                    // Handle both old format (String) and new format (List<String>)
                    final skillLevelData = data['skillLevel'];
                    final List<String> skillLevels = skillLevelData is List
                        ? (skillLevelData as List).map((e) => e.toString()).toList()
                        : (skillLevelData != null ? [skillLevelData.toString()] : ['Beginners']);

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 300,
                        height: 360,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F3A),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Image section
                          Expanded(
                            flex: 2,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    topRight: Radius.circular(16),
                                  ),
                                  child: imageUrl != null && imageUrl.isNotEmpty
                                      ? (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')
                                          ? Image.network(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                              loadingBuilder: (context, child, loadingProgress) {
                                                if (loadingProgress == null) return child;
                                                return Container(
                                                  color: const Color(0xFF1E3A8A),
                                                  child: Center(
                                                    child: CircularProgressIndicator(
                                                      value: loadingProgress.expectedTotalBytes != null
                                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                                          : null,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                );
                                              },
                                              errorBuilder: (context, error, stackTrace) {
                                                return Container(
                                                  color: const Color(0xFF1E3A8A),
                                                  child: const Icon(
                                                    Icons.emoji_events,
                                                    color: Colors.white,
                                                    size: 48,
                                                  ),
                                                );
                                              },
                                            )
                                          : _buildAssetImage(imageUrl))
                                      : Container(
                                          color: const Color(0xFF1E3A8A),
                                          child: const Icon(
                                            Icons.emoji_events,
                                            color: Colors.white,
                                            size: 48,
                                          ),
                                        ),
                                ),
                                // Multiple skill level badges
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.end,
                                    children: skillLevels.map((level) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        level.toUpperCase(),
                                        style: const TextStyle(
                                          color: Color(0xFF1E3A8A),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Details section
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tournamentType,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF14B8A6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Text(
                                        '$date • $time',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    location,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  // Participants + Entry + Prize (same row)
                                  Wrap(
                                    spacing: 14,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '$participants/$maxParticipants',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withOpacity(0.85),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Entry: $entryFee EGP',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withOpacity(0.8),
                                        ),
                                      ),
                                      Text(
                                        'Prize: $prize EGP',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  LinearProgressIndicator(
                                    value: maxParticipants > 0 ? participants / maxParticipants : 0,
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF14B8A6)),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${maxParticipants - participants} spots left',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                  ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Button section: Join/View Weekly | Dashboard (no duplicate)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Builder(
                              builder: (context) {
                                final hasStarted = ['phase1', 'phase2', 'knockout', 'completed', 'groups'].contains(tournamentStatus);
                                return Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Upcoming: Join only. Started: Dashboard only. Parent: View Weekly only.
                                        if (isParentTournament || !hasStarted)
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () async {
                                                if (isParentTournament) {
                                                  _showWeeklyTournamentsFromHome(context, parentTournamentId ?? doc.id, name);
                                                  return;
                                                }
                                                // Join tournament requires login
                                                final loggedIn = await requireLogin(context);
                                                if (loggedIn && mounted) {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => TournamentJoinScreen(
                                                        tournamentId: doc.id,
                                                        tournamentName: name,
                                                        tournamentImageUrl: imageUrl,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              child: Container(
                                                height: 44,
                                                alignment: Alignment.center,
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF1E3A8A),
                                                  borderRadius: BorderRadius.circular(22),
                                                ),
                                                child: Text(
                                                  isParentTournament ? 'View Weekly Tournaments' : 'Join Tournament',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        // Right: Dashboard (📊) - only for regular started; parent and upcoming have no dashboard
                                        if (!isParentTournament && hasStarted)
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                // Dashboard viewable without login
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => TournamentDashboardScreen(
                                                      tournamentId: doc.id,
                                                      tournamentName: name,
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Container(
                                                height: 44,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.green[600],
                                                  borderRadius: BorderRadius.circular(22),
                                                ),
                                                child: const Icon(
                                                  Icons.leaderboard,
                                                  color: Colors.white,
                                                  size: 22,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isParentTournament
                                          ? 'Tap for weekly list'
                                          : hasStarted
                                              ? 'Tap 📊 for results'
                                              : 'Tap to join',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.7),
                                        fontStyle: FontStyle.italic,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // DATE DISPLAY WITH CALENDAR PICKER - Shows today's date with calendar button
  Widget _buildDateDisplayWithCalendar(DateTime? currentSelectedDate) {
    final displayDate = currentSelectedDate ?? DateTime.now();
    final today = DateTime.now();
    final isToday = displayDate.year == today.year &&
        displayDate.month == today.month &&
        displayDate.day == today.day;
    
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Date display
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 20,
                    color: const Color(0xFF14B8A6),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isToday ? 'Today' : dayNames[displayDate.weekday - 1],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${monthNames[displayDate.month - 1]} ${displayDate.day}, ${displayDate.year}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Calendar picker button
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF14B8A6),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF14B8A6).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: currentSelectedDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    _selectedDateNotifier.value = picked;
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: const Icon(
                    Icons.calendar_month,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build venue slot children list
  List<Widget> _buildVenueSlotChildren(String venueName, List<Map<String, String>> sortedSlots, Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    if (sortedSlots.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No slots available for this venue',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ];
    }
    
    // Build list of widgets
    List<Widget> slotWidgets = [];
    for (var slot in sortedSlots) {
      final time = slot['time'] ?? '';
      final coach = slot['coach'] ?? '';
      final bookingCount = _getSlotBookingCount(venueName, time, slotCounts, currentSelectedDate);
      
      slotWidgets.add(_buildSlotWidget(venueName, time, coach, bookingCount, currentSelectedDate));
    }
    
    return slotWidgets;
  }

  // Build individual slot widget
  Widget _buildSlotWidget(String venueName, String time, String coach, int bookingCount, DateTime? currentSelectedDate) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: StreamBuilder<bool>(
        stream: currentSelectedDate != null 
            ? _isSlotBlockedStream(venueName, time, _getDayName(currentSelectedDate))
            : Stream.value(false),
        builder: (context, blockedSnapshot) {
          // Get blocked status from stream
          final isBlocked = blockedSnapshot.hasData ? blockedSnapshot.data! : false;
          
          return FutureBuilder<Map<String, dynamic>>(
            future: Future.wait([
              _getMaxUsersPerSlot(),
              _getRecurringBookingDays(venueName, time),
            ]).then((results) => {
              'maxUsers': results[0] as int,
              'recurringDays': results[1] as Map<String, bool>,
            }).catchError((error) => {
              'maxUsers': 4,
              'recurringDays': <String, bool>{'Sunday': false, 'Tuesday': false},
            }),
            builder: (context, snapshot) {
              int maxUsersPerSlot = 4;
              Map<String, bool> recurringDays = {'Sunday': false, 'Tuesday': false};
              
              if (snapshot.hasData) {
                maxUsersPerSlot = snapshot.data!['maxUsers'] as int;
                recurringDays = snapshot.data!['recurringDays'] as Map<String, bool>;
              }
              
              // If blocked, set maxUsersPerSlot to 0
              if (isBlocked) {
                maxUsersPerSlot = 0;
              }
              
              final isFull = isBlocked || bookingCount >= maxUsersPerSlot;
              final spotsAvailable = isBlocked ? 0 : (maxUsersPerSlot - bookingCount);
          final hasSundayBooking = recurringDays['Sunday'] ?? false;
          final hasTuesdayBooking = recurringDays['Tuesday'] ?? false;
          
          // Show loading indicator if still loading, but still show the slot info
          final isLoading = snapshot.connectionState == ConnectionState.waiting;
          
          // Determine gradient colors based on status
          List<Color> gradientColors;
          String statusText;
          Color statusColor;
          
          if (isBlocked) {
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
                      Row(
                        children: [
                          if (isLoading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          Flexible(
                            child: Text(
                              time,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (hasSundayBooking || hasTuesdayBooking) ...[
                            const SizedBox(width: 8),
                            Wrap(
                              spacing: 4,
                              children: [
                                if (hasSundayBooking)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[100],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Sun',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                                if (hasTuesdayBooking)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[100],
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'Tue',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      // Coach name hidden for now
                      // const SizedBox(height: 4),
                      // Text(
                      //   coach,
                      //   style: TextStyle(
                      //     fontSize: 14,
                      //     color: Colors.white.withOpacity(0.8),
                      //   ),
                      // ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            currentSelectedDate != null
                                ? (isBlocked
                                    ? 'Booked - Not available on ${_getDayName(currentSelectedDate)}'
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
                      if (hasSundayBooking || hasTuesdayBooking) ...[
                        const SizedBox(height: 4),
                        Text(
                          hasSundayBooking && hasTuesdayBooking
                              ? 'Recurring: Every Sunday & Tuesday'
                              : hasSundayBooking
                                  ? 'Recurring: Every Sunday'
                                  : 'Recurring: Every Tuesday',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBlocked || isFull || spotsAvailable <= 1)
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
                        onPressed: () => _handleBooking(
                          venueName,
                          time,
                          coach,
                        ),
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

  // BUILD EXPANDABLE VENUE
  Widget _buildExpandableVenue(String venueName, List<Map<String, String>> timeSlots, Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    final isExpanded = _expandedVenues.contains(venueName);
    
    // Sort time slots by time (chronologically)
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
    
    // Filter out past times if today's date is selected
    List<Map<String, String>> filteredSlots = sortedSlots;
    if (currentSelectedDate != null && _isToday(currentSelectedDate)) {
      final now = DateTime.now();
      filteredSlots = sortedSlots.where((slot) {
        final time = slot['time'] ?? '';
        final parsedTime = _parseTimeString(time);
        if (parsedTime == null) return true; // Keep if can't parse
        
        final slotDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          parsedTime.hour,
          parsedTime.minute,
        );
        
        return slotDateTime.isAfter(now) || slotDateTime.isAtSameMomentAs(now);
      }).toList();
    }
    
    // Don't create key here - it's already on the Padding widget that wraps this
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
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
              if (!mounted) return;
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
                    const Color(0xFF6B46C1).withOpacity(0.3),
                    const Color(0xFF1E3A8A).withOpacity(0.3),
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
                          '${filteredSlots.length} time slot${filteredSlots.length != 1 ? 's' : ''} available',
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
                children: _buildVenueSlotChildren(venueName, filteredSlots, slotCounts, currentSelectedDate),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // VENUE BUILDER (kept for backward compatibility if needed)
  Widget buildVenue(String venueName, List<Map<String, String>> timeSlots, Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              venueName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...timeSlots.map((slot) {
              final time = slot['time'] ?? '';
              final coach = slot['coach'] ?? '';
              final bookingCount = _getSlotBookingCount(venueName, time, slotCounts, currentSelectedDate);
              
              // Get max users per slot (default 4)
              int maxUsersPerSlot = 4;
              
              return FutureBuilder<int>(
                future: _getMaxUsersPerSlot(),
                builder: (context, maxSnapshot) {
                  if (maxSnapshot.hasData) {
                    maxUsersPerSlot = maxSnapshot.data!;
                  }
                  
                  final isFull = bookingCount >= maxUsersPerSlot;
                  final spotsAvailable = maxUsersPerSlot - bookingCount;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isFull ? Colors.grey[200] : Colors.white,
                        border: Border.all(
                          color: isFull ? Colors.grey[400]! : Colors.grey[300]!,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  time,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: isFull ? Colors.grey[600] : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  coach,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isFull ? Colors.grey[500] : Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isFull
                                      ? 'Full ($bookingCount/$maxUsersPerSlot)'
                                      : '$spotsAvailable spot${spotsAvailable != 1 ? 's' : ''} available ($bookingCount/$maxUsersPerSlot)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isFull ? Colors.red : Colors.green[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isFull)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Full',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red,
                                ),
                              ),
                            )
                          else
                            ElevatedButton(
                              onPressed: () => _handleBooking(
                                venueName,
                                time,
                                coach,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text('Book'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _showManageTournamentsDialog() async {
    try {
      // Fetch all tournaments
      final tournamentsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .orderBy('name')
          .get();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manage Upcoming Tournaments'),
              content: SizedBox(
                width: double.maxFinite,
                height: 500,
                child: tournamentsSnapshot.docs.isEmpty
                    ? const Center(child: Text('No tournaments found'))
                    : ListView.builder(
                        itemCount: tournamentsSnapshot.docs.length,
                        itemBuilder: (context, index) {
                          final doc = tournamentsSnapshot.docs[index];
                          final data = doc.data();
                          final name = data['name'] as String? ?? 'Unknown';
                          final isParent = data['isParentTournament'] as bool? ?? false;
                          final isArchived = data['isArchived'] as bool? ?? false;
                          final isHidden = data['hidden'] as bool? ?? false;
                          final showOnHomePage = data['showOnHomePage'] as bool? ?? true;

                          // Show archived/hidden status
                          String statusLabel = '';
                          Color? statusColor;
                          if (isArchived) {
                            statusLabel = 'Archived';
                            statusColor = Colors.grey;
                          } else if (isHidden) {
                            statusLabel = 'Hidden';
                            statusColor = Colors.orange;
                          }

                          return CheckboxListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: showOnHomePage ? Colors.black : Colors.grey,
                                    ),
                                  ),
                                ),
                                if (isParent)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Parent',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.purple[900],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                if (statusLabel.isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor?.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            value: showOnHomePage,
                            onChanged: isArchived || isHidden
                                ? null // Can't show archived/hidden tournaments
                                : (bool? value) async {
                                    if (value != null) {
                                      try {
                                        await FirebaseFirestore.instance
                                            .collection('tournaments')
                                            .doc(doc.id)
                                            .update({'showOnHomePage': value});

                                        setDialogState(() {
                                          // Trigger rebuild
                                        });
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Error: $e'),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  },
                            secondary: Icon(
                              isParent ? Icons.folder : Icons.emoji_events,
                              color: showOnHomePage ? const Color(0xFF1E3A8A) : Colors.grey,
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading tournaments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
