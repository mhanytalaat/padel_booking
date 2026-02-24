import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'required_profile_update_screen.dart';
import '../services/notification_service.dart';
import '../services/profile_completion_service.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class TournamentJoinScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;
  final String? tournamentImageUrl;

  const TournamentJoinScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
    this.tournamentImageUrl,
  });

  @override
  State<TournamentJoinScreen> createState() => _TournamentJoinScreenState();
}

class _TournamentJoinScreenState extends State<TournamentJoinScreen> {
  Set<String> _selectedLevels = {};
  Set<String> _alreadyRegisteredLevels = {}; // Levels user is already registered for
  Set<String> _levelsWhereUserIsPartner = {}; // Levels where someone else selected this user as partner
  bool _isSubmitting = false;
  List<String> _levels = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  // Per-level partner: 'registered'|'new', partnerId, partnerName, partnerPhone
  Map<String, Map<String, dynamic>> _partnersByLevel = {};
  Map<String, TextEditingController> _partnerNameControllers = {};
  Map<String, TextEditingController> _partnerPhoneControllers = {};
  Map<String, bool> _addNewPartnerByLevel = {};
  List<Map<String, dynamic>> _registeredUsers = [];
  bool _loadingUsers = false;
  bool _loadingProfile = true;
  /// Partner IDs already selected by others for this tournament (per level).
  /// Used to exclude them from the partner picker so no double-booking.
  Map<String, Set<String>> _takenPartnerIdsByLevel = {};
  
  // Admin credentials to filter out
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com';

