import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'phase1_setup_screen.dart';
import 'phase2_setup_screen.dart';
import 'knockout_setup_screen.dart';
import '../utils/knockout_bracket_utils.dart';

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
  /// Per-level phase: 'groups' | 'knockout' | 'completed'. Enables e.g. D in knockout while Beginners still in groups.
  Map<String, String> _statusByLevel = {};
  /// Level names that have a bracket in knockout.levelBrackets (for per-level "Move to knockout").
  List<String> _knockoutLevels = [];
  final TextEditingController _rulesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _loadTournamentData();
  }

  String get _statusForCurrentType {
    if (_tournamentType == 'simple') {
      return ['upcoming', 'groups', 'knockout', 'completed'].contains(_status)
          ? _status
          : 'upcoming';
    }
    return ['upcoming', 'phase1', 'phase2', 'knockout', 'completed'].contains(_status)
        ? _status
        : 'upcoming';
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
        final type = data['type'] as String? ?? 'simple';
        var status = data['status'] as String? ?? 'upcoming';
        // Map legacy/invalid status when loading
        if (type == 'simple' && ['phase1', 'phase2'].contains(status)) {
          status = 'groups';
        } else if (type == 'two-phase-knockout' && status == 'groups') {
          status = 'phase1';
        }
        final statusByLevelRaw = data['statusByLevel'] as Map<String, dynamic>?;
        final statusByLevel = statusByLevelRaw != null
            ? statusByLevelRaw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
            : <String, String>{};
        final knockout = data['knockout'] as Map<String, dynamic>?;
        final levelBrackets = knockout?['levelBrackets'] as Map<String, dynamic>?;
        Map<String, dynamic> groupsRaw = data['groups'] as Map<String, dynamic>? ?? {};
        if (type == 'two-phase-knockout') {
          final phase1 = data?['phase1'] as Map<String, dynamic>?;
          if (phase1 != null) groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
        }
        final byLevel = KnockoutBracketUtils.groupGroupsByLevel(groupsRaw);
        final levelsFromGroups = byLevel.isNotEmpty
            ? KnockoutBracketUtils.sortLevels(byLevel.keys.toList())
            : <String>[];
        final knockoutLevels = levelBrackets != null && levelBrackets.isNotEmpty
            ? KnockoutBracketUtils.sortLevels(levelBrackets.keys.map((e) => e.toString()).toList())
            : levelsFromGroups;
        setState(() {
          _tournamentType = type;
          _status = status;
          _statusByLevel = statusByLevel;
          _knockoutLevels = knockoutLevels;
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
                if (_tournamentType == 'simple') ...[
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
                  // Reset status if invalid for simple (phase1/phase2 → groups)
                  if (_status == 'phase1' || _status == 'phase2') {
                    _status = 'groups';
                  }
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
                  // Reset status if invalid for two-phase (groups → phase1)
                  if (_status == 'groups') {
                    _status = 'phase1';
                  }
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
              value: _statusForCurrentType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _tournamentType == 'simple'
                  ? const [
                      DropdownMenuItem(value: 'upcoming', child: Text('Upcoming')),
                      DropdownMenuItem(value: 'groups', child: Text('Groups Stage - In Progress')),
                      DropdownMenuItem(value: 'knockout', child: Text('Knockout - In Progress')),
                      DropdownMenuItem(value: 'completed', child: Text('Completed ✓')),
                    ]
                  : const [
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
            if (_status == 'phase2' || _status == 'knockout' || _status == 'completed') ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loading ? null : _refillPhase2FromPhase1,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Re-fill Phase 2 from Phase 1 results'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refillPhase2FromPhase1() async {
    setState(() => _loading = true);
    try {
      final standings = await _calculatePhase1Standings();
      await _autoFillPhase2Groups(standings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Phase 2 groups re-filled from Phase 1 standings'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildKnockoutSection() {
    final isSimple = _tournamentType == 'simple';
    final showAdvanceToKnockout = isSimple && _status == 'groups';
    final showFillBracket = isSimple && (_status == 'groups' || _status == 'knockout');

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
            const SizedBox(height: 8),
            Text(
              'Tip: In Knockout Setup, tap "Sync with tournament groups" so the bracket uses your actual group names, then Save.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            if (!['groups', 'knockout', 'completed'].contains(_status)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Set Tournament Status above to "Groups Stage - In Progress" to see advance-to-knockout and per-level options.',
                        style: TextStyle(fontSize: 13, color: Colors.blue[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (showAdvanceToKnockout) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loading ? null : _advanceSimpleToKnockout,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Advance to Knockout (auto-fill from groups)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
              ),
              if (_knockoutLevels.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Or move one level at a time:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                ..._knockoutLevels.map((level) {
                  final levelStatus = _statusByLevel[level] ?? 'groups';
                  final canAdvance = levelStatus != 'knockout' && levelStatus != 'completed';
                  final canRevert = levelStatus == 'knockout' || levelStatus == 'completed';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _loading || !canAdvance ? null : () => _advanceLevelToKnockout(level),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text('Move $level to knockout'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading || !canRevert ? null : () => _revertLevelToGroups(level),
                          icon: const Icon(Icons.undo, size: 18),
                          label: Text('Revert $level to groups'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            if (showFillBracket && !showAdvanceToKnockout) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loading ? null : _fillBracketFromGroups,
                icon: const Icon(Icons.refresh),
                label: const Text('Fill bracket from groups (retry)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _fillBracketFromGroups() async {
    setState(() => _loading = true);
    try {
      final standings = await _calculateSimpleGroupStandings();
      if (standings.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No groups with teams found. Create groups and add teams first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final filled = await _autoFillKnockoutBracket(standings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(filled > 0
                ? '✅ Filled $filled team slot(s) from ${standings.length} groups.'
                : '⚠️ 0 teams filled. Add teams to groups (e.g. D - Group 1) in Tournament → Groups, then retry.'),
            backgroundColor: filled > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _advanceSimpleToKnockout() async {
    setState(() => _loading = true);
    try {
      final standings = await _calculateSimpleGroupStandings();
      if (standings.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No groups with teams found. Create groups and add teams first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final filled = await _autoFillKnockoutBracket(standings);
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'status': 'knockout', 'updatedAt': FieldValue.serverTimestamp()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(filled > 0
                ? '✅ Advanced! Filled $filled team slot(s) from ${standings.length} groups.'
                : '⚠️ Advanced but 0 teams filled. Use group names like "D - Group 1", "D - Group 2" and ensure groups have teams.'),
            backgroundColor: filled > 0 ? Colors.green : Colors.orange,
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
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Move a single level to knockout. Builds the bracket from groups if needed, fills from standings, then sets statusByLevel.
  Future<void> _advanceLevelToKnockout(String level) async {
    setState(() => _loading = true);
    try {
      final standings = await _calculateSimpleGroupStandings();
      if (standings.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No groups with teams found. Create groups and add teams first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final tournamentData = tournamentDoc.data();
      final knockout = tournamentData?['knockout'] as Map<String, dynamic>?;
      var levelBrackets = knockout?['levelBrackets'] as Map<String, dynamic>?;
      Map<String, dynamic> groupsRaw = tournamentData?['groups'] as Map<String, dynamic>? ?? {};
      if (groupsRaw.isEmpty && tournamentData != null) {
        final type = tournamentData['type'] as String? ?? 'simple';
        if (type == 'two-phase-knockout') {
          final phase1 = tournamentData['phase1'] as Map<String, dynamic>?;
          if (phase1 != null) groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
        }
      }
      final byLevel = KnockoutBracketUtils.groupGroupsByLevel(groupsRaw);
      final groupsForLevel = byLevel[level] ?? [];
      final allLevelKeys = byLevel.keys.toList();
      final rawGroupKeys = groupsRaw.keys.take(6).toList();

      if (groupsForLevel.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No groups found for "$level".\n'
                'Levels detected: $allLevelKeys\n'
                'Raw group keys: $rawGroupKeys',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }

      final existingRoundsRaw = levelBrackets != null ? levelBrackets[level] : null;
      final hasExistingLevelBracket =
          existingRoundsRaw is List && (existingRoundsRaw as List).isNotEmpty;

      // Collect advancing teams from standings (top 2 per group), deduped
      final advancing = <Map<String, dynamic>>[];
      final seenTeamIds = <String>{};
      for (final g in groupsForLevel) {
        final list = _standingsForGroup(g, standings);
        if (list != null) {
          final takeN = list.length >= 2 ? 2 : list.length;
          for (int i = 0; i < takeN; i++) {
            final t = list[i];
            final teamKey = (t['teamKey'] ?? '').toString().trim();
            final teamName = (t['teamName'] ?? '').toString().trim();
            if (teamKey.isEmpty && teamName.isEmpty) continue;
            final dedupeId = teamKey.isNotEmpty ? teamKey : teamName.toLowerCase();
            if (!seenTeamIds.add(dedupeId)) continue;
            advancing.add(t);
          }
        }
      }
      advancing.sort((a, b) {
        final cp = (b['points'] as int).compareTo(a['points'] as int);
        if (cp != 0) return cp;
        return (b['scoreDifference'] as int).compareTo(a['scoreDifference'] as int);
      });
      if (advancing.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No teams found in groups for "$level". Add teams to the groups first.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      int _maxSeedInRounds(List<dynamic> rounds) {
        var maxSeed = 0;
        for (final r in rounds) {
          final rMap = r is Map ? Map<String, dynamic>.from(r as Map<String, dynamic>) : <String, dynamic>{};
          for (final m in rMap['matches'] as List<dynamic>? ?? const []) {
            final mMap = m is Map ? Map<String, dynamic>.from(m as Map<String, dynamic>) : <String, dynamic>{};
            for (final slotName in ['team1', 'team2']) {
              final slot = mMap[slotName] as Map<String, dynamic>?;
              if (slot == null) continue;
              final from = (slot['from'] ?? '').toString();
              if (!from.startsWith('seed')) continue;
              final idx = int.tryParse(from.replaceFirst('seed', '')) ?? 0;
              if (idx > maxSeed) maxSeed = idx;
            }
          }
        }
        return maxSeed;
      }

      final roundsOut = <Map<String, dynamic>>[];
      final existingSeedMax = hasExistingLevelBracket
          ? _maxSeedInRounds((existingRoundsRaw as List<dynamic>))
          : 0;
      final reuseConfiguredShape =
          hasExistingLevelBracket && existingSeedMax == advancing.length;

      if (reuseConfiguredShape) {
        // Reuse configured knockout shape only when its seed size matches qualifiers.
        for (final r in (existingRoundsRaw as List<dynamic>)) {
          final rMap = Map<String, dynamic>.from(r is Map ? r as Map<String, dynamic> : <String, dynamic>{});
          final matchesOut = <Map<String, dynamic>>[];
          for (var m in rMap['matches'] as List<dynamic>? ?? []) {
            final mMap = Map<String, dynamic>.from(m is Map ? m as Map<String, dynamic> : <String, dynamic>{});
            for (final slotName in ['team1', 'team2']) {
              final slot = mMap[slotName] as Map<String, dynamic>?;
              if (slot == null) continue;
              final from = (slot['from'] ?? '').toString();
              if (from.startsWith('seed')) {
                final idx = int.tryParse(from.replaceFirst('seed', '')) ?? 0;
                if (idx >= 1 && idx <= advancing.length) {
                  final team = advancing[idx - 1];
                  slot['teamKey'] = team['teamKey'];
                  slot['teamName'] = team['teamName'];
                } else {
                  slot['teamKey'] = null;
                  slot['teamName'] = null;
                }
              }
              mMap[slotName] = slot;
            }
            matchesOut.add(mMap);
          }
          roundsOut.add({'name': rMap['name'], 'matches': matchesOut});
        }
        KnockoutBracketUtils.applyByesToRounds(roundsOut);
      } else {
        // No compatible configured bracket: build fresh bracket from qualifier count.
        final numAdvancing = advancing.length < 2 ? 2 : advancing.length;
        final rawRounds = KnockoutBracketUtils.buildBracketWithByes(numAdvancing, '${level.replaceAll(' ', '_')}_');
        if (rawRounds.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not build bracket.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        for (var r in rawRounds) {
          final rMap = r as Map<String, dynamic>;
          final matchesOut = <Map<String, dynamic>>[];
          for (var m in rMap['matches'] as List<dynamic>? ?? []) {
            final mMap = Map<String, dynamic>.from(m is Map ? m as Map<String, dynamic> : <String, dynamic>{});
            for (final slotName in ['team1', 'team2']) {
              final slot = mMap[slotName] as Map<String, dynamic>?;
              if (slot == null) continue;
              final from = (slot['from'] ?? '').toString();
              if (from.startsWith('seed')) {
                final idx = int.tryParse(from.replaceFirst('seed', '')) ?? 0;
                if (idx >= 1 && idx <= advancing.length) {
                  final team = advancing[idx - 1];
                  slot['teamKey'] = team['teamKey'];
                  slot['teamName'] = team['teamName'];
                }
              }
              mMap[slotName] = slot;
            }
            matchesOut.add(mMap);
          }
          roundsOut.add({'name': rMap['name'], 'matches': matchesOut});
        }
        KnockoutBracketUtils.applyByesToRounds(roundsOut);
      }

      levelBrackets = Map<String, dynamic>.from(levelBrackets ?? {});
      levelBrackets[level] = roundsOut;
      final knockoutData = Map<String, dynamic>.from(knockout ?? {});
      knockoutData['levelBrackets'] = levelBrackets;
      final newStatusByLevel = Map<String, String>.from(_statusByLevel)..[level] = 'knockout';
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'knockout': knockoutData,
        'statusByLevel': newStatusByLevel,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reuseConfiguredShape
                  ? '$level moved to knockout using configured bracket. Filled from ${advancing.length} qualifying team(s).'
                  : '$level moved to knockout. Bracket built with ${advancing.length} qualifying team(s).',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      setState(() {
        _statusByLevel = newStatusByLevel;
        if (!_knockoutLevels.contains(level)) {
          _knockoutLevels = KnockoutBracketUtils.sortLevels([..._knockoutLevels, level]);
        }
      });
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
      setState(() => _loading = false);
    }
  }

  /// Revert a single level back to groups stage.
  Future<void> _revertLevelToGroups(String level) async {
    setState(() => _loading = true);
    try {
      final newStatusByLevel = Map<String, String>.from(_statusByLevel)..[level] = 'groups';
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'statusByLevel': newStatusByLevel,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$level reverted to groups stage.'),
            backgroundColor: Colors.blue[700],
          ),
        );
      }
      setState(() {
        _statusByLevel = newStatusByLevel;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reverting $level: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> _calculateSimpleGroupStandings() async {
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();

    final data = tournamentDoc.data();
    Map<String, dynamic> groupsRaw = data?['groups'] as Map<String, dynamic>? ?? {};
    if (groupsRaw.isEmpty) {
      final type = data?['type'] as String? ?? 'simple';
      if (type == 'two-phase-knockout') {
        final phase1 = data?['phase1'] as Map<String, dynamic>?;
        if (phase1 != null) groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
      }
    }
    if (groupsRaw.isEmpty) return {};

    final Map<String, dynamic> groupsForStandings = {};
    for (var entry in groupsRaw.entries) {
      final rawName = entry.key?.toString() ?? '';
      final groupName = _normalizeGroupName(rawName);
      if (groupName.isEmpty) continue;
      final groupData = entry.value;
      List<String> teamKeys = [];
      if (groupData is List) {
        for (final e in groupData) {
          if (e is Map && e['teamKey'] != null) {
            teamKeys.add(e['teamKey'].toString().trim());
          } else {
            final s = e.toString().trim();
            if (s.isNotEmpty) teamKeys.add(s);
          }
        }
      } else if (groupData is Map) {
        final dataMap = groupData as Map<String, dynamic>;
        final fromKeys = dataMap['teamKeys'] as List<dynamic>?;
        if (fromKeys != null && fromKeys.isNotEmpty) {
          for (final e in fromKeys) {
            if (e is Map && e['teamKey'] != null) {
              teamKeys.add(e['teamKey'].toString().trim());
            } else {
              final s = e.toString().trim();
              if (s.isNotEmpty) teamKeys.add(s);
            }
          }
        } else {
          final slots = dataMap['teamSlots'] as List<dynamic>? ?? [];
          for (final s in slots) {
            if (s is Map) {
              final k = (s as Map<String, dynamic>)['teamKey']?.toString();
              if (k != null && k.trim().isNotEmpty) teamKeys.add(k.trim());
            }
          }
        }
      }
      teamKeys = teamKeys.where((k) => k.isNotEmpty).toSet().toList();
      if (teamKeys.isNotEmpty) {
        groupsForStandings[groupName] = {'teamKeys': teamKeys};
      }
    }
    if (groupsForStandings.isEmpty) return {};

    final registrationsSnapshot = await FirebaseFirestore.instance
        .collection('tournamentRegistrations')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .where('status', isEqualTo: 'approved')
        .get();

    final matchesSnapshot = await FirebaseFirestore.instance
        .collection('tournamentMatches')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .get();

    return _computeGroupStandingsFromMatches(
      matchesSnapshot.docs,
      registrationsSnapshot.docs,
      groupsForStandings,
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
    // Compute standings from tournamentMatches + registrations (same logic as dashboard)
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();

    final phase1 = tournamentDoc.data()?['phase1'] as Map<String, dynamic>?;
    if (phase1 == null) return {};

    final groups = phase1['groups'] as Map<String, dynamic>? ?? {};
    if (groups.isEmpty) return {};

    final registrationsSnapshot = await FirebaseFirestore.instance
        .collection('tournamentRegistrations')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .where('status', isEqualTo: 'approved')
        .get();

    final matchesSnapshot = await FirebaseFirestore.instance
        .collection('tournamentMatches')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .get();

    return _computeGroupStandingsFromMatches(
      matchesSnapshot.docs,
      registrationsSnapshot.docs,
      groups,
    );
  }

  /// Compute group standings from matches and registrations (mirrors dashboard logic)
  Map<String, List<Map<String, dynamic>>> _computeGroupStandingsFromMatches(
    List<QueryDocumentSnapshot> matches,
    List<QueryDocumentSnapshot> registrations,
    Map<String, dynamic> groups,
  ) {
    Map<String, Map<String, dynamic>> allTeamStats = {};

    String _genTeamKey(Map<String, dynamic> data) {
      final userId = data['userId'] as String;
      final partner = data['partner'] as Map<String, dynamic>?;
      if (partner != null) {
        final partnerId = partner['partnerId'] as String?;
        if (partnerId != null) {
          final userIds = [userId, partnerId]..sort();
          return userIds.join('_');
        }
      }
      return userId;
    }

    for (var reg in registrations) {
      final data = reg.data() as Map<String, dynamic>;
      final teamKey = _genTeamKey(data);
      final firstName = data['firstName'] as String? ?? '';
      final lastName = data['lastName'] as String? ?? '';
      final partner = data['partner'] as Map<String, dynamic>?;
      final teamName = partner != null
          ? '$firstName $lastName & ${partner['partnerName'] as String? ?? 'Unknown'}'
          : '$firstName $lastName';

      allTeamStats[teamKey] = {
        'teamKey': teamKey,
        'teamName': teamName,
        'points': 0,
        'scoreDifference': 0,
        'gamesPlayed': 0,
        'gamesWon': 0,
        'gamesLost': 0,
      };
    }

    String? resolveKey(String mk) {
      if (allTeamStats.containsKey(mk)) return mk;
      final t = mk.replaceAll(RegExp(r'_+$'), '').replaceAll(RegExp(r'^_+'), '');
      if (t.isNotEmpty && allTeamStats.containsKey(t)) return t;
      final parts = mk.split('_').where((s) => s.isNotEmpty).toList()..sort();
      if (parts.length >= 2) {
        final r = parts.join('_');
        if (allTeamStats.containsKey(r)) return r;
      }
      return null;
    }

    for (var matchDoc in matches) {
      final matchData = matchDoc.data() as Map<String, dynamic>;
      final m1 = matchData['team1Key'] as String?;
      final m2 = matchData['team2Key'] as String?;
      final winner = matchData['winner'] as String?;
      final scoreDifference = matchData['scoreDifference'] as int? ?? 0;

      if (m1 == null || m2 == null) continue;
      final team1Key = resolveKey(m1);
      final team2Key = resolveKey(m2);
      if (team1Key == null || team2Key == null) continue;

      allTeamStats[team1Key]!['gamesPlayed']++;
      if (winner == 'team1') {
        allTeamStats[team1Key]!['points'] += 3;
        allTeamStats[team1Key]!['gamesWon']++;
        allTeamStats[team1Key]!['scoreDifference'] += scoreDifference;
      } else {
        allTeamStats[team1Key]!['gamesLost']++;
        allTeamStats[team1Key]!['scoreDifference'] -= scoreDifference;
      }

      allTeamStats[team2Key]!['gamesPlayed']++;
      if (winner == 'team2') {
        allTeamStats[team2Key]!['points'] += 3;
        allTeamStats[team2Key]!['gamesWon']++;
        allTeamStats[team2Key]!['scoreDifference'] += scoreDifference;
      } else {
        allTeamStats[team2Key]!['gamesLost']++;
        allTeamStats[team2Key]!['scoreDifference'] -= scoreDifference;
      }
    }

    Map<String, List<Map<String, dynamic>>> groupStandings = {};
    for (var groupEntry in groups.entries) {
      final groupName = groupEntry.key;
      List<String> teamKeys;
      if (groupEntry.value is List) {
        teamKeys = (groupEntry.value as List<dynamic>).map((e) => e.toString()).toList();
      } else if (groupEntry.value is Map) {
        final groupData = groupEntry.value as Map<String, dynamic>;
        teamKeys = (groupData['teamKeys'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      } else {
        teamKeys = [];
      }

      final groupTeams = <Map<String, dynamic>>[];
      for (var teamKey in teamKeys) {
        if (allTeamStats.containsKey(teamKey)) {
          groupTeams.add(Map<String, dynamic>.from(allTeamStats[teamKey]!));
        }
      }

      groupTeams.sort((a, b) {
        if (a['points'] != b['points']) {
          return (b['points'] as int).compareTo(a['points'] as int);
        }
        if (a['scoreDifference'] != b['scoreDifference']) {
          return (b['scoreDifference'] as int).compareTo(a['scoreDifference'] as int);
        }
        return (b['gamesWon'] as int).compareTo(a['gamesWon'] as int);
      });

      groupStandings[groupName] = groupTeams;
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
    for (var groupName in groups.keys) {
      final groupData = groups[groupName] as Map<String, dynamic>?;
      if (groupData == null) continue;
      
      final teamSlots = List<Map<String, dynamic>>.from(groupData['teamSlots'] as List<dynamic>? ?? []);
      
      for (int i = 0; i < teamSlots.length; i++) {
        final slot = teamSlots[i];
        final slotType = slot['type'] as String?;
        if (slotType == 'winner' || slotType == 'runnerUp') {
          final fromGroup = slot['from'] as String?;
          if (fromGroup == null) continue;
          var groupStandings = standings[fromGroup];
          if (groupStandings == null) {
            for (final k in standings.keys) {
              if (k.toLowerCase() == fromGroup.toLowerCase()) {
                groupStandings = standings[k];
                break;
              }
            }
          }
          if (groupStandings != null && groupStandings.isNotEmpty) {
            final team = slotType == 'winner' ? groupStandings[0] : (groupStandings.length > 1 ? groupStandings[1] : null);
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
    // Compute Phase 2 standings from matches (same as Phase 1)
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();

    final phase2 = tournamentDoc.data()?['phase2'] as Map<String, dynamic>?;
    if (phase2 == null) return {};

    final phase2GroupsRaw = phase2['groups'] as Map<String, dynamic>? ?? {};
    if (phase2GroupsRaw.isEmpty) return {};

    // Build groups map: groupName -> { teamKeys: [...] } (phase2 uses teamSlots)
    final Map<String, dynamic> groupsForStandings = {};
    for (var entry in phase2GroupsRaw.entries) {
      final groupName = entry.key;
      final groupData = entry.value as Map<String, dynamic>? ?? {};
      final teamSlots = groupData['teamSlots'] as List<dynamic>? ?? [];
      final teamKeys = <String>[];
      for (var slot in teamSlots) {
        final slotMap = slot is Map ? slot as Map<String, dynamic> : {};
        final key = slotMap['teamKey'] as String?;
        if (key != null && key.isNotEmpty) {
          teamKeys.add(key);
        }
      }
      if (teamKeys.isNotEmpty) {
        groupsForStandings[groupName] = {'teamKeys': teamKeys};
      }
    }

    if (groupsForStandings.isEmpty) return {};

    final registrationsSnapshot = await FirebaseFirestore.instance
        .collection('tournamentRegistrations')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .where('status', isEqualTo: 'approved')
        .get();

    final matchesSnapshot = await FirebaseFirestore.instance
        .collection('tournamentMatches')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .get();

    return _computeGroupStandingsFromMatches(
      matchesSnapshot.docs,
      registrationsSnapshot.docs,
      groupsForStandings,
    );
  }

  /// Resolve group standings: exact match, then "Level - Group N" suffix match (e.g. "Group 1" -> "D - Group 1"), then legacy A/B/C/D or 1/2/3/4.
  List<Map<String, dynamic>>? _resolveGroupStandings(
    String from,
    Map<String, List<Map<String, dynamic>>> standings,
  ) {
    final f = from.trim();
    if (f.isEmpty) return null;
    if (standings.containsKey(f)) return standings[f];
    for (final k in standings.keys) {
      if (k.trim().toLowerCase() == f.toLowerCase()) return standings[k];
    }
    // Match "D - Group 1" style: bracket may say "Group 1", standings key is "D - Group 1"
    for (final k in standings.keys) {
      final kTrim = k.trim();
      if (kTrim.endsWith(' - $f') || kTrim.toLowerCase().endsWith(' - ${f.toLowerCase()}')) return standings[k];
      if (kTrim.endsWith(f) || kTrim.toLowerCase().endsWith(f.toLowerCase())) return standings[k];
    }
    // Legacy: map Group A/B/C/D or Group 1/2/3/4 -> position (by sorted name)
    final sortedNames = standings.keys.toList()..sort();
    final letterIndex = {
      'Group A': 0, 'Group B': 1, 'Group C': 2, 'Group D': 3,
      'Group 1': 0, 'Group 2': 1, 'Group 3': 2, 'Group 4': 3,
    }[f];
    if (letterIndex != null && letterIndex < sortedNames.length) {
      return standings[sortedNames[letterIndex]];
    }
    return null;
  }

  /// Normalize group name to "Level - Group N" (single space around dash) for consistent lookup.
  static String _normalizeGroupName(String name) {
    final t = name.trim();
    if (t.isEmpty) return t;
    return t.replaceAll(RegExp(r'\s*-\s*'), ' - ');
  }

  /// Get standings for a group name; supports "D - Group 1" and flexible matching.
  List<Map<String, dynamic>>? _standingsForGroup(String groupName, Map<String, List<Map<String, dynamic>>> standings) {
    final g = _normalizeGroupName(groupName);
    if (g.isEmpty) return null;
    if (standings.containsKey(g)) return standings[g];
    for (final k in standings.keys) {
      if (_normalizeGroupName(k).toLowerCase() == g.toLowerCase()) return standings[k];
    }
    for (final k in standings.keys) {
      final nk = _normalizeGroupName(k);
      if (nk.endsWith(' - $g') || nk.toLowerCase().endsWith(' - ${g.toLowerCase()}')) return standings[k];
      if (nk == g || nk.toLowerCase() == g.toLowerCase()) return standings[k];
    }
    return null;
  }

  Future<int> _autoFillKnockoutBracket(Map<String, List<Map<String, dynamic>>> standings) async {
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();

    final knockout = tournamentDoc.data()?['knockout'] as Map<String, dynamic>?;
    if (knockout == null) return 0;

    final levelBracketsData = knockout['levelBrackets'] as Map<String, dynamic>?;
    if (levelBracketsData != null && levelBracketsData.isNotEmpty) {
      return await _fillLevelBrackets(standings, levelBracketsData, tournamentDoc.data());
    }

    final roundsRaw = knockout['rounds'] as List<dynamic>?;
    if (roundsRaw != null && roundsRaw.isNotEmpty) {
      return await _fillRoundsBracket(standings, roundsRaw);
    }

    final qfRaw = knockout['quarterFinals'] as List<dynamic>? ?? [];
    if (qfRaw.isEmpty) return 0;
    final qfList = <Map<String, dynamic>>[];
    int filled = 0;
    for (var qf in qfRaw) {
      final qfMap = Map<String, dynamic>.from(qf is Map ? qf as Map<String, dynamic> : <String, dynamic>{});
      final t1 = qfMap['team1'];
      final t2 = qfMap['team2'];
      final team1 = t1 is Map ? Map<String, dynamic>.from(Map.from(t1)) : <String, dynamic>{};
      final team2 = t2 is Map ? Map<String, dynamic>.from(Map.from(t2)) : <String, dynamic>{};
      filled = _fillMatchWithStandings(standings, team1, filled);
      filled = _fillMatchWithStandings(standings, team2, filled);
      qfMap['team1'] = team1;
      qfMap['team2'] = team2;
      qfList.add(qfMap);
    }
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({'knockout.quarterFinals': qfList});
    return filled;
  }

  int _fillMatchWithStandings(
    Map<String, List<Map<String, dynamic>>> standings,
    Map<String, dynamic> teamSlot,
    int currentFilled,
  ) {
    final from = (teamSlot['from'] ?? '').toString();
    final type = (teamSlot['type'] ?? 'winner').toString();
    if (from.isEmpty) return currentFilled;
    final groupStandings = standings.containsKey(from)
        ? standings[from]
        : _resolveGroupStandings(from, standings);
    if (groupStandings == null || groupStandings.isEmpty) return currentFilled;
    final team = type == 'winner' ? groupStandings[0] : (groupStandings.length > 1 ? groupStandings[1] : null);
    if (team != null) {
      teamSlot['teamKey'] = team['teamKey'];
      teamSlot['teamName'] = team['teamName'];
      return currentFilled + 1;
    }
    return currentFilled;
  }

  Future<int> _fillLevelBrackets(
    Map<String, List<Map<String, dynamic>>> standings,
    Map<String, dynamic> levelBracketsData,
    Map<String, dynamic>? tournamentData,
  ) async {
    Map<String, dynamic> groupsRaw = tournamentData?['groups'] as Map<String, dynamic>? ?? {};
    if (groupsRaw.isEmpty && tournamentData != null) {
      final type = tournamentData['type'] as String? ?? 'simple';
      if (type == 'two-phase-knockout') {
        final phase1 = tournamentData['phase1'] as Map<String, dynamic>?;
        if (phase1 != null) groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
      }
    }
    final byLevel = KnockoutBracketUtils.groupGroupsByLevel(groupsRaw);
    int totalFilled = 0;
    final levelBracketsOut = <String, dynamic>{};
    for (final entry in levelBracketsData.entries) {
      final level = entry.key;
      final groupsForLevel = byLevel[level] ?? [];
      final advancing = <Map<String, dynamic>>[];
      for (final g in groupsForLevel) {
        final list = _standingsForGroup(g, standings);
        if (list != null) {
          if (list.isNotEmpty) advancing.add(list[0]);
          if (list.length > 1) advancing.add(list[1]);
        }
      }
      advancing.sort((a, b) {
        final cp = (b['points'] as int).compareTo(a['points'] as int);
        if (cp != 0) return cp;
        return (b['scoreDifference'] as int).compareTo(a['scoreDifference'] as int);
      });
      final roundsRaw = entry.value as List<dynamic>;
      final roundsOut = <Map<String, dynamic>>[];
      for (var r in roundsRaw) {
        final rMap = r as Map<String, dynamic>;
        final matchesOut = <Map<String, dynamic>>[];
        for (var m in rMap['matches'] as List<dynamic>? ?? []) {
          final mMap = Map<String, dynamic>.from(m is Map ? m as Map<String, dynamic> : <String, dynamic>{});
          for (final slotName in ['team1', 'team2']) {
            final slot = mMap[slotName] as Map<String, dynamic>?;
            if (slot == null) continue;
            final from = (slot['from'] ?? '').toString();
            if (from.startsWith('seed')) {
              final idx = int.tryParse(from.replaceFirst('seed', '')) ?? 0;
              if (idx >= 1 && idx <= advancing.length) {
                final team = advancing[idx - 1];
                slot['teamKey'] = team['teamKey'];
                slot['teamName'] = team['teamName'];
                totalFilled++;
              }
            }
          }
          matchesOut.add(mMap);
        }
        roundsOut.add({'name': rMap['name'], 'matches': matchesOut});
      }
      KnockoutBracketUtils.applyByesToRounds(roundsOut);
      levelBracketsOut[level] = roundsOut;
    }
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({'knockout.levelBrackets': levelBracketsOut});
    return totalFilled;
  }

  /// Fills bracket for a single level and merges into existing levelBrackets. Used for per-level "Move to knockout".
  Future<int> _fillOneLevelBracket(
    String level,
    Map<String, List<Map<String, dynamic>>> standings,
    Map<String, dynamic>? tournamentData,
  ) async {
    final knockout = tournamentData?['knockout'] as Map<String, dynamic>?;
    final levelBracketsData = knockout?['levelBrackets'] as Map<String, dynamic>?;
    if (levelBracketsData == null || !levelBracketsData.containsKey(level)) return 0;
    Map<String, dynamic> groupsRaw = tournamentData?['groups'] as Map<String, dynamic>? ?? {};
    if (groupsRaw.isEmpty && tournamentData != null) {
      final type = tournamentData['type'] as String? ?? 'simple';
      if (type == 'two-phase-knockout') {
        final phase1 = tournamentData['phase1'] as Map<String, dynamic>?;
        if (phase1 != null) groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
      }
    }
    final byLevel = KnockoutBracketUtils.groupGroupsByLevel(groupsRaw);
    final groupsForLevel = byLevel[level] ?? [];
    final advancing = <Map<String, dynamic>>[];
    for (final g in groupsForLevel) {
      final list = _standingsForGroup(g, standings);
      if (list != null) {
        if (list.isNotEmpty) advancing.add(list[0]);
        if (list.length > 1) advancing.add(list[1]);
      }
    }
    advancing.sort((a, b) {
      final cp = (b['points'] as int).compareTo(a['points'] as int);
      if (cp != 0) return cp;
      return (b['scoreDifference'] as int).compareTo(a['scoreDifference'] as int);
    });
    final roundsRaw = levelBracketsData[level] as List<dynamic>? ?? [];
    int totalFilled = 0;
    final roundsOut = <Map<String, dynamic>>[];
    for (var r in roundsRaw) {
      final rMap = r as Map<String, dynamic>;
      final matchesOut = <Map<String, dynamic>>[];
      for (var m in rMap['matches'] as List<dynamic>? ?? []) {
        final mMap = Map<String, dynamic>.from(m is Map ? m as Map<String, dynamic> : <String, dynamic>{});
        for (final slotName in ['team1', 'team2']) {
          final slot = mMap[slotName] as Map<String, dynamic>?;
          if (slot == null) continue;
          final from = (slot['from'] ?? '').toString();
          if (from.startsWith('seed')) {
            final idx = int.tryParse(from.replaceFirst('seed', '')) ?? 0;
            if (idx >= 1 && idx <= advancing.length) {
              final team = advancing[idx - 1];
              slot['teamKey'] = team['teamKey'];
              slot['teamName'] = team['teamName'];
              totalFilled++;
            }
          }
        }
        matchesOut.add(mMap);
      }
      roundsOut.add({'name': rMap['name'], 'matches': matchesOut});
    }
    KnockoutBracketUtils.applyByesToRounds(roundsOut);
    final levelBracketsOut = Map<String, dynamic>.from(levelBracketsData);
    levelBracketsOut[level] = roundsOut;
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({'knockout.levelBrackets': levelBracketsOut});
    return totalFilled;
  }

  Future<int> _fillRoundsBracket(
    Map<String, List<Map<String, dynamic>>> standings,
    List<dynamic> roundsRaw,
  ) async {
    int totalFilled = 0;
    final roundsOut = <Map<String, dynamic>>[];
    for (var r in roundsRaw) {
      final rMap = r as Map<String, dynamic>;
      final matchesRaw = rMap['matches'] as List<dynamic>? ?? [];
      final matchesOut = <Map<String, dynamic>>[];
      for (var m in matchesRaw) {
        final mMap = Map<String, dynamic>.from(m is Map ? m as Map<String, dynamic> : <String, dynamic>{});
        final t1 = mMap['team1'];
        final t2 = mMap['team2'];
        final team1 = t1 is Map ? Map<String, dynamic>.from(Map.from(t1)) : <String, dynamic>{};
        final team2 = t2 is Map ? Map<String, dynamic>.from(Map.from(t2)) : <String, dynamic>{};
        totalFilled = _fillMatchWithStandings(standings, team1, totalFilled);
        totalFilled = _fillMatchWithStandings(standings, team2, totalFilled);
        mMap['team1'] = team1;
        mMap['team2'] = team2;
        matchesOut.add(mMap);
      }
      roundsOut.add({'name': rMap['name'], 'matches': matchesOut});
    }
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({'knockout.rounds': roundsOut});
    return totalFilled;
  }

  Future<void> _saveBasicConfiguration() async {
    setState(() {
      _loading = true;
    });

    try {
      final updateData = <String, dynamic>{
        'type': _tournamentType,
        'status': _status,
        'rules': {
          'text': _rulesController.text.trim(),
          'acceptanceRequired': true,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_statusByLevel.isNotEmpty) {
        updateData['statusByLevel'] = _statusByLevel;
      }
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update(updateData);

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
    ).then((_) => _loadTournamentData());
  }

  @override
  void dispose() {
    _rulesController.dispose();
    super.dispose();
  }
}

