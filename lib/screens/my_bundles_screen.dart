import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bundle_model.dart';
import '../services/bundle_service.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/bundle_selector_dialog.dart';
import 'package:intl/intl.dart';

class MyBundlesScreen extends StatefulWidget {
  const MyBundlesScreen({super.key});

  @override
  State<MyBundlesScreen> createState() => _MyBundlesScreenState();
}

class _MyBundlesScreenState extends State<MyBundlesScreen> {
  final BundleService _bundleService = BundleService();
  final user = FirebaseAuth.instance.currentUser;
  String _filter = 'all'; // all, active, completed, expired

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        appBar: AppHeader(title: 'My Training Bundles'),
        body: const Center(
          child: Text('Please log in to view your bundles'),
        ),
      );
    }

    return Scaffold(
      appBar: AppHeader(title: 'My Training Bundles'),
      bottomNavigationBar: const AppFooter(selectedIndex: 1),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _requestNewBundle,
        icon: const Icon(Icons.add),
        label: const Text('Request Bundle'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: StreamBuilder<List<TrainingBundle>>(
              stream: _bundleService.getUserBundles(user!.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState();
                }

                final bundles = _filterBundles(snapshot.data!);

                if (bundles.isEmpty) {
                  return Center(
                    child: Text('No $_filter bundles'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: bundles.length,
                  itemBuilder: (context, index) {
                    return _buildBundleCard(bundles[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('All', 'all'),
            const SizedBox(width: 8),
            _buildFilterChip('Active', 'active'),
            const SizedBox(width: 8),
            _buildFilterChip('Pending', 'pending'),
            const SizedBox(width: 8),
            _buildFilterChip('Completed', 'completed'),
            const SizedBox(width: 8),
            _buildFilterChip('Expired', 'expired'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filter = value;
        });
      },
      backgroundColor: Colors.grey[200],
      selectedColor: Colors.blue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  List<TrainingBundle> _filterBundles(List<TrainingBundle> bundles) {
    if (_filter == 'all') return bundles;
    return bundles.where((b) => b.status == _filter).toList();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.card_membership_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'No Training Bundles',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Request your first training bundle',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _requestNewBundle,
            icon: const Icon(Icons.add),
            label: const Text('Request Bundle'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBundleCard(TrainingBundle bundle) {
    final progress = bundle.totalSessions > 0
        ? bundle.usedSessions / bundle.totalSessions
        : 0.0;

    Color statusColor;
    switch (bundle.status) {
      case 'active':
        statusColor = Colors.green;
        break;
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'completed':
        statusColor = Colors.blue;
        break;
      case 'expired':
        statusColor = Colors.red;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showBundleDetails(bundle),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${bundle.bundleType} Session Bundle',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${bundle.playerCount} Player${bundle.playerCount > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      bundle.statusDisplay,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${bundle.usedSessions}/${bundle.totalSessions} sessions used',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${bundle.remainingSessions} remaining',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        bundle.status == 'expired' ? Colors.red : Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Details
              Row(
                children: [
                  Expanded(
                    child: _buildInfoChip(
                      Icons.check_circle_outline,
                      '${bundle.attendedSessions} Attended',
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoChip(
                      Icons.cancel_outlined,
                      '${bundle.missedSessions} Missed',
                      Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Payment status
              Row(
                children: [
                  Icon(
                    bundle.paymentStatus == 'paid'
                        ? Icons.payment
                        : Icons.pending_actions,
                    size: 16,
                    color: bundle.paymentStatus == 'paid'
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    bundle.paymentStatusDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      color: bundle.paymentStatus == 'paid'
                          ? Colors.green
                          : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${bundle.price.toStringAsFixed(0)} EGP',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),

              // Expiration warning
              if (bundle.isExpiringSoon) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange[700], size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Expires on ${DateFormat('MMM dd, yyyy').format(bundle.expirationDate!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[900],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (bundle.isExpired) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700], size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Bundle expired',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showBundleDetails(TrainingBundle bundle) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return StreamBuilder<List<BundleSession>>(
            stream: _bundleService.getBundleSessions(bundle.id),
            builder: (context, sessionsSnapshot) {
              final sessions = sessionsSnapshot.data ?? [];

              return SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title
                      Text(
                        'Bundle Details',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${bundle.bundleType} Sessions - ${bundle.playerCount} Player${bundle.playerCount > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Stats
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'Total',
                              bundle.totalSessions.toString(),
                              Icons.format_list_numbered,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              'Used',
                              bundle.usedSessions.toString(),
                              Icons.done_all,
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              'Remaining',
                              bundle.remainingSessions.toString(),
                              Icons.pending_actions,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Session history
                      const Text(
                        'Session History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (sessions.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No sessions booked yet',
                              style: TextStyle(
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        )
                      else
                        ...sessions.map((session) => _buildSessionTile(session)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(BundleSession session) {
    Color statusColor;
    IconData statusIcon;

    switch (session.attendanceStatus) {
      case 'attended':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'missed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        statusIcon = Icons.block;
        break;
      default:
        statusColor = Colors.blue;
        statusIcon = Icons.schedule;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.2),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text('Session ${session.sessionNumber}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${session.venue} - ${session.coach}'),
            Text('${session.date} at ${session.time}'),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            session.attendanceStatus.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestNewBundle() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const BundleSelectorDialog(),
    );

    if (result != null && user != null) {
      try {
        // Get user profile from server so Firebase Console updates show immediately
        final userProfile = await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get(const GetOptions(source: Source.server));
        final userData = userProfile.data() as Map<String, dynamic>?;
        final firstName = userData?['firstName'] as String? ?? '';
        final lastName = userData?['lastName'] as String? ?? '';
        final combined = '$firstName $lastName'.trim();
        final fullName = (userData?['fullName'] as String?)?.trim() ?? '';
        final userName = combined.isNotEmpty
            ? combined
            : (fullName.isNotEmpty ? fullName : (user!.phoneNumber ?? 'User'));
        final userPhone = userData?['phone'] as String? ?? user!.phoneNumber ?? '';

        await _bundleService.createBundleRequest(
          userId: user!.uid,
          userName: userName,
          userPhone: userPhone,
          bundleType: result['sessions'],
          playerCount: result['players'],
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bundle request submitted! Waiting for admin approval.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error requesting bundle: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
