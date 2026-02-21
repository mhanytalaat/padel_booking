import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/knockout_bracket_utils.dart';

class TournamentGroupsScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;

  const TournamentGroupsScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<TournamentGroupsScreen> createState() => _TournamentGroupsScreenState();
}

class _TournamentGroupsScreenState extends State<TournamentGroupsScreen> {
  bool _isAdmin = false;
  bool _checkingAdmin = true;

  // Admin credentials
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com';

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
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

  // Generate team key from registration (normalized: trimmed for consistency)
  String _generateTeamKey(Map<String, dynamic> registration) {
    final userId = (registration['userId'] as String? ?? '').toString().trim();
    if (userId.isEmpty) return '';
    final partner = registration['partner'] as Map<String, dynamic>?;
    
    if (partner != null) {
      final partnerId = (partner['partnerId'] as String? ?? '').toString().trim();
      if (partnerId.isNotEmpty) {
        final userIds = [userId, partnerId];
        userIds.sort();
        return userIds.join('_');
      }
    }
    return userId;
  }

  /// Normalized name key for deduplication (same pair = same key regardless of order)
  /// Also builds from all regs so we can match teamKeys that don't directly match a reg
  String _getNameKeyForTeam(String teamKey, List<QueryDocumentSnapshot> registrations) {
    for (final reg in registrations) {
      if (_generateTeamKey(reg.data() as Map<String, dynamic>) == teamKey) {
        final d = reg.data() as Map<String, dynamic>;
        final n1 = '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim().toLowerCase();
        final partner = d['partner'] as Map<String, dynamic>?;
        final n2 = (partner?['partnerName'] as String? ?? '').trim().toLowerCase();
        if (n1.isEmpty && n2.isEmpty) return teamKey;
        final names = [n1, n2].where((s) => s.isNotEmpty).toList()..sort();
        return names.isEmpty ? teamKey : names.join('|');
      }
    }
    return teamKey;
  }

  // Get team name from registration
  String _getTeamNameByKey(String teamKey, List<QueryDocumentSnapshot> registrations) {
    for (var reg in registrations) {
      if (_generateTeamKey(reg.data() as Map<String, dynamic>) == teamKey) {
        return _getTeamName(reg.data() as Map<String, dynamic>);
      }
    }
    return teamKey.isEmpty ? '' : 'Unknown';
  }

