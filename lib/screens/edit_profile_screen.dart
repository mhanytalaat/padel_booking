import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import 'login_screen.dart';

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
  String? selectedGender; // 'male' or 'female'
  
  bool isLoading = false;
  bool isInitialized = false;
  
  // Profile photo
  String? profilePhotoUrl;
  bool isUploadingPhoto = false;

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
          final gender = data?['gender'] as String?;
          selectedGender = (gender == 'male' || gender == 'female') ? gender : null;
          profilePhotoUrl = data?['profilePhotoUrl'] as String?;
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
          phoneNumber = user.phoneNumber;
          phoneController.text = phoneNumber ?? '';
          isInitialized = true;
        });
        // On web, Firestore SDK can throw INTERNAL ASSERTION FAILED; don't show raw error to user
        final isFirestoreWebBug = kIsWeb &&
            (e.toString().contains('INTERNAL ASSERTION FAILED') ||
                e.toString().contains('Unexpected state'));
        if (isFirestoreWebBug) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile form ready. You can update your details below.'),
              backgroundColor: Colors.blue,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading profile: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
    // Must start with +2 (Egypt country code)
    final phone = value.trim();
    if (!phone.startsWith('+2')) {
      return 'Phone number must start with +2 (Egypt country code)';
    }
    // Remove +2 and check remaining digits
    final remainingDigits = phone.substring(2);
    
    // Must be exactly 11 digits after +2
    if (!RegExp(r'^\d{11}$').hasMatch(remainingDigits)) {
      if (!RegExp(r'^\d+$').hasMatch(remainingDigits)) {
        return 'Phone number must contain only digits after +2';
      } else if (remainingDigits.length < 11) {
        return 'Phone number must be 11 digits after +2 (e.g., +201012345678)';
      } else {
        return 'Phone number must be exactly 11 digits after +2 (e.g., +201012345678)';
      }
    }
    return null;
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    
    try {
      // Show source selection dialog
      final source = await showDialog<ImageSource>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Photo Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (source == null) return;

      // Pick image (camera requires NSCameraUsageDescription in Info.plist on iOS)
      XFile? image;
      try {
        image = await picker.pickImage(
          source: source,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 85,
        );
      } catch (pickError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not open ${source == ImageSource.camera ? "camera" : "gallery"}. '
                'Please check app permissions in Settings.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      if (image == null) return;

      if (!mounted) return;

      setState(() {
        isUploadingPhoto = true;
      });

      // Upload to Firebase Storage
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('${user.uid}.jpg');

      // Use bytes for web compatibility
      final bytes = await image.readAsBytes();
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'profilePhotoUrl': downloadUrl}, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          profilePhotoUrl = downloadUrl;
          isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error uploading photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showPhotoOptions() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Profile Photo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Change Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickAndUploadPhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteProfilePhoto();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProfilePhoto() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() {
        isUploadingPhoto = true;
      });

      // Delete from Storage
      try {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_photos')
            .child('${user.uid}.jpg');
        await storageRef.delete();
      } catch (e) {
        // Photo might not exist in storage, that's okay
      }

      // Remove from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'profilePhotoUrl': FieldValue.delete()});

      if (mounted) {
        setState(() {
          profilePhotoUrl = null;
          isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile photo removed'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
      final updateData = <String, dynamic>{
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

      // Add gender if selected
      if (selectedGender != null) {
        updateData['gender'] = selectedGender;
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
        appBar: const AppHeader(title: 'Edit Profile'),
        bottomNavigationBar: const AppFooter(selectedIndex: 4),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: const AppHeader(title: 'Edit Profile'),
      bottomNavigationBar: const AppFooter(selectedIndex: 4),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Profile Photo
              Center(
                child: Stack(
                  children: [
                    // Photo or Initial Avatar
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: const Color(0xFF1E3A8A),
                      backgroundImage: profilePhotoUrl != null
                          ? NetworkImage(profilePhotoUrl!)
                          : null,
                      child: profilePhotoUrl == null
                          ? Text(
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
                            )
                          : null,
                    ),
                    // Edit/Upload Button
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: isUploadingPhoto ? null : () {
                            // Show options: upload or delete
                            if (profilePhotoUrl != null) {
                              _showPhotoOptions();
                            } else {
                              _pickAndUploadPhoto();
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: isUploadingPhoto
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    profilePhotoUrl != null ? Icons.edit : Icons.add_a_photo,
                                    size: 20,
                                    color: const Color(0xFF1E3A8A),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // User ID Display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A8A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1E3A8A).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.badge,
                          color: const Color(0xFF1E3A8A),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Your Tournament ID',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '#${user?.uid != null && user!.uid.length >= 4 ? user.uid.substring(0, 4).toUpperCase() : "N/A"}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                            letterSpacing: 2,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          color: const Color(0xFF1E3A8A),
                          tooltip: 'Copy ID',
                          onPressed: () async {
                            if (user?.uid != null && user!.uid.length >= 4) {
                              final uniqueId = user.uid.substring(0, 4).toUpperCase();
                              await Clipboard.setData(ClipboardData(text: uniqueId));
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('ID #$uniqueId copied to clipboard'),
                                    backgroundColor: Colors.green,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Share this ID with your partner when joining tournaments together',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Phone Number - Editable if doesn't exist, or always editable
              TextFormField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number *',
                  hintText: '+201012345678 (11 digits after +2)',
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
              const SizedBox(height: 16),
              
              // Gender (Male / Female)
              const Text(
                'Gender',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String?>(
                      segments: const [
                        ButtonSegment(value: 'male', label: Text('Male'), icon: Icon(Icons.male)),
                        ButtonSegment(value: 'female', label: Text('Female'), icon: Icon(Icons.female)),
                      ],
                      selected: {selectedGender},
                      onSelectionChanged: isLoading
                          ? null
                          : (Set<String?> newSelection) {
                              setState(() {
                                selectedGender = newSelection.isEmpty ? null : newSelection.first;
                              });
                            },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                  ),
                ],
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
              
              // Logout Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : _handleLogout,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.orange[700]!, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(Icons.logout, color: Colors.orange[700]),
                  label: Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[700],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Support Contact Section
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Support Contact',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('config')
                    .doc('support')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const SizedBox.shrink();
                  }
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  final email = (data?['supportEmail'] as String?)?.trim() ?? '';
                  final phone = (data?['supportPhone'] as String?)?.trim() ?? '';
                  final whatsapp = (data?['supportWhatsapp'] as String?)?.trim() ?? '';
                  if (email.isEmpty && phone.isEmpty && whatsapp.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (email.isNotEmpty)
                        _SupportContactTile(
                          icon: Icons.email_outlined,
                          label: 'Support Email:',
                          value: email,
                          onTap: () => _launchUrl('mailto:$email'),
                        ),
                      if (phone.isNotEmpty)
                        _SupportContactTile(
                          icon: Icons.phone_outlined,
                          label: 'Support Phone:',
                          value: phone,
                          onTap: () => _launchUrl('tel:$phone'),
                        ),
                      if (whatsapp.isNotEmpty)
                        _SupportContactTile(
                          icon: Icons.chat_outlined,
                          label: 'Support WhatsApp:',
                          value: whatsapp,
                          onTap: () => _launchWhatsApp(whatsapp),
                        ),
                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
              
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final number = clean.startsWith('+') ? clean.substring(1) : clean;
    await _launchUrl('https://wa.me/$number');
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // On web, clear navigation stack first to allow Firestore streams to dispose
        if (kIsWeb) {
          // Navigate to login screen and clear stack
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (Route<dynamic> route) => false,
          );
          // Small delay to allow streams to dispose
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        // Sign out from Firebase
        await FirebaseAuth.instance.signOut();
        
        // For non-web platforms, navigate after sign out
        if (!kIsWeb && mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (Route<dynamic> route) => false,
          );
        }
      } catch (e) {
        debugPrint('Error during logout: $e');
        // Even if there's an error, try to navigate to login
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (Route<dynamic> route) => false,
          );
        }
      }
    }
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

class _SupportContactTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SupportContactTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
          child: Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFF1E3A8A)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1E3A8A),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
