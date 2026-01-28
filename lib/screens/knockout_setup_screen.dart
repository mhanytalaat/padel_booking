import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Knockout Setup Screen for configuring the bracket
/// Quarter Finals → Semi Finals → Final
class KnockoutSetupScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;

  const KnockoutSetupScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<KnockoutSetupScreen> createState() => _KnockoutSetupScreenState();
}

class _KnockoutSetupScreenState extends State<KnockoutSetupScreen> {
  bool _loading = false;

  // Quarter Finals (4 matches)
  final List<KnockoutMatchConfig> _quarterFinals = [
    KnockoutMatchConfig(
      id: 'qf1',
      name: 'Quarter Final 1',
      team1Type: 'winner',
      team1From: 'Group A',
      team2Type: 'runnerUp',
      team2From: 'Group B',
    ),
    KnockoutMatchConfig(
      id: 'qf2',
      name: 'Quarter Final 2',
      team1Type: 'winner',
      team1From: 'Group B',
      team2Type: 'runnerUp',
      team2From: 'Group A',
    ),
    KnockoutMatchConfig(
      id: 'qf3',
      name: 'Quarter Final 3',
      team1Type: 'winner',
      team1From: 'Group C',
      team2Type: 'runnerUp',
      team2From: 'Group D',
    ),
    KnockoutMatchConfig(
      id: 'qf4',
      name: 'Quarter Final 4',
      team1Type: 'winner',
      team1From: 'Group D',
      team2Type: 'runnerUp',
      team2From: 'Group C',
    ),
  ];

  // Semi Finals (2 matches)
  final List<KnockoutMatchConfig> _semiFinals = [
    KnockoutMatchConfig(
      id: 'sf1',
      name: 'Semi Final 1',
      team1Type: 'winner',
      team1From: 'qf1',
      team2Type: 'winner',
      team2From: 'qf4',
    ),
    KnockoutMatchConfig(
      id: 'sf2',
      name: 'Semi Final 2',
      team1Type: 'winner',
      team1From: 'qf2',
      team2Type: 'winner',
      team2From: 'qf3',
    ),
  ];

  // Final (1 match)
  late KnockoutMatchConfig _final;

  @override
  void initState() {
    super.initState();
    _final = KnockoutMatchConfig(
      id: 'final',
      name: 'Final',
      team1Type: 'winner',
      team1From: 'sf1',
      team2Type: 'winner',
      team2From: 'sf2',
    );
    _loadExistingConfiguration();
  }

  Future<void> _loadExistingConfiguration() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final knockout = data['knockout'] as Map<String, dynamic>?;
        
