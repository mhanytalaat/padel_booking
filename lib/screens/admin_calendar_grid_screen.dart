import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'home_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'home_screen.dart';

class AdminCalendarGridScreen extends StatefulWidget {
  const AdminCalendarGridScreen({super.key});

  @override
  State<AdminCalendarGridScreen> createState() => _AdminCalendarGridScreenState();
}

class _AdminCalendarGridScreenState extends State<AdminCalendarGridScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isAdmin = false;
  bool _isSubAdmin = false;
  List<String> _subAdminLocationIds = [];
  bool _checkingAuth = true;
  
  String? _selectedLocationId;
  DateTime _selectedDate = DateTime.now();
  String _viewMode = 'Day'; // 'Day', 'Week', 'Month'
  
  // Scroll controller for synchronized scrolling
  final ScrollController _timeScrollController = ScrollController();
  final List<ScrollController> _courtScrollControllers = [];
  bool _isSyncingScroll = false;
  
  // Color palette for booking blocks
  final List<Color> _bookingColors = [
    Colors.blue.shade300,
    Colors.green.shade300,
    Colors.orange.shade300,
    Colors.purple.shade300,
    Colors.red.shade300,
    Colors.teal.shade300,
    Colors.pink.shade300,
    Colors.amber.shade300,
  ];

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _setupScrollSync();
  }

  @override
  void dispose() {
    _timeScrollController.dispose();
    for (var controller in _courtScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setupScrollSync() {
    // Sync time column with court columns
    _timeScrollController.addListener(() {
      if (_isSyncingScroll) return;
      _isSyncingScroll = true;
      final offset = _timeScrollController.offset;
      if (offset.isNaN || offset.isInfinite) {
        _isSyncingScroll = false;
        return;
      }
      
      // Sync all court columns
      for (var controller in _courtScrollControllers) {
        if (controller.hasClients && (controller.offset - offset).abs() > 2.0) {
          controller.jumpTo(offset);
        }
      }
      
      Future.microtask(() => _isSyncingScroll = false);
    });
  }

  // Convert time from 12-hour format (e.g., "5:00 PM") to 24-hour format (e.g., "17:00")
  String _normalizeTimeTo24Hour(String timeStr) {
    try {
      // If already in 24-hour format (contains only numbers and colon), return as is
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(timeStr.trim())) {
        // Ensure it's in HH:MM format
        final parts = timeStr.trim().split(':');
        if (parts.length == 2) {
          final hour = int.tryParse(parts[0]) ?? 0;
          final minute = int.tryParse(parts[1]) ?? 0;
          return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
        }
        return timeStr;
      }
      
      // Parse 12-hour format (e.g., "5:00 PM" or "5:00PM")
      final cleaned = timeStr.trim().toUpperCase();
      final isPM = cleaned.contains('PM');
      final isAM = cleaned.contains('AM');
      
      // Extract hour and minute
      final timePart = cleaned.replaceAll(RegExp(r'[APM\s]'), '');
      final parts = timePart.split(':');
      
      if (parts.length >= 2) {
        int hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        
        // Convert to 24-hour format
        if (isPM && hour != 12) {
          hour += 12;
        } else if (isAM && hour == 12) {
          hour = 0;
        }
        
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      debugPrint('Error normalizing time "$timeStr": $e');
    }
    
    // Fallback: return original string
    return timeStr;
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
    
    // Get locations where user is sub-admin
    List<String> subAdminLocationIds = [];
    bool isSubAdminForAnyLocation = false;
    
    try {
      final locationsSnapshot = await FirebaseFirestore.instance
          .collection('courtLocations')
          .get();
      
      for (var doc in locationsSnapshot.docs) {
        final data = doc.data();
        final subAdmins = (data['subAdmins'] as List<dynamic>?) ?? [];
        if (subAdmins.contains(user.uid)) {
          subAdminLocationIds.add(doc.id);
          isSubAdminForAnyLocation = true;
        }
      }
    } catch (e) {
      debugPrint('Error checking sub-admin access: $e');
    }
    
    setState(() {
      _isAdmin = isMainAdmin;
      _isSubAdmin = isSubAdminForAnyLocation;
      _subAdminLocationIds = subAdminLocationIds;
      _checkingAuth = false;
    });
    
    if (!_isAdmin && !_isSubAdmin) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access denied. Admin or sub-admin access required.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (!_isAdmin && !_isSubAdmin) {
      return const Scaffold(
        body: Center(child: Text('Access denied')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Calendar'),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
              );
            }
          },
        ),
      ),
      body: Column(
        children: [
          _buildCalendarHeader(),
          Expanded(
            child: _buildCalendarGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    String dateRangeText;
    if (_viewMode == 'Day') {
      dateRangeText = DateFormat('MMM dd, yyyy').format(_selectedDate);
    } else if (_viewMode == 'Week') {
      final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      dateRangeText = '${DateFormat('MMM dd').format(startOfWeek)} - ${DateFormat('MMM dd, yyyy').format(endOfWeek)}';
    } else {
      dateRangeText = DateFormat('MMMM yyyy').format(_selectedDate);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() {
                        if (_viewMode == 'Day') {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                        } else {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                        }
                      });
                    },
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedDate = DateTime.now();
                      });
                    },
                    child: const Text('Today'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() {
                        if (_viewMode == 'Day') {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                        } else {
                          _selectedDate = _selectedDate.add(const Duration(days: 7));
                        }
                      });
                    },
                  ),
                ],
              ),
              Text(
                dateRangeText,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              DropdownButton<String>(
                value: _viewMode,
                items: const [
                  DropdownMenuItem(value: 'Day', child: Text('Day')),
                  DropdownMenuItem(value: 'Week', child: Text('Week')),
                  DropdownMenuItem(value: 'Month', child: Text('Month')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _viewMode = value;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Location filter
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('courtLocations').get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              List<DocumentSnapshot> locations = snapshot.data!.docs;
              
              if (_isSubAdmin && !_isAdmin) {
                locations = locations.where((doc) => _subAdminLocationIds.contains(doc.id)).toList();
              }

              return DropdownButtonFormField<String>(
                value: _selectedLocationId,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('All Locations'),
                  ),
                  ...locations.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text(data['name'] ?? doc.id),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedLocationId = value;
                  });
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    // Get dates for the week
    final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    final weekDates = List.generate(7, (index) => startOfWeek.add(Duration(days: index)));
    
    // Generate time slots (30-minute intervals from 6 AM to 11:30 PM)
    final timeSlots = <String>[];
    for (int hour = 6; hour < 24; hour++) {
      timeSlots.add('${hour.toString().padLeft(2, '0')}:00');
      timeSlots.add('${hour.toString().padLeft(2, '0')}:30');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _buildBookingsQuery(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
                const SizedBox(height: 8),
                const Text(
                  'Note: If filtering by location, you may need to create a Firestore index.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Process bookings into a map: date -> locationId -> court -> timeSlot -> booking data
        final bookingsMap = <String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>>{};
        
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final date = data['date'] as String? ?? '';
            final locationId = data['locationId'] as String? ?? '';
            final courts = data['courts'] as Map<String, dynamic>? ?? {};
            final userId = data['userId'] as String? ?? '';
            
            if (!bookingsMap.containsKey(date)) {
              bookingsMap[date] = {};
            }
            
            if (!bookingsMap[date]!.containsKey(locationId)) {
              bookingsMap[date]![locationId] = {};
            }
            
            for (var courtEntry in courts.entries) {
              final courtId = courtEntry.key;
              final slots = (courtEntry.value as List<dynamic>?)?.cast<String>() ?? [];
              
              if (!bookingsMap[date]![locationId]!.containsKey(courtId)) {
                bookingsMap[date]![locationId]![courtId] = {};
              }
              
              for (var slot in slots) {
                // Normalize time slot to 24-hour format for matching
                // Bookings store times like "5:00 PM", calendar uses "17:00"
                final normalizedSlot = _normalizeTimeTo24Hour(slot);
                bookingsMap[date]![locationId]![courtId]![normalizedSlot] = {
                  'userId': userId,
                  'bookingId': doc.id,
                  'data': data,
                };
              }
            }
          }
        }

        // Get courts for all locations or selected location
        // For Day view with "All Locations", show all locations' courts side by side
        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance.collection('courtLocations').get(),
          builder: (context, locationsSnapshot) {
            // Structure: List of {locationName, locationId, courts: [court1, court2, ...]}
            final List<Map<String, dynamic>> locationCourtsList = [];
            
            if (locationsSnapshot.hasData && locationsSnapshot.data!.docs.isNotEmpty) {
              List<DocumentSnapshot> locations = locationsSnapshot.data!.docs;
              
              // Filter locations for sub-admins
              if (_isSubAdmin && !_isAdmin) {
                locations = locations.where((doc) => _subAdminLocationIds.contains(doc.id)).toList();
              }
              
              // Filter by selected location if specified
              if (_selectedLocationId != null) {
                locations = locations.where((doc) => doc.id == _selectedLocationId).toList();
              }
              
              for (var locationDoc in locations) {
                try {
                  final locationData = locationDoc.data() as Map<String, dynamic>?;
                  final locationName = locationData?['name'] as String? ?? locationDoc.id;
                  final courtsData = (locationData?['courts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                  final courts = courtsData
                      .map((c) => c['id'] as String? ?? c['name'] as String? ?? '')
                      .where((id) => id.isNotEmpty)
                      .toList();
                  
                  if (courts.isNotEmpty) {
                    locationCourtsList.add({
                      'locationId': locationDoc.id,
                      'locationName': locationName,
                      'courts': courts,
                    });
                  }
                } catch (e) {
                  debugPrint('Error processing location ${locationDoc.id}: $e');
                }
              }
            }
            
            // If no locations found, use default
            if (locationCourtsList.isEmpty) {
              locationCourtsList.add({
                'locationId': 'default',
                'locationName': 'Default',
                'courts': List.generate(5, (i) => 'Court ${i + 1}'),
              });
            }

            return Row(
              children: [
                // Time column
                SizedBox(
                  width: 80,
                  child: Column(
                    children: [
                      const SizedBox(height: 40), // Header space
                      Expanded(
                        child: ListView.builder(
                          controller: _timeScrollController,
                          itemCount: timeSlots.length,
                          itemBuilder: (context, index) {
                            final time = timeSlots[index];
                            final isCurrentTime = _isCurrentTimeSlot(time);
                            
                            return Container(
                              height: 60,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey.shade300),
                                  right: BorderSide(color: Colors.grey.shade300),
                                ),
                                color: isCurrentTime ? Colors.red.shade50 : null,
                              ),
                              child: Center(
                                child: Text(
                                  _formatTime(time),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isCurrentTime ? FontWeight.bold : FontWeight.normal,
                                    color: isCurrentTime ? Colors.red : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // Show courts for Day view, courts with days for Week view
                Expanded(
                  child: _viewMode == 'Day'
                      ? _buildAllLocationsCourtColumns(locationCourtsList, timeSlots, bookingsMap)
                      : _buildWeekViewCourtColumns(locationCourtsList, weekDates, timeSlots, bookingsMap),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Stream<QuerySnapshot> _buildBookingsQuery() {
    Query query = FirebaseFirestore.instance.collection('courtBookings');
    
    if (_viewMode == 'Day') {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      query = query.where('date', isEqualTo: dateStr);
    } else if (_viewMode == 'Week') {
      final startOfWeek = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      final datesInRange = <String>[];
      for (var date = startOfWeek; date.isBefore(endOfWeek.add(const Duration(days: 1))); date = date.add(const Duration(days: 1))) {
        datesInRange.add(DateFormat('yyyy-MM-dd').format(date));
      }
      query = query.where('date', whereIn: datesInRange.length > 10 ? datesInRange.take(10).toList() : datesInRange);
    }
    
    // Filter by location
    if (_selectedLocationId != null) {
      query = query.where('locationId', isEqualTo: _selectedLocationId);
    } else if (_isSubAdmin && !_isAdmin && _subAdminLocationIds.isNotEmpty) {
      if (_subAdminLocationIds.length == 1) {
        query = query.where('locationId', isEqualTo: _subAdminLocationIds.first);
      }
      // For multiple locations, filter client-side
    }
    
    return query.snapshots();
  }

  Widget _buildAllLocationsCourtColumns(List<Map<String, dynamic>> locationCourtsList, List<String> timeSlots,
      Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>> bookingsMap) {
    // For Day view with all locations, show all courts from all locations side by side
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    // Calculate total courts and ensure we have enough scroll controllers
    int totalCourts = locationCourtsList.fold(0, (sum, loc) => sum + (loc['courts'] as List).length);
    while (_courtScrollControllers.length < totalCourts) {
      final controller = ScrollController();
      final index = _courtScrollControllers.length;
      
      // Sync with time column and other court columns
      controller.addListener(() {
        if (_isSyncingScroll) return;
        _isSyncingScroll = true;
        final offset = controller.offset;
        if (offset.isNaN || offset.isInfinite) {
          _isSyncingScroll = false;
          return;
        }
        
        // Sync time column
        if (_timeScrollController.hasClients && (_timeScrollController.offset - offset).abs() > 2.0) {
          _timeScrollController.jumpTo(offset);
        }
        
        // Sync all other court columns
        for (int j = 0; j < _courtScrollControllers.length; j++) {
          if (j != index && _courtScrollControllers[j].hasClients) {
            final otherController = _courtScrollControllers[j];
            if ((otherController.offset - offset).abs() > 2.0) {
              otherController.jumpTo(offset);
            }
          }
        }
        
        Future.microtask(() => _isSyncingScroll = false);
      });
      
      _courtScrollControllers.add(controller);
    }
    
    // Remove excess controllers
    while (_courtScrollControllers.length > totalCourts) {
      _courtScrollControllers.removeLast().dispose();
    }
    
    int controllerIndex = 0;
    
    // Determine column width based on platform and screen size
    // On mobile, show 2-3 courts at a time, on web/tablet show more
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = !kIsWeb && screenWidth < 600;
    final columnWidth = isMobile ? screenWidth / 2.5 : null; // Show ~2.5 courts on mobile
    
    final courtColumns = locationCourtsList.expand((locationData) {
          final locationId = locationData['locationId'] as String;
          final locationName = locationData['locationName'] as String;
          final courts = (locationData['courts'] as List).cast<String>();
          
          return courts.map((court) {
            final scrollController = _courtScrollControllers[controllerIndex++];
            
            final columnWidget = Column(
              children: [
                // Court header with location name
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300),
                      right: BorderSide(color: Colors.grey.shade300),
                    ),
                    color: Colors.grey.shade100,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            locationName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            court,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Time slots grid
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: timeSlots.length,
                    itemBuilder: (context, index) {
                      final time = timeSlots[index];
                      final isCurrentTime = _isCurrentTimeSlot(time);
                      
                      // Find booking for this location, court and time
                      Map<String, dynamic>? bookingData;
                      
                      if (bookingsMap.containsKey(selectedDateStr) &&
                          bookingsMap[selectedDateStr]!.containsKey(locationId) &&
                          bookingsMap[selectedDateStr]![locationId]!.containsKey(court) &&
                          bookingsMap[selectedDateStr]![locationId]![court]!.containsKey(time)) {
                        bookingData = bookingsMap[selectedDateStr]![locationId]![court]![time];
                      }
                      
                      return Container(
                        height: 60,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade300),
                            right: BorderSide(color: Colors.grey.shade300),
                          ),
                          color: isCurrentTime ? Colors.red.shade50 : Colors.white,
                        ),
                        child: bookingData != null
                            ? SizedBox(
                                height: 60,
                                child: _buildBookingBlock(bookingData, '$locationName - $court', time),
                              )
                            : const SizedBox.shrink(),
                      );
                    },
                  ),
                ),
              ],
            );
            
            if (isMobile && columnWidth != null) {
              return SizedBox(width: columnWidth, child: columnWidget);
            } else {
              return Expanded(child: columnWidget);
            }
          });
      }).toList();
    
    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: courtColumns),
      );
    } else {
      return Row(children: courtColumns);
    }
  }

  Widget _buildWeekViewCourtColumns(List<Map<String, dynamic>> locationCourtsList, List<DateTime> weekDates,
      List<String> timeSlots, Map<String, Map<String, Map<String, Map<String, Map<String, dynamic>>>>> bookingsMap) {
    // For Week view, show dates as column headers, time as rows, courts listed in cells
    
    // Ensure we have enough scroll controllers for all date columns (7 days)
    while (_courtScrollControllers.length < 7) {
      final controller = ScrollController();
      final index = _courtScrollControllers.length;
      
      // Sync with time column and other columns
      controller.addListener(() {
        if (_isSyncingScroll) return;
        _isSyncingScroll = true;
        final offset = controller.offset;
        if (offset.isNaN || offset.isInfinite) {
          _isSyncingScroll = false;
          return;
        }
        
        // Sync time column
        if (_timeScrollController.hasClients && (_timeScrollController.offset - offset).abs() > 2.0) {
          _timeScrollController.jumpTo(offset);
        }
        
        // Sync all other date columns
        for (int j = 0; j < _courtScrollControllers.length; j++) {
          if (j != index && _courtScrollControllers[j].hasClients) {
            final otherController = _courtScrollControllers[j];
            if ((otherController.offset - offset).abs() > 2.0) {
              otherController.jumpTo(offset);
            }
          }
        }
        
        Future.microtask(() => _isSyncingScroll = false);
      });
      
      _courtScrollControllers.add(controller);
    }
    
    // Remove excess controllers
    while (_courtScrollControllers.length > 7) {
      _courtScrollControllers.removeLast().dispose();
    }
    
    return Row(
      children: weekDates.asMap().entries.map((entry) {
        final index = entry.key;
        final date = entry.value;
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final scrollController = _courtScrollControllers[index];
        
        return Expanded(
          child: Column(
            children: [
              // Date header
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                    right: BorderSide(color: Colors.grey.shade300),
                  ),
                  color: Colors.grey.shade100,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('EEE').format(date),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        DateFormat('MMM dd').format(date),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Time slots grid
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: timeSlots.length,
                  itemBuilder: (context, timeIndex) {
                    final time = timeSlots[timeIndex];
                    final isCurrentTime = _isCurrentTimeSlot(time);
                    
                    // Find all courts booked at this date and time
                    final List<String> bookedCourts = [];
                    final Map<String, String> courtToLocation = {}; // court -> location name
                    
                    if (bookingsMap.containsKey(dateStr)) {
                      for (var locationEntry in bookingsMap[dateStr]!.entries) {
                        final locationId = locationEntry.key;
                        // Find location name
                        String? locationName;
                        for (var locData in locationCourtsList) {
                          if (locData['locationId'] == locationId) {
                            locationName = locData['locationName'] as String;
                            break;
                          }
                        }
                        
                        for (var courtEntry in locationEntry.value.entries) {
                          final courtId = courtEntry.key;
                          if (courtEntry.value.containsKey(time)) {
                            // Format: "locationName courtId" or just "courtId" if same location
                            final displayName = locationName != null 
                                ? '$locationName $courtId'
                                : courtId;
                            bookedCourts.add(displayName);
                            courtToLocation[displayName] = locationName ?? '';
                          }
                        }
                      }
                    }
                    
                    return Container(
                      height: 60,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                          right: BorderSide(color: Colors.grey.shade300),
                        ),
                        color: isCurrentTime ? Colors.red.shade50 : Colors.white,
                      ),
                      child: bookedCourts.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Center(
                                child: Text(
                                  bookedCourts.join(' '),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  List<String> _getAllCourts(List<Map<String, dynamic>> locationCourtsList) {
    final allCourts = <String>[];
    for (var location in locationCourtsList) {
      allCourts.addAll((location['courts'] as List).cast<String>());
    }
    return allCourts.isEmpty ? List.generate(5, (i) => 'Court ${i + 1}') : allCourts;
  }

  Widget _buildBookingBlock(Map<String, dynamic> bookingData, String courtId, String timeSlot) {
    final userId = bookingData['userId'] as String? ?? '';
    final bookingInfo = bookingData['data'] as Map<String, dynamic>;
    
    // Get color based on user ID hash
    final colorIndex = userId.hashCode.abs() % _bookingColors.length;
    final color = _bookingColors[colorIndex];
    
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, userSnapshot) {
        String userName = 'Unknown';
        String phone = 'No phone';
        
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade400, width: 1),
            ),
            padding: const EdgeInsets.all(4),
            child: const Center(
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
          final firstName = userData?['firstName'] as String? ?? '';
          final lastName = userData?['lastName'] as String? ?? '';
          userName = userData?['fullName'] as String? ?? 
              (firstName.isNotEmpty || lastName.isNotEmpty 
                  ? '$firstName $lastName'.trim() 
                  : 'Unknown');
          phone = userData?['phone'] as String? ?? 'No phone';
        }
        
        return Container(
          height: 60,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade400, width: 1),
          ),
          padding: const EdgeInsets.all(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person, size: 10, color: Colors.grey.shade800),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      userName,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone, size: 9, color: Colors.grey.shade700),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      phone,
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.grey.shade800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isCurrentTimeSlot(String timeSlot) {
    try {
      final now = DateTime.now();
      final currentHour = now.hour;
      final currentMinute = now.minute;
      final currentSlot = '${currentHour.toString().padLeft(2, '0')}:${(currentMinute < 30 ? 0 : 30).toString().padLeft(2, '0')}';
      return timeSlot == currentSlot && DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(now);
    } catch (e) {
      return false;
    }
  }

  String _formatTime(String timeSlot) {
    try {
      // Convert 24-hour format to 12-hour format for display
      final parts = timeSlot.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
      }
    } catch (e) {
      debugPrint('Error formatting time "$timeSlot": $e');
    }
    return timeSlot;
  }
}
