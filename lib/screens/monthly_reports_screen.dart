import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class MonthlyReportsScreen extends StatefulWidget {
  const MonthlyReportsScreen({super.key});

  @override
  State<MonthlyReportsScreen> createState() => _MonthlyReportsScreenState();
}

class _MonthlyReportsScreenState extends State<MonthlyReportsScreen> {
  DateTime _selectedMonth = DateTime.now();
  bool _isLoading = false;
  Map<String, dynamic> _reportData = {};

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get first and last day of month
      final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final firstDayStr = DateFormat('yyyy-MM-dd').format(firstDay);
      final lastDayStr = DateFormat('yyyy-MM-dd').format(lastDay);

      // Query training bookings
      final trainingBookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: user.uid)
          .get();

      // Query court bookings
      final courtBookingsSnapshot = await FirebaseFirestore.instance
          .collection('courtBookings')
          .where('userId', isEqualTo: user.uid)
          .get();

      // Filter by month and process data
      final trainingBookings = trainingBookingsSnapshot.docs.where((doc) {
        final date = doc.data()['date'] as String?;
        return date != null && date.compareTo(firstDayStr) >= 0 && date.compareTo(lastDayStr) <= 0;
      }).toList();

      final courtBookings = courtBookingsSnapshot.docs.where((doc) {
        final date = doc.data()['date'] as String?;
        return date != null && date.compareTo(firstDayStr) >= 0 && date.compareTo(lastDayStr) <= 0;
      }).toList();

      // Calculate statistics
      int totalTrainingBookings = trainingBookings.length;
      int approvedTrainingBookings = trainingBookings.where((doc) => doc.data()['status'] == 'approved').length;
      int pendingTrainingBookings = trainingBookings.where((doc) => doc.data()['status'] == 'pending').length;
      int rejectedTrainingBookings = trainingBookings.where((doc) => doc.data()['status'] == 'rejected').length;

      int totalCourtBookings = courtBookings.length;
      int approvedCourtBookings = courtBookings.where((doc) => doc.data()['status'] == 'approved').length;
      int pendingCourtBookings = courtBookings.where((doc) => doc.data()['status'] == 'pending').length;

      // Group by venue
      Map<String, int> trainingVenueCounts = {};
      for (var doc in trainingBookings) {
        final venue = doc.data()['venue'] as String? ?? 'Unknown';
        trainingVenueCounts[venue] = (trainingVenueCounts[venue] ?? 0) + 1;
      }

      Map<String, int> courtVenueCounts = {};
      for (var doc in courtBookings) {
        final venue = doc.data()['locationName'] as String? ?? 'Unknown';
        courtVenueCounts[venue] = (courtVenueCounts[venue] ?? 0) + 1;
      }

      // Group by booking type (Private vs Group)
      int privateBookings = trainingBookings.where((doc) => doc.data()['bookingType'] == 'Private').length;
      int groupBookings = trainingBookings.where((doc) => doc.data()['bookingType'] == 'Group').length;

      // Calculate total cost (for court bookings)
      double totalCost = 0;
      for (var doc in courtBookings) {
        final cost = (doc.data()['totalCost'] as num?)?.toDouble() ?? 0;
        totalCost += cost;
      }

      if (mounted) {
        setState(() {
          _reportData = {
            'totalTrainingBookings': totalTrainingBookings,
            'approvedTrainingBookings': approvedTrainingBookings,
            'pendingTrainingBookings': pendingTrainingBookings,
            'rejectedTrainingBookings': rejectedTrainingBookings,
            'totalCourtBookings': totalCourtBookings,
            'approvedCourtBookings': approvedCourtBookings,
            'pendingCourtBookings': pendingCourtBookings,
            'trainingVenueCounts': trainingVenueCounts,
            'courtVenueCounts': courtVenueCounts,
            'privateBookings': privateBookings,
            'groupBookings': groupBookings,
            'totalCost': totalCost,
            'trainingBookingDocs': trainingBookings,
            'courtBookingDocs': courtBookings,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _exportReport() {
    // For now, show a summary dialog
    // In a real app, you'd export to CSV/PDF
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report - ${DateFormat('MMMM yyyy').format(_selectedMonth)}'),
        content: SingleChildScrollView(
          child: Text(_generateReportText()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _generateReportText() {
    final month = DateFormat('MMMM yyyy').format(_selectedMonth);
    return '''
MONTHLY REPORT - $month

TRAINING SESSIONS:
- Total Bookings: ${_reportData['totalTrainingBookings'] ?? 0}
- Approved: ${_reportData['approvedTrainingBookings'] ?? 0}
- Pending: ${_reportData['pendingTrainingBookings'] ?? 0}
- Rejected: ${_reportData['rejectedTrainingBookings'] ?? 0}

BOOKING TYPES:
- Private: ${_reportData['privateBookings'] ?? 0}
- Group: ${_reportData['groupBookings'] ?? 0}

COURT BOOKINGS:
- Total Bookings: ${_reportData['totalCourtBookings'] ?? 0}
- Approved: ${_reportData['approvedCourtBookings'] ?? 0}
- Pending: ${_reportData['pendingCourtBookings'] ?? 0}
- Total Cost: EGP ${(_reportData['totalCost'] ?? 0).toStringAsFixed(2)}

TRAINING VENUES:
${_generateVenueList(_reportData['trainingVenueCounts'] ?? {})}

COURT LOCATIONS:
${_generateVenueList(_reportData['courtVenueCounts'] ?? {})}
''';
  }

  String _generateVenueList(Map<String, int> venues) {
    if (venues.isEmpty) return '  None';
    return venues.entries.map((e) => '  - ${e.key}: ${e.value}').join('\n');
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.7), color],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueBreakdown(String title, Map<String, int> venues) {
    if (venues.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedVenues = venues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            ...sortedVenues.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.value}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalTraining = _reportData['totalTrainingBookings'] ?? 0;
    final totalCourt = _reportData['totalCourtBookings'] ?? 0;
    final approvedTraining = _reportData['approvedTrainingBookings'] ?? 0;
    final approvedCourt = _reportData['approvedCourtBookings'] ?? 0;
    final pendingTraining = _reportData['pendingTrainingBookings'] ?? 0;
    final pendingCourt = _reportData['pendingCourtBookings'] ?? 0;
    final privateBookings = _reportData['privateBookings'] ?? 0;
    final groupBookings = _reportData['groupBookings'] ?? 0;
    final totalCost = _reportData['totalCost'] ?? 0.0;

    return Scaffold(
      appBar: const AppHeader(title: 'Monthly Reports'),
      bottomNavigationBar: const AppFooter(selectedIndex: 1),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month Selector
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                            });
                            _loadReportData();
                          },
                        ),
                        Text(
                          DateFormat('MMMM yyyy').format(_selectedMonth),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                            });
                            _loadReportData();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Summary Stats
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.2,
                    children: [
                      _buildStatCard(
                        title: 'Total Training',
                        value: '$totalTraining',
                        icon: Icons.sports_tennis,
                        color: Colors.blue,
                      ),
                      _buildStatCard(
                        title: 'Total Courts',
                        value: '$totalCourt',
                        icon: Icons.stadium,
                        color: Colors.green,
                      ),
                      _buildStatCard(
                        title: 'Approved',
                        value: '${approvedTraining + approvedCourt}',
                        icon: Icons.check_circle,
                        color: Colors.green.shade700,
                      ),
                      _buildStatCard(
                        title: 'Pending',
                        value: '${pendingTraining + pendingCourt}',
                        icon: Icons.pending,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Booking Type Breakdown
                  if (totalTraining > 0) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Training Booking Types',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Icon(Icons.lock, size: 40, color: Colors.purple),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$privateBookings',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Text('Private'),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      const Icon(Icons.group, size: 40, color: Colors.green),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$groupBookings',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Text('Group'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Court Cost Summary
                  if (totalCourt > 0) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.attach_money, size: 40, color: Color(0xFF1E3A8A)),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total Court Booking Cost',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'EGP ${totalCost.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Venue Breakdowns
                  _buildVenueBreakdown(
                    'Training Venues',
                    _reportData['trainingVenueCounts'] ?? {},
                  ),
                  _buildVenueBreakdown(
                    'Court Locations',
                    _reportData['courtVenueCounts'] ?? {},
                  ),

                  // Export Button
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _exportReport,
                      icon: const Icon(Icons.file_download),
                      label: const Text('View Full Report'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
