import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _limitController = TextEditingController();
  bool _isLoading = false;
  bool _isAuthorized = false;
  bool _checkingAuth = true;

  // Admin phone number and email
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com'; // Add admin email if needed

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _checkAdminAccess();
    _loadCurrentLimit();
  }

  Future<void> _checkAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.phoneNumber == adminPhone || user?.email == adminEmail) {
      setState(() {
        _isAuthorized = true;
        _checkingAuth = false;
      });
    } else {
      setState(() {
        _isAuthorized = false;
        _checkingAuth = false;
      });
    }
  }

  Future<void> _loadCurrentLimit() async {
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('config')
          .doc('bookingSettings')
          .get();

      if (configDoc.exists) {
        final data = configDoc.data();
        final limit = data?['maxUsersPerSlot'] as int? ?? 4;
        _limitController.text = limit.toString();
      } else {
        _limitController.text = '4';
      }
    } catch (e) {
      _limitController.text = '4';
    }
  }

  // Generate time slots from 8AM to 11PM (8-9, 9-10, etc.)
  List<String> _generateTimeSlots() {
    List<String> slots = [];
    for (int hour = 8; hour <= 23; hour++) {
      String startTime = hour == 12 
          ? '12:00 PM'
          : hour < 12 
              ? '${hour}:00 AM'
              : '${hour - 12}:00 PM';
      String endTime = (hour + 1) == 12
          ? '12:00 PM'
          : (hour + 1) < 12
              ? '${hour + 1}:00 AM'
              : (hour + 1) == 24
                  ? '12:00 AM'
                  : '${hour + 1 - 12}:00 PM';
      slots.add('$startTime - $endTime');
    }
    return slots;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAuthorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Access')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Text(
                  'Access Denied',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'You are not authorized to access the admin panel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
            Tab(icon: Icon(Icons.add_circle), text: 'Slots'),
            Tab(icon: Icon(Icons.book), text: 'Bookings'),
            Tab(icon: Icon(Icons.check_circle), text: 'Approvals'),
            Tab(icon: Icon(Icons.radar), text: 'Skills'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSettingsTab(),
          _buildSlotsTab(),
          _buildAllBookingsTab(),
          _buildApprovalsTab(),
          _buildSkillsTab(),
        ],
      ),
    );
  }

  // SETTINGS TAB
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Slot Capacity Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Set the maximum number of users allowed per time slot.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _limitController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Maximum Users Per Slot',
              hintText: 'Enter a number (e.g., 4)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.people),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveLimit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Save Slot Capacity'),
            ),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Manage Venues',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('venues').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              final venues = snapshot.data!.docs;
              return Column(
                children: venues.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] as String? ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.location_on),
                      title: Text(name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditVenueDialog(doc.id, name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteVenue(doc.id, name),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _showAddVenueDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add New Venue'),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Manage Coaches',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('coaches').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const CircularProgressIndicator();
              }
              final coaches = snapshot.data!.docs;
              return Column(
                children: coaches.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] as String? ?? '';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditCoachDialog(doc.id, name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteCoach(doc.id, name),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _showAddCoachDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add New Coach'),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Block Time Slots',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Block specific time slots on specific days (e.g., Sunday 5 PM = 0 slots available)',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showBlockSlotDialog,
            icon: const Icon(Icons.block),
            label: const Text('Block Time Slot'),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('blockedSlots')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }
              final blockedSlots = snapshot.data!.docs;
              if (blockedSlots.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Blocked Slots:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...blockedSlots.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final venue = data['venue'] as String? ?? '';
                    final time = data['time'] as String? ?? '';
                    final day = data['day'] as String? ?? '';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: Colors.red[50],
                      child: ListTile(
                        leading: const Icon(Icons.block, color: Colors.red),
                        title: Text('$venue - $time'),
                        subtitle: Text('Day: $day'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _unblockSlot(doc.id),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveLimit() async {
    final limit = int.tryParse(_limitController.text);
    if (limit == null || limit < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid number (minimum 1)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('bookingSettings')
          .set({
        'maxUsersPerSlot': limit,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking limit updated to $limit successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving limit: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Helper to sync venues and coaches from existing slots
  Future<void> _syncVenuesAndCoachesFromSlots() async {
    try {
      final slots = await FirebaseFirestore.instance.collection('slots').get();
      final venues = await FirebaseFirestore.instance.collection('venues').get();
      final coaches = await FirebaseFirestore.instance.collection('coaches').get();

      Set<String> existingVenues = venues.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .toSet();
      Set<String> existingCoaches = coaches.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .toSet();

      // Extract unique venues and coaches from slots
      Set<String> slotVenues = {};
      Set<String> slotCoaches = {};

      for (var slot in slots.docs) {
        final data = slot.data() as Map<String, dynamic>;
        final venue = data['venue'] as String? ?? '';
        final coach = data['coach'] as String? ?? '';
        
        if (venue.isNotEmpty && !existingVenues.contains(venue)) {
          slotVenues.add(venue);
        }
        if (coach.isNotEmpty && !existingCoaches.contains(coach)) {
          slotCoaches.add(coach);
        }
      }

      // Add missing venues
      for (var venue in slotVenues) {
        await FirebaseFirestore.instance.collection('venues').add({
          'name': venue,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Add missing coaches
      for (var coach in slotCoaches) {
        await FirebaseFirestore.instance.collection('coaches').add({
          'name': coach,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // Silently fail - not critical
    }
  }

  // SLOTS TAB - Add venue, time, and coach together
  Widget _buildSlotsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _showAddSlotDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add New Slot'),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('slots')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final slots = snapshot.data!.docs;

              if (slots.isEmpty) {
                return const Center(child: Text('No slots added yet'));
              }

              // Sort slots client-side by venue, then time
              final sortedSlots = slots.toList()
                ..sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aVenue = aData['venue'] as String? ?? '';
                  final bVenue = bData['venue'] as String? ?? '';
                  if (aVenue != bVenue) {
                    return aVenue.compareTo(bVenue);
                  }
                  final aTime = aData['time'] as String? ?? '';
                  final bTime = bData['time'] as String? ?? '';
                  return aTime.compareTo(bTime);
                });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: sortedSlots.length,
                itemBuilder: (context, index) {
                  final doc = sortedSlots[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final venue = data['venue'] as String? ?? '';
                  final time = data['time'] as String? ?? '';
                  final coach = data['coach'] as String? ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.event_available),
                      title: Text(venue),
                      subtitle: Text('$time - $coach'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditSlotDialog(doc.id, venue, time, coach),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteSlot(doc.id, venue, time, coach),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddSlotDialog() async {
    try {
      // Sync venues and coaches from existing slots
      await _syncVenuesAndCoachesFromSlots();
      
      if (!context.mounted) return;
      
      // Fetch venues and coaches once (not real-time)
      final venuesSnapshot = await FirebaseFirestore.instance
          .collection('venues')
          .get();
      final coachesSnapshot = await FirebaseFirestore.instance
          .collection('coaches')
          .get();
      
      if (!context.mounted) return;
      
      List<String> venues = venuesSnapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      
      List<String> coaches = coachesSnapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      
      String? selectedVenue;
      String? selectedCoach;
      String? selectedTimeSlot;
      final timeController = TextEditingController();
      final newVenueController = TextEditingController();
      final newCoachController = TextEditingController();
      bool showNewVenueField = false;
      bool showNewCoachField = false;

      if (!context.mounted) return;
      
      await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add New Slot'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Venue Dropdown
                  Builder(
                    builder: (context) {

                      // Build dropdown items
                      List<DropdownMenuItem<String>> venueItems = [
                        ...venues.map((venue) => DropdownMenuItem(
                              value: venue,
                              child: Text(venue),
                            )),
                        const DropdownMenuItem(
                          value: '__ADD_NEW__',
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 18),
                              SizedBox(width: 8),
                              Text('Add New Venue'),
                            ],
                          ),
                        ),
                      ];

                      // Only set value if it exists in items
                      String? dropdownValue = selectedVenue;
                      if (selectedVenue != null && 
                          !venues.contains(selectedVenue) && 
                          selectedVenue != '__ADD_NEW__') {
                        dropdownValue = null;
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Venue:', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: dropdownValue,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Select or add venue',
                            ),
                            items: venueItems,
                            onChanged: (value) {
                              if (value == '__ADD_NEW__') {
                                setDialogState(() {
                                  showNewVenueField = true;
                                  selectedVenue = null;
                                });
                              } else {
                                setDialogState(() {
                                  selectedVenue = value;
                                  showNewVenueField = false;
                                  newVenueController.clear();
                                });
                              }
                            },
                          ),
                          if (showNewVenueField) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: newVenueController,
                              decoration: const InputDecoration(
                                labelText: 'New Venue Name',
                                hintText: 'e.g., Club13 Sheikh Zayed',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                // Don't set selectedVenue here - only when adding
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Time Slot Dropdown (8AM to 11PM)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Time Slot:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedTimeSlot,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Select time slot',
                        ),
                        items: _generateTimeSlots().map((slot) => DropdownMenuItem(
                          value: slot,
                          child: Text(slot),
                        )).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedTimeSlot = value;
                            if (value != null) {
                              timeController.text = value;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Coach Dropdown
                  Builder(
                    builder: (context) {

                      // Build dropdown items
                      List<DropdownMenuItem<String>> coachItems = [
                        ...coaches.map((coach) => DropdownMenuItem(
                              value: coach,
                              child: Text(coach),
                            )),
                        const DropdownMenuItem(
                          value: '__ADD_NEW__',
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 18),
                              SizedBox(width: 8),
                              Text('Add New Coach'),
                            ],
                          ),
                        ),
                      ];

                      // Only set value if it exists in items
                      String? dropdownValue = selectedCoach;
                      if (selectedCoach != null && 
                          !coaches.contains(selectedCoach) && 
                          selectedCoach != '__ADD_NEW__') {
                        dropdownValue = null;
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Coach:', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: dropdownValue,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Select or add coach',
                            ),
                            items: coachItems,
                            onChanged: (value) {
                              if (value == '__ADD_NEW__') {
                                setDialogState(() {
                                  showNewCoachField = true;
                                  selectedCoach = null;
                                });
                              } else {
                                setDialogState(() {
                                  selectedCoach = value;
                                  showNewCoachField = false;
                                  newCoachController.clear();
                                });
                              }
                            },
                          ),
                          if (showNewCoachField) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: newCoachController,
                              decoration: const InputDecoration(
                                labelText: 'New Coach Name',
                                hintText: 'e.g., Coach Ahmed',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                // Don't set selectedCoach here - only when adding
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  String? venue = selectedVenue;
                  String? coach = selectedCoach;
                  
                  // If new venue was entered, use it
                  if (showNewVenueField && newVenueController.text.trim().isNotEmpty) {
                    venue = newVenueController.text.trim();
                    await _addVenueIfNotExists(venue);
                  }
                  
                  // If new coach was entered, use it
                  if (showNewCoachField && newCoachController.text.trim().isNotEmpty) {
                    coach = newCoachController.text.trim();
                    await _addCoachIfNotExists(coach);
                  }
                  
                  final time = timeController.text.trim();
                  
                  if (venue != null && venue.isNotEmpty && 
                      time.isNotEmpty && 
                      coach != null && coach.isNotEmpty) {
                    await _addSlot(venue, time, coach);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill all fields'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Add'),
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
            content: Text('Error opening dialog: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addVenueIfNotExists(String venueName) async {
    try {
      // Check if venue already exists
      final existing = await FirebaseFirestore.instance
          .collection('venues')
          .where('name', isEqualTo: venueName)
          .get();

      if (existing.docs.isEmpty) {
        // Add new venue
        await FirebaseFirestore.instance.collection('venues').add({
          'name': venueName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // Silently fail - venue might already exist
    }
  }

  Future<void> _addCoachIfNotExists(String coachName) async {
    try {
      // Check if coach already exists
      final existing = await FirebaseFirestore.instance
          .collection('coaches')
          .where('name', isEqualTo: coachName)
          .get();

      if (existing.docs.isEmpty) {
        // Add new coach
        await FirebaseFirestore.instance.collection('coaches').add({
          'name': coachName,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // Silently fail - coach might already exist
    }
  }

  Future<void> _showEditSlotDialog(String slotId, String currentVenue, String currentTime, String currentCoach) async {
    try {
      // Sync venues and coaches from existing slots
      await _syncVenuesAndCoachesFromSlots();
      
      if (!context.mounted) return;
      
      // Fetch venues and coaches
      final venuesSnapshot = await FirebaseFirestore.instance
          .collection('venues')
          .get();
      final coachesSnapshot = await FirebaseFirestore.instance
          .collection('coaches')
          .get();
      
      if (!context.mounted) return;
      
      List<String> venues = venuesSnapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      
      List<String> coaches = coachesSnapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      
      String? selectedVenue = currentVenue;
      String? selectedCoach = currentCoach;
      String? selectedTimeSlot = currentTime;
      final newVenueController = TextEditingController();
      final newCoachController = TextEditingController();
      bool showNewVenueField = false;
      bool showNewCoachField = false;
      
      if (!context.mounted) return;
      
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Slot'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Venue Dropdown
                    Builder(
                      builder: (context) {
                        List<DropdownMenuItem<String>> venueItems = [
                          ...venues.map((venue) => DropdownMenuItem(
                                value: venue,
                                child: Text(venue),
                              )),
                          const DropdownMenuItem(
                            value: '__ADD_NEW__',
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18),
                                SizedBox(width: 8),
                                Text('Add New Venue'),
                              ],
                            ),
                          ),
                        ];
                        
                        String? dropdownValue = selectedVenue;
                        if (selectedVenue != null && 
                            !venues.contains(selectedVenue) && 
                            selectedVenue != '__ADD_NEW__') {
                          dropdownValue = null;
                        }
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Venue:', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: dropdownValue,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Select or add venue',
                              ),
                              items: venueItems,
                              onChanged: (value) {
                                if (value == '__ADD_NEW__') {
                                  setDialogState(() {
                                    showNewVenueField = true;
                                    selectedVenue = null;
                                  });
                                } else {
                                  setDialogState(() {
                                    selectedVenue = value;
                                    showNewVenueField = false;
                                    newVenueController.clear();
                                  });
                                }
                              },
                            ),
                            if (showNewVenueField) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: newVenueController,
                                decoration: const InputDecoration(
                                  labelText: 'New Venue Name',
                                  hintText: 'e.g., Club13 Sheikh Zayed',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Time Slot Dropdown
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Time Slot:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: selectedTimeSlot,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Select time slot',
                          ),
                          items: _generateTimeSlots().map((slot) => DropdownMenuItem(
                            value: slot,
                            child: Text(slot),
                          )).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedTimeSlot = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Coach Dropdown
                    Builder(
                      builder: (context) {
                        List<DropdownMenuItem<String>> coachItems = [
                          ...coaches.map((coach) => DropdownMenuItem(
                                value: coach,
                                child: Text(coach),
                              )),
                          const DropdownMenuItem(
                            value: '__ADD_NEW__',
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 18),
                                SizedBox(width: 8),
                                Text('Add New Coach'),
                              ],
                            ),
                          ),
                        ];
                        
                        String? dropdownValue = selectedCoach;
                        if (selectedCoach != null && 
                            !coaches.contains(selectedCoach) && 
                            selectedCoach != '__ADD_NEW__') {
                          dropdownValue = null;
                        }
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Coach:', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: dropdownValue,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'Select or add coach',
                              ),
                              items: coachItems,
                              onChanged: (value) {
                                if (value == '__ADD_NEW__') {
                                  setDialogState(() {
                                    showNewCoachField = true;
                                    selectedCoach = null;
                                  });
                                } else {
                                  setDialogState(() {
                                    selectedCoach = value;
                                    showNewCoachField = false;
                                    newCoachController.clear();
                                  });
                                }
                              },
                            ),
                            if (showNewCoachField) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: newCoachController,
                                decoration: const InputDecoration(
                                  labelText: 'New Coach Name',
                                  hintText: 'e.g., Coach Ahmed',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    String? venue = selectedVenue;
                    String? coach = selectedCoach;
                    
                    if (showNewVenueField && newVenueController.text.trim().isNotEmpty) {
                      venue = newVenueController.text.trim();
                      await _addVenueIfNotExists(venue);
                    }
                    
                    if (showNewCoachField && newCoachController.text.trim().isNotEmpty) {
                      coach = newCoachController.text.trim();
                      await _addCoachIfNotExists(coach);
                    }
                    
                    final time = selectedTimeSlot;
                    
                    if (venue != null && venue.isNotEmpty && 
                        time != null && time.isNotEmpty && 
                        coach != null && coach.isNotEmpty) {
                      await _updateSlot(slotId, venue, time, coach);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please fill all fields'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Update'),
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
            content: Text('Error opening dialog: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateSlot(String slotId, String venue, String time, String coach) async {
    try {
      await FirebaseFirestore.instance
          .collection('slots')
          .doc(slotId)
          .update({
        'venue': venue,
        'time': time,
        'coach': coach,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Slot updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating slot: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addSlot(String venue, String time, String coach) async {
    try {
      // Check for duplicates
      final existing = await FirebaseFirestore.instance
          .collection('slots')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .where('coach', isEqualTo: coach)
          .get();

      if (existing.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This slot already exists!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await FirebaseFirestore.instance.collection('slots').add({
        'venue': venue,
        'time': time,
        'coach': coach,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Slot added successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
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

  Future<void> _deleteSlot(String id, String venue, String time, String coach) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Slot'),
        content: Text('Are you sure you want to delete:\n$venue\n$time - $coach?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('slots').doc(id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Slot deleted'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // VENUE MANAGEMENT
  Future<void> _showAddVenueDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Venue'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Venue Name',
            hintText: 'e.g., Club13 Sheikh Zayed',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _addVenueIfNotExists(controller.text.trim());
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditVenueDialog(String venueId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Venue'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Venue Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                try {
                  await FirebaseFirestore.instance
                      .collection('venues')
                      .doc(venueId)
                      .update({'name': controller.text.trim()});
                  
                  // Update all slots with this venue name
                  final slots = await FirebaseFirestore.instance
                      .collection('slots')
                      .where('venue', isEqualTo: currentName)
                      .get();
                  
                  for (var slot in slots.docs) {
                    await slot.reference.update({'venue': controller.text.trim()});
                  }
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Venue updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
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
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteVenue(String venueId, String venueName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Venue'),
        content: Text('Are you sure you want to delete "$venueName"?\n\nThis will also delete all slots for this venue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete all slots for this venue
        final slots = await FirebaseFirestore.instance
            .collection('slots')
            .where('venue', isEqualTo: venueName)
            .get();
        
        for (var slot in slots.docs) {
          await slot.reference.delete();
        }
        
        // Delete the venue
        await FirebaseFirestore.instance.collection('venues').doc(venueId).delete();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Venue deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
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

  // COACH MANAGEMENT
  Future<void> _showAddCoachDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Coach'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Coach Name',
            hintText: 'e.g., Coach Ahmed',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _addCoachIfNotExists(controller.text.trim());
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCoachDialog(String coachId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Coach'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Coach Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                try {
                  await FirebaseFirestore.instance
                      .collection('coaches')
                      .doc(coachId)
                      .update({'name': controller.text.trim()});
                  
                  // Update all slots with this coach name
                  final slots = await FirebaseFirestore.instance
                      .collection('slots')
                      .where('coach', isEqualTo: currentName)
                      .get();
                  
                  for (var slot in slots.docs) {
                    await slot.reference.update({'coach': controller.text.trim()});
                  }
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Coach updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
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
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCoach(String coachId, String coachName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Coach'),
        content: Text('Are you sure you want to delete "$coachName"?\n\nThis will also delete all slots for this coach.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete all slots for this coach
        final slots = await FirebaseFirestore.instance
            .collection('slots')
            .where('coach', isEqualTo: coachName)
            .get();
        
        for (var slot in slots.docs) {
          await slot.reference.delete();
        }
        
        // Delete the coach
        await FirebaseFirestore.instance.collection('coaches').doc(coachId).delete();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Coach deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
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

  // SLOT BLOCKING
  Future<void> _showBlockSlotDialog() async {
    try {
      final venuesSnapshot = await FirebaseFirestore.instance.collection('venues').get();
      final venues = venuesSnapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .where((name) => name.isNotEmpty)
          .toList()
        ..sort();

      String? selectedVenue;
      String? selectedTime;
      String? selectedDay;
      final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

      if (!context.mounted) return;

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Block Time Slot'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedVenue,
                      decoration: const InputDecoration(
                        labelText: 'Venue',
                        border: OutlineInputBorder(),
                      ),
                      items: venues.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedVenue = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedTime,
                      decoration: const InputDecoration(
                        labelText: 'Time Slot',
                        border: OutlineInputBorder(),
                      ),
                      items: _generateTimeSlots().map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedTime = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedDay,
                      decoration: const InputDecoration(
                        labelText: 'Day of Week',
                        border: OutlineInputBorder(),
                      ),
                      items: days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (value) {
                        setDialogState(() => selectedDay = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedVenue != null && selectedTime != null && selectedDay != null) {
                      try {
                        await FirebaseFirestore.instance.collection('blockedSlots').add({
                          'venue': selectedVenue,
                          'time': selectedTime,
                          'day': selectedDay,
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Time slot blocked successfully'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          Navigator.pop(context);
                        }
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
                  child: const Text('Block'),
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
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unblockSlot(String blockedSlotId) async {
    try {
      await FirebaseFirestore.instance.collection('blockedSlots').doc(blockedSlotId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Time slot unblocked'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
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

  // APPROVALS TAB
  Widget _buildApprovalsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'No pending approvals',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final bookings = snapshot.data!.docs;
        
        // Sort by timestamp client-side
        bookings.sort((a, b) {
          final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp); // Descending
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final doc = bookings[index];
            final data = doc.data() as Map<String, dynamic>;

            final venue = data['venue'] as String? ?? 'Unknown';
            final time = data['time'] as String? ?? 'Unknown';
            final coach = data['coach'] as String? ?? 'Unknown';
            final phone = data['phone'] as String? ?? 'Unknown';
            final isRecurring = data['isRecurring'] as bool? ?? false;
            final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
            final dateStr = data['date'] as String? ?? '';
            final timestamp = data['timestamp'] as Timestamp?;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venue,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Time: $time'),
                              Text('Coach: $coach'),
                              Text('Phone: $phone'),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Pending',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isRecurring && recurringDays.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Days: ${recurringDays.join(', ')}',
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ] else if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Date: $dateStr'),
                    ],
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Requested: ${_formatTimestamp(timestamp)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _rejectBooking(doc.id),
                          icon: const Icon(Icons.cancel, size: 18),
                          label: const Text('Reject'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _approveBooking(doc.id),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Approve'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _approveBooking(String bookingId) async {
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving booking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Booking'),
        content: const Text('Are you sure you want to reject this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .update({
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking rejected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error rejecting booking: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ALL BOOKINGS TAB
  Widget _buildAllBookingsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No bookings found'));
        }

        final bookings = snapshot.data!.docs;
        
        // Sort by timestamp client-side
        bookings.sort((a, b) {
          final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp); // Descending
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final doc = bookings[index];
            final data = doc.data() as Map<String, dynamic>;

            final venue = data['venue'] as String? ?? 'Unknown';
            final time = data['time'] as String? ?? 'Unknown';
            final coach = data['coach'] as String? ?? 'Unknown';
            final phone = data['phone'] as String? ?? 'Unknown';
            final isRecurring = data['isRecurring'] as bool? ?? false;
            final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
            final dateStr = data['date'] as String? ?? '';
            final timestamp = data['timestamp'] as Timestamp?;
            final status = data['status'] as String? ?? 'pending';

            Color statusColorLight;
            Color statusColorDark;
            String statusText;
            switch (status) {
              case 'approved':
                statusColorLight = Colors.green[100]!;
                statusColorDark = Colors.green[900]!;
                statusText = 'Approved';
                break;
              case 'rejected':
                statusColorLight = Colors.red[100]!;
                statusColorDark = Colors.red[900]!;
                statusText = 'Rejected';
                break;
              default:
                statusColorLight = Colors.orange[100]!;
                statusColorDark = Colors.orange[900]!;
                statusText = 'Pending';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venue,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text('Time: $time'),
                              Text('Coach: $coach'),
                              Text('Phone: $phone'),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColorLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColorDark,
                                ),
                              ),
                            ),
                            if (isRecurring) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Recurring',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    if (isRecurring && recurringDays.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Days: ${recurringDays.join(', ')}',
                        style: const TextStyle(color: Colors.blue),
                      ),
                    ] else if (dateStr.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Date: $dateStr'),
                    ],
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Booked: ${_formatTimestamp(timestamp)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () => _deleteBooking(doc.id),
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Delete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Booking'),
        content: const Text('Are you sure you want to delete this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting booking: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // SKILLS TAB
  Widget _buildSkillsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please make sure you are logged in as admin',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No users found'),
          );
        }

        // Sort users by fullName client-side
        final users = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final aName = (a.data() as Map<String, dynamic>)['fullName'] as String? ?? '';
            final bName = (b.data() as Map<String, dynamic>)['fullName'] as String? ?? '';
            return aName.compareTo(bName);
          });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final userDoc = users[index];
            final userData = userDoc.data() as Map<String, dynamic>;
            final fullName = userData['fullName'] as String? ?? 'Unknown User';
            final email = userData['email'] as String? ?? '';
            final phone = userData['phone'] as String? ?? '';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  child: Text(
                    fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  fullName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (email.isNotEmpty) Text('Email: $email'),
                    if (phone.isNotEmpty) Text('Phone: $phone'),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Skills',
                  onPressed: () => _showEditSkillsDialog(userDoc.id, fullName, userData),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditSkillsDialog(String userId, String userName, Map<String, dynamic> userData) {
    final skills = userData['skills'] as Map<String, dynamic>? ?? {};
    
    // Attack Skills
    final bajadaController = TextEditingController(text: (skills['bajada'] as num?)?.toString() ?? '0');
    final viboraController = TextEditingController(text: (skills['vibora'] as num?)?.toString() ?? '0');
    final smashController = TextEditingController(text: (skills['smash'] as num?)?.toString() ?? '0');
    final ruloController = TextEditingController(text: (skills['rulo'] as num?)?.toString() ?? '0');
    final ganchoController = TextEditingController(text: (skills['gancho'] as num?)?.toString() ?? '0');
    
    // Overall Performance
    final attackController = TextEditingController(text: (skills['attack'] as num?)?.toString() ?? '0');
    final defenseController = TextEditingController(text: (skills['defense'] as num?)?.toString() ?? '0');
    final netPlayController = TextEditingController(text: (skills['netPlay'] as num?)?.toString() ?? '0');
    final fundamentalsController = TextEditingController(text: (skills['fundamentals'] as num?)?.toString() ?? '0');
    final intelligenceController = TextEditingController(text: (skills['intelligence'] as num?)?.toString() ?? '0');
    final physicalMentalController = TextEditingController(text: (skills['physicalMental'] as num?)?.toString() ?? '0');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Edit Skills: $userName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attack Skills (0-10)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildSkillField('Bajada', bajadaController),
                  _buildSkillField('Vibora', viboraController),
                  _buildSkillField('Smash', smashController),
                  _buildSkillField('Rulo', ruloController),
                  _buildSkillField('Gancho', ganchoController),
                  const SizedBox(height: 16),
                  const Text(
                    'Overall Performance (0-10)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildSkillField('Attack', attackController),
                  _buildSkillField('Defense', defenseController),
                  _buildSkillField('Net Play', netPlayController),
                  _buildSkillField('Fundamentals', fundamentalsController),
                  _buildSkillField('Intelligence', intelligenceController),
                  _buildSkillField('Physical/Mental', physicalMentalController),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  bajadaController.dispose();
                  viboraController.dispose();
                  smashController.dispose();
                  ruloController.dispose();
                  ganchoController.dispose();
                  attackController.dispose();
                  defenseController.dispose();
                  netPlayController.dispose();
                  fundamentalsController.dispose();
                  intelligenceController.dispose();
                  physicalMentalController.dispose();
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final skillsData = {
                      'bajada': double.tryParse(bajadaController.text) ?? 0.0,
                      'vibora': double.tryParse(viboraController.text) ?? 0.0,
                      'smash': double.tryParse(smashController.text) ?? 0.0,
                      'rulo': double.tryParse(ruloController.text) ?? 0.0,
                      'gancho': double.tryParse(ganchoController.text) ?? 0.0,
                      'attack': double.tryParse(attackController.text) ?? 0.0,
                      'defense': double.tryParse(defenseController.text) ?? 0.0,
                      'netPlay': double.tryParse(netPlayController.text) ?? 0.0,
                      'fundamentals': double.tryParse(fundamentalsController.text) ?? 0.0,
                      'intelligence': double.tryParse(intelligenceController.text) ?? 0.0,
                      'physicalMental': double.tryParse(physicalMentalController.text) ?? 0.0,
                    };

                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .update({
                      'skills': skillsData,
                      'skillsUpdatedAt': FieldValue.serverTimestamp(),
                    });

                    if (mounted) {
                      bajadaController.dispose();
                      viboraController.dispose();
                      smashController.dispose();
                      ruloController.dispose();
                      ganchoController.dispose();
                      attackController.dispose();
                      defenseController.dispose();
                      netPlayController.dispose();
                      fundamentalsController.dispose();
                      intelligenceController.dispose();
                      physicalMentalController.dispose();
                      
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Skills updated successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating skills: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSkillField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '0-10',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
