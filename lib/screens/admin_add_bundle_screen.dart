import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/bundle_service.dart';
import '../services/notification_service.dart';

/// Admin-only screen to create a training bundle on behalf of a user.
class AdminAddBundleScreen extends StatefulWidget {
  const AdminAddBundleScreen({super.key});

  @override
  State<AdminAddBundleScreen> createState() => _AdminAddBundleScreenState();
}

class _AdminAddBundleScreenState extends State<AdminAddBundleScreen> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final _expirationController = TextEditingController(text: '60');

  List<Map<String, dynamic>> _userMatches = [];
  bool _searching = false;
  String? _selectedUserId;
  String? _selectedUserName;
  String? _selectedUserPhone;

  int _bundleType = 4; // 1, 4, or 8 sessions
  int _playerCount = 1; // 1-4
  bool _isPrivate = false; // when true, booking takes all 4 slots
  bool _approveAndActivate = true;
  bool _markPaid = false;
  bool _submitting = false;

  // Schedule (venue, coach, date & time)
  List<Map<String, dynamic>> _slots = [];
  bool _slotsLoaded = false;
  String? _selectedVenue;
  String? _selectedTime;
  String? _selectedCoach;
  DateTime _scheduleDate = DateTime.now();
  bool _isRecurring = false;
  final List<String> _recurringDays = [];

  static const List<String> _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    _expirationController.dispose();
    super.dispose();
  }

  Future<void> _loadSlots() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('slots').get();
      final list = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final venue = d['venue'] as String? ?? '';
        final time = d['time'] as String? ?? '';
        final coach = d['coach'] as String? ?? '';
        if (venue.isNotEmpty) {
          list.add({'venue': venue, 'time': time, 'coach': coach});
        }
      }
      if (mounted) {
        setState(() {
          _slots = list;
          _slotsLoaded = true;
          if (_slots.isNotEmpty && _selectedVenue == null) {
            final venues = _slots.map((e) => e['venue'] as String).toSet().toList()..sort();
            _selectedVenue = venues.first;
            _updateTimeAndCoachFromSlot();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _slotsLoaded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load slots: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _updateTimeAndCoachFromSlot() {
    final forVenue = _slots.where((s) => s['venue'] == _selectedVenue).toList();
    if (forVenue.isNotEmpty) {
      if (_selectedTime == null) _selectedTime = forVenue.first['time'] as String?;
      final forTime = forVenue.where((s) => s['time'] == _selectedTime).toList();
      _selectedCoach = forTime.isNotEmpty ? forTime.first['coach'] as String? : forVenue.first['coach'] as String?;
    }
  }

  Future<void> _searchUsers() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() {
        _userMatches = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(100)
          .get();
      final matches = <Map<String, dynamic>>[];
      final qLower = q.toLowerCase();
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final uid = doc.id;
        final first = d['firstName'] as String? ?? '';
        final last = d['lastName'] as String? ?? '';
        final full = d['fullName'] as String? ?? '';
        final phone = (d['phone'] as String? ?? '').replaceAll(RegExp(r'\s'), '');
        final name = full.trim().isNotEmpty
            ? full
            : '$first $last'.trim().isEmpty
                ? phone
                : '$first $last'.trim();
        final searchable =
            '${name.toLowerCase()} ${phone.replaceAll(RegExp(r'[\s\-]'), '')}';
        if (name.toLowerCase().contains(qLower) ||
            phone.contains(q) ||
            searchable.contains(qLower)) {
          matches.add({
            'userId': uid,
            'name': name.isEmpty ? 'No name' : name,
            'phone': phone.isEmpty ? 'No phone' : phone,
          });
        }
      }
      if (mounted) {
        setState(() {
          _userMatches = matches;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedUserId == null ||
        _selectedUserName == null ||
        _selectedUserPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a user'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    int expirationDays = 60;
    if (_approveAndActivate) {
      expirationDays = int.tryParse(_expirationController.text.trim()) ?? 60;
      if (expirationDays < 1 || expirationDays > 365) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expiration days must be between 1 and 365'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    final startDateStr = '${_scheduleDate.year}-${_scheduleDate.month.toString().padLeft(2, '0')}-${_scheduleDate.day.toString().padLeft(2, '0')}';
    final scheduleDetails = <String, dynamic>{
      'venue': _selectedVenue ?? '',
      'coach': _selectedCoach ?? '',
      'startDate': startDateStr,
      'time': _selectedTime ?? '',
      'isRecurring': _isRecurring,
      'isPrivate': _isPrivate,
      if (_isRecurring && _recurringDays.isNotEmpty) 'recurringDays': _recurringDays,
    };

    setState(() => _submitting = true);
    try {
      await BundleService().createBundleForUserAdmin(
        userId: _selectedUserId!,
        userName: _selectedUserName!,
        userPhone: _selectedUserPhone!,
        bundleType: _bundleType,
        playerCount: _playerCount,
        notes: _notesController.text.trim(),
        approveAndActivate: _approveAndActivate,
        markPaid: _markPaid,
        expirationDays: expirationDays,
        scheduleDetails: scheduleDetails,
      );

      if (mounted && _selectedUserId != null) {
        final scheduleInfo = _selectedVenue != null && _selectedVenue!.isNotEmpty
            ? ' at $_selectedVenue${_selectedTime != null && _selectedTime!.isNotEmpty ? " on $startDateStr at $_selectedTime" : ""}.'
            : '.';
        await NotificationService().notifyUserCreatedOnBehalf(
          userId: _selectedUserId!,
          title: 'Bundle added for you',
          body: 'A training bundle of $_bundleType session${_bundleType > 1 ? 's' : ''} was added for you$scheduleInfo',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bundle created successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating bundle: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add bundle for user'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Find user (by name or phone)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Name or phone...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _searchUsers(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searching ? null : _searchUsers,
                  child: _searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Search'),
                ),
              ],
            ),
            if (_userMatches.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._userMatches.take(10).map((u) {
                final isSelected = _selectedUserId == u['userId'];
                return ListTile(
                  title: Text(u['name'] as String? ?? ''),
                  subtitle: Text(u['phone'] as String? ?? ''),
                  selected: isSelected,
                  onTap: () {
                    setState(() {
                      _selectedUserId = u['userId'] as String?;
                      _selectedUserName = u['name'] as String?;
                      _selectedUserPhone = u['phone'] as String?;
                    });
                  },
                );
              }),
            ],
            if (_selectedUserId != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bundle for: $_selectedUserName ($_selectedUserPhone)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _selectedUserId = null;
                          _selectedUserName = null;
                          _selectedUserPhone = null;
                        }),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              '2. Bundle details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _bundleType,
              decoration: const InputDecoration(
                labelText: 'Sessions',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 session')),
                DropdownMenuItem(value: 4, child: Text('4 sessions')),
                DropdownMenuItem(value: 8, child: Text('8 sessions')),
              ],
              onChanged: (v) => setState(() => _bundleType = v ?? 4),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _playerCount,
              decoration: const InputDecoration(
                labelText: 'Players',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 player')),
                DropdownMenuItem(value: 2, child: Text('2 players')),
                DropdownMenuItem(value: 3, child: Text('3 players')),
                DropdownMenuItem(value: 4, child: Text('4 players')),
              ],
              onChanged: (v) => setState(() => _playerCount = v ?? 1),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _isPrivate,
              onChanged: (v) => setState(() => _isPrivate = v ?? false),
              title: const Text('Private'),
              subtitle: const Text('Takes all 4 slots (full court)'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            const Text(
              '3. Schedule (venue, coach, date & time)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (!_slotsLoaded)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (_slots.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('No slots configured. Add slots in Admin > Slots.'),
              )
            else ...[
              DropdownButtonFormField<String>(
                value: _selectedVenue,
                decoration: const InputDecoration(
                  labelText: 'Venue',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: () {
                  final venues = _slots.map((e) => e['venue'] as String).toSet().toList()..sort();
                  return venues.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList();
                }(),
                onChanged: (v) => setState(() {
                  _selectedVenue = v;
                  _updateTimeAndCoachFromSlot();
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedTime,
                decoration: const InputDecoration(
                  labelText: 'Time',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: () {
                  final times = _slots
                      .where((s) => s['venue'] == _selectedVenue)
                      .map((s) => s['time'] as String)
                      .toSet()
                      .toList()..sort();
                  return times.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList();
                }(),
                onChanged: (v) => setState(() {
                  _selectedTime = v;
                  final forVenue = _slots.where((s) => s['venue'] == _selectedVenue).toList();
                  final forTime = forVenue.where((s) => s['time'] == v).toList();
                  _selectedCoach = forTime.isNotEmpty ? forTime.first['coach'] as String? : _selectedCoach;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedCoach,
                decoration: const InputDecoration(
                  labelText: 'Coach',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _slots
                    .where((s) => s['venue'] == _selectedVenue && s['time'] == _selectedTime)
                    .map((s) => s['coach'] as String)
                    .toSet()
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCoach = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start date'),
                subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_scheduleDate)),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _scheduleDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _scheduleDate = picked);
                  },
                  child: const Text('Pick date'),
                ),
              ),
              if (_bundleType > 1) ...[
                CheckboxListTile(
                  value: _isRecurring,
                  onChanged: (v) => setState(() => _isRecurring = v ?? false),
                  title: const Text('Recurring (same time each week)'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (_isRecurring)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _dayNames.map((day) {
                      final selected = _recurringDays.contains(day);
                      return FilterChip(
                        label: Text(day),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) _recurringDays.add(day);
                            else _recurringDays.remove(day);
                          });
                        },
                      );
                    }).toList(),
                  ),
                if (_isRecurring) const SizedBox(height: 8),
              ],
            ],
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _approveAndActivate,
              onChanged: (v) => setState(() => _approveAndActivate = v ?? true),
              title: const Text('Approve and activate immediately'),
              subtitle: const Text(
                'Bundle will be active; user can book sessions from it',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_approveAndActivate) ...[
              Padding(
                padding: const EdgeInsets.only(left: 48, right: 16),
                child: TextField(
                  controller: _expirationController,
                  decoration: const InputDecoration(
                    labelText: 'Expiration (days)',
                    hintText: '60',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(height: 8),
            ],
            CheckboxListTile(
              value: _markPaid,
              onChanged: (v) => setState(() => _markPaid = v ?? false),
              title: const Text('Mark payment received'),
              subtitle: const Text('Set payment status to Paid'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create bundle for user'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
