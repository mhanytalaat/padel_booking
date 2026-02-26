import 'admin_calendar_screen.dart';
import 'admin_calendar_grid_screen.dart';
import 'admin_book_training_screen.dart';
import 'admin_add_bundle_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import '../services/notification_service.dart';
import '../services/bundle_service.dart';
import '../models/bundle_model.dart';
import 'tournament_dashboard_screen.dart';
import 'tournament_groups_screen.dart';
import 'training_calendar_screen.dart';
import 'monthly_reports_screen.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _limitController = TextEditingController();
  final _supportEmailController = TextEditingController();
  final _supportPhoneController = TextEditingController();
  final _supportWhatsappController = TextEditingController();
  bool _isLoading = false;
  bool _isSavingSupport = false;
  bool _isAuthorized = false;
  bool _isSubAdmin = false;
  List<String> _subAdminLocationIds = [];
  bool _checkingAuth = true;

  // Tournament requests tab filters
  String? _tournamentFilterId;
  String? _tournamentFilterLevel;
  String _tournamentRequestViewMode = 'pending'; // 'pending' | 'approved'

  // Admin Bookings tab filters (training bookings list)
  DateTime? _bookingFilterDate;
  String? _bookingFilterStatus; // null = all, 'pending', 'approved', 'rejected'
  final TextEditingController _bookingFilterNameController = TextEditingController();
  final FocusNode _bookingFilterNameFocus = FocusNode();

  // Admin phone number and email
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com'; // Add admin email if needed

  // Time options for dropdowns
  static const List<String> _timeOptions = [
    '6:00 AM', '6:30 AM', '7:00 AM', '7:30 AM', '8:00 AM', '8:30 AM',
    '9:00 AM', '9:30 AM', '10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM',
    '12:00 PM', '12:30 PM', '1:00 PM', '1:30 PM', '2:00 PM', '2:30 PM',
    '3:00 PM', '3:30 PM', '4:00 PM', '4:30 PM', '5:00 PM', '5:30 PM',
    '6:00 PM', '6:30 PM', '7:00 PM', '7:30 PM', '8:00 PM', '8:30 PM',
    '9:00 PM', '9:30 PM', '10:00 PM', '10:30 PM', '11:00 PM', '11:30 PM',
    '12:00 AM', // Midnight
  ];

  // Midnight play end time options (12:30 AM to 6:00 AM). Midnight play = same cost as night; morning starts after this.
  static const List<String> _midnightPlayEndOptions = [
    '12:30 AM',
    '1:00 AM',
    '1:30 AM',
    '2:00 AM',
    '2:30 AM',
    '3:00 AM',
    '3:30 AM',
    '4:00 AM',
    '4:30 AM',
    '5:00 AM',
    '5:30 AM',
    '6:00 AM',
  ];

  // Morning start time options (when morning rate begins). Default 6:00 AM.
  static const List<String> _morningStartTimeOptions = [
    '4:00 AM',
    '4:30 AM',
    '5:00 AM',
    '5:30 AM',
    '6:00 AM',
    '6:30 AM',
    '7:00 AM',
    '7:30 AM',
    '8:00 AM',
  ];

  Future<String?> _uploadLocationImage(File imageFile) async {
    const maxRetries = 3;
    const timeoutDuration = Duration(seconds: 60); // Increased to 60 seconds
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('Reading image file... (Attempt $attempt/$maxRetries)');
        final fileSize = await imageFile.length();
        debugPrint('Image size: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
        
        final fileName = 'location_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref().child('location_logos/$fileName');
        
        debugPrint('Uploading to Firebase Storage... (Attempt $attempt/$maxRetries)');
        
        // Upload with increased timeout and retry logic
        final uploadTask = ref.putFile(
          imageFile,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        
        // Wait for upload with timeout
        await uploadTask.timeout(
          timeoutDuration,
          onTimeout: () {
            throw TimeoutException('Image upload timed out after ${timeoutDuration.inSeconds} seconds');
          },
        );
        
        debugPrint('Upload successful, getting download URL...');
        // Get download URL - this should work with public read rules
        final downloadUrl = await ref.getDownloadURL().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Getting download URL timed out');
          },
        );
        
        debugPrint('Upload complete: $downloadUrl');
        debugPrint('NOTE: If images fail to load on web, configure CORS in Firebase Console:');
        debugPrint('Storage → Settings → CORS configuration');
        debugPrint('Add: [{"origin":["*"],"method":["GET"],"maxAgeSeconds":3600}]');
        return downloadUrl;
      } catch (e) {
        debugPrint('Error uploading image (Attempt $attempt/$maxRetries): $e');
        debugPrint('Error type: ${e.runtimeType}');
        debugPrint('Error details: ${e.toString()}');
        
        if (e is TimeoutException) {
          if (attempt < maxRetries) {
            debugPrint('Retrying upload...');
            await Future.delayed(Duration(seconds: attempt * 2)); // Exponential backoff
            continue;
          } else {
            debugPrint('Upload failed after $maxRetries attempts');
            debugPrint('TROUBLESHOOTING:');
            debugPrint('1. Check Firebase Storage rules in Firebase Console');
            debugPrint('2. Verify network connection');
            debugPrint('3. Check Firebase Storage quota/limits');
            return null;
          }
        } else {
          // For non-timeout errors, log and return
          debugPrint('Upload failed with non-timeout error: $e');
          debugPrint('Error type: ${e.runtimeType}');
          // Check if it's a permission error
          if (e.toString().toLowerCase().contains('permission') || 
              e.toString().toLowerCase().contains('unauthorized') ||
              e.toString().toLowerCase().contains('403')) {
            debugPrint('PERMISSION ERROR: Check Firebase Storage rules!');
            debugPrint('Make sure storage.rules allows authenticated admin users to write');
          }
          return null;
        }
      }
    }
    
    return null;
  }

  Future<String?> _uploadLocationImageFromXFile(XFile imageFile) async {
    const maxRetries = 3;
    const timeoutDuration = Duration(seconds: 60); // Increased to 60 seconds
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('Reading image bytes... (Attempt $attempt/$maxRetries)');
        final bytes = await imageFile.readAsBytes();
        debugPrint('Image size: ${bytes.length} bytes (${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
        
        final fileName = 'location_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref().child('location_logos/$fileName');
        
        debugPrint('Uploading to Firebase Storage... (Attempt $attempt/$maxRetries)');
        
        // Upload with increased timeout and retry logic
        final uploadTask = ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        
        // Wait for upload with timeout
        await uploadTask.timeout(
          timeoutDuration,
          onTimeout: () {
            throw TimeoutException('Image upload timed out after ${timeoutDuration.inSeconds} seconds');
          },
        );
        
        debugPrint('Upload successful, getting download URL...');
        // Get download URL - this should work with public read rules
        final downloadUrl = await ref.getDownloadURL().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Getting download URL timed out');
          },
        );
        
        debugPrint('Upload complete: $downloadUrl');
        debugPrint('NOTE: If images fail to load on web, configure CORS in Firebase Console:');
        debugPrint('Storage → Settings → CORS configuration');
        debugPrint('Add: [{"origin":["*"],"method":["GET"],"maxAgeSeconds":3600}]');
        return downloadUrl;
      } catch (e) {
        debugPrint('Error uploading image (Attempt $attempt/$maxRetries): $e');
        debugPrint('Error type: ${e.runtimeType}');
        debugPrint('Error details: ${e.toString()}');
        
        if (e is TimeoutException) {
          if (attempt < maxRetries) {
            debugPrint('Retrying upload...');
            await Future.delayed(Duration(seconds: attempt * 2)); // Exponential backoff
            continue;
          } else {
            debugPrint('Upload failed after $maxRetries attempts');
            debugPrint('TROUBLESHOOTING:');
            debugPrint('1. Check Firebase Storage rules in Firebase Console');
            debugPrint('2. Verify network connection');
            debugPrint('3. Check Firebase Storage quota/limits');
            return null;
          }
        } else {
          // For non-timeout errors, log and return
          debugPrint('Upload failed with non-timeout error: $e');
          debugPrint('Error type: ${e.runtimeType}');
          // Check if it's a permission error
          if (e.toString().toLowerCase().contains('permission') || 
              e.toString().toLowerCase().contains('unauthorized') ||
              e.toString().toLowerCase().contains('403')) {
            debugPrint('PERMISSION ERROR: Check Firebase Storage rules!');
            debugPrint('Make sure storage.rules allows authenticated admin users to write');
          }
          return null;
        }
      }
    }
    
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 11, vsync: this);
    _checkAdminAccess();
    _loadCurrentLimit();
    _loadSupportConfig();
  }

  Future<void> _checkAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isAuthorized = false;
        _isSubAdmin = false;
        _checkingAuth = false;
      });
      return;
    }

    // Check if main admin
    final isMainAdmin = user.phoneNumber == adminPhone || user.email == adminEmail;
    
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
      // Permission denied during sign-out is expected, ignore silently
      if (!e.toString().contains('permission-denied')) {
        debugPrint('Error checking sub-admin access: $e');
      }
    }
    
    setState(() {
      _isAuthorized = isMainAdmin || isSubAdminForAnyLocation;
      _isSubAdmin = isSubAdminForAnyLocation && !isMainAdmin;
      _subAdminLocationIds = subAdminLocationIds;
      _checkingAuth = false;
    });
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

  Future<void> _loadSupportConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('support')
          .get();
      if (doc.exists && mounted) {
        final data = doc.data();
        _supportEmailController.text = data?['supportEmail'] as String? ?? '';
        _supportPhoneController.text = data?['supportPhone'] as String? ?? '';
        _supportWhatsappController.text = data?['supportWhatsapp'] as String? ?? '';
      }
    } catch (e) {
      debugPrint('Error loading support config: $e');
    }
  }

  Future<void> _saveSupportConfig() async {
    setState(() => _isSavingSupport = true);
    try {
      await FirebaseFirestore.instance
          .collection('config')
          .doc('support')
          .set({
        'supportEmail': _supportEmailController.text.trim(),
        'supportPhone': _supportPhoneController.text.trim(),
        'supportWhatsapp': _supportWhatsappController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Support contact saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving support contact: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSupport = false);
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
    _bookingFilterNameController.dispose();
    _bookingFilterNameFocus.dispose();
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
        actions: [
          // Training Calendar Button
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Training Calendar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TrainingCalendarScreen(),
                ),
              );
            },
          ),
          // Monthly Reports Button
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: 'Monthly Reports',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MonthlyReportsScreen(),
                ),
              );
            },
          ),
        ],
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
            Tab(icon: Icon(Icons.calendar_today), text: 'Court Booking'),
            Tab(icon: Icon(Icons.check_circle), text: 'Approvals'),
            Tab(icon: Icon(Icons.card_membership), text: 'Training Bundles'),
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
          const AdminCalendarGridScreen(),
          _buildApprovalsTab(),
          _buildTrainingBundlesTab(),
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
            'Support Contact',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'These details will appear in the user profile. Users can reach out for help.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _supportEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Support Email',
              hintText: 'e.g. support@padelcore.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _supportPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Support Phone',
              hintText: 'e.g. +201006500506',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _supportWhatsappController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Support WhatsApp',
              hintText: 'e.g. +201006500506 (same as phone or different)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.chat_outlined),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSavingSupport ? null : _saveSupportConfig,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isSavingSupport
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Support Contact'),
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

  Future<void> _addVenueIfNotExists(String venueName, {double? lat, double? lng}) async {
    try {
      // Check if venue already exists
      final existing = await FirebaseFirestore.instance
          .collection('venues')
          .where('name', isEqualTo: venueName)
          .get();

      if (existing.docs.isEmpty) {
        // Add new venue
        final venueData = {
          'name': venueName,
          'createdAt': FieldValue.serverTimestamp(),
        };
        
        // Add coordinates if provided
        if (lat != null) venueData['lat'] = lat;
        if (lng != null) venueData['lng'] = lng;
        
        await FirebaseFirestore.instance.collection('venues').add(venueData);
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
    final nameController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Venue'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Venue Name',
                  hintText: 'e.g., Club13 Sheikh Zayed',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: latController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Latitude (Optional)',
                  hintText: 'e.g., 30.0444',
                  border: OutlineInputBorder(),
                  helperText: 'Get from Google Maps',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: lngController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Longitude (Optional)',
                  hintText: 'e.g., 31.2357',
                  border: OutlineInputBorder(),
                  helperText: 'Get from Google Maps',
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
                double? lat;
                double? lng;
                
                if (latController.text.trim().isNotEmpty) {
                  lat = double.tryParse(latController.text.trim());
                }
                if (lngController.text.trim().isNotEmpty) {
                  lng = double.tryParse(lngController.text.trim());
                }
                
                await _addVenueIfNotExists(nameController.text.trim(), lat: lat, lng: lng);
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
    try {
      // Fetch current venue data
      final venueDoc = await FirebaseFirestore.instance
          .collection('venues')
          .doc(venueId)
          .get();
      
      final venueData = venueDoc.data() as Map<String, dynamic>?;
      final currentLat = (venueData?['lat'] as num?)?.toDouble();
      final currentLng = (venueData?['lng'] as num?)?.toDouble();
      
      final nameController = TextEditingController(text: currentName);
      final latController = TextEditingController(
        text: currentLat != null ? currentLat.toString() : ''
      );
      final lngController = TextEditingController(
        text: currentLng != null ? currentLng.toString() : ''
      );
      
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit Venue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Venue Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: latController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Latitude (Optional)',
                    hintText: 'e.g., 30.0444',
                    border: OutlineInputBorder(),
                    helperText: 'Get from Google Maps',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: lngController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Longitude (Optional)',
                    hintText: 'e.g., 31.2357',
                    border: OutlineInputBorder(),
                    helperText: 'Get from Google Maps',
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
                  try {
                    final updateData = <String, dynamic>{
                      'name': nameController.text.trim(),
                    };
                    
                    // Parse and add coordinates if provided
                    if (latController.text.trim().isNotEmpty) {
                      final lat = double.tryParse(latController.text.trim());
                      if (lat != null) updateData['lat'] = lat;
                    } else {
                      updateData['lat'] = FieldValue.delete();
                    }
                    
                    if (lngController.text.trim().isNotEmpty) {
                      final lng = double.tryParse(lngController.text.trim());
                      if (lng != null) updateData['lng'] = lng;
                    } else {
                      updateData['lng'] = FieldValue.delete();
                    }
                    
                    await FirebaseFirestore.instance
                        .collection('venues')
                        .doc(venueId)
                        .update(updateData);
                    
                    // Update all slots with this venue name if name changed
                    if (nameController.text.trim() != currentName) {
                      final slots = await FirebaseFirestore.instance
                          .collection('slots')
                          .where('venue', isEqualTo: currentName)
                          .get();
                      
                      for (var slot in slots.docs) {
                        await slot.reference.update({'venue': nameController.text.trim()});
                      }
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading venue: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

        // Filter out bundle requests (they appear in Training Bundles tab)
        final allBookings = snapshot.data!.docs;
        final bookings = allBookings.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final isBundle = data['isBundle'] as bool? ?? false;
          final bookingType = data['bookingType'] as String? ?? '';
          // Exclude bundle bookings
          return !isBundle && bookingType != 'Bundle';
        }).toList();
        
        // Sort by timestamp client-side
        bookings.sort((a, b) {
          final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp); // Descending
        });

        // Show empty state if no bookings after filtering
        if (bookings.isEmpty) {
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
      final coach = bookingData['coach'] as String? ?? '';
      final bundleId = bookingData['bundleId'] as String?;
      final isBundle = bookingData['isBundle'] as bool? ?? false;

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // If this is a bundle booking, create a bundle session record
      if (isBundle && bundleId != null && bundleId.isNotEmpty) {
        try {
          final bundle = await BundleService().getBundleById(bundleId);
          if (bundle != null) {
            final sessionNumber = bundle.totalSessions - bundle.remainingSessions + 1;
            final playerCount = bookingData['slotsReserved'] as int? ?? 1;
            
            await BundleService().createBundleSession(
              bundleId: bundleId,
              userId: userId,
              sessionNumber: sessionNumber,
              date: date,
              time: time,
              venue: venue,
              coach: coach,
              playerCount: playerCount,
              bookingId: bookingId,
            );
          }
        } catch (e) {
          debugPrint('Error creating bundle session: $e');
        }
      }

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

  Future<Map<String, String>> _fetchBookingUserNames(Set<String> userIds) async {
    if (userIds.isEmpty) return {};
    final map = <String, String>{};
    for (final uid in userIds) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          final d = doc.data() as Map<String, dynamic>?;
          final first = d?['firstName'] as String? ?? '';
          final last = d?['lastName'] as String? ?? '';
          final full = d?['fullName'] as String?;
          final name = (full?.trim().isNotEmpty == true)
              ? full!
              : '$first $last'.trim().isEmpty
                  ? (d?['phone'] as String? ?? 'Unknown')
                  : '$first $last'.trim();
          map[uid] = name.isEmpty ? 'Unknown' : name;
        } else {
          map[uid] = 'Unknown';
        }
      } catch (_) {
        map[uid] = 'Unknown';
      }
    }
    return map;
  }

  // ALL BOOKINGS TAB
  // Bookings = training slot requests (venue, coach, time, approval workflow).
  // Training Bundles tab = purchased session packs; each bundle has multiple sessions.
  Widget _buildAllBookingsTab() {
    // Show court bookings for sub-admins, training bookings for main admin
    if (_isSubAdmin) {
      // Show court bookings filtered by sub-admin locations
      Query query = FirebaseFirestore.instance.collection('courtBookings');
      
      if (_subAdminLocationIds.length == 1) {
        query = query.where('locationId', isEqualTo: _subAdminLocationIds.first);
      }
      // For multiple locations, filter client-side
      
      return StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No court bookings found'));
          }

          final bookings = snapshot.data!.docs.where((doc) {
            if (_subAdminLocationIds.length > 1) {
              final data = doc.data() as Map<String, dynamic>;
              final locationId = data['locationId'] as String?;
              return locationId != null && _subAdminLocationIds.contains(locationId);
            }
            return true;
          }).toList();
          
          // Sort by date and time
          bookings.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aDate = aData['date'] as String? ?? '';
            final bDate = bData['date'] as String? ?? '';
            if (aDate != bDate) return aDate.compareTo(bDate);
            final aTimeRange = aData['timeRange'] as String? ?? '';
            final bTimeRange = bData['timeRange'] as String? ?? '';
            return aTimeRange.compareTo(bTimeRange);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            itemBuilder: (context, index) {
              final doc = bookings[index];
              final data = doc.data() as Map<String, dynamic>;
              
              final locationName = data['locationName'] as String? ?? 'Unknown Location';
              final dateStr = data['date'] as String? ?? '';
              final timeRange = data['timeRange'] as String? ?? '';
              final courts = data['courts'] as Map<String, dynamic>? ?? {};
              final totalCost = data['totalCost'] as num? ?? 0;
              final status = data['status'] as String? ?? 'confirmed';
              final userId = data['userId'] as String? ?? '';

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
                                  locationName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Date: $dateStr'),
                                Text('Time: $timeRange'),
                                Text('Courts: ${courts.keys.join(", ")}'),
                                Text('Total Cost: ${totalCost.toStringAsFixed(2)} EGP'),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: status == 'confirmed' ? Colors.green[100] : Colors.orange[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: status == 'confirmed' ? Colors.green[900] : Colors.orange[900],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
                        builder: (context, userSnapshot) {
                          if (userSnapshot.hasData && userSnapshot.data!.exists) {
                            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                            final userName = userData?['fullName'] as String? ?? 
                                '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();
                            final phone = userData?['phone'] as String? ?? 'No phone';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('User: $userName'),
                                Text('Phone: $phone'),
                              ],
                            );
                          }
                          return const Text('User: Loading...');
                        },
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
    
    // Main admin sees training bookings with filters and "Book for user"
    return Column(
      children: [
        _buildBookingsFilterBar(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
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
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('No bookings found'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _openAdminBookTraining(context),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Book for user'),
                      ),
                    ],
                  ),
                );
              }
              final bookings = snapshot.data!.docs;
              final userIds = bookings
                  .map((d) => (d.data() as Map<String, dynamic>)['userId'] as String?)
                  .whereType<String>()
                  .toSet();
              return FutureBuilder<Map<String, String>>(
                future: _fetchBookingUserNames(userIds),
                builder: (context, nameSnapshot) {
                  final userNames = nameSnapshot.data ?? {};
                  List<QueryDocumentSnapshot> filtered = List.from(bookings);
                  if (_bookingFilterDate != null) {
                    final fd = _bookingFilterDate!;
                    final filterDateStr =
                        '${fd.year}-${fd.month.toString().padLeft(2, '0')}-${fd.day.toString().padLeft(2, '0')}';
                    final filterDay = DateFormat('EEEE').format(fd);
                    filtered = filtered.where((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final isRecurring = d['isRecurring'] as bool? ?? false;
                      if (isRecurring) {
                        final days =
                            (d['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
                        return days.any(
                            (day) => day.toLowerCase() == filterDay.toLowerCase());
                      }
                      return d['date'] == filterDateStr;
                    }).toList();
                  }
                  final nameQuery =
                      _bookingFilterNameController.text.trim().toLowerCase();
                  if (nameQuery.isNotEmpty) {
                    filtered = filtered.where((doc) {
                      final uid =
                          (doc.data() as Map<String, dynamic>)['userId'] as String?;
                      final name = (uid != null ? userNames[uid] ?? '' : '').toLowerCase();
                      return name.contains(nameQuery);
                    }).toList();
                  }
                  if (_bookingFilterStatus != null && _bookingFilterStatus!.isNotEmpty) {
                    filtered = filtered.where((doc) {
                      final status = (doc.data() as Map<String, dynamic>)['status'] as String? ?? 'pending';
                      return status == _bookingFilterStatus;
                    }).toList();
                  }
                  filtered.sort((a, b) {
                    final aTimestamp =
                        (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    final bTimestamp =
                        (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    if (aTimestamp == null && bTimestamp == null) return 0;
                    if (aTimestamp == null) return 1;
                    if (bTimestamp == null) return -1;
                    return bTimestamp.compareTo(aTimestamp);
                  });
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final venue = data['venue'] as String? ?? 'Unknown';
                      final time = data['time'] as String? ?? 'Unknown';
                      final coach = data['coach'] as String? ?? 'Unknown';
                      final phone = data['phone'] as String? ?? 'Unknown';
                      final userId = data['userId'] as String? ?? '';
                      final isRecurring = data['isRecurring'] as bool? ?? false;
                      final recurringDays =
                          (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
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
                                        Text('Booked by: ${userNames[userId] ?? 'Unknown'}'),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if ((data['bundleId'] as String? ?? '').isEmpty) ...[
                                    TextButton.icon(
                                      onPressed: () => _addBookingToTrainingBundle(
                                        context,
                                        doc.id,
                                        data,
                                        userNames[userId] ?? 'Unknown',
                                      ),
                                      icon: const Icon(Icons.card_membership, size: 18),
                                      label: const Text('Add to training bundle'),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  ElevatedButton.icon(
                                    onPressed: () => _deleteBooking(doc.id),
                                    icon: const Icon(Icons.delete, size: 18),
                                    label: const Text('Delete'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
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
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openAdminBookTraining(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Book training for user (on behalf of)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookingsFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.calendar_today),
                tooltip: 'Filter by date',
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _bookingFilterDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) setState(() => _bookingFilterDate = picked);
                },
              ),
              if (_bookingFilterDate != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    label: Text(DateFormat('MMM d, yyyy').format(_bookingFilterDate!)),
                    onDeleted: () => setState(() => _bookingFilterDate = null),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: _bookingFilterNameController,
                  focusNode: _bookingFilterNameFocus,
                  decoration: const InputDecoration(
                    labelText: 'Search by name',
                    hintText: 'Booked by name...',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_bookingFilterDate != null ||
                  _bookingFilterNameController.text.trim().isNotEmpty ||
                  _bookingFilterStatus != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _bookingFilterDate = null;
                      _bookingFilterStatus = null;
                      _bookingFilterNameController.clear();
                    });
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip('All', null),
                _buildStatusChip('Pending', 'pending'),
                _buildStatusChip('Approved', 'approved'),
                _buildStatusChip('Rejected', 'rejected'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String? value) {
    final selected = _bookingFilterStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (v) => setState(() => _bookingFilterStatus = v ? value : null),
      ),
    );
  }

  void _openAdminBookTraining(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AdminBookTrainingScreen(),
      ),
    );
  }

  Future<void> _addBookingToTrainingBundle(
    BuildContext context,
    String bookingId,
    Map<String, dynamic> data,
    String userName,
  ) async {
    final userId = data['userId'] as String? ?? '';
    final userPhone = data['phone'] as String? ?? '';
    final date = data['date'] as String? ?? '';
    final time = data['time'] as String? ?? '';
    final venue = data['venue'] as String? ?? '';
    final coach = data['coach'] as String? ?? '';
    if (userId.isEmpty || date.isEmpty || time.isEmpty || venue.isEmpty || coach.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking is missing required fields'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    try {
      final bundleId = await BundleService().createOneTimeBundleForBooking(
        bookingId: bookingId,
        userId: userId,
        userName: userName,
        userPhone: userPhone,
        date: date,
        time: time,
        venue: venue,
        coach: coach,
        playerCount: 1,
        approveAndActivate: true,
        expirationDays: 60,
      );
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'bundleId': bundleId,
        'isBundle': true,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking linked to Training Bundle. You can add payment, notes, and mark attendance there.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding to bundle: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  // Helper method to fetch Firebase Storage images via authenticated API (bypasses CORS on web)
  Future<Uint8List?> _fetchImageBytesFromUrl(String imageUrl) async {
    try {
      debugPrint('Fetching image bytes from Firebase Storage: $imageUrl');
      
      // Extract the path from the download URL
      // URL format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media&token={token}
      final uri = Uri.parse(imageUrl);
      
      // Try to extract path from the full URI string (including query)
      // The path is between /o/ and the first ?
      final fullUriString = imageUrl;
      final pathMatch = RegExp(r'/o/(.+?)(\?|$)').firstMatch(fullUriString);
      
      if (pathMatch == null) {
        debugPrint('Could not extract path from URL: $imageUrl');
        debugPrint('URI path: ${uri.path}');
        debugPrint('Full URI string: $fullUriString');
        return null;
      }
      
      final encodedPath = pathMatch.group(1);
      if (encodedPath == null || encodedPath.isEmpty) {
        debugPrint('Path group is null or empty');
        return null;
      }
      
      debugPrint('Extracted encoded path: $encodedPath');
      
      // Decode the path (URL encoded, e.g., location_logos%2Flocation_xxx.jpg)
      final decodedPath = Uri.decodeComponent(encodedPath);
      debugPrint('Decoded path: $decodedPath');
      
      // Get reference using the decoded path
      final ref = FirebaseStorage.instance.ref(decodedPath);
      
      // Fetch bytes using authenticated request (bypasses CORS)
      final bytes = await ref.getData().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Timeout fetching image bytes');
          throw TimeoutException('Image fetch timed out');
        },
      );
      
      if (bytes != null) {
        debugPrint('Successfully fetched ${bytes.length} bytes');
      } else {
        debugPrint('Fetched bytes are null');
      }
      
      return bytes;
    } catch (e) {
      debugPrint('Error fetching image bytes from Firebase Storage: $e');
      debugPrint('Error type: ${e.runtimeType}');
      return null;
    }
  }

  // Helper method to build network image (CORS must be configured in Firebase Storage for web)
  Widget _buildNetworkImage(String imageUrl, {double? width, double? height, BoxFit fit = BoxFit.cover, Widget? fallback}) {
    // Use Image.network directly - will work if CORS is configured, otherwise shows fallback
    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        // Silently show fallback if image fails to load (likely CORS issue)
        if (!context.mounted) return const SizedBox.shrink();
        return fallback ?? const Icon(Icons.error, color: Colors.red);
      },
    );
  }

  // TOURNAMENTS TAB
  Widget _buildTournamentsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showAddTournamentDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add New Tournament'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showClearTestDataDialog(),
                icon: const Icon(Icons.delete_sweep, color: Colors.red),
                label: const Text('Clear Test Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red,
                ),
              ),
            ],
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
                  final isArchived = data['isArchived'] as bool? ?? false;
                  final status = data['status'] as String? ?? 'upcoming';
                  final date = data['date'] as String?;
                  final tournamentNumber = data['tournamentNumber'] as int?;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isArchived ? Colors.grey[200] : null,
                    child: ListTile(
                      leading: imageUrl.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: imageUrl.startsWith('http')
                                  ? _buildNetworkImage(
                                      imageUrl,
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                      fallback: const Icon(Icons.emoji_events, color: Color(0xFF1E3A8A)),
                                    )
                                  : _buildAssetImage(imageUrl, width: 40, height: 40),
                            )
                          : const Icon(Icons.emoji_events, color: Color(0xFF1E3A8A)),
                      title: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (tournamentNumber != null) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[100],
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '#$tournamentNumber',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[900],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (date != null && date.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
                                      const SizedBox(width: 4),
                                      Text(
                                        date,
                                        style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isArchived)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey[400],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'ARCHIVED',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (description.isNotEmpty) Text(description),
                          Text('Status: ${status.toUpperCase()}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildActionButton(
                                  icon: isArchived ? Icons.unarchive : Icons.archive,
                                  label: isArchived ? 'Unarchive' : 'Archive',
                                  color: Colors.orange,
                                  onTap: () => _toggleArchiveTournament(doc.id, name, !isArchived),
                                ),
                                _buildActionButton(
                                  icon: Icons.group,
                                  label: 'Groups',
                                  color: Colors.orange,
                                  onTap: () {
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
                                ),
                                _buildActionButton(
                                  icon: Icons.leaderboard,
                                  label: 'Dashboard',
                                  color: Colors.green,
                                  onTap: () {
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
                                ),
                                if (data['isParentTournament'] == true)
                                  _buildActionButton(
                                    icon: Icons.add_circle,
                                    label: 'Add Week',
                                    color: Colors.green,
                                    onTap: () => _showAddTournamentDialog(
                                      parentTournamentId: doc.id,
                                      parentTournamentName: name,
                                    ),
                                  ),
                                if (data['isParentTournament'] == true)
                                  _buildActionButton(
                                    icon: Icons.calendar_view_week,
                                    label: 'View Weeks',
                                    color: Colors.purple,
                                    onTap: () => _showWeeklyTournamentsDialog(doc.id, name),
                                  ),
                                _buildActionButton(
                                  icon: Icons.edit,
                                  label: 'Edit',
                                  color: Colors.blue,
                                  onTap: () => _showEditTournamentDialog(doc.id, name, description),
                                ),
                                _buildActionButton(
                                  icon: Icons.delete_sweep,
                                  label: 'Clear',
                                  color: Colors.orange,
                                  onTap: () => _showClearSingleTournamentDialog(doc.id, name),
                                ),
                                _buildActionButton(
                                  icon: Icons.delete,
                                  label: 'Delete',
                                  color: Colors.red,
                                  onTap: () => _deleteTournament(doc.id, name),
                                ),
                              ],
                            ),
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

  Future<void> _showAddTournamentDialog({String? parentTournamentId, String? parentTournamentName}) async {
    final nameController = TextEditingController(
      text: parentTournamentName != null ? '$parentTournamentName - Week ' : '',
    );
    final descriptionController = TextEditingController();
    final imageUrlController = TextEditingController();
    final dateController = TextEditingController();
    final tournamentNumberController = TextEditingController();
    final timeController = TextEditingController();
    final locationController = TextEditingController();
    final entryFeeController = TextEditingController();
    final prizeController = TextEditingController();
    final maxParticipantsController = TextEditingController(text: '12');
    String typeValue = 'Single Elimination';
    List<String> skillLevelValues = ['Beginners'];
    const List<String> allSkillLevels = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];
    bool isParentTournament = parentTournamentId == null; // If no parent, this IS a parent

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title: Text(parentTournamentId != null 
            ? 'Add Weekly Tournament to $parentTournamentName' 
            : 'Add New Tournament'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: parentTournamentId != null ? 'Weekly Tournament Name' : 'Tournament Name',
                  hintText: parentTournamentId != null 
                      ? 'e.g., TPF Sheikh Zayed - Week 1' 
                      : 'e.g., Tournament Padel Factory (TPF)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (parentTournamentId == null) ...[
                Row(
                  children: [
                    Checkbox(
                      value: isParentTournament,
                      onChanged: (value) => setDialogState(() => isParentTournament = value ?? true),
                    ),
                    const Expanded(
                      child: Text(
                        'This is a parent tournament (e.g., TPF - with weekly tournaments)',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
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
                        newList.add('Beginners');
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
                    'tournamentNumber': tournamentNumberController.text.trim().isNotEmpty 
                        ? int.tryParse(tournamentNumberController.text.trim()) 
                        : null,
                    'time': timeController.text.trim(),
                    'location': locationController.text.trim(),
                    'entryFee': int.tryParse(entryFeeController.text.trim()) ?? 0,
                    'prize': int.tryParse(prizeController.text.trim()) ?? 0,
                    'maxParticipants': int.tryParse(maxParticipantsController.text.trim()) ?? 12,
                    'participants': 0,
                    'isParentTournament': parentTournamentId == null && isParentTournament,
                    'parentTournamentId': parentTournamentId,
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
    List<String> currentSkill = skillLevelData is List
        ? (skillLevelData as List).map((e) => e.toString()).toList()
        : (skillLevelData != null ? [skillLevelData.toString()] : ['Beginners']);
    // Normalize legacy 'Beginner' to 'Beginners'
    currentSkill = currentSkill.map((l) => l == 'Beginner' ? 'Beginners' : l).toList();
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
    // Ensure typeValue is valid - if currentType is not in dropdown, default to 'Single Elimination'
    const validTypes = ['Single Elimination', 'League', 'simple', 'two-phase-knockout'];
    String typeValue = validTypes.contains(currentType) ? currentType : 'Single Elimination';
    List<String> skillLevelValues = List<String>.from(currentSkill);
    const List<String> allSkillLevels = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];

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
                  DropdownMenuItem(value: 'simple', child: Text('Simple (Groups + Playoffs)')),
                  DropdownMenuItem(value: 'two-phase-knockout', child: Text('Two-Phase + Knockout')),
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
                        newList.add('Beginners');
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
        'status': 'upcoming',
        'isArchived': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      if (imageUrl.isNotEmpty) {
        tournamentData['imageUrl'] = imageUrl;
      }

      // Extra fields for home cards
      extraFields.forEach((key, value) {
        if (value != null) {
          tournamentData[key] = value;
        }
        // Explicitly set null values for optional fields
        else if (key == 'parentTournamentId' || key == 'tournamentNumber') {
          // Don't add these fields if they're null
        }
        else {
          tournamentData[key] = value;
        }
      });
      
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

  Future<void> _showWeeklyTournamentsDialog(String parentTournamentId, String parentName) async {
    try {
      // Get all weekly tournaments for this parent
      final weeklyTournamentsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .where('parentTournamentId', isEqualTo: parentTournamentId)
          .get();

      if (!mounted) return;

      // Sort client-side by date
      final weeklyTournaments = weeklyTournamentsSnapshot.docs;
      weeklyTournaments.sort((a, b) {
        final aDate = (a.data())['date'] as String? ?? '';
        final bDate = (b.data())['date'] as String? ?? '';
        return aDate.compareTo(bDate);
      });

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Weekly Tournaments - $parentName'),
          content: SizedBox(
            width: double.maxFinite,
            child: weeklyTournaments.isEmpty
                ? const Text('No weekly tournaments yet. Click "Add Weekly Tournament" to create one.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: weeklyTournaments.length,
                    itemBuilder: (context, index) {
                      final doc = weeklyTournaments[index];
                      final data = doc.data();
                      final name = data['name'] as String? ?? 'Week ${index + 1}';
                      final date = data['date'] as String? ?? '';
                      final status = data['status'] as String? ?? 'upcoming';
                      final tournamentNumber = data['tournamentNumber'] as int?;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: status == 'completed' ? Colors.green : Colors.orange,
                        child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          if (tournamentNumber != null) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#$tournamentNumber',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text('$date • ${status.toUpperCase()}', style: const TextStyle(fontSize: 11)),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
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
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          minimumSize: const Size(60, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.open_in_new, size: 18),
                            SizedBox(width: 6),
                            Text('View', style: TextStyle(fontSize: 12)),
                          ],
                        ),
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
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showAddTournamentDialog(
                  parentTournamentId: parentTournamentId,
                  parentTournamentName: parentName,
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Week'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading weekly tournaments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteTournament(String tournamentId, String tournamentName) async {
    // Check if this is a parent tournament with weekly tournaments
    final weeklyTournaments = await FirebaseFirestore.instance
        .collection('tournaments')
        .where('parentTournamentId', isEqualTo: tournamentId)
        .get();

    if (weeklyTournaments.docs.isNotEmpty) {
      final deleteWeekly = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Parent Tournament'),
          content: Text('This tournament has ${weeklyTournaments.docs.length} weekly tournament(s).\n\nDo you want to delete the parent tournament and ALL weekly tournaments?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete All'),
            ),
          ],
        ),
      );

      if (deleteWeekly == true) {
        try {
          // Delete all weekly tournaments first
          for (var weeklyDoc in weeklyTournaments.docs) {
            await _deleteAllTournamentData(weeklyDoc.id);
          }
          // Then delete parent
          await _deleteAllTournamentData(tournamentId);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Parent tournament and all weekly tournaments deleted successfully'),
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
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tournament'),
        content: Text('Are you sure you want to delete "$tournamentName"?\n\nThis will also delete all registrations, matches, and standings for this tournament.'),
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
        await _deleteAllTournamentData(tournamentId);

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

  Future<void> _deleteAllTournamentData(String tournamentId) async {
    // Delete all registrations for this tournament
    final registrations = await FirebaseFirestore.instance
        .collection('tournamentRegistrations')
        .where('tournamentId', isEqualTo: tournamentId)
        .get();

    for (var reg in registrations.docs) {
      await reg.reference.delete();
    }

    // Delete all matches for this tournament
    final matches = await FirebaseFirestore.instance
        .collection('tournamentMatches')
        .where('tournamentId', isEqualTo: tournamentId)
        .get();

    for (var match in matches.docs) {
      await match.reference.delete();
    }

    // Delete standings subcollection
    final standings = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(tournamentId)
        .collection('standings')
        .get();

    for (var standing in standings.docs) {
      await standing.reference.delete();
    }

    // Delete the tournament document
    await FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).delete();
  }

  Future<void> _toggleArchiveTournament(String tournamentId, String tournamentName, bool archive) async {
    try {
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .update({'isArchived': archive});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(archive 
                ? '✅ Tournament archived (hidden from main list)' 
                : '✅ Tournament unarchived (visible in main list)'),
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

  Future<void> _showClearTestDataDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Clear All Test Data?', style: TextStyle(color: Colors.red)),
        content: const Text(
          'This will PERMANENTLY DELETE:\n\n'
          '• All tournaments\n'
          '• All tournament registrations\n'
          '• All tournament matches\n'
          '• All tournament standings\n\n'
          'This action CANNOT be undone!\n\n'
          'Are you absolutely sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearAllTestData();
    }
  }

  Future<void> _showClearSingleTournamentDialog(String tournamentId, String tournamentName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Clear Tournament Data?', style: TextStyle(color: Colors.orange)),
        content: Text(
          'This will PERMANENTLY DELETE all data for "$tournamentName":\n\n'
          '• All registrations\n'
          '• All matches\n'
          '• All standings\n'
          '• Phase 1, Phase 2, and Knockout configurations\n\n'
          'The tournament itself will remain but will be reset.\n\n'
          'This action CANNOT be undone!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearSingleTournamentData(tournamentId, tournamentName);
    }
  }

  Future<void> _clearSingleTournamentData(String tournamentId, String tournamentName) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clearing tournament data...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final batch = FirebaseFirestore.instance.batch();

      // Delete all registrations for this tournament
      final registrations = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: tournamentId)
          .get();
      for (var reg in registrations.docs) {
        batch.delete(reg.reference);
      }

      // Delete all matches for this tournament
      final matches = await FirebaseFirestore.instance
          .collection('tournamentMatches')
          .where('tournamentId', isEqualTo: tournamentId)
          .get();
      for (var match in matches.docs) {
        batch.delete(match.reference);
      }

      // Delete standings subcollection (delete individually to avoid permission issues)
      final standings = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId)
          .collection('standings')
          .get();
      for (var standing in standings.docs) {
        await standing.reference.delete();
      }

      // Commit batch for registrations and matches
      await batch.commit();

      // Reset tournament configuration (clear phase1, phase2, knockout, but keep basic info)
      final tournamentRef = FirebaseFirestore.instance
          .collection('tournaments')
          .doc(tournamentId);
      
      await tournamentRef.update({
        'phase1': FieldValue.delete(),
        'phase2': FieldValue.delete(),
        'knockout': FieldValue.delete(),
        'status': 'upcoming',
        'isArchived': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "$tournamentName" data cleared successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error clearing tournament data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _clearAllTestData() async {
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clearing test data...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final batch = FirebaseFirestore.instance.batch();

      // Delete all tournament registrations
      final registrations = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .get();
      for (var reg in registrations.docs) {
        batch.delete(reg.reference);
      }

      // Delete all tournament matches
      final matches = await FirebaseFirestore.instance
          .collection('tournamentMatches')
          .get();
      for (var match in matches.docs) {
        batch.delete(match.reference);
      }

      // Delete all tournament standings (subcollections)
      final tournaments = await FirebaseFirestore.instance
          .collection('tournaments')
          .get();
      
      for (var tournament in tournaments.docs) {
        // Delete standings subcollection
        final standings = await tournament.reference
            .collection('standings')
            .get();
        for (var standing in standings.docs) {
          batch.delete(standing.reference);
        }
        
        // Delete the tournament itself
        batch.delete(tournament.reference);
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ All test data cleared successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error clearing test data: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // TOURNAMENT REQUESTS TAB
  static const List<String> _tournamentLevelOptions = [
    'C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women',
  ];

  Widget _buildTournamentRequestsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filters and view mode
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ToggleButtons(
                      isSelected: [
                        _tournamentRequestViewMode == 'pending',
                        _tournamentRequestViewMode == 'approved',
                      ],
                      onPressed: (index) => setState(() {
                        _tournamentRequestViewMode = index == 0 ? 'pending' : 'approved';
                      }),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pending, size: 20),
                              SizedBox(width: 8),
                              Text('Pending Requests'),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people, size: 20),
                              SizedBox(width: 8),
                              Text('Approved Players'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('tournaments')
                    .snapshots(),
                builder: (context, tournamentsSnapshot) {
                  final tournaments = tournamentsSnapshot.data?.docs ?? [];
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final useVertical = constraints.maxWidth < 500;
                      if (useVertical) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DropdownButtonFormField<String>(
                              value: _tournamentFilterId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Tournament',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('All tournaments')),
                                ...tournaments.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final name = data['name'] as String? ?? doc.id;
                                  return DropdownMenuItem(
                                    value: doc.id,
                                    child: Text(name, overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (v) => setState(() => _tournamentFilterId = v),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _tournamentFilterLevel,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Level / Group',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('All levels')),
                                ..._tournamentLevelOptions.map((l) => DropdownMenuItem(
                                  value: l,
                                  child: Text(l, overflow: TextOverflow.ellipsis),
                                )),
                              ],
                              onChanged: (v) => setState(() => _tournamentFilterLevel = v),
                            ),
                            if (_tournamentRequestViewMode == 'approved')
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading ? null : _exportApprovedPlayersToExcel,
                                  icon: const Icon(Icons.download, size: 20),
                                  label: const Text('Export to Excel'),
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                                ),
                              ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _tournamentFilterId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Tournament',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('All tournaments')),
                                ...tournaments.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final name = data['name'] as String? ?? doc.id;
                                  return DropdownMenuItem(
                                    value: doc.id,
                                    child: Text(name, overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (v) => setState(() => _tournamentFilterId = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _tournamentFilterLevel,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Level / Group',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('All levels')),
                                ..._tournamentLevelOptions.map((l) => DropdownMenuItem(
                                  value: l,
                                  child: Text(l, overflow: TextOverflow.ellipsis),
                                )),
                              ],
                              onChanged: (v) => setState(() => _tournamentFilterLevel = v),
                            ),
                          ),
                          if (_tournamentRequestViewMode == 'approved') ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _exportApprovedPlayersToExcel,
                              icon: const Icon(Icons.download, size: 20),
                              label: const Text('Export'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tournamentRegistrations')
                .where('status', isEqualTo: _tournamentRequestViewMode)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              var requests = snapshot.data?.docs ?? [];
              // Filter by tournament and level
              if (_tournamentFilterId != null) {
                requests = requests.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['tournamentId'] == _tournamentFilterId;
                }).toList();
              }
              if (_tournamentFilterLevel != null) {
                requests = requests.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['level'] == _tournamentFilterLevel;
                }).toList();
              }

              if (requests.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _tournamentRequestViewMode == 'pending'
                            ? Icons.check_circle
                            : Icons.people,
                        size: 64,
                        color: _tournamentRequestViewMode == 'pending' ? Colors.green : Colors.blue,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _tournamentRequestViewMode == 'pending'
                            ? 'No pending tournament requests'
                            : 'No approved players',
                        style: const TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              // Sort by timestamp client-side
              requests.sort((a, b) {
                final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                if (aTimestamp == null && bTimestamp == null) return 0;
                if (aTimestamp == null) return 1;
                if (bTimestamp == null) return -1;
                return bTimestamp.compareTo(aTimestamp);
              });

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;

            final tournamentId = data['tournamentId'] as String?;
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

                final isApproved = _tournamentRequestViewMode == 'approved';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  color: isApproved ? Colors.green[50] : Colors.orange[50],
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
                                color: isApproved ? Colors.green[200] : Colors.orange[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isApproved ? 'Approved' : 'Pending',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isApproved ? Colors.green[800] : Colors.orange[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (timestamp != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${isApproved ? "Registered" : "Requested"}: ${_formatTimestamp(timestamp)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (isApproved && tournamentId != null) ...[
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TournamentDashboardScreen(
                                        tournamentId: tournamentId,
                                        tournamentName: tournamentName,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('View Tournament'),
                              ),
                            ] else if (!isApproved) ...[
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
    ),
    ),
      ],
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
      final tournamentName = requestData['tournamentName'] as String? ?? 'Tournament';
      final partner = requestData['partner'] as Map<String, dynamic>?;

      await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .doc(requestId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // Create notification documents - onNotificationCreated sends FCM to both requester and partner
      final usersToNotify = <String>[userId];
      if (partner != null &&
          partner['partnerType'] == 'registered' &&
          partner['partnerId'] != null) {
        final partnerId = partner['partnerId'] as String?;
        if (partnerId != null &&
            partnerId.isNotEmpty &&
            !usersToNotify.contains(partnerId)) {
          usersToNotify.add(partnerId);
        }
      }

      for (final uid in usersToNotify) {
        if (uid.isEmpty) continue;
        try {
          await NotificationService().notifyUserForTournamentStatus(
            userId: uid,
            requestId: requestId,
            status: 'approved',
            tournamentName: tournamentName,
          );
        } catch (e) {
          debugPrint('Error notifying user $uid of tournament approval: $e');
        }
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

  Future<void> _exportApprovedPlayersToExcel() async {
    setState(() => _isLoading = true);
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('status', isEqualTo: 'approved')
          .get();

      var requests = snapshot.docs;
      if (_tournamentFilterId != null) {
        requests = requests.where((d) => d.data()['tournamentId'] == _tournamentFilterId).toList();
      }
      if (_tournamentFilterLevel != null) {
        requests = requests.where((d) => d.data()['level'] == _tournamentFilterLevel).toList();
      }

      if (requests.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No approved players to export'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      final tournaments = <String, String>{};
      for (final doc in requests) {
        final data = doc.data();
        final tournamentId = data['tournamentId'] as String?;
        if (tournamentId != null && !tournaments.containsKey(tournamentId)) {
          final tDoc = await FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).get();
          tournaments[tournamentId] = (tDoc.data()?['name'] ?? tournamentId) as String;
        }
      }

      String _escapeCsv(String s) {
        if (s.contains(',') || s.contains('"') || s.contains('\n')) {
          return '"${s.replaceAll('"', '""')}"';
        }
        return s;
      }

      final buffer = StringBuffer();
      buffer.writeln('Tournament,Player Name,Phone,Level,Partner Name,Partner Phone,Registered At');

      for (final doc in requests) {
        final data = doc.data();
        final tournamentId = data['tournamentId'] as String? ?? '';
        final tournamentName = tournaments[tournamentId] ?? tournamentId;
        String userName = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        if (userName.isEmpty) {
          final uid = data['userId'] as String? ?? '';
          if (uid.isNotEmpty) {
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
            final u = userDoc.data();
            userName = '${u?['firstName'] ?? ''} ${u?['lastName'] ?? ''}'.trim();
          }
        }
        if (userName.isEmpty) userName = 'Unknown';
        final phone = data['phone'] as String? ?? '';
        final level = data['level'] as String? ?? '';
        final partner = data['partner'] as Map<String, dynamic>?;
        final partnerName = partner?['partnerName'] as String? ?? '';
        final partnerPhone = partner?['partnerPhone'] as String? ?? '';
        final ts = data['approvedAt'] as dynamic;
        String regAt = '';
        if (ts != null && ts is Timestamp) {
          regAt = DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
        }
        buffer.writeln([
          _escapeCsv(tournamentName),
          _escapeCsv(userName),
          _escapeCsv(phone),
          _escapeCsv(level),
          _escapeCsv(partnerName),
          _escapeCsv(partnerPhone),
          _escapeCsv(regAt),
        ].join(','));
      }

      await Clipboard.setData(ClipboardData(text: buffer.toString()));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copied ${requests.length} players to clipboard. Paste into Excel or save as .csv'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    final latitudeController = TextEditingController();
    final longitudeController = TextEditingController();
    String selectedOpenTime = '8:00 AM';
    String selectedCloseTime = '12:00 AM';
    String selectedMidnightPlayEndTime = '4:00 AM'; // Default midnight play end (same cost as night up to this time)
    final priceController = TextEditingController(text: '200');
    final pricePerHourController = TextEditingController();
    String? selectedMorningEndTimeAdd;
    String selectedMorningStartTimeAdd = '6:00 AM'; // Morning rate starts at this time (admin-adjustable)
    final morningPricePer30ControllerAdd = TextEditingController();
    final morningPricePerHourControllerAdd = TextEditingController();
    final courtsController = TextEditingController(text: '1');
    File? selectedImage;
    XFile? selectedXFile; // For web compatibility
    Uint8List? selectedImageBytes; // For web display
    String? imageUrl;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Add New Location'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Location Logo Image Picker
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 70, // Compress to 70% quality to reduce file size
                        maxWidth: 800, // Resize to max 800px width
                        maxHeight: 800, // Resize to max 800px height
                      );
                      if (pickedFile != null) {
                        if (kIsWeb) {
                          // For web, read bytes first, then update state
                          final bytes = await pickedFile.readAsBytes();
                          setDialogState(() {
                            selectedXFile = pickedFile;
                            selectedImageBytes = bytes;
                            selectedImage = null; // Not used on web
                          });
                        } else {
                          // For mobile, use File
                          setDialogState(() {
                            selectedImage = File(pickedFile.path);
                            selectedXFile = null;
                            selectedImageBytes = null;
                          });
                        }
                      }
                    },
                    child: Container(
                      height: 120,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: (selectedImageBytes != null && kIsWeb)
                          ? Image.memory(selectedImageBytes!, fit: BoxFit.cover)
                          : (selectedImage != null && !kIsWeb)
                              ? Image.file(selectedImage!, fit: BoxFit.cover)
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    Text(
                                      imageUrl != null ? 'Change Logo' : 'Add Location Logo',
                                      style: const TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                    ),
                  ),
              const SizedBox(height: 16),
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
              TextField(
                controller: latitudeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Latitude (Optional)',
                  hintText: 'e.g., 30.0444',
                  border: OutlineInputBorder(),
                  helperText: 'Get from Google Maps for directions',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: longitudeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Longitude (Optional)',
                  hintText: 'e.g., 31.2357',
                  border: OutlineInputBorder(),
                  helperText: 'Get from Google Maps for directions',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String>(
                          value: selectedOpenTime,
                          decoration: const InputDecoration(
                            labelText: 'Open Time',
                            border: OutlineInputBorder(),
                          ),
                          items: _timeOptions.map((time) {
                            return DropdownMenuItem(
                              value: time,
                              child: Text(time),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedOpenTime = value ?? '8:00 AM';
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String>(
                          value: selectedCloseTime,
                          decoration: const InputDecoration(
                            labelText: 'Close Time',
                            border: OutlineInputBorder(),
                          ),
                          items: _timeOptions.map((time) {
                            return DropdownMenuItem(
                              value: time,
                              child: Text(time),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedCloseTime = value ?? '12:00 AM';
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              // Midnight Play End Time (only show if close time is 12:00 AM)
              if (selectedCloseTime == '12:00 AM') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatefulBuilder(
                        builder: (context, setDialogState) {
                          return DropdownButtonFormField<String>(
                            value: selectedMidnightPlayEndTime,
                            decoration: const InputDecoration(
                              labelText: 'Midnight Play End Time',
                              border: OutlineInputBorder(),
                              helperText: 'End time for midnight play (next day)',
                            ),
                            items: _midnightPlayEndOptions.map((time) {
                              return DropdownMenuItem(
                                value: time,
                                child: Text(time),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedMidnightPlayEndTime = value ?? '4:00 AM';
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
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
                controller: pricePerHourController,
                decoration: const InputDecoration(
                  labelText: 'Price per 1 hour (EGP)',
                  hintText: 'Optional – e.g. 350',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text('Morning rates (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String>(
                          value: selectedMorningStartTimeAdd,
                          decoration: const InputDecoration(
                            labelText: 'Morning starts at',
                            border: OutlineInputBorder(),
                            helperText: 'Morning rate applies from this time',
                          ),
                          items: _morningStartTimeOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedMorningStartTimeAdd = value ?? '6:00 AM';
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String?>(
                          value: selectedMorningEndTimeAdd,
                          decoration: const InputDecoration(
                            labelText: 'Morning ends at',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('No morning rate')),
                            ...List.generate(_timeOptions.length, (i) => DropdownMenuItem<String?>(value: _timeOptions[i], child: Text(_timeOptions[i]))),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedMorningEndTimeAdd = value;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: morningPricePer30ControllerAdd,
                      decoration: const InputDecoration(
                        labelText: 'Morning price/30 min (EGP)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: morningPricePerHourControllerAdd,
                      decoration: const InputDecoration(
                        labelText: 'Morning price/1h (EGP)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
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
                    // Upload image if selected
                    String? finalImageUrl = imageUrl;
                    if (kIsWeb && selectedXFile != null) {
                      // For web, upload from XFile
                      final uploadedUrl = await _uploadLocationImageFromXFile(selectedXFile!);
                      if (uploadedUrl != null) {
                        finalImageUrl = uploadedUrl;
                      }
                    } else if (!kIsWeb && selectedImage != null) {
                      // For mobile, upload from File
                      final uploadedUrl = await _uploadLocationImage(selectedImage!);
                      if (uploadedUrl != null) {
                        finalImageUrl = uploadedUrl;
                      }
                    }
                    
                    await _addCourtLocation(
                      nameController.text.trim(),
                      addressController.text.trim(),
                      double.tryParse(latitudeController.text),
                      double.tryParse(longitudeController.text),
                      selectedOpenTime,
                      selectedCloseTime,
                      selectedCloseTime == '12:00 AM' ? selectedMidnightPlayEndTime : null, // Only set if close time is midnight
                      double.tryParse(priceController.text) ?? 200.0,
                      int.tryParse(courtsController.text) ?? 1,
                      finalImageUrl,
                      pricePerHour: double.tryParse(pricePerHourController.text),
                      morningStartTime: selectedMorningStartTimeAdd,
                      morningEndTime: selectedMorningEndTimeAdd, // "Morning ends at" dropdown
                      morningPricePer30Min: double.tryParse(morningPricePer30ControllerAdd.text),
                      morningPricePerHour: double.tryParse(morningPricePerHourControllerAdd.text),
                    );
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditCourtLocationDialog(String locationId, Map<String, dynamic> data) async {
    final nameController = TextEditingController(text: data['name'] as String? ?? '');
    final addressController = TextEditingController(text: data['address'] as String? ?? '');
    final phoneController = TextEditingController(text: data['phoneNumber'] as String? ?? '');
    final mapsUrlController = TextEditingController(text: data['mapsUrl'] as String? ?? '');
    final backgroundImageUrlController = TextEditingController(text: data['backgroundImageUrl'] as String? ?? '');
    final latitudeController = TextEditingController(text: data['lat']?.toString() ?? '');
    final longitudeController = TextEditingController(text: data['lng']?.toString() ?? '');
    String selectedOpenTime = data['openTime'] as String? ?? '8:00 AM';
    String selectedCloseTime = data['closeTime'] as String? ?? '12:00 AM';
    String selectedMidnightPlayEndTime = data['midnightPlayEndTime'] as String? ?? '4:00 AM'; // Default to 4 AM (midnight play = night cost up to this time)
    final priceController = TextEditingController(text: (data['pricePer30Min'] as num?)?.toString() ?? '200');
    final pricePerHourController = TextEditingController(text: (data['pricePerHour'] as num?)?.toString() ?? '');
    String selectedMorningStartTime = data['morningStartTime'] as String? ?? '6:00 AM';
    String? selectedMorningEndTime = data['morningEndTime'] as String?;
    if (selectedMorningEndTime != null && selectedMorningEndTime.isEmpty) selectedMorningEndTime = null;
    final morningPricePer30Controller = TextEditingController(text: (data['morningPricePer30Min'] as num?)?.toString() ?? '');
    final morningPricePerHourController = TextEditingController(text: (data['morningPricePerHour'] as num?)?.toString() ?? '');
    final courts = (data['courts'] as List?) ?? [];
    final courtsController = TextEditingController(text: courts.length.toString());
    String? existingLogoUrl = data['logoUrl'] as String?;
    File? selectedImage;
    XFile? selectedXFile; // For web compatibility
    Uint8List? selectedImageBytes; // For web display
    String? imageUrl = existingLogoUrl;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Location'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Location Logo Image Picker
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 70, // Compress to 70% quality to reduce file size
                        maxWidth: 800, // Resize to max 800px width
                        maxHeight: 800, // Resize to max 800px height
                      );
                      if (pickedFile != null) {
                        if (kIsWeb) {
                          // For web, read bytes first, then update state
                          final bytes = await pickedFile.readAsBytes();
                          setDialogState(() {
                            selectedXFile = pickedFile;
                            selectedImageBytes = bytes;
                            selectedImage = null; // Not used on web
                          });
                        } else {
                          // For mobile, use File
                          setDialogState(() {
                            selectedImage = File(pickedFile.path);
                            selectedXFile = null;
                            selectedImageBytes = null;
                          });
                        }
                      }
                    },
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: (selectedImageBytes != null && kIsWeb)
                      ? Image.memory(selectedImageBytes!, fit: BoxFit.cover)
                      : (selectedImage != null && !kIsWeb)
                          ? Image.file(selectedImage!, fit: BoxFit.cover)
                          : (imageUrl != null && imageUrl!.isNotEmpty
                              ? _buildNetworkImage(
                                  imageUrl!,
                                  fit: BoxFit.cover,
                                  fallback: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Change Logo',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Change Logo',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                )),
                ),
              ),
              const SizedBox(height: 16),
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
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  hintText: '+20 XXX XXX XXXX',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: mapsUrlController,
                decoration: const InputDecoration(
                  labelText: 'Google Maps URL',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.map),
                  hintText: 'https://maps.google.com/...',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: backgroundImageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Background image URL or asset path (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.image),
                  hintText: 'https://... or images/venue.jpg (dimmed behind booking)',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latitudeController,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.my_location),
                        hintText: '30.0444',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: longitudeController,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                        hintText: '31.2357',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String>(
                          value: selectedOpenTime,
                          decoration: const InputDecoration(
                            labelText: 'Open Time',
                            border: OutlineInputBorder(),
                          ),
                          items: _timeOptions.map((time) {
                            return DropdownMenuItem(
                              value: time,
                              child: Text(time),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedOpenTime = value ?? '8:00 AM';
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String>(
                          value: selectedCloseTime,
                          decoration: const InputDecoration(
                            labelText: 'Close Time',
                            border: OutlineInputBorder(),
                          ),
                          items: _timeOptions.map((time) {
                            return DropdownMenuItem(
                              value: time,
                              child: Text(time),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedCloseTime = value ?? '12:00 AM';
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              // Midnight Play End Time (only show if close time is 12:00 AM)
              if (selectedCloseTime == '12:00 AM') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: StatefulBuilder(
                        builder: (context, setDialogState) {
                          return DropdownButtonFormField<String>(
                            value: selectedMidnightPlayEndTime,
                            decoration: const InputDecoration(
                              labelText: 'Midnight Play End Time',
                              border: OutlineInputBorder(),
                              helperText: 'End time for midnight play (next day)',
                            ),
                            items: _midnightPlayEndOptions.map((time) {
                              return DropdownMenuItem(
                                value: time,
                                child: Text(time),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setDialogState(() {
                                selectedMidnightPlayEndTime = value ?? '4:00 AM';
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
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
                controller: pricePerHourController,
                decoration: const InputDecoration(
                  labelText: 'Price per 1 hour (EGP)',
                  hintText: 'Optional – e.g. 350 (cheaper than 2×30 min)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text('Morning rates (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String>(
                          value: _morningStartTimeOptions.contains(selectedMorningStartTime) ? selectedMorningStartTime : '6:00 AM',
                          decoration: const InputDecoration(
                            labelText: 'Morning starts at',
                            border: OutlineInputBorder(),
                            helperText: 'Morning rate from this time',
                          ),
                          items: _morningStartTimeOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedMorningStartTime = value ?? '6:00 AM';
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return DropdownButtonFormField<String?>(
                          value: selectedMorningEndTime,
                          decoration: const InputDecoration(
                            labelText: 'Morning ends at',
                            border: OutlineInputBorder(),
                            helperText: 'Slots before this use morning price',
                          ),
                          items: [
                            DropdownMenuItem<String?>(value: null, child: Text('No morning rate')),
                            ...List.generate(_timeOptions.length, (i) => DropdownMenuItem<String?>(value: _timeOptions[i], child: Text(_timeOptions[i]))),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              selectedMorningEndTime = value;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: morningPricePer30Controller,
                      decoration: const InputDecoration(
                        labelText: 'Morning price/30 min (EGP)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: morningPricePerHourController,
                      decoration: const InputDecoration(
                        labelText: 'Morning price/1h (EGP)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
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
                    // Show loading indicator
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    
                    try {
                      // Upload image if selected
                      String? finalImageUrl = imageUrl; // Start with existing URL
                      
                      if (kIsWeb && selectedXFile != null) {
                        // For web, upload from XFile
                        debugPrint('Uploading image from XFile...');
                        final uploadedUrl = await _uploadLocationImageFromXFile(selectedXFile!);
                        if (uploadedUrl != null) {
                          finalImageUrl = uploadedUrl;
                          debugPrint('Image uploaded successfully: $uploadedUrl');
                          // Update dialog state to show the uploaded image
                          setDialogState(() {
                            imageUrl = uploadedUrl;
                            selectedImageBytes = null; // Clear local selection
                            selectedXFile = null; // Clear XFile
                          });
                        } else {
                          debugPrint('Image upload failed - URL is null');
                        }
                      } else if (!kIsWeb && selectedImage != null) {
                        // For mobile, upload from File
                        debugPrint('Uploading image from File...');
                        final uploadedUrl = await _uploadLocationImage(selectedImage!);
                        if (uploadedUrl != null) {
                          finalImageUrl = uploadedUrl;
                          debugPrint('Image uploaded successfully: $uploadedUrl');
                          // Update dialog state to show the uploaded image
                          setDialogState(() {
                            imageUrl = uploadedUrl;
                            selectedImage = null; // Clear local selection
                          });
                        } else {
                          debugPrint('Image upload failed - URL is null');
                        }
                      }
                      
                      debugPrint('Updating location with logoUrl: $finalImageUrl');
                      
                      // Show loading dialog
                      if (context.mounted) {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      
                      // Always pass the logoUrl (either new upload or existing)
                      await _updateCourtLocation(
                        locationId,
                        nameController.text.trim(),
                        addressController.text.trim(),
                        phoneController.text.trim(),
                        mapsUrlController.text.trim(),
                        double.tryParse(latitudeController.text),
                        double.tryParse(longitudeController.text),
                        selectedOpenTime,
                        selectedCloseTime,
                        selectedCloseTime == '12:00 AM' ? selectedMidnightPlayEndTime : null, // Only set if close time is midnight
                        double.tryParse(priceController.text) ?? 200.0,
                        int.tryParse(courtsController.text) ?? 1,
                        finalImageUrl, // Pass the URL (either new or existing)
                        pricePerHour: double.tryParse(pricePerHourController.text),
                        morningStartTime: selectedMorningStartTime,
                        morningEndTime: selectedMorningEndTime,
                        morningPricePer30Min: double.tryParse(morningPricePer30Controller.text),
                        morningPricePerHour: double.tryParse(morningPricePerHourController.text),
                        backgroundImageUrl: backgroundImageUrlController.text.trim().isEmpty ? null : backgroundImageUrlController.text.trim(),
                      );
                      
                      // Close loading dialog
                      if (context.mounted) {
                        Navigator.pop(context); // Close loading dialog
                        Navigator.pop(context); // Close edit dialog
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Location updated successfully'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('Error updating location: $e');
                      // Close loading dialog
                      if (context.mounted) {
                        Navigator.pop(context); // Close loading dialog
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error updating location: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
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
  }

  Future<void> _addCourtLocation(
    String name,
    String address,
    double? latitude,
    double? longitude,
    String openTime,
    String closeTime,
    String? midnightPlayEndTime,
    double pricePer30Min,
    int numberOfCourts,
    String? logoUrl, {
    double? pricePerHour,
    String? morningStartTime,
    String? morningEndTime,
    double? morningPricePer30Min,
    double? morningPricePerHour,
  }) async {
    try {
      final courts = List.generate(numberOfCourts, (index) => {
        'id': 'court_${index + 1}',
        'name': 'Court ${index + 1}',
      });

      final locationData = {
        'name': name,
        'address': address,
        'openTime': openTime,
        'closeTime': closeTime,
        'pricePer30Min': pricePer30Min,
        'courts': courts,
        'subAdmins': [], // Initialize empty sub-admins array
        'logoUrl': logoUrl, // Location logo URL
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      // Add latitude and longitude if provided (using 'lat' and 'lng' for consistency with booking code)
      if (latitude != null) locationData['lat'] = latitude;
      if (longitude != null) locationData['lng'] = longitude;
      
      // Only add midnightPlayEndTime if close time is 12:00 AM
      if (closeTime == '12:00 AM' && midnightPlayEndTime != null) {
        locationData['midnightPlayEndTime'] = midnightPlayEndTime;
      }

      if (pricePerHour != null && pricePerHour > 0) locationData['pricePerHour'] = pricePerHour;
      if (morningEndTime != null && morningEndTime.isNotEmpty) {
        if (morningStartTime != null && morningStartTime.isNotEmpty) locationData['morningStartTime'] = morningStartTime;
        locationData['morningEndTime'] = morningEndTime;
        if (morningPricePer30Min != null && morningPricePer30Min > 0) locationData['morningPricePer30Min'] = morningPricePer30Min;
        if (morningPricePerHour != null && morningPricePerHour > 0) locationData['morningPricePerHour'] = morningPricePerHour;
      }

      await FirebaseFirestore.instance.collection('courtLocations').add(locationData);

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
    String phoneNumber,
    String mapsUrl,
    double? latitude,
    double? longitude,
    String openTime,
    String closeTime,
    String? midnightPlayEndTime,
    double pricePer30Min,
    int numberOfCourts,
    String? logoUrl, {
    double? pricePerHour,
    String? morningStartTime,
    String? morningEndTime,
    double? morningPricePer30Min,
    double? morningPricePerHour,
    String? backgroundImageUrl,
  }) async {
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

      final updateData = {
        'name': name,
        'address': address,
        'phoneNumber': phoneNumber.isNotEmpty ? phoneNumber : null,
        'mapsUrl': mapsUrl.isNotEmpty ? mapsUrl : null,
        'lat': latitude, // Using 'lat' for consistency with booking code
        'lng': longitude, // Using 'lng' for consistency with booking code
        'openTime': openTime,
        'closeTime': closeTime,
        'pricePer30Min': pricePer30Min,
        'courts': courts,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Always update logoUrl if provided (either new upload or existing)
      // This ensures the logo is preserved or updated correctly
      // If logoUrl is null or empty, we don't update it (keeps existing or removes if needed)
      if (logoUrl != null && logoUrl.isNotEmpty) {
        updateData['logoUrl'] = logoUrl;
        debugPrint('Setting logoUrl in update: $logoUrl');
      } else {
        debugPrint('logoUrl is null or empty, not updating logo field');
      }
      if (backgroundImageUrl != null && backgroundImageUrl.isNotEmpty) {
        updateData['backgroundImageUrl'] = backgroundImageUrl;
      } else {
        updateData['backgroundImageUrl'] = FieldValue.delete();
      }

      // Only add midnightPlayEndTime if close time is 12:00 AM
      if (closeTime == '12:00 AM' && midnightPlayEndTime != null) {
        updateData['midnightPlayEndTime'] = midnightPlayEndTime;
      } else {
        // Remove midnightPlayEndTime if close time is not midnight
        updateData['midnightPlayEndTime'] = FieldValue.delete();
      }

      if (pricePerHour != null && pricePerHour > 0) {
        updateData['pricePerHour'] = pricePerHour;
      } else {
        updateData['pricePerHour'] = FieldValue.delete();
      }
      if (morningEndTime != null && morningEndTime.isNotEmpty) {
        if (morningStartTime != null && morningStartTime.isNotEmpty) {
          updateData['morningStartTime'] = morningStartTime;
        }
        updateData['morningEndTime'] = morningEndTime;
        if (morningPricePer30Min != null && morningPricePer30Min > 0) {
          updateData['morningPricePer30Min'] = morningPricePer30Min;
        } else {
          updateData['morningPricePer30Min'] = FieldValue.delete();
        }
        if (morningPricePerHour != null && morningPricePerHour > 0) {
          updateData['morningPricePerHour'] = morningPricePerHour;
        } else {
          updateData['morningPricePerHour'] = FieldValue.delete();
        }
      } else {
        updateData['morningEndTime'] = FieldValue.delete();
        updateData['morningStartTime'] = FieldValue.delete();
        updateData['morningPricePer30Min'] = FieldValue.delete();
        updateData['morningPricePerHour'] = FieldValue.delete();
      }
      
      await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(locationId)
          .update(updateData);

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
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.maxFinite,
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _addSubAdmin(locationId, searchController.text.trim());
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showSubAdminDialog(locationId, locationName, currentSubAdmins);
                        }
                      },
                      child: const Text('Add Sub-Admin'),
                    ),
                  ),
                  if (currentSubAdmins.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Current Sub-Admins:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...currentSubAdmins.map((adminId) => FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(adminId).get(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            title: Text(
                              adminId,
                              style: const TextStyle(fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
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
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          title: Text(
                            userName,
                            style: const TextStyle(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            userData?['phone'] as String? ?? '',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
      ),
    );
  }

  // Training Bundles Tab
  Widget _buildTrainingBundlesTab() {
    return Column(
      children: [
        Expanded(
          child: DefaultTabController(
            length: 4,
            child: Column(
              children: [
                const TabBar(
                  labelColor: Colors.blue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blue,
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Pending'),
                    Tab(text: 'Active'),
                    Tab(text: 'Completed'),
                    Tab(text: 'All'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildBundlesList('pending'),
                      _buildBundlesList('active'),
                      _buildBundlesList('completed'),
                      _buildBundlesList('all'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openAdminAddBundle(context),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add bundle for user (on behalf of)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openAdminAddBundle(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AdminAddBundleScreen(),
      ),
    );
  }

  Widget _buildBundlesList(String filter) {
    final bundleService = BundleService();
    
    return StreamBuilder<List<TrainingBundle>>(
      stream: bundleService.getAllBundles(statusFilter: filter == 'all' ? null : filter),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final bundles = snapshot.data ?? [];

        if (bundles.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.card_membership_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No $filter bundles',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bundles.length,
          itemBuilder: (context, index) {
            final bundle = bundles[index];
            return _buildBundleCard(bundle);
          },
        );
      },
    );
  }

  Widget _buildBundleCard(TrainingBundle bundle) {
    final progress = bundle.totalSessions > 0
        ? bundle.usedSessions / bundle.totalSessions
        : 0.0;

    Color statusColor;
    switch (bundle.status) {
      case 'active':
        statusColor = Colors.green;
        break;
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'completed':
        statusColor = Colors.blue;
        break;
      case 'expired':
        statusColor = Colors.red;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Text(
            '${bundle.bundleType}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ),
        title: Text(
          bundle.userName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${bundle.bundleType} Sessions - ${bundle.playerCount} Player${bundle.playerCount > 1 ? 's' : ''}'),
            Text('${bundle.remainingSessions} remaining • ${bundle.price.toStringAsFixed(0)} EGP'),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor),
              ),
              child: Text(
                bundle.statusDisplay,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress bar
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progress: ${bundle.usedSessions}/${bundle.totalSessions}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${(progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 10,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        'Attended',
                        bundle.attendedSessions.toString(),
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        'Missed',
                        bundle.missedSessions.toString(),
                        Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        'Cancelled',
                        bundle.cancelledSessions.toString(),
                        Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Details
                _buildDetailRow('Phone', bundle.userPhone),
                _buildDetailRow('Payment Status', bundle.paymentStatusDisplay),
                if (bundle.paymentDate != null)
                  _buildDetailRow('Payment Date', DateFormat('MMM dd, yyyy').format(bundle.paymentDate!)),
                if (bundle.approvalDate != null)
                  _buildDetailRow('Approved On', DateFormat('MMM dd, yyyy').format(bundle.approvalDate!)),
                if (bundle.expirationDate != null)
                  _buildDetailRow('Expires On', DateFormat('MMM dd, yyyy').format(bundle.expirationDate!)),
                if (bundle.notes.isNotEmpty)
                  _buildDetailRow('User Notes', bundle.notes),
                if (bundle.adminNotes.isNotEmpty)
                  _buildDetailRow('Admin Notes', bundle.adminNotes),
                
                const SizedBox(height: 16),

                // Action buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (bundle.status == 'pending')
                      ElevatedButton.icon(
                        onPressed: () => _approveBundle(bundle),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    if (bundle.status == 'active' && bundle.paymentStatus != 'paid')
                      ElevatedButton.icon(
                        onPressed: () => _confirmBundlePayment(bundle),
                        icon: const Icon(Icons.payment, size: 16),
                        label: const Text('Confirm Payment'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    if (bundle.status == 'active')
                      OutlinedButton.icon(
                        onPressed: () => _viewBundleSessions(bundle),
                        icon: const Icon(Icons.list, size: 16),
                        label: const Text('View Sessions'),
                      ),
                    if (bundle.status == 'active')
                      OutlinedButton.icon(
                        onPressed: () => _extendBundle(bundle),
                        icon: const Icon(Icons.update, size: 16),
                        label: const Text('Extend'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _addAdminNotes(bundle),
                      icon: const Icon(Icons.note_add, size: 16),
                      label: const Text('Add Notes'),
                    ),
                    if (bundle.status == 'pending' || bundle.status == 'active')
                      OutlinedButton.icon(
                        onPressed: () => _cancelBundle(bundle),
                        icon: const Icon(Icons.cancel, size: 16),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveBundle(TrainingBundle bundle) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Bundle'),
        content: Text('Approve training bundle for ${bundle.userName}?\n\nBundle will be valid for 2 months.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await BundleService().approveBundle(bundle.id, user.uid);
          
          // Auto-generate all sessions based on schedule
          await _generateBundleSessions(bundle);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bundle approved and sessions created successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error approving bundle: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmBundlePayment(TrainingBundle bundle) async {
    DateTime selectedDate = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Confirm Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Confirm payment for ${bundle.userName}?'),
                const SizedBox(height: 16),
                Text('Amount: ${bundle.price.toStringAsFixed(0)} EGP'),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('Payment Date'),
                  subtitle: Text(DateFormat('MMM dd, yyyy').format(selectedDate)),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await BundleService().confirmPayment(bundle.id, user.uid, selectedDate);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment confirmed successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error confirming payment: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _viewBundleSessions(TrainingBundle bundle) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StreamBuilder<List<BundleSession>>(
            stream: BundleService().getBundleSessions(bundle.id),
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? [];

              return SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Bundle Sessions - ${bundle.userName}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (sessions.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No sessions booked yet'),
                          ),
                        )
                      else
                        ...sessions.map((session) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text('${session.sessionNumber}'),
                            ),
                            title: Text('${session.venue} - ${session.coach}'),
                            subtitle: Text('${session.date} at ${session.time}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      session.attendanceStatus.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _getAttendanceColor(session.attendanceStatus),
                                      ),
                                    ),
                                    if (session.attendanceStatus == 'scheduled')
                                      TextButton(
                                        onPressed: () => _markAttendance(session, bundle.id),
                                        child: const Text('Mark', style: TextStyle(fontSize: 10)),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: () => _rescheduleSession(session, bundle.id),
                                  tooltip: 'Reschedule',
                                ),
                              ],
                            ),
                          ),
                        )),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getAttendanceColor(String status) {
    switch (status) {
      case 'attended':
        return Colors.green;
      case 'missed':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  Future<void> _markAttendance(BundleSession session, String bundleId) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Attendance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Attended'),
              onTap: () => Navigator.pop(context, 'attended'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('Missed'),
              onTap: () => Navigator.pop(context, 'missed'),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.grey),
              title: const Text('Cancelled'),
              onTap: () => Navigator.pop(context, 'cancelled'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await BundleService().markAttendance(
            sessionId: session.id,
            attendanceStatus: result,
            markedBy: user.uid,
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Attendance marked successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error marking attendance: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _extendBundle(TrainingBundle bundle) async {
    DateTime? newDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Extend Bundle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Extend bundle expiration date'),
                const SizedBox(height: 16),
                if (bundle.expirationDate != null)
                  Text('Current expiration: ${DateFormat('MMM dd, yyyy').format(bundle.expirationDate!)}'),
                const SizedBox(height: 16),
                ListTile(
                  title: const Text('New Expiration Date'),
                  subtitle: Text(newDate != null ? DateFormat('MMM dd, yyyy').format(newDate!) : 'Select date'),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: bundle.expirationDate ?? DateTime.now().add(const Duration(days: 60)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() {
                          newDate = picked;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: newDate != null ? () => Navigator.pop(context, true) : null,
                child: const Text('Extend'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && newDate != null) {
      try {
        await BundleService().extendBundle(bundle.id, newDate!);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bundle extended successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error extending bundle: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _addAdminNotes(TrainingBundle bundle) async {
    final controller = TextEditingController(text: bundle.adminNotes);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Notes'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Add notes about this bundle...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('bundles')
            .doc(bundle.id)
            .update({
          'adminNotes': controller.text,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notes saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving notes: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _cancelBundle(TrainingBundle bundle) async {
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Bundle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to cancel this bundle?'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await BundleService().cancelBundle(bundle.id, controller.text);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bundle cancelled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error cancelling bundle: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _rescheduleSession(BundleSession session, String bundleId) async {
    final dateController = TextEditingController(text: session.date);
    final timeController = TextEditingController(text: session.time);
    final venueController = TextEditingController(text: session.venue);
    final coachController = TextEditingController(text: session.coach);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reschedule Session ${session.sessionNumber}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date (YYYY-MM-DD)',
                  hintText: '2026-02-06',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: timeController,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  hintText: '1:00 PM - 2:00 PM',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: venueController,
                decoration: const InputDecoration(
                  labelText: 'Venue',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: coachController,
                decoration: const InputDecoration(
                  labelText: 'Coach',
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
            onPressed: () {
              Navigator.pop(context, {
                'date': dateController.text,
                'time': timeController.text,
                'venue': venueController.text,
                'coach': coachController.text,
              });
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await FirebaseFirestore.instance
            .collection('bundleSessions')
            .doc(session.id)
            .update({
          'date': result['date'],
          'time': result['time'],
          'venue': result['venue'],
          'coach': result['coach'],
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session rescheduled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error rescheduling session: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _generateBundleSessions(TrainingBundle bundle) async {
    try {
      // Get schedule details from bundle
      final scheduleDetails = bundle.scheduleDetails ?? {};
      final dayTimeSchedule = scheduleDetails['dayTimeSchedule'] as Map<String, dynamic>? ?? {};
      final venue = scheduleDetails['venue'] as String? ?? '';
      final coach = scheduleDetails['coach'] as String? ?? '';
      final startDateStr = scheduleDetails['startDate'] as String? ?? '';
      
      if (dayTimeSchedule.isEmpty || venue.isEmpty) {
        debugPrint('No schedule details found, skipping session generation');
        return;
      }

      // Parse start date
      DateTime startDate = DateTime.now();
      if (startDateStr.isNotEmpty) {
        try {
          final parts = startDateStr.split('/');
          if (parts.length == 3) {
            startDate = DateTime(
              int.parse(parts[2]), // year
              int.parse(parts[1]), // month
              int.parse(parts[0]), // day
            );
          }
        } catch (e) {
          debugPrint('Error parsing start date: $e');
        }
      }

      // Convert dayTimeSchedule to Map<String, String>
      final Map<String, String> schedule = {};
      dayTimeSchedule.forEach((key, value) {
        schedule[key.toString()] = value.toString();
      });

      // Generate session dates based on recurring schedule
      final List<Map<String, dynamic>> sessions = [];
      final daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      
      int sessionNumber = 1;
      DateTime currentDate = startDate;
      int weeksSearched = 0;
      final maxWeeksToSearch = 20; // Search up to 20 weeks

      while (sessionNumber <= bundle.totalSessions && weeksSearched < maxWeeksToSearch) {
        final dayName = daysOfWeek[currentDate.weekday - 1];
        
        // Check if this day is in the schedule
        if (schedule.containsKey(dayName)) {
          final time = schedule[dayName]!;
          sessions.add({
            'sessionNumber': sessionNumber,
            'date': currentDate,
            'dateStr': '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}',
            'time': time,
            'day': dayName,
          });
          sessionNumber++;
        }
        
        currentDate = currentDate.add(const Duration(days: 1));
        
        // Track weeks searched
        if (currentDate.weekday == 1) { // Monday
          weeksSearched++;
        }
      }

      // Create bundle session records
      for (var session in sessions) {
        await BundleService().createBundleSession(
          bundleId: bundle.id,
          userId: bundle.userId,
          sessionNumber: session['sessionNumber'],
          date: session['dateStr'],
          time: session['time'],
          venue: venue,
          coach: coach,
          playerCount: bundle.playerCount,
          bookingId: '', // No booking ID for auto-generated sessions
          bookingStatus: 'approved', // Auto-generated sessions are pre-approved
        );
      }

      debugPrint('Generated ${sessions.length} sessions for bundle ${bundle.id}');
    } catch (e) {
      debugPrint('Error generating bundle sessions: $e');
    }
  }
}
