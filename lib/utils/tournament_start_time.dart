import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads the instant used for the home-page countdown. Set from Admin (tournament
/// edit/add) or manually in Firebase Console as field `startsAt` (timestamp).
DateTime? readTournamentStartsAt(Map<String, dynamic> data) {
  final dynamic ts = data['startsAt'] ?? data['startAt'];
  if (ts is Timestamp) return ts.toDate();
  return null;
}

class NextTournamentCountdownTarget {
  final String name;
  final DateTime target;

  const NextTournamentCountdownTarget({required this.name, required this.target});
}

/// Picks the nearest future start among visible home tournaments.
NextTournamentCountdownTarget? computeNextTournamentCountdown(
  Iterable<QueryDocumentSnapshot<Object?>> docs,
) {
  final now = DateTime.now();
  NextTournamentCountdownTarget? best;
  for (final doc in docs) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) continue;
    final status = data['status'] as String? ?? 'upcoming';
    if (status == 'completed') continue;
    final start = readTournamentStartsAt(data);
    if (start == null || !start.isAfter(now)) continue;
    if (best == null || start.isBefore(best.target)) {
      best = NextTournamentCountdownTarget(
        name: data['name'] as String? ?? 'Tournament',
        target: start,
      );
    }
  }
  return best;
}
