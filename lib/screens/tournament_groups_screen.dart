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
              if (!registrationsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
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
                for (var groupTeams in groups.values) {
                  final teamKeys = (groupTeams as List<dynamic>).map((e) => e.toString()).toList();
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
                  // Add button to randomly distribute teams if there are approved teams
                  if (_isAdmin && approvedTeams.isNotEmpty && groups.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton.icon(
                        onPressed: _distributeTeamsRandomly,
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Distribute Teams Randomly'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
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
                    final teamKey = _generateTeamKey(data);
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
                      children: [
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
      // Create empty groups
      final groups = <String, List<String>>{};
      for (int i = 1; i <= count; i++) {
        groups['Group $i'] = [];
      }

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'groups': groups.map((key, value) => MapEntry(key, value)),
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

      // Clear existing teams from groups
      final updatedGroups = <String, List<String>>{};
      for (var groupName in groups.keys) {
        updatedGroups[groupName] = [];
      }

      // Distribute teams evenly across groups
      final groupList = updatedGroups.keys.toList();
      for (int i = 0; i < allTeamKeys.length; i++) {
        final groupIndex = i % groupList.length;
        updatedGroups[groupList[groupIndex]]!.add(allTeamKeys[i]);
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
      
      final groupTeams = List<String>.from(groups[groupName] as List<dynamic>? ?? []);
      if (!groupTeams.contains(teamKey)) {
        groupTeams.add(teamKey);
        groups[groupName] = groupTeams;
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
      
      final groupTeams = List<String>.from(groups[groupName] as List<dynamic>? ?? []);
      groupTeams.remove(teamKey);
      groups[groupName] = groupTeams;

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
}
