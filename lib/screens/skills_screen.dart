import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'admin_screen.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  final user = FirebaseAuth.instance.currentUser;
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com';
  
  bool _isAdmin() {
    if (user == null) return false;
    return user!.phoneNumber == adminPhone || user!.email == adminEmail;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Skills'),
        actions: [
          if (_isAdmin())
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Skills',
              onPressed: () => _showEditSkillsDialog(),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user?.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                'No skills data available.\nContact admin to add your skills.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final skills = userData?['skills'] as Map<String, dynamic>? ?? {};
          
          // Attack Skills
          final attackSkills = {
            'Bajada': (skills['bajada'] as num?)?.toDouble() ?? 0.0,
            'Vibora': (skills['vibora'] as num?)?.toDouble() ?? 0.0,
            'Smash': (skills['smash'] as num?)?.toDouble() ?? 0.0,
            'Rulo': (skills['rulo'] as num?)?.toDouble() ?? 0.0,
            'Gancho': (skills['gancho'] as num?)?.toDouble() ?? 0.0,
          };

          // Overall Performance
          final overallSkills = {
            'Attack': (skills['attack'] as num?)?.toDouble() ?? 0.0,
            'Defense': (skills['defense'] as num?)?.toDouble() ?? 0.0,
            'Net Play': (skills['netPlay'] as num?)?.toDouble() ?? 0.0,
            'Fundamentals': (skills['fundamentals'] as num?)?.toDouble() ?? 0.0,
            'Intelligence': (skills['intelligence'] as num?)?.toDouble() ?? 0.0,
            'Physical/Mental': (skills['physicalMental'] as num?)?.toDouble() ?? 0.0,
          };

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Attack Skills Chart
                _buildChartCard(
                  title: 'ATTACK SKILL',
                  skills: attackSkills,
                  maxValue: 10,
                ),
                const SizedBox(height: 24),
                // Overall Performance Chart
                _buildChartCard(
                  title: 'OVERALL PERFORMANCE',
                  skills: overallSkills,
                  maxValue: 10,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required Map<String, double> skills,
    required double maxValue,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A8A),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: RadarChart(
                RadarChartData(
                  dataSets: [
                    RadarDataSet(
                      fillColor: const Color(0xFF4CAF50).withOpacity(0.3),
                      borderColor: const Color(0xFF1E3A8A),
                      borderWidth: 2,
                      dataEntries: skills.values.map((value) => RadarEntry(value: value.clamp(0.0, maxValue))).toList(),
                    ),
                  ],
                  tickCount: 3,
                  ticksTextStyle: const TextStyle(color: Colors.grey, fontSize: 10),
                  tickBorderData: null, // No border for ticks
                  radarBorderData: const BorderSide(color: Colors.grey, width: 1),
                  radarBackgroundColor: Colors.grey.withOpacity(0.1),
                  titleTextStyle: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  getTitle: (index, angle) {
                    return RadarChartTitle(
                      text: skills.keys.elementAt(index),
                      angle: angle,
                      positionPercentageOffset: 0.15,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Legend with values
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: skills.entries.map((entry) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withOpacity(0.3),
                        border: Border.all(color: const Color(0xFF1E3A8A), width: 1),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.key}: ${entry.value.toStringAsFixed(1)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSkillsDialog() {
    // Navigate to admin panel Skills tab
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const AdminScreen(),
      ),
    );
  }
}

