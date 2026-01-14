import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final ageController = TextEditingController();
  final phoneController = TextEditingController();
  String? phoneNumber; // Store phone number from Firestore
  bool phoneExists = false; // Track if phone number exists
  
  bool isLoading = false;
  bool isInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    ageController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && mounted) {
        final data = userDoc.data() as Map<String, dynamic>?;
        final phoneFromFirestore = data?['phone'] as String?;
        final phoneFromAuth = user.phoneNumber;
        phoneNumber = phoneFromFirestore ?? phoneFromAuth;
        phoneExists = phoneFromFirestore != null && phoneFromFirestore.isNotEmpty;
        
        setState(() {
          firstNameController.text = data?['firstName'] as String? ?? '';
          lastNameController.text = data?['lastName'] as String? ?? '';
          ageController.text = data?['age']?.toString() ?? '';
          phoneController.text = phoneNumber ?? '';
          isInitialized = true;
        });
      } else {
        // User profile doesn't exist yet
        phoneNumber = user.phoneNumber;
        phoneExists = false;
        setState(() {
          phoneController.text = phoneNumber ?? '';
          isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isInitialized = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String? _validateFirstName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'First name is required';
    }
    return null;
  }

  String? _validateLastName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Last name is required';
    }
    return null;
  }

  String? _validateAge(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Age is required';
    }
    final age = int.tryParse(value.trim());
    if (age == null) {
      return 'Please enter a valid age';
    }
    if (age < 1 || age > 150) {
      return 'Please enter a valid age (1-150)';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    // Basic phone validation - should start with + and have at least 10 digits
    final phone = value.trim();
    if (!phone.startsWith('+')) {
      return 'Phone number must start with +';
    }
    if (phone.length < 10) {
      return 'Please enter a valid phone number';
    }
    return null;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to edit your profile'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final firstName = firstNameController.text.trim();
      final lastName = lastNameController.text.trim();
      final age = int.tryParse(ageController.text.trim()) ?? 0;
      final phone = phoneController.text.trim();
      final fullName = '$firstName $lastName';

      // Prepare update data
      final updateData = {
        'firstName': firstName,
        'lastName': lastName,
        'fullName': fullName,
        'age': age,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Add phone number if provided
      if (phone.isNotEmpty) {
        updateData['phone'] = phone;
      }

      // Use set with merge to create if doesn't exist, or update if exists
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (!isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Profile Icon
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFF1E3A8A),
                  child: Text(
                    firstNameController.text.isNotEmpty
                        ? firstNameController.text[0].toUpperCase()
                        : (user?.displayName?.isNotEmpty == true
                            ? user!.displayName![0].toUpperCase()
                            : '?'),
                    style: const TextStyle(
                      fontSize: 40,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Phone Number - Editable if doesn't exist, or always editable
              TextFormField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number *',
                  hintText: '+201234567890',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  helperText: phoneExists 
                      ? 'You can update your phone number' 
                      : 'Please add your phone number',
                ),
                validator: _validatePhone,
                enabled: !isLoading,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              
              // Email (Read-only if exists)
              if (user?.email != null) ...[
                TextFormField(
                  initialValue: user!.email,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[200],
                  ),
                  enabled: false,
                ),
                const SizedBox(height: 16),
              ],
              
              // First Name
              TextFormField(
                controller: firstNameController,
                decoration: InputDecoration(
                  labelText: 'First Name *',
                  hintText: 'Enter your first name',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: _validateFirstName,
                enabled: !isLoading,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => setState(() {}), // Update avatar
              ),
              const SizedBox(height: 16),
              
              // Last Name
              TextFormField(
                controller: lastNameController,
                decoration: InputDecoration(
                  labelText: 'Last Name *',
                  hintText: 'Enter your last name',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: _validateLastName,
                enabled: !isLoading,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              
              // Age
              TextFormField(
                controller: ageController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Age *',
                  hintText: 'Enter your age',
                  prefixIcon: const Icon(Icons.calendar_today),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: _validateAge,
                enabled: !isLoading,
              ),
              const SizedBox(height: 32),
              
              // Save Button
              ElevatedButton(
                onPressed: isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      )
                    : const Text(
                        'Save Profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              
              // Delete Account Section
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Account Management',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Deleting your account will permanently remove all your data including bookings, tournament registrations, and profile information. This action cannot be undone.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              
              // Delete Account Button
              OutlinedButton(
                onPressed: isLoading ? null : _showDeleteAccountDialog,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.red, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Delete Account',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete your account?\n\n'
          'This will permanently delete:\n'
          '• Your profile information\n'
          '• All your bookings\n'
          '• All your tournament registrations\n'
          '• All your notifications\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No user logged in'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final userId = user.uid;
      
      // Delete all Firestore data first
      try {
        final batch = FirebaseFirestore.instance.batch();

        // Delete all user's bookings
        final bookingsSnapshot = await FirebaseFirestore.instance
            .collection('bookings')
            .where('userId', isEqualTo: userId)
            .get();
        
        for (var doc in bookingsSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Delete all user's tournament registrations
        final tournamentRegistrationsSnapshot = await FirebaseFirestore.instance
            .collection('tournamentRegistrations')
            .where('userId', isEqualTo: userId)
            .get();
        
        for (var doc in tournamentRegistrationsSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Delete all user's notifications
        final notificationsSnapshot = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .get();
        
        for (var doc in notificationsSnapshot.docs) {
          batch.delete(doc.reference);
        }

        // Delete user profile
        final userRef = FirebaseFirestore.instance
            .collection('users')
            .doc(userId);
        batch.delete(userRef);

        // Commit all deletions
        await batch.commit();
      } catch (e) {
        debugPrint('Error deleting Firestore data: $e');
        // Continue with auth deletion even if Firestore deletion fails
      }

      // Delete Firebase Auth account (this will automatically sign out the user)
      try {
        await user.delete();
        // user.delete() automatically signs out, so AuthWrapper will handle navigation
      } catch (e) {
        // If auth deletion fails, try to sign out manually
        debugPrint('Error deleting auth account: $e');
        try {
          await FirebaseAuth.instance.signOut();
        } catch (signOutError) {
          debugPrint('Error signing out: $signOutError');
        }
        
        // Re-throw to show error to user
        throw e;
      }
      
      // Account deleted successfully
      // The AuthWrapper will automatically detect the sign out and show LoginScreen
      // Just pop this screen and let the auth state change handle navigation
      if (mounted) {
        // Simply pop this screen - AuthWrapper will handle the rest
        Navigator.of(context).pop();
        
        // Show success message after navigation
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account deleted successfully. You have been signed out.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        
        String errorMessage = 'Error deleting account: $e';
        
        // Provide more specific error messages
        if (e.toString().contains('requires-recent-login')) {
          errorMessage = 'For security reasons, please sign out and sign in again before deleting your account.';
        } else if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permission denied. Please try again or contact support.';
        } else if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection and try again.';
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
}

