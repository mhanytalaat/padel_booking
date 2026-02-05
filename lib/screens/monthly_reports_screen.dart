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
  bool _isAdmin = false;
  bool _isSubAdmin = false;
  List<String> _subAdminLocationIds = [];

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  Future<void> _checkAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if main admin
    final isMainAdmin = user.phoneNumber == '+201006500506' || user.email == 'admin@padelcore.com';
    
    // Check if sub-admin
    bool isSubAdminForAnyLocation = false;
    List<String> subAdminLocationIds = [];
    
    try {
      final locationsSnapshot = await FirebaseFirestore.instance
          .collection('courtLocations')
          .get();
      
      for (var doc in locationsSnapshot.docs) {
        final data = doc.data();
        final subAdmins = (data['subAdmins'] as List<dynamic>?) ?? [];
        if (subAdmins.contains(user.uid)) {
          subAdminLocationIds.add(doc.id);
          isSubAdminForAnyLocation = true;
        }
      }
    } catch (e) {
      if (!e.toString().contains('permission-denied')) {
        debugPrint('Error checking sub-admin access: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _isAdmin = isMainAdmin;
        _isSubAdmin = isSubAdminForAnyLocation;
        _subAdminLocationIds = subAdminLocationIds;
      });
      _loadReportData();
    }
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

      // Query court bookings based on user role
      List<QueryDocumentSnapshot> allCourtBookings = [];
      
      if (_isAdmin) {
        // Main admin sees all court bookings
        final snapshot = await FirebaseFirestore.instance
            .collection('courtBookings')
            .get();
        allCourtBookings = snapshot.docs;
      } else if (_isSubAdmin && _subAdminLocationIds.isNotEmpty) {
        // Sub-admin sees only their assigned locations
        if (_subAdminLocationIds.length == 1) {
          // Single location - simple query
          final snapshot = await FirebaseFirestore.instance
              .collection('courtBookings')
              .where('locationId', isEqualTo: _subAdminLocationIds.first)
              .get();
          allCourtBookings = snapshot.docs;
        } else if (_subAdminLocationIds.length <= 10) {
          // Multiple locations (up to 10) - use whereIn
          final snapshot = await FirebaseFirestore.instance
              .collection('courtBookings')
              .where('locationId', whereIn: _subAdminLocationIds)
              .get();
          allCourtBookings = snapshot.docs;
        } else {
          // More than 10 locations - make multiple queries
          for (int i = 0; i < _subAdminLocationIds.length; i += 10) {
            final batch = _subAdminLocationIds.skip(i).take(10).toList();
            final snapshot = await FirebaseFirestore.instance
                .collection('courtBookings')
                .where('locationId', whereIn: batch)
                .get();
            allCourtBookings.addAll(snapshot.docs);
          }
        }
      } else {
        // Regular user sees their own bookings
        final snapshot = await FirebaseFirestore.instance
            .collection('courtBookings')
            .where('userId', isEqualTo: user.uid)
            .get();
        allCourtBookings = snapshot.docs;
      }

      // Filter by month
      final courtBookings = allCourtBookings.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final date = data['date'] as String?;
        
        // Check date range
        return date != null && date.compareTo(firstDayStr) >= 0 && date.compareTo(lastDayStr) <= 0;
      }).toList();

      // Calculate statistics
      int totalCourtBookings = courtBookings.length;
      int confirmedCourtBookings = courtBookings.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return data['status'] == 'confirmed';
      }).length;

      // Group by venue
      Map<String, int> courtVenueCounts = {};
      for (var doc in courtBookings) {
        final data = doc.data() as Map<String, dynamic>;
        final venue = data['locationName'] as String? ?? 'Unknown';
        courtVenueCounts[venue] = (courtVenueCounts[venue] ?? 0) + 1;
      }

      // Group by user
      Map<String, Map<String, dynamic>> userBookings = {};
      for (var doc in courtBookings) {
        final data = doc.data() as Map<String, dynamic>;
        final userId = data['userId'] as String? ?? 'Unknown';
        if (!userBookings.containsKey(userId)) {
          userBookings[userId] = {
            'count': 0,
            'totalCost': 0.0,
            'userId': userId,
          };
        }
        userBookings[userId]!['count'] = (userBookings[userId]!['count'] as int) + 1;
        final cost = (data['totalCost'] as num?)?.toDouble() ?? 0;
        userBookings[userId]!['totalCost'] = (userBookings[userId]!['totalCost'] as double) + cost;
      }

      // Group by court
      Map<String, int> courtCounts = {};
      for (var doc in courtBookings) {
        final data = doc.data() as Map<String, dynamic>;
        final courts = data['courts'] as Map<String, dynamic>?;
        if (courts != null) {
          for (var courtName in courts.keys) {
            courtCounts[courtName] = (courtCounts[courtName] ?? 0) + 1;
          }
        }
      }

      // Calculate total income (for court bookings)
      double totalIncome = 0;
      for (var doc in courtBookings) {
        final data = doc.data() as Map<String, dynamic>;
        final cost = (data['totalCost'] as num?)?.toDouble() ?? 0;
        totalIncome += cost;
      }

      if (mounted) {
        setState(() {
          _reportData = {
            'totalCourtBookings': totalCourtBookings,
            'confirmedCourtBookings': confirmedCourtBookings,
            'courtVenueCounts': courtVenueCounts,
            'totalIncome': totalIncome,
            'courtBookingDocs': courtBookings,
            'userBookings': userBookings,
            'courtCounts': courtCounts,
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
    final userBookings = _reportData['userBookings'] as Map<String, Map<String, dynamic>>? ?? {};
    final courtCounts = _reportData['courtCounts'] as Map<String, int>? ?? {};
    
    return '''
MONTHLY REPORT - $month
${_isSubAdmin && !_isAdmin ? '(Sub-Admin Report - Assigned Locations Only)' : ''}

COURT BOOKINGS:
- Total Bookings: ${_reportData['totalCourtBookings'] ?? 0}
- Confirmed: ${_reportData['confirmedCourtBookings'] ?? 0}
- Total Income: EGP ${(_reportData['totalIncome'] ?? 0).toStringAsFixed(2)}

COURT LOCATIONS:
${_generateVenueList(_reportData['courtVenueCounts'] ?? {})}

BOOKINGS BY USER:
${_generateUserBookingsList(userBookings)}

BOOKINGS BY COURT:
${_generateVenueList(courtCounts)}
''';
  }

  String _generateUserBookingsList(Map<String, Map<String, dynamic>> userBookings) {
    if (userBookings.isEmpty) return '  None';
    return userBookings.entries.map((e) {
      final count = e.value['count'];
      final cost = e.value['totalCost'] as double;
      return '  - User ${e.key.substring(0, 8)}...: $count booking(s), EGP ${cost.toStringAsFixed(2)}';
    }).join('\n');
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

  Widget _buildUserBreakdown() {
    final userBookings = _reportData['userBookings'] as Map<String, Map<String, dynamic>>? ?? {};
    if (userBookings.isEmpty) return const SizedBox.shrink();

    final sortedUsers = userBookings.entries.toList()
      ..sort((a, b) => (b.value['count'] as int).compareTo(a.value['count'] as int));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bookings by User',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ...sortedUsers.take(10).map((entry) {
              final userId = entry.key;
              final count = entry.value['count'] as int;
              final cost = entry.value['totalCost'] as double;
              
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
                builder: (context, snapshot) {
                  String userName = 'User ${userId.substring(0, 8)}...';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final userData = snapshot.data!.data() as Map<String, dynamic>?;
                    userName = userData?['fullName'] ?? userData?['firstName'] ?? userName;
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(userName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                              Text('$count booking(s) • EGP ${cost.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A8A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCourtBreakdown() {
    final courtCounts = _reportData['courtCounts'] as Map<String, int>? ?? {};
    if (courtCounts.isEmpty) return const SizedBox.shrink();

    final sortedCourts = courtCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bookings by Court', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            ...sortedCourts.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(child: Text(entry.key, style: const TextStyle(fontSize: 14))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${entry.value}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final totalCourt = _reportData['totalCourtBookings'] ?? 0;
    final confirmedCourt = _reportData['confirmedCourtBookings'] ?? 0;
    final totalIncome = _reportData['totalIncome'] ?? 0.0;

    return Scaffold(
      appBar: AppHeader(
        title: _isSubAdmin && !_isAdmin ? 'Monthly Reports (Sub-Admin)' : 'Monthly Reports',
      ),
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
                        title: 'Total Bookings',
                        value: '$totalCourt',
                        icon: Icons.stadium,
                        color: Colors.blue,
                      ),
                      _buildStatCard(
                        title: 'Confirmed',
                        value: '$confirmedCourt',
                        icon: Icons.check_circle,
                        color: Colors.green.shade700,
                      ),
                      _buildStatCard(
                        title: 'Total Income',
                        value: 'EGP ${totalIncome.toStringAsFixed(0)}',
                        icon: Icons.attach_money,
                        color: const Color(0xFF1E3A8A),
                      ),
                      _buildStatCard(
                        title: 'Locations',
                        value: '${(_reportData['courtVenueCounts'] as Map? ?? {}).length}',
                        icon: Icons.location_city,
                        color: Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Total Income Summary
                  if (totalCourt > 0) ...[
                    Card(
                      elevation: 6,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet, size: 48, color: Colors.white),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Total Revenue',
                                  style: TextStyle(fontSize: 14, color: Colors.white70),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'EGP ${totalIncome.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'from $totalCourt booking${totalCourt > 1 ? 's' : ''}',
                                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Per-User Breakdown
                  _buildUserBreakdown(),

                  // Per-Court Breakdown
                  _buildCourtBreakdown(),

                  // Venue Breakdowns
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
