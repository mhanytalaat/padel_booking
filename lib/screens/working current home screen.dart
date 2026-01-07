import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? selectedDate;
  Set<String> bookedSlots = {};

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  // Load bookings from local storage
  Future<void> _loadBookings() async {
    final prefs = await SharedPreferences.getInstance();
    final bookingsJson = prefs.getString('bookings');
    if (bookingsJson != null) {
      final List<dynamic> bookings = json.decode(bookingsJson);
      setState(() {
        bookedSlots = bookings.map((e) => e.toString()).toSet();
      });
    }
  }

  // Save bookings to local storage
  Future<void> _saveBookings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bookings', json.encode(bookedSlots.toList()));
  }

  // Generate unique key for a booking slot
  String _getBookingKey(String venue, String time, DateTime date) {
    final dateStr = '${date.year}-${date.month}-${date.day}';
    return '$dateStr|$venue|$time';
  }

  // Check if a slot is booked
  bool _isSlotBooked(String venue, String time) {
    if (selectedDate == null) return false;
    final key = _getBookingKey(venue, time, selectedDate!);
    return bookedSlots.contains(key);
  }

  // Show confirmation dialog
  Future<void> _showBookingConfirmation(
      String venue, String time, String coach) async {
    if (selectedDate == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Venue: $venue'),
              const SizedBox(height: 8),
              Text('Date: ${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'),
              const SizedBox(height: 8),
              Text('Time: $time'),
              const SizedBox(height: 8),
              Text('Coach: $coach'),
              const SizedBox(height: 16),
              const Text('Are you sure you want to book this slot?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final key = _getBookingKey(venue, time, selectedDate!);
      setState(() {
        bookedSlots.add(key);
      });
      await _saveBookings();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking confirmed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 34,
            ),
            const SizedBox(width: 10),
            const Text("PadelCore"),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _dateSelector(),
          if (selectedDate != null) ...[
            const SizedBox(height: 20),
            buildVenue(
              "Club13 Sheikh Zayed",
              [
                {"time": "6:00 PM", "coach": "Coach Ahmed"},
                {"time": "7:00 PM", "coach": "Coach Omar"},
              ],
            ),
            const SizedBox(height: 24),
            buildVenue(
              "Padel Avenue 360 Mall",
              [
                {"time": "5:00 PM", "coach": "Coach Karim"},
                {"time": "8:00 PM", "coach": "Coach Adam"},
              ],
            ),
          ] else ...[
            const SizedBox(height: 40),
            Center(
              child: Text(
                'Please select a date to view available venues',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // DATE PICKER
  Widget _dateSelector() {
    return GestureDetector(
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          setState(() {
            selectedDate = picked;
          });
          _loadBookings();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selectedDate != null
                  ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                  : 'Select a date',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: selectedDate != null ? Colors.black : Colors.grey[600],
              ),
            ),
            const Icon(Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  // VENUE BUILDER
  Widget buildVenue(String venueName, List<Map<String, String>> timeSlots) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              venueName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...timeSlots.map((slot) {
              final time = slot['time'] ?? '';
              final coach = slot['coach'] ?? '';
              final isBooked = _isSlotBooked(venueName, time);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isBooked ? Colors.grey[200] : Colors.white,
                    border: Border.all(
                      color: isBooked ? Colors.grey[400]! : Colors.grey[300]!,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: isBooked ? Colors.grey[600] : Colors.black,
                                decoration: isBooked
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              coach,
                              style: TextStyle(
                                fontSize: 14,
                                color: isBooked ? Colors.grey[500] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isBooked)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Booked',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.red,
                            ),
                          ),
                        )
                      else
                        ElevatedButton(
                          onPressed: () => _showBookingConfirmation(
                            venueName,
                            time,
                            coach,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          child: const Text('Book'),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
