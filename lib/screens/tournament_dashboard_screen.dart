import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tournament_groups_screen.dart';

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
    if (_checkingAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.tournamentName),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Groups', icon: Icon(Icons.group)),
              Tab(text: 'Standings', icon: Icon(Icons.leaderboard)),
              Tab(text: 'Playoffs', icon: Icon(Icons.tour)),
              Tab(text: 'Matches', icon: Icon(Icons.sports_tennis)),
            ],
          ),
          actions: _isAdmin
              ? [
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
          children: [
            _buildGroupsTab(),
            _buildStandingsTab(),
            _buildPlayoffsTab(),
            _buildMatchesTab(),
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
                    'Tap + to create groups',
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
                final teamKeys = (groups[groupName] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ?? [];

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
                        ? IconButton(
                            icon: const Icon(Icons.edit, color: Color(0xFF1E3A8A)),
                            onPressed: () => _showAddGroupMatchDialog(groupName, teamsInGroup),
                            tooltip: 'Enter Results for ${groupName}',
                          )
                        : null,
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
                            title: Text(teamName),
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
      final teamKeys = (groupEntry.value as List<dynamic>).map((e) => e.toString()).toList();
      
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
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, matchesSnapshot) {
                if (matchesSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final registrations = registrationsSnapshot.data!.docs;
                final matches = matchesSnapshot.hasData ? matchesSnapshot.data!.docs : <QueryDocumentSnapshot>[];

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
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isTopTwo
                                      ? (isFirst ? Colors.amber : Colors.green)
                                      : Colors.grey[400],
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
                                        style: TextStyle(
                                          fontWeight: isTopTwo ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isTopTwo)
                                      Container(
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
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
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
                                    const SizedBox(width: 8),
                                    Text(
                                      '${team['scoreDifference'] >= 0 ? '+' : ''}${team['scoreDifference']}',
                                      style: TextStyle(
                                        color: (team['scoreDifference'] as int) >= 0
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${team['gamesWon']}-${team['gamesLost']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
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
        final groups = tournamentData?['groups'] as Map<String, dynamic>? ?? {};

        if (groups.isEmpty) {
          return const Center(
            child: Text('No groups created yet. Create groups first to see playoffs.'),
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
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, matchesSnapshot) {
                if (matchesSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final registrations = registrationsSnapshot.data!.docs;
                final matches = matchesSnapshot.hasData ? matchesSnapshot.data!.docs : <QueryDocumentSnapshot>[];

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

  Widget _buildMatchesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tournamentMatches')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .orderBy('timestamp', descending: true)
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

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: matches.length,
          itemBuilder: (context, index) {
            final matchDoc = matches[index];
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
                            style: TextStyle(
                              fontWeight: winner == 'team1' ? FontWeight.bold : FontWeight.normal,
                              color: winner == 'team1' ? Colors.green[700] : null,
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
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: winner == 'team2' ? FontWeight.bold : FontWeight.normal,
                              color: winner == 'team2' ? Colors.green[700] : null,
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
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Team 1',
                      border: OutlineInputBorder(),
                    ),
                    items: teams.map((team) {
                      return DropdownMenuItem(
                        value: team['key'] as String,
                        child: Text(team['name'] as String),
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
                    ),
                    items: teams
                        .where((team) => team['key'] != selectedTeam1Key)
                        .map((team) {
                      return DropdownMenuItem(
                        value: team['key'] as String,
                        child: Text(team['name'] as String),
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
                    decoration: const InputDecoration(
                      labelText: 'Winner',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      if (selectedTeam1Name != null)
                        DropdownMenuItem(
                          value: 'team1',
                          child: Text(selectedTeam1Name!),
                        ),
                      if (selectedTeam2Name != null)
                        DropdownMenuItem(
                          value: 'team2',
                          child: Text(selectedTeam2Name!),
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

  // Generate team key from registration
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
                    decoration: const InputDecoration(
                      labelText: 'Team 1',
                      border: OutlineInputBorder(),
                    ),
                    items: teams.map((team) {
                      return DropdownMenuItem(
                        value: team['key'] as String,
                        child: Text(team['name'] as String),
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
                    ),
                    items: teams
                        .where((team) => team['key'] != selectedTeam1Key)
                        .map((team) {
                      return DropdownMenuItem(
                        value: team['key'] as String,
                        child: Text(team['name'] as String),
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
                    decoration: const InputDecoration(
                      labelText: 'Winner',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      if (selectedTeam1Name != null)
                        DropdownMenuItem(
                          value: 'team1',
                          child: Text(selectedTeam1Name!),
                        ),
                      if (selectedTeam2Name != null)
                        DropdownMenuItem(
                          value: 'team2',
                          child: Text(selectedTeam2Name!),
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

                  final scoreDifference = _calculateScoreDifference(
                    scoreController.text.trim(),
                    selectedWinner!,
                  );

                  if (scoreDifference == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invalid score format'),
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
                    scoreDifference['difference'] as int,
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
}
