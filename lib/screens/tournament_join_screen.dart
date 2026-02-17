import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
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
  String? _selectedLevel;
  String? _selectedPartnerId; // Selected registered user as partner
  String? _selectedPartnerName; // Selected partner name for display
  bool _isSubmitting = false;
  bool _addNewPartner = false; // Toggle for adding new partner
  List<String> _levels = ['C+', 'C-', 'D', 'Beginner', 'Seniors', 'Mix Doubles', 'Women'];
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _partnerNameController = TextEditingController();
  final TextEditingController _partnerPhoneController = TextEditingController();
  List<Map<String, dynamic>> _registeredUsers = [];
  bool _loadingUsers = false;
  bool _loadingProfile = true;
  
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
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _partnerNameController.dispose();
    _partnerPhoneController.dispose();
    super.dispose();
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
            final List<String> tournamentLevels = skillLevelData is List
                ? (skillLevelData as List).map((e) => e.toString()).toList()
                : (skillLevelData != null ? [skillLevelData.toString()] : []);
            const allLevels = ['C+', 'C-', 'D', 'Beginner', 'Seniors', 'Mix Doubles', 'Women'];
            _levels = tournamentLevels.isNotEmpty
                ? tournamentLevels.where((l) => allLevels.contains(l)).toList()
                : allLevels;
            if (_levels.length == 1) {
              _selectedLevel = _levels.first;
            }
          }
          setState(() {
            _loadingProfile = false;
          });
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
    if (_selectedLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your skill level'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate partner selection
    if (!_addNewPartner) {
      if (_selectedPartnerId == null || _selectedPartnerName == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please search and select a partner or add a new one'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (_addNewPartner) {
      if (_partnerNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter partner name'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_partnerPhoneController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter partner phone number'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
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
      // Check if user already has a pending or approved request for this tournament
      final existingRequests = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('userId', isEqualTo: user.uid)
          .get();

      if (existingRequests.docs.isNotEmpty) {
        final existingData = existingRequests.docs.first.data();
        final status = existingData['status'] as String? ?? 'pending';
        
        if (status == 'pending' || status == 'approved') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  status == 'pending'
                      ? 'You already have a pending request for this tournament'
                      : 'You are already registered for this tournament',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() {
            _isSubmitting = false;
          });
          return;
        }
      }

      // Use pre-filled form values (from user profile)
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final phone = _phoneController.text.trim();

      // Prepare partner data
      Map<String, dynamic> partnerData = {};
      if (_addNewPartner) {
        partnerData = {
          'partnerType': 'new',
          'partnerName': _partnerNameController.text.trim(),
          'partnerPhone': _partnerPhoneController.text.trim(),
        };
      } else if (_selectedPartnerId != null) {
        final selectedPartner = _registeredUsers.firstWhere(
          (user) => user['id'] == _selectedPartnerId,
        );
        partnerData = {
          'partnerType': 'registered',
          'partnerId': _selectedPartnerId,
          'partnerName': selectedPartner['fullName'],
          'partnerPhone': selectedPartner['phone'],
        };
      }

      // Create tournament registration request
      final requestRef = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .add({
        'tournamentId': widget.tournamentId,
        'tournamentName': widget.tournamentName,
        'userId': user.uid,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'level': _selectedLevel,
        'partner': partnerData,
        'status': 'pending',
        'rulesAccepted': true,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Notify admin about the tournament request
      final userName = '$firstName $lastName'.trim().isEmpty 
          ? (user.phoneNumber ?? 'User') 
          : '$firstName $lastName';
      await NotificationService().notifyAdminForTournamentRequest(
        requestId: requestRef.id,
        userId: user.uid,
        userName: userName,
        phone: phone,
        tournamentName: widget.tournamentName,
        level: _selectedLevel ?? 'Unknown',
      );

      // Notify selected partner (if registered user)
      if (partnerData['partnerType'] == 'registered' && partnerData['partnerId'] != null) {
        try {
          await FirebaseFirestore.instance.collection('notifications').add({
            'userId': partnerData['partnerId'],
            'type': 'tournament_partner_request',
            'title': '🎾 Tournament Partner Request',
            'body': '$userName requested you to join ${widget.tournamentName} together at level ${_selectedLevel ?? 'Unknown'}',
            'read': false,
            'timestamp': FieldValue.serverTimestamp(),
            'tournamentId': widget.tournamentId,
            'tournamentName': widget.tournamentName,
            'requesterId': user.uid,
            'requesterName': userName,
            'level': _selectedLevel,
          });
        } catch (e) {
          debugPrint('Error sending partner notification: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tournament join request submitted! Waiting for admin approval.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
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
              'Select Your Skill Level',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the level that best matches your current skill:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 24),
            ..._levels.map((level) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: _selectedLevel == level
                        ? const Color(0xFF1E3A8A).withOpacity(0.2)
                        : const Color(0xFF1A1F3A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedLevel == level
                          ? const Color(0xFF3B82F6)
                          : Colors.white.withOpacity(0.1),
                      width: _selectedLevel == level ? 2 : 1,
                    ),
                  ),
                  child: RadioListTile<String>(
                    title: Text(
                      level,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: _getLevelDescription(level),
                    value: level,
                    groupValue: _selectedLevel,
                    onChanged: (value) {
                      setState(() {
                        _selectedLevel = value;
                      });
                    },
                    activeColor: const Color(0xFF3B82F6),
                    tileColor: Colors.transparent,
                  ),
                ),
              );
            }),
            const SizedBox(height: 32),
            
            // Partner Selection Section
            Divider(color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 24),
            const Text(
              'Select Your Partner',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a partner from registered users or add a new one:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 16),
            
            // Toggle between selecting registered user or adding new
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Select Registered User'),
                    selected: !_addNewPartner,
                    onSelected: (selected) {
                      setState(() {
                        _addNewPartner = false;
                        _selectedPartnerId = null;
                        _selectedPartnerName = null;
                        _partnerNameController.clear();
                        _partnerPhoneController.clear();
                      });
                      // Reload users when switching to this option
                      if (selected && _registeredUsers.isEmpty) {
                        _loadRegisteredUsers();
                      }
                    },
                    selectedColor: const Color(0xFF1E3A8A),
                    labelStyle: TextStyle(
                      color: !_addNewPartner ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Add New Partner'),
                    selected: _addNewPartner,
                    onSelected: (selected) {
                      setState(() {
                        _addNewPartner = true;
                        _selectedPartnerId = null;
                      });
                    },
                    selectedColor: const Color(0xFF1E3A8A),
                    labelStyle: TextStyle(
                      color: _addNewPartner ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            if (!_addNewPartner) ...[
              // Select from registered users using Autocomplete
              if (_loadingUsers)
                const Center(child: CircularProgressIndicator())
              else if (_registeredUsers.isEmpty)
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1F3A),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'No registered users available',
                        style: TextStyle(color: Colors.white.withOpacity(0.7)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loadRegisteredUsers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                )
              else
                Autocomplete<Map<String, dynamic>>(
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
                        suffixIcon: _selectedPartnerId != null
                            ? IconButton(
                                icon: Icon(Icons.clear, color: Colors.white.withOpacity(0.7)),
                                onPressed: () {
                                  setState(() {
                                    _selectedPartnerId = null;
                                    _selectedPartnerName = null;
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
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1A1F3A),
                      ),
                    );
                  },
                  optionsBuilder: (textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }
                    final query = textEditingValue.text.toLowerCase();
                    return _registeredUsers.where((user) {
                      final fullName = (user['fullName'] as String).toLowerCase();
                      final displayName = (user['displayName'] as String).toLowerCase();
                      return fullName.contains(query) || displayName.contains(query);
                    });
                  },
                  displayStringForOption: (option) => option['displayName'] as String,
                  onSelected: (option) {
                    setState(() {
                      _selectedPartnerId = option['id'] as String;
                      _selectedPartnerName = option['displayName'] as String;
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
                              final displayName = option['displayName'] as String;
                              
                              return ListTile(
                                dense: true,
                                tileColor: const Color(0xFF1A1F3A),
                                title: Text(
                                  displayName,
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
                ),
            ] else ...[
              // Add new partner form
              TextFormField(
                controller: _partnerNameController,
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
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1A1F3A),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _partnerPhoneController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Partner Phone Number *',
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
      case 'Beginner':
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
