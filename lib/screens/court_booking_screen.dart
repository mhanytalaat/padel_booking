import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'court_booking_confirmation_screen.dart';
import 'admin_calendar_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class CourtBookingScreen extends StatefulWidget {
  final String locationId;

  const CourtBookingScreen({
    super.key,
    required this.locationId,
  });

  @override
  State<CourtBookingScreen> createState() => _CourtBookingScreenState();
}

class _CourtBookingScreenState extends State<CourtBookingScreen> with TickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  final Map<String, List<String>> _selectedSlots = {}; // courtId -> [time slots]
  String? _locationName;
  String? _locationAddress;
  String? _locationLogoUrl;
  String? _phoneNumber;
  String? _mapsUrl;
  Map<String, dynamic>? _locationData;
  List<String> _cachedTimeSlots = []; // Cache time slots to avoid regeneration
  List<String> _regularSlots = []; // Regular hours slots
  List<String> _midnightSlots = []; // Midnight play slots (12:00 AM - 4:00 AM)
  int _midnightStartIndex = -1; // Index where midnight play starts
  final List<ScrollController> _courtScrollControllers = []; // Individual controllers for each court
  bool _isSyncingScroll = false; // Flag to prevent infinite scroll loops
  bool _isLoading = true; // Loading state
  Set<String> _bookedSlots = {}; // Set of booked slots: "courtId|timeSlot" format
  late AnimationController _racketAnimationController;
  late AnimationController _ballAnimationController;
  bool _isAdmin = false;
  bool _isSubAdmin = false;
  bool _checkingAuth = true;

  @override
  void initState() {
    super.initState();
    // Initialize animation controllers
    _racketAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _ballAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
    
    // Show UI immediately with default data, then load
    _locationName = 'Select Court'; // Default name, not "Loading..."
    _locationAddress = '';
    _cachedTimeSlots = _generateSlotsBetween('6:00 AM', '11:00 PM', '5:00 AM'); // Default slots
    _loadLocationData(); // Load in background
    _loadBookedSlots(); // Load booked slots
    _checkAdminAccess(); // Check if user is admin or sub-admin
  }

  Future<void> _checkAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isAdmin = false;
        _isSubAdmin = false;
        _checkingAuth = false;
      });
      return;
    }

    // Check if main admin
    final isMainAdmin = user.phoneNumber == '+201006500506' || user.email == 'admin@padelcore.com';
    
    // Check if sub-admin for this location
    bool isSubAdminForLocation = false;
    try {
      final locationDoc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(widget.locationId)
          .get();
      
      if (locationDoc.exists) {
        final subAdmins = (locationDoc.data()?['subAdmins'] as List?)?.cast<String>() ?? [];
        isSubAdminForLocation = subAdmins.contains(user.uid);
      }
    } catch (e) {
      // Permission denied during sign-out is expected, ignore silently
      if (!e.toString().contains('permission-denied')) {
        debugPrint('Error checking sub-admin access: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isAdmin = isMainAdmin;
        _isSubAdmin = isSubAdminForLocation;
        _checkingAuth = false;
      });
    }
  }

  @override
  void dispose() {
    _racketAnimationController.dispose();
    _ballAnimationController.dispose();
    for (var controller in _courtScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLocationData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(widget.locationId)
          .get();
      
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _locationData = data;
          _locationName = data['name'] as String?;
          _locationAddress = data['address'] as String?;
          _locationLogoUrl = data['logoUrl'] as String?;
          _phoneNumber = data['phoneNumber'] as String?;
          _mapsUrl = data['mapsUrl'] as String?;
          // Generate and cache time slots once
          _cachedTimeSlots = _generateTimeSlotsFromData(data);
          _isLoading = false; // Data loaded
        });
      } else if (mounted) {
        setState(() {
          _locationName = 'Location not found';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading location: $e');
      if (mounted) {
        setState(() {
          _locationName = 'Error loading location';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadBookedSlots() async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final bookingsSnapshot = await FirebaseFirestore.instance
          .collection('courtBookings')
          .where('locationId', isEqualTo: widget.locationId)
          .where('date', isEqualTo: dateStr)
          .where('status', whereIn: ['confirmed', 'pending']) // Only active bookings
          .get();
      
      final bookedSlotsSet = <String>{};
      
      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final courts = data['courts'] as Map<String, dynamic>? ?? {};
        
        for (var entry in courts.entries) {
          final courtId = entry.key;
          final slots = (entry.value as List<dynamic>?)?.cast<String>() ?? [];
          
          for (var slot in slots) {
            bookedSlotsSet.add('$courtId|$slot');
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _bookedSlots = bookedSlotsSet;
        });
      }
    } catch (e) {
      debugPrint('Error loading booked slots: $e');
    }
  }

  bool _isSlotBooked(String courtId, String timeSlot) {
    return _bookedSlots.contains('$courtId|$timeSlot');
  }

  bool _isSlotInPast(String timeSlot) {
    try {
      final format = DateFormat('h:mm a');
      final slotTime = format.parse(timeSlot);
      
      // Early morning slots (12:00 AM - 6:00 AM) are from the next day, so they're always available
      if (slotTime.hour >= 0 && slotTime.hour < 6) {
        return false; // These are next day slots, always available
      }
      
      // For other slots, check if they're in the past for the selected date
      final slotDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        slotTime.hour,
        slotTime.minute,
      );
      
      // Only check if past if the selected date is today
      final now = DateTime.now();
      final isToday = _selectedDate.year == now.year &&
          _selectedDate.month == now.month &&
          _selectedDate.day == now.day;
      
      if (isToday) {
        return slotDateTime.isBefore(now);
      }
      
      return false; // Future dates are always available
    } catch (e) {
      return false;
    }
  }

  void _toggleSlot(String courtId, String timeSlot) {
    // Don't allow booking if slot is booked or in the past
    if (_isSlotBooked(courtId, timeSlot) || _isSlotInPast(timeSlot)) {
      return;
    }
    
    // Create new map to avoid mutation issues
    final newSelectedSlots = Map<String, List<String>>.from(_selectedSlots);
    
    if (!newSelectedSlots.containsKey(courtId)) {
      newSelectedSlots[courtId] = [];
    }
    
    final courtSlots = List<String>.from(newSelectedSlots[courtId]!);
    
    if (courtSlots.contains(timeSlot)) {
      courtSlots.remove(timeSlot);
      if (courtSlots.isEmpty) {
        newSelectedSlots.remove(courtId);
      } else {
        newSelectedSlots[courtId] = courtSlots;
      }
    } else {
      courtSlots.add(timeSlot);
      courtSlots.sort();
      newSelectedSlots[courtId] = courtSlots;
    }
    
    setState(() {
      _selectedSlots.clear();
      _selectedSlots.addAll(newSelectedSlots);
    });
  }

  double _calculateTotalCost() {
    if (_locationData == null) return 0.0;
    
    final pricePer30Min = (_locationData!['pricePer30Min'] as num?)?.toDouble() ?? 0.0;
    double total = 0.0;
    
    for (var slots in _selectedSlots.values) {
      total += slots.length * pricePer30Min;
    }
    
    return total;
  }

  double _calculateDuration() {
    double totalMinutes = 0.0;
    for (var slots in _selectedSlots.values) {
      totalMinutes += slots.length * 30;
    }
    return totalMinutes / 60; // Convert to hours
  }

  String _getTimeRange() {
    if (_selectedSlots.isEmpty) return '';
    
    // Collect all selected time slots from all courts
    final allSlots = <String>[];
    for (var slots in _selectedSlots.values) {
      allSlots.addAll(slots);
    }
    
    if (allSlots.isEmpty) return '';
    
    // Sort slots chronologically
    allSlots.sort((a, b) {
      try {
        final timeA = _parseTime(a);
        final timeB = _parseTime(b);
        return timeA.compareTo(timeB);
      } catch (e) {
        return a.compareTo(b);
      }
    });
    
    final startTime = allSlots.first;
    final endSlot = _parseTime(allSlots.last);
    // Add 30 minutes to the last slot to get the end time
    final endTime = endSlot.add(const Duration(minutes: 30));
    final endTimeStr = _formatTime(endTime);
    
    final duration = _calculateDuration();
    final hours = duration.floor();
    final minutes = ((duration - hours) * 60).round();
    
    String durationStr;
    if (hours > 0 && minutes > 0) {
      durationStr = '$hours hour${hours > 1 ? 's' : ''} $minutes minute${minutes > 1 ? 's' : ''}';
    } else if (hours > 0) {
      durationStr = '$hours hour${hours > 1 ? 's' : ''}';
    } else {
      durationStr = '$minutes minute${minutes > 1 ? 's' : ''}';
    }
    
    return 'From $startTime to $endTimeStr : $durationStr';
  }

  List<String> _generateTimeSlotsFromData(Map<String, dynamic> data) {
    final openTime = data['openTime'] as String? ?? '6:00 AM';
    final closeTime = data['closeTime'] as String? ?? '11:00 PM';
    final midnightPlayEndTime = data['midnightPlayEndTime'] as String? ?? '6:00 AM'; // Default to 6 AM, can be 12:30 AM to 6:00 AM
    
    return _generateSlotsBetween(openTime, closeTime, midnightPlayEndTime);
  }

  List<String> _generateSlotsBetween(String start, String end, [String? midnightPlayEnd]) {
    final startTime = _parseTime(start);
    final endTime = _parseTime(end);
    final slots = <String>[];
    final regularSlots = <String>[];
    final midnightSlots = <String>[];
    
    final nextDayMidnight = DateTime(startTime.year, startTime.month, startTime.day + 1, 0, 0);
    
    // Check if close time is midnight (12:00 AM)
    final endHour = endTime.hour;
    final endMinute = endTime.minute;
    final isMidnightClose = endHour == 0 && endMinute == 0;
    
    // Regular hours: from start time to close time
    // If close time is midnight, regular hours go up to 11:30 PM (last slot before midnight)
    // If close time is before midnight, regular hours go up to close time
    var current = startTime;
    final regularEndTime = isMidnightClose 
        ? nextDayMidnight.subtract(const Duration(minutes: 30)) // 11:30 PM
        : endTime;
    
    while (current.isBefore(regularEndTime) || current.isAtSameMomentAs(regularEndTime)) {
      final timeStr = _formatTime(current);
      regularSlots.add(timeStr);
      slots.add(timeStr);
      current = current.add(const Duration(minutes: 30));
      
      // Stop if we've passed the regular end time
      if (current.isAfter(regularEndTime)) {
        break;
      }
    }
    
    // Midnight play: 12:00 AM to configured end time - next day
    // Only add if close time is 12:00 AM (midnight)
    if (isMidnightClose) {
      // Close time is midnight, add midnight play slots
      final midnightEndTimeStr = midnightPlayEnd ?? '6:00 AM';
      final midnightEndTime = _parseTime(midnightEndTimeStr);
      // Convert to next day
      final midnightEnd = DateTime(
        startTime.year, 
        startTime.month, 
        startTime.day + 1, 
        midnightEndTime.hour, 
        midnightEndTime.minute
      );
      
      var midnightCurrent = nextDayMidnight;
      
      while (midnightCurrent.isBefore(midnightEnd)) {
        final timeStr = _formatTime(midnightCurrent);
        midnightSlots.add(timeStr);
        slots.add(timeStr);
        midnightCurrent = midnightCurrent.add(const Duration(minutes: 30));
      }
    }
    
    // Update state
    _regularSlots = regularSlots;
    _midnightSlots = midnightSlots;
    _midnightStartIndex = regularSlots.length > 0 && midnightSlots.isNotEmpty ? regularSlots.length : -1;
    
    return slots;
  }

  DateTime _parseTime(String timeStr) {
    try {
      final format = DateFormat('h:mm a');
      return format.parse(timeStr);
    } catch (e) {
      // Fallback parsing
      final parts = timeStr.replaceAll(' ', '').toUpperCase().split(RegExp(r'[:\s]'));
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        final isPM = parts.length > 2 && parts[2].contains('PM');
        final hour24 = isPM && hour != 12 ? hour + 12 : (hour == 12 && !isPM ? 0 : hour);
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, hour24, minute);
      }
      return DateTime.now();
    }
  }

  String _formatTime(DateTime time) {
    final format = DateFormat('h:mm a');
    return format.format(time);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppHeader(
        titleWidget: _buildTitleWithLogo(),
        actions: [
          if (_phoneNumber != null && _phoneNumber!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone),
              onPressed: () {
                _launchUrl('tel:$_phoneNumber');
              },
              tooltip: 'Call',
            ),
          if (_mapsUrl != null && _mapsUrl!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.map),
              onPressed: () {
                _launchUrl(_mapsUrl!);
              },
              tooltip: 'View on Map',
            ),
        ],
      ),
      bottomNavigationBar: const AppFooter(),
      body: _isLoading
          ? _buildLoadingAnimation()
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('courtBookings')
                  .where('locationId', isEqualTo: widget.locationId)
                  .where('date', isEqualTo: DateFormat('yyyy-MM-dd').format(_selectedDate))
                  .where('status', whereIn: ['confirmed', 'pending'])
                  .snapshots(),
              builder: (context, bookingsSnapshot) {
                // Update booked slots from stream
                if (bookingsSnapshot.hasData) {
                  final bookedSlotsSet = <String>{};
                  
                  for (var doc in bookingsSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final courts = data['courts'] as Map<String, dynamic>? ?? {};
                    
                    for (var entry in courts.entries) {
                      final courtId = entry.key;
                      final slots = (entry.value as List<dynamic>?)?.cast<String>() ?? [];
                      
                      for (var slot in slots) {
                        bookedSlotsSet.add('$courtId|$slot');
                      }
                    }
                  }
                  
                  // Update state without rebuilding entire widget tree
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _bookedSlots = bookedSlotsSet;
                      });
                    }
                  });
                }
                
                // Use cached data or default - don't wait for locationData
                final locationData = _locationData ?? {};
                final courts = (locationData['courts'] as List?)?.cast<Map<String, dynamic>>() ?? 
                    List.generate(5, (i) => {'id': 'court_${i + 1}', 'name': 'Court ${i + 1}'});
                final timeSlots = _cachedTimeSlots;

                return Column(
            children: [
              // Date Selector
              _buildDateSelector(),
              
              // Location Info
              if (_locationAddress != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _locationAddress!,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          const Icon(Icons.sports_tennis, size: 16, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            '${courts.length} ${courts.length == 1 ? 'Court' : 'Courts'}',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Courts and Time Slots
              Expanded(
                child: courts.isEmpty
                    ? const Center(
                        child: Text(
                          'No courts available',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : _buildSynchronizedCourts(courts, timeSlots),
              ),

                    // Summary Bar
                    if (_selectedSlots.isNotEmpty) _buildSummaryBar(locationData),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: const Color(0xFF0A0E27),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatDate(_selectedDate),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 7, // 7 days ahead for regular users
                    itemBuilder: (context, index) {
                      final date = now.add(Duration(days: index));
                final isSelected = date.day == _selectedDate.day &&
                    date.month == _selectedDate.month &&
                    date.year == _selectedDate.year;
                final dayName = _getDayName(date.weekday);
                final dayNumber = date.day;

                final isPast = date.isBefore(DateTime.now().subtract(const Duration(days: 1)));
                
                return GestureDetector(
                  onTap: isPast ? null : () {
                    setState(() {
                      _selectedDate = date;
                      _selectedSlots.clear(); // Clear selections when date changes
                    });
                    _loadBookedSlots(); // Reload booked slots for new date
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: isPast 
                          ? Colors.grey.withOpacity(0.3) 
                          : (isSelected ? Colors.green.withOpacity(0.2) : Colors.white),
                      borderRadius: BorderRadius.circular(6), // Cubical/square with rounded corners
                      border: isSelected
                          ? Border.all(color: Colors.green, width: 2)
                          : (isPast 
                              ? Border.all(color: Colors.grey.withOpacity(0.5), width: 1)
                              : Border.all(color: Colors.grey.withOpacity(0.3), width: 1)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayName,
                          style: TextStyle(
                            fontSize: 8,
                            color: isPast 
                                ? Colors.grey.shade600 
                                : (isSelected ? Colors.green.shade700 : Colors.black),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 12,
                            color: isPast 
                                ? Colors.grey.shade600 
                                : (isSelected ? Colors.green.shade700 : Colors.black),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
                    ),
                  ),
                ),
              // Calendar button for admin/sub-admin only
              if (!_checkingAuth && (_isAdmin || _isSubAdmin))
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AdminCalendarScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 38,
                        height: 38,
                        padding: const EdgeInsets.all(8),
                        child: const Icon(
                          Icons.calendar_month,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSynchronizedCourts(List<Map<String, dynamic>> courts, List<String> timeSlots) {
    // Ensure we have enough scroll controllers
    while (_courtScrollControllers.length < courts.length) {
      final controller = ScrollController();
      final index = _courtScrollControllers.length;
      
      // Add listener to sync scrolling - optimized to reduce lag
      controller.addListener(() {
        if (_isSyncingScroll || !controller.hasClients) return;
        
        final offset = controller.offset;
        // Only sync if scroll has moved significantly (reduces unnecessary updates)
        if (offset.isNaN || offset.isInfinite) return;
        
        _isSyncingScroll = true;
        
        // Use Future.microtask to batch updates and reduce lag
        Future.microtask(() {
          if (!mounted) {
            _isSyncingScroll = false;
            return;
          }
          
          // Update all other controllers to match
          for (int j = 0; j < _courtScrollControllers.length; j++) {
            if (j != index && _courtScrollControllers[j].hasClients) {
              final otherController = _courtScrollControllers[j];
              final diff = (otherController.offset - offset).abs();
              // Only update if difference is significant (reduces jitter)
              if (diff > 2.0) {
                otherController.jumpTo(offset);
              }
            }
          }
          
          _isSyncingScroll = false;
        });
      });
      
      _courtScrollControllers.add(controller);
    }
    
    // Remove excess controllers
    while (_courtScrollControllers.length > courts.length) {
      _courtScrollControllers.removeLast().dispose();
    }

    // Show courts with dynamic width based on count
    final courtCount = courts.length;
    final courtWidth = courtCount < 3 
        ? MediaQuery.of(context).size.width / 2  // 2 columns (wider) when less than 3 courts
        : MediaQuery.of(context).size.width / 3; // 3 columns when 3+ courts
    
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7, // Adjust height as needed
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: courts.length,
        itemBuilder: (context, index) {
          final court = courts[index];
          final courtId = court['id'] as String? ?? '';
          final courtName = court['name'] as String? ?? 'Court ${index + 1}';
          final scrollController = _courtScrollControllers[index];
          
          return SizedBox(
            width: courtWidth,
            child: _buildCourtColumn(
              courtId: courtId,
              courtName: courtName,
              timeSlots: timeSlots,
              scrollController: scrollController,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCourtColumn({
    required String courtId,
    required String courtName,
    required List<String> timeSlots,
    required ScrollController scrollController,
  }) {
    final selectedSlots = _selectedSlots[courtId] ?? [];
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          // Court Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(
                  courtName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.circle, size: 8, color: Colors.orange),
              ],
            ),
          ),
          // Time Slots
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              key: ValueKey('court_$courtId'),
              cacheExtent: 200, // Reduced from 500 to improve performance
              physics: const ClampingScrollPhysics(), // Smoother scrolling
              itemCount: timeSlots.length + (_midnightStartIndex >= 0 && _midnightSlots.isNotEmpty ? 1 : 0), // +1 for separator
              itemBuilder: (context, index) {
                // Check if this is the separator position
                if (_midnightStartIndex >= 0 && _midnightSlots.isNotEmpty && index == _midnightStartIndex) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        const Divider(
                          color: Colors.white30,
                          thickness: 1,
                          height: 1,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Midnight Play',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                }
                
                // Adjust index if we're past the separator
                final actualIndex = _midnightStartIndex >= 0 && _midnightSlots.isNotEmpty && index > _midnightStartIndex
                    ? index - 1
                    : index;
                
                if (actualIndex >= timeSlots.length) {
                  return const SizedBox.shrink();
                }
                
                final slot = timeSlots[actualIndex];
                final isSelected = selectedSlots.contains(slot);
                final isBooked = _isSlotBooked(courtId, slot);
                final isPast = _isSlotInPast(slot);
                final isDisabled = isBooked || isPast;
                final isMidnightSlot = _midnightSlots.contains(slot);
                
                // Check if this is the start of a new hour (e.g., 9:00 AM, 10:00 AM)
                final isHourStart = slot.contains(':00 ');
                
                return RepaintBoundary(
                  key: ValueKey('slot_${courtId}_$slot'),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: isHourStart && actualIndex > 0 ? 12 : 3,
                      bottom: 3,
                      left: 4,
                      right: 4,
                    ),
                    child: InkWell(
                      onTap: isDisabled ? null : () => _toggleSlot(courtId, slot),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 48, // Fixed height for alignment
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: (isBooked && !isPast)
                              ? const Color(0xFF2E6C4A) // Dark green background for booked
                              : (isSelected 
                                  ? Colors.white // White background when selected (before booking)
                                  : (isPast ? Colors.grey.shade600 : Colors.white)), // Medium grey for past
                          borderRadius: BorderRadius.circular(16),
                          border: (isBooked && !isPast)
                              ? Border.all(color: const Color(0xFF2E6C4A), width: 1)
                              : (isSelected
                                  ? Border.all(color: Colors.green, width: 2) // Green border when selected
                                  : Border.all(
                                      color: isPast ? Colors.grey.shade700 : Colors.grey.shade300,
                                      width: 1,
                                    )),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isSelected || (isBooked && !isPast))
                                Icon(
                                  Icons.check_circle, 
                                  color: isSelected ? Colors.green : const Color(0xFF80CD9A), 
                                  size: 16
                                ),
                              if (isSelected || (isBooked && !isPast)) const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  slot,
                                  style: TextStyle(
                                    color: (isBooked && !isPast)
                                        ? const Color(0xFF80CD9A) // Lighter green text for booked
                                        : (isSelected
                                            ? Colors.green // Green text when selected (before booking)
                                            : (isPast ? Colors.white : Colors.black)), // White text for past, black for available
                                    fontSize: 11,
                                    fontWeight: (isSelected || (isBooked && !isPast)) ? FontWeight.bold : FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSummaryBar(Map<String, dynamic> locationData) {
    final totalCost = _calculateTotalCost();
    final duration = _calculateDuration();
    final pricePer30Min = (locationData['pricePer30Min'] as num?)?.toDouble() ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total amount',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${totalCost.toStringAsFixed(0)} EGP',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_selectedSlots.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'From: ${_getTimeRange()}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${duration.toStringAsFixed(1)} hour${duration != 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () {
                if (_selectedSlots.isEmpty) return;
                
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CourtBookingConfirmationScreen(
                      locationId: widget.locationId,
                      locationName: _locationName ?? '',
                      locationAddress: _locationAddress ?? '',
                      selectedDate: _selectedDate,
                      selectedSlots: _selectedSlots,
                      totalCost: totalCost,
                      pricePer30Min: pricePer30Min,
                      locationLogoUrl: _locationLogoUrl,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(80, 48),
                elevation: 0,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NEXT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  Widget _buildLoadingAnimation() {
    return Container(
      color: const Color(0xFF0A0E27),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Padel racket animation (swinging)
            AnimatedBuilder(
              animation: _racketAnimationController,
              builder: (context, child) {
                final value = _racketAnimationController.value;
                return Transform.translate(
                  offset: Offset(
                    (value * 100 - 50) * (1 - (value * 2 - 1).abs()), // Bouncing motion
                    -50 * (value * 2 - 1).abs() * (value * 2 - 1).abs(), // Up and down
                  ),
                  child: Transform.rotate(
                    angle: value * 2 * 3.14159, // Rotation
                    child: Icon(
                      Icons.sports_tennis,
                      size: 60,
                      color: Colors.amber[300],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            // Ball bouncing animation
            AnimatedBuilder(
              animation: _ballAnimationController,
              builder: (context, child) {
                final value = _ballAnimationController.value;
                return Transform.translate(
                  offset: Offset(0, -30 * (value * 2 - 1).abs() * (value * 2 - 1).abs()),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.yellow,
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 30),
            const Text(
              'Loading courts...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleWithLogo() {
    final locationName = _locationName ?? 'Select Court';
    
    // If no logo URL, just return the text
    if (_locationLogoUrl == null || _locationLogoUrl!.isEmpty) {
      return Text(locationName);
    }
    
    // Build title with logo
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1),
          ),
          child: ClipOval(
            child: _buildNetworkImage(
              _locationLogoUrl!,
              locationName,
              width: 32,
              height: 32,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Location name
        Flexible(
          child: Text(
            locationName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkImage(String imageUrl, String fallbackText, {double? width, double? height}) {
    // Try Image.network first - if CORS is configured, it will work
    // If it fails, show fallback
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        // If image fails to load, show fallback icon
        return _buildFallbackIcon(fallbackText, width: width, height: height);
      },
    );
  }

  Widget _buildFallbackIcon(String fallbackText, {double? width, double? height}) {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open $url'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
