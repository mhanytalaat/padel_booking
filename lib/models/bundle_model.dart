import 'package:cloud_firestore/cloud_firestore.dart';

class TrainingBundle {
  final String id;
  final String userId;
  final String userName;
  final String userPhone;
  final int bundleType; // 1, 4, or 8
  final int playerCount; // 1-4
  final int totalSessions;
  final int usedSessions;
  final int attendedSessions;
  final int missedSessions;
  final int cancelledSessions;
  final int remainingSessions;
  final double price;
  final String paymentStatus; // pending/paid/completed
  final DateTime? paymentDate;
  final String paymentMethod;
  final String? paymentConfirmedBy;
  final DateTime requestDate;
  final DateTime? approvalDate;
  final String? approvedBy;
  final DateTime? expirationDate;
  final String status; // pending/active/completed/expired/cancelled
  final String notes;
  final String adminNotes;
  final Map<String, dynamic>? scheduleDetails; // Stores venue, coach, startDate, dayTimeSchedule
  final DateTime createdAt;
  final DateTime updatedAt;

  TrainingBundle({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.bundleType,
    required this.playerCount,
    required this.totalSessions,
    required this.usedSessions,
    required this.attendedSessions,
    required this.missedSessions,
    required this.cancelledSessions,
    required this.remainingSessions,
    required this.price,
    required this.paymentStatus,
    this.paymentDate,
    required this.paymentMethod,
    this.paymentConfirmedBy,
    required this.requestDate,
    this.approvalDate,
    this.approvedBy,
    this.expirationDate,
    required this.status,
    required this.notes,
    required this.adminNotes,
    this.scheduleDetails,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrainingBundle.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TrainingBundle(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userPhone: data['userPhone'] ?? '',
      bundleType: data['bundleType'] ?? 1,
      playerCount: data['playerCount'] ?? 1,
      totalSessions: data['totalSessions'] ?? 0,
      usedSessions: data['usedSessions'] ?? 0,
      attendedSessions: data['attendedSessions'] ?? 0,
      missedSessions: data['missedSessions'] ?? 0,
      cancelledSessions: data['cancelledSessions'] ?? 0,
      remainingSessions: data['remainingSessions'] ?? 0,
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: data['paymentStatus'] ?? 'pending',
      paymentDate: (data['paymentDate'] as Timestamp?)?.toDate(),
      paymentMethod: data['paymentMethod'] ?? 'transfer',
      paymentConfirmedBy: data['paymentConfirmedBy'],
      requestDate: (data['requestDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      approvalDate: (data['approvalDate'] as Timestamp?)?.toDate(),
      approvedBy: data['approvedBy'],
      expirationDate: (data['expirationDate'] as Timestamp?)?.toDate(),
      status: data['status'] ?? 'pending',
      notes: data['notes'] ?? '',
      adminNotes: data['adminNotes'] ?? '',
      scheduleDetails: data['scheduleDetails'] as Map<String, dynamic>?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'bundleType': bundleType,
      'playerCount': playerCount,
      'totalSessions': totalSessions,
      'usedSessions': usedSessions,
      'attendedSessions': attendedSessions,
      'missedSessions': missedSessions,
      'cancelledSessions': cancelledSessions,
      'remainingSessions': remainingSessions,
      'price': price,
      'paymentStatus': paymentStatus,
      'paymentDate': paymentDate != null ? Timestamp.fromDate(paymentDate!) : null,
      'paymentMethod': paymentMethod,
      'paymentConfirmedBy': paymentConfirmedBy,
      'requestDate': Timestamp.fromDate(requestDate),
      'approvalDate': approvalDate != null ? Timestamp.fromDate(approvalDate!) : null,
      'approvedBy': approvedBy,
      'expirationDate': expirationDate != null ? Timestamp.fromDate(expirationDate!) : null,
      'status': status,
      'notes': notes,
      'adminNotes': adminNotes,
      'scheduleDetails': scheduleDetails,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  bool get isExpired {
    if (expirationDate == null) return false;
    return DateTime.now().isAfter(expirationDate!);
  }

  bool get isExpiringSoon {
    if (expirationDate == null) return false;
    final daysUntilExpiry = expirationDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 7 && daysUntilExpiry > 0;
  }

  bool get isAlmostFinished {
    return remainingSessions == 1 && status == 'active';
  }

  String get statusDisplay {
    switch (status) {
      case 'pending':
        return 'Pending Approval';
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  String get paymentStatusDisplay {
    switch (paymentStatus) {
      case 'pending':
        return 'Pending Payment';
      case 'paid':
        return 'Paid';
      case 'completed':
        return 'Completed';
      default:
        return paymentStatus;
    }
  }
}

class BundleSession {
  final String id;
  final String bundleId;
  final String? bookingId;
  final String userId;
  final int sessionNumber;
  final String date;
  final String time;
  final String venue;
  final String coach;
  final int playerCount;
  final double extraPlayerFees;
  final String bookingStatus; // pending/approved/rejected
  final String attendanceStatus; // scheduled/attended/missed/cancelled
  final String? markedBy;
  final DateTime? markedAt;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  BundleSession({
    required this.id,
    required this.bundleId,
    this.bookingId,
    required this.userId,
    required this.sessionNumber,
    required this.date,
    required this.time,
    required this.venue,
    required this.coach,
    required this.playerCount,
    required this.extraPlayerFees,
    required this.bookingStatus,
    required this.attendanceStatus,
    this.markedBy,
    this.markedAt,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BundleSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BundleSession(
      id: doc.id,
      bundleId: data['bundleId'] ?? '',
      bookingId: data['bookingId'],
      userId: data['userId'] ?? '',
      sessionNumber: data['sessionNumber'] ?? 0,
      date: data['date'] ?? '',
      time: data['time'] ?? '',
      venue: data['venue'] ?? '',
      coach: data['coach'] ?? '',
      playerCount: data['playerCount'] ?? 1,
      extraPlayerFees: (data['extraPlayerFees'] as num?)?.toDouble() ?? 0.0,
      bookingStatus: data['bookingStatus'] ?? 'pending',
      attendanceStatus: data['attendanceStatus'] ?? 'scheduled',
      markedBy: data['markedBy'],
      markedAt: (data['markedAt'] as Timestamp?)?.toDate(),
      notes: data['notes'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
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
      'attendanceStatus': attendanceStatus,
      'markedBy': markedBy,
      'markedAt': markedAt != null ? Timestamp.fromDate(markedAt!) : null,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
