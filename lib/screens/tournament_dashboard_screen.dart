import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tournament_groups_screen.dart';
import 'admin_tournament_setup_screen.dart';

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
    // Normal tournaments: All tabs (5 tabs)
    final tabLength = _isParentTournament ? 2 : 5;

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
                        Tab(child: Text('Standings', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
                        Tab(child: Text('Playoffs', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
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
                          _navigateToGroupsScreen();
                        } else if (value == 'match') {
                          _showAddMatchDialog();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'groups',
                          child: Row(
                            children: [
                              Icon(Icons.group, color: Color(0xFF1E3A8A)),
                              SizedBox(width: 8),
                              Text('Add Groups'),
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
                      _buildStandingsTab(),
                      _buildPlayoffsTab(),
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
            final groupList = groups.keys.toList()..sort();

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groupList.length,
              itemBuilder: (context, index) {
                final groupName = groupList[index];
                
                // Handle both old (List) and new (Map with teamKeys) group structures
                List<String> teamKeys;
                Map<String, dynamic>? schedule;
                final groupValue = groups[groupName];
                if (groupValue is List) {
                  // Old structure: groups are lists of team keys
                  teamKeys = (groupValue as List<dynamic>).map((e) => e.toString()).toList();
                  schedule = null;
                } else if (groupValue is Map) {
                  // New structure: groups are maps with teamKeys and schedule
                  final groupData = groupValue as Map<String, dynamic>;
                  teamKeys = (groupData['teamKeys'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
                  schedule = groupData['schedule'] as Map<String, dynamic>?;
                } else {
                  teamKeys = [];
                  schedule = null;
                }

                // Get teams in this group
                final teamsInGroup = registrations.where((reg) {
                  final data = reg.data() as Map<String, dynamic>;
                  final userId = data['userId'] as String;
                  final partner = data['partner'] as Map<String, dynamic>?;
                  
                  String teamKey;
                  if (partner != null) {
                    final partnerId = partner['partnerId'] as String?;
                    if (partnerId != null) {
                      final userIds = [userId, partnerId];
                      userIds.sort();
                      teamKey = userIds.join('_');
                    } else {
                      teamKey = userId;
                    }
                  } else {
                    teamKey = userId;
                  }
                  
                  return teamKeys.contains(teamKey);
                }).toList();

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
                                onPressed: () => _showEditGroupScheduleDialog(groupName, schedule),
                                tooltip: 'Edit Schedule for ${groupName}',
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
                      // Order of Play (Schedule)
                      if (schedule != null && (schedule['court'] != null || schedule['startTime'] != null))
                        Container(
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
                              if (schedule['court'] != null)
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
                              if (schedule['startTime'] != null) ...[
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
                            ],
                          ),
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
              },
            );
          },
        );
      },
    );
  }

  // Calculate group-based standings
  Map<String, dynamic> _calculateGroupStandings(
    List<QueryDocumentSnapshot> matches,
    List<QueryDocumentSnapshot> registrations,
    Map<String, dynamic> groups,
  ) {
    Map<String, List<Map<String, dynamic>>> groupStandings = {};
    Map<String, Map<String, dynamic>> allTeamStats = {};

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
        final userIds = [userId, partner['partnerId'] as String? ?? ''];
        userIds.sort();
        teamKey = userIds.join('_');
        teamName = '$firstName $lastName & $partnerName';
      } else {
        teamKey = userId;
        teamName = '$firstName $lastName';
      }

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

    // Process matches
    for (var matchDoc in matches) {
      final matchData = matchDoc.data() as Map<String, dynamic>;
      final team1Key = matchData['team1Key'] as String?;
      final team2Key = matchData['team2Key'] as String?;
      final winner = matchData['winner'] as String?;
      final scoreDifference = matchData['scoreDifference'] as int? ?? 0;

      if (team1Key != null && team2Key != null && allTeamStats.containsKey(team1Key) && allTeamStats.containsKey(team2Key)) {
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
    }

    // Organize by groups
    for (var groupEntry in groups.entries) {
      final groupName = groupEntry.key;
      
      // Handle both old (List) and new (Map with teamKeys) group structures
      List<String> teamKeys;
      if (groupEntry.value is List) {
        // Old structure: groups are lists of team keys
        teamKeys = (groupEntry.value as List<dynamic>).map((e) => e.toString()).toList();
      } else if (groupEntry.value is Map) {
        // New structure: groups are maps with teamKeys and schedule
        final groupData = groupEntry.value as Map<String, dynamic>;
        teamKeys = (groupData['teamKeys'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
      } else {
        teamKeys = [];
      }
      
      final groupTeams = <Map<String, dynamic>>[];
      for (var teamKey in teamKeys) {
        if (allTeamStats.containsKey(teamKey)) {
          groupTeams.add(allTeamStats[teamKey]!);
        }
      }

      // Sort group teams
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
    final groupList = groups.keys.toList()..sort();

    return groupList.map((groupName) {
      final groupData = groups[groupName] as Map<String, dynamic>;
      final teamKeys = (groupData['teamKeys'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final schedule = groupData['schedule'] as Map<String, dynamic>?;
      final court = schedule?['court'] as String? ?? 'TBD';
      final startTime = schedule?['startTime'] as String? ?? 'TBD';
      final endTime = schedule?['endTime'] as String? ?? 'TBD';

      // Get teams in this group
      final teamsInGroup = registrations.where((reg) {
        final data = reg.data() as Map<String, dynamic>;
        final teamKey = _generateTeamKey(data);
        return teamKeys.contains(teamKey);
      }).toList();

      return Card(
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
      );
    }).toList();
  }

  List<Widget> _buildPhase2GroupCards(Map<String, dynamic> phase2, List<QueryDocumentSnapshot> registrations) {
    final groups = phase2['groups'] as Map<String, dynamic>? ?? {};
    final groupList = groups.keys.toList()..sort();

    return groupList.map((groupName) {
      final groupData = groups[groupName] as Map<String, dynamic>;
      final teamSlots = groupData['teamSlots'] as List<dynamic>? ?? [];
      final schedule = groupData['schedule'] as Map<String, dynamic>?;
      final court = schedule?['court'] as String? ?? 'TBD';
      final startTime = schedule?['startTime'] as String? ?? 'TBD';
      final endTime = schedule?['endTime'] as String? ?? 'TBD';

      return Card(
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
      );
    }).toList();
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
        
        // If parent tournament, show overall year standings
        if (isParentTournament) {
          return _buildOverallYearStandings();
        }

        final groups = tournamentData?['groups'] as Map<String, dynamic>? ?? {};

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

                // Group-based standings
                final groupStandingsData = _calculateGroupStandings(matches, registrations, groups);
                final groupStandings = groupStandingsData['groupStandings'] as Map<String, List<Map<String, dynamic>>>;

                if (groupStandings.isEmpty) {
                  return const Center(
                    child: Text('No group standings available'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groupStandings.length,
                  itemBuilder: (context, index) {
                    final groupName = groupStandings.keys.elementAt(index);
                    final teams = groupStandings[groupName]!;

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
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Top 2 Advance',
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
                          // Teams in group
                          ...teams.asMap().entries.map((entry) {
                            final position = entry.key;
                            final team = entry.value;
                            final isTopTwo = position < 2;
                            final isFirst = position == 0;

                            return Container(
                              decoration: BoxDecoration(
                                color: isTopTwo
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
                                    backgroundColor: isTopTwo
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
                                              fontWeight: isTopTwo ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        if (isTopTwo)
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
                                        '${team['points']}',
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
                                      '${team['scoreDifference'] >= 0 ? '+' : ''}${team['scoreDifference']}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: (team['scoreDifference'] as int) >= 0
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${team['gamesWon']}-${team['gamesLost']}',
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

  Widget _buildOverallStandings(List<Map<String, dynamic>> standings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        
        // Check for two-phase tournament with knockout bracket
        if (tournamentType == 'two-phase-knockout') {
          final knockout = tournamentData?['knockout'] as Map<String, dynamic>?;
          if (knockout != null) {
            return _buildKnockoutBracketDisplay(knockout);
          }
        }
        
        // Legacy format
        final groups = tournamentData?['groups'] as Map<String, dynamic>? ?? {};

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

                // Get advanced teams (top 2 from each group)
                final advancedTeams = _getAdvancedTeams(groupStandings);

                if (advancedTeams.isEmpty) {
                  return const Center(
                    child: Text('No teams have advanced yet. Play group matches first.'),
                  );
                }

                // Organize advanced teams for bracket display
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
                            '${advancedTeams.length} teams advanced (Top 2 from each group)',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Advanced teams by group
                    ...groupStandings.entries.map((groupEntry) {
                      final groupName = groupEntry.key;
                      final teams = groupEntry.value;
                      final topTwo = teams.take(2).toList();

                      if (topTwo.isEmpty) return const SizedBox.shrink();

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green,
                            child: const Icon(Icons.check, color: Colors.white),
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
                                    '${team['points']} pts | ${team['scoreDifference'] >= 0 ? '+' : ''}${team['scoreDifference']} diff | ${team['gamesWon']}-${team['gamesLost']} W-L',
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

  Widget _buildKnockoutBracketDisplay(Map<String, dynamic> knockout) {
    final quarterFinals = knockout['quarterFinals'] as List<dynamic>? ?? [];
    final semiFinals = knockout['semiFinals'] as List<dynamic>? ?? [];
    final finalMatch = knockout['final'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Quarter Finals
        if (quarterFinals.isNotEmpty) ...[
          _buildKnockoutStageHeader('🔶 Quarter Finals', Colors.orange),
          ...quarterFinals.map((qf) {
            final matchData = qf as Map<String, dynamic>;
            return _buildKnockoutMatchCard(matchData, Colors.orange);
          }),
          const SizedBox(height: 24),
        ],

        // Semi Finals
        if (semiFinals.isNotEmpty) ...[
          _buildKnockoutStageHeader('🔷 Semi Finals', Colors.deepOrange),
          ...semiFinals.map((sf) {
            final matchData = sf as Map<String, dynamic>;
            return _buildKnockoutMatchCard(matchData, Colors.deepOrange);
          }),
          const SizedBox(height: 24),
        ],

        // Final
        if (finalMatch != null) ...[
          _buildKnockoutStageHeader('🏆 FINAL', Colors.amber),
          _buildKnockoutMatchCard(finalMatch, Colors.amber),
        ],

        // Empty state
        if (quarterFinals.isEmpty && semiFinals.isEmpty && finalMatch == null) ...[
          Center(
            child: Column(
              children: [
                const Icon(Icons.settings, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Knockout bracket not configured yet',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
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
          ),
        ],
      ],
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

    final team1Text = team1 != null 
        ? '${team1['type'] == 'winner' ? 'Winner' : 'Runner-up'} of ${team1['from']}'
        : 'TBD';
    final team2Text = team2 != null 
        ? '${team2['type'] == 'winner' ? 'Winner' : 'Runner-up'} of ${team2['from']}'
        : 'TBD';

    final court = schedule?['court'] as String? ?? 'TBD';
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
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  court,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$startTime - $endTime',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
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
          .collection('tournamentMatches')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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

        final matches = snapshot.data!.docs;
        
        // Sort matches by timestamp (most recent first), handling null timestamps
        final sortedMatches = List<QueryDocumentSnapshot>.from(matches);
        sortedMatches.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTimestamp = aData['timestamp'] as Timestamp?;
          final bTimestamp = bData['timestamp'] as Timestamp?;
          
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1; // Put null timestamps at the end
          if (bTimestamp == null) return -1;
          
          return bTimestamp.compareTo(aTimestamp); // Descending order
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: sortedMatches.length,
          itemBuilder: (context, index) {
            final matchDoc = sortedMatches[index];
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
          },
        );
      },
    );
  }

  Future<void> _showAddMatchDialog() async {
    // Load approved registrations to select teams
    final registrationsSnapshot = await FirebaseFirestore.instance
        .collection('tournamentRegistrations')
        .where('tournamentId', isEqualTo: widget.tournamentId)
        .where('status', isEqualTo: 'approved')
        .get();

    if (registrationsSnapshot.docs.isEmpty) {
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

    // Build team list from registrations
    List<Map<String, dynamic>> teams = [];
    for (var reg in registrationsSnapshot.docs) {
      final data = reg.data();
      final userId = data['userId'] as String;
      final firstName = data['firstName'] as String? ?? '';
      final lastName = data['lastName'] as String? ?? '';
      final partner = data['partner'] as Map<String, dynamic>?;
      
      String teamKey;
      String teamName;
      
      if (partner != null) {
        final partnerName = partner['partnerName'] as String? ?? 'Unknown';
        final partnerId = partner['partnerId'] as String?;
        // Create consistent team key (sort user IDs)
        final userIds = [userId, partnerId ?? ''];
        userIds.sort();
        teamKey = userIds.join('_');
        teamName = '$firstName $lastName & $partnerName';
      } else {
        teamKey = userId;
        teamName = '$firstName $lastName';
      }

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
            title: const Text('Add Match Result'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Team 1',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: teams.map((team) {
                        return DropdownMenuItem(
                          value: team['key'] as String,
                          child: Text(
                            team['name'] as String,
                            overflow: TextOverflow.ellipsis,
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
                      decoration: const InputDecoration(
                        labelText: 'Team 2',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: teams
                          .where((team) => team['key'] != selectedTeam1Key)
                          .map((team) {
                        return DropdownMenuItem(
                          value: team['key'] as String,
                          child: Text(
                            team['name'] as String,
                            overflow: TextOverflow.ellipsis,
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
                        hintText: '6-1 6-1 or 6-1',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Format: 6-1 6-1 (2 sets) or 6-1 (1 set)',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Winner',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: [
                        if (selectedTeam1Name != null)
                          DropdownMenuItem(
                            value: 'team1',
                            child: Text(
                              selectedTeam1Name!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (selectedTeam2Name != null)
                          DropdownMenuItem(
                            value: 'team2',
                            child: Text(
                              selectedTeam2Name!,
                              overflow: TextOverflow.ellipsis,
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
                  );

                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Add Match'),
              ),
            ],
          ),
        ),
      );
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
    int scoreDifference,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('tournamentMatches').add({
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
      });

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

  // Navigate to groups screen
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

  // Show edit schedule dialog for a specific group
  Future<void> _showEditGroupScheduleDialog(String groupName, Map<String, dynamic>? currentSchedule) async {
    final courtController = TextEditingController(text: currentSchedule?['court']?.toString() ?? '');
    final startTimeController = TextEditingController(text: currentSchedule?['startTime'] ?? '');
    final endTimeController = TextEditingController(text: currentSchedule?['endTime'] ?? '');

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Edit Schedule - $groupName'),
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
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: startTimeController,
                  decoration: const InputDecoration(
                    labelText: 'Start Time',
                    hintText: 'e.g., 7:45 PM',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: endTimeController,
                  decoration: const InputDecoration(
                    labelText: 'End Time (Optional)',
                    hintText: 'e.g., 9:00 PM',
                    border: OutlineInputBorder(),
                  ),
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
                // Save schedule to Firestore
                try {
                  final schedule = {
                    'court': courtController.text.trim().isNotEmpty ? courtController.text.trim() : null,
                    'startTime': startTimeController.text.trim().isNotEmpty ? startTimeController.text.trim() : null,
                    'endTime': endTimeController.text.trim().isNotEmpty ? endTimeController.text.trim() : null,
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
                        content: Text('Schedule updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating schedule: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
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

    // Build team list from teams in this group
    List<Map<String, dynamic>> teams = [];
    for (var reg in teamsInGroup) {
      final data = reg.data() as Map<String, dynamic>;
      final userId = data['userId'] as String;
      final firstName = data['firstName'] as String? ?? '';
      final lastName = data['lastName'] as String? ?? '';
      final partner = data['partner'] as Map<String, dynamic>?;
      
      String teamKey;
      String teamName;
      
      if (partner != null) {
        final partnerName = partner['partnerName'] as String? ?? 'Unknown';
        final partnerId = partner['partnerId'] as String?;
        final userIds = [userId, partnerId ?? ''];
        userIds.sort();
        teamKey = userIds.join('_');
        teamName = '$firstName $lastName & $partnerName';
      } else {
        teamKey = userId;
        teamName = '$firstName $lastName';
      }

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
        if (!snapshot.hasData) {
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

        // Fetch all standings from all weekly tournaments
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('tpfOverallStandings')
              .orderBy('totalPoints', descending: true)
              .snapshots(),
          builder: (context, standingsSnapshot) {
            if (!standingsSnapshot.hasData) {
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

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
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
                          'Overall Year Standings',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${weeklyTournaments.length} Tournament${weeklyTournaments.length != 1 ? 's' : ''} Completed',
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

                // Standings list
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