        if (knockout != null) {
          // Load Quarter Finals
          final qfList = knockout['quarterFinals'] as List<dynamic>?;
          if (qfList != null) {
            for (int i = 0; i < qfList.length && i < _quarterFinals.length; i++) {
              _quarterFinals[i].loadFromFirestore(qfList[i] as Map<String, dynamic>);
            }
          }

          // Load Semi Finals
          final sfList = knockout['semiFinals'] as List<dynamic>?;
          if (sfList != null) {
            for (int i = 0; i < sfList.length && i < _semiFinals.length; i++) {
              _semiFinals[i].loadFromFirestore(sfList[i] as Map<String, dynamic>);
            }
          }

          // Load Final
          final finalData = knockout['final'] as Map<String, dynamic>?;
          if (finalData != null) {
            _final.loadFromFirestore(finalData);
          }

          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('Error loading existing configuration: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Knockout Setup - ${widget.tournamentName}'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  color: Color(0xFFFFF3E0),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🏅 KNOCKOUT STAGE',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Configure the elimination bracket:\n• Quarter Finals (4 matches)\n• Semi Finals (2 matches)\n• Final (1 match)',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Quarter Finals
                _buildStageHeader('Quarter Finals', Icons.filter_4, Colors.orange),
                ..._quarterFinals.map((match) => _buildMatchCard(match)),
                
                const SizedBox(height: 24),
                
                // Semi Finals
                _buildStageHeader('Semi Finals', Icons.filter_2, Colors.deepOrange),
                ..._semiFinals.map((match) => _buildMatchCard(match)),
                
                const SizedBox(height: 24),
                
                // Final
                _buildStageHeader('Final', Icons.emoji_events, Colors.amber),
                _buildMatchCard(_final),
                
                const SizedBox(height: 24),
                _buildSaveButton(),
              ],
            ),
    );
  }

  Widget _buildStageHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(KnockoutMatchConfig match) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.sports_tennis, color: Colors.orange),
        title: Text(
          match.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${match.court} | ${match.startTime}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Team 1
                _buildTeamInfo(
                  teamNumber: 1,
                  type: match.team1Type,
                  from: match.team1From,
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Team 2
                _buildTeamInfo(
                  teamNumber: 2,
                  type: match.team2Type,
                  from: match.team2From,
                ),
                
                const Divider(height: 32),
                
                // Court and Time
                const Text(
                  'Match Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: match.courtController,
                  decoration: const InputDecoration(
                    labelText: 'Court',
                    hintText: 'e.g., Court 1',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    match.court = value;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: match.startTimeController,
                        decoration: const InputDecoration(
                          labelText: 'Start Time',
                          hintText: '10:50 PM',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          match.startTime = value;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: match.endTimeController,
                        decoration: const InputDecoration(
                          labelText: 'End Time',
                          hintText: '11:45 PM',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          match.endTime = value;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamInfo({
    required int teamNumber,
    required String type,
    required String from,
  }) {
    final isWinner = type == 'winner';
    final displayType = isWinner ? 'Winner' : 'Runner-up';
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWinner ? Colors.amber[50] : Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWinner ? Colors.amber : Colors.orange,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isWinner ? Colors.amber : Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$teamNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team $teamNumber',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '$displayType of $from',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  'Will be filled after previous stage',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isWinner ? Icons.emoji_events : Icons.military_tech,
            color: isWinner ? Colors.amber : Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _saveConfiguration,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      child: const Text('💾 Save Knockout Configuration'),
    );
  }

  Future<void> _saveConfiguration() async {
    setState(() {
      _loading = true;
    });

    try {
      // Build Knockout data structure
      final knockoutData = {
        'quarterFinals': _quarterFinals.map((match) => match.toMap()).toList(),
        'semiFinals': _semiFinals.map((match) => match.toMap()).toList(),
        'final': _final.toMap(),
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'knockout': knockoutData,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Knockout configuration saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving configuration: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }
}

/// Configuration class for knockout match
class KnockoutMatchConfig {
  final String id;
  final String name;
  
  String team1Type;
  String team1From;
  String? team1Key;
  
  String team2Type;
  String team2From;
  String? team2Key;
  
  String? winner;
  
  String court = '';
  String startTime = '';
  String endTime = '';

  final TextEditingController courtController = TextEditingController();
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();

  KnockoutMatchConfig({
    required this.id,
    required this.name,
    required this.team1Type,
    required this.team1From,
    required this.team2Type,
    required this.team2From,
  });

  void loadFromFirestore(Map<String, dynamic> data) {
    final team1 = data['team1'] as Map<String, dynamic>?;
    if (team1 != null) {
      team1Type = team1['type'] as String? ?? team1Type;
      team1From = team1['from'] as String? ?? team1From;
      team1Key = team1['teamKey'] as String?;
    }

    final team2 = data['team2'] as Map<String, dynamic>?;
    if (team2 != null) {
      team2Type = team2['type'] as String? ?? team2Type;
      team2From = team2['from'] as String? ?? team2From;
      team2Key = team2['teamKey'] as String?;
    }

    winner = data['winner'] as String?;

    final schedule = data['schedule'] as Map<String, dynamic>?;
    if (schedule != null) {
      court = schedule['court'] as String? ?? '';
      startTime = schedule['startTime'] as String? ?? '';
      endTime = schedule['endTime'] as String? ?? '';

      courtController.text = court;
      startTimeController.text = startTime;
      endTimeController.text = endTime;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'team1': {
        'type': team1Type,
        'from': team1From,
        'teamKey': team1Key,
      },
      'team2': {
        'type': team2Type,
        'from': team2From,
        'teamKey': team2Key,
      },
      'schedule': {
        'court': court,
        'startTime': startTime,
        'endTime': endTime,
      },
      'winner': winner,
    };
  }
}
