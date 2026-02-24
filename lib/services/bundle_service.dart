import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/bundle_model.dart';
import 'notification_service.dart';

class BundleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get bundle pricing from config
  Future<Map<String, dynamic>> getBundlePricing() async {
    try {
      final doc = await _firestore
          .collection('config')
          .doc('bundlePricing')
          .get();

      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }

      // Default pricing if config doesn't exist
      return _getDefaultPricing();
    } catch (e) {
      print('Error getting bundle pricing: $e');
      return _getDefaultPricing();
    }
  }

  Map<String, dynamic> _getDefaultPricing() {
    return {
      '1_session': {
        '1_player': 1000,
        '2_players': 1500,
        '3_players': 1750,
        '4_players': 2000,
      },
      '4_sessions': {
        '1_player': 3400,
        '2_players': 2600,
        '3_players': 2000,
        '4_players': 1800,
      },
      '8_sessions': {
        '1_player': 6080,
        '2_players': 3800,
        '3_players': 2720,
        '4_players': 2000,
      },
    };
  }

  // Get price for specific bundle configuration
  Future<double> getBundlePrice(int sessions, int playerCount) async {
    final pricing = await getBundlePricing();
    final sessionKey = '${sessions}_session${sessions > 1 ? 's' : ''}';
    final playerKey = '${playerCount}_player${playerCount > 1 ? 's' : ''}';

    try {
      return (pricing[sessionKey]?[playerKey] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print('Error getting bundle price: $e');
      return 0.0;
    }
  }

  // Update bundle pricing (admin only)
  Future<void> updateBundlePricing(Map<String, dynamic> pricing) async {
    await _firestore
        .collection('config')
        .doc('bundlePricing')
        .set(pricing, SetOptions(merge: true));
  }

  // Create bundle request
  Future<String> createBundleRequest({
    required String userId,
    required String userName,
    required String userPhone,
    required int bundleType,
    required int playerCount,
    String notes = '',
    Map<String, dynamic>? scheduleDetails,
  }) async {
    final price = await getBundlePrice(bundleType, playerCount);

    final bundleData = {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'bundleType': bundleType,
      'playerCount': playerCount,
      'totalSessions': bundleType,
      'usedSessions': 0,
      'attendedSessions': 0,
      'missedSessions': 0,
      'cancelledSessions': 0,
      'remainingSessions': bundleType,
      'price': price,
      'paymentStatus': 'pending',
      'paymentDate': null,
      'paymentMethod': 'transfer',
      'paymentConfirmedBy': null,
      'requestDate': FieldValue.serverTimestamp(),
      'approvalDate': null,
      'approvedBy': null,
      'expirationDate': null,
      'status': 'pending',
      'notes': notes,
      'adminNotes': '',
      'scheduleDetails': scheduleDetails ?? {},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _firestore.collection('bundles').add(bundleData);
    return docRef.id;
  }

  // Approve bundle
  Future<void> approveBundle(String bundleId, String adminId) async {
    final expirationDate = DateTime.now().add(const Duration(days: 60)); // 2 months

    // Update bundle status
    await _firestore.collection('bundles').doc(bundleId).update({
      'status': 'active',
      'approvalDate': FieldValue.serverTimestamp(),
      'approvedBy': adminId,
      'expirationDate': Timestamp.fromDate(expirationDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also approve any bookings that reference this bundle
    final bookingsSnapshot = await _firestore
        .collection('bookings')
        .where('bundleId', isEqualTo: bundleId)
        .get();

    final batch = _firestore.batch();
    for (var doc in bookingsSnapshot.docs) {
      batch.update(doc.reference, {
        'status': 'approved',
        'approvedBy': adminId,
        'approvalDate': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // Approve any existing bundle sessions
    final sessionsSnapshot = await _firestore
        .collection('bundleSessions')
        .where('bundleId', isEqualTo: bundleId)
        .get();

    final sessionBatch = _firestore.batch();
    for (var doc in sessionsSnapshot.docs) {
      sessionBatch.update(doc.reference, {
        'bookingStatus': 'approved',
      });
    }
    await sessionBatch.commit();
  }

  // Confirm payment
  Future<void> confirmPayment(String bundleId, String adminId, DateTime paymentDate) async {
    await _firestore.collection('bundles').doc(bundleId).update({
      'paymentStatus': 'paid',
      'paymentDate': Timestamp.fromDate(paymentDate),
      'paymentConfirmedBy': adminId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Get user bundles
  Stream<List<TrainingBundle>> getUserBundles(String userId) {
    return _firestore
        .collection('bundles')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          // Sort in memory to avoid composite index requirement
          final bundles = snapshot.docs
              .map((doc) => TrainingBundle.fromFirestore(doc))
              .toList();
          bundles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return bundles;
        });
  }

  // Get all bundles (admin)
  Stream<List<TrainingBundle>> getAllBundles({String? statusFilter}) {
    Query query = _firestore.collection('bundles');
    
    if (statusFilter != null && statusFilter.isNotEmpty) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    
    return query
        .snapshots()
        .map((snapshot) {
          // Sort in memory to avoid composite index requirement
          final bundles = snapshot.docs
              .map((doc) => TrainingBundle.fromFirestore(doc))
              .toList();
          bundles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return bundles;
        });
  }

  // Get bundle by ID
  Future<TrainingBundle?> getBundleById(String bundleId) async {
    final doc = await _firestore.collection('bundles').doc(bundleId).get();
    if (doc.exists) {
      return TrainingBundle.fromFirestore(doc);
    }
    return null;
  }

  // Get active bundles for user
  Future<List<TrainingBundle>> getActiveBundlesForUser(String userId) async {
    // Simplified query to avoid composite index requirement
    // Query only by userId, filter everything else in memory
    final snapshot = await _firestore
        .collection('bundles')
        .where('userId', isEqualTo: userId)
        .get();

    return snapshot.docs
        .map((doc) => TrainingBundle.fromFirestore(doc))
        .where((bundle) => 
          bundle.status == 'active' && 
          bundle.remainingSessions > 0
        )
        .toList();
  }

  // Create bundle session (when booking is made)
  Future<String> createBundleSession({
    required String bundleId,
    required String userId,
    required int sessionNumber,
    required String date,
    required String time,
    required String venue,
    required String coach,
    required int playerCount,
    double extraPlayerFees = 0.0,
    String? bookingId,
    String bookingStatus = 'pending', // Default to pending, but can be overridden
  }) async {
    final sessionData = {
      'bundleId': bundleId,
      'bookingId': bookingId,
      'userId': userId,
      'sessionNumber': sessionNumber,
      'date': date,
      'time': time,
      'venue': venue,
      'coach': coach,
      'playerCount': playerCount,
      'extraPlayerFees': extraPlayerFees,
      'bookingStatus': bookingStatus,
      'attendanceStatus': 'scheduled',
      'markedBy': null,
      'markedAt': null,
      'notes': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _firestore.collection('bundleSessions').add(sessionData);
    return docRef.id;
  }

  // Mark attendance
  Future<void> markAttendance({
    required String sessionId,
    required String attendanceStatus,
    required String markedBy,
    String notes = '',
  }) async {
    await _firestore.collection('bundleSessions').doc(sessionId).update({
      'attendanceStatus': attendanceStatus,
      'markedBy': markedBy,
      'markedAt': FieldValue.serverTimestamp(),
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update bundle counters
    final session = await _firestore.collection('bundleSessions').doc(sessionId).get();
    if (session.exists) {
      final bundleId = session.data()?['bundleId'];
      if (bundleId != null) {
        await _updateBundleCounters(bundleId);
      }
    }
  }

  // Update bundle counters based on sessions
  Future<void> _updateBundleCounters(String bundleId) async {
    final sessions = await _firestore
        .collection('bundleSessions')
        .where('bundleId', isEqualTo: bundleId)
        .get();

    int attended = 0;
    int missed = 0;
    int cancelled = 0;

    for (var doc in sessions.docs) {
      final status = doc.data()['attendanceStatus'];
      if (status == 'attended') attended++;
      if (status == 'missed') missed++;
      if (status == 'cancelled') cancelled++;
    }

    final bundle = await _firestore.collection('bundles').doc(bundleId).get();
    final totalSessions = bundle.data()?['totalSessions'] ?? 0;
    final used = attended + missed;
    final remaining = totalSessions - used;

    await _firestore.collection('bundles').doc(bundleId).update({
      'usedSessions': used,
      'attendedSessions': attended,
      'missedSessions': missed,
      'cancelledSessions': cancelled,
      'remainingSessions': remaining > 0 ? remaining : 0,
      'status': remaining <= 0 ? 'completed' : 'active',
      'paymentStatus': remaining <= 0 ? 'completed' : bundle.data()?['paymentStatus'],
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Get bundle sessions
  Stream<List<BundleSession>> getBundleSessions(String bundleId) {
    return _firestore
        .collection('bundleSessions')
        .where('bundleId', isEqualTo: bundleId)
        .snapshots()
        .map((snapshot) {
          // Sort in memory to avoid composite index requirement
          final sessions = snapshot.docs
              .map((doc) => BundleSession.fromFirestore(doc))
              .toList();
          sessions.sort((a, b) => a.sessionNumber.compareTo(b.sessionNumber));
          return sessions;
        });
  }

  // Extend bundle expiration (admin only)
  Future<void> extendBundle(String bundleId, DateTime newExpirationDate) async {
    await _firestore.collection('bundles').doc(bundleId).update({
      'expirationDate': Timestamp.fromDate(newExpirationDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Cancel bundle (admin only). Rejects related bookings, revokes all bundle sessions, and notifies user.
  Future<void> cancelBundle(String bundleId, String reason) async {
    await _firestore.collection('bundles').doc(bundleId).update({
      'status': 'cancelled',
      'adminNotes': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 1. Reject all bookings linked to this bundle (releases slots)
    final bookingsSnapshot = await _firestore
        .collection('bookings')
        .where('bundleId', isEqualTo: bundleId)
        .get();

    for (final doc in bookingsSnapshot.docs) {
      final data = doc.data();
      final status = data['status'] as String? ?? '';
      if (status == 'rejected') continue;

      final userId = data['userId'] as String? ?? '';
      final venue = data['venue'] as String? ?? '';
      final time = data['time'] as String? ?? '';
      final date = data['date'] as String? ?? '';

      await doc.reference.update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        if (reason.isNotEmpty) 'rejectionReason': reason,
      });

      if (userId.isNotEmpty) {
        await NotificationService().notifyUserForBookingStatus(
          userId: userId,
          bookingId: doc.id,
          status: 'rejected',
          venue: venue,
          time: time,
          date: date,
        );
      }
    }

    // 2. Revoke all bundle sessions (so they no longer count as "booked" and disappear from My Bookings)
    final sessionsSnapshot = await _firestore
        .collection('bundleSessions')
        .where('bundleId', isEqualTo: bundleId)
        .get();

    for (final doc in sessionsSnapshot.docs) {
      await doc.reference.update({
        'bookingStatus': 'rejected',
        'attendanceStatus': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
        if (reason.isNotEmpty) 'notes': 'Bundle cancelled: $reason',
      });
    }
  }

  // Check and update expired bundles
  Future<void> checkExpiredBundles() async {
    final now = DateTime.now();
    // Simplified query - filter expiration date in memory
    final activeBundles = await _firestore
        .collection('bundles')
        .where('status', isEqualTo: 'active')
        .get();

    for (var doc in activeBundles.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final expirationDate = (data['expirationDate'] as Timestamp?)?.toDate();
      
      if (expirationDate != null && expirationDate.isBefore(now)) {
        await doc.reference.update({
          'status': 'expired',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }
}
