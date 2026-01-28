import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'phase1_setup_screen.dart';
import 'phase2_setup_screen.dart';
import 'knockout_setup_screen.dart';

/// Admin screen to set up two-phase tournament structure
/// for TPF tournaments with Phase 1 → Phase 2 → Knockout
class AdminTournamentSetupScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;

  const AdminTournamentSetupScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<AdminTournamentSetupScreen> createState() => _AdminTournamentSetupScreenState();
}

class _AdminTournamentSetupScreenState extends State<AdminTournamentSetupScreen> {
  bool _isAdmin = false;
  bool _checkingAdmin = true;
  bool _loading = false;

  // Admin credentials
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com';

  // Tournament configuration
  String _tournamentType = 'simple'; // 'simple' or 'two-phase-knockout'
  String _status = 'upcoming';
  final TextEditingController _rulesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _loadTournamentData();
  }

  Future<void> _checkAdminAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.phoneNumber == adminPhone || user?.email == adminEmail) {
      setState(() {
        _isAdmin = true;
        _checkingAdmin = false;
      });
    } else {
      setState(() {
        _isAdmin = false;
        _checkingAdmin = false;
      });
    }
  }

  Future<void> _loadTournamentData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _tournamentType = data['type'] as String? ?? 'simple';
          _status = data['status'] as String? ?? 'upcoming';
          final rules = data['rules'] as Map<String, dynamic>?;
          _rulesController.text = rules?['text'] as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading tournament data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Access Denied'),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Admin access required',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Setup: ${widget.tournamentName}'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTournamentTypeSection(),
                const SizedBox(height: 24),
                _buildRulesSection(),
                const SizedBox(height: 24),
                if (_tournamentType == 'two-phase-knockout') ...[
                  _buildPhase1Section(),
                  const SizedBox(height: 24),
                  _buildPhase2Section(),
                  const SizedBox(height: 24),
                  _buildKnockoutSection(),
                  const SizedBox(height: 24),
                ],
                _buildSaveButton(),
              ],
            ),
    );
  }

  Widget _buildTournamentTypeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🏆 Tournament Type',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            RadioListTile<String>(
              title: const Text('Simple (Groups + Playoffs)'),
              subtitle: const Text('Traditional tournament format'),
              value: 'simple',
              groupValue: _tournamentType,
              onChanged: (value) {
                setState(() {
                  _tournamentType = value!;
                });
              },
            ),
            RadioListTile<String>(
              title: const Text('Two-Phase + Knockout'),
              subtitle: const Text('TPF format: Phase 1 → Phase 2 → Knockout'),
              value: 'two-phase-knockout',
              groupValue: _tournamentType,
              onChanged: (value) {
                setState(() {
                  _tournamentType = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Tournament Status',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'upcoming', child: Text('Upcoming')),
                DropdownMenuItem(value: 'phase1', child: Text('Phase 1 - In Progress')),
                DropdownMenuItem(value: 'phase2', child: Text('Phase 2 - In Progress')),
                DropdownMenuItem(value: 'knockout', child: Text('Knockout - In Progress')),
                DropdownMenuItem(value: 'completed', child: Text('Completed ✓')),
              ],
              onChanged: (value) async {
                // If marking as completed, save to overall standings
                if (value == 'completed' && _status != 'completed') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Complete Tournament?'),
                      content: const Text(
                        'This will:\n'
                        '• Mark the tournament as completed\n'
                        '• Archive the tournament (hide from main list)\n'
                        '• Save final standings to overall leaderboard\n'
                        '• Add placement bonuses (+10/+7/+5)\n\n'
                        'Continue?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Complete'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirm == true) {
                    await _completeTournament();
                    
                    // Check if this is a weekly tournament (has parentTournamentId)
                    final tournamentDoc = await FirebaseFirestore.instance
                        .collection('tournaments')
                        .doc(widget.tournamentId)
                        .get();
                    final hasParent = tournamentDoc.data()?['parentTournamentId'] != null;
                    
                    // Archive ONLY if it's NOT a weekly tournament
                    await FirebaseFirestore.instance
                        .collection('tournaments')
                        .doc(widget.tournamentId)
                        .update({
                      'isArchived': hasParent ? false : true, // Don't archive weekly tournaments
                      'completedAt': FieldValue.serverTimestamp(),
                    });
                  }
                }
                // Auto-archive when status is set to "upcoming" (for weekly tournaments)
                else if (value == 'upcoming' && _status != 'upcoming') {
                  // Archive previous completed tournaments when starting a new one
                  await FirebaseFirestore.instance
                      .collection('tournaments')
                      .doc(widget.tournamentId)
                      .update({'isArchived': false});
                }
                
                setState(() {
                  _status = value!;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📜 Tournament Rules',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _rulesController,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Enter tournament rules...\n\nExample:\n• All games are Deciding until Semi Final stage\n• In case of 6-6, tie break is played\n• 10 minutes delay = 2 games down\n• 20 minutes delay = Walk-over',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase1Section() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📍 PHASE 1 - Initial Groups',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToPhase1Setup(),
                    icon: const Icon(Icons.settings),
                    label: const Text('Configure'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _status == 'phase1' ? () => _advanceToPhase2() : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Advance to Phase 2'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase2Section() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📍 PHASE 2 - Advanced Groups',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _navigateToPhase2Setup(),
                    icon: const Icon(Icons.settings),
                    label: const Text('Configure'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _status == 'phase2' ? () => _advanceToKnockout() : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Advance to Knockout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKnockoutSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🏅 KNOCKOUT STAGE',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _navigateToKnockoutSetup(),
              icon: const Icon(Icons.settings),
              label: const Text('Configure Knockout Bracket'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _saveBasicConfiguration,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      child: const Text('Save Tournament Configuration'),
    );
  }

  Future<void> _completeTournament() async {
    setState(() {
      _loading = true;
    });

    try {
      // Get final standings from tournament
      final standingsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .collection('standings')
          .orderBy('points', descending: true)
          .get();

      // Calculate placement bonuses
      final standings = standingsSnapshot.docs;
      final batch = FirebaseFirestore.instance.batch();

      for (int i = 0; i < standings.length && i < 3; i++) {
        final standingDoc = standings[i];
        final data = standingDoc.data();
        final teamKey = data['teamKey'] as String;
        final currentPoints = data['points'] as int;
        
        // Add bonus: 1st = +10, 2nd = +7, 3rd = +5
        int bonus = 0;
        if (i == 0) bonus = 10;
        else if (i == 1) bonus = 7;
        else if (i == 2) bonus = 5;

        final totalPoints = currentPoints + bonus;

        // Update standing with bonus
        batch.update(standingDoc.reference, {
          'placementBonus': bonus,
          'totalPoints': totalPoints,
          'placement': i + 1,
        });

        // Save to overall standings (TPF leaderboard)
        final overallRef = FirebaseFirestore.instance
            .collection('tpfOverallStandings')
            .doc(teamKey);

        final overallDoc = await overallRef.get();
        if (overallDoc.exists) {
          // Update existing overall standing
          final overallData = overallDoc.data() as Map<String, dynamic>;
          final currentOverallPoints = overallData['totalPoints'] as int? ?? 0;
          final tournamentsPlayed = overallData['tournamentsPlayed'] as int? ?? 0;

          batch.update(overallRef, {
            'totalPoints': currentOverallPoints + totalPoints,
            'tournamentsPlayed': tournamentsPlayed + 1,
            'lastUpdated': FieldValue.serverTimestamp(),
            'tournaments.${widget.tournamentId}': {
              'tournamentName': widget.tournamentName,
              'placement': i + 1,
              'points': totalPoints,
              'bonus': bonus,
              'completedAt': FieldValue.serverTimestamp(),
            },
          });
        } else {
          // Create new overall standing
          batch.set(overallRef, {
            'teamKey': teamKey,
            'teamName': data['teamName'] as String,
            'totalPoints': totalPoints,
            'tournamentsPlayed': 1,
            'lastUpdated': FieldValue.serverTimestamp(),
            'tournaments': {
              widget.tournamentId: {
                'tournamentName': widget.tournamentName,
                'placement': i + 1,
                'points': totalPoints,
                'bonus': bonus,
                'completedAt': FieldValue.serverTimestamp(),
              },
            },
          });
        }
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Tournament completed! Saved to overall standings.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error completing tournament: $e'),
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

  Future<void> _advanceToPhase2() async {
    setState(() {
      _loading = true;
    });

    try {
      // Calculate Phase 1 standings and auto-fill Phase 2
      final standings = await _calculatePhase1Standings();
      
      // Update Phase 2 groups with winners and runners-up
      await _autoFillPhase2Groups(standings);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Advanced to Phase 2! Check Phase 2 configuration.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _status = 'phase2';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error advancing to Phase 2: $e'),
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

  Future<Map<String, List<Map<String, dynamic>>>> _calculatePhase1Standings() async {
    // Get standings for each Phase 1 group (Groups 1-4)
    final Map<String, List<Map<String, dynamic>>> groupStandings = {};
    
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();
    
    final phase1 = tournamentDoc.data()?['phase1'] as Map<String, dynamic>?;
    if (phase1 == null) return {};
    
    final groups = phase1['groups'] as Map<String, dynamic>? ?? {};
    
    for (var groupName in ['Group 1', 'Group 2', 'Group 3', 'Group 4']) {
      final groupData = groups[groupName] as Map<String, dynamic>?;
      if (groupData == null) continue;
      
      // Calculate standings for this group
      final standingsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .collection('standings')
          .where('groupName', isEqualTo: groupName)
          .orderBy('points', descending: true)
          .orderBy('scoreDifference', descending: true)
          .get();
      
      groupStandings[groupName] = standingsSnapshot.docs.map((doc) => doc.data()).toList();
    }
    
    return groupStandings;
  }

  Future<void> _autoFillPhase2Groups(Map<String, List<Map<String, dynamic>>> standings) async {
    // Get Phase 2 configuration
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();
    
    final phase2 = tournamentDoc.data()?['phase2'] as Map<String, dynamic>?;
    if (phase2 == null) return;
    
    final groups = Map<String, dynamic>.from(phase2['groups'] as Map<String, dynamic>? ?? {});
    
    // Fill Phase 2 groups with winners/runners-up
    for (var groupName in ['Group A', 'Group B', 'Group C', 'Group D']) {
      final groupData = groups[groupName] as Map<String, dynamic>?;
      if (groupData == null) continue;
      
      final teamSlots = List<Map<String, dynamic>>.from(groupData['teamSlots'] as List<dynamic>? ?? []);
      
      for (int i = 0; i < teamSlots.length; i++) {
        final slot = teamSlots[i];
        if (slot['type'] == 'winner' || slot['type'] == 'runnerUp') {
          final fromGroup = slot['from'] as String;
          final groupStandings = standings[fromGroup];
          
          if (groupStandings != null && groupStandings.isNotEmpty) {
            final team = slot['type'] == 'winner' ? groupStandings[0] : (groupStandings.length > 1 ? groupStandings[1] : null);
            if (team != null) {
              teamSlots[i]['teamKey'] = team['teamKey'];
              teamSlots[i]['teamName'] = team['teamName'];
            }
          }
        }
      }
      
      groups[groupName] = {...groupData, 'teamSlots': teamSlots};
    }
    
    // Update Firestore
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({
      'phase2.groups': groups,
    });
  }

  Future<void> _advanceToKnockout() async {
    setState(() {
      _loading = true;
    });

    try {
      // Calculate Phase 2 standings and auto-fill Knockout
      final standings = await _calculatePhase2Standings();
      
      // Update Knockout bracket with winners and runners-up
      await _autoFillKnockoutBracket(standings);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Advanced to Knockout! Check Knockout configuration.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _status = 'knockout';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error advancing to Knockout: $e'),
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

  Future<Map<String, List<Map<String, dynamic>>>> _calculatePhase2Standings() async {
    // Get standings for each Phase 2 group (Groups A-D)
    final Map<String, List<Map<String, dynamic>>> groupStandings = {};
    
    for (var groupName in ['Group A', 'Group B', 'Group C', 'Group D']) {
      final standingsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .collection('standings')
          .where('groupName', isEqualTo: groupName)
          .orderBy('points', descending: true)
          .orderBy('scoreDifference', descending: true)
          .get();
      
      groupStandings[groupName] = standingsSnapshot.docs.map((doc) => doc.data()).toList();
    }
    
    return groupStandings;
  }

  Future<void> _autoFillKnockoutBracket(Map<String, List<Map<String, dynamic>>> standings) async {
    // Get Knockout configuration
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();
    
    final knockout = tournamentDoc.data()?['knockout'] as Map<String, dynamic>?;
    if (knockout == null) return;
    
    // Fill Quarter Finals with Phase 2 winners/runners-up
    final qfList = List<Map<String, dynamic>>.from(knockout['quarterFinals'] as List<dynamic>? ?? []);
    for (var qf in qfList) {
      // Team 1
      final team1From = qf['team1']['from'] as String;
      final team1Type = qf['team1']['type'] as String;
      if (team1From.startsWith('Group')) {
        final groupStandings = standings[team1From];
        if (groupStandings != null && groupStandings.isNotEmpty) {
          final team = team1Type == 'winner' ? groupStandings[0] : (groupStandings.length > 1 ? groupStandings[1] : null);
          if (team != null) {
            qf['team1']['teamKey'] = team['teamKey'];
            qf['team1']['teamName'] = team['teamName'];
          }
        }
      }
      
      // Team 2
      final team2From = qf['team2']['from'] as String;
      final team2Type = qf['team2']['type'] as String;
      if (team2From.startsWith('Group')) {
        final groupStandings = standings[team2From];
        if (groupStandings != null && groupStandings.isNotEmpty) {
          final team = team2Type == 'winner' ? groupStandings[0] : (groupStandings.length > 1 ? groupStandings[1] : null);
          if (team != null) {
            qf['team2']['teamKey'] = team['teamKey'];
            qf['team2']['teamName'] = team['teamName'];
          }
        }
      }
    }
    
    // Update Firestore
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({
      'knockout.quarterFinals': qfList,
    });
  }

  Future<void> _saveBasicConfiguration() async {
    setState(() {
      _loading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'type': _tournamentType,
        'status': _status,
        'rules': {
          'text': _rulesController.text.trim(),
          'acceptanceRequired': true,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Basic configuration saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
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

  void _navigateToPhase1Setup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Phase1SetupScreen(
          tournamentId: widget.tournamentId,
          tournamentName: widget.tournamentName,
        ),
      ),
    );
  }

  void _navigateToPhase2Setup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Phase2SetupScreen(
          tournamentId: widget.tournamentId,
          tournamentName: widget.tournamentName,
        ),
      ),
    );
  }

  void _navigateToKnockoutSetup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KnockoutSetupScreen(
          tournamentId: widget.tournamentId,
          tournamentName: widget.tournamentName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _rulesController.dispose();
    super.dispose();
  }
}

