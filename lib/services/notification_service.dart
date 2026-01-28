import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  // Initialize FCM and request permissions
  Future<void> initialize() async {
    try {
      // Initialize local notifications for Android
      if (!kIsWeb) {
        const AndroidInitializationSettings initializationSettingsAndroid =
            AndroidInitializationSettings('@mipmap/ic_launcher');

        const InitializationSettings initializationSettings = InitializationSettings(
          android: initializationSettingsAndroid,
        );

        await _localNotifications.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            debugPrint('Notification tapped: ${response.payload}');
          },
        );

        // Create notification channel for Android 8.0+
        const AndroidNotificationChannel channel = AndroidNotificationChannel(
          'padelcore_notifications', // id
          'PadelCore Notifications', // name
          description: 'Notifications for booking updates and alerts',
          importance: Importance.high,
          playSound: true,
        );

        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      // Request notification permissions
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('✅ User granted provisional notification permission');
      } else {
        debugPrint('❌ User declined or has not accepted notification permission');
        // Don't return - still try to get token on Android (auto-granted)
      }

      // Get FCM token
      debugPrint('🔄 Getting FCM token...');
      
      String? token = await _messaging.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
        debugPrint('✅ FCM Token saved: ${token.substring(0, 20)}...');
        debugPrint('   Token length: ${token.length}');
      } else {
        debugPrint('❌ Failed to get FCM token');
        // Try again after a delay
        await Future.delayed(const Duration(seconds: 2));
        token = await _messaging.getToken();
        if (token != null) {
          await _saveTokenToFirestore(token);
          debugPrint('✅ FCM Token saved on retry: ${token.substring(0, 20)}...');
        } else {
          debugPrint('❌ Still failed to get FCM token after retry');
        }
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _saveTokenToFirestore(newToken);
        debugPrint('FCM Token refreshed: $newToken');
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleForegroundMessage(message);
      });

      // Handle background messages (when app is opened from notification)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleBackgroundMessage(message);
      });
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  // Manually refresh FCM token (useful for troubleshooting)
  Future<void> refreshToken() async {
    try {
      debugPrint('🔄 Manually refreshing FCM token...');
      String? token = await _messaging.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
        debugPrint('✅ Token refreshed successfully');
      } else {
        debugPrint('❌ Failed to refresh token');
      }
    } catch (e) {
      debugPrint('❌ Error refreshing token: $e');
    }
  }

  // Save FCM token to Firestore (supports multiple devices per user)
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('❌ Cannot save FCM token - no user logged in');
        return;
      }

      debugPrint('💾 Saving FCM token for user: ${user.uid}');
      debugPrint('   Email: ${user.email}');
      debugPrint('   Phone: ${user.phoneNumber}');
      
      // Determine platform
      String platform = kIsWeb ? 'web' : defaultTargetPlatform.toString();
      platform = platform.replaceAll('TargetPlatform.', ''); // Clean up: "TargetPlatform.iOS" -> "iOS"
      
      debugPrint('   Platform: $platform');
      debugPrint('   Token: ${token.substring(0, 20)}...');
      
      // Get existing tokens
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic> fcmTokens = {};
      
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null && data.containsKey('fcmTokens')) {
          fcmTokens = Map<String, dynamic>.from(data['fcmTokens'] as Map? ?? {});
        }
      }
      
      // Add or update token for this platform
      fcmTokens[platform] = {
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Also keep legacy fcmToken field for backward compatibility
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token, // Legacy field (last device)
        'fcmTokens': fcmTokens, // New field (all devices)
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'lastPlatform': platform,
      }, SetOptions(merge: true));
      
      debugPrint('✅ FCM token saved successfully to Firestore');
      debugPrint('   Active devices: ${fcmTokens.keys.join(', ')}');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
      debugPrint('   Stack trace: ${StackTrace.current}');
    }
  }

  // Handle foreground messages (when app is open)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Foreground message received: ${message.notification?.title}');
    
    // Show local notification when app is in foreground
    if (!kIsWeb && message.notification != null) {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'padelcore_notifications',
        'PadelCore Notifications',
        channelDescription: 'Notifications for booking updates and alerts',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        playSound: true,
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await _localNotifications.show(
        message.hashCode,
        message.notification?.title ?? 'New Notification',
        message.notification?.body ?? '',
        platformChannelSpecifics,
        payload: message.data.toString(),
      );
    }
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
        'title': '🎾 New Booking Request',
        'body': '$userName wants to book $venue on $date at $time',
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
        'title': '🏆 New Tournament Registration',
        'body': '$userName wants to join $tournamentName (Level: $level)',
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
      String title = status == 'approved'
          ? '✅ Booking Confirmed!'
          : '❌ Booking Rejected';
      
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
        'title': title,
        'body': message,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('Notification created for booking status: $bookingId');
    } catch (e) {
      debugPrint('Error notifying user for booking status: $e');
    }
  }

  // Send booking reminder to user before their booking time
  Future<void> sendBookingReminder({
    required String userId,
    required String bookingId,
    required String venue,
    required String time,
    required String date,
    required int minutesBefore,
  }) async {
    try {
      String title = '⏰ Booking Reminder';
      String body = '';
      
      if (minutesBefore == 30) {
        body = 'Your booking at $venue is in 30 minutes! ($time on $date)';
      } else if (minutesBefore == 10) {
        body = 'Your booking at $venue starts in 10 minutes! ($time on $date)';
      } else if (minutesBefore == 0) {
        body = 'Your booking at $venue is starting now! ($time)';
      }

      await _firestore.collection('notifications').add({
        'type': 'booking_reminder',
        'userId': userId,
        'bookingId': bookingId,
        'venue': venue,
        'time': time,
        'date': date,
        'minutesBefore': minutesBefore,
        'title': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      debugPrint('Booking reminder sent: $bookingId ($minutesBefore mins before)');
    } catch (e) {
      debugPrint('Error sending booking reminder: $e');
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
      String title = status == 'approved'
          ? '✅ Tournament Registration Approved!'
          : '❌ Tournament Registration Rejected';
      
      String message = status == 'approved'
          ? 'Your tournament registration for $tournamentName has been approved!'
          : 'Your tournament registration for $tournamentName has been rejected.';

      await _firestore.collection('notifications').add({
        'type': 'tournament_status',
        'userId': userId,
        'requestId': requestId,
        'status': status,
        'tournamentName': tournamentName,
        'title': title,
        'body': message,
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
  // Initialize Firebase in the background isolate
  await Firebase.initializeApp();
  
  debugPrint('Background message received: ${message.notification?.title}');
  debugPrint('Background message data: ${message.data}');
  
  // Initialize local notifications for showing notification when app is terminated
  final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
  
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  
  await localNotifications.initialize(initializationSettings);
  
  // Create notification channel if it doesn't exist
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'padelcore_notifications',
    'PadelCore Notifications',
    description: 'Notifications for booking updates and alerts',
    importance: Importance.high,
    playSound: true,
  );
  
  await localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
  
  // Show notification
  if (message.notification != null) {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'padelcore_notifications',
      'PadelCore Notifications',
      channelDescription: 'Notifications for booking updates and alerts',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await localNotifications.show(
      message.hashCode,
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      platformChannelSpecifics,
      payload: message.data.toString(),
    );
  }
}
