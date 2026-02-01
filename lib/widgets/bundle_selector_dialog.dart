import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/bundle_service.dart';

class BundleSelectorDialog extends StatefulWidget {
  final String? venue;
  final String? date;
  final String? day;
  final String? time;

  const BundleSelectorDialog({
    super.key,
    this.venue,
    this.date,
    this.day,
    this.time,
  });

  @override
  State<BundleSelectorDialog> createState() => _BundleSelectorDialogState();
}

class _BundleSelectorDialogState extends State<BundleSelectorDialog> {
  final BundleService _bundleService = BundleService();
  
  int selectedSessions = 1;
  int selectedPlayers = 1;
  double price = 0;
  Map<String, dynamic> pricing = {};
  bool loading = true;
  Map<String, String> dayTimeSchedule = {}; // For recurring schedule

  @override
  void initState() {
    super.initState();
    _loadPricing();
    // Auto-populate schedule with initial day/time if available
    if (widget.day != null && widget.time != null) {
      dayTimeSchedule[widget.day!] = widget.time!;
    }
  }

  Future<void> _loadPricing() async {
    final bundlePricing = await _bundleService.getBundlePricing();
    final calculatedPrice = await _bundleService.getBundlePrice(selectedSessions, selectedPlayers);
    
    setState(() {
      pricing = bundlePricing;
      price = calculatedPrice;
      loading = false;
    });
  }

