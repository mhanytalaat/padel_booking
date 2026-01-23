import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'admin_calendar_grid_screen.dart';

class AdminCalendarScreen extends StatefulWidget {
  const AdminCalendarScreen({super.key});

  @override
  State<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends State<AdminCalendarScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isAdmin = false;
  bool _isSubAdmin = false;
  List<String> _subAdminLocationIds = [];
  bool _checkingAuth = true;
  
  String? _selectedLocationId;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  
  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
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
        final subAdmins = (doc.data()['subAdmins'] as List?)?.cast<String>() ?? [];
        if (subAdmins.contains(user.uid)) {
          subAdminLocationIds.add(doc.id);
          isSubAdminForAnyLocation = true;
        }
      }
    } catch (e) {
      debugPrint('Error checking sub-admin access: $e');
    }

    if (mounted) {
      setState(() {
        _isAdmin = isMainAdmin;
        _isSubAdmin = isSubAdminForAnyLocation;
        _subAdminLocationIds = subAdminLocationIds;
        _checkingAuth = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Calendar'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin && !_isSubAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Calendar'),
        ),
        body: const Center(
          child: Text('You are not authorized to access this page.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminCalendarGridScreen(),
                ),
              );
            },
            tooltip: 'Grid View',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: _buildBookingsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location filter
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance.collection('courtLocations').get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              List<DocumentSnapshot> locations = snapshot.data!.docs;
              
              // Filter locations for sub-admins
              if (_isSubAdmin && !_isAdmin) {
                locations = locations.where((doc) => _subAdminLocationIds.contains(doc.id)).toList();
              }

              return DropdownButtonFormField<String>(
                value: _selectedLocationId,
                decoration: const InputDecoration(
                  labelText: 'Filter by Location',
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
          const SizedBox(height: 16),
          // Date range filters
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() {
                        _startDate = picked;
                        if (_startDate.isAfter(_endDate)) {
                          _endDate = _startDate.add(const Duration(days: 30));
                        }
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Start Date',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(DateFormat('yyyy-MM-dd').format(_startDate)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _endDate,
                      firstDate: _startDate,
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() {
                        _endDate = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'End Date',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: Text(DateFormat('yyyy-MM-dd').format(_endDate)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsList() {
    // Use date string instead of selectedDate to avoid composite index issues
    final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate);
    final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate);
    
    // Get all dates in range
    final datesInRange = <String>[];
    var current = _startDate;
    while (!current.isAfter(_endDate)) {
      datesInRange.add(DateFormat('yyyy-MM-dd').format(current));
      current = current.add(const Duration(days: 1));
    }
    
    // Query using date strings (simpler, avoids composite index requirement)
    Query query = FirebaseFirestore.instance
        .collection('courtBookings')
        .where('date', whereIn: datesInRange.length > 10 ? datesInRange.take(10).toList() : datesInRange);

    // Filter by location if selected - use client-side filtering to avoid index issues
    // This is less efficient but avoids the need for composite indexes
    if (_selectedLocationId != null) {
      // Try server-side first, but fall back to client-side if it fails
      query = FirebaseFirestore.instance
          .collection('courtBookings')
          .where('locationId', isEqualTo: _selectedLocationId)
          .where('date', whereIn: datesInRange.length > 10 ? datesInRange.take(10).toList() : datesInRange);
    } else if (_isSubAdmin && !_isAdmin) {
      if (_subAdminLocationIds.isEmpty) {
        return const Center(
          child: Text('No locations assigned. Contact admin.'),
        );
      } else if (_subAdminLocationIds.length == 1) {
        query = FirebaseFirestore.instance
            .collection('courtBookings')
            .where('locationId', isEqualTo: _subAdminLocationIds.first)
            .where('date', whereIn: datesInRange.length > 10 ? datesInRange.take(10).toList() : datesInRange);
      }
      // For multiple locations, filter client-side
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No bookings found',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Try adjusting the date range or location filter',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final bookings = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          
          // Client-side filtering for date range if needed
          final bookingDate = data['date'] as String? ?? '';
          if (bookingDate.isNotEmpty && datesInRange.length > 10) {
            if (!datesInRange.contains(bookingDate)) {
              return false;
            }
          }
          
          // Client-side filtering for sub-admins with multiple locations
          if (_isSubAdmin && !_isAdmin && _subAdminLocationIds.length > 1) {
            final locationId = data['locationId'] as String?;
            if (locationId == null || !_subAdminLocationIds.contains(locationId)) {
              return false;
            }
          }
          
          // Client-side filtering for location if selected (fallback)
          if (_selectedLocationId != null) {
            final locationId = data['locationId'] as String?;
            if (locationId != _selectedLocationId) {
              return false;
            }
          }
          
          return true;
        }).toList()..sort((a, b) {
          // Sort by date and time
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aDate = aData['date'] as String? ?? '';
          final bDate = bData['date'] as String? ?? '';
          if (aDate != bDate) return aDate.compareTo(bDate);
          
          final aTimeRange = aData['timeRange'] as String? ?? '';
          final bTimeRange = bData['timeRange'] as String? ?? '';
          return aTimeRange.compareTo(bTimeRange);
        });

        if (bookings.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No bookings found',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Try adjusting the date range or location filter',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final booking = bookings[index];
            final data = booking.data() as Map<String, dynamic>;
            return _buildBookingCard(booking.id, data);
          },
        );
      },
    );
  }

  Widget _buildBookingCard(String bookingId, Map<String, dynamic> data) {
    final userId = data['userId'] as String? ?? '';
    final locationName = data['locationName'] as String? ?? 'Unknown Location';
    final date = data['date'] as String? ?? '';
    final selectedDate = data['selectedDate'] as Timestamp?;
    final courts = data['courts'] as Map<String, dynamic>? ?? {};
    final status = data['status'] as String? ?? 'unknown';
    final timeRange = data['timeRange'] as String? ?? '';
    final totalCost = data['totalCost'] as num? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with date and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        locationName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: status == 'confirmed' ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // User information
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const SizedBox.shrink();
                }

                final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                final firstName = userData?['firstName'] as String? ?? '';
                final lastName = userData?['lastName'] as String? ?? '';
                final fullName = userData?['fullName'] as String? ?? 
                    (firstName.isNotEmpty || lastName.isNotEmpty 
                        ? '$firstName $lastName'.trim() 
                        : 'Unknown User');
                final phone = userData?['phone'] as String? ?? 'No phone';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fullName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            phone,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Booking details
            if (timeRange.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    timeRange,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // Courts and slots
            ...courts.entries.map((entry) {
              final courtId = entry.key;
              final slots = (entry.value as List<dynamic>?)?.cast<String>() ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sports_tennis, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Court $courtId',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: slots.map((slot) {
                              return Chip(
                                label: Text(
                                  slot,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (totalCost > 0) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Total: ${totalCost.toStringAsFixed(0)} EGP',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
