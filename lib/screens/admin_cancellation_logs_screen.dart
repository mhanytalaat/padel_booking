import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Admin tab: list of court booking cancellations (app or external API).
/// Data from Firestore collection courtBookingCancellationLogs.
class AdminCancellationLogsScreen extends StatelessWidget {
  const AdminCancellationLogsScreen({super.key});

  static const String _collection = 'courtBookingCancellationLogs';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                'Court booking cancellations',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'App + External API',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection(_collection)
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error: ${snapshot.error}. Ensure Firestore rules allow read on $_collection for admins.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No cancellations logged yet'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  return _CancellationLogCard(data: data);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CancellationLogCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _CancellationLogCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final locationName = data['locationName'] as String? ?? '—';
    final date = data['date'] as String? ?? '';
    final source = data['source'] as String? ?? 'unknown';
    final cancelledAt = data['cancelledAt'];
    final guestName = data['guestName'] as String?;
    final guestPhone = data['guestPhone'] as String?;
    final courts = data['courts'];
    final timeRange = data['timeRange'] as String?;
    final bookingId = data['bookingId'] as String? ?? '';

    final isExternal = source == 'external_api';
    final sourceLabel = isExternal ? 'External API' : 'App';
    final sourceColor = isExternal ? Colors.purple : Colors.blue;

    String courtsSummary = '—';
    if (courts is Map && courts.isNotEmpty) {
      final parts = <String>[];
      for (final e in (courts as Map).entries) {
        final list = e.value is List ? (e.value as List).length : 0;
        parts.add('${e.key}: $list slot(s)');
      }
      courtsSummary = parts.join(' · ');
    }

    String whenStr = '';
    if (cancelledAt != null) {
      if (cancelledAt is Timestamp) {
        whenStr = DateFormat('dd/MM/yyyy HH:mm').format(cancelledAt.toDate());
      } else {
        whenStr = cancelledAt.toString();
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cancel_outlined,
                  color: sourceColor,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    locationName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: sourceColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    sourceLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: sourceColor,
                    ),
                  ),
                ),
              ],
            ),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Date: $date', style: const TextStyle(fontSize: 14)),
            ],
            if (courtsSummary != '—') ...[
              const SizedBox(height: 4),
              Text('Courts: $courtsSummary', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
            if (timeRange != null && timeRange.toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Time: $timeRange', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
            if (guestName != null && guestName.toString().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Guest: $guestName', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            ],
            if (guestPhone != null && guestPhone.toString().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Phone: $guestPhone', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
            if (whenStr.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Cancelled at: $whenStr',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (bookingId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ID: $bookingId',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