  String _getTeamName(Map<String, dynamic> registration) {
    final firstName = registration['firstName'] as String? ?? '';
    final lastName = registration['lastName'] as String? ?? '';
    final partner = registration['partner'] as Map<String, dynamic>?;
    
    if (partner != null) {
      final partnerName = partner['partnerName'] as String? ?? 'Unknown';
      return '$firstName $lastName & $partnerName';
    }
    return '$firstName $lastName';
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.tournamentName} - Groups'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        actions: _isAdmin
            ? [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showCreateGroupsDialog(),
                  tooltip: 'Create/Update Groups',
                ),
              ]
            : null,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .snapshots(),
        builder: (context, tournamentSnapshot) {
          if (tournamentSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!tournamentSnapshot.hasData || !tournamentSnapshot.data!.exists) {
            return const Center(child: Text('Tournament not found'));
          }

          final tournamentData = tournamentSnapshot.data!.data() as Map<String, dynamic>?;
          if (tournamentData == null) {
            return const Center(child: Text('No tournament data'));
          }

          final groups = tournamentData['groups'] as Map<String, dynamic>? ?? {};

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tournamentRegistrations')
                .where('tournamentId', isEqualTo: widget.tournamentId)
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            builder: (context, registrationsSnapshot) {
              if (registrationsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!registrationsSnapshot.hasData) {
                return const Center(child: Text('Error loading registrations'));
              }

              final registrations = registrationsSnapshot.data!.docs;
              if (groups.isNotEmpty && registrations.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _autoFixDuplicateTeamsInAllGroups(groups, registrations);
                });
              }
              
              if (registrations.isEmpty) {
                return const Center(
                  child: Text('No approved teams yet'),
                );
              }

              if (groups.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No groups created yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Tap + to create groups',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                );
              }

              // Check if there are approved teams available (not in a group at their level)
              // Teams can join different levels - only exclude if in a group at the SAME level
              final approvedTeams = registrations.where((reg) {
                final data = reg.data() as Map<String, dynamic>;
                final teamKey = _generateTeamKey(data);
                final regLevel = (data['level'] as String? ?? '').trim();
                for (var entry in groups.entries) {
                  final groupData = entry.value;
                  final gLevel = groupData is Map ? (groupData['level'] as String?) ?? '' : null;
                  if (regLevel.isNotEmpty && gLevel != null && gLevel != regLevel) continue;
                  List<String> teamKeys;
                  if (groupData is List) {
                    teamKeys = groupData.map((e) => e.toString()).toList();
                  } else if (groupData is Map && groupData['teamKeys'] is List) {
                    teamKeys = (groupData['teamKeys'] as List).map((e) => e.toString()).toList();
                  } else {
                    teamKeys = [];
                  }
                  if (teamKeys.contains(teamKey)) return false;
                }
                return true;
              }).toList();

              // Build group display – categorized by level
              final byLevel = _groupGroupsByLevel(groups);
              final sortedLevels = _sortedLevels(byLevel);
              
              return Column(
                children: [
                  if (_isAdmin && approvedTeams.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (groups.isNotEmpty)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _distributeTeamsRandomly,
                                icon: const Icon(Icons.shuffle),
                                label: const Text('Distribute Teams Randomly'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E3A8A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                          if (groups.isNotEmpty)
                            const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _createGroupsByLevel,
                              icon: const Icon(Icons.category),
                              label: const Text('Auto-Group by Level'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ),
                          if (groups.isNotEmpty) const SizedBox(height: 8),
                          if (groups.isNotEmpty)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _cleanDuplicateTeams,
                                icon: const Icon(Icons.cleaning_services, size: 20),
                                label: const Text('Clean Duplicate Teams'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange[800],
                                  side: BorderSide(color: Colors.orange[700]!),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('groups_list'),
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final levelLabel in sortedLevels) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.stacked_bar_chart, size: 20, color: const Color(0xFF1E3A8A)),
                                const SizedBox(width: 8),
                                Text(
                                  levelLabel,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final groupName in byLevel[levelLabel]!)
                            _buildGroupCard(
                              groupName,
                              groups,
                              registrations,
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _autoFixDuplicateTeamsInAllGroups(
    Map<String, dynamic> groups,
    List<QueryDocumentSnapshot>? registrations,
  ) async {
    if (registrations == null || registrations.isEmpty) return;
    try {
      final updated = Map<String, dynamic>.from(groups);
      bool changed = false;
      for (final groupName in groups.keys.toList()) {
        final g = groups[groupName];
        List<String> rawKeys;
        if (g is List) {
          rawKeys = g.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        } else if (g is Map && g['teamKeys'] is List) {
          rawKeys = (g['teamKeys'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        } else {
          continue;
        }
        final cleanKeys = _deduplicateTeamKeys(rawKeys, registrations);
        if (cleanKeys.length < rawKeys.length) {
          changed = true;
          if (g is Map) {
            updated[groupName] = Map<String, dynamic>.from(g as Map)..['teamKeys'] = cleanKeys;
          } else {
            updated[groupName] = cleanKeys;
          }
        }
      }
      if (changed) {
        await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .update({'groups': updated});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Duplicate teams removed automatically'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (_) {}
  }

  /// Deduplicate teamKeys (exact + name-based). Returns clean list.
  List<String> _deduplicateTeamKeys(List<String> teamKeys, List<QueryDocumentSnapshot> registrations) {
    if (teamKeys.isEmpty) return teamKeys;
    var result = teamKeys.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    final seen = <String>{};
    result = result.where((k) => seen.add(k)).toList();
    if (registrations.isEmpty) return result;
    final seenNameKeys = <String>{};
    result = result.where((k) {
      final nameKey = _getNameKeyForTeam(k, registrations);
      return seenNameKeys.add(nameKey);
    }).toList();
    return result;
  }

  Widget _buildGroupCard(
    String groupName,
    Map<String, dynamic> groups,
    List<QueryDocumentSnapshot> registrations,
  ) {
    final groupData = groups[groupName];
    List<String> rawTeamKeys;
    Map<String, dynamic>? schedule;
    String? groupLevel;

    if (groupData is List) {
      rawTeamKeys = groupData.map((e) => e.toString()).toList();
      schedule = null;
      groupLevel = null;
    } else if (groupData is Map) {
      rawTeamKeys = (groupData['teamKeys'] as List?)?.map((e) => e.toString()).toList() ?? [];
      schedule = groupData['schedule'] as Map<String, dynamic>?;
      groupLevel = groupData['level'] as String?;
    } else {
      rawTeamKeys = [];
      schedule = null;
      groupLevel = null;
    }

    final teamKeys = _deduplicateTeamKeys(rawTeamKeys, registrations);

    final teamsInGroup = teamKeys.map((k) {
      for (final reg in registrations) {
        if (_generateTeamKey(reg.data() as Map<String, dynamic>) == k) {
          return reg;
        }
      }
      return null;
    }).whereType<QueryDocumentSnapshot>().toList();

    String subtitle = '${teamKeys.length} teams';
    if (groupLevel != null) subtitle += ' • $groupLevel';
    if (schedule != null) {
      final court = schedule['court'] as String? ?? '';
      final startTime = schedule['startTime'] as String? ?? '';
      if (court.isNotEmpty || startTime.isNotEmpty) {
        subtitle += ' | ${court.isNotEmpty ? court : 'No court'} @ ${startTime.isNotEmpty ? startTime : 'No time'}';
      }
    }

    return Card(
      key: ValueKey('group_$groupName'),
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1E3A8A),
          child: Text(
            groupName.split(' ').last,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        title: Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        subtitle: Text(subtitle),
        children: [
          if (_isAdmin)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 18, color: Color(0xFF1E3A8A)),
                      const SizedBox(width: 8),
                      const Text('Match Schedule', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showEditScheduleDialog(groupName, schedule ?? {}, teamKeys, registrations),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Edit Schedule'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (schedule != null) ...[
                    Text('Court: ${schedule['court'] ?? 'Not set'}'),
                    Text('Time: ${schedule['startTime'] ?? 'Not set'}'),
                    if (schedule['endTime'] != null) Text('End: ${schedule['endTime']}'),
                    if ((schedule['orderOfPlay'] as List?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      const Text('Order of Play:', style: TextStyle(fontWeight: FontWeight.w600)),
                      ...(schedule['orderOfPlay'] as List).asMap().entries.map((e) {
                        final m = e.value as Map<dynamic, dynamic>?;
                        final t1 = _getTeamNameByKey(m?['team1Key']?.toString() ?? '', registrations);
                        final t2 = _getTeamNameByKey(m?['team2Key']?.toString() ?? '', registrations);
                        if (t1.isEmpty && t2.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e.key + 1}. $t1', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('vs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                              const SizedBox(height: 2),
                              Text(t2, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        );
                      }),
                    ],
                  ] else
                    const Text('No schedule set', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          if (teamsInGroup.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No teams assigned to this group'))
          else
            ...teamsInGroup.map((reg) {
              final data = reg.data() as Map<String, dynamic>;
              final teamName = _getTeamName(data);
              return ListTile(
                leading: const Icon(Icons.people, color: Color(0xFF1E3A8A)),
                title: Text(teamName),
                trailing: _isAdmin
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.red, size: 20),
                        onPressed: () => _removeTeamFromGroup(groupName, _generateTeamKey(data)),
                      )
                    : null,
              );
            }),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ElevatedButton.icon(
                onPressed: () => _showAddTeamToGroupDialog(groupName, registrations, teamKeys, groups, groupLevel),
                icon: const Icon(Icons.add),
                label: const Text('Add Team to Group'),
              ),
            ),
        ],
      ),
    );
  }

  static const List<String> _levelOptions = [
    'C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women',
  ];

  static const List<String> _levelOrder = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];

  Map<String, List<String>> _groupGroupsByLevel(Map<String, dynamic> groups) {
    final byLevel = <String, List<String>>{};
    for (final groupName in groups.keys) {
      final groupValue = groups[groupName];
      String levelLabel = 'All levels';
      if (groupValue is Map) {
        final level = (groupValue as Map<String, dynamic>)['level'] as String?;
        if (level != null && level.isNotEmpty) levelLabel = level;
      }
      if (levelLabel == 'All levels') {
        final inferred = KnockoutBracketUtils.levelFromGroupName(groupName);
        if (inferred != null && inferred.isNotEmpty) levelLabel = inferred;
      }
      byLevel.putIfAbsent(levelLabel, () => []).add(groupName);
    }
    for (final list in byLevel.values) {
      list.sort((a, b) {
        final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (numA != numB) return numA.compareTo(numB);
        return a.compareTo(b);
      });
    }
    return byLevel;
  }

  List<String> _sortedLevels(Map<String, List<String>> byLevel) {
    return byLevel.keys.toList()
      ..sort((a, b) {
        if (a == 'All levels') return 1;
        if (b == 'All levels') return -1;
        final ia = _levelOrder.indexOf(a);
        final ib = _levelOrder.indexOf(b);
        if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
        if (ia >= 0) return -1;
        if (ib >= 0) return 1;
        return a.compareTo(b);
      });
  }

  /// Suggest number of groups for a given team count (standard: 3 teams per group).
  static int _suggestedGroupsForTeamCount(int teams) {
    if (teams <= 0) return 1;
    const maxPerGroup = 3;
    return (teams / maxPerGroup).ceil().clamp(1, 999);
  }

  Future<void> _showCreateGroupsDialog() async {
    // Fetch registrations and count unique teams per level (dedupe by teamKey)
    Map<String, int> teamsPerLevel = {};
    try {
      final regs = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .get();
      final seenByLevel = <String, Set<String>>{};
      for (final doc in regs.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['userId'] == null) continue;
        final level = (data['level'] as String? ?? 'Beginners').trim();
        final teamKey = _generateTeamKey(data);
        if (teamKey.isEmpty) continue;
        seenByLevel.putIfAbsent(level, () => {}).add(teamKey);
      }
      for (final e in seenByLevel.entries) {
        teamsPerLevel[e.key] = e.value.length;
      }
    } catch (_) {}

    final levelOrder = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];
    final sortedLevels = teamsPerLevel.keys.toList()
      ..sort((a, b) {
        final ia = levelOrder.indexOf(a);
        final ib = levelOrder.indexOf(b);
        if (ia == -1 && ib == -1) return a.compareTo(b);
        if (ia == -1) return 1;
        if (ib == -1) return -1;
        return ia.compareTo(ib);
      });

    final groupCountController = TextEditingController(text: '3');
    String? selectedLevel;

    // Pre-fill with first level's suggestion when available
    if (sortedLevels.isNotEmpty) {
      selectedLevel = sortedLevels.first;
      final count = teamsPerLevel[selectedLevel] ?? 0;
      groupCountController.text = '${_suggestedGroupsForTeamCount(count)}';
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Groups'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add groups for a level. You can add Seniors, then Beginners, then D, etc. – each batch is merged with existing groups.',
                ),
                if (teamsPerLevel.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Based on approved registrations:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...sortedLevels.map((level) {
                    final count = teamsPerLevel[level]!;
                    final suggested = _suggestedGroupsForTeamCount(count);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '$level: $count team${count == 1 ? '' : 's'} → suggest $suggested group${suggested == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                TextField(
                controller: groupCountController,
                decoration: const InputDecoration(
                  labelText: 'Number of Groups',
                  hintText: 'e.g., 3 or 4',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedLevel,
                decoration: const InputDecoration(
                  labelText: 'Level (categorizes this set of groups)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All levels (mixed)')),
                  ..._levelOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))),
                ],
                onChanged: (v) {
                  setDialogState(() {
                    selectedLevel = v;
                    if (v != null && teamsPerLevel.containsKey(v)) {
                      groupCountController.text = '${_suggestedGroupsForTeamCount(teamsPerLevel[v]!)}';
                    }
                  });
                },
              ),
            ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final count = int.tryParse(groupCountController.text);
                if (count == null || count < 1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid number'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                await _createGroups(count, level: selectedLevel);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroups(int count, {String? level}) async {
    try {
      // Merge with existing groups (allow adding Seniors, then Beginners, then D, etc.)
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();
      final existing = doc.data()?['groups'] as Map<String, dynamic>? ?? {};
      final groups = <String, Map<String, dynamic>>{};
      for (final e in existing.entries) {
        final v = e.value;
        if (v is Map) {
          groups[e.key] = Map<String, dynamic>.from(v as Map);
        } else if (v is List) {
          groups[e.key] = {
            'teamKeys': v.map((x) => x.toString()).toList(),
            'schedule': <String, dynamic>{},
          };
        }
      }

      final prefix = level != null ? '$level - ' : '';
      // Find next group number for this prefix (e.g. "D - Group 1", "D - group 2" -> next is 3)
      int startNum = 1;
      for (final k in groups.keys) {
        if (k.startsWith(prefix) && RegExp(r'[Gg]roup\s*\d+').hasMatch(k)) {
          final numMatch = RegExp(r'[Gg]roup\s*(\d+)').firstMatch(k);
          if (numMatch != null) {
            final n = int.tryParse(numMatch.group(1) ?? '1') ?? 1;
            if (n >= startNum) startNum = n + 1;
          }
        }
      }
      for (int i = 0; i < count; i++) {
        final name = '${prefix}Group ${startNum + i}';
        groups[name] = {
          'teamKeys': [],
          'schedule': {'court': '', 'startTime': ''},
          if (level != null) 'level': level,
        };
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'groups': groups});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created $count empty groups'),
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
    }
  }

  // Randomly distribute teams to groups (respecting level: only put teams in groups of their level)
  Future<void> _distributeTeamsRandomly() async {
    try {
      // Get all approved teams
      final registrations = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .get();

      if (registrations.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No approved teams to assign to groups'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Get current groups
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      if (!tournamentDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tournament not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final tournamentData = tournamentDoc.data() as Map<String, dynamic>;
      final groups = Map<String, dynamic>.from(tournamentData['groups'] as Map<String, dynamic>? ?? {});

      if (groups.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please create groups first'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Group teams by their registration level (dedupe by teamKey - one team per level)
      final teamsByLevel = <String, List<String>>{};
      for (final doc in registrations.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['userId'] == null) continue;
        final level = (data['level'] as String? ?? 'Beginners').trim();
        final teamKey = _generateTeamKey(data);
        teamsByLevel.putIfAbsent(level, () => []).add(teamKey);
      }
      for (final key in teamsByLevel.keys) {
        teamsByLevel[key] = teamsByLevel[key]!.toSet().toList();
      }

      // Shuffle each level's teams
      for (final list in teamsByLevel.values) {
        list.shuffle();
      }

      // Group names by level (same logic as _groupGroupsByLevel)
      final groupsByLevel = <String, List<String>>{};
      for (final groupName in groups.keys) {
        final groupValue = groups[groupName];
        String levelLabel = 'All levels';
        if (groupValue is Map) {
          final level = (groupValue as Map<String, dynamic>)['level'] as String?;
          if (level != null && level.isNotEmpty) levelLabel = level;
        }
        groupsByLevel.putIfAbsent(levelLabel, () => []).add(groupName);
      }

      // Clear existing teams from groups, keep structure and level
      final updatedGroups = <String, dynamic>{};
      for (var entry in groups.entries) {
        final groupName = entry.key;
        final groupData = entry.value;

        if (groupData is Map && groupData['schedule'] != null) {
          updatedGroups[groupName] = {
            'teamKeys': [],
            'schedule': groupData['schedule'],
            if (groupData['level'] != null) 'level': groupData['level'],
          };
        } else {
          updatedGroups[groupName] = [];
        }
      }

      // Distribute each level's teams only to that level's groups
      int totalDistributed = 0;
      for (final level in groupsByLevel.keys) {
        final levelGroupNames = groupsByLevel[level]!;
        final levelTeams = teamsByLevel[level] ?? [];

        for (int i = 0; i < levelTeams.length; i++) {
          final groupIndex = i % levelGroupNames.length;
          final groupName = levelGroupNames[groupIndex];
          final groupData = updatedGroups[groupName];

          if (groupData is List) {
            groupData.add(levelTeams[i]);
          } else if (groupData is Map && groupData['teamKeys'] is List) {
            (groupData['teamKeys'] as List).add(levelTeams[i]);
          }
          totalDistributed++;
        }
      }

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'groups': updatedGroups.map((key, value) => MapEntry(key, value)),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Randomly distributed $totalDistributed teams by level'),
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
    }
  }

  Future<void> _showAddTeamToGroupDialog(
    String groupName,
    List<QueryDocumentSnapshot> allRegistrations,
    List<String> currentTeamKeys,
    Map<String, dynamic> allGroups, [
    String? groupLevel,
  ]) async {
    // Build: teamKey -> which group it's in (for "Already in X" label)
    // Only consider groups of the SAME level - teams can be in different levels (e.g. D + Beginners)
    final teamKeyToGroup = <String, String>{};
    for (final groupEntry in allGroups.entries) {
      final gName = groupEntry.key;
      final groupValue = groupEntry.value;
      if (groupLevel != null && groupLevel.isNotEmpty) {
        final gLevel = groupValue is Map ? (groupValue['level'] as String?) ?? '' : null;
        if (gLevel != groupLevel) continue;
      }
      List<String> keys;
      if (groupValue is List) {
        keys = groupValue.map((e) => e.toString()).toList();
      } else if (groupValue is Map && groupValue['teamKeys'] != null) {
        keys = (groupValue['teamKeys'] as List).map((e) => e.toString()).toList();
      } else {
        keys = [];
      }
      for (final k in keys) {
        teamKeyToGroup[k] = gName;
      }
    }
    final allAssignedTeamKeys = teamKeyToGroup.keys.toSet();

    // All teams per level (deduped) - show ALL teams, mark assigned ones
    const levelOrder = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];
    final teamsByLevel = <String, List<QueryDocumentSnapshot>>{};
    final seenByLevel = <String, Set<String>>{};
    for (final reg in allRegistrations) {
      final data = reg.data() as Map<String, dynamic>;
      if (data['userId'] == null) continue;
      final level = (data['level'] as String? ?? 'Other').trim();
      if (groupLevel != null && groupLevel.isNotEmpty && level != groupLevel) continue;
      final teamKey = _generateTeamKey(data);
      if (teamKey.isEmpty) continue;
      if (seenByLevel.putIfAbsent(level, () => {}).add(teamKey)) {
        teamsByLevel.putIfAbsent(level, () => []).add(reg);
      }
    }

    final totalByLevel = <String, int>{};
    for (final e in teamsByLevel.entries) {
      totalByLevel[e.key] = e.value.length;
    }

    final availableCountByLevel = <String, int>{};
    for (final e in teamsByLevel.entries) {
      final count = e.value.where((reg) {
        final k = _generateTeamKey(reg.data() as Map<String, dynamic>);
        return !allAssignedTeamKeys.contains(k);
      }).length;
      availableCountByLevel[e.key] = count;
    }

    if (teamsByLevel.isEmpty || teamsByLevel.values.every((l) => l.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No teams for this level'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Sort levels: known first (in order), then "Other"
    final sortedLevels = teamsByLevel.keys.toList()
      ..sort((a, b) {
        final aIndex = levelOrder.indexOf(a);
        final bIndex = levelOrder.indexOf(b);
        if (aIndex >= 0 && bIndex >= 0) return aIndex.compareTo(bIndex);
        if (aIndex >= 0) return -1;
        if (bIndex >= 0) return 1;
        return a.compareTo(b);
      });

    Set<String> selectedTeamKeys = {};
    final scaffoldContext = context;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Team to $groupName'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Select teams to add. Teams are grouped by level:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...sortedLevels.map((level) {
                    final teams = teamsByLevel[level]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            children: [
                              Icon(Icons.star, size: 16, color: Colors.amber[700]),
                              const SizedBox(width: 6),
                              Text(
                                level,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${totalByLevel[level] ?? 0} teams, ${availableCountByLevel[level] ?? 0} available)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...teams.map((reg) {
                          final data = reg.data() as Map<String, dynamic>;
                          final teamName = _getTeamName(data);
                          final teamKey = _generateTeamKey(data);
                          final assignedTo = teamKeyToGroup[teamKey];
                          final isAvailable = assignedTo == null;

                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: CheckboxListTile(
                              title: Text(teamName),
                              subtitle: assignedTo != null
                                  ? Text(
                                      'Already in $assignedTo',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  : null,
                              value: selectedTeamKeys.contains(teamKey),
                              onChanged: isAvailable
                                  ? (checked) {
                                      setDialogState(() {
                                        if (checked == true) {
                                          selectedTeamKeys.add(teamKey);
                                        } else {
                                          selectedTeamKeys.remove(teamKey);
                                        }
                                      });
                                    }
                                  : null,
                              activeColor: isAvailable ? null : Colors.grey,
                            ),
                          );
                        }),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedTeamKeys.isEmpty
                  ? null
                  : () async {
                      final keysToAdd = Set<String>.from(selectedTeamKeys);
                      Navigator.pop(context);
                      try {
                        await _addTeamsToGroup(groupName, keysToAdd);
                        if (scaffoldContext.mounted) {
                          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                keysToAdd.length == 1
                                    ? '1 team added to $groupName'
                                    : '${keysToAdd.length} teams added to $groupName',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (scaffoldContext.mounted) {
                          ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                            SnackBar(
                              content: Text('Error adding teams: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: Text(
                selectedTeamKeys.isEmpty
                    ? 'Add (0 selected)'
                    : 'Add (${selectedTeamKeys.length} selected)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Add multiple teams to a group in a single Firestore update (avoids race conditions)
  Future<void> _addTeamsToGroup(String groupName, Set<String> teamKeys) async {
    if (teamKeys.isEmpty) return;

    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();

    final data = tournamentDoc.data() as Map<String, dynamic>?;
    final groups = Map<String, dynamic>.from(data?['groups'] as Map<String, dynamic>? ?? {});
    final groupData = groups[groupName];

    List<String> groupTeams;
    if (groupData is List) {
      groupTeams = List<String>.from(groupData);
    } else if (groupData is Map && groupData['teamKeys'] is List) {
      groupTeams = List<String>.from(groupData['teamKeys'] as List);
    } else {
      groupTeams = [];
    }

    for (final teamKey in teamKeys) {
      if (!groupTeams.contains(teamKey)) {
        groupTeams.add(teamKey);
      }
    }

    // Remove any existing duplicates before save (safety)
    final seen = <String>{};
    groupTeams = groupTeams.where((k) => seen.add(k)).toList();

    if (groupData is Map) {
      groups[groupName] = Map<String, dynamic>.from(groupData)
        ..['teamKeys'] = groupTeams;
    } else {
      groups[groupName] = groupTeams;
    }

    await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .update({'groups': groups});
  }

  /// Removes duplicate teams from all groups (exact + name-based dedup)
  Future<void> _cleanDuplicateTeams() async {
    try {
      // Force server read to avoid stale cache (StreamBuilder may have newer data than get())
      DocumentSnapshot tournamentDoc;
      try {
        tournamentDoc = await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .get(const GetOptions(source: Source.server));
      } on Exception {
        tournamentDoc = await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .get();
      }
      final rawGroups = (tournamentDoc.data() as Map<String, dynamic>?)?['groups'];
      if (rawGroups == null || rawGroups is! Map) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No groups found'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
      final groups = Map<String, dynamic>.from(rawGroups as Map);

      final regs = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .get();
      final registrations = regs.docs;

      bool changed = false;
      final groupNames = groups.keys.toList();
      for (final groupName in groupNames) {
        final groupValue = groups[groupName];
        List<String> teamKeys;
        if (groupValue is List) {
          teamKeys = groupValue.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        } else if (groupValue is Map && groupValue['teamKeys'] is List) {
          teamKeys = (groupValue['teamKeys'] as List).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        } else {
          continue;
        }

        final origLen = teamKeys.length;

        // 1) Remove exact duplicate teamKeys
        final seen = <String>{};
        teamKeys = teamKeys.where((k) => seen.add(k)).toList();

        // 2) Remove name-based duplicates (same pair, different keys e.g. A+B vs B+A with new partner)
        if (registrations.isNotEmpty) {
          final seenNameKeys = <String>{};
          teamKeys = teamKeys.where((k) {
            final nameKey = _getNameKeyForTeam(k, registrations);
            return seenNameKeys.add(nameKey);
          }).toList();
        }

        if (teamKeys.length != origLen) {
          changed = true;
          if (groupValue is Map) {
            groups[groupName] = Map<String, dynamic>.from(groupValue as Map)
              ..['teamKeys'] = teamKeys;
          } else {
            groups[groupName] = teamKeys;
          }
        }
      }

      if (changed) {
        await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .update({'groups': groups});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Duplicate teams removed'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No duplicate teams found'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cleaning duplicates: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addTeamToGroup(String groupName, String teamKey) async {
    try {
      await _addTeamsToGroup(groupName, {teamKey});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Team added to group'),
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
    }
  }

  Future<void> _removeTeamFromGroup(String groupName, String teamKey) async {
    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      final data = tournamentDoc.data() as Map<String, dynamic>?;
      final groups = Map<String, dynamic>.from(data?['groups'] as Map<String, dynamic>? ?? {});
      
      final groupData = groups[groupName];
      List<String> groupTeams;
      
      // Handle both old (list) and new (object) structures
      if (groupData is List) {
        groupTeams = List<String>.from(groupData);
      } else if (groupData is Map && groupData['teamKeys'] is List) {
        groupTeams = List<String>.from(groupData['teamKeys'] as List);
      } else {
        groupTeams = [];
      }
      
      groupTeams.removeWhere((k) => k == teamKey);
      
      // Keep new structure if it exists, otherwise use old structure
      if (groupData is Map) {
        groups[groupName] = {
          ...groupData,
          'teamKeys': groupTeams,
        };
      } else {
        groups[groupName] = groupTeams;
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'groups': groups});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Team removed from group'),
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
    }
  }

  // Auto-create groups based on player registration levels
  Future<void> _createGroupsByLevel() async {
    try {
      // Get all approved teams for this tournament only
      final registrations = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .get();

      if (registrations.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No approved teams to group'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Group teams by their registration level (each team goes only in its level)
      final Map<String, List<String>> levelGroups = {};
      
      for (var doc in registrations.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        if (data['userId'] == null) continue;

        final levelRaw = data['level'] as String? ?? 'Beginners';
        final level = levelRaw.trim().isEmpty ? 'Beginners' : levelRaw.trim();

        String teamKey;
        try {
          teamKey = _generateTeamKey(data);
        } catch (_) {
          continue;
        }
        
        levelGroups.putIfAbsent(level, () => []).add(teamKey);
      }

      // Deduplicate team keys per level (in case of duplicate registrations)
      for (final key in levelGroups.keys) {
        levelGroups[key] = levelGroups[key]!.toSet().toList();
      }

      // Sort levels in preferred order: C+, C-, D, Beginners, Seniors, Mix Doubles, Mix/Family Doubles, Women
      final levelOrder = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];
      final sortedLevels = levelGroups.keys.toList()
        ..sort((a, b) {
          final aIndex = levelOrder.indexOf(a);
          final bIndex = levelOrder.indexOf(b);
          if (aIndex == -1 && bIndex == -1) return a.compareTo(b);
          if (aIndex == -1) return 1;
          if (bIndex == -1) return -1;
          return aIndex.compareTo(bIndex);
        });

      // Create groups based on levels
      final Map<String, dynamic> groups = {};
      int totalTeams = 0;
      
      for (var level in sortedLevels) {
        final teams = List<String>.from(levelGroups[level]!);
        totalTeams += teams.length;
        
        // If a level has many teams, split into multiple groups
        // Standard: 3 teams per group
        const maxTeamsPerGroup = 3;
        final numGroups = (teams.length / maxTeamsPerGroup).ceil().clamp(1, 999);
        
        if (numGroups == 1) {
          groups['$level - Group 1'] = {
            'teamKeys': List<String>.from(teams),
            'schedule': {'court': '', 'startTime': ''},
            'level': level,
          };
        } else {
          for (int i = 0; i < numGroups; i++) {
            final startIndex = i * maxTeamsPerGroup;
            final endIndex = (startIndex + maxTeamsPerGroup > teams.length)
                ? teams.length
                : startIndex + maxTeamsPerGroup;
            final groupTeams = List<String>.from(teams.sublist(startIndex, endIndex));
            groups['$level - Group ${i + 1}'] = {
              'teamKeys': groupTeams,
              'schedule': {'court': '', 'startTime': ''},
              'level': level,
            };
          }
        }
      }

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'groups': groups});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Created ${groups.length} groups for $totalTeams teams by level'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating groups by level: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEditScheduleDialog(
    String groupName,
    Map<String, dynamic>? currentSchedule,
    List<String> teamKeys,
    List<QueryDocumentSnapshot> registrations,
  ) async {
    final courtController = TextEditingController(text: currentSchedule?['court'] as String? ?? '');
    final dateController = TextEditingController(text: currentSchedule?['date'] as String? ?? '');
    final startTimeController = TextEditingController(text: currentSchedule?['startTime'] as String? ?? '');
    final endTimeController = TextEditingController(text: currentSchedule?['endTime'] as String? ?? '');

    final teams = teamKeys.map((k) => {'key': k, 'name': _getTeamNameByKey(k, registrations)}).toList();
    final numMatches = teamKeys.length >= 2 ? (teamKeys.length * (teamKeys.length - 1) ~/ 2) : 0;
    final orderOfPlayRaw = currentSchedule?['orderOfPlay'] as List<dynamic>? ?? [];
    final orderOfPlay = List<Map<String, String>>.from(
      List.generate(numMatches, (i) {
        if (i < orderOfPlayRaw.length && orderOfPlayRaw[i] is Map) {
          final m = orderOfPlayRaw[i] as Map;
          return {'team1Key': m['team1Key']?.toString() ?? '', 'team2Key': m['team2Key']?.toString() ?? ''};
        }
        return {'team1Key': '', 'team2Key': ''};
      }),
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Schedule: $groupName'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: courtController,
                  decoration: const InputDecoration(
                    labelText: 'Court Number',
                    hintText: 'e.g., 1, 2, 3',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.sports_tennis),
                  ),
                  keyboardType: TextInputType.number,
                ),
              const SizedBox(height: 16),
              TextField(
                controller: dateController,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  hintText: 'e.g., Feb 15, 2026',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: startTimeController,
                decoration: const InputDecoration(
                  labelText: 'Start Time',
                  hintText: 'e.g., 7:45 PM or 19:45',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.access_time),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: endTimeController,
                decoration: const InputDecoration(
                  labelText: 'End Time (Optional)',
                  hintText: 'e.g., 9:00 PM or 21:00',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.access_time_filled),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Format: 7:45 PM or 19:45',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (numMatches > 0) ...[
                const SizedBox(height: 24),
                const Text('Order of Play', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Set which teams play in each match', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                const SizedBox(height: 12),
                ...List.generate(numMatches, (i) {
                  final team1Key = orderOfPlay[i]['team1Key'] ?? '';
                  final team2Key = orderOfPlay[i]['team2Key'] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Match ${i + 1}:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: team1Key.isEmpty ? null : team1Key,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Team 1', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), border: OutlineInputBorder()),
                          items: [const DropdownMenuItem(value: null, child: Text('Select...')), ...teams.map((t) => DropdownMenuItem(value: t['key'] as String, child: Text(t['name'] as String, overflow: TextOverflow.ellipsis)))],
                          onChanged: (v) {
                            setDialogState(() {
                              orderOfPlay[i]['team1Key'] = v ?? '';
                              if (orderOfPlay[i]['team2Key'] == v) orderOfPlay[i]['team2Key'] = '';
                            });
                          },
                        ),
                        const SizedBox(height: 6),
                        Center(child: Text('vs', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600]))),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          value: (team2Key.isEmpty || team2Key == team1Key) ? null : team2Key,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Team 2', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), border: OutlineInputBorder()),
                          items: [const DropdownMenuItem(value: null, child: Text('Select...')), ...teams.where((t) => t['key'] != team1Key).map((t) => DropdownMenuItem(value: t['key'] as String, child: Text(t['name'] as String, overflow: TextOverflow.ellipsis)))],
                          onChanged: (v) {
                            setDialogState(() {
                              orderOfPlay[i]['team2Key'] = v ?? '';
                            });
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final schedule = {
                'court': courtController.text.trim().isNotEmpty ? courtController.text.trim() : null,
                'date': dateController.text.trim().isNotEmpty ? dateController.text.trim() : null,
                'startTime': startTimeController.text.trim().isNotEmpty ? startTimeController.text.trim() : null,
                if (endTimeController.text.trim().isNotEmpty) 'endTime': endTimeController.text.trim(),
                'orderOfPlay': orderOfPlay.where((m) => (m['team1Key'] ?? '').isNotEmpty && (m['team2Key'] ?? '').isNotEmpty).map((m) => {'team1Key': m['team1Key'], 'team2Key': m['team2Key']}).toList(),
              };
              await _saveGroupSchedule(groupName, schedule, teamKeys);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
    );
  }

  Future<void> _saveGroupSchedule(String groupName, Map<String, dynamic> schedule, List<String> teamKeys) async {
    try {
      final tournamentDoc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      final data = tournamentDoc.data() as Map<String, dynamic>?;
      final groups = Map<String, dynamic>.from(data?['groups'] as Map<String, dynamic>? ?? {});
      final existing = groups[groupName] is Map ? groups[groupName] as Map<String, dynamic> : <String, dynamic>{};

      groups[groupName] = {
        ...existing,
        'teamKeys': teamKeys,
        'schedule': schedule,
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'groups': groups});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving schedule: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
