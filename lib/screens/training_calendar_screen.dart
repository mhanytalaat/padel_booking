import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

class TrainingCalendarScreen extends StatefulWidget {
  const TrainingCalendarScreen({super.key});

  @override
  State<TrainingCalendarScreen> createState() => _TrainingCalendarScreenState();
}

class _TrainingCalendarScreenState extends State<TrainingCalendarScreen> {
  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDate;
  List<DateTime> _datesWithBookings = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadBookingsForMonth();
  }

  String _getDayName(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  Future<void> _loadBookingsForMonth() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Get first and last day of month
      final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

      // Query all approved bookings for this user
      final snapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'approved')
          .get();

      // Filter by month and collect unique dates
      final Set<DateTime> uniqueDates = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final isRecurring = data['isRecurring'] as bool? ?? false;
        
        if (isRecurring) {
          // Handle recurring bookings
          final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
          
          if (recurringDays.isNotEmpty) {
            // Add all dates in this month that match the recurring days
            for (int day = 1; day <= lastDay.day; day++) {
              final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
              final dayName = _getDayName(date);
              
              if (recurringDays.contains(dayName)) {
                // Make sure it's not before the booking start date
                final dateStr = data['date'] as String?;
                if (dateStr != null) {
                  try {
                    final parts = dateStr.split('-');
                    if (parts.length == 3) {
                      final startDate = DateTime(
                        int.parse(parts[0]),
                        int.parse(parts[1]),
                        int.parse(parts[2]),
                      );
                      // Only add if date is on or after start date
                      if (!date.isBefore(startDate)) {
                        uniqueDates.add(date);
                      }
                    }
                  } catch (e) {
                    // If we can't parse start date, add it anyway
                    uniqueDates.add(date);
                  }
                }
              }
            }
          }
        } else {
          // Handle one-time bookings
          final dateStr = data['date'] as String?;
          if (dateStr != null) {
            try {
              final parts = dateStr.split('-');
              if (parts.length == 3) {
                final date = DateTime(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                );
                if (date.isAfter(firstDay.subtract(const Duration(days: 1))) &&
                    date.isBefore(lastDay.add(const Duration(days: 1)))) {
                  uniqueDates.add(date);
                }
              }
            } catch (e) {
              // Skip invalid dates
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _datesWithBookings = uniqueDates.toList()..sort();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading calendar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildCalendar() {
    final firstDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDayOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final daysInMonth = lastDayOfMonth.day;
    final firstWeekday = firstDayOfMonth.weekday; // 1 = Monday, 7 = Sunday

    return Column(
      children: [
        // Month/Year Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                  });
                  _loadBookingsForMonth();
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedMonth),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                  });
                  _loadBookingsForMonth();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Day Labels
        Row(
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        // Calendar Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
          ),
          itemCount: daysInMonth + (firstWeekday - 1),
          itemBuilder: (context, index) {
            // Empty cells before first day
            if (index < firstWeekday - 1) {
              return const SizedBox();
            }

            final day = index - (firstWeekday - 1) + 1;
            final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
            final isToday = DateTime.now().year == date.year &&
                DateTime.now().month == date.month &&
                DateTime.now().day == date.day;
            final isSelected = _selectedDate != null &&
                _selectedDate!.year == date.year &&
                _selectedDate!.month == date.month &&
                _selectedDate!.day == date.day;
            final hasBooking = _datesWithBookings.any((d) =>
                d.year == date.year && d.month == date.month && d.day == date.day);

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDate = date;
                });
              },
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1E3A8A)
                      : isToday
                          ? Colors.orange.withOpacity(0.3)
                          : Colors.transparent,
                  border: Border.all(
                    color: isToday ? Colors.orange : Colors.grey.shade300,
                    width: isToday ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    if (hasBooking)
                      Positioned(
                        bottom: 4,
                        right: 0,
                        left: 0,
                        child: Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : const Color(0xFF1E3A8A),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBookingsList() {
    if (_selectedDate == null) {
      return const Center(
        child: Text('Select a date to view bookings'),
      );
    }

    final dateStr =
        '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}';
    final selectedDayName = _getDayName(_selectedDate!);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('No bookings'));
        }

        // Filter bookings to show only those that apply to the selected date
        final bookingsForDate = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bookingDateStr = data['date'] as String?;
          final isRecurring = data['isRecurring'] as bool? ?? false;
          
          if (isRecurring) {
            // For recurring bookings, check if selected day matches recurringDays
            final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
            if (recurringDays.contains(selectedDayName)) {
              // Also check if selected date is on or after booking start date
              if (bookingDateStr != null) {
                try {
                  final parts = bookingDateStr.split('-');
                  if (parts.length == 3) {
                    final startDate = DateTime(
                      int.parse(parts[0]),
                      int.parse(parts[1]),
                      int.parse(parts[2]),
                    );
                    return !_selectedDate!.isBefore(startDate);
                  }
                } catch (e) {
                  return true; // If we can't parse, include it
                }
              }
              return true;
            }
            return false;
          } else {
            // For one-time bookings, check exact date match
            return bookingDateStr == dateStr;
          }
        }).toList();

        if (bookingsForDate.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'No bookings on ${DateFormat('MMM d, yyyy').format(_selectedDate!)}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bookingsForDate.length,
          itemBuilder: (context, index) {
            final doc = bookingsForDate[index];
            final data = doc.data() as Map<String, dynamic>;
            final venue = data['venue'] as String? ?? 'Unknown Venue';
            final time = data['time'] as String? ?? 'Unknown Time';
            final coach = data['coach'] as String? ?? 'No Coach';
            final bookingType = data['bookingType'] as String? ?? 'Group';
            final isRecurring = data['isRecurring'] as bool? ?? false;
            final recurringDays = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF1E3A8A),
                  child: Icon(
                    bookingType == 'Private' ? Icons.lock : Icons.group,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  venue,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(time),
                      ],
                    ),
                    if (coach.isNotEmpty && coach != 'No Coach') ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.sports_tennis, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(coach),
                        ],
                      ),
                    ],
                    if (isRecurring && recurringDays.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat, size: 12, color: Colors.blue[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Every ${recurringDays.join(', ')}',
                              style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: bookingType == 'Private' ? Colors.purple : Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        bookingType,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    if (isRecurring) ...[
                      const SizedBox(height: 4),
                      const Icon(Icons.repeat, size: 16, color: Colors.orange),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppHeader(title: 'Training Calendar'),
      bottomNavigationBar: const AppFooter(selectedIndex: 1),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCalendar(),
                  const SizedBox(height: 24),
                  if (_selectedDate != null) ...[
                    Text(
                      'Bookings on ${DateFormat('EEEE, MMM d, yyyy').format(_selectedDate!)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildBookingsList(),
                  ],
                ],
              ),
            ),
    );
  }
}
