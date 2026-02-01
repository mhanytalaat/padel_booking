import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../screens/my_bookings_screen.dart';
import '../screens/tournaments_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/skills_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/booking_page_screen.dart';
import '../screens/court_locations_screen.dart';

class AppFooter extends StatefulWidget {
  final int? selectedIndex; // -1 for none selected, 0-4 for specific items

  const AppFooter({
    super.key,
    this.selectedIndex,
  });

  @override
  State<AppFooter> createState() => _AppFooterState();
}

class _AppFooterState extends State<AppFooter> {
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex ?? -1;
  }

  @override
  void didUpdateWidget(AppFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      setState(() {
        _selectedIndex = widget.selectedIndex ?? -1;
      });
    }
  }

  /// Safely navigate to HomeScreen without breaking app initialization
  /// This keeps the root route intact to prevent app initialization errors
  void _navigateToHome() {
    final navigator = Navigator.of(context);
    
    // Check if we're already on HomeScreen
    final currentRoute = ModalRoute.of(context);
    if (currentRoute != null) {
      // Try to check if current route is HomeScreen by checking route settings
      final routeSettings = currentRoute.settings;
      if (routeSettings.name == '/' || routeSettings.name == '/home') {
        // Already on home, don't navigate
        return;
      }
    }
    
    // Use pushAndRemoveUntil but ALWAYS keep the first route (root)
    // This prevents the "app initialization error" by preserving the MaterialApp root
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const HomeScreen(),
        settings: const RouteSettings(name: '/home'), // Set route name for detection
      ),
      (Route<dynamic> route) => route.isFirst, // Keep ONLY the first route (root)
    ).then((_) {
      if (mounted) {
        setState(() {
          _selectedIndex = -1;
        });
      }
    });
  }

          void _onNavItemTapped(int index) {
            setState(() {
              _selectedIndex = index;
            });

            switch (index) {
              case -1: // Home
                _navigateToHome();
                break;
              case 0: // Book (new)
                _showBookingOptions();
                break;
              case 1: // My Bookings
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MyBookingsScreen()),
        ).then((_) {
          setState(() {
            _selectedIndex = -1;
          });
        });
        break;
      case 2: // Tournaments
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TournamentsScreen()),
        ).then((_) {
          setState(() {
            _selectedIndex = -1;
          });
        });
        break;
      case 3: // Skills
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SkillsScreen()),
        ).then((_) {
          setState(() {
            _selectedIndex = -1;
          });
        });
        break;
      case 4: // Profile
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
        ).then((_) {
          setState(() {
            _selectedIndex = -1;
          });
        });
        break;
    }
  }

  void _showBookingOptions() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Book Your Session',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                Expanded(
                  child: _buildBookingOptionCard(
                    title: 'Train',
                    subtitle: 'With certified coaches',
                    imagePath: 'assets/images/train1.png',
                    color: Colors.orange,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const BookingPageScreen()),
                      );
                    },
                  ),
                ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildBookingOptionCard(
                      title: 'Book a Court',
                      subtitle: 'Get on the game',
                      imagePath: 'assets/images/court_icon.png',
                      color: Colors.blue,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CourtLocationsScreen()),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildBookingOptionCard(
                      title: 'Compete',
                      subtitle: 'Join tournaments',
                      imagePath: 'assets/images/compete.png',
                      color: Colors.purple,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TournamentsScreen()),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    
    setState(() {
      _selectedIndex = -1;
    });
  }

  Widget _buildBookingOptionCard({
    required String title,
    required String subtitle,
    IconData? icon,
    String? imagePath,
    bool isSvg = false,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 135, // Fixed height for all cards
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon/Image - Fixed size container
            SizedBox(
              width: 40,
              height: 40,
              child: imagePath != null && !isSvg
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        imagePath,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    )
                  : icon != null
                      ? Icon(icon, size: 40, color: Colors.white)
                      : const SizedBox.shrink(),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Flexible(
              child: Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onNavItemTapped(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                ),
              ),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 2,
                  width: 30,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(1)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E27),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.home,
                label: 'Home',
                index: -1, // Special index for home
              ),
              _buildNavItem(
                icon: Icons.add_circle,
                label: 'Book',
                index: 0,
              ),
              _buildNavItem(
                icon: Icons.bookmark,
                label: 'My Bookings',
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.emoji_events,
                label: 'Tournaments',
                index: 2,
              ),
              _buildNavItem(
                icon: Icons.radar,
                label: 'Skills',
                index: 3,
              ),
              _buildNavItem(
                icon: Icons.person,
                label: 'Profile',
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