  Future<void> _updatePrice() async {
    final newPrice = await _bundleService.getBundlePrice(selectedSessions, selectedPlayers);
    setState(() {
      price = newPrice;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading bundle options...'),
            ],
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Training Bundle',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Session Details Section - More Compact
            if (widget.venue != null && widget.date != null && widget.time != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 14, color: Colors.blue[700]),
                        const SizedBox(width: 6),
                        const Text(
                          'Session Details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildDetailRow('Venue', widget.venue!),
                    const SizedBox(height: 3),
                    _buildDetailRow('Date', widget.date!),
                    const SizedBox(height: 3),
                    _buildDetailRow('Day', widget.day!),
                    const SizedBox(height: 3),
                    _buildDetailRow('Time', widget.time!),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Session selection
            const Text(
              'Number of Sessions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildSessionOption(1),
                const SizedBox(width: 8),
                _buildSessionOption(4),
                const SizedBox(width: 8),
                _buildSessionOption(8),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Player count selection
            const Text(
              'Number of Players',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildPlayerOption(1),
                const SizedBox(width: 8),
                _buildPlayerOption(2),
                const SizedBox(width: 8),
                _buildPlayerOption(3),
                const SizedBox(width: 8),
                _buildPlayerOption(4),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Recurring Schedule Section (for 4 or 8 sessions)
            if (selectedSessions > 1 && dayTimeSchedule.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Training Schedule',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (selectedSessions == 8)
                          TextButton(
                            onPressed: () => _showScheduleDialog(context),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 20),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Add More Days', style: TextStyle(fontSize: 10)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...dayTimeSchedule.entries.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, size: 12, color: Colors.green[700]),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${entry.key}: ${entry.value}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    )),
                    if (selectedSessions == 4) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Fixed schedule for 4 weeks',
                        style: TextStyle(fontSize: 9, color: Colors.grey[600], fontStyle: FontStyle.italic),
                        softWrap: true,
                      ),
                    ],
                    if (selectedSessions == 8 && dayTimeSchedule.length < 3) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tap "Edit" for more days (2-3/week)',
                        style: TextStyle(fontSize: 9, color: Colors.orange[700]),
                        softWrap: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Price display
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Price:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${price.toStringAsFixed(0)} EGP',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Info text
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Bundle valid for 2 months from approval date',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, {
                        'sessions': selectedSessions,
                        'players': selectedPlayers,
                        'price': price,
                        'dayTimeSchedule': dayTimeSchedule,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.blue,
                    ),
                    child: const Text(
                      'Request Bundle',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<bool> _isSlotBlocked(String day, String time) async {
    if (widget.venue == null) return false;
    
    final blockedQuery = await FirebaseFirestore.instance
        .collection('blockedSlots')
        .where('venue', isEqualTo: widget.venue)
        .where('time', isEqualTo: time)
        .where('day', isEqualTo: day)
        .limit(1)
        .get();
    
    return blockedQuery.docs.isNotEmpty;
  }

  Future<void> _showScheduleDialog(BuildContext context) async {
    final daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final availableTimes = [
      '8:00 AM - 9:00 AM', '9:00 AM - 10:00 AM', '10:00 AM - 11:00 AM', '11:00 AM - 12:00 PM',
      '12:00 PM - 1:00 PM', '1:00 PM - 2:00 PM', '2:00 PM - 3:00 PM', '3:00 PM - 4:00 PM',
      '4:00 PM - 5:00 PM', '5:00 PM - 6:00 PM', '6:00 PM - 7:00 PM', '7:00 PM - 8:00 PM',
      '8:00 PM - 9:00 PM', '9:00 PM - 10:00 PM', '10:00 PM - 11:00 PM',
    ];
    
    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Training Days & Times', style: TextStyle(fontSize: 14)),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select 2-3 days per week for 8 sessions:', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 12),
                      
                      // Current schedule
                      if (dayTimeSchedule.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Current Schedule:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              const SizedBox(height: 6),
                              ...dayTimeSchedule.entries.map((entry) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text('${entry.key}: ${entry.value}', style: const TextStyle(fontSize: 11)),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 14),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        setDialogState(() {
                                          dayTimeSchedule.remove(entry.key);
                                        });
                                        setState(() {}); // Update parent
                                      },
                                    ),
                                  ],
                                ),
                              )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      // Add new day/time
                      const Text('Add More Days:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      const SizedBox(height: 6),
                      ...daysOfWeek.where((day) => !dayTimeSchedule.containsKey(day)).map((day) => 
                        ExpansionTile(
                          title: Text(day, style: const TextStyle(fontSize: 12)),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          children: availableTimes.map((timeSlot) => 
                            FutureBuilder<bool>(
                              future: _isSlotBlocked(day, timeSlot),
                              builder: (context, snapshot) {
                                final isBlocked = snapshot.data ?? false;
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          timeSlot,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isBlocked ? Colors.grey : Colors.black,
                                            decoration: isBlocked ? TextDecoration.lineThrough : null,
                                          ),
                                        ),
                                      ),
                                      if (isBlocked)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red[100],
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Booked',
                                            style: TextStyle(fontSize: 9, color: Colors.red[700]),
                                          ),
                                        ),
                                    ],
                                  ),
                                  enabled: !isBlocked,
                                  onTap: isBlocked ? null : () {
                                    if (dayTimeSchedule.length >= 3) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Maximum 3 days allowed for 8 sessions'),
                                          backgroundColor: Colors.orange,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                      return;
                                    }
                                    setDialogState(() {
                                      dayTimeSchedule[day] = timeSlot;
                                    });
                                    setState(() {}); // Update parent
                                  },
                                );
                              },
                            ),
                          ).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Done', style: TextStyle(fontSize: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSessionOption(int sessions) {
    final isSelected = selectedSessions == sessions;
    return Expanded(
      child: InkWell(
        onTap: () async {
          setState(() {
            selectedSessions = sessions;
          });
          await _updatePrice();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue : Colors.white,
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[300]!,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Text(
                '$sessions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sessions == 1 ? 'Session' : 'Sessions',
                style: TextStyle(
                  fontSize: 9,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerOption(int players) {
    final isSelected = selectedPlayers == players;
    // Check if this player count is available for selected session type
    final sessionKey = '${selectedSessions}_session${selectedSessions > 1 ? 's' : ''}';
    final playerKey = '${players}_player${players > 1 ? 's' : ''}';
    final isAvailable = pricing[sessionKey]?[playerKey] != null;

    return Expanded(
      child: InkWell(
        onTap: isAvailable ? () async {
          setState(() {
            selectedPlayers = players;
          });
          await _updatePrice();
        } : null,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isAvailable
                ? (isSelected ? Colors.blue : Colors.white)
                : Colors.grey[200],
            border: Border.all(
              color: isAvailable
                  ? (isSelected ? Colors.blue : Colors.grey[300]!)
                  : Colors.grey[300]!,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              Icon(
                Icons.person,
                color: isAvailable
                    ? (isSelected ? Colors.white : Colors.blue)
                    : Colors.grey,
                size: 16,
              ),
              const SizedBox(height: 1),
              Text(
                '$players',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isAvailable
                      ? (isSelected ? Colors.white : Colors.black)
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 45,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
