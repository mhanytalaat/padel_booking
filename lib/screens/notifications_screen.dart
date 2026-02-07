import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isAdmin() {
    final user = _auth.currentUser;
    if (user == null) return false;
    return user.phoneNumber == '+201006500506' || user.email == 'admin@padelcore.com';
  }

  Future<bool> _isSubAdmin() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    
    try {
      final locationsSnapshot = await _firestore.collection('courtLocations').get();
      for (var doc in locationsSnapshot.docs) {
        final subAdmins = (doc.data()['subAdmins'] as List?)?.cast<String>() ?? [];
        if (subAdmins.contains(user.uid)) {
          return true;
        }
      }
    } catch (e) {
      if (!e.toString().contains('permission-denied')) {
        debugPrint('Error checking sub-admin: $e');
      }
    }
    return false;
  }

  Stream<QuerySnapshot> _getNotificationsStream() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    // Both admins and sub-admins see all notifications (filtered client-side)
    return _firestore.collection('notifications').snapshots();
  }

  Future<void> _markAsRead(String notificationId) async {
    await _notificationService.markNotificationAsRead(notificationId);
  }

  Future<void> _markAllAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final isSubAdmin = await _isSubAdmin();
      
      QuerySnapshot snapshot;
      if (_isAdmin() || isSubAdmin) {
        // Get all notifications and filter client-side (Firestore can't do complex where clauses)
        snapshot = await _firestore
            .collection('notifications')
            .where('isAdminNotification', isEqualTo: true)
            .where('read', isEqualTo: false)
            .get();
        
        // For sub-admins, filter to only booking_request types
        final docsToMark = isSubAdmin && !_isAdmin()
            ? snapshot.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final type = data['type'] as String? ?? '';
                return type == 'booking_request';
              }).toList()
            : snapshot.docs;
        
        final batch = _firestore.batch();
        for (var doc in docsToMark) {
          batch.update(doc.reference, {'read': true});
        }
        await batch.commit();
      } else {
        // Regular users
        snapshot = await _firestore
            .collection('notifications')
            .where('userId', isEqualTo: user.uid)
            .where('read', isEqualTo: false)
            .get();
        
        final batch = _firestore.batch();
        for (var doc in snapshot.docs) {
          batch.update(doc.reference, {'read': true});
        }
        await batch.commit();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking notifications as read: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getNotificationTitle(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    switch (type) {
      case 'booking_request':
        return 'New Booking Request';
      case 'bundle_request':
        return 'New Training Bundle Request';
      case 'tournament_request':
        return 'New Tournament Request';
      case 'booking_status':
        final status = data['status'] as String? ?? '';
        return status == 'approved' ? 'Booking Approved' : 'Booking Rejected';
      case 'tournament_status':
        final status = data['status'] as String? ?? '';
        return status == 'approved' ? 'Tournament Approved' : 'Tournament Rejected';
      default:
        return 'Notification';
    }
  }

  String _getNotificationMessage(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    final message = data['message'] as String?;
    
    if (message != null && message.isNotEmpty) {
      return message;
    }

    switch (type) {
      case 'booking_request':
        final userName = data['userName'] as String? ?? 'User';
        final venue = data['venue'] as String? ?? '';
        final time = data['time'] as String? ?? '';
        final date = data['date'] as String? ?? '';
        return '$userName requested a booking at $venue on $date at $time';
      case 'bundle_request':
        final userName = data['userName'] as String? ?? 'User';
        final sessions = data['sessions'] as int? ?? 0;
        final players = data['players'] as int? ?? 0;
        final price = (data['price'] as num?)?.toDouble() ?? 0.0;
        return '$userName requested $sessions-session bundle for $players player${players > 1 ? 's' : ''} (${price.toStringAsFixed(0)} EGP)';
      case 'tournament_request':
        final userName = data['userName'] as String? ?? 'User';
        final tournamentName = data['tournamentName'] as String? ?? '';
        final level = data['level'] as String? ?? '';
        return '$userName wants to join $tournamentName (Level: $level)';
      case 'booking_status':
        final venue = data['venue'] as String? ?? '';
        final time = data['time'] as String? ?? '';
        final date = data['date'] as String? ?? '';
        final status = data['status'] as String? ?? '';
        if (status == 'approved') {
          return 'Your booking at $venue on $date at $time has been approved!';
        } else {
          return 'Your booking at $venue on $date at $time has been rejected.';
        }
      case 'tournament_status':
        final tournamentName = data['tournamentName'] as String? ?? '';
        final status = data['status'] as String? ?? '';
        if (status == 'approved') {
          return 'Your tournament registration for $tournamentName has been approved!';
        } else {
          return 'Your tournament registration for $tournamentName has been rejected.';
        }
      case 'bundle_approved':
        final title = data['title'] as String? ?? '';
        final body = data['body'] as String? ?? '';
        return body.isNotEmpty ? body : title.isNotEmpty ? title : 'Your training bundle has been approved!';
      default:
        return 'You have a new notification';
    }
  }

  IconData _getNotificationIcon(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    switch (type) {
      case 'booking_request':
      case 'booking_status':
        return Icons.calendar_today;
      case 'bundle_request':
      case 'bundle_approved':
        return Icons.card_giftcard;
      case 'tournament_request':
      case 'tournament_status':
        return Icons.emoji_events;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    switch (type) {
      case 'booking_status':
      case 'tournament_status':
        final status = data['status'] as String? ?? '';
        return status == 'approved' ? Colors.green : Colors.orange;
      case 'bundle_approved':
        return Colors.green;
      case 'booking_request':
      case 'bundle_request':
      case 'tournament_request':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(
        title: 'Notifications',
        showNotifications: false,
        actions: [
          FutureBuilder<bool>(
            future: _isSubAdmin(),
            builder: (context, subAdminSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: _getNotificationsStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }

                  final user = _auth.currentUser;
                  if (user == null) {
                    return const SizedBox.shrink();
                  }

                  final isSubAdmin = subAdminSnapshot.data ?? false;
                  final isMainAdmin = _isAdmin();

                  // Filter notifications based on user type
                  final allNotifications = snapshot.data!.docs;
                  List<QueryDocumentSnapshot> filteredNotifications;
                  
                  if (isMainAdmin) {
                    // Main admin sees all admin notifications
                    filteredNotifications = allNotifications.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['isAdminNotification'] == true;
                    }).toList();
                  } else if (isSubAdmin) {
                    // Sub-admin sees ONLY court booking notifications (booking_request type with venue)
                    filteredNotifications = allNotifications.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final type = data['type'] as String? ?? '';
                      return data['isAdminNotification'] == true && type == 'booking_request';
                    }).toList();
                  } else {
                    // Regular users see only their notifications
                    filteredNotifications = allNotifications.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data['userId'] == user.uid;
                    }).toList();
                  }

                  final unreadCount = filteredNotifications
                      .where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return data['read'] != true;
                      })
                      .length;

                  if (unreadCount == 0) {
                    return const SizedBox.shrink();
                  }

                  return TextButton(
                    onPressed: _markAllAsRead,
                    child: const Text('Mark all read'),
                  );
                },
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: const AppFooter(),
      body: FutureBuilder<bool>(
        future: _isSubAdmin(),
        builder: (context, subAdminSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: _getNotificationsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see notifications here when you receive them',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final allNotifications = snapshot.data!.docs.toList();
          
          // Filter notifications based on user type
          final user = _auth.currentUser;
          final isSubAdmin = subAdminSnapshot.data ?? false;
          final isMainAdmin = _isAdmin();
          List<QueryDocumentSnapshot> notifications;
          
          if (isMainAdmin) {
            // Main admin sees all admin notifications (including bundle requests)
            notifications = allNotifications.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['isAdminNotification'] == true;
            }).toList();
          } else if (isSubAdmin) {
            // Sub-admin sees ONLY court booking notifications (booking_request type with venue)
            notifications = allNotifications.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final type = data['type'] as String? ?? '';
              return data['isAdminNotification'] == true && type == 'booking_request';
            }).toList();
          } else {
            // Regular users see only their notifications
            notifications = allNotifications.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['userId'] == user?.uid;
            }).toList();
          }
          
          // Sort by timestamp (descending) - client-side
          notifications.sort((a, b) {
            final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            if (aTimestamp == null && bTimestamp == null) return 0;
            if (aTimestamp == null) return 1;
            if (bTimestamp == null) return -1;
            return bTimestamp.compareTo(aTimestamp);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['read'] == true;
              final timestamp = data['timestamp'] as Timestamp?;
              final dateTime = timestamp?.toDate();
              final userId = data['userId'] as String?;

              return FutureBuilder<DocumentSnapshot?>(
                future: userId != null && (data['userName'] as String? ?? '').isEmpty
                    ? _firestore.collection('users').doc(userId).get()
                    : Future.value(null),
                builder: (context, userSnapshot) {
                  String displayUserName = data['userName'] as String? ?? 'User';
                  
                  // If userName is missing, try to get it from users collection
                  if (displayUserName == 'User' && userSnapshot.hasData && userSnapshot.data?.exists == true) {
                    final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                    if (userData != null) {
                      final firstName = userData['firstName'] as String? ?? '';
                      final lastName = userData['lastName'] as String? ?? '';
                      final fullName = '$firstName $lastName'.trim();
                      if (fullName.isNotEmpty) {
                        displayUserName = fullName;
                      }
                    }
                  }

                  // Update data with the fetched userName for message generation
                  final updatedData = Map<String, dynamic>.from(data);
                  updatedData['userName'] = displayUserName;

                  return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: isRead ? Colors.white : const Color(0xFFE3F2FD),
                elevation: isRead ? 1 : 2,
                child: InkWell(
                  onTap: () {
                    if (!isRead) {
                      _markAsRead(doc.id);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _getNotificationColor(updatedData).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _getNotificationIcon(updatedData),
                            color: _getNotificationColor(updatedData),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _getNotificationTitle(updatedData),
                                      style: TextStyle(
                                        fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  if (!isRead)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getNotificationMessage(updatedData),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                ),
                              ),
                              if (dateTime != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _formatTimestamp(dateTime),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
                },
              );
            },
          );
        },
      );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}
