import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'court_booking_confirmation_screen.dart';

class CourtBookingScreen extends StatefulWidget {
  final String locationId;

  const CourtBookingScreen({
    super.key,
    required this.locationId,
  });

  @override
  State<CourtBookingScreen> createState() => _CourtBookingScreenState();
}

class _CourtBookingScreenState extends State<CourtBookingScreen> {
  DateTime _selectedDate = DateTime.now();
  final Map<String, List<String>> _selectedSlots = {}; // courtId -> [time slots]
  String? _locationName;
  String? _locationAddress;
  Map<String, dynamic>? _locationData;

  @override
  void initState() {
    super.initState();
    _loadLocationData();
  }

  Future<void> _loadLocationData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('courtLocations')
          .doc(widget.locationId)
          .get();
      
      if (doc.exists) {
        setState(() {
          _locationData = doc.data();
          _locationName = _locationData!['name'] as String?;
          _locationAddress = _locationData!['address'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error loading location: $e');
    }
  }

  void _toggleSlot(String courtId, String timeSlot) {
    setState(() {
      if (!_selectedSlots.containsKey(courtId)) {
        _selectedSlots[courtId] = [];
      }
      
      if (_selectedSlots[courtId]!.contains(timeSlot)) {
        _selectedSlots[courtId]!.remove(timeSlot);
        if (_selectedSlots[courtId]!.isEmpty) {
          _selectedSlots.remove(courtId);
        }
      } else {
        _selectedSlots[courtId]!.add(timeSlot);
        _selectedSlots[courtId]!.sort();
      }
    });
  }

  double _calculateTotalCost() {
    if (_locationData == null) return 0.0;
    
    final pricePer30Min = (_locationData!['pricePer30Min'] as num?)?.toDouble() ?? 0.0;
    double total = 0.0;
    
    for (var slots in _selectedSlots.values) {
      total += slots.length * pricePer30Min;
    }
    
    return total;
  }

  double _calculateDuration() {
    double totalMinutes = 0.0;
    for (var slots in _selectedSlots.values) {
      totalMinutes += slots.length * 30;
    }
    return totalMinutes / 60; // Convert to hours
  }

  List<String> _generateTimeSlots() {
    if (_locationData == null) return [];
    
    final openTime = _locationData!['openTime'] as String? ?? '6:00 AM';
    final closeTime = _locationData!['closeTime'] as String? ?? '11:00 PM';
    
    return _generateSlotsBetween(openTime, closeTime);
  }

  List<String> _generateSlotsBetween(String start, String end) {
    final startTime = _parseTime(start);
    final endTime = _parseTime(end);
    final slots = <String>[];
    
    var current = startTime;
    while (current.isBefore(endTime) || current == endTime) {
      slots.add(_formatTime(current));
      current = current.add(const Duration(minutes: 30));
    }
    
    return slots;
  }

  DateTime _parseTime(String timeStr) {
    try {
      final format = DateFormat('h:mm a');
      return format.parse(timeStr);
    } catch (e) {
      // Fallback parsing
      final parts = timeStr.replaceAll(' ', '').toUpperCase().split(RegExp(r'[:\s]'));
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        final isPM = parts.length > 2 && parts[2].contains('PM');
        final hour24 = isPM && hour != 12 ? hour + 12 : (hour == 12 && !isPM ? 0 : hour);
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, hour24, minute);
      }
      return DateTime.now();
    }
  }

  String _formatTime(DateTime time) {
    final format = DateFormat('h:mm a');
    return format.format(time);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: Text(
          _locationName ?? 'Select Court',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0A0E27),
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.location_on),
            onPressed: () {
              // TODO: Show location on map
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('courtLocations')
            .doc(widget.locationId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                'Location not found',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final locationData = snapshot.data!.data() as Map<String, dynamic>;
          final courts = (locationData['courts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final timeSlots = _generateTimeSlots();

          return Column(
            children: [
              // Date Selector
              _buildDateSelector(),
              
              // Location Info
              if (_locationAddress != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _locationAddress!,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

              // Courts and Time Slots
              Expanded(
                child: courts.isEmpty
                    ? const Center(
                        child: Text(
                          'No courts available',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : Row(
                        children: courts.map((court) {
                          final courtId = court['id'] as String? ?? '';
                          final courtName = court['name'] as String? ?? 'Court ${courts.indexOf(court) + 1}';
                          return Expanded(
                            child: _buildCourtColumn(
                              courtId: courtId,
                              courtName: courtName,
                              timeSlots: timeSlots,
                            ),
                          );
                        }).toList(),
                      ),
              ),

              // Summary Bar
              if (_selectedSlots.isNotEmpty) _buildSummaryBar(locationData),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDateSelector() {
    final now = DateTime.now();
    
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF0A0E27),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDate(_selectedDate),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              itemBuilder: (context, index) {
                final date = now.add(Duration(days: index));
                final isSelected = date.day == _selectedDate.day &&
                    date.month == _selectedDate.month &&
                    date.year == _selectedDate.year;
                final dayName = _getDayName(date.weekday);
                final dayNumber = date.day;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                      _selectedSlots.clear(); // Clear selections when date changes
                    });
                  },
                  child: Container(
                    width: 50,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1E3A8A)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? null
                          : Border.all(color: Colors.white30, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 16,
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourtColumn({
    required String courtId,
    required String courtName,
    required List<String> timeSlots,
  }) {
    final selectedSlots = _selectedSlots[courtId] ?? [];
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          // Court Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(
                  courtName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(Icons.circle, size: 8, color: Colors.orange),
              ],
            ),
          ),
          // Time Slots
          Expanded(
            child: ListView.builder(
              itemCount: timeSlots.length,
              itemBuilder: (context, index) {
                final slot = timeSlots[index];
                final isSelected = selectedSlots.contains(slot);
                final isConsecutive = _isConsecutiveSlot(courtId, slot, selectedSlots);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: GestureDetector(
                    onTap: () => _toggleSlot(courtId, slot),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.green
                            : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? null
                            : Border.all(color: Colors.white30, width: 1),
                      ),
                      child: Center(
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white, size: 20)
                            : Text(
                                slot,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isConsecutiveSlot(String courtId, String slot, List<String> selectedSlots) {
    if (selectedSlots.isEmpty) return false;
    final slotIndex = _generateTimeSlots().indexOf(slot);
    if (slotIndex == -1) return false;
    
    // Check if previous or next slot is selected
    if (slotIndex > 0) {
      final prevSlot = _generateTimeSlots()[slotIndex - 1];
      if (selectedSlots.contains(prevSlot)) return true;
    }
    if (slotIndex < _generateTimeSlots().length - 1) {
      final nextSlot = _generateTimeSlots()[slotIndex + 1];
      if (selectedSlots.contains(nextSlot)) return true;
    }
    
    return false;
  }

  Widget _buildSummaryBar(Map<String, dynamic> locationData) {
    final totalCost = _calculateTotalCost();
    final duration = _calculateDuration();
    final pricePer30Min = (locationData['pricePer30Min'] as num?)?.toDouble() ?? 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            const Icon(Icons.payment, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total amount',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${totalCost.toStringAsFixed(1)} EGP',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_selectedSlots.isEmpty) return;
                
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CourtBookingConfirmationScreen(
                      locationId: widget.locationId,
                      locationName: _locationName ?? '',
                      locationAddress: _locationAddress ?? '',
                      selectedDate: _selectedDate,
                      selectedSlots: _selectedSlots,
                      totalCost: totalCost,
                      pricePer30Min: pricePer30Min,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E3A8A),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'NEXT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  String _getDayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[weekday - 1];
  }
}
