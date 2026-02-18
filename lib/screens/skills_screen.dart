import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'admin_screen.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

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
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppHeader(
        title: 'Player Skills',
        actions: [
          if (_isAdmin())
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit Skills',
              onPressed: () => _showEditSkillsDialog(),
            ),
        ],
      ),
      bottomNavigationBar: const AppFooter(selectedIndex: 3),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [
              const Color(0xFF0A0E27),
              const Color(0xFF1A1F3A),
            ],
          ),
        ),
        child: StreamBuilder<DocumentSnapshot>(
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
                style: TextStyle(fontSize: 16, color: Colors.white70),
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
            'Net Play': (skills['netPlay'] as num?)?.toDouble() ?? 0.0,
            'Defense': (skills['defense'] as num?)?.toDouble() ?? 0.0,
            'Intelligence': (skills['intelligence'] as num?)?.toDouble() ?? 0.0,
            'Fundamentals': (skills['fundamentals'] as num?)?.toDouble() ?? 0.0,
            'Physical/Mental': (skills['physicalMental'] as num?)?.toDouble() ?? 0.0,
          };

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Player Level Header
                const Text(
                  'Player Skills',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Advanced Competitive Player',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Overall Performance Chart (Radar)
                _buildRadarChart(
                  skills: overallSkills,
                  maxValue: 10,
                ),
                const SizedBox(height: 32),
                // Skill Improvements
                _buildSkillImprovements(attackSkills),
                const SizedBox(height: 32),
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
                const SizedBox(height: 24),
                // Training Recommendations Button
                ElevatedButton(
                  onPressed: () {
                    // Navigate to training recommendations or show dialog
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.withOpacity(0.2),
                    foregroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.green, width: 2),
                    ),
                  ),
                  child: const Text(
                    'Get Training Recommendations',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required Map<String, double> skills,
    required double maxValue,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
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
                ticksTextStyle: const TextStyle(color: Colors.white70, fontSize: 9),
                tickBorderData: null, // No border for ticks
                radarBorderData: const BorderSide(color: Colors.white30, width: 1),
                radarBackgroundColor: Colors.white.withOpacity(0.05),
                titleTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                getTitle: (index, angle) {
                  final label = skills.keys.elementAt(index);
                  final displayText = label == 'Physical/Mental' ? 'Physical\nMental' : label;
                  double offset = 0.25;
                  if (label == 'Physical/Mental') {
                    offset = 0.35;
                  } else if (label == 'Fundamentals') {
                    offset = 0.30;
                  } else if (label == 'Intelligence') {
                    offset = 0.19;
                  } else if (label == 'Attack') {
                    offset = 0.19;
                  }
                  return RadarChartTitle(
                    text: displayText,
                    angle: 0,
                    positionPercentageOffset: offset,
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
                    '${entry.key == 'Physical/Mental' ? 'Physical\nMental' : entry.key}: ${entry.value.toStringAsFixed(1)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarChart({
    required Map<String, double> skills,
    required double maxValue,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 300,
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.green.withOpacity(0.3),
                    borderColor: Colors.green,
                    borderWidth: 3,
                    dataEntries: skills.values.map((value) => RadarEntry(value: value.clamp(0.0, maxValue))).toList(),
                  ),
                ],
                tickCount: 5,
                ticksTextStyle: const TextStyle(color: Colors.white70, fontSize: 9),
                tickBorderData: null,
                radarBorderData: const BorderSide(color: Colors.white30, width: 1),
                radarBackgroundColor: Colors.white.withOpacity(0.05),
                titleTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                getTitle: (index, angle) {
                  final label = skills.keys.elementAt(index);
                  final displayText = label == 'Physical/Mental' ? 'Physical\nMental' : label;
                  double offset = 0.25;
                  if (label == 'Physical/Mental') {
                    offset = 0.35;
                  } else if (label == 'Fundamentals') {
                    offset = 0.30;
                  } else if (label == 'Intelligence') {
                    offset = 0.19;
                  } else if (label == 'Attack') {
                    offset = 0.19;
                  }
                  return RadarChartTitle(
                    text: displayText,
                    angle: 0,
                    positionPercentageOffset: offset,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillImprovements(Map<String, double> skills) {
    // Calculate improvements (mock data for now)
    final improvements = [
      {'name': 'Bajada', 'value': 12},
      {'name': 'Vibora', 'value': 10},
      {'name': 'Rulo', 'value': 8},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: improvements.map((improvement) {
          return Column(
            children: [
              const Icon(Icons.trending_up, color: Color(0xFFFFC400), size: 24),
              const SizedBox(height: 8),
              Text(
                '↑ ${improvement['name']}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '+${improvement['value']}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFC400),
                ),
              ),
            ],
          );
        }).toList(),
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

