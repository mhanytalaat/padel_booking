import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';
import 'court_booking_screen.dart';
import 'locations_map_screen.dart';
import '../utils/map_launcher.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class CourtLocationsScreen extends StatefulWidget {
  const CourtLocationsScreen({super.key});

  @override
  State<CourtLocationsScreen> createState() => _CourtLocationsScreenState();
}

class _CourtLocationsScreenState extends State<CourtLocationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showFavorites = false;
  List<String> _subAdminLocationIds = []; // Locations where user is sub-admin
  bool _isAdmin = false;
  bool _isSubAdmin = false;
  bool _checkingAuth = true;

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
      // Permission denied during sign-out is expected, ignore silently
      if (!e.toString().contains('permission-denied')) {
        debugPrint('Error checking sub-admin access: $e');
      }
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppHeader(
        title: 'Locations',
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LocationsMapScreen(),
                ),
              );
            },
            icon: const Icon(Icons.map, color: Colors.white),
            label: const Text(
              'Map',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppFooter(),
      body: Column(
        children: [
          // Date Selector - Hidden for now
          // _buildDateSelector(),
          
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search locations...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white70),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : IconButton(
                              icon: Icon(
                                _showFavorites ? Icons.favorite : Icons.favorite_border,
                                color: _showFavorites ? Colors.blue : Colors.white70,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showFavorites = !_showFavorites;
                                });
                              },
                            ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Filter buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip('Filters', Icons.filter_list),
                const SizedBox(width: 8),
                _buildFilterChip('Recommended', Icons.swap_vert),
              ],
            ),
          ),

          if (_showFavorites)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Search: Favorites',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),

          // Locations List
          Expanded(
            child: _checkingAuth
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('courtLocations')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.location_off, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                'No locations available',
                                style: TextStyle(color: Colors.white.withOpacity(0.7)),
                              ),
                            ],
                          ),
                        );
                      }

                      var locations = snapshot.data!.docs;

                      // Filter locations for sub-admins (only show their assigned locations)
                      if (_isSubAdmin && !_isAdmin) {
                        locations = locations.where((doc) {
                          return _subAdminLocationIds.contains(doc.id);
                        }).toList();
                      }

                      // Apply search filter
                      if (_searchQuery.isNotEmpty) {
                        locations = locations.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final name = (data['name'] as String? ?? '').toLowerCase();
                          final address = (data['address'] as String? ?? '').toLowerCase();
                          return name.contains(_searchQuery) || address.contains(_searchQuery);
                        }).toList();
                      }

                      // Apply favorites filter
                      if (_showFavorites) {
                        // TODO: Implement favorites logic
                      }

                      // Show message if sub-admin has no locations
                      if (_isSubAdmin && !_isAdmin && locations.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.location_off, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                'No locations assigned to you',
                                style: TextStyle(color: Colors.white.withOpacity(0.7)),
                              ),
                            ],
                          ),
                        );
                      }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: locations.length,
                  itemBuilder: (context, index) {
                    final doc = locations[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['name'] as String? ?? 'Unknown Location';
                    final address = data['address'] as String? ?? '';
                    final courtsCount = (data['courts'] as List?)?.length ?? 0;
                    final distance = data['distance'] as String? ?? '';
                    final isFavorite = data['isFavorite'] as bool? ?? false;

                    return _buildLocationCard(
                      locationId: doc.id,
                      name: name,
                      address: address,
                      courtsCount: courtsCount,
                      distance: distance,
                      isFavorite: isFavorite,
                      logoUrl: data['logoUrl'] as String?,
                      phoneNumber: data['phoneNumber'] as String?,
                      mapsUrl: data['mapsUrl'] as String?,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    final selectedDate = now;

    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF0A0E27),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(selectedDate),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              itemBuilder: (context, index) {
                final date = now.add(Duration(days: index));
                final isSelected = index == 0;
                final dayName = _getDayName(date.weekday);
                final dayNumber = date.day;

                return GestureDetector(
                  onTap: () {
                    // TODO: Handle date selection
                  },
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1E3A8A)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? null
                          : Border.all(color: Colors.white30, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 16,
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard({
    required String locationId,
    required String name,
    required String address,
    required int courtsCount,
    required String distance,
    required bool isFavorite,
    String? logoUrl,
    String? phoneNumber,
    String? mapsUrl,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CourtBookingScreen(locationId: locationId),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Location Logo
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipOval(
                  child: logoUrl != null && logoUrl.isNotEmpty
                      ? _buildNetworkImage(logoUrl, name)
                      : Center(
                          child: Text(
                            name.split(' ').first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // Location Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '$courtsCount Courts',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1E3A8A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (distance.isNotEmpty) ...[
                          const Text(' • ', style: TextStyle(color: Colors.grey)),
                          Text(
                            distance,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1E3A8A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Action Buttons
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Maps Button
                  if ((mapsUrl != null && mapsUrl.isNotEmpty) || (name.isNotEmpty || address.isNotEmpty))
                    IconButton(
                      icon: const Icon(Icons.map, color: Color(0xFF1E3A8A), size: 20),
                      onPressed: () {
                        MapLauncher.openLocationFromUrl(
                          context,
                          url: mapsUrl,
                          fallbackAddressQuery: '$name $address'.trim(),
                        );
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'View on Map',
                    ),
                  // Phone Button
                  if (phoneNumber != null && phoneNumber.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.phone, color: Color(0xFF1E3A8A), size: 20),
                      onPressed: () {
                        _launchUrl('tel:$phoneNumber');
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Call',
                    ),
                  // Favorite Icon
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.red : Colors.grey,
                      size: 20,
                    ),
                    onPressed: () {
                      // TODO: Toggle favorite
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Favorite',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }

  Widget _buildNetworkImage(String imageUrl, String fallbackText) {
    // Use Image.network directly - will work if CORS is configured, otherwise shows fallback
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        // Silently show fallback if image fails to load (likely CORS issue)
        return _buildFallbackText(fallbackText);
      },
    );
  }

  Future<Uint8List?> _fetchImageBytesFromUrl(String imageUrl) async {
    try {
      debugPrint('Fetching image bytes from Firebase Storage: $imageUrl');
      
      // Extract the path from the download URL
      // URL format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media&token={token}
      // Match on the full URL string, not just uri.path (since ? is in query, not path)
      final pathMatch = RegExp(r'/o/(.+?)(\?|$)').firstMatch(imageUrl);
      
      if (pathMatch == null) {
        debugPrint('Could not extract path from URL: $imageUrl');
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
      // Set a timeout to avoid hanging
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
      debugPrint('Image URL: $imageUrl');
      return null;
    }
  }

  Widget _buildFallbackText(String fallbackText) {
    return Center(
      child: Text(
        fallbackText.split(' ').first,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open $url'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
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
