import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/knockout_bracket_utils.dart';

/// Knockout Setup Screen - per-level brackets with BYE support and seeding.
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

  /// Per-level brackets. Key = level name (e.g. "Seniors", "Beginners").
  Map<String, List<KnockoutRound>> _levelBrackets = {};

  /// Legacy single bracket (when no levels). Kept for backward compat.
  List<KnockoutRound> _rounds = [];

  @override
  void initState() {
    super.initState();
    _loadExistingConfiguration();
  }

  List<KnockoutRound> _parseRounds(List<dynamic> roundsData) {
    final out = <KnockoutRound>[];
    for (var r in roundsData) {
      final rMap = r as Map<String, dynamic>;
      final matches = <KnockoutMatchConfig>[];
      for (var m in rMap['matches'] as List<dynamic>? ?? []) {
        final mMap = m as Map<String, dynamic>;
        final mc = KnockoutMatchConfig(
          id: (mMap['id'] ?? 'm${matches.length}').toString(),
          name: (mMap['name'] ?? 'Match ${matches.length + 1}').toString(),
          team1Type: (mMap['team1']?['type'] ?? 'winner').toString(),
          team1From: (mMap['team1']?['from'] ?? '').toString(),
          team2Type: (mMap['team2']?['type'] ?? 'runnerUp').toString(),
          team2From: (mMap['team2']?['from'] ?? '').toString(),
        );
        mc.loadFromFirestore(mMap);
        matches.add(mc);
      }
      out.add(
        KnockoutRound(
          name: KnockoutBracketUtils.standardizedRoundNameFromMatchCount(
            matches.length,
            fallbackRawName: rMap['name']?.toString(),
          ),
          matches: matches,
        ),
      );
    }
    return out;
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
          final normalizedKnockout = Map<String, dynamic>.from(knockout);
          final migrated = _normalizeStoredRoundNames(normalizedKnockout);
          if (migrated) {
            await FirebaseFirestore.instance
                .collection('tournaments')
                .doc(widget.tournamentId)
                .update({
              'knockout': normalizedKnockout,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          final levelBracketsData = normalizedKnockout['levelBrackets'] as Map<String, dynamic>?;
          final hasValidLevelBrackets = levelBracketsData != null &&
              levelBracketsData.isNotEmpty &&
              levelBracketsData.entries.any((e) {
                final rounds = (e.value as List<dynamic>?) ?? [];
                final totalMatches = rounds.fold<int>(0, (s, r) {
                  final matches = (r as Map)['matches'] as List?;
                  return s + (matches?.length ?? 0);
                });
                return totalMatches > 0;
              });
          if (hasValidLevelBrackets) {
            _levelBrackets = {};
            for (var entry in levelBracketsData!.entries) {
              final roundsData = (entry.value as List<dynamic>?) ?? [];
              _levelBrackets[entry.key] = _parseRounds(roundsData);
            }
            _rounds = [];
          } else {
            final roundsData = normalizedKnockout['rounds'] as List<dynamic>?;
            if (roundsData != null && roundsData.isNotEmpty) {
              _rounds = _parseRounds(roundsData);
              _levelBrackets = {};
            } else {
            // Legacy: quarterFinals, semiFinals, final
            final qfList = normalizedKnockout['quarterFinals'] as List<dynamic>? ?? [];
            final sfList = normalizedKnockout['semiFinals'] as List<dynamic>? ?? [];
            final finalData = normalizedKnockout['final'] as Map<String, dynamic>?;
            _rounds = [];
            if (qfList.isNotEmpty) {
              final matches = <KnockoutMatchConfig>[];
              for (int i = 0; i < qfList.length; i++) {
                final m = qfList[i] as Map<String, dynamic>;
                final mc = KnockoutMatchConfig(
                  id: (m['id'] ?? 'qf${i + 1}').toString(),
                  name: (m['name'] ?? 'Quarter Final ${i + 1}').toString(),
                  team1Type: (m['team1']?['type'] ?? 'winner').toString(),
                  team1From: (m['team1']?['from'] ?? '').toString(),
                  team2Type: (m['team2']?['type'] ?? 'runnerUp').toString(),
                  team2From: (m['team2']?['from'] ?? '').toString(),
                );
                mc.loadFromFirestore(m);
                matches.add(mc);
              }
              _rounds.add(
                KnockoutRound(
                  name: KnockoutBracketUtils.standardizedRoundNameFromMatchCount(
                    matches.length,
                    fallbackRawName: 'Round of ${matches.length * 2}',
                  ),
                  matches: matches,
                ),
              );
            }
            if (sfList.isNotEmpty) {
              final matches = <KnockoutMatchConfig>[];
              for (int i = 0; i < sfList.length; i++) {
                final m = sfList[i] as Map<String, dynamic>;
                final mc = KnockoutMatchConfig(
                  id: (m['id'] ?? 'sf${i + 1}').toString(),
                  name: (m['name'] ?? 'Semi Final ${i + 1}').toString(),
                  team1Type: 'winner',
                  team1From: (m['team1']?['from'] ?? '').toString(),
                  team2Type: 'winner',
                  team2From: (m['team2']?['from'] ?? '').toString(),
                );
                mc.loadFromFirestore(m);
                matches.add(mc);
              }
              _rounds.add(KnockoutRound(name: 'Semi Finals', matches: matches));
            }
            if (finalData != null && finalData.isNotEmpty) {
              final mc = KnockoutMatchConfig(
                id: 'final',
                name: 'Final',
                team1Type: 'winner',
                team1From: (finalData['team1']?['from'] ?? '').toString(),
                team2Type: 'winner',
                team2From: (finalData['team2']?['from'] ?? '').toString(),
              );
              mc.loadFromFirestore(finalData);
              _rounds.add(KnockoutRound(name: 'Final', matches: [mc]));
            }
            _levelBrackets = {};
            }
          }
          setState(() {});
        }
      }
    } catch (e) {
      debugPrint('Error loading existing configuration: $e');
    }
  }

  bool _normalizeStoredRoundNames(Map<String, dynamic> knockout) {
    var changed = false;

    bool normalizeRoundsList(List<dynamic> rounds) {
      var localChanged = false;
      for (final round in rounds) {
        if (round is! Map) continue;
        final roundMap = round as Map<String, dynamic>;
        final matches = (roundMap['matches'] as List<dynamic>? ?? const []);
        if (matches.isEmpty) continue;
        final standardized = KnockoutBracketUtils.standardizedRoundNameFromMatchCount(
          matches.length,
          fallbackRawName: roundMap['name']?.toString(),
        );
        if ((roundMap['name']?.toString() ?? '') != standardized) {
          roundMap['name'] = standardized;
          localChanged = true;
        }
      }
      return localChanged;
    }

    final rounds = knockout['rounds'];
    if (rounds is List<dynamic>) {
      if (normalizeRoundsList(rounds)) changed = true;
    }

    final levelBrackets = knockout['levelBrackets'];
    if (levelBrackets is Map) {
      final map = levelBrackets as Map<String, dynamic>;
      for (final level in map.keys) {
        final roundsForLevel = map[level];
        if (roundsForLevel is List<dynamic>) {
          if (normalizeRoundsList(roundsForLevel)) changed = true;
        }
      }
    }

    return changed;
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
                Card(
                  color: const Color(0xFFFFF3E0),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🏅 KNOCKOUT STAGE',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _levelBrackets.isEmpty && _rounds.isEmpty
                              ? 'Tap "Sync with tournament groups" to build per-level brackets. Top seeds get byes when odd.'
                              : _levelBrackets.isNotEmpty
                                  ? _levelBrackets.entries.map((e) => '• ${e.key}: ${e.value.fold<int>(0, (s, r) => s + r.matches.length)} matches').join('\n')
                                  : '${_rounds.map((r) => '• ${r.name} (${r.matches.length} match${r.matches.length == 1 ? "" : "es"})').join('\n')}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _syncWithTournamentGroups,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync with tournament groups'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                ),
                if (_levelBrackets.isNotEmpty || _rounds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _fillTeamNamesFromGroups,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Fill team names from group results'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Play group matches first, then tap here to populate team names.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
                const SizedBox(height: 16),
                if (_levelBrackets.isNotEmpty)
                  ...KnockoutBracketUtils.sortLevels(_levelBrackets.keys.toList()).map((level) {
                    final rounds = _levelBrackets[level]!;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        title: Text(level, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        subtitle: Text('${rounds.fold<int>(0, (s, r) => s + r.matches.length)} matches'),
                        children: rounds.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final round = entry.value;
                          final color = idx == 0 ? Colors.orange : (idx == rounds.length - 1 ? Colors.amber : Colors.deepOrange);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildStageHeader(round.name, Icons.sports_tennis, color),
                              ...round.matches.map((match) => _buildMatchCard(match, level)),
                              const SizedBox(height: 16),
                            ],
                          );
                        }).toList(),
                      ),
                    );
                  }),
                if (_rounds.isNotEmpty)
                  ..._rounds.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final round = entry.value;
                    final color = idx == 0 ? Colors.orange : (idx == _rounds.length - 1 ? Colors.amber : Colors.deepOrange);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStageHeader(round.name, Icons.sports_tennis, color),
                        ...round.matches.map((match) => _buildMatchCard(match, 'All levels')),
                        const SizedBox(height: 24),
                      ],
                    );
                  }),
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

  Widget _buildMatchCard(KnockoutMatchConfig match, [String? level]) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.sports_tennis, color: Colors.orange),
        title: Text(
          match.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(() {
          final parts = [
            if (match.court.isNotEmpty) match.court,
            if (match.date.isNotEmpty) match.date,
            if (match.startTime.isNotEmpty) match.startTime,
          ];
          return parts.isEmpty ? 'Schedule not set' : parts.join(' | ');
        }()),
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
                  teamName: match.team1Name,
                  level: level,
                  onEdit: () => _showTeamPicker(match, 1, level),
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
                  teamName: match.team2Name,
                  level: level,
                  onEdit: () => _showTeamPicker(match, 2, level),
                ),
                
                const Divider(height: 32),
                
                // Court, Date and Time
                const Text(
                  'Match Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: match.dateController,
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    hintText: 'e.g., 20 Mar 2025 or 2025-03-20',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    match.date = value;
                  },
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
    String? teamName,
    String? level,
    VoidCallback? onEdit,
  }) {
    final isWinner = type == 'winner';
    final displayType = type == 'seed' ? 'Seed' : (isWinner ? 'Winner' : 'Runner-up');
    final isBye = (teamName?.trim().toUpperCase() == 'BYE') || from.trim().toUpperCase() == 'BYE';
    final hasTeam = teamName != null && teamName.trim().isNotEmpty && !isBye;
    final canEdit = onEdit != null && !isBye;
    
    Widget content = Container(
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
                  isBye
                      ? 'BYE'
                      : (hasTeam
                          ? teamName!
                          : (type == 'seed' ? 'Seed ${from.replaceFirst('seed', '')}' : 'Team $teamNumber')),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasTeam ? Colors.black87 : null,
                  ),
                ),
                if (type != 'seed' && !isBye) Text('$displayType of $from', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (type == 'seed' && !hasTeam && !isBye)
                  Text('Tap to assign', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                if (!hasTeam && type != 'seed' && !isBye) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Will be filled after previous stage',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
              tooltip: 'Edit team',
            )
          else
            Icon(isWinner ? Icons.emoji_events : Icons.military_tech, color: isWinner ? Colors.amber : Colors.orange),
        ],
      ),
    );
    return content;
  }

  Future<void> _showTeamPicker(KnockoutMatchConfig match, int teamNum, String? level) async {
    final standings = await _calculateStandingsForLevel(level);
    if (standings.isEmpty && mounted) {
      _showSyncMessage('No advancing teams for this level. Add teams and enter match results first.');
      return;
    }
    final teams = standings;
    if (!mounted) return;
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Select team for ${teamNum == 1 ? "Team 1" : "Team 2"}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: teams.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return ListTile(
                  title: const Text('(Clear)'),
                  onTap: () => Navigator.pop(ctx, <String, dynamic>{}),
                );
              }
              final t = teams[i - 1];
              final name = t['teamName'] as String? ?? 'Unknown';
              final pts = t['points'] as int? ?? 0;
              return ListTile(
                title: Text(name),
                subtitle: Text('$pts pts'),
                onTap: () => Navigator.pop(ctx, t),
              );
            },
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        if (teamNum == 1) {
          match.team1Key = picked['teamKey']?.toString();
          match.team1Name = picked['teamName']?.toString();
        } else {
          match.team2Key = picked['teamKey']?.toString();
          match.team2Name = picked['teamName']?.toString();
        }
      });
    }
  }

  Future<void> _syncWithTournamentGroups() async {
    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      if (!doc.exists) {
        if (mounted) _showSyncMessage('Tournament not found');
        return;
      }
      final data = doc.data() as Map<String, dynamic>?;
      final type = data?['type'] as String? ?? 'simple';
      Map<String, dynamic> groupsRaw = {};
      if (type == 'two-phase-knockout') {
        final phase2 = data?['phase2'] as Map<String, dynamic>?;
        final phase1 = data?['phase1'] as Map<String, dynamic>?;
        groupsRaw = phase2?['groups'] as Map<String, dynamic>? ?? {};
        if (groupsRaw.isEmpty && phase1 != null) {
          groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
        }
      } else {
        groupsRaw = data?['groups'] as Map<String, dynamic>? ?? {};
      }
      final byLevel = KnockoutBracketUtils.groupGroupsByLevel(groupsRaw);
      if (byLevel.isEmpty) {
        if (mounted) _showSyncMessage(
          'No groups found. Raw groups keys (${groupsRaw.length}): ${groupsRaw.keys.take(5).join(", ")}',
        );
        return;
      }
      final newLevelBrackets = <String, List<KnockoutRound>>{};
      int totalMatches = 0;
      for (final level in KnockoutBracketUtils.sortLevels(byLevel.keys.toList())) {
        final groupNames = byLevel[level]!;
        final numAdvancing = groupNames.length >= 2
            ? 2 * groupNames.length
            : 4;
        if (numAdvancing < 2) continue;
        final rawRounds = KnockoutBracketUtils.buildBracketWithByes(numAdvancing, '${level.replaceAll(' ', '_')}_');
        if (rawRounds.isEmpty) continue;
        newLevelBrackets[level] = _roundsFromRaw(rawRounds);
        totalMatches += newLevelBrackets[level]!.fold<int>(0, (s, r) => s + r.matches.length);
      }
      if (newLevelBrackets.isEmpty) {
        final levelSummary = byLevel.entries.map((e) => '${e.key}:${e.value.length}grp').join(', ');
        if (mounted) _showSyncMessage('Could not build brackets. Levels found: [$levelSummary]. Each level needs ≥2 groups or ≥1 group with 4+ teams.');
        return;
      }
      _levelBrackets = newLevelBrackets;
      _rounds = [];
      if (mounted) {
        setState(() {});
        _showSyncMessage(
          'Built ${_levelBrackets.length} level bracket(s), $totalMatches total matches. Top seeds get byes when odd.',
          success: true,
        );
      }
    } catch (e) {
      if (mounted) _showSyncMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<KnockoutRound> _roundsFromRaw(List<Map<String, dynamic>> rawRounds) {
    return rawRounds.map((r) {
      final matches = <KnockoutMatchConfig>[];
      for (var m in r['matches'] as List) {
        final mMap = m as Map<String, dynamic>;
        final t1 = mMap['team1'] as Map? ?? {};
        final t2 = mMap['team2'] as Map? ?? {};
        final mc = KnockoutMatchConfig(
          id: (mMap['id'] ?? 'm').toString(),
          name: (mMap['name'] ?? 'Match').toString(),
          team1Type: (t1['type'] ?? 'seed').toString(),
          team1From: (t1['from'] ?? '').toString(),
          team2Type: (t2['type'] ?? 'seed').toString(),
          team2From: (t2['from'] ?? '').toString(),
        );
        mc.loadFromFirestore(mMap);
        if (t1['teamKey'] != null) mc.team1Key = t1['teamKey'].toString();
        if (t1['teamName'] != null) mc.team1Name = t1['teamName'].toString();
        if (t2['teamKey'] != null) mc.team2Key = t2['teamKey'].toString();
        if (t2['teamName'] != null) mc.team2Name = t2['teamName'].toString();
        matches.add(mc);
      }
      return KnockoutRound(
        name: KnockoutBracketUtils.standardizedRoundNameFromMatchCount(
          matches.length,
          fallbackRawName: r['name']?.toString(),
        ),
        matches: matches,
      );
    }).toList();
  }

  void _showSyncMessage(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? Colors.green : Colors.orange,
      ),
    );
  }

  Future<void> _fillTeamNamesFromGroups() async {
    if (_levelBrackets.isEmpty && _rounds.isEmpty) return;
    setState(() => _loading = true);
    try {
      int filled = 0;
      if (_levelBrackets.isNotEmpty) {
        for (final level in _levelBrackets.keys) {
          final advancing = await _calculateStandingsForLevel(level);
          if (advancing.isEmpty) continue;
          for (final round in _levelBrackets[level]!) {
            for (final match in round.matches) {
              filled += _fillSeedSlot(match.team1Type, match.team1From, advancing, (t) {
                match.team1Key = t['teamKey'];
                match.team1Name = t['teamName'];
              });
              filled += _fillSeedSlot(match.team2Type, match.team2From, advancing, (t) {
                match.team2Key = t['teamKey'];
                match.team2Name = t['teamName'];
              });
            }
          }
          _applyByesAndPropagateForRounds(_levelBrackets[level]!);
        }
      } else {
        final standings = await _calculateSimpleGroupStandings();
        if (standings.isNotEmpty) {
          for (final round in _rounds) {
            for (final match in round.matches) {
              filled += _fillMatchFromStandings(standings, match.team1Type, match.team1From, (t) {
                match.team1Key = t['teamKey'];
                match.team1Name = t['teamName'];
              });
              filled += _fillMatchFromStandings(standings, match.team2Type, match.team2From, (t) {
                match.team2Key = t['teamKey'];
                match.team2Name = t['teamName'];
              });
            }
          }
          _applyByesAndPropagateForRounds(_rounds);
        }
      }
      await _saveToFirestore();
      if (mounted) {
        setState(() {});
        _showSyncMessage(
          filled > 0 ? 'Filled $filled team name(s).' : 'No names filled. Add teams and enter match results first.',
          success: filled > 0,
        );
      }
    } catch (e) {
      if (mounted) _showSyncMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _fillSeedSlot(String type, String from, List<Map<String, dynamic>> advancing, void Function(Map<String, dynamic>) apply) {
    if (from.isEmpty || !from.startsWith('seed')) return 0;
    final idx = int.tryParse(from.replaceFirst('seed', '')) ?? 0;
    if (idx >= 1 && idx <= advancing.length) {
      apply(advancing[idx - 1]);
      return 1;
    }
    return 0;
  }

  void _applyByesAndPropagateForRounds(List<KnockoutRound> rounds) {
    final rawRounds = rounds
        .map((r) => {
              'name': r.name,
              'matches': r.matches.map((m) => m.toMap()).toList(),
            })
        .toList();
    KnockoutBracketUtils.applyByesToRounds(rawRounds);

    for (int ri = 0; ri < rounds.length && ri < rawRounds.length; ri++) {
      final rawMatches = (rawRounds[ri]['matches'] as List<dynamic>? ?? const []);
      for (int mi = 0; mi < rounds[ri].matches.length && mi < rawMatches.length; mi++) {
        final match = rounds[ri].matches[mi];
        final m = rawMatches[mi] as Map<String, dynamic>;
        final t1 = m['team1'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final t2 = m['team2'] as Map<String, dynamic>? ?? <String, dynamic>{};
        match.team1Key = t1['teamKey']?.toString();
        match.team1Name = t1['teamName']?.toString();
        match.team2Key = t2['teamKey']?.toString();
        match.team2Name = t2['teamName']?.toString();
        match.winner = m['winner']?.toString();
      }
    }
  }

  int _fillMatchFromStandings(
    Map<String, List<Map<String, dynamic>>> standings,
    String type,
    String from,
    void Function(Map<String, dynamic>) apply,
  ) {
    if (from.isEmpty) return 0;
    if (from.startsWith('r') && from.contains('m')) return 0;
    var list = standings[from];
    if (list == null) {
      for (final k in standings.keys) {
        if (k.toLowerCase() == from.toLowerCase()) {
          list = standings[k];
          break;
        }
      }
    }
    if (list == null || list.isEmpty) return 0;
    final team = type == 'winner' ? list[0] : (list.length > 1 ? list[1] : null);
    if (team != null) {
      apply(team);
      return 1;
    }
    return 0;
  }

  /// Advancing teams for a level (1st+2nd from each group), sorted by points desc.
  Future<List<Map<String, dynamic>>> _calculateStandingsForLevel(String? level) async {
    final allStandings = await _calculateSimpleGroupStandings();
    if (allStandings.isEmpty) return [];
    final doc = await FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId).get();
    final data = doc.data() as Map<String, dynamic>?;
    final type = data?['type'] as String? ?? 'simple';
    Map<String, dynamic> groupsRaw = {};
    if (type == 'two-phase-knockout') {
      final phase2 = data?['phase2'] as Map<String, dynamic>?;
      final phase1 = data?['phase1'] as Map<String, dynamic>?;
      groupsRaw = phase2?['groups'] as Map<String, dynamic>? ?? {};
      if (groupsRaw.isEmpty && phase1 != null) {
        groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
      }
    } else {
      groupsRaw = data?['groups'] as Map<String, dynamic>? ?? {};
    }
    final byLevel = KnockoutBracketUtils.groupGroupsByLevel(groupsRaw);
    List<String> groupsForLevel;
    if (level == null || level == 'All levels') {
      groupsForLevel = allStandings.keys.toList();
    } else {
      groupsForLevel = byLevel[level] ?? [];
      if (groupsForLevel.isEmpty) {
        for (final k in byLevel.keys) {
          if (k.toLowerCase() == level.toLowerCase()) {
            groupsForLevel = byLevel[k]!;
            break;
          }
        }
      }
    }
    final advancing = <Map<String, dynamic>>[];
    for (final g in groupsForLevel) {
      final list = allStandings[g];
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
    return advancing;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _calculateSimpleGroupStandings() async {
    final doc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();
    final data = doc.data() as Map<String, dynamic>?;
    final type = data?['type'] as String? ?? 'simple';
    Map<String, dynamic> groupsRaw = {};
    if (type == 'two-phase-knockout') {
      final phase2 = data?['phase2'] as Map<String, dynamic>?;
      final phase1 = data?['phase1'] as Map<String, dynamic>?;
      groupsRaw = phase2?['groups'] as Map<String, dynamic>? ?? {};
      if (groupsRaw.isEmpty && phase1 != null) {
        groupsRaw = phase1['groups'] as Map<String, dynamic>? ?? {};
      }
    } else {
      groupsRaw = data?['groups'] as Map<String, dynamic>? ?? {};
    }
    if (groupsRaw.isEmpty) return {};
    final groupsForStandings = <String, dynamic>{};
    for (var entry in groupsRaw.entries) {
      final groupData = entry.value;
      List<String> teamKeys = [];
      if (groupData is List) {
        teamKeys = groupData.map((e) => e.toString()).toList();
      } else if (groupData is Map) {
        final data = groupData as Map<String, dynamic>;
        final fromKeys = data['teamKeys'] as List<dynamic>?;
        if (fromKeys != null && fromKeys.isNotEmpty) {
          teamKeys = fromKeys.map((e) => e.toString()).toList();
        } else {
          for (final s in data['teamSlots'] as List<dynamic>? ?? []) {
            if (s is Map) {
              final k = (s as Map)['teamKey']?.toString();
              if (k != null && k.isNotEmpty) teamKeys.add(k);
            }
          }
        }
      }
      if (teamKeys.isNotEmpty) {
        groupsForStandings[entry.key] = {'teamKeys': teamKeys};
      }
    }
    if (groupsForStandings.isEmpty) return {};
    final regs = await FirebaseFirestore.instance
        .collection('tournamentRegistrations')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .where('status', isEqualTo: 'approved')
        .get();
    final matches = await FirebaseFirestore.instance
        .collection('tournamentMatches')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .get();
    return _computeGroupStandings(matches.docs, regs.docs, groupsForStandings);
  }

  Map<String, List<Map<String, dynamic>>> _computeGroupStandings(
    List<QueryDocumentSnapshot> matchDocs,
    List<QueryDocumentSnapshot> regDocs,
    Map<String, dynamic> groups,
  ) {
    final allTeamStats = <String, Map<String, dynamic>>{};
    String genKey(Map<String, dynamic> d) {
      final uid = d['userId'] as String?;
      final p = d['partner'] as Map?;
      if (p != null && p['partnerId'] != null) {
        final uids = [uid, p['partnerId']]..sort();
        return uids.join('_');
      }
      return uid ?? '';
    }
    for (var r in regDocs) {
      final d = r.data() as Map<String, dynamic>;
      final key = genKey(d);
      if (key.isEmpty) continue;
      final fn = d['firstName'] ?? '';
      final ln = d['lastName'] ?? '';
      final pn = (d['partner'] as Map?)?['partnerName'] ?? 'Unknown';
      allTeamStats[key] = {
        'teamKey': key,
        'teamName': (d['partner'] != null) ? '$fn $ln & $pn' : '$fn $ln',
        'points': 0,
        'scoreDifference': 0,
        'gamesPlayed': 0,
      };
    }
    String? resolve(String k) {
      if (allTeamStats.containsKey(k)) return k;
      final t = k.replaceAll(RegExp(r'_+$'), '').replaceAll(RegExp(r'^_+'), '');
      if (allTeamStats.containsKey(t)) return t;
      final parts = k.split('_').where((s) => s.isNotEmpty).toList()..sort();
      if (parts.length >= 2 && allTeamStats.containsKey(parts.join('_'))) return parts.join('_');
      return null;
    }
    for (var m in matchDocs) {
      final d = m.data() as Map<String, dynamic>;
      final t1 = resolve(d['team1Key']?.toString() ?? '');
      final t2 = resolve(d['team2Key']?.toString() ?? '');
      if (t1 == null || t2 == null) continue;
      allTeamStats[t1]!['gamesPlayed'] = (allTeamStats[t1]!['gamesPlayed'] as int) + 1;
      allTeamStats[t2]!['gamesPlayed'] = (allTeamStats[t2]!['gamesPlayed'] as int) + 1;
      final w = d['winner']?.toString();
      final diff = d['scoreDifference'] as int? ?? 0;
      if (w == 'team1') {
        allTeamStats[t1]!['points'] = (allTeamStats[t1]!['points'] as int) + 3;
        allTeamStats[t1]!['scoreDifference'] = (allTeamStats[t1]!['scoreDifference'] as int) + diff;
        allTeamStats[t2]!['scoreDifference'] = (allTeamStats[t2]!['scoreDifference'] as int) - diff;
      } else if (w == 'team2') {
        allTeamStats[t2]!['points'] = (allTeamStats[t2]!['points'] as int) + 3;
        allTeamStats[t2]!['scoreDifference'] = (allTeamStats[t2]!['scoreDifference'] as int) + diff;
        allTeamStats[t1]!['scoreDifference'] = (allTeamStats[t1]!['scoreDifference'] as int) - diff;
      }
    }
    final result = <String, List<Map<String, dynamic>>>{};
    for (var e in groups.entries) {
      final keys = (e.value is Map)
          ? ((e.value as Map)['teamKeys'] as List?)?.map((x) => x.toString()).toList() ?? []
          : (e.value as List).map((x) => x.toString()).toList();
      final list = <Map<String, dynamic>>[];
      for (var k in keys) {
        if (allTeamStats.containsKey(k)) list.add(Map.from(allTeamStats[k]!));
      }
      list.sort((a, b) {
        final cp = (b['points'] as int).compareTo(a['points'] as int);
        if (cp != 0) return cp;
        return (b['scoreDifference'] as int).compareTo(a['scoreDifference'] as int);
      });
      result[e.key] = list;
    }
    return result;
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

  Future<void> _saveToFirestore() async {
    final knockoutData = _buildKnockoutData();
    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({
      'knockout': knockoutData,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Map<String, dynamic> _buildKnockoutData() {
    final data = <String, dynamic>{};
    if (_levelBrackets.isNotEmpty) {
      data['levelBrackets'] = _levelBrackets.map((level, rounds) => MapEntry(
        level,
        rounds.map((r) => {'name': r.name, 'matches': r.matches.map((m) => m.toMap()).toList()}).toList(),
      ));
    }
    if (_rounds.isNotEmpty) {
      data['rounds'] = _rounds.map((r) => {'name': r.name, 'matches': r.matches.map((m) => m.toMap()).toList()}).toList();
      data['quarterFinals'] = _rounds[0].matches.map((m) => m.toMap()).toList();
      if (_rounds.length > 1) data['semiFinals'] = _rounds[1].matches.map((m) => m.toMap()).toList();
      if (_rounds.isNotEmpty && _rounds.last.matches.length == 1) data['final'] = _rounds.last.matches[0].toMap();
    }
    return data;
  }

  Future<void> _saveConfiguration() async {
    setState(() {
      _loading = true;
    });

    try {
      final knockoutData = _buildKnockoutData();

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

/// A round in the knockout bracket
class KnockoutRound {
  final String name;
  final List<KnockoutMatchConfig> matches;
  KnockoutRound({required this.name, required this.matches});
}

/// Configuration class for knockout match
class KnockoutMatchConfig {
  final String id;
  final String name;
  
  String team1Type;
  String team1From;
  String? team1Key;
  String? team1Name;
  
  String team2Type;
  String team2From;
  String? team2Key;
  String? team2Name;
  
  String? winner;
  
  String court = '';
  String startTime = '';
  String endTime = '';
  String date = '';

  final TextEditingController courtController = TextEditingController();
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();
  final TextEditingController dateController = TextEditingController();

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
      team1Name = team1['teamName'] as String?;
    }

    final team2 = data['team2'] as Map<String, dynamic>?;
    if (team2 != null) {
      team2Type = team2['type'] as String? ?? team2Type;
      team2From = team2['from'] as String? ?? team2From;
      team2Key = team2['teamKey'] as String?;
      team2Name = team2['teamName'] as String?;
    }

    winner = data['winner'] as String?;

    final schedule = data['schedule'] as Map<String, dynamic>?;
    if (schedule != null) {
      court = schedule['court'] as String? ?? '';
      startTime = schedule['startTime'] as String? ?? '';
      endTime = schedule['endTime'] as String? ?? '';
      date = schedule['date'] as String? ?? '';

      courtController.text = court;
      startTimeController.text = startTime;
      endTimeController.text = endTime;
      dateController.text = date;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'team1': {
        'type': team1Type,
        'from': team1From,
        'teamKey': team1Key,
        'teamName': team1Name,
      },
      'team2': {
        'type': team2Type,
        'from': team2From,
        'teamKey': team2Key,
        'teamName': team2Name,
      },
      'schedule': {
        'court': court,
        'startTime': startTime,
        'endTime': endTime,
        if (date.isNotEmpty) 'date': date,
      },
      'winner': winner,
    };
  }
}
