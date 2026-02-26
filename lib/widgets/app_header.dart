import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/notifications_screen.dart';
import '../screens/admin_screen.dart';
import '../screens/admin_calendar_grid_screen.dart';
import '../screens/monthly_reports_screen.dart';
import '../screens/home_screen.dart';
import '../screens/edit_profile_screen.dart';
import '../screens/login_screen.dart';
import '../utils/auth_required.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget; // Allow custom title widget
  final List<Widget>? actions;
  final bool showNotifications;
  final bool showAdminButton;

  const AppHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.showNotifications = true,
    this.showAdminButton = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  bool _isAdmin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.phoneNumber == '+201006500506' || user.email == 'admin@padelcore.com';
  }

  Future<bool> _isSubAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    
    try {
      final locationsSnapshot = await FirebaseFirestore.instance
          .collection('courtLocations')
          .get();
      
      for (var doc in locationsSnapshot.docs) {
        final data = doc.data();
        final subAdmins = (data['subAdmins'] as List<dynamic>?) ?? [];
        if (subAdmins.contains(user.uid)) {
          return true;
        }
      }
    } catch (e) {
      // Permission denied during sign-out is expected, ignore silently
      if (e.toString().contains('permission-denied')) {
        return false;
      }
      debugPrint('Error checking sub-admin: $e');
    }
    
    return false;
  }

  Widget _buildAssetImage(String imagePath, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (imagePath.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: const Color(0xFF1E3A8A),
        child: const Icon(
          Icons.emoji_events,
          color: Colors.white,
          size: 48,
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
          color: const Color(0xFF1E3A8A),
          child: const Icon(
            Icons.emoji_events,
            color: Colors.white,
            size: 48,
          ),
        );
      },
    );
  }

  Widget _buildNotificationIcon(BuildContext context, int unreadCount) {
    final isGuest = FirebaseAuth.instance.currentUser == null;
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications, size: 28),
          tooltip: 'Notifications',
          onPressed: () async {
            if (isGuest) {
              final loggedIn = await requireLogin(context);
              if (loggedIn && context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                );
              }
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsScreen()),
              );
            }
          },
        ),
        if (unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if we're on HomeScreen - hide back button on home screen
    final currentRoute = ModalRoute.of(context);
    bool isHomeScreen = false;
    
    if (currentRoute != null) {
      final routeName = currentRoute.settings.name;
      final canPop = Navigator.canPop(context);
      
      // If route name is '/home' or '/', definitely home screen
      if (routeName == '/home' || routeName == '/') {
        isHomeScreen = true;
      } 
      // If we can't pop, we're at root/home
      else if (!canPop) {
        isHomeScreen = true;
      }
      // For web: if route name is null, check if it's the first route
      else if (routeName == null && currentRoute.isFirst) {
        isHomeScreen = true;
      }
    } else {
      // If no route, check if we can pop
      isHomeScreen = !Navigator.canPop(context);
    }
    
    final List<Widget> headerActions = [];
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null;

    // Add Profile / Login button
    headerActions.add(
      IconButton(
        icon: Icon(isGuest ? Icons.login : Icons.person_outline, size: 28),
        tooltip: isGuest ? 'Login' : 'Profile',
        onPressed: () async {
          if (isGuest) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const EditProfileScreen()),
            );
          }
        },
      ),
    );
    
    // Add notifications if enabled
    if (showNotifications) {
      headerActions.add(
        FutureBuilder<bool>(
          future: _isSubAdmin(),
          builder: (context, subAdminSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .snapshots(),
              builder: (context, snapshot) {
                int unreadCount = 0;
                if (snapshot.hasData) {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    final isSubAdmin = subAdminSnapshot.data ?? false;
                    final isMainAdmin = _isAdmin();
                    final notifications = snapshot.data!.docs;
                    
                    if (isMainAdmin) {
                      // Main admin sees all admin notifications
                      unreadCount = notifications.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['isAdminNotification'] == true &&
                               (data['read'] != true);
                      }).length;
                    } else if (isSubAdmin) {
                      // Sub-admin sees ONLY court booking notifications
                      unreadCount = notifications.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final type = data['type'] as String? ?? '';
                        return data['isAdminNotification'] == true &&
                               type == 'booking_request' &&
                               (data['read'] != true);
                      }).length;
                    } else {
                      // Regular users see only their notifications
                      unreadCount = notifications.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['userId'] == user.uid && 
                               (data['read'] != true);
                      }).length;
                    }
                  }
                }
                return _buildNotificationIcon(context, unreadCount);
              },
            );
          },
        ),
      );
    }
    
    // Add admin button if enabled and user is admin
    if (showAdminButton && _isAdmin()) {
      headerActions.add(
        IconButton(
          icon: const Icon(Icons.settings, size: 28),
          tooltip: 'Admin Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AdminScreen()),
            );
          },
        ),
      );
    }
    
    // Add calendar and reports buttons for sub-admins
    if (showAdminButton) {
      headerActions.add(
        FutureBuilder<bool>(
          future: _isSubAdmin(),
          builder: (context, snapshot) {
            final isSubAdmin = snapshot.hasData && snapshot.data == true;
            if (!isSubAdmin) return const SizedBox.shrink();
            
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.calendar_today, size: 28),
                  tooltip: 'Bookings Calendar',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AdminCalendarGridScreen()),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.analytics, size: 28),
                  tooltip: 'Monthly Reports',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const MonthlyReportsScreen()),
                    );
                  },
                ),
              ],
            );
          },
        ),
      );
    }
    
    // Add custom actions
    if (actions != null) {
      headerActions.addAll(actions!);
    }

    return AppBar(
      backgroundColor: const Color(0xFF0A0E27),
      elevation: 0,
      automaticallyImplyLeading: !isHomeScreen, // Hide back button on home screen
      title: InkWell(
        onTap: () {
          // Navigate to home screen, clearing the navigation stack
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _buildAssetImage(
                'assets/images/logo.png',
                height: 52,
                width: 52,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: titleWidget ?? Text(
                title ?? "PadelCore",
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
      actions: headerActions,
    );
  }
}
