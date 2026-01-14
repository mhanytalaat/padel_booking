import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

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
  final List<String> _levels = ['Beginner', 'D', 'C', 'B', 'A'];
  final TextEditingController _partnerNameController = TextEditingController();
  final TextEditingController _partnerPhoneController = TextEditingController();
  List<Map<String, dynamic>> _registeredUsers = [];
  bool _loadingUsers = false;
  
  // Admin credentials to filter out
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com';

  @override
  void initState() {
    super.initState();
    _loadRegisteredUsers();
  }

  @override
  void dispose() {
    _partnerNameController.dispose();
    _partnerPhoneController.dispose();
    super.dispose();
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

  Future<void> _submitJoinRequest() async {
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

      // Get user profile data
      final userProfile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String firstName = '';
      String lastName = '';
      String phone = user.phoneNumber ?? '';

      if (userProfile.exists) {
        final userData = userProfile.data() as Map<String, dynamic>;
        firstName = userData['firstName'] as String? ?? '';
        lastName = userData['lastName'] as String? ?? '';
        phone = userData['phone'] as String? ?? user.phoneNumber ?? '';
      }

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
      appBar: AppBar(
        title: Text(widget.tournamentName),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
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
                          : Image.asset(
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
                            ),
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
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Select Your Skill Level',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose the level that best matches your current skill:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ..._levels.map((level) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RadioListTile<String>(
                  title: Text(
                    level,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
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
                  activeColor: const Color(0xFF1E3A8A),
                  tileColor: _selectedLevel == level
                      ? const Color(0xFF1E3A8A).withOpacity(0.1)
                      : Colors.grey[100],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: _selectedLevel == level
                          ? const Color(0xFF1E3A8A)
                          : Colors.grey[300]!,
                      width: _selectedLevel == level ? 2 : 1,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 32),
            
            // Partner Selection Section
            const Divider(),
            const SizedBox(height: 24),
            const Text(
              'Select Your Partner',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a partner from registered users or add a new one:',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
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
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'No registered users available',
                        style: TextStyle(color: Colors.grey),
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
                      decoration: InputDecoration(
                        labelText: 'Search partner by name',
                        hintText: 'Type to search...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _selectedPartnerId != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
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
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
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
                                title: Text(
                                  displayName,
                                  style: const TextStyle(fontSize: 14),
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
                decoration: InputDecoration(
                  labelText: 'Partner Name *',
                  hintText: 'Enter partner full name',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _partnerPhoneController,
                decoration: InputDecoration(
                  labelText: 'Partner Phone Number *',
                  hintText: '+201234567890',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
            
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitJoinRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
      case 'Beginner':
        return const Text('Just starting out with padel');
      case 'D':
        return const Text('Basic skills, learning fundamentals');
      case 'C':
        return const Text('Intermediate level, consistent play');
      case 'B':
        return const Text('Advanced level, competitive player');
      case 'A':
        return const Text('Expert level, tournament experience');
      default:
        return null;
    }
  }
}
