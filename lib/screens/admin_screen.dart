import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import 'tournament_dashboard_screen.dart';
import 'tournament_groups_screen.dart';

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
    _tabController = TabController(length: 9, vsync: this);
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
            Tab(icon: Icon(Icons.emoji_events), text: 'Tournaments'),
            Tab(icon: Icon(Icons.person_add), text: 'Tournament Requests'),
            Tab(icon: Icon(Icons.radar), text: 'Skills'),
            Tab(icon: Icon(Icons.location_city), text: 'Court Locations'),
            Tab(icon: Icon(Icons.history), text: 'Sub-Admin Logs'),
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
          _buildTournamentsTab(),
          _buildTournamentRequestsTab(),
          _buildSkillsTab(),
          _buildCourtLocationsTab(),
          _buildSubAdminLogsTab(),
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
            final bookingPhone = data['phone'] as String? ?? '';
            final userId = data['userId'] as String? ?? '';
            final isRecurring = data['isRecurring'] as bool? ?? false;
            final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
            final dateStr = data['date'] as String? ?? '';
            final timestamp = data['timestamp'] as Timestamp?;

            // Fetch user data from users collection
            return FutureBuilder<DocumentSnapshot>(
              future: userId.isNotEmpty
                  ? FirebaseFirestore.instance.collection('users').doc(userId).get()
                  : Future.value(null),
              builder: (context, userSnapshot) {
                String firstName = '';
                String lastName = '';
                String phone = bookingPhone;

                if (userSnapshot.hasData && userSnapshot.data != null && userSnapshot.data!.exists) {
                  final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  firstName = userData?['firstName'] as String? ?? '';
                  lastName = userData?['lastName'] as String? ?? '';
                  // Use phone from user document if available, otherwise use booking phone
                  phone = (userData?['phone'] as String?)?.isNotEmpty == true
                      ? (userData!['phone'] as String)
                      : (phone.isNotEmpty ? phone : 'Not provided');
                } else if (phone.isEmpty) {
                  phone = 'Not provided';
                }

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
                                  if (firstName.isNotEmpty || lastName.isNotEmpty) ...[
                                    Text(
                                      'Name: ${firstName.isNotEmpty && lastName.isNotEmpty ? "$firstName $lastName" : (firstName.isNotEmpty ? firstName : lastName)}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ],
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
      },
    );
  }

  Future<void> _approveBooking(String bookingId) async {
    try {
      // Get booking data before updating
      final bookingDoc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .get();
      
      if (!bookingDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final bookingData = bookingDoc.data() as Map<String, dynamic>;
      final userId = bookingData['userId'] as String? ?? '';
      final venue = bookingData['venue'] as String? ?? '';
      final time = bookingData['time'] as String? ?? '';
      final date = bookingData['date'] as String? ?? '';

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // Notify user about approval
      if (userId.isNotEmpty) {
        await NotificationService().notifyUserForBookingStatus(
          userId: userId,
          bookingId: bookingId,
          status: 'approved',
          venue: venue,
          time: time,
          date: date,
        );
      }

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
        // Get booking data before updating
        final bookingDoc = await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .get();
        
        if (!bookingDoc.exists) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Booking not found'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        final bookingData = bookingDoc.data() as Map<String, dynamic>;
        final userId = bookingData['userId'] as String? ?? '';
        final venue = bookingData['venue'] as String? ?? '';
        final time = bookingData['time'] as String? ?? '';
        final date = bookingData['date'] as String? ?? '';

        await FirebaseFirestore.instance
            .collection('bookings')
            .doc(bookingId)
            .update({
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });

        // Notify user about rejection
        if (userId.isNotEmpty) {
          await NotificationService().notifyUserForBookingStatus(
            userId: userId,
            bookingId: bookingId,
            status: 'rejected',
            venue: venue,
            time: time,
            date: date,
          );
        }

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

  // Helper method to build asset image with proper path handling
  Widget _buildAssetImage(String imagePath, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (imagePath.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFF1E3A8A).withOpacity(0.1),
        child: const Icon(
          Icons.emoji_events,
          color: Color(0xFF1E3A8A),
          size: 32,
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
          color: const Color(0xFF1E3A8A).withOpacity(0.1),
          child: const Icon(
            Icons.emoji_events,
            color: Color(0xFF1E3A8A),
            size: 32,
          ),
        );
      },
    );
  }

  // TOURNAMENTS TAB
  Widget _buildTournamentsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _showAddTournamentDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add New Tournament'),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tournaments')
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final tournaments = snapshot.data!.docs;

              if (tournaments.isEmpty) {
                return const Center(child: Text('No tournaments added yet'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tournaments.length,
                itemBuilder: (context, index) {
                  final doc = tournaments[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] as String? ?? 'Unknown';
                  final description = data['description'] as String? ?? '';
                  final imageUrl = data['imageUrl'] as String? ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: imageUrl.startsWith('http')
                                  ? Image.network(
                                      imageUrl,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Icon(Icons.emoji_events, color: Color(0xFF1E3A8A));
                                      },
                                    )
                                  : _buildAssetImage(imageUrl, width: 40, height: 40),
                            )
                          : const Icon(Icons.emoji_events, color: Color(0xFF1E3A8A)),
                      title: Text(name),
                      subtitle: description.isNotEmpty ? Text(description) : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.group, color: Colors.orange),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TournamentGroupsScreen(
                                    tournamentId: doc.id,
                                    tournamentName: name,
                                  ),
                                ),
                              );
                            },
                            tooltip: 'Manage Groups',
                          ),
                          IconButton(
                            icon: const Icon(Icons.leaderboard, color: Colors.green),
                            onPressed: () {
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
                            tooltip: 'Manage Matches & View Dashboard',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditTournamentDialog(doc.id, name, description),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteTournament(doc.id, name),
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

  Future<void> _showAddTournamentDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final imageUrlController = TextEditingController();
    final dateController = TextEditingController();
    final timeController = TextEditingController();
    final locationController = TextEditingController();
    final entryFeeController = TextEditingController();
    final prizeController = TextEditingController();
    final maxParticipantsController = TextEditingController(text: '12');
    String typeValue = 'Single Elimination';
    List<String> skillLevelValues = ['Beginner'];
    const List<String> allSkillLevels = ['Beginner', 'D', 'C', 'B', 'A'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add New Tournament'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Tournament Name',
                  hintText: 'e.g., Tournament Padel Factory (TPF)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Tournament description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: imageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Image URL (Optional)',
                  hintText: 'Asset path (e.g., assets/images/tournament.png) or network URL',
                  border: OutlineInputBorder(),
                  helperText: 'Use asset path for local images or full URL for network images',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: typeValue,
                items: const [
                  DropdownMenuItem(value: 'Single Elimination', child: Text('Single Elimination')),
                  DropdownMenuItem(value: 'League', child: Text('League')),
                ],
                onChanged: (v) => setDialogState(() => typeValue = v ?? 'Single Elimination'),
                decoration: const InputDecoration(
                  labelText: 'Tournament Type',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Multi-select skill levels with checkboxes
              const Text(
                'Skill Level Badge (Select multiple)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...allSkillLevels.map((level) {
                return CheckboxListTile(
                  title: Text(level),
                  value: skillLevelValues.contains(level),
                  onChanged: (checked) {
                    setDialogState(() {
                      // Create a new list instead of mutating the existing one
                      final newList = List<String>.from(skillLevelValues);
                      if (checked == true) {
                        if (!newList.contains(level)) {
                          newList.add(level);
                        }
                      } else {
                        newList.remove(level);
                      }
                      // Ensure at least one is selected
                      if (newList.isEmpty) {
                        newList.add('Beginner');
                      }
                      skillLevelValues.clear();
                      skillLevelValues.addAll(newList);
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                );
              }).toList(),
              const SizedBox(height: 16),
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date (Optional)',
                  hintText: 'e.g., Feb 1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: 'Time (Optional)',
                  hintText: 'e.g., 8:00 AM',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Location (Optional)',
                  hintText: 'e.g., Elite Sports Complex',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: entryFeeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Entry Fee',
                        hintText: 'e.g., 100',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: prizeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Prize',
                        hintText: 'e.g., 1200',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxParticipantsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max Participants',
                  hintText: 'e.g., 12',
                  border: OutlineInputBorder(),
                ),
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
              if (nameController.text.trim().isNotEmpty) {
                await _addTournament(
                  nameController.text.trim(),
                  descriptionController.text.trim(),
                  imageUrlController.text.trim(),
                  {
                    'type': typeValue,
                    'skillLevel': skillLevelValues, // Store as List
                    'date': dateController.text.trim(),
                    'time': timeController.text.trim(),
                    'location': locationController.text.trim(),
                    'entryFee': int.tryParse(entryFeeController.text.trim()) ?? 0,
                    'prize': int.tryParse(prizeController.text.trim()) ?? 0,
                    'maxParticipants': int.tryParse(maxParticipantsController.text.trim()) ?? 12,
                    'participants': 0,
                  },
                );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _showEditTournamentDialog(String tournamentId, String currentName, String currentDescription) async {
    // Get current image URL from Firestore
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(tournamentId)
        .get();
    final data = tournamentDoc.data() ?? {};
    final currentImageUrl = data['imageUrl'] as String? ?? '';
    final currentType = data['type'] as String? ?? 'Single Elimination';
    // Handle both old format (String) and new format (List<String>)
    final skillLevelData = data['skillLevel'];
    final List<String> currentSkill = skillLevelData is List
        ? (skillLevelData as List).map((e) => e.toString()).toList()
        : (skillLevelData != null ? [skillLevelData.toString()] : ['Beginner']);
    final currentDate = data['date'] as String? ?? '';
    final currentTime = data['time'] as String? ?? '';
    final currentLocation = data['location'] as String? ?? '';
    final currentEntryFee = (data['entryFee'] as num?)?.toInt() ?? 0;
    final currentPrize = (data['prize'] as num?)?.toInt() ?? 0;
    final currentMaxParticipants = (data['maxParticipants'] as num?)?.toInt() ?? 12;
    
    final nameController = TextEditingController(text: currentName);
    final descriptionController = TextEditingController(text: currentDescription);
    final imageUrlController = TextEditingController(text: currentImageUrl);
    final dateController = TextEditingController(text: currentDate);
    final timeController = TextEditingController(text: currentTime);
    final locationController = TextEditingController(text: currentLocation);
    final entryFeeController = TextEditingController(text: '$currentEntryFee');
    final prizeController = TextEditingController(text: '$currentPrize');
    final maxParticipantsController = TextEditingController(text: '$currentMaxParticipants');
    String typeValue = currentType;
    List<String> skillLevelValues = List<String>.from(currentSkill);
    const List<String> allSkillLevels = ['Beginner', 'D', 'C', 'B', 'A'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: const Text('Edit Tournament'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Tournament Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: imageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Image URL (Optional)',
                  hintText: 'Asset path or network URL',
                  border: OutlineInputBorder(),
                  helperText: 'Use asset path for local images or full URL for network images',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: typeValue,
                items: const [
                  DropdownMenuItem(value: 'Single Elimination', child: Text('Single Elimination')),
                  DropdownMenuItem(value: 'League', child: Text('League')),
                ],
                onChanged: (v) => setDialogState(() => typeValue = v ?? 'Single Elimination'),
                decoration: const InputDecoration(
                  labelText: 'Tournament Type',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Multi-select skill levels with checkboxes
              const Text(
                'Skill Level Badge (Select multiple)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...allSkillLevels.map((level) {
                return CheckboxListTile(
                  title: Text(level),
                  value: skillLevelValues.contains(level),
                  onChanged: (checked) {
                    setDialogState(() {
                      // Create a new list instead of mutating the existing one
                      final newList = List<String>.from(skillLevelValues);
                      if (checked == true) {
                        if (!newList.contains(level)) {
                          newList.add(level);
                        }
                      } else {
                        newList.remove(level);
                      }
                      // Ensure at least one is selected
                      if (newList.isEmpty) {
                        newList.add('Beginner');
                      }
                      skillLevelValues.clear();
                      skillLevelValues.addAll(newList);
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                );
              }).toList(),
              const SizedBox(height: 16),
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date (Optional)',
                  hintText: 'e.g., Feb 1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: 'Time (Optional)',
                  hintText: 'e.g., 8:00 AM',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: locationController,
                decoration: const InputDecoration(
                  labelText: 'Location (Optional)',
                  hintText: 'e.g., Elite Sports Complex',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: entryFeeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Entry Fee',
                        hintText: 'e.g., 100',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: prizeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Prize',
                        hintText: 'e.g., 1200',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxParticipantsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max Participants',
                  hintText: 'e.g., 12',
                  border: OutlineInputBorder(),
                ),
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
              if (nameController.text.trim().isNotEmpty) {
                await _updateTournament(
                  tournamentId, 
                  nameController.text.trim(), 
                  descriptionController.text.trim(),
                  imageUrlController.text.trim(),
                  {
                    'type': typeValue,
                    'skillLevel': skillLevelValues, // Store as List
                    'date': dateController.text.trim(),
                    'time': timeController.text.trim(),
                    'location': locationController.text.trim(),
                    'entryFee': int.tryParse(entryFeeController.text.trim()) ?? 0,
                    'prize': int.tryParse(prizeController.text.trim()) ?? 0,
                    'maxParticipants': int.tryParse(maxParticipantsController.text.trim()) ?? 12,
                  },
                );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _addTournament(String name, String description, String imageUrl, Map<String, dynamic> extraFields) async {
    try {
      final tournamentData = {
        'name': name,
        'description': description,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      if (imageUrl.isNotEmpty) {
        tournamentData['imageUrl'] = imageUrl;
      }

      // Extra fields for home cards
      tournamentData.addAll(extraFields.map((key, value) => MapEntry(key, value as Object)));
      
      await FirebaseFirestore.instance.collection('tournaments').add(tournamentData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tournament added successfully'),
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

  Future<void> _updateTournament(String tournamentId, String name, String description, String imageUrl, Map<String, dynamic> extraFields) async {
    try {
      final updateData = {
        'name': name,
        'description': description,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      if (imageUrl.isNotEmpty) {
        updateData['imageUrl'] = imageUrl;
      } else {
        // Remove imageUrl if empty
        updateData['imageUrl'] = FieldValue.delete();
      }

      // Extra fields for home cards
      updateData.addAll(extraFields.map((key, value) => MapEntry(key, value as Object)));
      
      await FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).update(updateData);

      // Update all registrations with the new tournament name
      final registrations = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: tournamentId)
          .get();

      for (var reg in registrations.docs) {
        await reg.reference.update({'tournamentName': name});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tournament updated successfully'),
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

  Future<void> _deleteTournament(String tournamentId, String tournamentName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tournament'),
        content: Text('Are you sure you want to delete "$tournamentName"?\n\nThis will also delete all registrations for this tournament.'),
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
        // Delete all registrations for this tournament
        final registrations = await FirebaseFirestore.instance
            .collection('tournamentRegistrations')
            .where('tournamentId', isEqualTo: tournamentId)
            .get();

        for (var reg in registrations.docs) {
          await reg.reference.delete();
        }

        // Delete the tournament
        await FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tournament deleted successfully'),
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

  // TOURNAMENT REQUESTS TAB
  Widget _buildTournamentRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournamentRegistrations')
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
                  'No pending tournament requests',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final requests = snapshot.data!.docs;

        // Sort by timestamp client-side
        requests.sort((a, b) {
          final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp); // Descending
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;

            final tournamentName = data['tournamentName'] as String? ?? 'Unknown Tournament';
            final level = data['level'] as String? ?? 'Unknown';
            final userId = data['userId'] as String? ?? '';
            final firstName = data['firstName'] as String? ?? '';
            final lastName = data['lastName'] as String? ?? '';
            final phone = data['phone'] as String? ?? 'Not provided';
            final timestamp = data['timestamp'] as Timestamp?;
            final partner = data['partner'] as Map<String, dynamic>?;

            return FutureBuilder<DocumentSnapshot>(
              future: userId.isNotEmpty
                  ? FirebaseFirestore.instance.collection('users').doc(userId).get()
                  : Future.value(null),
              builder: (context, userSnapshot) {
                String userName = '$firstName $lastName'.trim();
                String userPhone = phone;

                if (userSnapshot.hasData && userSnapshot.data != null && userSnapshot.data!.exists) {
                  final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                  final userFirstName = userData?['firstName'] as String? ?? '';
                  final userLastName = userData?['lastName'] as String? ?? '';
                  if (userFirstName.isNotEmpty || userLastName.isNotEmpty) {
                    userName = '$userFirstName $userLastName'.trim();
                  }
                  userPhone = userData?['phone'] as String? ?? phone;
                }

                if (userName.isEmpty) {
                  userName = 'Unknown User';
                }

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
                                    tournamentName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    userName,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text('Phone: $userPhone'),
                                  Text('Level: $level'),
                                  if (partner != null) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.blue[200]!),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.person, size: 16, color: Colors.blue),
                                              const SizedBox(width: 4),
                                              const Text(
                                                'Partner:',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            partner['partnerName'] as String? ?? 'Unknown',
                                            style: const TextStyle(fontWeight: FontWeight.w500),
                                          ),
                                          Text(
                                            'Phone: ${partner['partnerPhone'] as String? ?? 'Not provided'}',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                          if (partner['partnerType'] == 'registered')
                                            const Text(
                                              '(Registered User)',
                                              style: TextStyle(fontSize: 11, color: Colors.green),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
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
                        if (timestamp != null) ...[
                          const SizedBox(height: 8),
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
                              onPressed: () => _rejectTournamentRequest(doc.id),
                              icon: const Icon(Icons.cancel, size: 18),
                              label: const Text('Reject'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _approveTournamentRequest(doc.id),
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
      },
    );
  }

  Future<void> _approveTournamentRequest(String requestId) async {
    try {
      // Get request data before updating
      final requestDoc = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .doc(requestId)
          .get();
      
      if (!requestDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Request not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final requestData = requestDoc.data() as Map<String, dynamic>;
      final userId = requestData['userId'] as String? ?? '';
      final tournamentName = requestData['tournamentName'] as String? ?? '';

      await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .doc(requestId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // Notify user about approval
      if (userId.isNotEmpty) {
        await NotificationService().notifyUserForTournamentStatus(
          userId: userId,
          requestId: requestId,
          status: 'approved',
          tournamentName: tournamentName,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tournament request approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectTournamentRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Tournament Request'),
        content: const Text('Are you sure you want to reject this tournament request?'),
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
        // Get request data before updating
        final requestDoc = await FirebaseFirestore.instance
            .collection('tournamentRegistrations')
            .doc(requestId)
            .get();
        
        if (!requestDoc.exists) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Request not found'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        final requestData = requestDoc.data() as Map<String, dynamic>;
        final userId = requestData['userId'] as String? ?? '';
        final tournamentName = requestData['tournamentName'] as String? ?? '';

        await FirebaseFirestore.instance
            .collection('tournamentRegistrations')
            .doc(requestId)
            .update({
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });

        // Notify user about rejection
        if (userId.isNotEmpty) {
          await NotificationService().notifyUserForTournamentStatus(
            userId: userId,
            requestId: requestId,
            status: 'rejected',
            tournamentName: tournamentName,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tournament request rejected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error rejecting request: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
                  _buildSkillField('Net Play', netPlayController),
                  _buildSkillField('Defense', defenseController),
                  _buildSkillField('Intelligence', intelligenceController),
                  _buildSkillField('Fundamentals', fundamentalsController),
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

  // COURT LOCATIONS TAB
  Widget _buildCourtLocationsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () => _showAddCourtLocationDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add New Location'),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('courtLocations')
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final locations = snapshot.data!.docs;

              if (locations.isEmpty) {
                return const Center(child: Text('No locations added yet'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: locations.length,
                itemBuilder: (context, index) {
                  final doc = locations[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final name = data['name'] as String? ?? 'Unknown';
                  final address = data['address'] as String? ?? '';
                  final courts = (data['courts'] as List?)?.length ?? 0;

                  final subAdmins = (data['subAdmins'] as List?)?.cast<String>() ?? [];
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      leading: const Icon(Icons.location_city, color: Color(0xFF1E3A8A)),
                      title: Text(name),
                      subtitle: Text('$address • $courts courts • ${subAdmins.length} sub-admin(s)'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.people, color: Colors.orange),
                            onPressed: () => _showSubAdminDialog(doc.id, name, subAdmins),
                            tooltip: 'Manage Sub-Admins',
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditCourtLocationDialog(doc.id, data),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteCourtLocation(doc.id, name),
                          ),
                        ],
                      ),
                      children: [
                        if (subAdmins.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sub-Admins:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                ...subAdmins.map((adminId) => FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(adminId)
                                      .get(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData || !snapshot.data!.exists) {
                                      return ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.person, size: 20),
                                        title: Text(adminId),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                                          onPressed: () => _removeSubAdmin(doc.id, adminId),
                                        ),
                                      );
                                    }
                                    final userData = snapshot.data!.data() as Map<String, dynamic>?;
                                    final userName = userData?['firstName'] != null && userData?['lastName'] != null
                                        ? '${userData!['firstName']} ${userData['lastName']}'
                                        : userData?['phone'] as String? ?? adminId;
                                    
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.person, size: 20),
                                      title: Text(userName),
                                      subtitle: Text(userData?['phone'] as String? ?? ''),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                                        onPressed: () => _removeSubAdmin(doc.id, adminId),
                                      ),
                                    );
                                  },
                                )),
                              ],
                            ),
                          ),
                      ],
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

  Future<void> _showAddCourtLocationDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final openTimeController = TextEditingController(text: '6:00 AM');
    final closeTimeController = TextEditingController(text: '11:00 PM');
    final priceController = TextEditingController(text: '200');
    final courtsController = TextEditingController(text: '1');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Location Name',
                  hintText: 'e.g., 13 Padel',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'e.g., October & Zayed',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: openTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Open Time',
                        hintText: '6:00 AM',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: closeTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Close Time',
                        hintText: '11:00 PM',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Price per 30 min (EGP)',
                  hintText: '200',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: courtsController,
                decoration: const InputDecoration(
                  labelText: 'Number of Courts',
                  hintText: '1',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
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
              if (nameController.text.trim().isNotEmpty) {
                await _addCourtLocation(
                  nameController.text.trim(),
                  addressController.text.trim(),
                  openTimeController.text.trim(),
                  closeTimeController.text.trim(),
                  double.tryParse(priceController.text) ?? 200.0,
                  int.tryParse(courtsController.text) ?? 1,
                );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCourtLocationDialog(String locationId, Map<String, dynamic> data) async {
    final nameController = TextEditingController(text: data['name'] as String? ?? '');
    final addressController = TextEditingController(text: data['address'] as String? ?? '');
    final openTimeController = TextEditingController(text: data['openTime'] as String? ?? '6:00 AM');
    final closeTimeController = TextEditingController(text: data['closeTime'] as String? ?? '11:00 PM');
    final priceController = TextEditingController(text: (data['pricePer30Min'] as num?)?.toString() ?? '200');
    final courts = (data['courts'] as List?) ?? [];
    final courtsController = TextEditingController(text: courts.length.toString());

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Location Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: openTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Open Time',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: closeTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Close Time',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(
                  labelText: 'Price per 30 min (EGP)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: courtsController,
                decoration: const InputDecoration(
                  labelText: 'Number of Courts',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
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
              if (nameController.text.trim().isNotEmpty) {
                await _updateCourtLocation(
                  locationId,
                  nameController.text.trim(),
                  addressController.text.trim(),
                  openTimeController.text.trim(),
                  closeTimeController.text.trim(),
                  double.tryParse(priceController.text) ?? 200.0,
                  int.tryParse(courtsController.text) ?? 1,
                );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCourtLocation(
    String name,
    String address,
    String openTime,
    String closeTime,
    double pricePer30Min,
    int numberOfCourts,
  ) async {
    try {
      final courts = List.generate(numberOfCourts, (index) => {
        'id': 'court_${index + 1}',
        'name': 'Court ${index + 1}',
      });

      await FirebaseFirestore.instance.collection('courtLocations').add({
        'name': name,
        'address': address,
        'openTime': openTime,
        'closeTime': closeTime,
        'pricePer30Min': pricePer30Min,
        'courts': courts,
        'subAdmins': [], // Initialize empty sub-admins array
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location added successfully'),
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

  Future<void> _updateCourtLocation(
    String locationId,
    String name,
    String address,
    String openTime,
    String closeTime,
    double pricePer30Min,
    int numberOfCourts,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(locationId)
          .get();
      
      final existingCourts = (doc.data()?['courts'] as List?) ?? [];
      final currentCount = existingCourts.length;
      
      List<Map<String, dynamic>> courts;
      if (numberOfCourts > currentCount) {
        // Add new courts
        courts = List.from(existingCourts);
        for (int i = currentCount; i < numberOfCourts; i++) {
          courts.add({
            'id': 'court_${i + 1}',
            'name': 'Court ${i + 1}',
          });
        }
      } else if (numberOfCourts < currentCount) {
        // Remove courts
        courts = existingCourts.take(numberOfCourts).toList().cast<Map<String, dynamic>>();
      } else {
        courts = existingCourts.cast<Map<String, dynamic>>();
      }

      await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(locationId)
          .update({
        'name': name,
        'address': address,
        'openTime': openTime,
        'closeTime': closeTime,
        'pricePer30Min': pricePer30Min,
        'courts': courts,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated successfully'),
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

  Future<void> _deleteCourtLocation(String locationId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Location'),
        content: Text('Are you sure you want to delete "$name"?'),
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
            .collection('courtLocations')
            .doc(locationId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting location: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showSubAdminDialog(String locationId, String locationName, List<String> currentSubAdmins) async {
    final searchController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Sub-Admins for $locationName'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Search for user by phone number or email:'),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Phone or Email',
                    hintText: '+201234567890 or user@example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    await _addSubAdmin(locationId, searchController.text.trim());
                    if (context.mounted) {
                      Navigator.pop(context);
                      _showSubAdminDialog(locationId, locationName, currentSubAdmins);
                    }
                  },
                  child: const Text('Add Sub-Admin'),
                ),
                if (currentSubAdmins.isNotEmpty) ...[
                  const Divider(),
                  const Text('Current Sub-Admins:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...currentSubAdmins.map((adminId) => FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(adminId).get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return ListTile(
                          dense: true,
                          title: Text(adminId),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red),
                            onPressed: () {
                              _removeSubAdmin(locationId, adminId);
                              Navigator.pop(context);
                              _showSubAdminDialog(locationId, locationName, currentSubAdmins);
                            },
                          ),
                        );
                      }
                      final userData = snapshot.data!.data() as Map<String, dynamic>?;
                      final userName = userData?['firstName'] != null && userData?['lastName'] != null
                          ? '${userData!['firstName']} ${userData['lastName']}'
                          : userData?['phone'] as String? ?? adminId;
                      
                      return ListTile(
                        dense: true,
                        title: Text(userName),
                        subtitle: Text(userData?['phone'] as String? ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red),
                          onPressed: () {
                            _removeSubAdmin(locationId, adminId);
                            Navigator.pop(context);
                            _showSubAdminDialog(locationId, locationName, currentSubAdmins);
                          },
                        ),
                      );
                    },
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSubAdmin(String locationId, String identifier) async {
    try {
      // Search for user by phone or email
      QuerySnapshot? userSnapshot;
      
      // Try phone first
      if (identifier.startsWith('+') || RegExp(r'^\d+$').hasMatch(identifier.replaceAll(' ', ''))) {
        userSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: identifier)
            .limit(1)
            .get();
      }
      
      // If not found, try email
      if ((userSnapshot?.docs.isEmpty ?? true) && identifier.contains('@')) {
        userSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: identifier)
            .limit(1)
            .get();
      }
      
      if (userSnapshot == null || userSnapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found. Please check the phone number or email.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final userId = userSnapshot.docs.first.id;
      final locationDoc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(locationId)
          .get();
      
      final currentSubAdmins = (locationDoc.data()?['subAdmins'] as List?)?.cast<String>() ?? [];
      
      if (currentSubAdmins.contains(userId)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User is already a sub-admin for this location.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      currentSubAdmins.add(userId);
      
      await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(locationId)
          .update({
        'subAdmins': currentSubAdmins,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Log the action
      await _logSubAdminAction(
        locationId: locationId,
        action: 'sub_admin_added',
        performedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        details: 'Sub-admin assigned to location',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sub-admin added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding sub-admin: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeSubAdmin(String locationId, String userId) async {
    try {
      final locationDoc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(locationId)
          .get();
      
      final currentSubAdmins = (locationDoc.data()?['subAdmins'] as List?)?.cast<String>() ?? [];
      currentSubAdmins.remove(userId);
      
      await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(locationId)
          .update({
        'subAdmins': currentSubAdmins,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Log the action
      await _logSubAdminAction(
        locationId: locationId,
        action: 'sub_admin_removed',
        performedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        details: 'Sub-admin removed from location',
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sub-admin removed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing sub-admin: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logSubAdminAction({
    required String locationId,
    required String action,
    required String performedBy,
    required String details,
    String? bookingId,
    String? targetUserId,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('subAdminLogs').add({
        'locationId': locationId,
        'action': action, // 'sub_admin_added', 'sub_admin_removed', 'booking_created', 'booking_cancelled', 'booking_blocked'
        'performedBy': performedBy,
        'targetUserId': targetUserId,
        'bookingId': bookingId,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error logging sub-admin action: $e');
    }
  }

  // SUB-ADMIN LOGS TAB
  Widget _buildSubAdminLogsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                'Sub-Admin Action Logs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() {});
                },
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('subAdminLogs')
                .orderBy('timestamp', descending: true)
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final logs = snapshot.data!.docs;

              if (logs.isEmpty) {
                return const Center(child: Text('No logs available'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final doc = logs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final action = data['action'] as String? ?? 'unknown';
                  final performedBy = data['performedBy'] as String? ?? '';
                  final targetUserId = data['targetUserId'] as String? ?? '';
                  final locationId = data['locationId'] as String? ?? '';
                  final bookingId = data['bookingId'] as String? ?? '';
                  final details = data['details'] as String? ?? '';
                  final timestamp = data['timestamp'] as Timestamp?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        _getActionIcon(action),
                        color: _getActionColor(action),
                      ),
                      title: Text(_getActionLabel(action)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (locationId.isNotEmpty)
                            FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('courtLocations')
                                  .doc(locationId)
                                  .get(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data!.exists) {
                                  final locData = snapshot.data!.data() as Map<String, dynamic>?;
                                  return Text('Location: ${locData?['name'] ?? locationId}');
                                }
                                return Text('Location: $locationId');
                              },
                            ),
                          if (targetUserId.isNotEmpty)
                            FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(targetUserId)
                                  .get(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data!.exists) {
                                  final userData = snapshot.data!.data() as Map<String, dynamic>?;
                                  final userName = userData?['firstName'] != null && userData?['lastName'] != null
                                      ? '${userData!['firstName']} ${userData['lastName']}'
                                      : userData?['phone'] as String? ?? targetUserId;
                                  return Text('User: $userName');
                                }
                                return Text('User: $targetUserId');
                              },
                            ),
                          if (details.isNotEmpty) Text('Details: $details'),
                          if (timestamp != null)
                            Text(
                              'Time: ${_formatTimestamp(timestamp)}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                      trailing: bookingId.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.arrow_forward),
                              onPressed: () {
                                // TODO: Navigate to booking details
                              },
                            )
                          : null,
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

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'sub_admin_added':
        return Icons.person_add;
      case 'sub_admin_removed':
        return Icons.person_remove;
      case 'booking_created':
        return Icons.add_circle;
      case 'booking_cancelled':
        return Icons.cancel;
      case 'booking_blocked':
        return Icons.block;
      default:
        return Icons.info;
    }
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'sub_admin_added':
        return Colors.green;
      case 'sub_admin_removed':
        return Colors.red;
      case 'booking_created':
        return Colors.blue;
      case 'booking_cancelled':
        return Colors.orange;
      case 'booking_blocked':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getActionLabel(String action) {
    switch (action) {
      case 'sub_admin_added':
        return 'Sub-Admin Added';
      case 'sub_admin_removed':
        return 'Sub-Admin Removed';
      case 'booking_created':
        return 'Booking Created';
      case 'booking_cancelled':
        return 'Booking Cancelled';
      case 'booking_blocked':
        return 'Booking Blocked';
      default:
        return action;
    }
  }
}
