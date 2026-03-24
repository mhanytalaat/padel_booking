import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/map_launcher.dart';
import '../utils/auth_required.dart';
import 'admin_screen.dart';
import 'my_bookings_screen.dart';
import 'my_tournaments_screen.dart';
import 'tournaments_screen.dart';
import 'tournament_join_screen.dart';
import 'tournament_dashboard_screen.dart';
import 'skills_screen.dart';
import 'edit_profile_screen.dart';
import 'notifications_screen.dart';
import 'booking_page_screen.dart';
import 'court_locations_screen.dart';
import 'login_screen.dart';
import '../services/notification_service.dart';
import '../services/bundle_service.dart';
import '../models/bundle_model.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';
import '../widgets/bundle_selector_dialog.dart';
import '../widgets/next_tournament_countdown_banner.dart';
import '../utils/tournament_start_time.dart';


class HomeScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialVenue;

  const HomeScreen({
    super.key,
    this.initialDate,
    this.initialVenue,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final ValueNotifier<DateTime?> _selectedDateNotifier = ValueNotifier<DateTime?>(null);
  DateTime? get selectedDate => _selectedDateNotifier.value;
  int _selectedNavIndex = -1;
  Set<String> _expandedVenues = {};
  final ScrollController _scrollController = ScrollController();
  String? _selectedVenueFilter;
  final Map<String, GlobalKey> _venueKeys = {};
  static const String adminPhone = '+201006500506';
  static const String adminEmail = 'admin@padelcore.com';

  late AnimationController _heroAnimationController;
  late AnimationController _highlightController;
  late AnimationController _cardsEntranceController;
  late Animation<double> _trainOpacity;
  late Animation<double> _competeOpacity;
  late Animation<double> _improveOpacity;
  late Animation<double> _subtitleOpacity;
  late Animation<Offset> _trainSlide;
  late Animation<Offset> _competeSlide;
  late Animation<Offset> _improveSlide;
  late Animation<Offset> _subtitleSlide;
  late Animation<double> _card1Entrance;
  late Animation<double> _card2Entrance;
  late Animation<double> _card3Entrance;

  // ── Ball travel animation ──────────────────────────────────────────────────
  // X and Y driven independently so arcs are true parabolas.
  late AnimationController _ballTravelController;
  late Animation<double> _ballTravelX; // fraction of cardW (0.0–1.0)
  late Animation<double> _ballTravelY; // absolute px from top of cards Stack
  late Animation<double> _ballScale;

  // ── Cup spin ──────────────────────────────────────────────────────────────
  late AnimationController _cupRotationController;
  late Animation<double> _cupRotation;

  static const double _dimmedHighlight = 0.42;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedDateNotifier.value = widget.initialDate ?? DateTime.now();
    _selectedVenueFilter = widget.initialVenue;

    // ── Hero entrance ────────────────────────────────────────────────────────
    _heroAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    const curve = Curves.easeOutCubic;
    _trainOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.0, 0.25, curve: curve)));
    _competeOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.2, 0.45, curve: curve)));
    _improveOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.4, 0.65, curve: curve)));
    _subtitleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.55, 0.85, curve: curve)));

    const slideBegin = Offset(-0.15, 0);
    const slideEnd = Offset.zero;
    _trainSlide = Tween<Offset>(begin: slideBegin, end: slideEnd).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.0, 0.25, curve: curve)));
    _competeSlide = Tween<Offset>(begin: slideBegin, end: slideEnd).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.2, 0.45, curve: curve)));
    _improveSlide = Tween<Offset>(begin: slideBegin, end: slideEnd).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.4, 0.65, curve: curve)));
    _subtitleSlide = Tween<Offset>(begin: slideBegin, end: slideEnd).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: const Interval(0.55, 0.85, curve: curve)));

    // ── Highlight cycle ───────────────────────────────────────────────────────
    _highlightController = AnimationController(vsync: this, duration: const Duration(milliseconds: 4000));

    // ── Cards entrance ────────────────────────────────────────────────────────
    _cardsEntranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    const cardCurve = Curves.easeOutCubic;
    _card1Entrance = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardsEntranceController, curve: const Interval(0.0, 0.35, curve: cardCurve)));
    _card2Entrance = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardsEntranceController, curve: const Interval(0.15, 0.5, curve: cardCurve)));
    _card3Entrance = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _cardsEntranceController, curve: const Interval(0.3, 0.65, curve: cardCurve)));

    // ── Ball travel (looping, 9 s per cycle) ─────────────────────────────────
    // To get real parabolic arcs we drive X and Y independently.
    //
    // Card geometry (Stack coords):
    //   Train card    y = 0..180,   centre-x fraction ≈ 0.20
    //   Bottom row    y = 192..372
    //     BookCourt   centre-x fraction ≈ 0.24
    //     Compete     centre-x fraction ≈ 0.76
    //
    // Timeline (weights sum = 100):
    //   w 5  – Train bounce up
    //   w 5  – Train bounce down
    //   w 5  – Train bounce up
    //   w 5  – Train bounce down        ← last touch = launch moment
    //   w 8  – arc BC (x slides, y arcs up then down)
    //   w 5  – BC bounce up
    //   w 5  – BC bounce down
    //   w 5  – BC bounce up
    //   w 5  – BC bounce down           ← last touch = launch moment
    //   w 8  – arc Compete (x slides, y arcs up then down)
    //   w 5  – Compete bounce up
    //   w 5  – Compete bounce down
    //   w 5  – Compete bounce up
    //   w 5  – Compete bounce down      ← last touch = launch moment
    //   w 9  – arc back to Train
    //   w 5  – pause

    _ballTravelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();

    // ─────────────────────────────────────────────────────────────────────────
    // Ball positions:
    //   Train centre      dx=0.50, dy=155   bounce top dy=122
    //   BookCourt centre  dx=0.24, dy=282   bounce top dy=252
    //   Compete centre    dx=0.76, dy=282   bounce top dy=252
    //
    // Weight budget — X and Y must have IDENTICAL item count & weights:
    //   Phase 1  Train bounce ×4 half-bounces          4 × w5  = 20
    //   Phase 2  arc Train→BookCourt (rise+fall in Y)  2 × w4  =  8
    //   Phase 3  BookCourt bounce ×4 half-bounces      4 × w5  = 20
    //   Phase 4  arc BookCourt→Compete (rise+fall)     2 × w4  =  8
    //   Phase 5  Compete bounce ×4 half-bounces        4 × w5  = 20
    //   Phase 6  arc Compete→Train    (rise+fall)      2 × w4  =  8
    //   Phase 7  pause at Train                        1 × w16 = 16
    //                                                  total   100
    // ─────────────────────────────────────────────────────────────────────────

    // ── X (fraction of cardW) ────────────────────────────────────────────────
    _ballTravelX = TweenSequence<double>([
      // Phase 1 – Train bounces: stay at 0.50
      TweenSequenceItem(tween: ConstantTween(0.50), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.50), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.50), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.50), weight: 5),
      // Phase 2 – arc Train→BookCourt: X slides 0.50→0.24 evenly across both halves
      TweenSequenceItem(tween: Tween(begin: 0.50, end: 0.37), weight: 4),
      TweenSequenceItem(tween: Tween(begin: 0.37, end: 0.24), weight: 4),
      // Phase 3 – BookCourt bounces: stay at 0.24
      TweenSequenceItem(tween: ConstantTween(0.24), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.24), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.24), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.24), weight: 5),
      // Phase 4 – arc BookCourt→Compete: X slides 0.24→0.76 evenly
      TweenSequenceItem(tween: Tween(begin: 0.24, end: 0.50), weight: 4),
      TweenSequenceItem(tween: Tween(begin: 0.50, end: 0.76), weight: 4),
      // Phase 5 – Compete bounces: stay at 0.76
      TweenSequenceItem(tween: ConstantTween(0.76), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.76), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.76), weight: 5),
      TweenSequenceItem(tween: ConstantTween(0.76), weight: 5),
      // Phase 6 – arc Compete→Train: X slides 0.76→0.50 evenly
      TweenSequenceItem(tween: Tween(begin: 0.76, end: 0.63), weight: 4),
      TweenSequenceItem(tween: Tween(begin: 0.63, end: 0.50), weight: 4),
      // Phase 7 – pause
      TweenSequenceItem(tween: ConstantTween(0.50), weight: 16),
    ]).animate(_ballTravelController);

    // ── Y (absolute px from top of Stack) ───────────────────────────────────
    _ballTravelY = TweenSequence<double>([
      // Phase 1 – Train bounces (around dy=155, peak=122)
      TweenSequenceItem(tween: Tween(begin: 155.0, end: 122.0).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 122.0, end: 155.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 5),
      TweenSequenceItem(tween: Tween(begin: 155.0, end: 122.0).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 122.0, end: 155.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 5),
      // Phase 2 – arc Train→BookCourt: rises to peak 100, then drops to 282
      TweenSequenceItem(tween: Tween(begin: 155.0, end: 100.0).chain(CurveTween(curve: Curves.easeOut)), weight: 4),
      TweenSequenceItem(tween: Tween(begin: 100.0, end: 282.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 4),
      // Phase 3 – BookCourt bounces (around dy=282, peak=252)
      TweenSequenceItem(tween: Tween(begin: 282.0, end: 252.0).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 252.0, end: 282.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 5),
      TweenSequenceItem(tween: Tween(begin: 282.0, end: 252.0).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 252.0, end: 282.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 5),
      // Phase 4 – arc BookCourt→Compete: rises to peak 210, drops to 282
      TweenSequenceItem(tween: Tween(begin: 282.0, end: 210.0).chain(CurveTween(curve: Curves.easeOut)), weight: 4),
      TweenSequenceItem(tween: Tween(begin: 210.0, end: 282.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 4),
      // Phase 5 – Compete bounces (around dy=282, peak=252)
      TweenSequenceItem(tween: Tween(begin: 282.0, end: 252.0).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 252.0, end: 282.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 5),
      TweenSequenceItem(tween: Tween(begin: 282.0, end: 252.0).chain(CurveTween(curve: Curves.easeOut)), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 252.0, end: 282.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 5),
      // Phase 6 – arc Compete→Train: rises high to peak 60, drops to 155
      TweenSequenceItem(tween: Tween(begin: 282.0, end: 60.0).chain(CurveTween(curve: Curves.easeOut)),  weight: 4),
      TweenSequenceItem(tween: Tween(begin: 60.0,  end: 155.0).chain(CurveTween(curve: Curves.easeIn)),  weight: 4),
      // Phase 7 – pause at Train start (exactly matches loop restart value)
      TweenSequenceItem(tween: ConstantTween(155.0), weight: 16),
    ]).animate(_ballTravelController);

    // Ball is always full size — no shrinking
    _ballScale = ConstantTween<double>(1.0).animate(_ballTravelController);

    // ── Cup spin ──────────────────────────────────────────────────────────────
    // Cup removed — controller kept only so dispose() doesn't crash
    _cupRotationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    _cupRotation = ConstantTween<double>(0.0).animate(_cupRotationController);

    // ── Start sequence ────────────────────────────────────────────────────────
    _heroAnimationController.forward();
    _heroAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _highlightController.repeat();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _cardsEntranceController.forward();
        });
      }
    });
  }

  (double, double, double) _getHighlightOpacities() {
    final v = _highlightController.value;
    const d = _dimmedHighlight;
    if (v <= 0.25) return (1.0, d, d);
    if (v <= 0.5) {
      final t = Curves.easeInOutCubic.transform((v - 0.25) / 0.25);
      return (1.0 + (d - 1.0) * t, d + (1.0 - d) * t, d);
    }
    if (v <= 0.75) {
      final t = Curves.easeInOutCubic.transform((v - 0.5) / 0.25);
      return (d, 1.0 + (d - 1.0) * t, d + (1.0 - d) * t);
    }
    final t = Curves.easeInOutCubic.transform((v - 0.75) / 0.25);
    return (d + (1.0 - d) * t, d, 1.0 + (d - 1.0) * t);
  }

  @override
  void dispose() {
    _ballTravelController.dispose();
    _cupRotationController.dispose();
    _highlightController.dispose();
    _cardsEntranceController.dispose();
    _heroAnimationController.dispose();
    _scrollController.dispose();
    _selectedDateNotifier.dispose();
    super.dispose();
  }

  bool _isAdmin() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.phoneNumber == adminPhone || user.email == adminEmail;
  }

  Stream<QuerySnapshot> _getBookingsStream() {
    return FirebaseFirestore.instance.collection('bookings').snapshots();
  }

  Stream<QuerySnapshot> getUserBookings(String userId) {
    return FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  String _getBookingKey(String venue, String time, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$dateStr|$venue|$time';
  }

  int _getSlotBookingCount(String venue, String time, Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    if (currentSelectedDate == null) return 0;
    final key = _getBookingKey(venue, time, currentSelectedDate);
    return slotCounts[key] ?? 0;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  Future<Map<String, bool>> _getRecurringBookingDays(String venue, String time) async {
    Map<String, bool> recurringDays = {'Sunday': false, 'Tuesday': false};
    try {
      final bookings = await FirebaseFirestore.instance
          .collection('bookings')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .where('isRecurring', isEqualTo: true)
          .where('status', isEqualTo: 'approved')
          .get();
      for (var doc in bookings.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final recurringDaysList = (data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
        if (recurringDaysList.contains('Sunday')) recurringDays['Sunday'] = true;
        if (recurringDaysList.contains('Tuesday')) recurringDays['Tuesday'] = true;
      }
    } catch (e) {}
    return recurringDays;
  }

  Stream<bool> _isSlotBlockedStream(String venue, String time, String dayName) {
    return FirebaseFirestore.instance
        .collection('blockedSlots')
        .where('venue', isEqualTo: venue)
        .where('time', isEqualTo: time)
        .where('day', isEqualTo: dayName)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty);
  }

  String _getDayName(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  bool _doesRecurringBookingApply(Map<String, dynamic> booking, DateTime date) {
    if (booking['isRecurring'] != true) return false;
    final recurringDays = (booking['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
    return recurringDays.contains(_getDayName(date));
  }

  Future<int> _getMaxUsersPerSlot() async {
    int maxUsersPerSlot = 4;
    try {
      final configDoc = await FirebaseFirestore.instance.collection('config').doc('bookingSettings').get();
      if (configDoc.exists) {
        maxUsersPerSlot = (configDoc.data()?['maxUsersPerSlot'] as int?) ?? 4;
      }
    } catch (e) {}
    return maxUsersPerSlot;
  }

  Future<Map<String, dynamic>?> _showBookingConfirmation(String venue, String time, String coach) async {
    if (_selectedDateNotifier.value == null) return null;
    final selectedDate = _selectedDateNotifier.value!;
    final dayName = _getDayName(selectedDate);

    Map<String, dynamic>? bundleConfig = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => BundleSelectorDialog(
        venue: venue,
        date: '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
        day: dayName,
        time: time,
      ),
    );
    if (bundleConfig == null) return null;

    final dayTimeSchedule = bundleConfig['dayTimeSchedule'] as Map<String, String>? ?? {};
    final sessions = bundleConfig['sessions'] as int;
    final isRecurring = sessions > 1 && dayTimeSchedule.isNotEmpty;

    for (var entry in dayTimeSchedule.entries) {
      final blockedCheck = await FirebaseFirestore.instance
          .collection('blockedSlots')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: entry.value)
          .where('day', isEqualTo: entry.key)
          .get();
      if (blockedCheck.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${entry.key} at ${entry.value} has been blocked by admin'), backgroundColor: Colors.red),
          );
        }
        return null;
      }
    }

    Set<String> selectedDays = dayTimeSchedule.keys.toSet();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Booking'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Training Details:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('Venue: $venue')),
                    TextButton.icon(
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('Map', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      onPressed: () async {
                        try {
                          final locationSnapshot = await FirebaseFirestore.instance
                              .collection('courtLocations')
                              .where('name', isEqualTo: venue)
                              .limit(1)
                              .get();
                          if (locationSnapshot.docs.isNotEmpty && context.mounted) {
                            final locationData = locationSnapshot.docs.first.data();
                            await MapLauncher.openLocation(
                              context: context,
                              lat: (locationData['lat'] as num?)?.toDouble(),
                              lng: (locationData['lng'] as num?)?.toDouble(),
                              addressQuery: '$venue, ${locationData['address'] ?? venue}',
                            );
                          }
                        } catch (e) { debugPrint('Error opening map: $e'); }
                      },
                    ),
                  ],
                ),
                Text('Time: $time'),
                Text('Coach: $coach'),
                const SizedBox(height: 16),
                const Text('Bundle:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text('${bundleConfig['sessions']} Sessions - ${bundleConfig['players']} Player${bundleConfig['players'] > 1 ? 's' : ''}'),
                Text('Price: ${bundleConfig['price']} EGP'),
                if (isRecurring) ...[
                  const SizedBox(height: 16),
                  const Text('Schedule:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...dayTimeSchedule.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${e.key}: ${e.value}'),
                        )),
                        const SizedBox(height: 8),
                        Text('Start date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                        Text('Duration: 4 weeks'),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Text('Single session on: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm Booking')),
          ],
        );
      },
    );

    if (confirmed != true) return null;
    return {
      'confirmed': true,
      'isRecurring': isRecurring,
      'recurringDays': selectedDays.toList(),
      'dayTimeSchedule': dayTimeSchedule,
      'bundleConfig': bundleConfig,
      'selectedBundleId': null,
    };
  }

  Future<void> _showRecurringDaysTimeDialog(Map<String, String> dayTimeSchedule, int sessions, String venue) async {
    final daysOfWeek = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final availableTimes = [
      '8:00 AM - 9:00 AM', '9:00 AM - 10:00 AM', '10:00 AM - 11:00 AM', '11:00 AM - 12:00 PM',
      '12:00 PM - 1:00 PM', '1:00 PM - 2:00 PM', '2:00 PM - 3:00 PM', '3:00 PM - 4:00 PM',
      '4:00 PM - 5:00 PM', '5:00 PM - 6:00 PM', '6:00 PM - 7:00 PM', '7:00 PM - 8:00 PM',
      '8:00 PM - 9:00 PM', '9:00 PM - 10:00 PM', '10:00 PM - 11:00 PM',
    ];
    await showDialog(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setState) {
          final currentDays = dayTimeSchedule.keys.toList();
          return AlertDialog(
            title: Text('Select Training Schedule ($sessions sessions)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select ${sessions == 4 ? '1-2' : '2-3'} days per week with specific times:',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (currentDays.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Current Schedule:', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ...currentDays.map((day) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('$day: ${dayTimeSchedule[day]}'),
                                IconButton(icon: const Icon(Icons.close, size: 18),
                                    onPressed: () => setState(() => dayTimeSchedule.remove(day))),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Add More Days:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...daysOfWeek.where((day) => !dayTimeSchedule.containsKey(day)).map((day) =>
                    ExpansionTile(
                      title: Text(day),
                      children: availableTimes.map((timeSlot) => ListTile(
                        title: Text(timeSlot, style: const TextStyle(fontSize: 14)),
                        onTap: () {
                          if ((sessions == 4 && dayTimeSchedule.length >= 2) ||
                              (sessions == 8 && dayTimeSchedule.length >= 3)) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Maximum ${sessions == 4 ? '2' : '3'} days allowed'),
                              backgroundColor: Colors.orange,
                            ));
                            return;
                          }
                          setState(() => dayTimeSchedule[day] = timeSlot);
                        },
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final minDays = sessions == 4 ? 1 : 2;
                  if (dayTimeSchedule.length < minDays) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Please select at least $minDays day(s) for $sessions sessions'),
                      backgroundColor: Colors.orange,
                    ));
                    return;
                  }
                  Navigator.of(context).pop();
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processBooking(String venue, String time, String coach, Map<String, dynamic> result) async {
    if (result['confirmed'] != true) return;

    final isRecurring = result['isRecurring'] as bool? ?? false;
    final recurringDays = (result['recurringDays'] as List<dynamic>?)?.cast<String>() ?? [];
    final dayTimeSchedule = result['dayTimeSchedule'] as Map<String, String>? ?? {};
    final Map<String, dynamic>? bundleConfig = result['bundleConfig'];
    final String? selectedBundleId = result['selectedBundleId'];

    int playerCount = 1;
    bool isPrivate = false;
    if (bundleConfig != null) {
      playerCount = bundleConfig['players'] as int;
      isPrivate = bundleConfig['isPrivate'] as bool? ?? false;
    } else if (selectedBundleId != null) {
      final bundle = await BundleService().getBundleById(selectedBundleId);
      if (bundle != null) {
        playerCount = bundle.playerCount;
        isPrivate = playerCount == 1;
      }
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in to book a slot'), backgroundColor: Colors.red));
        return;
      }

      final dateStr = '${_selectedDateNotifier.value!.year}-${_selectedDateNotifier.value!.month.toString().padLeft(2, '0')}-${_selectedDateNotifier.value!.day.toString().padLeft(2, '0')}';
      final dayName = _getDayName(_selectedDateNotifier.value!);

      final blockedSlotsQuery = await FirebaseFirestore.instance
          .collection('blockedSlots')
          .where('venue', isEqualTo: venue)
          .where('time', isEqualTo: time)
          .where('day', isEqualTo: dayName)
          .get();
      if (blockedSlotsQuery.docs.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This time slot has been blocked by admin'), backgroundColor: Colors.red));
        return;
      }

      final allBookings = await FirebaseFirestore.instance
          .collection('bookings').where('venue', isEqualTo: venue).where('time', isEqualTo: time).get();
      final existingBookings = allBookings.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        if ((data['status'] as String? ?? 'pending') == 'rejected') return false;
        if (data['isRecurring'] as bool? ?? false) {
          return ((data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? []).contains(dayName);
        }
        return (data['date'] as String? ?? '') == dateStr;
      }).toList();

      int maxUsersPerSlot = 4;
      try {
        final configDoc = await FirebaseFirestore.instance.collection('config').doc('bookingSettings').get();
        if (configDoc.exists) maxUsersPerSlot = (configDoc.data()?['maxUsersPerSlot'] as int?) ?? 4;
      } catch (e) {}

      int totalSlotsReserved = 0;
      for (var booking in existingBookings) {
        totalSlotsReserved += (booking.data()['slotsReserved'] as int? ?? 1);
      }

      if (isPrivate && totalSlotsReserved > 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Private booking requires all 4 slots to be available.'), backgroundColor: Colors.orange));
        return;
      }

      final slotsNeeded = isPrivate ? maxUsersPerSlot : playerCount;
      if (totalSlotsReserved + slotsNeeded > maxUsersPerSlot) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Not enough slots available. ${maxUsersPerSlot - totalSlotsReserved} slot(s) remaining.'),
            backgroundColor: Colors.orange));
        return;
      }

      final bookingData = <String, dynamic>{
        'userId': user.uid,
        'phone': user.phoneNumber ?? '',
        'venue': venue, 'time': time, 'coach': coach, 'date': dateStr,
        'bookingType': 'Bundle', 'isPrivate': isPrivate, 'isRecurring': isRecurring,
        'status': 'pending', 'timestamp': FieldValue.serverTimestamp(),
      };
      if (isRecurring) {
        bookingData['recurringDays'] = recurringDays;
        bookingData['dayOfWeek'] = _getDayName(_selectedDateNotifier.value!);
      }

      final userProfile = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get(const GetOptions(source: Source.server));
      if (!userProfile.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Your profile is not set up. Please sign out and sign up again.'),
            backgroundColor: Colors.red, duration: Duration(seconds: 5)));
        return;
      }

      final userData = userProfile.data() as Map<String, dynamic>?;
      final firstName = userData?['firstName'] as String? ?? '';
      final lastName = userData?['lastName'] as String? ?? '';
      final combined = '$firstName $lastName'.trim();
      final fullName = (userData?['fullName'] as String?)?.trim() ?? '';
      final userName = combined.isNotEmpty ? combined : (fullName.isNotEmpty ? fullName : (user.phoneNumber ?? 'User'));

      bookingData['slotsReserved'] = isPrivate ? maxUsersPerSlot : playerCount;

      String? bundleId;
      if (bundleConfig != null) {
        String scheduleNotes;
        if (isRecurring && dayTimeSchedule.isNotEmpty) {
          scheduleNotes = 'Recurring Schedule:\n${dayTimeSchedule.entries.map((e) => '${e.key}: ${e.value}').join('\n')}\nVenue: $venue\nCoach: $coach\nStart Date: $dateStr';
        } else {
          scheduleNotes = 'Single session at $venue on $dateStr at $time with $coach';
        }
        bundleId = await BundleService().createBundleRequest(
          userId: user.uid, userName: userName, userPhone: user.phoneNumber ?? '',
          bundleType: bundleConfig['sessions'], playerCount: bundleConfig['players'],
          notes: scheduleNotes,
          scheduleDetails: {
            'venue': venue, 'coach': coach, 'startDate': dateStr, 'time': time,
            'isRecurring': isRecurring, 'recurringDays': recurringDays, 'dayTimeSchedule': dayTimeSchedule,
          },
        );
        await NotificationService().notifyAdminForBundleRequest(
          bundleId: bundleId, userId: user.uid, userName: userName, phone: user.phoneNumber ?? '',
          sessions: bundleConfig['sessions'], players: bundleConfig['players'],
          price: bundleConfig['price'].toDouble(),
        );
      } else if (selectedBundleId != null) {
        bundleId = selectedBundleId;
      }

      if (bundleId != null) { bookingData['bundleId'] = bundleId; bookingData['isBundle'] = true; }

      final bookingRef = await FirebaseFirestore.instance.collection('bookings').add(bookingData);

      if (bundleId != null && selectedBundleId != null) {
        final bundle = await BundleService().getBundleById(bundleId);
        if (bundle != null) {
          await BundleService().createBundleSession(
            bundleId: bundleId, userId: user.uid,
            sessionNumber: bundle.totalSessions - bundle.remainingSessions + 1,
            date: dateStr, time: time, venue: venue, coach: coach,
            playerCount: bundle.playerCount, bookingId: bookingRef.id,
          );
        }
      }

      if (bundleId != null && bundleConfig != null && (bundleConfig['sessions'] as int? ?? 0) == 1) {
        await BundleService().createBundleSession(
          bundleId: bundleId, userId: user.uid, sessionNumber: 1,
          date: dateStr, time: time, venue: venue, coach: coach,
          playerCount: bundleConfig['players'] as int? ?? 1,
          bookingId: bookingRef.id, bookingStatus: 'pending',
        );
      }

      if (selectedBundleId != null) {
        await NotificationService().notifyAdminForBookingRequest(
          bookingId: bookingRef.id, userId: user.uid, userName: userName,
          phone: user.phoneNumber ?? '', venue: venue, time: time, date: dateStr,
        );
      }

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.check_circle, color: Colors.green, size: 32),
              SizedBox(width: 12),
              Expanded(child: Text('Request Submitted!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bundleConfig != null
                    ? 'Bundle request submitted! Admin will review and approve.'
                    : 'Booking from bundle submitted! Waiting for admin approval.'),
                const SizedBox(height: 16),
                Text(venue, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(time, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text(dateStr, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    var locationSnapshot = await FirebaseFirestore.instance
                        .collection('courtLocations').where('name', isEqualTo: venue).limit(1).get();
                    if (locationSnapshot.docs.isEmpty) {
                      locationSnapshot = await FirebaseFirestore.instance
                          .collection('venues').where('name', isEqualTo: venue).limit(1).get();
                    }
                    if (locationSnapshot.docs.isNotEmpty && context.mounted) {
                      final ld = locationSnapshot.docs.first.data();
                      await MapLauncher.openLocation(
                        context: context,
                        lat: (ld['lat'] as num?)?.toDouble(),
                        lng: (ld['lng'] as num?)?.toDouble(),
                        addressQuery: '$venue, ${ld['address'] ?? venue}',
                      );
                    }
                  } catch (e) { debugPrint('Error opening map: $e'); }
                },
                icon: const Icon(Icons.map),
                label: const Text('Get Directions'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), foregroundColor: Colors.white),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Error booking slot: $e';
        if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permission denied. Please make sure you are logged in and try again.';
        } else if (e.toString().contains('unavailable')) {
          errorMessage = 'Service temporarily unavailable. Please try again in a moment.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.red, duration: const Duration(seconds: 5)));
      }
    }
  }

  Future<void> _handleBooking(String venue, String time, String coach) async {
    final result = await _showBookingConfirmation(venue, time, coach);
    if (result != null) await _processBooking(venue, time, coach, result);
  }

  void _onNavItemTapped(int index) {
    final isGuest = FirebaseAuth.instance.currentUser == null;
    setState(() { _selectedNavIndex = index; });

    void popAndReset() => setState(() { _selectedNavIndex = -1; });

    switch (index) {
      case 0:
        requireLogin(context).then((loggedIn) {
          if (loggedIn && mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const MyBookingsScreen()))
                .then((_) => popAndReset());
          } else { popAndReset(); }
        });
        break;
      case 1:
        Navigator.push(context, MaterialPageRoute(builder: (context) => const TournamentsScreen()))
            .then((_) => popAndReset());
        break;
      case 2:
        if (isGuest) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen(initialSignUpMode: true)))
              .then((_) => popAndReset());
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfileScreen()))
              .then((_) => popAndReset());
        }
        break;
      case 3:
        Navigator.push(context, MaterialPageRoute(builder: (context) => const SkillsScreen()))
            .then((_) => popAndReset());
        break;
      case 4:
        if (isGuest) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen(initialSignUpMode: true)))
              .then((_) => popAndReset());
        } else { _handleLogout(); }
        break;
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Logout')),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
    } else {
      setState(() { _selectedNavIndex = -1; });
    }
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E27),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(icon: Icons.bookmark, label: 'My Bookings', index: 0),
              _buildNavItem(icon: Icons.emoji_events, label: 'Tournaments', index: 1),
              _buildNavItem(icon: Icons.person, label: 'Profile', index: 2),
              _buildNavItem(icon: Icons.radar, label: 'Skills', index: 3),
              _buildNavItem(
                icon: FirebaseAuth.instance.currentUser == null ? Icons.login : Icons.logout,
                label: FirebaseAuth.instance.currentUser == null ? 'Login' : 'Logout',
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(int unreadCount) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications, size: 28),
          tooltip: 'Notifications',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => NotificationsScreen())),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 8, top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  Widget _buildNavItem({required IconData icon, required String label, required int index}) {
    final isSelected = _selectedNavIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onNavItemTapped(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: TextStyle(color: Colors.white, fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), maxLines: 1),
              ),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  height: 2, width: 30,
                  decoration: const BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(1))),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: const AppHeader(),
      bottomNavigationBar: const AppFooter(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getBookingsStream(),
        builder: (context, snapshot) {
          return ValueListenableBuilder<DateTime?>(
            valueListenable: _selectedDateNotifier,
            builder: (context, currentSelectedDate, _) {
              Map<String, int> slotCounts = {};
              if (snapshot.hasData && currentSelectedDate != null) {
                final dayName = _getDayName(currentSelectedDate);
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if ((data['status'] as String? ?? 'pending') != 'approved') continue;
                  final venue = data['venue'] as String? ?? '';
                  final time = data['time'] as String? ?? '';
                  bool applies = false;
                  if (data['isRecurring'] as bool? ?? false) {
                    applies = ((data['recurringDays'] as List<dynamic>?)?.cast<String>() ?? []).contains(dayName);
                  } else {
                    final dateStr = '${currentSelectedDate.year}-${currentSelectedDate.month.toString().padLeft(2, '0')}-${currentSelectedDate.day.toString().padLeft(2, '0')}';
                    applies = (data['date'] as String? ?? '') == dateStr;
                  }
                  if (applies) {
                    final key = _getBookingKey(venue, time, currentSelectedDate);
                    slotCounts[key] = (slotCounts[key] ?? 0) + (data['slotsReserved'] as int? ?? 1);
                  }
                }
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('slots').snapshots(),
                builder: (context, slotsSnapshot) {
                  if (slotsSnapshot.connectionState == ConnectionState.waiting) {
                    return ListView(padding: const EdgeInsets.all(16), children: [
                      _buildDateDisplayWithCalendar(currentSelectedDate),
                      const Center(child: CircularProgressIndicator()),
                    ]);
                  }

                  Map<String, List<Map<String, String>>> venuesMap = {};
                  if (slotsSnapshot.hasData) {
                    for (var doc in slotsSnapshot.data!.docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final venue = data['venue'] as String? ?? '';
                      final time = data['time'] as String? ?? '';
                      final coach = data['coach'] as String? ?? '';
                      if (venue.isNotEmpty) {
                        venuesMap.putIfAbsent(venue, () => []).add({'time': time, 'coach': coach});
                      }
                    }
                  }

                  return ListView(
                    key: const PageStorageKey<String>('homeScreenListView'),
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    cacheExtent: 1000.0,
                    physics: const ClampingScrollPhysics(),
                    children: [
                      _buildHeroSection(),
                      _buildActionButtons(),
                      Container(
                        color: const Color(0xFF0A0E27),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: const Text('Book your training session today.',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                              ),
                              _buildDateDisplayWithCalendar(currentSelectedDate),
                              const SizedBox(height: 20),
                              Builder(builder: (context) {
                                final filteredVenuesMap = _selectedVenueFilter != null
                                    ? Map.fromEntries(venuesMap.entries.where((e) => e.key == _selectedVenueFilter))
                                    : venuesMap;
                                if (filteredVenuesMap.isEmpty) {
                                  return const SizedBox(height: 40,
                                      child: Center(child: Text('No slots available. Admin needs to add slots.',
                                          style: TextStyle(fontSize: 16, color: Colors.grey))));
                                }
                                return Column(children: [
                                  const SizedBox(height: 20),
                                  ...filteredVenuesMap.entries.map((entry) {
                                    _venueKeys.putIfAbsent(entry.key, () => GlobalKey());
                                    return Padding(
                                      key: _venueKeys[entry.key],
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _buildExpandableVenue(entry.key, entry.value, slotCounts, currentSelectedDate),
                                    );
                                  }),
                                ]);
                              }),
                            ],
                          ),
                        ),
                      ),
                      _buildTournamentsSection(),
                      _buildTrainingOptionsSection(),
                      _buildHowItWorksSection(),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HERO SECTION
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHeroSection() {
    return Container(
      height: 350,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF6B46C1)],
        ),
      ),
      child: Stack(
        children: [
          _buildAssetImage('assets/images/padel_court.jpg', fit: BoxFit.cover, width: double.infinity, height: 350),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.6)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: Listenable.merge([_heroAnimationController, _highlightController]),
              builder: (context, child) {
                final entranceDone = _heroAnimationController.value >= 1.0;
                final (trainH, competeH, improveH) = _getHighlightOpacities();
                const highlightGreen = Color(0xFF22C55E);
                const highlightThreshold = 0.5;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(opacity: _trainOpacity.value * (entranceDone ? trainH : 1.0),
                        child: SlideTransition(position: _trainSlide, child: Text('Train.',
                            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold,
                                color: trainH >= highlightThreshold ? highlightGreen : Colors.white, height: 1.1)))),
                    Opacity(opacity: _competeOpacity.value * (entranceDone ? competeH : 1.0),
                        child: SlideTransition(position: _competeSlide, child: Text('Compete.',
                            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold,
                                color: competeH >= highlightThreshold ? highlightGreen : Colors.white, height: 1.1)))),
                    Opacity(opacity: _improveOpacity.value * (entranceDone ? improveH : 1.0),
                        child: SlideTransition(position: _improveSlide, child: Text('Improve.',
                            style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold,
                                color: improveH >= highlightThreshold ? highlightGreen : Colors.white, height: 1.1)))),
                    const SizedBox(height: 16),
                    Opacity(opacity: _subtitleOpacity.value,
                        child: SlideTransition(position: _subtitleSlide,
                            child: const Text('Book your next padel session in seconds.',
                                style: TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w400)))),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTION BUTTONS  –  Train / Book Court / Compete cards with ball + cup
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildActionButtons() {
    // Layout constants
    const double trainH  = 180.0;
    const double gap     = 12.0;
    const double bottomH = 180.0;
    const double totalH  = trainH + gap + bottomH; // 372

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      color: const Color(0xFF0A0E27),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Explore PadelCore Features',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          // ── LayoutBuilder so we know the exact pixel width ──────────────
          LayoutBuilder(builder: (context, constraints) {
            final double cardW = constraints.maxWidth;
            final double halfW = (cardW - gap) / 2; // width of each bottom card

            return AnimatedBuilder(
              animation: Listenable.merge([_cardsEntranceController, _ballTravelController]),
              builder: (context, _) {
                final double ballX = _ballTravelX.value * cardW - 15;
                final double ballY = _ballTravelY.value - 15;
                final scale = _ballScale.value;

                return SizedBox(
                  height: totalH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [

                      // ── Train card (full width, top) ───────────────────────
                      Positioned(
                        left: 0, top: 0, width: cardW, height: trainH,
                        child: Opacity(
                          opacity: _card1Entrance.value,
                          child: _buildActionCard(
                            title: 'Train',
                            description: 'Certified coaches',
                            icon: Icons.fitness_center,
                            gradient: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                            imagePath: 'assets/images/train_today.jpg',
                            titleColor: Colors.white,
                            onTap: () async {
                              try {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate ?? DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null && mounted) {
                                  Navigator.push(context,
                                      MaterialPageRoute(builder: (context) => BookingPageScreen(initialDate: picked)));
                                }
                              } catch (e) {
                                debugPrint('Train Today error: $e');
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: Colors.red));
                              }
                            },
                          ),
                        ),
                      ),

                      // ── Book Court card (bottom-left) ──────────────────────
                      Positioned(
                        left: 0, top: trainH + gap, width: halfW, height: bottomH,
                        child: Opacity(
                          opacity: _card2Entrance.value,
                          child: _buildActionCard(
                            title: 'Book Court',
                            description: 'Get on game',
                            icon: Icons.emoji_events,
                            gradient: const [Color(0xFFFFC400), Color(0xFFFF9800)],
                            imagePath: 'assets/images/book_court.jpg',
                            titleColor: Colors.white,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (context) => const CourtLocationsScreen())),
                          ),
                        ),
                      ),

                      // ── Compete card (bottom-right) ────────────────────────
                      Positioned(
                        left: halfW + gap, top: trainH + gap, width: halfW, height: bottomH,
                        child: Opacity(
                          opacity: _card3Entrance.value,
                          child: _buildActionCard(
                            title: 'Compete',
                            description: 'Join tournaments',
                            icon: Icons.track_changes,
                            gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                            imagePath: 'assets/images/tournament.jpg',
                            titleColor: Colors.white,
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (context) => const TournamentsScreen())),
                          ),
                        ),
                      ),

                      // ── Travelling ball (drawn last so it's on top) ────────
                      if (scale > 0)
                        Positioned(
                          left: ballX,
                          top: ballY,
                          child: IgnorePointer(
                            child: Transform.scale(
                              scale: scale,
                              child: Image.asset(
                                'assets/images/ball.png',
                                width: 30,
                                height: 30,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 30, height: 30,
                                  decoration: const BoxDecoration(
                                      color: Color(0xFFCDDC39), shape: BoxShape.circle),
                                ),
                              ),
                            ),
                          ),
                        ),

                    ],
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
    String? imagePath,
    Color? titleColor,
    Color? descriptionColor,
    List<Widget>? stackOverlays,
  }) {
    final effectiveTitleColor = titleColor ?? Colors.white;
    final effectiveDescriptionColor = descriptionColor ?? Colors.white.withOpacity(0.9);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 180,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildAssetImage(imagePath, fit: BoxFit.cover, width: double.infinity, height: 180),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.7)]),
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                ),
                height: 80,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: effectiveTitleColor)),
                  const SizedBox(height: 4),
                  Text(description,
                      style: TextStyle(fontSize: 12, color: effectiveDescriptionColor),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (stackOverlays != null) ...stackOverlays,
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HOW IT WORKS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildHowItWorksSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How it works',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0A0E27))),
          const SizedBox(height: 32),
          _buildHowItWorksStep(stepNumber: 1, title: 'Book Training Sessions',
              steps: ['Select a date from the calendar', 'Choose your preferred location (Club 13 or Padel Avenue)',
                'Pick an available time slot', 'Click "Book" to reserve your session', 'Wait for admin approval'],
              icon: Icons.calendar_today, color: const Color(0xFF60A5FA)),
          const SizedBox(height: 32),
          _buildHowItWorksStep(stepNumber: 2, title: 'Book Courts',
              steps: ['Select a location from available courts', 'Choose your preferred date',
                'Pick available time slots (30-minute increments)', 'Review booking details and confirm',
                'Booking is confirmed immediately'],
              icon: Icons.sports_tennis, color: const Color(0xFF10B981)),
          const SizedBox(height: 32),
          _buildHowItWorksStep(stepNumber: 3, title: 'Join Tournaments',
              steps: ['Browse available tournaments', 'Select a tournament and choose your skill level',
                'Find or add a partner', 'Submit your registration', 'Wait for admin approval',
                'Check standings and compete!'],
              icon: Icons.emoji_events, color: const Color(0xFFFFC400)),
        ],
      ),
    );
  }

  Widget _buildHowItWorksStep({required int stepNumber, required String title,
      required List<String> steps, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A), borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 16),
            Expanded(child: Text('Step $stepNumber: $title',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))),
          ]),
          const SizedBox(height: 16),
          ...steps.map((step) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(margin: const EdgeInsets.only(top: 6), width: 6, height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Text(step,
                  style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9)))),
            ]),
          )),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TOURNAMENTS SECTION
  // ══════════════════════════════════════════════════════════════════════════
  void _showWeeklyTournamentsFromHome(BuildContext context, String parentTournamentId, String parentName) async {
    try {
      final weeklySnapshot = await FirebaseFirestore.instance
          .collection('tournaments').where('parentTournamentId', isEqualTo: parentTournamentId).get();
      if (!context.mounted) return;
      final weeklyTournaments = weeklySnapshot.docs
        ..sort((a, b) => ((a.data()['date'] as String?) ?? '').compareTo((b.data()['date'] as String?) ?? ''));
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('$parentName - Weekly Tournaments'),
            content: SizedBox(
              width: double.maxFinite, height: 400,
              child: weeklyTournaments.isEmpty
                  ? const Center(child: Text('No weekly tournaments yet.'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: weeklyTournaments.length,
                      itemBuilder: (context, index) {
                        final doc = weeklyTournaments[index];
                        final data = doc.data();
                        final name = data['name'] as String? ?? 'Week ${index + 1}';
                        final date = data['date'] as String? ?? '';
                        final status = data['status'] as String? ?? 'upcoming';
                        final hasStarted = ['phase1', 'phase2', 'knockout', 'completed', 'groups'].contains(status);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.white,
                              child: Text('${index + 1}',
                                  style: const TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 12))),
                            title: Text(date.isNotEmpty ? date : name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(status.toUpperCase()),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!hasStarted) TextButton(
                                  onPressed: () async {
                                    Navigator.pop(dialogContext);
                                    final loggedIn = await requireLogin(context);
                                    if (loggedIn && context.mounted) {
                                      Navigator.push(context, MaterialPageRoute(
                                          builder: (context) => TournamentJoinScreen(
                                              tournamentId: doc.id, tournamentName: name,
                                              tournamentImageUrl: data['imageUrl'] as String?)));
                                    }
                                  },
                                  child: const Text('Join'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    Navigator.push(context, MaterialPageRoute(
                                        builder: (context) => TournamentDashboardScreen(
                                            tournamentId: doc.id, tournamentName: name)));
                                  },
                                  child: const Text('Results'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading weekly tournaments: $e');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _buildTournamentsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Upcoming Tournaments',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              if (_isAdmin())
                IconButton(icon: const Icon(Icons.edit, color: Colors.white, size: 24),
                    onPressed: () => _showManageTournamentsDialog(), tooltip: 'Manage Visible Tournaments'),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('tournaments').orderBy('createdAt', descending: true).limit(40).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox(height: 100,
                    child: Center(child: Text('No tournaments available', style: TextStyle(color: Colors.white70))));
              }

              final tournaments = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if ((data['isArchived'] as bool? ?? false) || (data['hidden'] as bool? ?? false)) return false;
                return data['showOnHomePage'] as bool? ?? true;
              }).toList();

              if (tournaments.isEmpty) {
                return const SizedBox(height: 100,
                    child: Center(child: Text('No tournaments available', style: TextStyle(color: Colors.white70))));
              }

              final carousel = tournaments.length > 3 ? tournaments.sublist(0, 3) : tournaments;
              final nextCountdown = computeNextTournamentCountdown(tournaments);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (nextCountdown != null)
                    NextTournamentCountdownBanner(
                      tournamentName: nextCountdown.name,
                      target: nextCountdown.target,
                    ),
                  SizedBox(
                    height: 360,
                    child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: carousel.length,
                  itemBuilder: (context, index) {
                    final doc = carousel[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['name'] as String? ?? 'Unknown Tournament';
                    final imageUrl = data['imageUrl'] as String?;
                    final date = data['date'] as String? ?? '';
                    final time = data['time'] as String? ?? '';
                    final location = data['location'] as String? ?? '';
                    final entryFee = data['entryFee'] as int? ?? 0;
                    final prize = data['prize'] as int? ?? 0;
                    final maxParticipants = data['maxParticipants'] as int? ?? 12;
                    final participants = data['participants'] as int? ?? 0;
                    final tournamentType = data['type'] as String? ?? 'Single Elimination';
                    final isParentTournament = data['isParentTournament'] as bool? ?? false;
                    final parentTournamentId = data['parentTournamentId'] as String?;
                    final tournamentStatus = data['status'] as String? ?? 'upcoming';
                    final skillLevelData = data['skillLevel'];
                    final List<String> skillLevels = skillLevelData is List
                        ? (skillLevelData as List).map((e) => e.toString()).toList()
                        : (skillLevelData != null ? [skillLevelData.toString()] : ['Beginners']);

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 300, height: 360,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F3A), borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(flex: 2, child: Stack(fit: StackFit.expand, children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                              child: imageUrl != null && imageUrl.isNotEmpty
                                  ? (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')
                                      ? Image.network(imageUrl, fit: BoxFit.cover,
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Container(color: const Color(0xFF1E3A8A),
                                                child: Center(child: CircularProgressIndicator(
                                                    value: loadingProgress.expectedTotalBytes != null
                                                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes! : null,
                                                    color: Colors.white)));
                                          },
                                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E3A8A),
                                              child: const Icon(Icons.emoji_events, color: Colors.white, size: 48)))
                                      : _buildAssetImage(imageUrl))
                                  : Container(color: const Color(0xFF1E3A8A),
                                      child: const Icon(Icons.emoji_events, color: Colors.white, size: 48)),
                            ),
                            Positioned(
                              top: 8, right: 8,
                              child: Wrap(
                                spacing: 4, runSpacing: 4, alignment: WrapAlignment.end,
                                children: skillLevels.map((level) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                  child: Text(level.toUpperCase(),
                                      style: const TextStyle(color: Color(0xFF1E3A8A), fontSize: 9, fontWeight: FontWeight.bold)),
                                )).toList(),
                              ),
                            ),
                          ])),
                          Expanded(flex: 3, child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SingleChildScrollView(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(tournamentType, style: const TextStyle(fontSize: 12, color: Color(0xFF14B8A6))),
                                const SizedBox(height: 8),
                                Text('$date • $time', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                                const SizedBox(height: 4),
                                Text(location, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 12),
                                Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                  Text('$participants/$maxParticipants',
                                      style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600)),
                                  Text('Entry: $entryFee EGP', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                                  Text('Prize: $prize EGP', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
                                ]),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: maxParticipants > 0 ? participants / maxParticipants : 0,
                                  backgroundColor: Colors.white.withOpacity(0.1),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF14B8A6)),
                                ),
                                const SizedBox(height: 6),
                                Text('${maxParticipants - participants} spots left',
                                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7))),
                              ],
                            )),
                          )),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Builder(builder: (context) {
                              final hasStarted = ['phase1', 'phase2', 'knockout', 'completed', 'groups'].contains(tournamentStatus);
                              return Column(children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  if (isParentTournament || !hasStarted)
                                    Expanded(child: GestureDetector(
                                      onTap: () async {
                                        if (isParentTournament) {
                                          _showWeeklyTournamentsFromHome(context, parentTournamentId ?? doc.id, name);
                                          return;
                                        }
                                        final loggedIn = await requireLogin(context);
                                        if (loggedIn && mounted) {
                                          Navigator.push(context, MaterialPageRoute(
                                              builder: (context) => TournamentJoinScreen(
                                                  tournamentId: doc.id, tournamentName: name, tournamentImageUrl: imageUrl)));
                                        }
                                      },
                                      child: Container(
                                        height: 44, alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(color: const Color(0xFF1E3A8A), borderRadius: BorderRadius.circular(22)),
                                        child: Text(isParentTournament ? 'View Weekly Tournaments' : 'Join Tournament',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                                      ),
                                    )),
                                  if (!isParentTournament && hasStarted)
                                    Expanded(child: GestureDetector(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(
                                          builder: (context) => TournamentDashboardScreen(
                                              tournamentId: doc.id, tournamentName: name))),
                                      child: Container(
                                        height: 44, alignment: Alignment.center,
                                        decoration: BoxDecoration(color: Colors.green[600], borderRadius: BorderRadius.circular(22)),
                                        child: const Icon(Icons.leaderboard, color: Colors.white, size: 22),
                                      ),
                                    )),
                                ]),
                                const SizedBox(height: 4),
                                Text(
                                  isParentTournament ? 'Tap for weekly list' : hasStarted ? 'Tap 📊 for results' : 'Tap to join',
                                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7), fontStyle: FontStyle.italic),
                                  textAlign: TextAlign.center,
                                ),
                              ]);
                            }),
                          ),
                        ]),
                      ),
                    );
                  },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DATE DISPLAY
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildDateDisplayWithCalendar(DateTime? currentSelectedDate) {
    final displayDate = currentSelectedDate ?? DateTime.now();
    final today = DateTime.now();
    final isToday = displayDate.year == today.year && displayDate.month == today.month && displayDate.day == today.day;
    const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 1))],
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today, size: 20, color: Color(0xFF14B8A6)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(isToday ? 'Today' : dayNames[displayDate.weekday - 1],
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
              const SizedBox(height: 2),
              Text('${monthNames[displayDate.month - 1]} ${displayDate.day}, ${displayDate.year}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            ]),
          ]),
        )),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF14B8A6), borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: const Color(0xFF14B8A6).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: currentSelectedDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) _selectedDateNotifier.value = picked;
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(padding: const EdgeInsets.all(16),
                  child: const Icon(Icons.calendar_month, color: Colors.white, size: 24)),
            ),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // VENUE / SLOT WIDGETS
  // ══════════════════════════════════════════════════════════════════════════
  List<Widget> _buildVenueSlotChildren(String venueName, List<Map<String, String>> sortedSlots,
      Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    if (sortedSlots.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(16),
          child: Center(child: Text('No slots available for this venue', style: TextStyle(color: Colors.grey))))];
    }
    return sortedSlots.map((slot) {
      final time = slot['time'] ?? '';
      final coach = slot['coach'] ?? '';
      return _buildSlotWidget(venueName, time, coach,
          _getSlotBookingCount(venueName, time, slotCounts, currentSelectedDate), currentSelectedDate);
    }).toList();
  }

  Widget _buildSlotWidget(String venueName, String time, String coach, int bookingCount, DateTime? currentSelectedDate) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: StreamBuilder<bool>(
        stream: currentSelectedDate != null
            ? _isSlotBlockedStream(venueName, time, _getDayName(currentSelectedDate))
            : Stream.value(false),
        builder: (context, blockedSnapshot) {
          final isBlocked = blockedSnapshot.data ?? false;
          return FutureBuilder<Map<String, dynamic>>(
            future: Future.wait([_getMaxUsersPerSlot(), _getRecurringBookingDays(venueName, time)])
                .then((r) => {'maxUsers': r[0] as int, 'recurringDays': r[1] as Map<String, bool>})
                .catchError((_) => {'maxUsers': 4, 'recurringDays': <String, bool>{'Sunday': false, 'Tuesday': false}}),
            builder: (context, snapshot) {
              int maxUsersPerSlot = isBlocked ? 0 : (snapshot.data?['maxUsers'] as int? ?? 4);
              final recurringDays = snapshot.data?['recurringDays'] as Map<String, bool>? ?? {};
              final isFull = isBlocked || bookingCount >= maxUsersPerSlot;
              final spotsAvailable = isBlocked ? 0 : (maxUsersPerSlot - bookingCount);
              final hasSundayBooking = recurringDays['Sunday'] ?? false;
              final hasTuesdayBooking = recurringDays['Tuesday'] ?? false;
              final isLoading = snapshot.connectionState == ConnectionState.waiting;

              List<Color> gradientColors;
              String statusText;
              Color statusColor;
              if (isBlocked) {
                gradientColors = [const Color(0xFF1A1F3A), const Color(0xFF2D1B3D)];
                statusText = 'Booked'; statusColor = Colors.red;
              } else if (spotsAvailable <= 1 && spotsAvailable > 0) {
                gradientColors = [const Color(0xFF1E3A8A), const Color(0xFFFF9800)];
                statusText = 'Few Spots Left'; statusColor = Colors.orange;
              } else if (bookingCount >= maxUsersPerSlot * 0.7) {
                gradientColors = [const Color(0xFF6B46C1), const Color(0xFF9333EA)];
                statusText = 'Popular'; statusColor = Colors.purple;
              } else {
                gradientColors = [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)];
                statusText = 'Book'; statusColor = Colors.green;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradientColors),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          if (isLoading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          Flexible(child: Text(time,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis, maxLines: 1)),
                          if (hasSundayBooking || hasTuesdayBooking) ...[
                            const SizedBox(width: 8),
                            Wrap(spacing: 4, children: [
                              if (hasSundayBooking) Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(10)),
                                child: const Text('Sun', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange))),
                              if (hasTuesdayBooking) Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.purple[100], borderRadius: BorderRadius.circular(10)),
                                child: const Text('Tue', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.purple))),
                            ]),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          currentSelectedDate != null
                              ? (isBlocked ? 'Booked - Not available on ${_getDayName(currentSelectedDate)}'
                                  : isFull ? 'Full ($bookingCount/$maxUsersPerSlot)'
                                  : '$spotsAvailable spot${spotsAvailable != 1 ? 's' : ''} available ($bookingCount/$maxUsersPerSlot)')
                              : 'Select a date to see availability',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis, maxLines: 1,
                        ),
                        if (hasSundayBooking || hasTuesdayBooking) ...[
                          const SizedBox(height: 4),
                          Text(
                            hasSundayBooking && hasTuesdayBooking ? 'Recurring: Every Sunday & Tuesday'
                                : hasSundayBooking ? 'Recurring: Every Sunday' : 'Recurring: Every Tuesday',
                            style: TextStyle(fontSize: 11, color: Colors.blue[700], fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    )),
                    const SizedBox(width: 8),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (isBlocked || isFull || spotsAvailable <= 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor, width: 1.5)),
                          child: Text(statusText,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor))),
                      if (!isBlocked && !isFull)
                        ElevatedButton(
                          onPressed: () => _handleBooking(venueName, time, coach),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green, foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: const Text('Book', style: TextStyle(fontWeight: FontWeight.bold))),
                    ]),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  DateTime? _parseTimeString(String timeStr) {
    try {
      final parts = timeStr.split(' - ');
      if (parts.isEmpty) return null;
      final timeParts = parts[0].trim().split(' ');
      if (timeParts.length < 2) return null;
      final hourMinute = timeParts[0].split(':');
      if (hourMinute.length != 2) return null;
      int hour = int.parse(hourMinute[0]);
      final minute = int.parse(hourMinute[1]);
      final period = timeParts[1].toUpperCase();
      if (period == 'PM' && hour != 12) hour += 12;
      else if (period == 'AM' && hour == 12) hour = 0;
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (e) { return null; }
  }

  Widget _buildExpandableVenue(String venueName, List<Map<String, String>> timeSlots,
      Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    final isExpanded = _expandedVenues.contains(venueName);
    var sortedSlots = List<Map<String, String>>.from(timeSlots)
      ..sort((a, b) {
        final pa = _parseTimeString(a['time'] ?? '');
        final pb = _parseTimeString(b['time'] ?? '');
        if (pa == null && pb == null) return 0;
        if (pa == null) return 1;
        if (pb == null) return -1;
        return pa.compareTo(pb);
      });

    if (currentSelectedDate != null && _isToday(currentSelectedDate)) {
      final now = DateTime.now();
      sortedSlots = sortedSlots.where((slot) {
        final p = _parseTimeString(slot['time'] ?? '');
        if (p == null) return true;
        final slotDateTime = DateTime(now.year, now.month, now.day, p.hour, p.minute);
        return slotDateTime.isAfter(now) || slotDateTime.isAtSameMomentAs(now);
      }).toList();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A), borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        InkWell(
          onTap: () {
            if (!mounted) return;
            setState(() {
              if (_expandedVenues.contains(venueName)) _expandedVenues.remove(venueName);
              else _expandedVenues.add(venueName);
            });
          },
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
                const Color(0xFF6B46C1).withOpacity(0.3), const Color(0xFF1E3A8A).withOpacity(0.3)]),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.location_on, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(venueName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('${sortedSlots.length} time slot${sortedSlots.length != 1 ? 's' : ''} available',
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
              ])),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white),
            ]),
          ),
        ),
        if (isExpanded)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0A0E27),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            ),
            child: Column(children: _buildVenueSlotChildren(venueName, sortedSlots, slotCounts, currentSelectedDate)),
          ),
      ]),
    );
  }

  Widget buildVenue(String venueName, List<Map<String, String>> timeSlots,
      Map<String, int> slotCounts, DateTime? currentSelectedDate) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(venueName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...timeSlots.map((slot) {
            final time = slot['time'] ?? '';
            final coach = slot['coach'] ?? '';
            final bookingCount = _getSlotBookingCount(venueName, time, slotCounts, currentSelectedDate);
            int maxUsersPerSlot = 4;
            return FutureBuilder<int>(
              future: _getMaxUsersPerSlot(),
              builder: (context, maxSnapshot) {
                if (maxSnapshot.hasData) maxUsersPerSlot = maxSnapshot.data!;
                final isFull = bookingCount >= maxUsersPerSlot;
                final spotsAvailable = maxUsersPerSlot - bookingCount;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isFull ? Colors.grey[200] : Colors.white,
                      border: Border.all(color: isFull ? Colors.grey[400]! : Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(time, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500,
                            color: isFull ? Colors.grey[600] : Colors.black)),
                        const SizedBox(height: 4),
                        Text(coach, style: TextStyle(fontSize: 14, color: isFull ? Colors.grey[500] : Colors.grey[600])),
                        const SizedBox(height: 4),
                        Text(isFull ? 'Full ($bookingCount/$maxUsersPerSlot)' : '$spotsAvailable spot${spotsAvailable != 1 ? 's' : ''} available ($bookingCount/$maxUsersPerSlot)',
                            style: TextStyle(fontSize: 12, color: isFull ? Colors.red : Colors.green[700], fontWeight: FontWeight.w500)),
                      ])),
                      if (isFull)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(20)),
                            child: const Text('Full', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red)))
                      else
                        ElevatedButton(
                          onPressed: () => _handleBooking(venueName, time, coach),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                          child: const Text('Book')),
                    ]),
                  ),
                );
              },
            );
          }),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRAINING OPTIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTrainingOptionsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We train all styles.',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _buildTrainingCard(title: 'Group Training', icon: Icons.people,
                description1: 'Train with other players', description2: 'Social & competitive', color: const Color(0xFF3B82F6))),
            const SizedBox(width: 12),
            Expanded(child: _buildTrainingCard(title: 'Private Training', icon: Icons.person,
                description1: '1-on-1 coaching session', description2: 'With a certified coach', color: const Color(0xFF8B5CF6))),
            const SizedBox(width: 12),
            Expanded(child: _buildTrainingCard(title: 'Pro Training', icon: Icons.emoji_events,
                description1: 'Train like the pros', description2: 'Elevate your game', color: const Color(0xFFF59E0B))),
          ]),
        ],
      ),
    );
  }

  Widget _buildTrainingCard({required String title, required IconData icon,
      required String description1, required String description2, required Color color}) {
    return Container(
      height: 192, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          Icon(icon, color: color, size: 32),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(description1, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(description2, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildAssetImage(String imagePath, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
    if (imagePath.isEmpty) {
      return Container(width: width, height: height, color: const Color(0xFF1E3A8A),
          child: const Icon(Icons.emoji_events, color: Colors.white, size: 48));
    }
    String path = imagePath.trim();
    if (path.startsWith('/')) path = path.substring(1);
    if (!path.startsWith('assets/')) {
      path = path.startsWith('images/') ? 'assets/$path' : 'assets/images/$path';
    }
    return Image.asset(path, width: width, height: height, fit: fit,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Failed to load asset image: $path');
          return Container(width: width, height: height, color: const Color(0xFF1E3A8A),
              child: const Icon(Icons.emoji_events, color: Colors.white, size: 48));
        });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MANAGE TOURNAMENTS DIALOG (admin)
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _showManageTournamentsDialog() async {
    try {
      final tournamentsSnapshot = await FirebaseFirestore.instance
          .collection('tournaments').orderBy('name').get();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Manage Upcoming Tournaments'),
            content: SizedBox(
              width: double.maxFinite, height: 500,
              child: tournamentsSnapshot.docs.isEmpty
                  ? const Center(child: Text('No tournaments found'))
                  : ListView.builder(
                      itemCount: tournamentsSnapshot.docs.length,
                      itemBuilder: (context, index) {
                        final doc = tournamentsSnapshot.docs[index];
                        final data = doc.data();
                        final name = data['name'] as String? ?? 'Unknown';
                        final isParent = data['isParentTournament'] as bool? ?? false;
                        final isArchived = data['isArchived'] as bool? ?? false;
                        final isHidden = data['hidden'] as bool? ?? false;
                        final showOnHomePage = data['showOnHomePage'] as bool? ?? true;
                        String statusLabel = '';
                        Color? statusColor;
                        if (isArchived) { statusLabel = 'Archived'; statusColor = Colors.grey; }
                        else if (isHidden) { statusLabel = 'Hidden'; statusColor = Colors.orange; }
                        return CheckboxListTile(
                          title: Row(children: [
                            Expanded(child: Text(name, style: TextStyle(
                                fontWeight: FontWeight.w600, color: showOnHomePage ? Colors.black : Colors.grey))),
                            if (isParent) Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.purple[100], borderRadius: BorderRadius.circular(4)),
                              child: Text('Parent', style: TextStyle(fontSize: 10, color: Colors.purple[900], fontWeight: FontWeight.bold))),
                            if (statusLabel.isNotEmpty) Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: statusColor?.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                              child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold))),
                          ]),
                          value: showOnHomePage,
                          onChanged: isArchived || isHidden ? null : (bool? value) async {
                            if (value != null) {
                              try {
                                await FirebaseFirestore.instance
                                    .collection('tournaments').doc(doc.id).update({'showOnHomePage': value});
                                setDialogState(() {});
                              } catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                              }
                            }
                          },
                          secondary: Icon(isParent ? Icons.folder : Icons.emoji_events,
                              color: showOnHomePage ? const Color(0xFF1E3A8A) : Colors.grey),
                        );
                      },
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading tournaments: $e'), backgroundColor: Colors.red));
    }
  }
}
