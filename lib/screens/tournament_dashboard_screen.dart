import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tournament_groups_screen.dart';
import 'tournament_join_screen.dart';
import 'admin_tournament_setup_screen.dart';
import '../utils/knockout_bracket_utils.dart';

/// Info for a knockout match that can have a result entered.
class _KnockoutMatchInfo {
  final String matchId;
  final String? team1Key;
  final String? team1Name;
  final String? team2Key;
  final String? team2Name;
  final String path;
  final String? level;
  final int roundIdx;
  final int matchIdx;
  final Map<String, dynamic> matchData;

  const _KnockoutMatchInfo({
    required this.matchId,
    this.team1Key,
    this.team1Name,
    this.team2Key,
    this.team2Name,
    required this.path,
    this.level,
    required this.roundIdx,
    required this.matchIdx,
    required this.matchData,
  });
}

class TournamentDashboardScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;

  const TournamentDashboardScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<TournamentDashboardScreen> createState() => _TournamentDashboardScreenState();
}

class _TournamentDashboardScreenState extends State<TournamentDashboardScreen> {
  bool _isAdmin = false;
  bool _checkingAdmin = true;
  bool _isParentTournament = false;
  bool _loadingTournamentType = true;
  String _tournamentType = 'simple';

  // Admin credentials
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com';

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    // Defer tournament type loading to after first frame to prevent mouse tracker conflicts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadTournamentType();
      }
    });
  }

  Future<void> _loadTournamentType() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _isParentTournament = data?['isParentTournament'] as bool? ?? false;
            _tournamentType = data?['type'] as String? ?? 'simple';
            _loadingTournamentType = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loadingTournamentType = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading tournament type: $e');
      if (mounted) {
        setState(() {
          _loadingTournamentType = false;
        });
      }
    }
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

  /// Sort group names ascending: Group 1, Group 2, Group 3, ... Group 10, or Group A, B, C
  List<String> _sortGroupNames(List<String> names) {
    final list = List<String>.from(names);
    list.sort((a, b) {
      final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (numA != numB) return numA.compareTo(numB);
      return a.compareTo(b);
    });
    return list;
  }

  /// Sort group names by level first, then by group number within level (e.g. D Group 1, D Group 2, Beginners Group 1, Beginners Group 2)
  List<String> _sortGroupNamesByLevel(List<String> names, Map<String, dynamic> groups) {
    final byLevel = _groupGroupsByLevel(groups);
    final sortedLevels = _sortedLevels(byLevel);
    final result = <String>[];
    for (final level in sortedLevels) {
      final levelGroups = byLevel[level] ?? [];
      for (final name in levelGroups) {
        if (names.contains(name)) result.add(name);
      }
    }
    return result;
  }

  static const List<String> _levelOrder = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];

  /// Group names by level. Returns map: levelLabel -> List<groupName>. Groups without level go under 'All levels'.
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

  /// Group registrations by level. Returns map: levelLabel -> List<doc>.
  Map<String, List<QueryDocumentSnapshot>> _groupRegistrationsByLevel(List<QueryDocumentSnapshot> docs) {
    final byLevel = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final level = data['level'] as String? ?? 'All levels';
      final label = level.isEmpty ? 'All levels' : level;
      byLevel.putIfAbsent(label, () => []).add(doc);
    }
    return byLevel;
  }

  List<String> _sortedPlayerLevels(Map<String, List<QueryDocumentSnapshot>> byLevel) {
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

  // Calculate points and score difference from matches
  Map<String, dynamic> _calculateStandings(List<QueryDocumentSnapshot> matches, List<QueryDocumentSnapshot> registrations) {
    Map<String, Map<String, dynamic>> teamStats = {};

    // Initialize all teams with 0 stats
    for (var reg in registrations) {
      final data = reg.data() as Map<String, dynamic>;
      final userId = data['userId'] as String;
      final firstName = data['firstName'] as String? ?? '';
      final lastName = data['lastName'] as String? ?? '';
      final partner = data['partner'] as Map<String, dynamic>?;
      
      String teamKey;
      String teamName;
      
      if (partner != null) {
        final partnerName = partner['partnerName'] as String? ?? 'Unknown';
        // Create consistent team key (sort user IDs to ensure same team has same key)
        final userIds = [userId, partner['partnerId'] as String? ?? ''];
        userIds.sort();
        teamKey = userIds.join('_');
        teamName = '$firstName $lastName & $partnerName';
      } else {
        teamKey = userId;
        teamName = '$firstName $lastName';
      }

      if (!teamStats.containsKey(teamKey)) {
        teamStats[teamKey] = {
          'teamKey': teamKey,
          'teamName': teamName,
          'points': 0,
          'scoreDifference': 0,
          'gamesPlayed': 0,
          'gamesWon': 0,
          'gamesLost': 0,
        };
      }
    }

    // Process matches
    for (var matchDoc in matches) {
      final matchData = matchDoc.data() as Map<String, dynamic>;
      final team1Key = matchData['team1Key'] as String?;
      final team2Key = matchData['team2Key'] as String?;
      final winner = matchData['winner'] as String?; // 'team1' or 'team2'
      final score = matchData['score'] as String? ?? '';
      final scoreDifference = matchData['scoreDifference'] as int? ?? 0;

      if (team1Key != null && team2Key != null) {
        // Update team1 stats
        if (teamStats.containsKey(team1Key)) {
          teamStats[team1Key]!['gamesPlayed']++;
          if (winner == 'team1') {
            teamStats[team1Key]!['points'] += 3;
            teamStats[team1Key]!['gamesWon']++;
            teamStats[team1Key]!['scoreDifference'] += scoreDifference;
          } else {
            teamStats[team1Key]!['gamesLost']++;
            teamStats[team1Key]!['scoreDifference'] -= scoreDifference;
          }
        }

        // Update team2 stats
        if (teamStats.containsKey(team2Key)) {
          teamStats[team2Key]!['gamesPlayed']++;
          if (winner == 'team2') {
            teamStats[team2Key]!['points'] += 3;
            teamStats[team2Key]!['gamesWon']++;
            teamStats[team2Key]!['scoreDifference'] += scoreDifference;
          } else {
            teamStats[team2Key]!['gamesLost']++;
            teamStats[team2Key]!['scoreDifference'] -= scoreDifference;
          }
        }
      }
    }

    // Convert to list and sort
    List<Map<String, dynamic>> standings = teamStats.values.toList();
    standings.sort((a, b) {
      // Sort by points (descending)
      if (a['points'] != b['points']) {
        return (b['points'] as int).compareTo(a['points'] as int);
      }
      // Then by score difference (descending)
      if (a['scoreDifference'] != b['scoreDifference']) {
        return (b['scoreDifference'] as int).compareTo(a['scoreDifference'] as int);
      }
      // Then by games won (descending)
      return (b['gamesWon'] as int).compareTo(a['gamesWon'] as int);
    });

    return {'standings': standings};
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAdmin || _loadingTournamentType) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Parent tournaments: Only Standings and Rules tabs (2 tabs)
    // Normal tournaments: All tabs (7 - Groups, Players, Standings, Playoffs, Knockout, Matches, Rules)
    final tabLength = _isParentTournament ? 2 : 7;

    return DefaultTabController(
      length: tabLength,
      child: Scaffold(
            appBar: AppBar(
              title: Text(widget.tournamentName),
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
              bottom: TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                isScrollable: true,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                tabs: _isParentTournament
                    ? const [
                        Tab(child: Text('Standings', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Rules', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                      ]
                    : const [
                        Tab(child: Text('Groups', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Players', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Standings', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Playoffs', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Knockout', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Matches', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Rules', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                      ],
              ),
          actions: _isAdmin
              ? [
                  if (!_isParentTournament)
                    IconButton(
                      icon: const Icon(Icons.settings),
                      tooltip: 'Tournament Setup',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminTournamentSetupScreen(
                              tournamentId: widget.tournamentId,
                              tournamentName: widget.tournamentName,
                            ),
                          ),
                        );
                      },
                    ),
                  if (!_isParentTournament)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add',
                      onSelected: (value) {
                        if (value == 'groups') {
                          if (_tournamentType == 'two-phase-knockout') {
                            _navigateToTournamentSetup();
                          } else {
                            _navigateToGroupsScreen();
                          }
                        } else if (value == 'match') {
                          _showAddMatchDialog();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'groups',
                          child: Row(
                            children: [
                              const Icon(Icons.group, color: Color(0xFF1E3A8A)),
                              const SizedBox(width: 8),
                              Text(_tournamentType == 'two-phase-knockout'
                                  ? 'Configure Groups (Phase 1)'
                                  : 'Add Groups'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'match',
                          child: Row(
                            children: [
                              Icon(Icons.sports_tennis, color: Color(0xFF1E3A8A)),
                              SizedBox(width: 8),
                              Text('Add Match Result'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ]
              : null,
        ),
            body: TabBarView(
              children: _isParentTournament
                  ? [
                      _buildStandingsTab(),
                      _buildRulesTab(),
                    ]
                  : [
                      _buildGroupsTab(),
                      _buildApprovedPlayersTab(),
                      _buildStandingsTab(),
                      _buildPlayoffsTab(),
                      _buildKnockoutTab(),
                      _buildMatchesTab(),
                      _buildRulesTab(),
                    ],
            ),
          ),
        );
  }

  Widget _buildGroupsTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .snapshots(),
      builder: (context, tournamentSnapshot) {
        if (!tournamentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tournamentData = tournamentSnapshot.data!.data() as Map<String, dynamic>?;
        final tournamentType = tournamentData?['type'] as String? ?? 'simple';
        
        // Check for two-phase tournament
        if (tournamentType == 'two-phase-knockout') {
          return _buildTwoPhaseGroupsTab(tournamentData);
        }
        
        // Legacy simple tournament format
        final groups = tournamentData?['groups'] as Map<String, dynamic>? ?? {};

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
                    'Tap ⚙️ to configure tournament',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ],
            ),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tournamentRegistrations')
              .where('tournamentId', isEqualTo: widget.tournamentId)
              .where('status', isEqualTo: 'approved')
              .snapshots(),
          builder: (context, registrationsSnapshot) {
            if (!registrationsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final registrations = registrationsSnapshot.data!.docs;
            final byLevel = _groupGroupsByLevel(groups);
            final sortedLevels = _sortedLevels(byLevel);

            return ListView(
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
                  for (final groupName in byLevel[levelLabel]!) ...[
                    _buildSimpleGroupCard(groupName, groups, registrations),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSimpleGroupCard(
    String groupName,
    Map<String, dynamic> groups,
    List<QueryDocumentSnapshot> registrations,
  ) {
    List<String> rawTeamKeys;
    Map<String, dynamic>? schedule;
    final groupValue = groups[groupName];
    if (groupValue is List) {
      rawTeamKeys = (groupValue as List<dynamic>).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      schedule = null;
    } else if (groupValue is Map) {
      final groupData = groupValue as Map<String, dynamic>;
      rawTeamKeys = (groupData['teamKeys'] as List<dynamic>? ?? []).map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      schedule = groupData['schedule'] as Map<String, dynamic>?;
    } else {
      rawTeamKeys = [];
      schedule = null;
    }

    // Deduplicate teamKeys (source of truth from groups - no duplicates in UI)
    final seen = <String>{};
    final teamKeys = rawTeamKeys.where((k) => seen.add(k)).toList();

    // One reg per teamKey (avoids duplicate rows when same team has multiple level registrations)
    final teamsInGroup = <QueryDocumentSnapshot>[];
    for (final k in teamKeys) {
      for (final reg in registrations) {
        if (_generateTeamKey(reg.data() as Map<String, dynamic>) == k) {
          teamsInGroup.add(reg);
          break;
        }
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF1E3A8A),
                      child: Text(
                        groupName.replaceAll('Group ', ''),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      groupName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    subtitle: Text('${teamsInGroup.length} teams'),
                    trailing: _isAdmin
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.schedule, color: Color(0xFF1E3A8A)),
                                onPressed: () => _showEditGroupScheduleDialog(groupName, schedule, teamsInGroup),
                                tooltip: 'Edit Schedule & Order of Play for ${groupName}',
                              ),
                              IconButton(
                                icon: const Icon(Icons.sports, color: Colors.green),
                                onPressed: () => _showAddGroupMatchDialog(groupName, teamsInGroup),
                                tooltip: 'Enter Results for ${groupName}',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteGroup(groupName),
                                tooltip: 'Delete ${groupName}',
                              ),
                            ],
                          )
                        : null,
                    children: [
                      // Order of Play (Schedule + Match sequence)
                      if (schedule != null && (schedule['court'] != null || schedule['startTime'] != null || (schedule['orderOfPlay'] as List?)?.isNotEmpty == true))
                        Builder(
                          builder: (context) {
                            final orderOfPlay = schedule!['orderOfPlay'] as List<dynamic>? ?? [];
                            final teamKeyToName = <String, String>{};
                            for (var reg in teamsInGroup) {
                              final data = reg.data() as Map<String, dynamic>;
                              final teamKey = _generateTeamKey(data);
                              final firstName = data['firstName'] as String? ?? '';
                              final lastName = data['lastName'] as String? ?? '';
                              final partner = data['partner'] as Map<String, dynamic>?;
                              final name = partner != null
                                  ? '$firstName $lastName & ${partner['partnerName'] as String? ?? 'Unknown'}'
                                  : '$firstName $lastName';
                              teamKeyToName[teamKey] = name;
                            }
                            String teamName(String key) => teamKeyToName[key] ?? 'Unknown';
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey[300]!),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.access_time, size: 20, color: Colors.blue[700]),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Order of Play',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.blue[900],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (schedule['court'] != null && schedule['court'].toString().isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(Icons.sports_tennis, size: 18, color: Colors.grey[700]),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Court ${schedule['court']}',
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ],
                                    ),
                                  if (schedule['date'] != null && schedule['date'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today, size: 18, color: Colors.grey[700]),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${schedule['date']}',
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (schedule['startTime'] != null && schedule['startTime'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.schedule, size: 18, color: Colors.grey[700]),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${schedule['startTime']}${schedule['endTime'] != null ? ' - ${schedule['endTime']}' : ''}',
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (orderOfPlay.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    const Text('Match sequence:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 6),
                                    ...orderOfPlay.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final m = entry.value as Map<dynamic, dynamic>?;
                                      final t1 = m?['team1Key']?.toString() ?? '';
                                      final t2 = m?['team2Key']?.toString() ?? '';
                                      if (t1.isEmpty || t2.isEmpty) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${i + 1}. ${teamName(t1)}',
                                              style: const TextStyle(fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text('vs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                                            const SizedBox(height: 2),
                                            Text(
                                              teamName(t2),
                                              style: const TextStyle(fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      if (teamsInGroup.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No teams assigned to this group'),
                        )
                      else
                        ...teamsInGroup.map((reg) {
                          final data = reg.data() as Map<String, dynamic>;
                          final firstName = data['firstName'] as String? ?? '';
                          final lastName = data['lastName'] as String? ?? '';
                          final partner = data['partner'] as Map<String, dynamic>?;
                          
                          String teamName;
                          if (partner != null) {
                            final partnerName = partner['partnerName'] as String? ?? 'Unknown';
                            teamName = '$firstName $lastName & $partnerName';
                          } else {
                            teamName = '$firstName $lastName';
                          }
                          
                          return ListTile(
                            leading: const Icon(Icons.people, color: Color(0xFF1E3A8A)),
                            title: Text(
                              teamName,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                    ],
                  ),
                );
  }

  // Calculate group-based standings (each group only uses matches for THAT group - same team in different levels has separate results)
  Map<String, dynamic> _calculateGroupStandings(
    List<QueryDocumentSnapshot> matches,
    List<QueryDocumentSnapshot> registrations,
    Map<String, dynamic> groups,
  ) {
    Map<String, List<Map<String, dynamic>>> groupStandings = {};

    // Helper: resolve match key to canonical teamKey
    String? _resolveTeamKey(String matchKey, Map<String, dynamic> teamStats) {
      if (teamStats.containsKey(matchKey)) return matchKey;
      final trimmed = matchKey.replaceAll(RegExp(r'_+$'), '').replaceAll(RegExp(r'^_+'), '');
      if (trimmed.isNotEmpty && teamStats.containsKey(trimmed)) return trimmed;
      final parts = matchKey.split('_').where((s) => s.isNotEmpty).toList()..sort();
      if (parts.length >= 2) {
        final reordered = parts.join('_');
        if (teamStats.containsKey(reordered)) return reordered;
      }
      return null;
    }

    for (var groupEntry in groups.entries) {
      final groupName = groupEntry.key;
      final groupValue = groupEntry.value;

      List<String> teamKeys;
      if (groupValue is List) {
        teamKeys = groupValue.map((e) => e.toString()).toList();
      } else if (groupValue is Map) {
        final groupData = groupValue as Map<String, dynamic>;
        teamKeys = (groupData['teamKeys'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        if (teamKeys.isEmpty) {
          final slots = groupData['teamSlots'] as List<dynamic>? ?? [];
          teamKeys = [
            for (final s in slots)
              if (s is Map) (s['teamKey']?.toString())
          ].whereType<String>().where((k) => k.isNotEmpty).toList();
        }
      } else {
        teamKeys = [];
      }

      // Only matches for THIS group (same team in D vs Beginners must have separate results)
      final groupMatches = matches.where((m) {
        final data = m.data() as Map<String, dynamic>;
        final mGroup = data['groupName'] as String?;
        return mGroup == groupName;
      }).toList();

      // Build team name lookup from registrations
      final teamKeyToName = <String, String>{};
      for (var reg in registrations) {
        final data = reg.data() as Map<String, dynamic>;
        final teamKey = _generateTeamKey(data);
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        final partner = data['partner'] as Map<String, dynamic>?;
        final teamName = partner != null
            ? '$firstName $lastName & ${partner['partnerName'] as String? ?? 'Unknown'}'
            : '$firstName $lastName';
        teamKeyToName[teamKey] = teamName;
      }

      // Stats only for teams in this group (dedupe teamKeys)
      final seen = <String>{};
      final uniqueTeamKeys = teamKeys.where((k) => seen.add(k)).toList();
      Map<String, Map<String, dynamic>> groupTeamStats = {};
      for (var teamKey in uniqueTeamKeys) {
        groupTeamStats[teamKey] = {
          'teamKey': teamKey,
          'teamName': teamKeyToName[teamKey] ?? 'Unknown',
          'points': 0,
          'scoreDifference': 0,
          'gamesPlayed': 0,
          'gamesWon': 0,
          'gamesLost': 0,
        };
      }

      // Process only this group's matches
      for (var matchDoc in groupMatches) {
        final matchData = matchDoc.data() as Map<String, dynamic>;
        final m1 = matchData['team1Key'] as String?;
        final m2 = matchData['team2Key'] as String?;
        final winner = matchData['winner'] as String?;
        final scoreDifference = matchData['scoreDifference'] as int? ?? 0;

        if (m1 == null || m2 == null) continue;
        final team1Key = _resolveTeamKey(m1, groupTeamStats);
        final team2Key = _resolveTeamKey(m2, groupTeamStats);
        if (team1Key == null || team2Key == null) continue;

        groupTeamStats[team1Key]!['gamesPlayed'] = (groupTeamStats[team1Key]!['gamesPlayed'] as int) + 1;
        if (winner == 'team1') {
          groupTeamStats[team1Key]!['points'] = (groupTeamStats[team1Key]!['points'] as int) + 3;
          groupTeamStats[team1Key]!['gamesWon'] = (groupTeamStats[team1Key]!['gamesWon'] as int) + 1;
          groupTeamStats[team1Key]!['scoreDifference'] = (groupTeamStats[team1Key]!['scoreDifference'] as int) + scoreDifference;
        } else {
          groupTeamStats[team1Key]!['gamesLost'] = (groupTeamStats[team1Key]!['gamesLost'] as int) + 1;
          groupTeamStats[team1Key]!['scoreDifference'] = (groupTeamStats[team1Key]!['scoreDifference'] as int) - scoreDifference;
        }

        groupTeamStats[team2Key]!['gamesPlayed'] = (groupTeamStats[team2Key]!['gamesPlayed'] as int) + 1;
        if (winner == 'team2') {
          groupTeamStats[team2Key]!['points'] = (groupTeamStats[team2Key]!['points'] as int) + 3;
          groupTeamStats[team2Key]!['gamesWon'] = (groupTeamStats[team2Key]!['gamesWon'] as int) + 1;
          groupTeamStats[team2Key]!['scoreDifference'] = (groupTeamStats[team2Key]!['scoreDifference'] as int) + scoreDifference;
        } else {
          groupTeamStats[team2Key]!['gamesLost'] = (groupTeamStats[team2Key]!['gamesLost'] as int) + 1;
          groupTeamStats[team2Key]!['scoreDifference'] = (groupTeamStats[team2Key]!['scoreDifference'] as int) - scoreDifference;
        }
      }

      final groupTeams = groupTeamStats.values.toList();
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

    return {'groupStandings': groupStandings};
  }

  // Get top 2 from each group (automatic advancement)
  List<Map<String, dynamic>> _getAdvancedTeams(Map<String, List<Map<String, dynamic>>> groupStandings) {
    List<Map<String, dynamic>> advanced = [];
    
    for (var groupEntry in groupStandings.entries) {
      final groupName = groupEntry.key;
      final teams = groupEntry.value;
      
      // Top 2 advance (even if group has 4 teams)
      for (int i = 0; i < teams.length && i < 2; i++) {
        advanced.add({
          ...teams[i],
          'groupName': groupName,
          'position': i + 1,
        });
      }
    }
    
    return advanced;
  }

  Widget _buildTwoPhaseGroupsTab(Map<String, dynamic>? tournamentData) {
    final phase1 = tournamentData?['phase1'] as Map<String, dynamic>?;
    final phase2 = tournamentData?['phase2'] as Map<String, dynamic>?;
    final status = tournamentData?['status'] as String? ?? 'upcoming';

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, registrationsSnapshot) {
        if (!registrationsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final registrations = registrationsSnapshot.data!.docs;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // PHASE 1: Initial Groups
            if (phase1 != null) ...[
              _buildPhaseHeader(
                '📍 PHASE 1 - Initial Groups',
                status == 'phase1' ? 'In Progress 🔄' : 
                status == 'phase2' || status == 'knockout' || status == 'completed' ? 'Completed ✓' : 'Not Started',
                const Color(0xFF1E3A8A),
              ),
              const SizedBox(height: 12),
              ..._buildPhase1GroupCards(phase1, registrations),
              const SizedBox(height: 24),
            ],

            // PHASE 2: Advanced Groups
            if (phase2 != null) ...[
              _buildPhaseHeader(
                '📍 PHASE 2 - Advanced Groups',
                status == 'phase2' ? 'In Progress 🔄' : 
                status == 'knockout' || status == 'completed' ? 'Completed ✓' : 'Waiting for Phase 1',
                Colors.green,
              ),
              const SizedBox(height: 12),
              ..._buildPhase2GroupCards(phase2, registrations),
            ],

            // No configuration message
            if (phase1 == null && phase2 == null) ...[
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.settings, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Tournament not configured yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    if (_isAdmin) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Tap ⚙️ to configure phases',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildPhaseHeader(String title, String statusText, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: $statusText',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPhase1GroupCards(Map<String, dynamic> phase1, List<QueryDocumentSnapshot> registrations) {
    final groups = phase1['groups'] as Map<String, dynamic>? ?? {};
    final byLevel = _groupGroupsByLevel(groups);
    final sortedLevels = _sortedLevels(byLevel);
    final result = <Widget>[];

    for (final levelLabel in sortedLevels) {
      result.add(
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
      );
      for (final groupName in byLevel[levelLabel]!) {
        final groupData = groups[groupName] as Map<String, dynamic>;
        final rawTeamKeys = (groupData['teamKeys'] as List<dynamic>?)?.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList() ?? [];
        final seen = <String>{};
        final teamKeys = rawTeamKeys.where((k) => seen.add(k)).toList();
        final schedule = groupData['schedule'] as Map<String, dynamic>?;
        final court = schedule?['court'] as String? ?? 'TBD';
        final startTime = schedule?['startTime'] as String? ?? 'TBD';
        final endTime = schedule?['endTime'] as String? ?? 'TBD';

        final teamsInGroup = <QueryDocumentSnapshot>[];
        for (final k in teamKeys) {
          for (final reg in registrations) {
            if (_generateTeamKey(reg.data() as Map<String, dynamic>) == k) {
              teamsInGroup.add(reg);
              break;
            }
          }
        }

        result.add(Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF1E3A8A),
            child: Text(
              groupName.replaceAll('Group ', ''),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            groupName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(court, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 12),
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$startTime - $endTime',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text('${teamsInGroup.length} teams', style: const TextStyle(fontSize: 12)),
            ],
          ),
          children: [
            if (teamsInGroup.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No teams assigned to this group'),
              )
            else
              ...teamsInGroup.map((reg) {
                final data = reg.data() as Map<String, dynamic>;
                final firstName = data['firstName'] as String? ?? '';
                final lastName = data['lastName'] as String? ?? '';
                final partner = data['partner'] as Map<String, dynamic>?;
                
                String teamName;
                if (partner != null) {
                  final partnerName = partner['partnerName'] as String? ?? 'Unknown';
                  teamName = '$firstName $lastName & $partnerName';
                } else {
                  teamName = '$firstName $lastName';
                }
                
                return ListTile(
                  leading: const Icon(Icons.people, color: Color(0xFF1E3A8A)),
                  title: Text(
                    teamName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
          ],
        ),
      ));
      }
    }
    return result;
  }

  List<Widget> _buildPhase2GroupCards(Map<String, dynamic> phase2, List<QueryDocumentSnapshot> registrations) {
    final groups = phase2['groups'] as Map<String, dynamic>? ?? {};
    final byLevel = _groupGroupsByLevel(groups);
    final sortedLevels = _sortedLevels(byLevel);
    final result = <Widget>[];

    for (final levelLabel in sortedLevels) {
      result.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Row(
            children: [
              Icon(Icons.stacked_bar_chart, size: 20, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                levelLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
            ],
          ),
        ),
      );
      for (final groupName in byLevel[levelLabel]!) {
        final groupData = groups[groupName] as Map<String, dynamic>;
        final teamSlots = groupData['teamSlots'] as List<dynamic>? ?? [];
        final schedule = groupData['schedule'] as Map<String, dynamic>?;
        final court = schedule?['court'] as String? ?? 'TBD';
        final startTime = schedule?['startTime'] as String? ?? 'TBD';
        final endTime = schedule?['endTime'] as String? ?? 'TBD';

        result.add(Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green,
            child: Text(
              groupName.replaceAll('Group ', ''),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(
            groupName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(court, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 12),
                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$startTime - $endTime',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text('${teamSlots.length} team slots', style: const TextStyle(fontSize: 12)),
            ],
          ),
          children: [
            ...teamSlots.asMap().entries.map((entry) {
              final index = entry.key;
              final slot = entry.value as Map<String, dynamic>;
              final type = slot['type'] as String;
              final from = slot['from'] as String?;
              final name = slot['name'] as String?;
              final teamKey = slot['teamKey'] as String?;

              String displayText;
              IconData icon;
              Color iconColor;

              if (type == 'seeded') {
                displayText = name ?? 'Seeded Team';
                icon = Icons.star;
                iconColor = Colors.purple;
              } else if (type == 'winner') {
                displayText = teamKey != null ? _getTeamNameByKey(teamKey, registrations) : 'Winner of $from';
                icon = Icons.emoji_events;
                iconColor = Colors.amber;
              } else {
                displayText = teamKey != null ? _getTeamNameByKey(teamKey, registrations) : 'Runner-up of $from';
                icon = Icons.military_tech;
                iconColor = Colors.green;
              }

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: iconColor.withOpacity(0.2),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                title: Text(displayText),
                subtitle: teamKey == null && type != 'seeded'
                    ? Text(
                        'Pending Phase 1 results',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      )
                    : null,
              );
            }),
          ],
        ),
      ));
      }
    }
    return result;
  }

  String _getTeamNameByKey(String teamKey, List<QueryDocumentSnapshot> registrations) {
    for (var reg in registrations) {
      final data = reg.data() as Map<String, dynamic>;
      final userId = data['userId'] as String;
      final partner = data['partner'] as Map<String, dynamic>?;
      
      String registrationTeamKey;
      if (partner != null) {
        final partnerId = partner['partnerId'] as String?;
        if (partnerId != null) {
          final userIds = [userId, partnerId];
          userIds.sort();
          registrationTeamKey = userIds.join('_');
        } else {
          registrationTeamKey = userId;
        }
      } else {
        registrationTeamKey = userId;
      }

      if (registrationTeamKey == teamKey) {
        final firstName = data['firstName'] as String? ?? '';
        final lastName = data['lastName'] as String? ?? '';
        if (partner != null) {
          final partnerName = partner['partnerName'] as String? ?? '';
          return '$firstName $lastName & $partnerName';
        }
        return '$firstName $lastName';
      }
    }
    return 'Unknown Team';
  }

  // Helper to generate team key
  String _generateTeamKey(Map<String, dynamic> registration) {
    final userId = registration['userId'] as String;
    final partner = registration['partner'] as Map<String, dynamic>?;
    
    if (partner != null) {
      final partnerId = partner['partnerId'] as String?;
      if (partnerId != null) {
        final userIds = [userId, partnerId];
        userIds.sort();
        return userIds.join('_');
      }
    }
    return userId;
  }

  Widget _buildApprovedPlayersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final registrations = snapshot.data!.docs;
        if (registrations.isEmpty) {
          return const Center(
            child: Text(
              'No approved players yet',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }
        final byLevel = _groupRegistrationsByLevel(registrations);
        final sortedLevels = _sortedPlayerLevels(byLevel);

        return ListView(
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
              for (final doc in byLevel[levelLabel]!) ...[
                _buildPlayerCard(doc as QueryDocumentSnapshot<Map<String, dynamic>>),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _buildPlayerCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final firstName = data['firstName'] as String? ?? '';
    final lastName = data['lastName'] as String? ?? '';
    final phone = data['phone'] as String? ?? '';
    final level = data['level'] as String? ?? '-';
    final partner = data['partner'] as Map<String, dynamic>?;
    final partnerName = partner?['partnerName'] as String? ?? '';
    var teamName = partnerName.isNotEmpty
        ? '${firstName} ${lastName}'.trim() + ' / $partnerName'
        : '${firstName} ${lastName}'.trim();
    teamName = teamName.replaceAll(RegExp(r'^\s*/\s*'), '').trim();
    final displayName = teamName.isEmpty ? 'Unknown' : teamName;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(
          displayName.isEmpty ? 'Unknown' : displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('Level: $level${phone.isNotEmpty ? ' • $phone' : ''}'),
        trailing: _isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Color(0xFF1E3A8A)),
                    tooltip: 'Edit name',
                    onPressed: () => _showEditApprovedPlayerDialog(doc),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_remove, color: Colors.red),
                    tooltip: 'Remove from tournament',
                    onPressed: () => _removeApprovedPlayer(doc),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _showEditApprovedPlayerDialog(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final firstNameController = TextEditingController(text: data['firstName'] as String? ?? '');
    final lastNameController = TextEditingController(text: data['lastName'] as String? ?? '');
    final partner = data['partner'] as Map<String, dynamic>?;
    final partnerNameController = TextEditingController(
      text: partner?['partnerName'] as String? ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Player Name'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: partnerNameController,
                decoration: const InputDecoration(
                  labelText: 'Partner Name',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final partnerData = data['partner'] as Map<String, dynamic>? ?? {};
      final updatedPartner = Map<String, dynamic>.from(partnerData);
      updatedPartner['partnerName'] = partnerNameController.text.trim();
      await doc.reference.update({
        'firstName': firstNameController.text.trim(),
        'lastName': lastNameController.text.trim(),
        'partner': updatedPartner,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Player name updated'),
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

  Future<void> _removeApprovedPlayer(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Player'),
        content: const Text(
          'Are you sure you want to remove this player from the tournament? '
          'They will no longer appear in groups or standings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await doc.reference.update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Player removed from tournament'),
            backgroundColor: Colors.orange,
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

  Widget _buildStandingsTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .snapshots(),
      builder: (context, tournamentSnapshot) {
        if (!tournamentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tournamentData = tournamentSnapshot.data!.data() as Map<String, dynamic>?;
        final isParentTournament = tournamentData?['isParentTournament'] as bool? ?? false;
        final tournamentType = tournamentData?['type'] as String? ?? 'simple';
        
        // If parent tournament, show overall year standings
        if (isParentTournament) {
          return _buildOverallYearStandings();
        }

        // For two-phase: use EXACT same source as Groups tab - phase1.groups
        Map<String, dynamic> groups = tournamentData?['groups'] as Map<String, dynamic>? ?? {};
        if (tournamentType == 'two-phase-knockout') {
          final phase1 = tournamentData?['phase1'] as Map<String, dynamic>?;
          if (phase1 != null) {
            groups = phase1['groups'] as Map<String, dynamic>? ?? {};
          }
        }

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
              return const Center(child: Text('No approved registrations'));
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tournamentMatches')
                  .where('tournamentId', isEqualTo: widget.tournamentId)
                  .snapshots(),
              builder: (context, matchesSnapshot) {
                if (matchesSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final registrations = registrationsSnapshot.data!.docs;
                final matchesList = matchesSnapshot.hasData ? matchesSnapshot.data!.docs : <QueryDocumentSnapshot>[];
                
                // Sort matches by timestamp (most recent first), handling null timestamps
                final matches = List<QueryDocumentSnapshot>.from(matchesList);
                matches.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTimestamp = aData['timestamp'] as Timestamp?;
                  final bTimestamp = bData['timestamp'] as Timestamp?;
                  
                  if (aTimestamp == null && bTimestamp == null) return 0;
                  if (aTimestamp == null) return 1;
                  if (bTimestamp == null) return -1;
                  
                  return bTimestamp.compareTo(aTimestamp); // Descending order
                });

                if (registrations.isEmpty) {
                  return const Center(
                    child: Text('No approved teams yet'),
                  );
                }

                if (groups.isEmpty) {
                  // Fallback to overall standings if no groups
                  final standingsData = _calculateStandings(matches, registrations);
                  final standings = standingsData['standings'] as List<Map<String, dynamic>>;

                  if (standings.isEmpty) {
                    return const Center(
                      child: Text('No matches played yet'),
                    );
                  }

                  return _buildOverallStandings(standings);
                }

                // Group-based standings - same structure as Groups tab, with results
                final groupStandingsData = _calculateGroupStandings(matches, registrations, groups);
                final groupStandings = groupStandingsData['groupStandings'] as Map<String, List<Map<String, dynamic>>>;

                if (groupStandings.isEmpty) {
                  return const Center(
                    child: Text('No group standings available'),
                  );
                }

                final sortedGroupNames = _sortGroupNamesByLevel(groupStandings.keys.toList(), groups);

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sortedGroupNames.length,
                  itemBuilder: (context, index) {
                    final groupName = sortedGroupNames[index];
                    final teams = groupStandings[groupName]!;
                    // Only show "advancing" styling when at least one match has been played in this group
                    final hasPlayedMatches = teams.any((t) => (t['gamesPlayed'] as int? ?? 0) > 0);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A8A),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.white,
                                  child: Text(
                                    groupName.replaceAll('Group ', ''),
                                    style: const TextStyle(
                                      color: Color(0xFF1E3A8A),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    groupName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                if (teams.length >= 2)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: hasPlayedMatches ? Colors.green : Colors.grey,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      hasPlayedMatches ? 'Top 2 Advance' : 'Top 2 will advance',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Group standings header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              border: Border(
                                bottom: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 2, child: Text('Team', style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(child: Text('Pts', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(child: Text('+/-', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(child: Text('W-L', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),
                          // Teams in group - show Pts/+/-/W-L even with 0s; only show ✓ when matches played
                          ...teams.asMap().entries.map((entry) {
                            final position = entry.key;
                            final team = entry.value;
                            final isTopTwo = position < 2;
                            final isFirst = position == 0;
                            // Only highlight top 2 and show checkmark after matches played
                            final showAdvancing = hasPlayedMatches && isTopTwo;

                            return Container(
                              decoration: BoxDecoration(
                                color: showAdvancing
                                    ? (isFirst ? Colors.amber[50] : Colors.green[50])
                                    : null,
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey[200]!),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: showAdvancing
                                        ? (isFirst ? Colors.amber : Colors.green)
                                        : Colors.grey[400],
                                    child: Text(
                                      '${position + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            team['teamName'] as String,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: showAdvancing ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        if (showAdvancing)
                                          Container(
                                            margin: const EdgeInsets.only(left: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              '✓',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E3A8A),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${team['points'] ?? 0}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${(team['scoreDifference'] as int? ?? 0) >= 0 ? '+' : ''}${team['scoreDifference'] ?? 0}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: (team['scoreDifference'] as int? ?? 0) >= 0
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${team['gamesWon'] ?? 0}-${team['gamesLost'] ?? 0}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildOverallStandings(List<Map<String, dynamic>> standings, {String? hint}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hint != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
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
                    hint,
                    style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                  ),
                ),
              ],
            ),
          ),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Expanded(flex: 2, child: Text('Team', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              Expanded(child: Text('Pts', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              Expanded(child: Text('+/-', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              Expanded(child: Text('W-L', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...standings.asMap().entries.map((entry) {
          final index = entry.key;
          final team = entry.value;
          final isTopThree = index < 3;

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: isTopThree ? 4 : 1,
            color: isTopThree
                ? (index == 0
                    ? Colors.amber[50]
                    : index == 1
                        ? Colors.grey[200]
                        : Colors.brown[50])
                : null,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isTopThree
                    ? (index == 0
                        ? Colors.amber
                        : index == 1
                            ? Colors.grey[400]
                            : Colors.brown[300])
                    : const Color(0xFF1E3A8A),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                team['teamName'] as String,
                style: TextStyle(
                  fontWeight: isTopThree ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${team['points']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${team['scoreDifference'] >= 0 ? '+' : ''}${team['scoreDifference']}',
                    style: TextStyle(
                      color: (team['scoreDifference'] as int) >= 0
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${team['gamesWon']}-${team['gamesLost']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPlayoffsTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .snapshots(),
      builder: (context, tournamentSnapshot) {
        if (!tournamentSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tournamentData = tournamentSnapshot.data!.data() as Map<String, dynamic>?;
        final tournamentType = tournamentData?['type'] as String? ?? 'simple';
        final status = tournamentData?['status'] as String? ?? 'upcoming';

        // Knockout bracket is shown in the separate Knockout tab; Playoffs tab shows teams advancing from groups
        
        // Use phase1.groups for two-phase, else root groups
        Map<String, dynamic> groups = tournamentData?['groups'] as Map<String, dynamic>? ?? {};
        if (tournamentType == 'two-phase-knockout') {
          final phase1 = tournamentData?['phase1'] as Map<String, dynamic>?;
          if (phase1 != null) {
            groups = phase1['groups'] as Map<String, dynamic>? ?? {};
          }
        }

        if (groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Tournament not configured yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Tap ⚙️ to configure knockout bracket',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ],
            ),
          );
        }

        final statusByLevelRaw = tournamentData?['statusByLevel'] as Map<String, dynamic>?;
        final statusByLevel = statusByLevelRaw != null
            ? statusByLevelRaw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
            : <String, String>{};
        final byLevel = _groupGroupsByLevel(groups);
        final groupToLevel = <String, String>{};
        for (final e in byLevel.entries) {
          for (final g in e.value) groupToLevel[g] = e.key;
        }
        final levelsInKnockout = statusByLevel.entries
            .where((e) => e.value == 'knockout' || e.value == 'completed')
            .map((e) => e.key)
            .toList();

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
              return const Center(child: Text('No approved registrations'));
            }

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tournamentMatches')
                  .where('tournamentId', isEqualTo: widget.tournamentId)
                  .snapshots(),
              builder: (context, matchesSnapshot) {
                if (matchesSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final registrations = registrationsSnapshot.data!.docs;
                final matchesList = matchesSnapshot.hasData ? matchesSnapshot.data!.docs : <QueryDocumentSnapshot>[];
                
                // Sort matches by timestamp (most recent first), handling null timestamps
                final matches = List<QueryDocumentSnapshot>.from(matchesList);
                matches.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aTimestamp = aData['timestamp'] as Timestamp?;
                  final bTimestamp = bData['timestamp'] as Timestamp?;
                  
                  if (aTimestamp == null && bTimestamp == null) return 0;
                  if (aTimestamp == null) return 1;
                  if (bTimestamp == null) return -1;
                  
                  return bTimestamp.compareTo(aTimestamp); // Descending order
                });

                // Calculate group standings
                final groupStandingsData = _calculateGroupStandings(matches, registrations, groups);
                final groupStandings = groupStandingsData['groupStandings'] as Map<String, List<Map<String, dynamic>>>;

                // Exclude groups whose level has moved to knockout (per-level progression)
                final groupStandingsInGroups = Map<String, List<Map<String, dynamic>>>.fromEntries(
                  groupStandings.entries.where((e) => !levelsInKnockout.contains(groupToLevel[e.key])),
                );

                // Get advanced teams (top 2 from each group) for levels still in groups
                final advancedTeams = _getAdvancedTeams(groupStandingsInGroups);
                final anyGroupHasPlayed = groupStandingsInGroups.values.any(
                  (teams) => teams.any((t) => (t['gamesPlayed'] as int? ?? 0) > 0),
                );

                if (advancedTeams.isEmpty && levelsInKnockout.isEmpty) {
                  return const Center(
                    child: Text('No teams have advanced yet. Play group matches first.'),
                  );
                }

                // When no matches played, don't show any team names – just a prompt (and any levels already in knockout)
                if (!anyGroupHasPlayed && advancedTeams.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (levelsInKnockout.isNotEmpty) ...[
                        ...KnockoutBracketUtils.sortLevels(List.from(levelsInKnockout)).map((level) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.amber[700],
                              child: const Icon(Icons.emoji_events, color: Colors.white),
                            ),
                            title: Text('$level — In knockout', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: const Text('See Knockout tab'),
                          ),
                        )),
                        const SizedBox(height: 16),
                      ],
                      const Icon(Icons.sports_score, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Playoff Round',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        levelsInKnockout.isEmpty
                            ? 'Play group matches first. Teams advancing to playoffs will appear here once results are entered.'
                            : 'Play group matches for remaining levels. Teams advancing will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      ),
                    ],
                  );
                }

                // Organize advanced teams for bracket display (only when matches have been played)
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Levels already in knockout (per-level progression)
                    if (levelsInKnockout.isNotEmpty) ...[
                      ...KnockoutBracketUtils.sortLevels(List.from(levelsInKnockout)).map((level) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.amber[700],
                            child: const Icon(Icons.emoji_events, color: Colors.white),
                          ),
                          title: Text('$level — In knockout', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: const Text('See Knockout tab'),
                        ),
                      )),
                      const SizedBox(height: 16),
                    ],
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A8A),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Playoff Round',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            advancedTeams.isEmpty
                                ? 'Teams advancing from groups (play matches for remaining levels)'
                                : '${advancedTeams.length} teams advanced (Top 2 from each group)',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Advanced teams by group (level first, then group number) — only levels still in groups
                    ..._sortGroupNamesByLevel(groupStandingsInGroups.keys.toList(), groups).map((groupName) {
                      final teams = groupStandingsInGroups[groupName]!;
                      final topTwo = teams.take(2).toList();
                      final hasPlayedMatches = teams.any((t) => (t['gamesPlayed'] as int? ?? 0) > 0);

                      if (topTwo.isEmpty || !hasPlayedMatches) return const SizedBox.shrink();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ExpansionTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Icon(Icons.check, color: Colors.white),
                          ),
                          title: Text(
                            groupName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text('${topTwo.length} team(s) advanced'),
                          children: [
                            ...topTwo.asMap().entries.map((entry) {
                              final position = entry.key;
                              final team = entry.value;

                              return Container(
                                decoration: BoxDecoration(
                                  color: position == 0 ? Colors.amber[50] : Colors.green[50],
                                  border: Border(
                                    bottom: BorderSide(color: Colors.grey[200]!),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: position == 0 ? Colors.amber : Colors.green,
                                    child: Text(
                                      '${position + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          team['teamName'] as String,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          position == 0 ? '1st Place' : '2nd Place',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${team['points'] ?? 0} pts | ${(team['scoreDifference'] as int? ?? 0) >= 0 ? '+' : ''}${team['scoreDifference'] ?? 0} diff | ${team['gamesWon'] ?? 0}-${team['gamesLost'] ?? 0} W-L',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    // Bracket visualization
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Playoff Bracket',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Total Advanced Teams: ${advancedTeams.length}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'These teams will compete in the playoff round. Add playoff matches using the Matches tab.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (_isAdmin) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _showAddMatchDialog(),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Playoff Match'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
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
        );
      },
    );
  }

  Widget _buildKnockoutTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final tournamentData = snapshot.data!.data() as Map<String, dynamic>?;
        final tournamentType = tournamentData?['type'] as String? ?? 'simple';
        final status = tournamentData?['status'] as String? ?? 'upcoming';
        final knockout = tournamentData?['knockout'] as Map<String, dynamic>?;
        final statusByLevelRaw = tournamentData?['statusByLevel'] as Map<String, dynamic>?;
        final statusByLevel = statusByLevelRaw != null
            ? statusByLevelRaw.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
            : <String, String>{};
        final levelBrackets = knockout?['levelBrackets'] as Map<String, dynamic>?;
        final anyLevelInKnockout = levelBrackets != null &&
            levelBrackets.isNotEmpty &&
            statusByLevel.values.any((s) => s == 'knockout' || s == 'completed');
        final showBracket = knockout != null &&
            (tournamentType == 'two-phase-knockout' ||
                (tournamentType == 'simple' &&
                    (status == 'knockout' ||
                        status == 'completed' ||
                        anyLevelInKnockout)));

        if (showBracket) {
          return _buildKnockoutBracketDisplay(knockout!, status: status, statusByLevel: statusByLevel);
        }

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events, size: 64, color: Colors.amber[700]),
                const SizedBox(height: 16),
                const Text(
                  'Knockout bracket',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  knockout == null
                      ? 'Not configured yet. Use tournament setup to create the knockout bracket.'
                      : 'Knockout will appear here once the bracket is active.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Tap ⚙️ to configure tournament and knockout',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKnockoutBracketDisplay(
    Map<String, dynamic> knockout, {
    String? status,
    Map<String, String> statusByLevel = const {},
  }) {
    final levelBrackets = knockout['levelBrackets'] as Map<String, dynamic>?;
    final roundsData = knockout['rounds'] as List<dynamic>?;
    final quarterFinals = knockout['quarterFinals'] as List<dynamic>? ?? [];
    final semiFinals = knockout['semiFinals'] as List<dynamic>? ?? [];
    final finalMatch = knockout['final'] as Map<String, dynamic>?;

    final hasLevelBrackets = levelBrackets != null && levelBrackets.isNotEmpty;
    final hasRounds = roundsData != null && roundsData.isNotEmpty;
    final hasLegacy = quarterFinals.isNotEmpty || semiFinals.isNotEmpty || (finalMatch != null && finalMatch.isNotEmpty);

    if (!hasLevelBrackets && !hasRounds && !hasLegacy) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.settings, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Knockout bracket not configured yet',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              if (_isAdmin) ...[
                const SizedBox(height: 8),
                const Text(
                  'Tap ⚙️ to configure knockout bracket',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (hasLevelBrackets) {
      final globalKnockout = status == 'knockout' || status == 'completed';
      final entriesToShow = levelBrackets!.entries.where((entry) {
        if (globalKnockout) return true;
        if (statusByLevel.isEmpty) return true;
        final levelStatus = statusByLevel[entry.key] ?? '';
        return levelStatus == 'knockout' || levelStatus == 'completed';
      }).toList();
      if (entriesToShow.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No level in knockout yet. Use tournament setup to move a level to knockout.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in entriesToShow) ...[
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 12),
              child: Text(
                entry.key,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ),
            _buildHorizontalBracket(
              (entry.value as List<dynamic>)
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],
        ],
      );
    }

    List<Map<String, dynamic>> roundsForDisplay = [];
    if (hasRounds) {
      roundsForDisplay = roundsData!
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } else {
      if (quarterFinals.isNotEmpty) {
        roundsForDisplay.add({
          'name': quarterFinals.length >= 4 ? 'First Round' : 'Semi-finals',
          'matches': quarterFinals,
        });
      }
      if (semiFinals.isNotEmpty) {
        roundsForDisplay.add({'name': 'Semi-finals', 'matches': semiFinals});
      }
      if (finalMatch != null && finalMatch.isNotEmpty) {
        roundsForDisplay.add({'name': 'Final', 'matches': [finalMatch]});
      }
    }

    return _buildHorizontalBracket(roundsForDisplay);
  }

  // ─── Bracket constants ───────────────────────────────────────────────────
  static const double _bBoxW  = 190.0;
  static const double _bBoxH  = 74.0;
  static const double _bGapX  = 36.0;
  static const double _bHdrH  = 28.0;
  static const Color  _lineClr = Color(0xFF9E9E9E);

  /// Renders a full bracket for one level's rounds.
  /// Uses only Positioned widgets in a Stack — no CustomPaint — to avoid
  /// pushClipRect crashes when placed inside a ListView.
  Widget _buildHorizontalBracket(List<Map<String, dynamic>> rounds) {
    if (rounds.isEmpty) return const SizedBox.shrink();

    final List<List<Map<String, dynamic>>> allMatches = rounds
        .map((r) => (r['matches'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList())
        .where((l) => l.isNotEmpty)
        .toList();
    if (allMatches.isEmpty) return const SizedBox.shrink();

    final int numRounds = allMatches.length;
    const double slotH = _bBoxH + 12.0;

    final double totalH = _bHdrH + slotH * allMatches[0].length + 8;
    final double totalW = numRounds * (_bBoxW + _bGapX) + 160;

    // centre-Y for every match
    final List<List<double>> cy = List.generate(numRounds, (_) => []);
    for (int mi = 0; mi < allMatches[0].length; mi++) {
      cy[0].add(_bHdrH + slotH * mi + _bBoxH / 2);
    }
    for (int ri = 1; ri < numRounds; ri++) {
      for (int mi = 0; mi < allMatches[ri].length; mi++) {
        final a = cy[ri - 1].length > mi * 2     ? cy[ri - 1][mi * 2]     : 0.0;
        final b = cy[ri - 1].length > mi * 2 + 1 ? cy[ri - 1][mi * 2 + 1] : a;
        cy[ri].add((a + b) / 2);
      }
    }

    final widgets = <Widget>[];

    // ── round headers ───────────────────────────────────────────────────
    for (int ri = 0; ri < numRounds; ri++) {
      widgets.add(Positioned(
        left: ri * (_bBoxW + _bGapX),
        top: 0,
        width: _bBoxW,
        height: _bHdrH,
        child: Center(
          child: Text(
            _knockoutRoundDisplayName(
              rounds[ri]['name']?.toString() ?? '',
              allMatches[ri].length,
            ),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
          ),
        ),
      ));
    }

    // ── match boxes ─────────────────────────────────────────────────────
    for (int ri = 0; ri < numRounds; ri++) {
      for (int mi = 0; mi < allMatches[ri].length; mi++) {
        widgets.add(Positioned(
          left: ri * (_bBoxW + _bGapX),
          top: cy[ri][mi] - _bBoxH / 2,
          width: _bBoxW,
          height: _bBoxH,
          child: _buildBracketMatchBox(allMatches[ri][mi]),
        ));
      }
    }

    // ── connector lines (thin Containers — zero CustomPaint) ────────────
    const double lw = 1.5;
    for (int ri = 0; ri < numRounds - 1; ri++) {
      final double colRight = ri * (_bBoxW + _bGapX) + _bBoxW;
      final double nextCol  = (ri + 1) * (_bBoxW + _bGapX);
      final double midX     = (colRight + nextCol) / 2;

      for (int mi = 0; mi < allMatches[ri].length; mi += 2) {
        final double topCY = cy[ri][mi];
        final double botCY = mi + 1 < cy[ri].length ? cy[ri][mi + 1] : topCY;
        final int pIdx = mi ~/ 2;
        if (pIdx >= cy[ri + 1].length) continue;
        final double parentCY = cy[ri + 1][pIdx];

        // horizontal stub: top match → mid
        widgets.add(Positioned(
          left: colRight, top: topCY - lw / 2, width: midX - colRight, height: lw,
          child: const ColoredBox(color: _lineClr),
        ));
        // horizontal stub: bottom match → mid
        if (mi + 1 < allMatches[ri].length) {
          widgets.add(Positioned(
            left: colRight, top: botCY - lw / 2, width: midX - colRight, height: lw,
            child: const ColoredBox(color: _lineClr),
          ));
        }
        // vertical bracket connecting the pair
        if ((botCY - topCY).abs() > 1) {
          widgets.add(Positioned(
            left: midX - lw / 2, top: topCY, width: lw, height: botCY - topCY,
            child: const ColoredBox(color: _lineClr),
          ));
        }
        // horizontal stub: mid → next-round match
        widgets.add(Positioned(
          left: midX, top: parentCY - lw / 2, width: nextCol - midX, height: lw,
          child: const ColoredBox(color: _lineClr),
        ));
      }
    }

    // ── winner badge ────────────────────────────────────────────────────
    String? winnerName;
    if (allMatches.last.length == 1) {
      final f = allMatches.last[0];
      final w = f['winner']?.toString();
      if (w != null) {
        final slot = (w == 'team1' ? f['team1'] : f['team2']);
        if (slot is Map) winnerName = slot['teamName']?.toString();
      }
    }
    if (winnerName != null && winnerName.isNotEmpty && cy.last.isNotEmpty) {
      final wLeft = numRounds * (_bBoxW + _bGapX) + 4;
      final wCY = cy.last[0];
      widgets.add(Positioned(
        left: wLeft,
        top: wCY - 22,
        width: 160,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)]),
            border: Border.all(color: Colors.amber, width: 2),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text('🥇', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 6),
                  Text('Champion', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                ],
              ),
              const SizedBox(height: 4),
              Text(winnerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ));
    }

    // Outer SizedBox supplies a finite height (ListView gives unbounded).
    // Inner SizedBox gives the Stack an explicit extent so every Positioned
    // child has valid coordinates.
    return SizedBox(
      height: totalH,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        child: SizedBox(
          width: totalW,
          height: totalH,
          child: Stack(clipBehavior: Clip.none, children: widgets),
        ),
      ),
    );
  }

  Widget _buildBracketMatchBox(Map<String, dynamic> matchData) {
    final team1 = matchData['team1'] as Map<String, dynamic>?;
    final team2 = matchData['team2'] as Map<String, dynamic>?;
    final winner = matchData['winner'] as String?;

    String _label(Map<String, dynamic>? slot) {
      if (slot == null) return 'TBD';
      final isBye = slot['isBye'] == true ||
          (slot['teamName']?.toString().trim().toUpperCase() == 'BYE') ||
          (slot['from']?.toString().trim().toUpperCase() == 'BYE');
      if (isBye) return 'BYE';
      final name = slot['teamName']?.toString() ?? '';
      if (name.trim().isNotEmpty) return name;
      final from = slot['from']?.toString() ?? '';
      final type = slot['type']?.toString() ?? '';
      if (type == 'winner' && from.isNotEmpty) return 'W: $from';
      if (from.startsWith('seed')) return 'Seed ${from.replaceFirst('seed', '')}';
      return from.isNotEmpty ? from : 'TBD';
    }

    final t1 = _label(team1);
    final t2 = _label(team2);
    final t1Won = winner == 'team1';
    final t2Won = winner == 'team2';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: t1Won ? const Color(0xFFDCFCE7) : Colors.white,
                border: Border.all(color: const Color(0xFFBBBBBB)),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  if (t1Won) const Text('✓ ', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      t1,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.1,
                        fontWeight: t1Won ? FontWeight.bold : FontWeight.normal,
                        color: t1Won ? const Color(0xFF166534) : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: t2Won ? const Color(0xFFDCFCE7) : const Color(0xFFF9F9F9),
                border: Border.all(color: const Color(0xFFBBBBBB)),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  if (t2Won) const Text('✓ ', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      t2,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.1,
                        fontWeight: t2Won ? FontWeight.bold : FontWeight.normal,
                        color: t2Won ? const Color(0xFF166534) : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Map stored round names to display names (First Round, Semi-finals, Final).
  String _knockoutRoundDisplayName(String rawName, int matchCount) {
    return KnockoutBracketUtils.standardizedRoundNameFromMatchCount(
      matchCount,
      fallbackRawName: rawName,
    );
  }

  Widget _buildKnockoutStageHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildKnockoutMatchCard(Map<String, dynamic> matchData, Color color) {
    final matchId = matchData['id'] as String;
    final team1 = matchData['team1'] as Map<String, dynamic>?;
    final team2 = matchData['team2'] as Map<String, dynamic>?;
    final schedule = matchData['schedule'] as Map<String, dynamic>?;
    final winner = matchData['winner'] as String?;

    final team1Name = team1?['teamName'] as String?;
    final team2Name = team2?['teamName'] as String?;
    final team1Text = team1 != null
        ? ((team1Name != null && team1Name.trim().isNotEmpty)
            ? team1Name
            : '${team1['type'] == 'winner' ? 'Winner' : 'Runner-up'} of ${team1['from']}')
        : 'TBD';
    final team2Text = team2 != null
        ? ((team2Name != null && team2Name.trim().isNotEmpty)
            ? team2Name
            : '${team2['type'] == 'winner' ? 'Winner' : 'Runner-up'} of ${team2['from']}')
        : 'TBD';

    final court = schedule?['court'] as String? ?? 'TBD';
    final date = schedule?['date'] as String? ?? '';
    final startTime = schedule?['startTime'] as String? ?? 'TBD';
    final endTime = schedule?['endTime'] as String? ?? 'TBD';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Match ID
            Text(
              matchId.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 12),
            
            // Teams
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: winner == 'team1' ? Colors.green[50] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: winner == 'team1' ? Colors.green : Colors.grey[300]!,
                        width: winner == 'team1' ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      team1Text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: winner == 'team1' ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'VS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: winner == 'team2' ? Colors.green[50] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: winner == 'team2' ? Colors.green : Colors.grey[300]!,
                        width: winner == 'team2' ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      team2Text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: winner == 'team2' ? FontWeight.bold : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            
            // Schedule Info
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      court,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                if (date.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        date,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      '$startTime - $endTime',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, regSnapshot) {
        if (!regSnapshot.hasData) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tournamentMatches')
                .where('tournamentId', isEqualTo: widget.tournamentId)
                .snapshots(),
            builder: (context, matchSnapshot) {
              if (matchSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return _buildMatchesList(
                matchSnapshot.hasData ? matchSnapshot.data!.docs : [],
                [],
              );
            },
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tournamentMatches')
              .where('tournamentId', isEqualTo: widget.tournamentId)
              .snapshots(),
          builder: (context, matchSnapshot) {
            if (matchSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildMatchesList(
              matchSnapshot.hasData ? matchSnapshot.data!.docs : [],
              regSnapshot.data!.docs,
            );
          },
        );
      },
    );
  }

  Widget _buildMatchesList(List<QueryDocumentSnapshot> matches, List<QueryDocumentSnapshot> registrations) {
    if (matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_tennis, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No matches recorded yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            if (_isAdmin) ...[
              const SizedBox(height: 8),
              const Text(
                'Tap + to add a match result',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ],
        ),
      );
    }

    // Build teamKey -> level from registrations
    final teamKeyToLevel = <String, String>{};
    for (var reg in registrations) {
      final data = reg.data() as Map<String, dynamic>;
      final teamKey = _generateTeamKey(data);
      final level = data['level'] as String? ?? 'All levels';
      teamKeyToLevel[teamKey] = level.isEmpty ? 'All levels' : level;
    }

    String matchLevel(QueryDocumentSnapshot matchDoc) {
      final d = matchDoc.data() as Map<String, dynamic>;
      final t1 = d['team1Key']?.toString() ?? '';
      final t2 = d['team2Key']?.toString() ?? '';
      return teamKeyToLevel[t1] ?? teamKeyToLevel[t2] ?? 'All levels';
    }

    final byLevel = <String, List<QueryDocumentSnapshot>>{};
    for (var m in matches) {
      final level = matchLevel(m);
      byLevel.putIfAbsent(level, () => []).add(m);
    }
    for (var list in byLevel.values) {
      list.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aTs = aData['timestamp'] as Timestamp?;
        final bTs = bData['timestamp'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });
    }
    final sortedLevels = byLevel.keys.toList()
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

    return ListView(
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
          for (final matchDoc in byLevel[levelLabel]!)
            _buildMatchCard(matchDoc),
        ],
      ],
    );
  }

  Widget _buildMatchCard(QueryDocumentSnapshot matchDoc) {
    final matchData = matchDoc.data() as Map<String, dynamic>;
    final team1Name = matchData['team1Name'] as String? ?? 'Team 1';
    final team2Name = matchData['team2Name'] as String? ?? 'Team 2';
    final score = matchData['score'] as String? ?? 'N/A';
    final winner = matchData['winner'] as String?;
    final timestamp = matchData['timestamp'] as Timestamp?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.sports_tennis, color: Color(0xFF1E3A8A)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    team1Name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: winner == 'team1' ? FontWeight.bold : FontWeight.normal,
                      color: winner == 'team1' ? Colors.green[700] : null,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: Text(
                    team2Name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight: winner == 'team2' ? FontWeight.bold : FontWeight.normal,
                      color: winner == 'team2' ? Colors.green[700] : null,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Score: $score',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ],
        ),
        subtitle: timestamp != null
            ? Text(
                _formatTimestamp(timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              )
            : null,
        trailing: _isAdmin
            ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteMatch(matchDoc.id),
              )
            : null,
      ),
    );
  }

  Future<void> _showAddMatchDialog() async {
    // Load tournament and groups (same source as Groups tab)
    final tournamentDoc = await FirebaseFirestore.instance
        .collection('tournaments')
        .doc(widget.tournamentId)
        .get();

    final registrationsSnapshot = await FirebaseFirestore.instance
        .collection('tournamentRegistrations')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .where('status', isEqualTo: 'approved')
        .get();

    if (!tournamentDoc.exists || registrationsSnapshot.docs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No approved teams yet. Approve teams first.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final tournamentData = tournamentDoc.data() as Map<String, dynamic>?;
    final tournamentType = tournamentData?['type'] as String? ?? 'simple';
    Map<String, dynamic> groups = tournamentData?['groups'] as Map<String, dynamic>? ?? {};
    if (tournamentType == 'two-phase-knockout') {
      final status = tournamentData?['status'] as String? ?? 'upcoming';
      final phase1 = tournamentData?['phase1'] as Map<String, dynamic>?;
      final phase2 = tournamentData?['phase2'] as Map<String, dynamic>?;
      if ((status == 'phase2' || status == 'knockout' || status == 'completed') && phase2 != null) {
        groups = phase2['groups'] as Map<String, dynamic>? ?? {};
      } else if (phase1 != null) {
        groups = phase1['groups'] as Map<String, dynamic>? ?? {};
      }
    }

    final knockout = tournamentData?['knockout'] as Map<String, dynamic>?;
    final status = tournamentData?['status'] as String? ?? 'upcoming';
    final knockoutActive = (status == 'knockout' || status == 'completed') && knockout != null;
    final knockoutMatches = knockoutActive ? _collectPlayableKnockoutMatches(knockout) : <_KnockoutMatchInfo>[];

    if (groups.isEmpty && knockoutMatches.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No groups or knockout matches to add results for.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final sortedNames = groups.isEmpty ? <String>[] : _sortGroupNamesByLevel(groups.keys.toList(), groups);
    final registrations = registrationsSnapshot.docs;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Match Result'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sortedNames.isNotEmpty) ...[
                  const Text('Group stage:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...sortedNames.map((groupName) {
                final groupData = groups[groupName];
                List<String> rawTeamKeys = [];
                if (groupData is Map) {
                  final fromKeys = groupData['teamKeys'] as List<dynamic>?;
                  if (fromKeys != null && fromKeys.isNotEmpty) {
                    rawTeamKeys = fromKeys.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
                  } else {
                    final slots = groupData['teamSlots'] as List<dynamic>? ?? [];
                    rawTeamKeys = [
                      for (final s in slots)
                        if (s is Map) (s['teamKey']?.toString())
                    ].whereType<String>().where((k) => k.isNotEmpty).toList();
                  }
                } else if (groupData is List) {
                  rawTeamKeys = groupData.map((e) => e.toString()).toList();
                }
                final seen = <String>{};
                final teamKeys = rawTeamKeys.where((k) => seen.add(k)).toList();
                final teamsInGroup = <QueryDocumentSnapshot>[];
                for (final k in teamKeys) {
                  for (final reg in registrations) {
                    if (_generateTeamKey(reg.data() as Map<String, dynamic>) == k) {
                      teamsInGroup.add(reg);
                      break;
                    }
                  }
                }
                return ListTile(
                  leading: const Icon(Icons.group, color: Color(0xFF1E3A8A)),
                  title: Text(groupName),
                  subtitle: Text('${teamsInGroup.length} teams'),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddGroupMatchDialog(groupName, teamsInGroup);
                  },
                );
              }),
                  const SizedBox(height: 16),
                ],
                if (knockoutMatches.isNotEmpty) ...[
                  const Text('Knockout / Playoffs:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...knockoutMatches.map((info) {
                    return ListTile(
                      leading: const Icon(Icons.emoji_events, color: Colors.amber),
                      title: Text(info.matchId),
                      subtitle: Text('${info.team1Name ?? "TBD"} vs ${info.team2Name ?? "TBD"}'),
                      onTap: () {
                        Navigator.pop(context);
                        _showAddKnockoutMatchResultDialog(info);
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
  }

  /// Info for a knockout match that can have a result entered.

  List<_KnockoutMatchInfo> _collectPlayableKnockoutMatches(Map<String, dynamic> knockout) {
    final out = <_KnockoutMatchInfo>[];
    final levelBrackets = knockout['levelBrackets'] as Map<String, dynamic>?;
    final roundsData = knockout['rounds'] as List<dynamic>?;
    final qf = knockout['quarterFinals'] as List<dynamic>? ?? [];
    final sf = knockout['semiFinals'] as List<dynamic>? ?? [];
    final finalMatch = knockout['final'] as Map<String, dynamic>?;

    void addFromMatch(Map<String, dynamic> m, String path, String? level, int roundIdx, int matchIdx) {
      final t1 = m['team1'] as Map<String, dynamic>?;
      final t2 = m['team2'] as Map<String, dynamic>?;
      final n1 = t1?['teamName']?.toString();
      final n2 = t2?['teamName']?.toString();
      if (n1 == null || n2 == null || n1.isEmpty || n2.isEmpty) return;
      if (m['winner'] != null) return;
      out.add(_KnockoutMatchInfo(
        matchId: (m['id'] ?? 'match').toString(),
        team1Key: t1?['teamKey']?.toString(),
        team1Name: n1,
        team2Key: t2?['teamKey']?.toString(),
        team2Name: n2,
        path: path,
        level: level,
        roundIdx: roundIdx,
        matchIdx: matchIdx,
        matchData: m,
      ));
    }

    if (levelBrackets != null && levelBrackets.isNotEmpty) {
      for (final entry in levelBrackets.entries) {
        final level = entry.key as String;
        final rounds = (entry.value as List<dynamic>? ?? []);
        for (var ri = 0; ri < rounds.length; ri++) {
          final r = rounds[ri] as Map<String, dynamic>;
          final matches = r['matches'] as List<dynamic>? ?? [];
          for (var mi = 0; mi < matches.length; mi++) {
            final m = matches[mi] as Map<String, dynamic>;
            addFromMatch(m, 'levelBrackets.$level.$ri.matches.$mi', level, ri, mi);
          }
        }
      }
    } else if (roundsData != null && roundsData.isNotEmpty) {
      for (var ri = 0; ri < roundsData.length; ri++) {
        final r = roundsData[ri] as Map<String, dynamic>;
        final matches = r['matches'] as List<dynamic>? ?? [];
        for (var mi = 0; mi < matches.length; mi++) {
          final m = matches[mi] as Map<String, dynamic>;
          addFromMatch(m, 'rounds.$ri.matches.$mi', null, ri, mi);
        }
      }
    } else {
      for (var i = 0; i < qf.length; i++) {
        addFromMatch(qf[i] as Map<String, dynamic>, 'quarterFinals.$i', null, 0, i);
      }
      for (var i = 0; i < sf.length; i++) {
        addFromMatch(sf[i] as Map<String, dynamic>, 'semiFinals.$i', null, 1, i);
      }
      if (finalMatch != null && finalMatch.isNotEmpty) {
        addFromMatch(finalMatch, 'final', null, 2, 0);
      }
    }
    return out;
  }

  Future<void> _showAddKnockoutMatchResultDialog(_KnockoutMatchInfo info) async {
    final scoreController = TextEditingController();
    String? selectedWinner;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Add Result - ${info.matchId}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${info.team1Name} vs ${info.team2Name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: scoreController,
                    decoration: const InputDecoration(
                      labelText: 'Score',
                      hintText: 'e.g., 6-1 6-1 or 6-1',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Winner', border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: 'team1', child: Text(info.team1Name!)),
                      DropdownMenuItem(value: 'team2', child: Text(info.team2Name!)),
                    ],
                    onChanged: (v) => setDialogState(() => selectedWinner = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (scoreController.text.trim().isEmpty || selectedWinner == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill score and winner'), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  final scoreResult = _parseScore(scoreController.text.trim());
                  if (scoreResult == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid score. Use: 6-1 6-1 or 6-1'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  await _saveKnockoutMatchResult(info, scoreController.text.trim(), selectedWinner!, scoreResult['difference'] as int);
                  if (mounted) {
                    Navigator.pop(context);
                    scoreController.dispose();
                  }
                },
                child: const Text('Add Result'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _saveKnockoutMatchResult(_KnockoutMatchInfo info, String score, String winner, int scoreDiff) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('tournaments').doc(widget.tournamentId);
      final doc = await docRef.get();
      if (!doc.exists) return;
      final data = doc.data()!;
      var knockout = Map<String, dynamic>.from(data['knockout'] as Map<String, dynamic>? ?? {});

      if (info.path.startsWith('levelBrackets.') && info.level != null) {
        var lb = Map<String, dynamic>.from(knockout['levelBrackets'] as Map<String, dynamic>? ?? {});
        var rounds = List<dynamic>.from(lb[info.level!] as List<dynamic>? ?? []);
        if (info.roundIdx < rounds.length) {
          var r = Map<String, dynamic>.from(rounds[info.roundIdx] as Map<String, dynamic>);
          var matches = List<dynamic>.from(r['matches'] as List<dynamic>? ?? []);
          if (info.matchIdx < matches.length) {
            var m = Map<String, dynamic>.from(matches[info.matchIdx] as Map<String, dynamic>);
            m['winner'] = winner;
            matches[info.matchIdx] = m;
            r['matches'] = matches;
            rounds[info.roundIdx] = r;
            lb[info.level!] = rounds;
            knockout['levelBrackets'] = lb;
          }
        }
      } else if (info.path.startsWith('rounds.')) {
        var rounds = List<dynamic>.from(knockout['rounds'] as List<dynamic>? ?? []);
        if (info.roundIdx < rounds.length) {
          var r = Map<String, dynamic>.from(rounds[info.roundIdx] as Map<String, dynamic>);
          var matches = List<dynamic>.from(r['matches'] as List<dynamic>? ?? []);
          if (info.matchIdx < matches.length) {
            var m = Map<String, dynamic>.from(matches[info.matchIdx] as Map<String, dynamic>);
            m['winner'] = winner;
            matches[info.matchIdx] = m;
            r['matches'] = matches;
            rounds[info.roundIdx] = r;
            knockout['rounds'] = rounds;
          }
        }
      } else if (info.path.startsWith('quarterFinals.')) {
        var qf = List<dynamic>.from(knockout['quarterFinals'] as List<dynamic>? ?? []);
        if (info.matchIdx < qf.length) {
          var m = Map<String, dynamic>.from(qf[info.matchIdx] as Map<String, dynamic>);
          m['winner'] = winner;
          qf[info.matchIdx] = m;
          knockout['quarterFinals'] = qf;
        }
      } else if (info.path.startsWith('semiFinals.')) {
        var sf = List<dynamic>.from(knockout['semiFinals'] as List<dynamic>? ?? []);
        if (info.matchIdx < sf.length) {
          var m = Map<String, dynamic>.from(sf[info.matchIdx] as Map<String, dynamic>);
          m['winner'] = winner;
          sf[info.matchIdx] = m;
          knockout['semiFinals'] = sf;
        }
      } else if (info.path == 'final') {
        var f = Map<String, dynamic>.from(knockout['final'] as Map<String, dynamic>? ?? {});
        f['winner'] = winner;
        knockout['final'] = f;
      }

      // Propagate winners to downstream matches (e.g. semi winners -> final)
      KnockoutBracketUtils.propagateWinners(knockout);

      await docRef.update({
        'knockout': knockout,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _addMatch(
        info.team1Key ?? '',
        info.team1Name ?? '',
        info.team2Key ?? '',
        info.team2Name ?? '',
        score,
        winner,
        scoreDiff,
        groupName: null,
        knockoutMatchId: info.matchId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Knockout result added'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Parse score string like "6-1 6-1" or "6-1" and calculate difference
  Map<String, dynamic>? _parseScore(String score) {
    try {
      // Remove extra spaces and split
      final parts = score.trim().split(RegExp(r'\s+'));
      int totalDifference = 0;

      for (var part in parts) {
        // Match format like "6-1"
        final match = RegExp(r'^(\d+)-(\d+)$').firstMatch(part);
        if (match == null) return null;

        final winnerScore = int.parse(match.group(1)!);
        final loserScore = int.parse(match.group(2)!);
        totalDifference += (winnerScore - loserScore);
      }

      return {
        'difference': totalDifference,
      };
    } catch (e) {
      return null;
    }
  }

  Future<void> _addMatch(
    String team1Key,
    String team1Name,
    String team2Key,
    String team2Name,
    String score,
    String winner,
    int scoreDifference, {
    String? groupName,
    String? knockoutMatchId,
  }) async {
    try {
      final data = {
        'tournamentId': widget.tournamentId,
        'tournamentName': widget.tournamentName,
        'team1Name': team1Name,
        'team2Name': team2Name,
        'team1Key': team1Key,
        'team2Key': team2Key,
        'score': score,
        'winner': winner,
        'scoreDifference': scoreDifference,
        'timestamp': FieldValue.serverTimestamp(),
      };
      if (groupName != null) data['groupName'] = groupName;
      if (knockoutMatchId != null) data['knockoutMatchId'] = knockoutMatchId;
      await FirebaseFirestore.instance.collection('tournamentMatches').add(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match added successfully'),
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

  Future<void> _deleteMatch(String matchId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Match'),
        content: const Text('Are you sure you want to delete this match?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('tournamentMatches')
            .doc(matchId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Match deleted'),
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
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // Navigate to groups screen (simple tournaments)
  void _navigateToGroupsScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TournamentGroupsScreen(
          tournamentId: widget.tournamentId,
          tournamentName: widget.tournamentName,
        ),
      ),
    );
  }

  // Navigate to tournament setup (two-phase: Phase 1 / Phase 2 configure)
  void _navigateToTournamentSetup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminTournamentSetupScreen(
          tournamentId: widget.tournamentId,
          tournamentName: widget.tournamentName,
        ),
      ),
    );
  }

  // Show edit schedule dialog for a specific group (court, time, and order of play)
  Future<void> _showEditGroupScheduleDialog(
    String groupName,
    Map<String, dynamic>? currentSchedule,
    List<QueryDocumentSnapshot> teamsInGroup,
  ) async {
    final courtController = TextEditingController(text: currentSchedule?['court']?.toString() ?? '');
    final dateController = TextEditingController(text: currentSchedule?['date'] ?? '');
    final startTimeController = TextEditingController(text: currentSchedule?['startTime'] ?? '');
    final endTimeController = TextEditingController(text: currentSchedule?['endTime'] ?? '');

    // Build team list
    final teams = <Map<String, dynamic>>[];
    for (var reg in teamsInGroup) {
      final data = reg.data() as Map<String, dynamic>;
      final teamKey = _generateTeamKey(data);
      final firstName = data['firstName'] as String? ?? '';
      final lastName = data['lastName'] as String? ?? '';
      final partner = data['partner'] as Map<String, dynamic>?;
      final teamName = partner != null
          ? '$firstName $lastName & ${partner['partnerName'] as String? ?? 'Unknown'}'
          : '$firstName $lastName';
      teams.add({'key': teamKey, 'name': teamName});
    }

    // Order of Play: for N teams, round-robin has N*(N-1)/2 matches
    final numMatches = teams.length >= 2 ? (teams.length * (teams.length - 1) ~/ 2) : 0;
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

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Edit Schedule: $groupName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    const Text(
                      'Order of Play',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Set which teams play in each match (e.g. Match 1: Team A vs Team B, Match 2: Team B vs Team C)',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
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
                              decoration: const InputDecoration(
                                labelText: 'Team 1',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Select...')),
                                ...teams.map((t) => DropdownMenuItem(
                                      value: t['key'] as String,
                                      child: Text(
                                        (t['name'] as String),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                              ],
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
                              decoration: const InputDecoration(
                                labelText: 'Team 2',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Select...')),
                                ...teams.where((t) => t['key'] != team1Key).map((t) => DropdownMenuItem(
                                      value: t['key'] as String,
                                      child: Text(
                                        (t['name'] as String),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                              ],
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
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    final schedule = {
                      'court': courtController.text.trim().isNotEmpty ? courtController.text.trim() : null,
                      'date': dateController.text.trim().isNotEmpty ? dateController.text.trim() : null,
                      'startTime': startTimeController.text.trim().isNotEmpty ? startTimeController.text.trim() : null,
                      'endTime': endTimeController.text.trim().isNotEmpty ? endTimeController.text.trim() : null,
                      'orderOfPlay': orderOfPlay
                          .where((m) => (m['team1Key'] ?? '').isNotEmpty && (m['team2Key'] ?? '').isNotEmpty)
                          .map((m) => {'team1Key': m['team1Key'], 'team2Key': m['team2Key']})
                          .toList(),
                    };

                    await FirebaseFirestore.instance
                        .collection('tournaments')
                        .doc(widget.tournamentId)
                        .update({
                      'groups.$groupName.schedule': schedule,
                    });

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Schedule and Order of Play updated'),
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
                },
                style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Show add match dialog for a specific group
  Future<void> _showAddGroupMatchDialog(String groupName, List<QueryDocumentSnapshot> teamsInGroup) async {
    if (teamsInGroup.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No teams in this group'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Build team list - one entry per unique teamKey (from groups, no duplicates)
    final seenKeys = <String>{};
    final List<Map<String, dynamic>> teams = [];
    for (var reg in teamsInGroup) {
      final data = reg.data() as Map<String, dynamic>;
      final teamKey = _generateTeamKey(data);
      if (!seenKeys.add(teamKey)) continue;
      final firstName = data['firstName'] as String? ?? '';
      final lastName = data['lastName'] as String? ?? '';
      final partner = data['partner'] as Map<String, dynamic>?;
      final teamName = partner != null
          ? '$firstName $lastName & ${partner['partnerName'] as String? ?? 'Unknown'}'
          : '$firstName $lastName';

      teams.add({
        'key': teamKey,
        'name': teamName,
        'registrationId': reg.id,
      });
    }

    String? selectedTeam1Key;
    String? selectedTeam1Name;
    String? selectedTeam2Key;
    String? selectedTeam2Name;
    final scoreController = TextEditingController();
    String? selectedWinner;

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Add Match Result - $groupName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Team 1',
                      border: OutlineInputBorder(),
                    ),
                    items: teams.map((team) {
                      return DropdownMenuItem(
                        value: team['key'] as String,
                        child: Text(
                          team['name'] as String,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedTeam1Key = value;
                        selectedTeam1Name = teams.firstWhere((t) => t['key'] == value)['name'] as String;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Team 2',
                      border: OutlineInputBorder(),
                    ),
                    items: teams
                        .where((team) => team['key'] != selectedTeam1Key)
                        .map((team) {
                      return DropdownMenuItem(
                        value: team['key'] as String,
                        child: Text(
                          team['name'] as String,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedTeam2Key = value;
                        selectedTeam2Name = teams.firstWhere((t) => t['key'] == value)['name'] as String;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: scoreController,
                    decoration: const InputDecoration(
                      labelText: 'Score',
                      hintText: 'e.g., 6-1 6-1 or 6-1 (for 1 set)',
                      border: OutlineInputBorder(),
                      helperText: 'Format: 6-1 6-1 (2 sets) or 6-1 (1 set)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Winner',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      if (selectedTeam1Name != null)
                        DropdownMenuItem(
                          value: 'team1',
                          child: Text(
                            selectedTeam1Name!,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      if (selectedTeam2Name != null)
                        DropdownMenuItem(
                          value: 'team2',
                          child: Text(
                            selectedTeam2Name!,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedWinner = value;
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
                  if (selectedTeam1Key == null ||
                      selectedTeam2Key == null ||
                      scoreController.text.trim().isEmpty ||
                      selectedWinner == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please fill all fields'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  // Validate and parse score
                  final scoreResult = _parseScore(scoreController.text.trim());
                  if (scoreResult == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invalid score format. Use: 6-1 6-1 or 6-1'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  await _addMatch(
                    selectedTeam1Key!,
                    selectedTeam1Name!,
                    selectedTeam2Key!,
                    selectedTeam2Name!,
                    scoreController.text.trim(),
                    selectedWinner!,
                    scoreResult['difference'] as int,
                    groupName: groupName,
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    scoreController.dispose();
                  }
                },
                child: const Text('Add Match'),
              ),
            ],
          ),
        ),
      );
    }
  }

  // Delete a group
  Future<void> _deleteGroup(String groupName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Are you sure you want to delete $groupName? This will remove all teams from this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
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
        
        groups.remove(groupName);

        await FirebaseFirestore.instance
            .collection('tournaments')
            .doc(widget.tournamentId)
            .update({'groups': groups});

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$groupName deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting group: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildOverallYearStandings() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournaments')
          .where('parentTournamentId', isEqualTo: widget.tournamentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final weeklyTournaments = snapshot.data!.docs;
        
        if (weeklyTournaments.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.leaderboard, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No weekly tournaments yet',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  'Add weekly tournaments to see overall year standings',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Fetch overall standings - use limit to avoid empty collection issues
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tpfOverallStandings')
              .orderBy('totalPoints', descending: true)
              .limit(100)
              .snapshots(),
          builder: (context, standingsSnapshot) {
            if (standingsSnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading standings: ${standingsSnapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (standingsSnapshot.connectionState == ConnectionState.waiting || !standingsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final overallStandings = standingsSnapshot.data!.docs;

            if (overallStandings.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.emoji_events, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No standings yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Complete weekly tournaments to see overall standings',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final screenWidth = MediaQuery.of(context).size.width;
            final panelWidth = screenWidth > 600 ? screenWidth * 0.45 : screenWidth * 0.85;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT: Overall Standings
                  SizedBox(
                    width: panelWidth,
                    child: ListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        Card(
                          color: const Color(0xFF1E3A8A),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.emoji_events,
                                  size: 48,
                                  color: Colors.amber,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Overall Standings',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${weeklyTournaments.length} Tournament${weeklyTournaments.length != 1 ? 's' : ''}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...overallStandings.asMap().entries.map((entry) {
                  final rank = entry.key + 1;
                  final doc = entry.value;
                  final data = doc.data() as Map<String, dynamic>;
                  final teamName = data['teamName'] as String? ?? 'Unknown Team';
                  final totalPoints = data['totalPoints'] as int? ?? 0;
                  final tournamentsPlayed = data['tournamentsPlayed'] as int? ?? 0;
                  final tournaments = data['tournaments'] as Map<String, dynamic>? ?? {};

                  Color rankColor = Colors.grey[700]!;
                  IconData? rankIcon;
                  
                  if (rank == 1) {
                    rankColor = Colors.amber;
                    rankIcon = Icons.emoji_events;
                  } else if (rank == 2) {
                    rankColor = Colors.grey[400]!;
                    rankIcon = Icons.looks_two;
                  } else if (rank == 3) {
                    rankColor = Colors.brown[300]!;
                    rankIcon = Icons.looks_3;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: rank <= 3 ? 4 : 1,
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: rankColor,
                        child: rankIcon != null
                            ? Icon(rankIcon, color: Colors.white)
                            : Text(
                                '$rank',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      title: Text(
                        teamName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        '$tournamentsPlayed tournament${tournamentsPlayed != 1 ? 's' : ''} played',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$totalPoints pts',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tournament History:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...tournaments.entries.map((tournamentEntry) {
                                final tournamentData = tournamentEntry.value as Map<String, dynamic>;
                                final tournamentName = tournamentData['tournamentName'] as String? ?? 'Unknown';
                                final placement = tournamentData['placement'] as int? ?? 0;
                                final points = tournamentData['points'] as int? ?? 0;
                                final bonus = tournamentData['bonus'] as int? ?? 0;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Icon(
                                        placement == 1
                                            ? Icons.emoji_events
                                            : placement == 2
                                                ? Icons.looks_two
                                                : placement == 3
                                                    ? Icons.looks_3
                                                    : Icons.military_tech,
                                        size: 16,
                                        color: placement <= 3 ? Colors.amber : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          tournamentName,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Text(
                                        '${placement}st/nd/rd',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '$points pts',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (bonus > 0) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          '(+$bonus)',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // RIGHT: Child Tournaments
                  SizedBox(
                    width: panelWidth,
                    child: ListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        Card(
                          color: const Color(0xFF1E3A8A),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.list,
                                  size: 48,
                                  color: Colors.white70,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Sub-Tournaments',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${weeklyTournaments.length} weekly',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...weeklyTournaments.asMap().entries.map((entry) {
                          final index = entry.key;
                          final wDoc = entry.value;
                          final wData = wDoc.data() as Map<String, dynamic>;
                          final wName = wData['name'] as String? ?? 'Week ${index + 1}';
                          final wDate = wData['date'] as String? ?? '';
                          final wStatus = wData['status'] as String? ?? 'upcoming';
                          final hasStarted = ['phase1', 'phase2', 'knockout', 'completed', 'groups'].contains(wStatus);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFF1E3A8A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                wDate.isNotEmpty ? wDate : wName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(wStatus.toUpperCase()),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!hasStarted)
                                    IconButton(
                                      icon: const Icon(Icons.login, size: 20, color: Color(0xFF1E3A8A)),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => TournamentJoinScreen(
                                              tournamentId: wDoc.id,
                                              tournamentName: wName,
                                              tournamentImageUrl: wData['imageUrl'] as String?,
                                            ),
                                          ),
                                        );
                                      },
                                      tooltip: 'Join',
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.leaderboard, size: 20, color: Colors.green),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => TournamentDashboardScreen(
                                            tournamentId: wDoc.id,
                                            tournamentName: wName,
                                          ),
                                        ),
                                      );
                                    },
                                    tooltip: 'Results',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRulesTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final tournamentData = snapshot.data!.data() as Map<String, dynamic>?;
        final rules = tournamentData?['rules'] as Map<String, dynamic>?;
        final rulesText = rules?['text'] as String?;

        if (rulesText == null || rulesText.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.rule, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'No rules have been set for this tournament',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AdminTournamentSetupScreen(
                            tournamentId: widget.tournamentId,
                            tournamentName: widget.tournamentName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Add Rules'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.rule, color: Colors.orange, size: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tournament Rules',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Please read and follow these rules during the tournament',
                            style: TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rulesText,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

