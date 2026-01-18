import 'package:flutter/material.dart';
import 'home_screen.dart';

class BookingPageScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? selectedVenue;

  const BookingPageScreen({
    super.key,
    this.initialDate,
    this.selectedVenue,
  });

  @override
  State<BookingPageScreen> createState() => _BookingPageScreenState();
}

class _BookingPageScreenState extends State<BookingPageScreen> {
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.initialDate ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text('Book Session'),
        backgroundColor: const Color(0xFF0A0E27),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: HomeScreen(
        initialDate: selectedDate,
        initialVenue: widget.selectedVenue,
      ),
    );
  }
}
