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
  int _selectedNavIndex = -1; // Track selected navigation item (-1 = none selected, on home screen)
  Set<String> _expandedVenues = {}; // Track which venues are expanded
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

  // Check if slot is blocked for the selected day
  Future<bool> _isSlotBlocked(String venue, String time, String dayName) async {
    try {
      final blocked = await FirebaseFirestore.instance
          .collection('blockedSlots')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .where('day', isEqualTo: dayName)
          .limit(1)
          .get();
      
      return blocked.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
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

  // Handle navigation item tap
  void _onNavItemTapped(int index) {
    setState(() {
      _selectedNavIndex = index;
    });

    switch (index) {
      case 0: // My Bookings
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MyBookingsScreen()),
        ).then((_) {
          // Reset selection when returning to home
          setState(() {
            _selectedNavIndex = -1;
          });
        });
        break;
      case 1: // Profile
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
        ).then((_) {
          setState(() {
            _selectedNavIndex = -1;
          });
        });
        break;
      case 2: // Skills
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SkillsScreen()),
        ).then((_) {
          setState(() {
            _selectedNavIndex = -1;
          });
        });
        break;
      case 3: // Logout
        _handleLogout();
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
        color: const Color(0xFF1E3A8A), // Dark blue background
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
                icon: Icons.person,
                label: 'Profile',
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.radar,
                label: 'Skills',
                index: 2,
              ),
              _buildNavItem(
                icon: Icons.logout,
                label: 'Logout',
                index: 3,
              ),
            ],
          ),
        ),
      ),
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
        // Only show admin settings button if user is admin
        actions: _isAdmin()
            ? [
                IconButton(
                  icon: const Icon(Icons.settings, size: 28),
                  tooltip: 'Admin Settings',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AdminScreen()),
                    );
                  },
                ),
              ]
            : null,
      ),
      bottomNavigationBar: _buildBottomNavBar(),
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
                padding: EdgeInsets.zero,
                children: [
                  // Welcome Section with Background
                  _buildWelcomeSection(),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (selectedDate != null) ...[
                          // Show selected date
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Selected: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
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
                          ),
                          const SizedBox(height: 20),
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
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildExpandableVenue(
                                  entry.key,
                                  entry.value,
                                  slotCounts,
                                ),
                              );
                            }),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // WELCOME SECTION
  Widget _buildWelcomeSection() {
    return Container(
      height: 280,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E3A8A),
            const Color(0xFF3B82F6),
            const Color(0xFF1E3A8A),
          ],
        ),
        // You can add a padel image here later by uncommenting and adding the image to assets
        // image: DecorationImage(
        //   image: AssetImage('assets/images/padel_background.jpg'),
        //   fit: BoxFit.cover,
        //   colorFilter: ColorFilter.mode(
        //     Colors.black.withOpacity(0.3),
        //     BlendMode.darken,
        //   ),
        // ),
      ),
      child: Stack(
        children: [
          // Decorative elements
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          // Content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Welcome to PadelCore',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          offset: Offset(2, 2),
                          blurRadius: 4,
                          color: Colors.black26,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Academy and Tournaments',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 3,
                          color: Colors.black26,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'PadelCore is a padel academy operating in 2 locations in Sheikh Zayed, and will soon operate in Cairo West near New Giza. We have certified and professional trainers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.white.withOpacity(0.95),
                        shadows: [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 2,
                            color: Colors.black26,
                          ),
                        ],
                      ),
                    ),
          ),
          const SizedBox(height: 24),
                  GestureDetector(
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
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Please choose a suitable date and time',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  // Build venue slot children list
  List<Widget> _buildVenueSlotChildren(String venueName, List<Map<String, String>> sortedSlots, Map<String, int> slotCounts) {
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
      final bookingCount = _getSlotBookingCount(venueName, time, slotCounts);
      
      slotWidgets.add(_buildSlotWidget(venueName, time, coach, bookingCount));
    }
    
    return slotWidgets;
  }

  // Build individual slot widget
  Widget _buildSlotWidget(String venueName, String time, String coach, int bookingCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: FutureBuilder<Map<String, dynamic>>(
        future: Future.wait([
          _getMaxUsersPerSlot(),
          _getRecurringBookingDays(venueName, time),
          selectedDate != null 
              ? _isSlotBlocked(venueName, time, _getDayName(selectedDate!))
              : Future.value(false),
        ]).then((results) => {
          'maxUsers': results[0] as int,
          'recurringDays': results[1] as Map<String, bool>,
          'isBlocked': results[2] as bool,
        }).catchError((error) => {
          'maxUsers': 4,
          'recurringDays': <String, bool>{'Sunday': false, 'Tuesday': false},
          'isBlocked': false,
        }),
        builder: (context, snapshot) {
          int maxUsersPerSlot = 4;
          Map<String, bool> recurringDays = {'Sunday': false, 'Tuesday': false};
          bool isBlocked = false;
          
          if (snapshot.hasData) {
            maxUsersPerSlot = snapshot.data!['maxUsers'] as int;
            recurringDays = snapshot.data!['recurringDays'] as Map<String, bool>;
            isBlocked = snapshot.data!['isBlocked'] as bool? ?? false;
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
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isFull ? Colors.grey[200] : Colors.white,
              border: Border.all(
                color: isFull ? Colors.grey[400]! : Colors.grey[300]!,
                width: (hasSundayBooking || hasTuesdayBooking) ? 2 : 1,
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
                      Row(
                        children: [
                          if (isLoading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const SizedBox(width: 16),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isFull ? Colors.grey[600] : Colors.black,
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
                        selectedDate != null
                            ? (isBlocked
                                ? 'Blocked - Not available on ${_getDayName(selectedDate!)}'
                                : isFull
                                    ? 'Full ($bookingCount/$maxUsersPerSlot)'
                                    : '$spotsAvailable spot${spotsAvailable != 1 ? 's' : ''} available ($bookingCount/$maxUsersPerSlot)')
                            : 'Select a date to see availability',
                        style: TextStyle(
                          fontSize: 12,
                          color: selectedDate != null
                              ? (isBlocked 
                                  ? Colors.red[700] 
                                  : isFull 
                                      ? Colors.red 
                                      : Colors.green[700])
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
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
                if (isBlocked || isFull)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isBlocked ? Colors.red[200] : Colors.red[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isBlocked ? 'Blocked' : 'Full',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red[800],
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
          );
        },
      ),
    );
  }

  // BUILD EXPANDABLE VENUE
  Widget _buildExpandableVenue(String venueName, List<Map<String, String>> timeSlots, Map<String, int> slotCounts) {
    final isExpanded = _expandedVenues.contains(venueName);
    
    // Sort time slots by time
    final sortedSlots = List<Map<String, String>>.from(timeSlots);
    sortedSlots.sort((a, b) {
      final timeA = a['time'] ?? '';
      final timeB = b['time'] ?? '';
      return timeA.compareTo(timeB);
    });
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: const Color(0xFF1E3A8A),
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
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${sortedSlots.length} time slot${sortedSlots.length != 1 ? 's' : ''} available',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: const Color(0xFF1E3A8A),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            ..._buildVenueSlotChildren(venueName, sortedSlots, slotCounts),
          ],
        ],
      ),
    );
  }

  // VENUE BUILDER (kept for backward compatibility if needed)
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
