import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Phase 1 Setup Screen for configuring Groups 1-4
class Phase1SetupScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;

  const Phase1SetupScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<Phase1SetupScreen> createState() => _Phase1SetupScreenState();
}

class _Phase1SetupScreenState extends State<Phase1SetupScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _approvedTeams = [];
  
  // Phase 1 configuration
  final Map<String, Phase1GroupConfig> _groupConfigs = {
    'Group 1': Phase1GroupConfig(),
    'Group 2': Phase1GroupConfig(),
    'Group 3': Phase1GroupConfig(),
    'Group 4': Phase1GroupConfig(),
  };

  @override
  void initState() {
    super.initState();
    _loadApprovedTeams();
    _loadExistingConfiguration();
  }

  Future<void> _loadApprovedTeams() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('tournamentRegistrations')
          .where('tournamentId', isEqualTo: widget.tournamentId)
          .where('status', isEqualTo: 'approved')
          .get();

      final teams = <Map<String, dynamic>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final teamKey = _generateTeamKey(data);
        final teamName = _getTeamName(data);
        teams.add({
          'key': teamKey,
          'name': teamName,
          'data': data,
        });
      }

      setState(() {
        _approvedTeams = teams;
      });
    } catch (e) {
      debugPrint('Error loading approved teams: $e');
    }
  }

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

  Future<void> _loadExistingConfiguration() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final phase1 = data['phase1'] as Map<String, dynamic>?;
        
        if (phase1 != null) {
          final groups = phase1['groups'] as Map<String, dynamic>?;
          if (groups != null) {
            groups.forEach((groupName, groupData) {
              final config = _groupConfigs[groupName];
              if (config != null && groupData is Map<String, dynamic>) {
                config.loadFromFirestore(groupData);
              }
            });
            setState(() {});
          }
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
        title: Text('Phase 1 Setup - ${widget.tournamentName}'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  color: Color(0xFFE3F2FD),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📍 PHASE 1 - Initial Groups',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Configure Groups 1-4 with teams, court assignments, and time slots.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ..._groupConfigs.entries.map((entry) {
                  return _buildGroupCard(entry.key, entry.value);
                }),
                const SizedBox(height: 24),
                _buildSaveButton(),
              ],
            ),
    );
  }

  Widget _buildGroupCard(String groupName, Phase1GroupConfig config) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1E3A8A),
          child: Text(
            groupName.replaceAll('Group ', ''),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                groupName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showEditGroupNameDialog(groupName, config),
              tooltip: 'Edit Group Name',
            ),
          ],
        ),
        subtitle: Text('${config.teamKeys.length} teams | ${config.court}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Court assignment
                const Text(
                  'Court Assignment',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: config.courtController,
                  decoration: const InputDecoration(
                    labelText: 'Court',
                    hintText: 'e.g., Court 1',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    config.court = value;
                  },
                ),
                const SizedBox(height: 16),
                // Time slot
                const Text(
                  'Time Slot',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: config.startTimeController,
                        decoration: const InputDecoration(
                          labelText: 'Start Time',
                          hintText: '7:45 PM',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          config.startTime = value;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: config.endTimeController,
                        decoration: const InputDecoration(
                          labelText: 'End Time',
                          hintText: '9:15 PM',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          config.endTime = value;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Teams
                const Text(
                  'Teams in Group',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (config.teamKeys.isEmpty)
                  const Text(
                    'No teams assigned yet',
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  )
                else
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final teamKey = config.teamKeys.removeAt(oldIndex);
                        config.teamKeys.insert(newIndex, teamKey);
                      });
                    },
                    children: config.teamKeys.asMap().entries.map((entry) {
                      final index = entry.key;
                      final teamKey = entry.value;
                      final team = _approvedTeams.firstWhere(
                        (t) => t['key'] == teamKey,
                        orElse: () => {'name': 'Unknown Team'},
                      );
                      return ListTile(
                        key: ValueKey(teamKey),
                        dense: true,
                        leading: const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                        title: Text(team['name'] as String),
                        subtitle: Text('Position ${index + 1}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.swap_vert, size: 20, color: Colors.blue),
                              onPressed: () => _showSwapTeamDialog(groupName, config, index),
                              tooltip: 'Swap/Edit Team',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  config.teamKeys.remove(teamKey);
                                });
                              },
                              tooltip: 'Remove Team',
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _showAddTeamDialog(groupName, config),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Team'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _saveConfiguration,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      child: const Text('💾 Save Phase 1 Configuration'),
    );
  }

  Future<void> _showAddTeamDialog(String groupName, Phase1GroupConfig config) async {
    // Get available teams (not already assigned to this group or others)
    final assignedTeams = <String>{};
    _groupConfigs.forEach((_, c) {
      assignedTeams.addAll(c.teamKeys);
    });

    final availableTeams = _approvedTeams.where((team) {
      return !assignedTeams.contains(team['key']);
    }).toList();

    if (availableTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No more teams available to add'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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
              final team = availableTeams[index];
              return ListTile(
                leading: const Icon(Icons.people),
                title: Text(team['name'] as String),
                onTap: () {
                  setState(() {
                    config.teamKeys.add(team['key'] as String);
                  });
                  Navigator.pop(context);
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

  Future<void> _showSwapTeamDialog(String groupName, Phase1GroupConfig config, int currentIndex) async {
    final currentTeamKey = config.teamKeys[currentIndex];
    final currentTeam = _approvedTeams.firstWhere(
      (t) => t['key'] == currentTeamKey,
      orElse: () => {'name': 'Unknown Team'},
    );

    // Get all available teams (including the current one)
    final assignedTeams = <String>{};
    _groupConfigs.forEach((_, c) {
      assignedTeams.addAll(c.teamKeys);
    });
    // Remove current team from assigned list so it can be swapped
    assignedTeams.remove(currentTeamKey);

    final availableTeams = _approvedTeams.where((team) {
      return !assignedTeams.contains(team['key']) || team['key'] == currentTeamKey;
    }).toList();

    if (availableTeams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No teams available to swap'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Team in $groupName'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Current: ${currentTeam['name']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Select replacement team:'),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: availableTeams.length,
                  itemBuilder: (context, index) {
                    final team = availableTeams[index];
                    final isCurrent = team['key'] == currentTeamKey;
                    return ListTile(
                      leading: Icon(
                        isCurrent ? Icons.check_circle : Icons.people,
                        color: isCurrent ? Colors.green : null,
                      ),
                      title: Text(team['name'] as String),
                      subtitle: isCurrent ? const Text('Current team') : null,
                      onTap: isCurrent
                          ? null
                          : () {
                              setState(() {
                                config.teamKeys[currentIndex] = team['key'] as String;
                              });
                              Navigator.pop(context);
                            },
                    );
                  },
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
        ],
      ),
    );
  }

  Future<void> _showEditGroupNameDialog(String currentName, Phase1GroupConfig config) async {
    final nameController = TextEditingController(text: currentName);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            hintText: 'e.g., Group 1',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      final newName = nameController.text.trim();
      if (newName != currentName) {
        // Update group name in config map
        final oldConfig = _groupConfigs[currentName];
        if (oldConfig != null) {
          _groupConfigs.remove(currentName);
          _groupConfigs[newName] = oldConfig;
          setState(() {});
        }
      }
    }
  }

  Future<void> _saveConfiguration() async {
    setState(() {
      _loading = true;
    });

    try {
      // Build Phase 1 data structure
      final phase1Data = {
        'name': 'Initial Groups',
        'groups': _groupConfigs.map((groupName, config) {
          return MapEntry(groupName, {
            'teamKeys': config.teamKeys,
            'schedule': {
              'court': config.court,
              'startTime': config.startTime,
              'endTime': config.endTime,
            },
            'orderOfPlay': [
              'Team 1 vs Team 2',
              'Team 2 vs Team 3',
              'Team 1 vs Team 3',
            ],
          });
        }),
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'phase1': phase1Data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Phase 1 configuration saved successfully!'),
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

/// Configuration class for Phase 1 group
class Phase1GroupConfig {
  List<String> teamKeys = [];
  String court = '';
  String startTime = '';
  String endTime = '';

  final TextEditingController courtController = TextEditingController();
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();

  void loadFromFirestore(Map<String, dynamic> data) {
    teamKeys = (data['teamKeys'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    
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
}