  // Helper method to build asset image with proper path handling
  Widget _buildAssetImage(String imagePath, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (imagePath.isEmpty) {
      return Container(
        width: width ?? double.infinity,
        height: height ?? 200,
        color: const Color(0xFF1E3A8A),
        child: const Icon(
          Icons.emoji_events,
          size: 64,
          color: Colors.white,
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
      width: width ?? double.infinity,
      height: height ?? 200,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Failed to load asset image: $normalizedPath');
        debugPrint('Original path: $imagePath');
        debugPrint('Error: $error');
        return Container(
          width: width ?? double.infinity,
          height: height ?? 200,
          color: const Color(0xFF1E3A8A),
          child: const Icon(
            Icons.emoji_events,
            size: 64,
            color: Colors.white,
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUserProfileAndTournamentLevels();
    _loadRegisteredUsers();
    _loadTakenPartners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requireServiceProfile());
  }

  /// Redirect to profile completion if required for joining tournaments (Apple guideline).
  Future<void> _requireServiceProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final needs = await ProfileCompletionService.needsServiceProfileCompletion(user);
    if (needs && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RequiredProfileUpdateScreen()),
      );
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    for (final c in _partnerNameControllers.values) {
      c.dispose();
    }
    for (final c in _partnerPhoneControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensurePartnerControllersForLevel(String level) {
    _partnerNameControllers.putIfAbsent(level, () => TextEditingController());
    _partnerPhoneControllers.putIfAbsent(level, () => TextEditingController());
  }

  void _removePartnerForLevel(String level) {
    _selectedLevels.remove(level);
    _partnersByLevel.remove(level);
    _addNewPartnerByLevel.remove(level);
    _partnerNameControllers[level]?.clear();
    _partnerPhoneControllers[level]?.clear();
  }

  Future<void> _loadUserProfileAndTournamentLevels() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final results = await Future.wait([
          FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).get(),
        ]);
        final userDoc = results[0] as DocumentSnapshot;
        final tournamentDoc = results[1] as DocumentSnapshot;
        if (mounted) {
          if (userDoc.exists) {
            final data = userDoc.data() as Map<String, dynamic>;
            _firstNameController.text = data['firstName'] as String? ?? '';
            _lastNameController.text = data['lastName'] as String? ?? '';
            _emailController.text = data['email'] as String? ?? user.email ?? '';
            _phoneController.text = data['phone'] as String? ?? user.phoneNumber ?? '';
          } else {
            _emailController.text = user.email ?? '';
            _phoneController.text = user.phoneNumber ?? '';
          }
          if (tournamentDoc.exists) {
            final data = tournamentDoc.data() as Map<String, dynamic>?;
            final skillLevelData = data?['skillLevel'];
            List<String> tournamentLevels = skillLevelData is List
                ? (skillLevelData as List).map((e) => e.toString()).toList()
                : (skillLevelData != null ? [skillLevelData.toString()] : []);
            // Normalize legacy 'Beginner' to 'Beginners'
            tournamentLevels = tournamentLevels.map((l) => l == 'Beginner' ? 'Beginners' : l).toList();
            const allLevels = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];
            _levels = tournamentLevels.isNotEmpty
                ? tournamentLevels.where((l) => allLevels.contains(l)).toList()
                : allLevels;
          }
          setState(() {
            _loadingProfile = false;
          });
          _loadExistingRegistrations();
        }
      } catch (e) {
        debugPrint('Error loading profile/tournament: $e');
        if (mounted) {
          setState(() {
            _emailController.text = user.email ?? '';
            _phoneController.text = user.phoneNumber ?? '';
            _loadingProfile = false;
          });
        }
      }
    } else {
      setState(() {
        _loadingProfile = false;
      });
    }
  }

  Future<void> _loadExistingRegistrations() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('userId', isEqualTo: user.uid)
          .get();
      if (mounted) {
        setState(() {
          _alreadyRegisteredLevels = snapshot.docs
              .where((d) {
                final status = (d.data()['status'] as String? ?? '').toString();
                return status == 'pending' || status == 'approved';
              })
              .map((d) => (d.data()['level'] as String? ?? '').toString())
              .where((l) => l.isNotEmpty)
              .toSet();
        });
      }
    } catch (e) {
      debugPrint('Error loading existing registrations: $e');
    }
  }

  /// Load partner IDs already selected by others for this tournament (per level).
  /// Those users cannot be selected again as partners for the same level.
  /// Also sets _levelsWhereUserIsPartner so we block the current user from joining those levels.
  Future<void> _loadTakenPartners() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', whereIn: ['pending', 'approved'])
          .get();

      final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
      final levelsWhereTaken = <String>{};

      final byLevel = <String, Set<String>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final level = data['level'] as String? ?? '';
        if (level.isEmpty) continue;
        final partner = data['partner'] as Map<String, dynamic>?;
        if (partner == null) continue;
        if (partner['partnerType'] != 'registered') continue;
        final partnerId = partner['partnerId'] as String?;
        if (partnerId == null || partnerId.isEmpty) continue;
        byLevel.putIfAbsent(level, () => {}).add(partnerId);
        if (partnerId == currentUserId) {
          levelsWhereTaken.add(level);
        }
      }
      if (mounted) {
        setState(() {
          _takenPartnerIdsByLevel = byLevel;
          _levelsWhereUserIsPartner = levelsWhereTaken;
        });
      }
    } catch (e) {
      debugPrint('Error loading taken partners: $e');
    }
  }

  Future<void> _loadRegisteredUsers() async {
    setState(() {
      _loadingUsers = true;
    });

    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      final currentUser = FirebaseAuth.instance.currentUser;
      
      setState(() {
        _registeredUsers = usersSnapshot.docs
            .where((doc) {
              // Exclude current user
              if (doc.id == currentUser?.uid) return false;
              
              final data = doc.data();
              final phone = data['phone'] as String? ?? '';
              final email = data['email'] as String? ?? '';
              final firstName = data['firstName'] as String? ?? '';
              final lastName = data['lastName'] as String? ?? '';
              
              // Exclude admin account
              if (phone == adminPhone || email == adminEmail) return false;
              
              // Exclude test accounts (check if name contains "test" case-insensitive)
              final fullName = '$firstName $lastName'.toLowerCase();
              if (fullName.contains('test')) return false;
              
              return true;
            })
            .map((doc) {
              final data = doc.data();
              final firstName = data['firstName'] as String? ?? '';
              final lastName = data['lastName'] as String? ?? '';
              final fullName = data['fullName'] as String? ?? 
                  '$firstName $lastName'.trim();
              // Create unique ID from first 4 characters of user ID
              final uniqueId = doc.id.length >= 4 ? doc.id.substring(0, 4).toUpperCase() : doc.id.toUpperCase();
              
              return {
                'id': doc.id,
                'firstName': firstName,
                'lastName': lastName,
                'phone': data['phone'] as String? ?? '',
                'fullName': fullName,
                'uniqueId': uniqueId,
                'displayName': fullName.isNotEmpty ? '$fullName (#$uniqueId)' : 'Unknown User',
              };
            })
            .where((user) => user['fullName'].toString().isNotEmpty)
            .toList()
          ..sort((a, b) => 
              (a['fullName'] as String).compareTo(b['fullName'] as String));
        _loadingUsers = false;
      });
    } catch (e) {
      setState(() {
        _loadingUsers = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<bool?> _showRulesAcceptanceDialog() async {
    try {
      // Get tournament rules
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      final tournamentData = tournamentDoc.data();
      final rules = tournamentData?['rules'] as Map<String, dynamic>?;
      final rulesText = rules?['text'] as String?;

      // If no rules, auto-accept
      if (rulesText == null || rulesText.isEmpty) {
        return true;
      }

      // Show rules dialog
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.rule, color: Colors.orange),
              SizedBox(width: 8),
              Text('Tournament Rules'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Text(
                      'Please read and accept the tournament rules before registering.',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    rulesText,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Decline'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Accept & Continue'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error loading rules: $e');
      return true; // Auto-accept if error
    }
  }

  Future<void> _submitJoinRequest() async {
    if (_firstNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your first name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your phone number'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedLevels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one skill level'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Filter to only levels not already registered
    final levelsToRegister = _selectedLevels
        .where((l) => !_alreadyRegisteredLevels.contains(l))
        .toList();
    if (levelsToRegister.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All selected levels are already registered'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate partner for each selected level
    for (final level in levelsToRegister) {
      final partner = _partnersByLevel[level];
      final addNew = _addNewPartnerByLevel[level] ?? false;
      if (addNew) {
        final name = _partnerNameControllers[level]?.text.trim() ?? '';
        final phone = _partnerPhoneControllers[level]?.text.trim() ?? '';
        if (name.isEmpty || phone.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please enter partner name and phone for $level'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      } else {
        if (partner == null || partner['partnerId'] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please select or add a partner for $level'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to join a tournament'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check for rules and show acceptance dialog
    final rulesAccepted = await _showRulesAcceptanceDialog();
    if (rulesAccepted != true) {
      return; // User didn't accept rules
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final phone = _phoneController.text.trim();
      final userName = '$firstName $lastName'.trim().isEmpty
          ? (user.phoneNumber ?? 'User')
          : '$firstName $lastName';

      for (final level in levelsToRegister) {
        Map<String, dynamic> partnerData = {};
        final addNew = _addNewPartnerByLevel[level] ?? false;
        if (addNew) {
          partnerData = {
            'partnerType': 'new',
            'partnerName': _partnerNameControllers[level]!.text.trim(),
            'partnerPhone': _partnerPhoneControllers[level]!.text.trim(),
          };
        } else {
          final partner = _partnersByLevel[level]!;
          final selectedPartner = _registeredUsers.firstWhere(
            (u) => u['id'] == partner['partnerId'],
          );
          partnerData = {
            'partnerType': 'registered',
            'partnerId': partner['partnerId'],
            'partnerName': selectedPartner['fullName'],
            'partnerPhone': selectedPartner['phone'],
          };
        }

        final requestRef = await FirebaseFirestore.instance
            .collection('tournamentRegistrations')
            .add({
          'tournamentId': widget.tournamentId,
          'tournamentName': widget.tournamentName,
          'userId': user.uid,
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
          'level': level,
          'partner': partnerData,
          'status': 'pending',
          'rulesAccepted': true,
          'timestamp': FieldValue.serverTimestamp(),
        });

        await NotificationService().notifyAdminForTournamentRequest(
          requestId: requestRef.id,
          userId: user.uid,
          userName: userName,
          phone: phone,
          tournamentName: widget.tournamentName,
          level: level,
        );

        if (partnerData['partnerType'] == 'registered' && partnerData['partnerId'] != null) {
          try {
            await FirebaseFirestore.instance.collection('notifications').add({
              'userId': partnerData['partnerId'],
              'type': 'tournament_partner_request',
              'title': '🎾 Tournament Partner Request',
              'body': '$userName requested you to join ${widget.tournamentName} together at level $level',
              'read': false,
              'timestamp': FieldValue.serverTimestamp(),
              'tournamentId': widget.tournamentId,
              'tournamentName': widget.tournamentName,
              'requesterId': user.uid,
              'requesterName': userName,
              'level': level,
            });
          } catch (e) {
            debugPrint('Error sending partner notification: $e');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              levelsToRegister.length == 1
                  ? 'Tournament join request submitted! Waiting for admin approval.'
                  : '${levelsToRegister.length} registration requests submitted! Waiting for admin approval.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppHeader(title: widget.tournamentName),
      bottomNavigationBar: const AppFooter(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
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
                  if (widget.tournamentImageUrl != null && widget.tournamentImageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: widget.tournamentImageUrl!.startsWith('http')
                          ? Image.network(
                              widget.tournamentImageUrl!,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.emoji_events,
                                  size: 64,
                                  color: Color(0xFF1E3A8A),
                                );
                              },
                            )
                          : _buildAssetImage(widget.tournamentImageUrl!),
                    )
                  else
                    const Icon(
                      Icons.emoji_events,
                      size: 64,
                      color: Color(0xFF1E3A8A),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    widget.tournamentName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Your Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Pre-filled from your profile. You can edit if needed.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 16),
            if (_loadingProfile)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'First Name *',
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                        hintText: 'Your first name',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        prefixIcon: Icon(Icons.person, color: Colors.white.withOpacity(0.7)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1A1F3A),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                        hintText: 'Your last name',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1A1F3A),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  hintText: 'your@email.com',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.email, color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1A1F3A),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Phone Number *',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  hintText: '+201234567890',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.phone, color: Colors.white.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1A1F3A),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
            const SizedBox(height: 32),
            const Text(
              'Select Your Skill Level(s)',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You can join multiple levels. Each level requires a partner. Already registered levels cannot be selected again.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 24),
            ..._levels.map((level) {
              final isAlreadyRegistered = _alreadyRegisteredLevels.contains(level);
              final isTakenAsPartner = _levelsWhereUserIsPartner.contains(level);
              final isDisabled = isAlreadyRegistered || isTakenAsPartner;
              final isSelected = _selectedLevels.contains(level);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1E3A8A).withOpacity(0.2)
                        : isDisabled
                            ? Colors.grey.withOpacity(0.2)
                            : const Color(0xFF1A1F3A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDisabled
                          ? Colors.grey
                          : isSelected
                              ? const Color(0xFF3B82F6)
                              : Colors.white.withOpacity(0.1),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CheckboxListTile(
                        value: isSelected,
                        title: Text(
                          level,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: isDisabled ? Colors.grey : Colors.white,
                          ),
                        ),
                        subtitle: isAlreadyRegistered
                            ? Text(
                                'Already registered (contact admin to remove)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              )
                            : isTakenAsPartner
                                ? Text(
                                    'Already selected as partner by another player',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[300],
                                    ),
                                  )
                                : _getLevelDescription(level),
                        onChanged: isDisabled
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedLevels.add(level);
                                    _ensurePartnerControllersForLevel(level);
                                    _addNewPartnerByLevel[level] = false;
                                  } else {
                                    _removePartnerForLevel(level);
                                  }
                                });
                              },
                        activeColor: const Color(0xFF3B82F6),
                        tileColor: Colors.transparent,
                      ),
                      if (isSelected && !isDisabled) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1F3A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Partner for $level',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ChoiceChip(
                                        label: const Text('Registered Partner'),
                                        selected: !(_addNewPartnerByLevel[level] ?? false),
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _addNewPartnerByLevel[level] = false;
                                              _partnersByLevel.remove(level);
                                              _partnerNameControllers[level]?.clear();
                                              _partnerPhoneControllers[level]?.clear();
                                              if (_registeredUsers.isEmpty) {
                                                _loadRegisteredUsers();
                                              }
                                            }
                                          });
                                        },
                                        selectedColor: const Color(0xFF1E3A8A),
                                        labelStyle: TextStyle(
                                          color: !(_addNewPartnerByLevel[level] ?? false)
                                              ? Colors.white
                                              : Colors.black,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ChoiceChip(
                                        label: const Text('Add New'),
                                        selected: _addNewPartnerByLevel[level] ?? false,
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _addNewPartnerByLevel[level] = true;
                                              _partnersByLevel.remove(level);
                                            }
                                          });
                                        },
                                        selectedColor: const Color(0xFF1E3A8A),
                                        labelStyle: TextStyle(
                                          color: (_addNewPartnerByLevel[level] ?? false)
                                              ? Colors.white
                                              : Colors.black,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_addNewPartnerByLevel[level] ?? false) ...[
                                  TextFormField(
                                    controller: _partnerNameControllers[level],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Partner Name *',
                                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      hintText: 'Enter partner full name',
                                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                      prefixIcon: Icon(Icons.person, color: Colors.white.withOpacity(0.7)),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFF1A1F3A),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    textCapitalization: TextCapitalization.words,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _partnerPhoneControllers[level],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Partner Phone *',
                                      labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                      hintText: '+201234567890',
                                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                      prefixIcon: Icon(Icons.phone, color: Colors.white.withOpacity(0.7)),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      filled: true,
                                      fillColor: const Color(0xFF1A1F3A),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    keyboardType: TextInputType.phone,
                                  ),
                                ] else ...[
                                  if (_loadingUsers)
                                    const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
                                  else if (_registeredUsers.isEmpty)
                                    TextButton.icon(
                                      onPressed: _loadRegisteredUsers,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Load users'),
                                    )
                                  else
                                    _buildPartnerAutocomplete(level),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitJoinRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Join Tournament',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerAutocomplete(String level) {
    final partner = _partnersByLevel[level];
    final selectedId = partner?['partnerId'] as String?;
    return Autocomplete<Map<String, dynamic>>(
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Search partner by name',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
            hintText: 'Type to search...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.7)),
            suffixIcon: selectedId != null
                ? IconButton(
                    icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.7)),
                    onPressed: () {
                      setState(() {
                        _partnersByLevel.remove(level);
                        textEditingController.clear();
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
            ),
            filled: true,
            fillColor: const Color(0xFF1A1F3A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        );
      },
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<Map<String, dynamic>>.empty();
        }
        final taken = _takenPartnerIdsByLevel[level] ?? {};
        final query = textEditingValue.text.toLowerCase();
        return _registeredUsers.where((u) {
          if (taken.contains(u['id'] as String?)) return false;
          final fullName = (u['fullName'] as String).toLowerCase();
          final displayName = (u['displayName'] as String).toLowerCase();
          return fullName.contains(query) || displayName.contains(query);
        });
      },
      displayStringForOption: (option) => option['displayName'] as String,
      onSelected: (option) {
        setState(() {
          _partnersByLevel[level] = {
            'partnerId': option['id'],
            'partnerName': option['fullName'],
          };
        });
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    tileColor: const Color(0xFF1A1F3A),
                    title: Text(
                      option['displayName'] as String,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _getLevelDescription(String level) {
    switch (level) {
      case 'C+':
        return Text(
          'Advanced level, Competitive player',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      case 'C-':
        return Text(
          'Intermediate level, consistent play',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      case 'D':
        return Text(
          'Basic skills, learning fundamentals',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      case 'Beginners':
        return Text(
          'Just starting out with padel',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      case 'Seniors':
        return Text(
          'Tournament for senior players',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      case 'Mix Doubles':
        return Text(
          'Mixed gender doubles tournament',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      case 'Mix/Family Doubles':
        return Text(
          'Mixed or family doubles tournament',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      case 'Women':
        return Text(
          'Tournament for women players',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        );
      default:
        return null;
    }
  }
}
