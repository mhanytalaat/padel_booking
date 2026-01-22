import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/my_bookings_screen.dart';
import '../screens/tournaments_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/skills_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';

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

          void _onNavItemTapped(int index) {
            setState(() {
              _selectedIndex = index;
            });

            switch (index) {
              case -1: // Home
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                ).then((_) {
                  setState(() {
                    _selectedIndex = -1;
                  });
                });
                break;
              case 0: // My Bookings
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const MyBookingsScreen()),
        ).then((_) {
          setState(() {
            _selectedIndex = -1;
          });
        });
        break;
      case 1: // Tournaments
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TournamentsScreen()),
        ).then((_) {
          setState(() {
            _selectedIndex = -1;
          });
        });
        break;
      case 2: // Profile
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const EditProfileScreen()),
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
      case 4: // Logout
        _handleLogout();
        break;
    }
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
    } else {
      setState(() {
        _selectedIndex = -1;
      });
    }
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
                icon: Icons.bookmark,
                label: 'My Bookings',
                index: 0,
              ),
              _buildNavItem(
                icon: Icons.emoji_events,
                label: 'Tournaments',
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.person,
                label: 'Profile',
                index: 2,
              ),
              _buildNavItem(
                icon: Icons.radar,
                label: 'Skills',
                index: 3,
              ),
              _buildNavItem(
                icon: Icons.logout,
                label: 'Logout',
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
