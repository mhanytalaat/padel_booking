import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/bundle_service.dart';

/// Admin-only screen to book a training slot on behalf of a user (by name or phone).
class AdminBookTrainingScreen extends StatefulWidget {
  const AdminBookTrainingScreen({super.key});

  @override
  State<AdminBookTrainingScreen> createState() => _AdminBookTrainingScreenState();
}

class _AdminBookTrainingScreenState extends State<AdminBookTrainingScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  List<Map<String, dynamic>> _userMatches = [];
  bool _searching = false;
  String? _selectedUserId;
  String? _selectedUserName;
  String? _selectedUserPhone;

  List<Map<String, dynamic>> _slots = [];
  bool _slotsLoaded = false;
  String? _selectedVenue;
  String? _selectedTime;
  String? _selectedCoach;
  DateTime _selectedDate = DateTime.now();
  bool _isRecurring = false;
  final List<String> _recurringDays = [];
  bool _submitting = false;

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
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSlots() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('slots').get();
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
          }
          _updateTimeAndCoachFromSlot();
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
    if (forVenue.isNotEmpty && (_selectedTime == null || _selectedCoach == null)) {
      _selectedTime ??= forVenue.first['time'] as String?;
      final forTime = forVenue.where((s) => s['time'] == _selectedTime!).toList();
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
        final searchable = '${name.toLowerCase()} ${phone.replaceAll(RegExp(r'[\s\-]'), '')}';
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
          SnackBar(content: Text('Search failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _submitBooking() async {
    if (_selectedUserId == null || _selectedUserPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a user'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedVenue == null || _selectedTime == null || _selectedCoach == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select venue, time and coach'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_isRecurring && _recurringDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one day for recurring'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final dateStr =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final dayName = DateFormat('EEEE').format(_selectedDate);

      final bookingData = <String, dynamic>{
        'userId': _selectedUserId,
        'phone': _selectedUserPhone,
        'venue': _selectedVenue,
        'time': _selectedTime,
        'coach': _selectedCoach,
        'date': dateStr,
        'bookingType': 'Bundle',
        'isPrivate': false,
        'isRecurring': _isRecurring,
        'status': 'approved',
        'timestamp': FieldValue.serverTimestamp(),
        'slotsReserved': 1,
      };
      if (_isRecurring) {
        bookingData['recurringDays'] = _recurringDays;
        bookingData['dayOfWeek'] = dayName;
      }

      final bookingRef = await FirebaseFirestore.instance.collection('bookings').add(bookingData);

      // Link one-time (non-recurring) booking to a 1-session bundle so it appears in Training Bundles (payment, notes, attendance)
      if (!_isRecurring && _selectedUserId != null && _selectedUserName != null && _selectedUserPhone != null) {
        final bundleId = await BundleService().createOneTimeBundleForBooking(
          bookingId: bookingRef.id,
          userId: _selectedUserId!,
          userName: _selectedUserName!,
          userPhone: _selectedUserPhone!,
          date: dateStr,
          time: _selectedTime!,
          venue: _selectedVenue!,
          coach: _selectedCoach!,
          playerCount: 1,
          approveAndActivate: true,
          expirationDays: 60,
        );
        await bookingRef.update({'bundleId': bundleId, 'isBundle': true});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking created successfully (on behalf of user)'),
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
            content: Text('Error creating booking: $e'),
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
        title: const Text('Book training for user'),
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
                    focusNode: _searchFocus,
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
                          'Booking for: $_selectedUserName ($_selectedUserPhone)',
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
              '2. Select slot and date',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (!_slotsLoaded)
              const Center(child: CircularProgressIndicator())
            else if (_slots.isEmpty)
              const Text('No slots configured. Add slots in Admin > Slots.')
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
                    .where((s) =>
                        s['venue'] == _selectedVenue && s['time'] == _selectedTime)
                    .map((s) => s['coach'] as String)
                    .toSet()
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCoach = v),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate)),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                  child: const Text('Pick date'),
                ),
              ),
              CheckboxListTile(
                value: _isRecurring,
                onChanged: (v) => setState(() => _isRecurring = v ?? false),
                title: const Text('Recurring (same slot every week)'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_isRecurring) ...[
                Wrap(
                  spacing: 8,
                  children: _dayNames.map((day) {
                    final selected = _recurringDays.contains(day);
                    return FilterChip(
                      label: Text(day),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _recurringDays.add(day);
                          } else {
                            _recurringDays.remove(day);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitBooking,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create booking (on behalf of user)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
