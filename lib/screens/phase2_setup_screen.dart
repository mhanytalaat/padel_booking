import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Phase 2 Setup Screen for configuring Groups A-D
/// with winner/runner-up mappings and seeded teams
class Phase2SetupScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;

  const Phase2SetupScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
  });

  @override
  State<Phase2SetupScreen> createState() => _Phase2SetupScreenState();
}

class _Phase2SetupScreenState extends State<Phase2SetupScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _approvedTeams = [];
  
  // Phase 2 configuration based on PDF structure
  final Map<String, Phase2GroupConfig> _groupConfigs = {
    'Group A': Phase2GroupConfig(
      slot1Type: 'winner',
      slot1From: 'Group 1',
      slot2Type: 'runnerUp',
      slot2From: 'Group 4',
    ),
    'Group B': Phase2GroupConfig(
      slot1Type: 'winner',
      slot1From: 'Group 2',
      slot2Type: 'runnerUp',
      slot2From: 'Group 3',
    ),
    'Group C': Phase2GroupConfig(
      slot1Type: 'winner',
      slot1From: 'Group 3',
      slot2Type: 'runnerUp',
      slot2From: 'Group 1',
    ),
    'Group D': Phase2GroupConfig(
      slot1Type: 'winner',
      slot1From: 'Group 4',
      slot2Type: 'runnerUp',
      slot2From: 'Group 2',
    ),
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
        final phase2 = data['phase2'] as Map<String, dynamic>?;
        
        if (phase2 != null) {
          final groups = phase2['groups'] as Map<String, dynamic>?;
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
        title: Text('Phase 2 Setup - ${widget.tournamentName}'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  color: Color(0xFFE8F5E9),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📍 PHASE 2 - Advanced Groups',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Configure Groups A-D. Each group has:\n• Winner from Phase 1 group\n• Runner-up from Phase 1 group\n• Seeded/Pre-qualified team',
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

  Widget _buildGroupCard(String groupName, Phase2GroupConfig config) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: CircleAvatar(
          backgroundColor: Colors.green,
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
        subtitle: Text('${config.court} | ${config.startTime}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Team Slot 1: Winner from Phase 1
                _buildTeamSlot(
                  slotNumber: 1,
                  type: config.slot1Type,
                  from: config.slot1From,
                  teamKey: config.slot1TeamKey,
                ),
                const Divider(height: 32),
                
                // Team Slot 2: Runner-up from Phase 1
                _buildTeamSlot(
                  slotNumber: 2,
                  type: config.slot2Type,
                  from: config.slot2From,
                  teamKey: config.slot2TeamKey,
                ),
                const Divider(height: 32),
                
                // Team Slot 3: Seeded team
                _buildSeededTeamSlot(groupName, config),
                
                const Divider(height: 32),
                
                // Court and Time
                const Text(
                  'Court & Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: config.courtController,
                  decoration: const InputDecoration(
                    labelText: 'Court',
                    hintText: 'e.g., Court 2',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    config.court = value;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: config.startTimeController,
                        decoration: const InputDecoration(
                          labelText: 'Start Time',
                          hintText: '9:20 PM',
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
                          hintText: '10:45 PM',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          config.endTime = value;
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

  Widget _buildTeamSlot({
    required int slotNumber,
    required String type,
    required String from,
    String? teamKey,
  }) {
    final isWinner = type == 'winner';
    final displayType = isWinner ? 'Winner' : 'Runner-up';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isWinner ? Colors.amber : Colors.green,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$slotNumber',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
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
                    'Team Slot $slotNumber',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$displayType of $from',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            children: [
              Icon(
                isWinner ? Icons.emoji_events : Icons.military_tech,
                color: isWinner ? Colors.amber : Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  teamKey != null ? 'Team assigned ✓' : 'Will be auto-filled after Phase 1',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: teamKey != null ? Colors.green : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeededTeamSlot(String groupName, Phase2GroupConfig config) {
    // Default seeded team names based on PDF
    final Map<String, String> defaultSeededTeams = {
      'Group A': 'Ziad Rizk / Seif',
      'Group B': 'Nabil / Abu',
      'Group C': 'Mostafa W / Yassin',
      'Group D': 'Karim Alaa / Seif',
    };

    if (config.seededTeamName.isEmpty && config.seededTeamKey == null) {
      config.seededTeamName = defaultSeededTeams[groupName] ?? '';
      config.seededTeamController.text = config.seededTeamName;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.purple,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  '3',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team Slot 3',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Seeded / Pre-qualified Team',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Option to select from registered users
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showSelectSeededTeamDialog(groupName, config),
                icon: const Icon(Icons.people, size: 16),
                label: const Text('Select from Users'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'OR enter manually:',
          style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: config.seededTeamController,
          decoration: const InputDecoration(
            labelText: 'Seeded Team Name',
            hintText: 'e.g., Ziad Rizk / Seif',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.star, color: Colors.purple),
          ),
          onChanged: (value) {
            config.seededTeamName = value;
            config.seededTeamKey = null; // Clear selection if manually typed
          },
        ),
        const SizedBox(height: 4),
        Text(
          config.seededTeamKey != null 
              ? '✓ Selected from registered users'
              : 'Manual entry (team may not be registered)',
          style: TextStyle(
            fontSize: 11,
            color: config.seededTeamKey != null ? Colors.green : Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
  
  Future<void> _showSelectSeededTeamDialog(String groupName, Phase2GroupConfig config) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Seeded Team for $groupName'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _approvedTeams.isEmpty
              ? const Center(child: Text('No approved teams available'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _approvedTeams.length,
                  itemBuilder: (context, index) {
                    final team = _approvedTeams[index];
                    return ListTile(
                      leading: const Icon(Icons.people, color: Colors.purple),
                      title: Text(team['name'] as String),
                      onTap: () {
                        setState(() {
                          config.seededTeamKey = team['key'] as String;
                          config.seededTeamName = team['name'] as String;
                          config.seededTeamController.text = config.seededTeamName;
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

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _saveConfiguration,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      child: const Text('💾 Save Phase 2 Configuration'),
    );
  }

  Future<void> _showEditGroupNameDialog(String currentName, Phase2GroupConfig config) async {
    final nameController = TextEditingController(text: currentName);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Group Name',
            hintText: 'e.g., Group A',
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
      // Build Phase 2 data structure
      final phase2Data = {
        'name': 'Advanced Groups',
        'groups': _groupConfigs.map((groupName, config) {
          return MapEntry(groupName, {
            'teamSlots': [
              {
                'type': config.slot1Type,
                'from': config.slot1From,
                'teamKey': config.slot1TeamKey,
              },
              {
                'type': config.slot2Type,
                'from': config.slot2From,
                'teamKey': config.slot2TeamKey,
              },
              {
                'type': 'seeded',
                'name': config.seededTeamName,
                'teamKey': config.seededTeamKey ?? 'seeded_${groupName.replaceAll(' ', '_').toLowerCase()}',
                'isRegisteredUser': config.seededTeamKey != null,
              },
            ],
            'schedule': {
              'court': config.court,
              'startTime': config.startTime,
              'endTime': config.endTime,
            },
          });
        }),
      };

      await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.tournamentId)
          .update({
        'phase2': phase2Data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Phase 2 configuration saved successfully!'),
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

/// Configuration class for Phase 2 group
class Phase2GroupConfig {
  // Team Slot 1
  String slot1Type;
  String slot1From;
  String? slot1TeamKey;

  // Team Slot 2
  String slot2Type;
  String slot2From;
  String? slot2TeamKey;

  // Team Slot 3 (Seeded)
  String seededTeamName = '';
  String? seededTeamKey; // NEW: Can be selected from registered users

  // Schedule
  String court = '';
  String startTime = '';
  String endTime = '';

  final TextEditingController courtController = TextEditingController();
  final TextEditingController startTimeController = TextEditingController();
  final TextEditingController endTimeController = TextEditingController();
  final TextEditingController seededTeamController = TextEditingController();

  Phase2GroupConfig({
    required this.slot1Type,
    required this.slot1From,
    required this.slot2Type,
    required this.slot2From,
  });

  void loadFromFirestore(Map<String, dynamic> data) {
    final teamSlots = data['teamSlots'] as List<dynamic>?;
    if (teamSlots != null && teamSlots.length >= 3) {
      final slot1 = teamSlots[0] as Map<String, dynamic>;
      final slot2 = teamSlots[1] as Map<String, dynamic>;
      final slot3 = teamSlots[2] as Map<String, dynamic>;

      slot1Type = slot1['type'] as String? ?? slot1Type;
      slot1From = slot1['from'] as String? ?? slot1From;
      slot1TeamKey = slot1['teamKey'] as String?;

      slot2Type = slot2['type'] as String? ?? slot2Type;
      slot2From = slot2['from'] as String? ?? slot2From;
      slot2TeamKey = slot2['teamKey'] as String?;

      seededTeamName = slot3['name'] as String? ?? '';
      seededTeamKey = slot3['teamKey'] as String?; // Load seeded team key
      seededTeamController.text = seededTeamName;
    }
    
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
