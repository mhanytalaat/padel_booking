import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_screen.dart';
import 'my_bookings_screen.dart';
import 'my_tournaments_screen.dart';
import 'tournaments_screen.dart';
import 'skills_screen.dart';
import 'edit_profile_screen.dart';
import 'notifications_screen.dart';
import 'booking_page_screen.dart';
import '../services/notification_service.dart';


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
  DateTime? selectedDate;
  int _selectedNavIndex = -1; // Track selected navigation item (-1 = none selected, on home screen)
  Set<String> _expandedVenues = {}; // Track which venues are expanded
  final ScrollController _scrollController = ScrollController();
  String? _selectedVenueFilter; // Filter by venue when booking from location card
  final Map<String, GlobalKey> _venueKeys = {}; // Keys for scrolling to specific venues
  final GlobalKey _listViewKey = GlobalKey(); // Key to preserve ListView state
  double _lastScrollPosition = 0.0; // Track last scroll position
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com'; // Add admin email if needed

  @override
  bool get wantKeepAlive => true; // Keep the state alive when navigating away

  @override
  void initState() {
    super.initState();
    // Set today's date as default if no initial date is provided
    selectedDate = widget.initialDate ?? DateTime.now();
    _selectedVenueFilter = widget.initialVenue;
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  // Show confirmation dialog with recurring option
  Future<Map<String, dynamic>?> _showBookingConfirmation(
      String venue, String time, String coach) async {
    if (selectedDate == null) return null;

    Set<String> selectedDays = {};
    bool isRecurring = false;
    String bookingType = 'Group'; // 'Private' or 'Group'

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

  // Process booking after confirmation
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

        // For private bookings, check if slot is completely empty
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

        // Check if slot has reached capacity (for group bookings)
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
          bookingData['dayOfWeek'] = _getDayName(selectedDate!);
        }
        
        // For private bookings, create 4 bookings (one for each slot)
        if (isPrivate) {
          for (int i = 0; i < maxUsersPerSlot; i++) {
            await FirebaseFirestore.instance.collection('bookings').add(bookingData);
          }
        } else {
          await FirebaseFirestore.instance.collection('bookings').add(bookingData);
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

        // Get user name for notification
        final userData = userProfile.data() as Map<String, dynamic>?;
        final firstName = userData?['firstName'] as String? ?? '';
        final lastName = userData?['lastName'] as String? ?? '';
        final userName = '$firstName $lastName'.trim().isEmpty 
            ? (user.phoneNumber ?? 'User') 
            : '$firstName $lastName';

        // Create booking
        final bookingRef = await FirebaseFirestore.instance.collection('bookings').add(bookingData);
        
        // Notify admin about the booking request
        await NotificationService().notifyAdminForBookingRequest(
          bookingId: bookingRef.id,
          userId: user.uid,
          userName: userName,
          phone: user.phoneNumber ?? '',
          venue: venue,
          time: time,
          date: dateStr,
        );

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
      case 1: // Tournaments
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TournamentsScreen()),
        ).then((_) {
          setState(() {
            _selectedNavIndex = -1;
          });
        });
        break;
      case 2: // Profile
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
        ).then((_) {
          setState(() {
            _selectedNavIndex = -1;
          });
        });
        break;
      case 3: // Skills
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SkillsScreen()),
        ).then((_) {
          setState(() {
            _selectedNavIndex = -1;
          });
        });
        break;
      case 4: // Logout
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
                icon: Icons.logout,
                label: 'Logout',
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E27),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset(
                'assets/images/logo.png',
                height: 24,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.sports_tennis, color: Colors.white, size: 20);
                },
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              "PadelCore",
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          // Notification bell icon with badge
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .snapshots(),
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  // Filter client-side to avoid index requirements
                  final notifications = snapshot.data!.docs;
                  if (_isAdmin()) {
                    // Admin sees unread admin notifications
                    unreadCount = notifications.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return (data['isAdminNotification'] == true || 
                              data['userId'] == user.uid) &&
                             (data['read'] != true);
                    }).length;
                  } else {
                    // Regular users see only their unread notifications
                    unreadCount = notifications.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['userId'] == user.uid && 
                             (data['read'] != true);
                    }).length;
                  }
                }
              }

              return _buildNotificationIcon(unreadCount);
            },
          ),
          // Admin settings button (only for admin)
          if (_isAdmin())
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
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getBookingsStream(),
        builder: (context, snapshot) {
          // Preserve scroll position before rebuild
          final savedPosition = _scrollController.hasClients 
              ? _scrollController.position.pixels 
              : 0.0;
          
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

              // Restore scroll position after ListView is built
              if (savedPosition > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    final currentPosition = _scrollController.position.pixels;
                    // Only restore if position changed significantly (more than 10 pixels)
                    if ((currentPosition - savedPosition).abs() > 10) {
                      _scrollController.jumpTo(savedPosition);
                    }
                  }
                });
              }

              return ListView(
                key: _listViewKey,
                controller: _scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // Hero Section with Train/Compete/Improve
                  _buildHeroSection(),
                  
                  // Action Buttons
                  _buildActionButtons(),
                  
                  // Feature Cards
                  _buildFeatureCards(),
                  
                  // Upcoming Sessions Section
                  _buildUpcomingSessionsSection(),
                  
                  Container(
                    color: const Color(0xFF0A0E27),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date selector - horizontal scrollable
                          _dateSelector(),
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
                  
                  // How It Works Section
                  _buildHowItWorksSection(),
                ],
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
              color: Colors.white,
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
          
          // Tournaments
          _buildHowItWorksStep(
            stepNumber: 2,
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
          Image.asset(
            'assets/images/padel_court.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: 350,
            errorBuilder: (context, error, stackTrace) {
              return Container(); // Empty if image doesn't exist
            },
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

  // ACTION BUTTONS
  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF0A0E27),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookingPageScreen(
                        initialDate: picked,
                      ),
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ).copyWith(
                backgroundColor: WidgetStateProperty.all(
                  const Color(0xFF10B981), // Green gradient start
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Center(
                  child: Text(
                    'Book Session',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TournamentsScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ).copyWith(
                backgroundColor: WidgetStateProperty.all(
                  const Color(0xFF1E3A8A), // Dark blue gradient start
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Center(
                  child: Text(
                    'Join Tournament',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
                  title: 'Train Today',
                  description: 'Book a session with certified coaches',
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
              setState(() {
                selectedDate = DateTime.now();
                _selectedVenueFilter = 'Club13 Sheikh Zayed';
              });
              
              // Scroll to venue smoothly without jumping to top
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final venueKey = _venueKeys['Club13 Sheikh Zayed'];
                if (venueKey?.currentContext != null && _scrollController.hasClients) {
                  Scrollable.ensureVisible(
                    venueKey!.currentContext!,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                    alignment: 0.3, // Show venue at 30% from top (keeps current position if already visible)
                    alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                  );
                }
              });
            },
          ),
          const SizedBox(height: 16),
          _buildSessionItem(
            title: 'Padel Avenue',
            venue: 'Padel Avenue',
            onBook: () {
              setState(() {
                selectedDate = DateTime.now();
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
                    alignment: 0.3, // Show venue at 30% from top (keeps current position if already visible)
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

  // DATE PICKER - Horizontal scrollable date picker
  Widget _dateSelector() {
    final today = DateTime.now();
    final dates = List.generate(14, (index) => today.add(Duration(days: index)));
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = selectedDate != null &&
              date.year == selectedDate!.year &&
              date.month == selectedDate!.month &&
              date.day == selectedDate!.day;
          final isToday = date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
          
          final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          
          return GestureDetector(
            onTap: () {
              // Save scroll position before setState
              final savedPos = _scrollController.hasClients 
                  ? _scrollController.position.pixels 
                  : _lastScrollPosition;
              
              setState(() {
                selectedDate = date;
              });
              
              // Restore scroll position after rebuild
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients && savedPos > 0) {
                  _scrollController.jumpTo(savedPos);
                }
              });
            },
            child: Container(
              width: 60,
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF14B8A6) : Colors.white, // Teal when selected
                borderRadius: BorderRadius.circular(12),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFF14B8A6).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    dayNames[date.weekday - 1],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.grey[600],
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    monthNames[date.month - 1],
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.grey[600],
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
      child: StreamBuilder<bool>(
        stream: selectedDate != null 
            ? _isSlotBlockedStream(venueName, time, _getDayName(selectedDate!))
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
    
    // Get or create a GlobalKey for this venue to scroll to it
    if (!_venueKeys.containsKey(venueName)) {
      _venueKeys[venueName] = GlobalKey();
    }
    final venueKey = _venueKeys[venueName]!;
    
    return Container(
      key: venueKey,
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
              final wasExpanded = _expandedVenues.contains(venueName);
              setState(() {
                if (wasExpanded) {
                  _expandedVenues.remove(venueName);
                } else {
                  _expandedVenues.add(venueName);
                }
              });
              // Don't scroll - just expand in place
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
                          '${sortedSlots.length} time slot${sortedSlots.length != 1 ? 's' : ''} available',
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
                children: _buildVenueSlotChildren(venueName, sortedSlots, slotCounts),
              ),
            ),
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
