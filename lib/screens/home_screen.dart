import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_screen.dart';
import 'my_bookings_screen.dart';
import 'skills_screen.dart';
import 'edit_profile_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? selectedDate;
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com'; // Add admin email if needed

  @override
  void initState() {
    super.initState();
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
    if (selectedDate == null) {
      return const Stream.empty();
    }
    // Get all bookings - we'll filter by date/recurring in the builder
    // This is necessary because Firestore doesn't support OR queries easily
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
  int _getSlotBookingCount(String venue, String time, Map<String, int> slotCounts) {
    if (selectedDate == null) return 0;
    final key = _getBookingKey(venue, time, selectedDate!);
    return slotCounts[key] ?? 0;
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

  // Show confirmation dialog with recurring option
  Future<Map<String, dynamic>?> _showBookingConfirmation(
      String venue, String time, String coach) async {
    if (selectedDate == null) return null;

    Set<String> selectedDays = {};
    bool isRecurring = false;

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
                    const SizedBox(height: 8),
                    Text('Coach: $coach'),
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
                      if (selectedDays.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You will be booked every ${selectedDays.join(' and ')} at $time',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[900],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  // Process booking after confirmation
  Future<void> _processBooking(
      String venue, String time, String coach, Map<String, dynamic> result) async {
    if (result['confirmed'] != true) return;

    final isRecurring = result['isRecurring'] as bool? ?? false;
    final recurringDays = (result['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];

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
        
        // Check how many users have already booked this specific slot
        // Need to check both regular bookings and recurring bookings
        final dayName = _getDayName(selectedDate!);
        
        // Get all bookings for this venue and time
        final allBookings = await FirebaseFirestore.instance
            .collection('bookings')
            .where('venue', isEqualTo: venue)
            .where('time', isEqualTo: time)
            .get();
        
        // Filter bookings that apply to this date and are approved
        final existingBookings = allBookings.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'pending';
          
          // Only count approved bookings
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

        // Check if slot has reached capacity
        if (existingBookings.length >= maxUsersPerSlot) {
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
        
        // Save booking to Firestore with pending status
        final bookingData = {
          'userId': user.uid,
          'phone': user.phoneNumber ?? '',
          'venue': venue,
          'time': time,
          'coach': coach,
          'date': dateStr,
          'isRecurring': isRecurring,
          'status': 'pending', // Booking requires approval
          'timestamp': FieldValue.serverTimestamp(),
        };

        if (isRecurring) {
          bookingData['recurringDays'] = recurringDays;
          bookingData['dayOfWeek'] = _getDayName(selectedDate!);
        }

        // Ensure user profile exists before booking
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

        await FirebaseFirestore.instance.collection('bookings').add(bookingData);

        if (mounted) {
          String message = 'Booking request submitted! Waiting for admin approval.';
          if (isRecurring && recurringDays.isNotEmpty) {
            message = 'Recurring booking request submitted for every ${recurringDays.join(' and ')} at $time! Waiting for approval.';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 34,
            ),
            const SizedBox(width: 10),
            const Text("PadelCore"),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'My Bookings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyBookingsScreen()),
              );
            },
          ),
          // Only show admin settings button if user is admin
          if (_isAdmin())
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Admin Settings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminScreen()),
                );
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) async {
              if (value == 'logout') {
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
                }
              } else if (value == 'skills') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SkillsScreen()),
                );
              } else if (value == 'profile') {
                // Navigate to edit profile screen
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'skills',
                child: Row(
                  children: [
                    Icon(Icons.radar, size: 20),
                    SizedBox(width: 8),
                    Text('Skills'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person, size: 20),
                    SizedBox(width: 8),
                    Text('Profile'),
          ],
        ),
      ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
        children: [
                    Icon(Icons.logout, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getBookingsStream(),
        builder: (context, snapshot) {
          // Count bookings per slot from Firestore (including recurring)
          Map<String, int> slotCounts = {};
          if (snapshot.hasData && selectedDate != null) {
            final dayName = _getDayName(selectedDate!);
            
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
            stream: FirebaseFirestore.instance
                .collection('slots')
                .snapshots(),
            builder: (context, slotsSnapshot) {
              if (slotsSnapshot.connectionState == ConnectionState.waiting) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _dateSelector(),
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
                padding: const EdgeInsets.all(16),
                children: [
                  _dateSelector(),
                  if (selectedDate != null) ...[
                    if (venuesMap.isEmpty) ...[
                      const SizedBox(height: 40),
                      const Center(
                        child: Text(
                          'No slots available. Admin needs to add slots.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 20),
                      ...venuesMap.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: buildVenue(
                            entry.key,
                            entry.value,
                            slotCounts,
                          ),
                        );
                      }),
                    ],
                  ] else ...[
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'Please select a date to view available venues',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  // DATE PICKER
  Widget _dateSelector() {
    return GestureDetector(
      onTap: () async {
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
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selectedDate != null
                  ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                  : 'Select a date',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: selectedDate != null ? Colors.black : Colors.grey[600],
              ),
            ),
            const Icon(Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  // VENUE BUILDER
  Widget buildVenue(String venueName, List<Map<String, String>> timeSlots, Map<String, int> slotCounts) {
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
              final bookingCount = _getSlotBookingCount(venueName, time, slotCounts);
              
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
}
