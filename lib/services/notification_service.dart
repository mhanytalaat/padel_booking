import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Initialize FCM and request permissions
  Future<void> initialize() async {
    try {
      // Request notification permissions
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('User granted provisional notification permission');
      } else {
        debugPrint('User declined or has not accepted notification permission');
        return;
      }

      // Get FCM token
      String? token = await _messaging.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
        debugPrint('FCM Token: $token');
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(newToken);
        debugPrint('FCM Token refreshed: $newToken');
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background messages (when app is in background)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  // Save FCM token to Firestore
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  // Handle foreground messages (when app is open)
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message received: ${message.notification?.title}');
    // You can show a local notification or update UI here
    // For now, we'll just log it
  }

  // Handle background messages (when app is opened from notification)
  void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('Background message opened: ${message.notification?.title}');
    // Navigate to appropriate screen based on notification data
  }

  // Send notification to admin when user submits a request
  Future<void> notifyAdminForBookingRequest({
    required String bookingId,
    required String userId,
    required String userName,
    required String phone,
    required String venue,
    required String time,
    required String date,
  }) async {
    try {
      // Create notification document in Firestore
      // Admin notifications don't need a userId - they'll be queried separately
      // For actual push notifications, you'll need Cloud Functions
      await _firestore.collection('notifications').add({
        'type': 'booking_request',
        'bookingId': bookingId,
        'userId': userId,
        'userName': userName,
        'phone': phone,
        'venue': venue,
        'time': time,
        'date': date,
        'status': 'pending',
        'isAdminNotification': true, // Mark as admin notification
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('Notification created for booking request: $bookingId');
    } catch (e) {
      debugPrint('Error notifying admin for booking: $e');
    }
  }

  // Send notification to admin when user submits tournament registration
  Future<void> notifyAdminForTournamentRequest({
    required String requestId,
    required String userId,
    required String userName,
    required String phone,
    required String tournamentName,
    required String level,
  }) async {
    try {
      // Create notification document in Firestore
      // Admin notifications don't need a userId - they'll be queried separately
      await _firestore.collection('notifications').add({
        'type': 'tournament_request',
        'requestId': requestId,
        'userId': userId,
        'userName': userName,
        'phone': phone,
        'tournamentName': tournamentName,
        'level': level,
        'status': 'pending',
        'isAdminNotification': true, // Mark as admin notification
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('Notification created for tournament request: $requestId');
    } catch (e) {
      debugPrint('Error notifying admin for tournament: $e');
    }
  }

  // Send notification to user when admin approves/rejects booking
  Future<void> notifyUserForBookingStatus({
    required String userId,
    required String bookingId,
    required String status, // 'approved' or 'rejected'
    required String venue,
    required String time,
    required String date,
  }) async {
    try {
      String message = status == 'approved'
          ? 'Your booking at $venue on $date at $time has been approved!'
          : 'Your booking at $venue on $date at $time has been rejected.';

      await _firestore.collection('notifications').add({
        'type': 'booking_status',
        'userId': userId,
        'bookingId': bookingId,
        'status': status,
        'venue': venue,
        'time': time,
        'date': date,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('Notification created for booking status: $bookingId');
    } catch (e) {
      debugPrint('Error notifying user for booking status: $e');
    }
  }

  // Send notification to user when admin approves/rejects tournament registration
  Future<void> notifyUserForTournamentStatus({
    required String userId,
    required String requestId,
    required String status, // 'approved' or 'rejected'
    required String tournamentName,
  }) async {
    try {
      String message = status == 'approved'
          ? 'Your tournament registration for $tournamentName has been approved!'
          : 'Your tournament registration for $tournamentName has been rejected.';

      await _firestore.collection('notifications').add({
        'type': 'tournament_status',
        'userId': userId,
        'requestId': requestId,
        'status': status,
        'tournamentName': tournamentName,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('Notification created for tournament status: $requestId');
    } catch (e) {
      debugPrint('Error notifying user for tournament status: $e');
    }
  }

  // Get unread notification count for current user
  Future<int> getUnreadNotificationCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0;

      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('read', isEqualTo: false)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      debugPrint('Error getting unread count: $e');
      return 0;
    }
  }

  // Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }
}

// Top-level function for background message handling (must be top-level)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.notification?.title}');
  // Handle background message here
}
