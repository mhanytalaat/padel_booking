import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  // Get team name from registration
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

              // Check if there are approved teams available that are not in any group
              final approvedTeams = registrations.where((reg) {
                final data = reg.data() as Map<String, dynamic>;
                final teamKey = _generateTeamKey(data);
                // Check if team is not already in any group
                for (var groupData in groups.values) {
                  List<String> teamKeys;
                  // Handle both old (list) and new (object with teamKeys) structures
                  if (groupData is List) {
                    teamKeys = groupData.map((e) => e.toString()).toList();
                  } else if (groupData is Map && groupData['teamKeys'] is List) {
                    teamKeys = (groupData['teamKeys'] as List).map((e) => e.toString()).toList();
                  } else {
                    teamKeys = [];
                  }
                  if (teamKeys.contains(teamKey)) {
                    return false;
                  }
                }
                return true;
              }).toList();

              // Build group display
              final groupList = groups.keys.toList()..sort();
              
              return Column(
                children: [
                  // Add buttons to distribute teams
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
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('groups_list'),
                      padding: const EdgeInsets.all(16),
                      itemCount: groupList.length,
                      itemBuilder: (context, index) {
                  final groupName = groupList[index];
                  final groupData = groups[groupName];
                  
                  // Handle both old (list) and new (object) structures
                  List<String> teamKeys;
                  Map<String, dynamic>? schedule;
                  
                  if (groupData is List) {
                    teamKeys = groupData.map((e) => e.toString()).toList();
                    schedule = null;
                  } else if (groupData is Map) {
                    teamKeys = (groupData['teamKeys'] as List?)?.map((e) => e.toString()).toList() ?? [];
                    schedule = groupData['schedule'] as Map<String, dynamic>?;
                  } else {
                    teamKeys = [];
                    schedule = null;
                  }

                  // Get teams in this group
                  final teamsInGroup = registrations.where((reg) {
                    final data = reg.data() as Map<String, dynamic>;
                    final teamKey = _generateTeamKey(data);
                    return teamKeys.contains(teamKey);
                  }).toList();
                  
                  // Build subtitle with team count and schedule info
                  String subtitle = '${teamsInGroup.length} teams';
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
                          groupName.replaceAll('Group ', ''),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        groupName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      subtitle: Text(subtitle),
                      children: [
                        // Schedule section (if admin)
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
                                    const Text(
                                      'Match Schedule',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () => _showEditScheduleDialog(groupName, schedule, teamKeys),
                                      icon: const Icon(Icons.edit, size: 16),
                                      label: const Text('Edit Schedule'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (schedule != null) ...[
                                  Text('Court: ${schedule['court'] ?? 'Not set'}'),
                                  Text('Time: ${schedule['startTime'] ?? 'Not set'}'),
                                  if (schedule['endTime'] != null)
                                    Text('End: ${schedule['endTime']}'),
                                ] else
                                  const Text('No schedule set', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
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
                              onPressed: () => _showAddTeamToGroupDialog(groupName, registrations, teamKeys),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Team to Group'),
                            ),
                          ),
                      ],
                    ),
                  );
                      },
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

  Future<void> _showCreateGroupsDialog() async {
    final groupCountController = TextEditingController(text: '3');
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Groups'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How many groups do you want to create?'),
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
          ],
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

              await _createGroups(count);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createGroups(int count) async {
    try {
      // Create empty groups with new structure
      final groups = <String, Map<String, dynamic>>{};
      for (int i = 1; i <= count; i++) {
        groups['Group $i'] = {
          'teamKeys': [],
          'schedule': {
            'court': '',
            'startTime': '',
          },
        };
      }

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'groups': groups,
      });

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

  // Randomly distribute teams to groups
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

      // Generate team keys
      final allTeamKeys = registrations.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return _generateTeamKey(data);
      }).toList();

      // Shuffle teams for random distribution
      allTeamKeys.shuffle();

      // Clear existing teams from groups, keep structure
      final updatedGroups = <String, dynamic>{};
      for (var entry in groups.entries) {
        final groupName = entry.key;
        final groupData = entry.value;
        
        // Preserve structure (new or old)
        if (groupData is Map && groupData['schedule'] != null) {
          updatedGroups[groupName] = {
            'teamKeys': [],
            'schedule': groupData['schedule'],
          };
        } else {
          updatedGroups[groupName] = [];
        }
      }

      // Distribute teams evenly across groups
      final groupList = updatedGroups.keys.toList();
      for (int i = 0; i < allTeamKeys.length; i++) {
        final groupIndex = i % groupList.length;
        final groupName = groupList[groupIndex];
        final groupData = updatedGroups[groupName];
        
        // Handle both structures
        if (groupData is List) {
          groupData.add(allTeamKeys[i]);
        } else if (groupData is Map && groupData['teamKeys'] is List) {
          (groupData['teamKeys'] as List).add(allTeamKeys[i]);
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
            content: Text('Randomly distributed ${allTeamKeys.length} teams across ${groupList.length} groups'),
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
  ) async {
    // Get teams not in any group or not in this group
    final availableTeams = allRegistrations.where((reg) {
      final data = reg.data() as Map<String, dynamic>;
      final teamKey = _generateTeamKey(data);
      return !currentTeamKeys.contains(teamKey);
    }).toList();

    if (availableTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No available teams to add'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? selectedTeamKey;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Team to $groupName'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableTeams.length,
            itemBuilder: (context, index) {
              final reg = availableTeams[index];
              final data = reg.data() as Map<String, dynamic>;
              final teamName = _getTeamName(data);
              final teamKey = _generateTeamKey(data);

              return RadioListTile<String>(
                title: Text(teamName),
                value: teamKey,
                groupValue: selectedTeamKey,
                onChanged: (value) {
                  setState(() {
                    selectedTeamKey = value;
                  });
                  Navigator.pop(context);
                  if (selectedTeamKey != null) {
                    _addTeamToGroup(groupName, selectedTeamKey!);
                  }
                },
              );
            },
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

  Future<void> _addTeamToGroup(String groupName, String teamKey) async {
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
      
      if (!groupTeams.contains(teamKey)) {
        groupTeams.add(teamKey);
        
        // Keep new structure if it exists, otherwise use old structure
        if (groupData is Map) {
          groups[groupName] = {
            ...groupData,
            'teamKeys': groupTeams,
          };
        } else {
          groups[groupName] = groupTeams;
        }
      }

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({'groups': groups});

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
      
      groupTeams.remove(teamKey);
      
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
              content: Text('No approved teams to group'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Group teams by their level
      final Map<String, List<String>> levelGroups = {};
      
      for (var doc in registrations.docs) {
        final data = doc.data();
        final level = data['level'] as String? ?? 'Beginner';
        final teamKey = _generateTeamKey(data);
        
        if (!levelGroups.containsKey(level)) {
          levelGroups[level] = [];
        }
        levelGroups[level]!.add(teamKey);
      }

      // Sort levels in preferred order: C+, C-, D, Beginner, Seniors, Mix Doubles, Women
      final levelOrder = ['C+', 'C-', 'D', 'Beginner', 'Seniors', 'Mix Doubles', 'Women'];
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
        final teams = levelGroups[level]!;
        totalTeams += teams.length;
        
        // If a level has many teams, split into multiple groups
        // Max 6 teams per group (adjust as needed)
        const maxTeamsPerGroup = 6;
        final numGroups = (teams.length / maxTeamsPerGroup).ceil();
        
        if (numGroups == 1) {
          // Single group for this level
          groups['Level $level'] = {
            'teamKeys': teams,
            'schedule': {
              'court': '',
              'startTime': '',
            },
          };
        } else {
          // Multiple groups for this level
          for (int i = 0; i < numGroups; i++) {
            final startIndex = i * maxTeamsPerGroup;
            final endIndex = (startIndex + maxTeamsPerGroup > teams.length) 
                ? teams.length 
                : startIndex + maxTeamsPerGroup;
            final groupTeams = teams.sublist(startIndex, endIndex);
            
            groups['Level $level - Group ${i + 1}'] = {
              'teamKeys': groupTeams,
              'schedule': {
                'court': '',
                'startTime': '',
              },
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

  Future<void> _showEditScheduleDialog(String groupName, Map<String, dynamic>? currentSchedule, List<String> teamKeys) async {
    final courtController = TextEditingController(text: currentSchedule?['court'] as String? ?? '');
    final dateController = TextEditingController(text: currentSchedule?['date'] as String? ?? '');
    final startTimeController = TextEditingController(text: currentSchedule?['startTime'] as String? ?? '');
    final endTimeController = TextEditingController(text: currentSchedule?['endTime'] as String? ?? '');
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              final schedule = {
                'court': courtController.text.trim().isNotEmpty ? courtController.text.trim() : null,
                'date': dateController.text.trim().isNotEmpty ? dateController.text.trim() : null,
                'startTime': startTimeController.text.trim().isNotEmpty ? startTimeController.text.trim() : null,
                if (endTimeController.text.trim().isNotEmpty)
                  'endTime': endTimeController.text.trim(),
              };
              
              await _saveGroupSchedule(groupName, schedule, teamKeys);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Schedule'),
          ),
        ],
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
      
      // Convert to new structure with teamKeys and schedule
      groups[groupName] = {
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
