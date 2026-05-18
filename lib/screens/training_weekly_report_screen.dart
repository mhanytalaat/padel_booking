import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/bundle_model.dart';
import '../widgets/app_header.dart';
import '../widgets/app_footer.dart';

// ─── Report mode ──────────────────────────────────────────────────────────────
enum _ReportMode { weekly, monthly }

// ─── Court rental cost config ────────────────────────────────────────────────
class _CourtCostConfig {
  static double costPerHour(String venue, int hour24) {
    final v = venue.toLowerCase();
    if (v.contains('club 13') || v.contains('club13')) {
      if (hour24 >= 8 && hour24 < 18) return 300;
      if (hour24 >= 18 && hour24 < 22) return 450;
      return 300;
    } else if (v.contains('pyramid')) {
      if (hour24 >= 8 && hour24 < 16) return 300;
      if (hour24 >= 16 && hour24 < 19) return 350;
      if (hour24 >= 19 && hour24 < 22) return 400;
      return 300;
    } else if (v.contains('avenue')) {
      return 250;
    }
    return 0;
  }

  static int parseHour(String time) {
    try {
      final t = time.trim();
      final colonIdx = t.indexOf(':');
      if (colonIdx < 0) return 0;
      int hour = int.parse(t.substring(0, colonIdx));
      final rest = t.substring(colonIdx + 1).trim().toUpperCase();
      if (rest.contains('PM') && hour != 12) hour += 12;
      if (rest.contains('AM') && hour == 12) hour = 0;
      return hour;
    } catch (_) {
      return 0;
    }
  }

  static String displayName(String venue) {
    final v = venue.toLowerCase();
    if (v.contains('club 13') || v.contains('club13')) return 'Club 13';
    if (v.contains('pyramid')) return 'Pyramids Heights';
    if (v.contains('avenue')) return 'Padel Avenue';
    return venue;
  }

  static String rateDescription(String venue) {
    final v = venue.toLowerCase();
    if (v.contains('club 13') || v.contains('club13')) {
      return '8AM–6PM: 300 LE  |  6PM–10PM: 450 LE';
    } else if (v.contains('pyramid')) {
      return '8AM–4PM: 300 LE  |  4PM–7PM: 350 LE  |  7PM–10PM: 400 LE';
    } else if (v.contains('avenue')) {
      return 'Flat 250 LE/hr';
    }
    return '';
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _EnrichedSession {
  final BundleSession session;
  final TrainingBundle? bundle;
  _EnrichedSession(this.session, this.bundle);

  double get perSessionIncome {
    if (bundle == null || bundle!.totalSessions <= 0) return 0;
    return bundle!.price / bundle!.totalSessions;
  }

  double get courtCost {
    final hour = _CourtCostConfig.parseHour(session.time);
    return _CourtCostConfig.costPerHour(session.venue, hour);
  }

  double get net => perSessionIncome - courtCost;
}

class _GroupStats {
  final String name;
  int sessions = 0;
  double income = 0;
  double courtCost = 0;
  _GroupStats(this.name);
  double get net => income - courtCost;
  double get avgNet => sessions > 0 ? net / sessions : 0;
}

class _BundleStats {
  final TrainingBundle bundle;
  final List<_EnrichedSession> sessions;
  _BundleStats(this.bundle, this.sessions);

  double get perSessionIncome =>
      bundle.totalSessions > 0 ? bundle.price / bundle.totalSessions : 0;
  double get periodIncome => perSessionIncome * sessions.length;
  double get periodCourtCost =>
      sessions.fold(0.0, (acc, s) => acc + s.courtCost);
  double get periodNet => periodIncome - periodCourtCost;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class TrainingWeeklyReportScreen extends StatefulWidget {
  const TrainingWeeklyReportScreen({super.key});

  @override
  State<TrainingWeeklyReportScreen> createState() =>
      _TrainingWeeklyReportScreenState();
}

class _TrainingWeeklyReportScreenState
    extends State<TrainingWeeklyReportScreen> {
  _ReportMode _mode = _ReportMode.weekly;
  late DateTime _weekStart;
  late DateTime _selectedMonth;
  bool _isLoading = false;
  List<_EnrichedSession> _sessions = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = _mondayOf(now);
    _selectedMonth = DateTime(now.year, now.month);
    _loadData();
  }

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  DateTime get _periodStart =>
      _mode == _ReportMode.weekly ? _weekStart : _selectedMonth;

  DateTime get _periodEnd => _mode == _ReportMode.weekly
      ? _weekStart.add(const Duration(days: 6))
      : DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

  String get _periodLabel {
    if (_mode == _ReportMode.weekly) {
      return '${DateFormat('MMM d').format(_periodStart)} – '
          '${DateFormat('MMM d, yyyy').format(_periodEnd)}';
    }
    return DateFormat('MMMM yyyy').format(_selectedMonth);
  }

  void _prev() {
    setState(() {
      if (_mode == _ReportMode.weekly) {
        _weekStart = _weekStart.subtract(const Duration(days: 7));
      } else {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      }
    });
    _loadData();
  }

  void _next() {
    setState(() {
      if (_mode == _ReportMode.weekly) {
        _weekStart = _weekStart.add(const Duration(days: 7));
      } else {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      }
    });
    _loadData();
  }

  // ── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_periodStart);
      final endStr = DateFormat('yyyy-MM-dd').format(_periodEnd);

      final snap = await FirebaseFirestore.instance
          .collection('bundleSessions')
          .where('date', isGreaterThanOrEqualTo: startStr)
          .where('date', isLessThanOrEqualTo: endStr)
          .get();

      final raw = snap.docs
          .map((d) => BundleSession.fromFirestore(d))
          .where((s) => s.attendanceStatus == 'attended')
          .toList()
        ..sort((a, b) {
          final c = a.date.compareTo(b.date);
          return c != 0 ? c : a.sessionNumber.compareTo(b.sessionNumber);
        });

      // Batch-fetch parent bundles
      final ids = raw.map((s) => s.bundleId).toSet().toList();
      final bundleMap = <String, TrainingBundle>{};
      for (int i = 0; i < ids.length; i += 10) {
        final batch = ids.skip(i).take(10).toList();
        final bSnap = await FirebaseFirestore.instance
            .collection('bundles')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in bSnap.docs) {
          bundleMap[doc.id] = TrainingBundle.fromFirestore(doc);
        }
      }

      if (mounted) {
        setState(() {
          _sessions =
              raw.map((s) => _EnrichedSession(s, bundleMap[s.bundleId])).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── Roll-ups ────────────────────────────────────────────────────────────────

  double get _totalIncome =>
      _sessions.fold(0.0, (acc, s) => acc + s.perSessionIncome);
  double get _totalCost =>
      _sessions.fold(0.0, (acc, s) => acc + s.courtCost);
  double get _net => _totalIncome - _totalCost;

  Map<String, _GroupStats> _groupBy(String Function(_EnrichedSession) key) {
    final map = <String, _GroupStats>{};
    for (final es in _sessions) {
      final k = key(es);
      map.putIfAbsent(k, () => _GroupStats(k));
      map[k]!.sessions++;
      map[k]!.income += es.perSessionIncome;
      map[k]!.courtCost += es.courtCost;
    }
    return map;
  }

  Map<String, _GroupStats> get _locationStats => _groupBy(
      (es) => _CourtCostConfig.displayName(es.session.venue));

  Map<String, _GroupStats> get _coachStats =>
      _groupBy((es) => es.session.coach.isNotEmpty ? es.session.coach : '—');

  List<_BundleStats> get _bundleStats {
    final map = <String, List<_EnrichedSession>>{};
    for (final es in _sessions) {
      map.putIfAbsent(es.session.bundleId, () => []).add(es);
    }
    return map.entries
        .where((e) => e.value.first.bundle != null)
        .map((e) => _BundleStats(e.value.first.bundle!, e.value))
        .toList()
      ..sort((a, b) => b.periodIncome.compareTo(a.periodIncome));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppHeader(title: 'Training Report'),
      bottomNavigationBar: const AppFooter(selectedIndex: 1),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModeToggle(),
                    const SizedBox(height: 12),
                    _buildPeriodSelector(),
                    const SizedBox(height: 20),
                    _buildSummaryRow(),
                    const SizedBox(height: 12),
                    _buildNetBanner(),
                    const SizedBox(height: 20),
                    _buildGroupSection(
                      icon: Icons.location_city,
                      title: 'By Location',
                      subtitle: 'Court costs vs. income per venue',
                      stats: _locationStats,
                      showRate: true,
                    ),
                    const SizedBox(height: 16),
                    _buildGroupSection(
                      icon: Icons.person,
                      title: 'By Coach',
                      subtitle: 'Sessions, income and net per coach',
                      stats: _coachStats,
                      showRate: false,
                      accentColor: Colors.purple,
                    ),
                    const SizedBox(height: 16),
                    _buildBundleSection(),
                    const SizedBox(height: 16),
                    if (_sessions.isNotEmpty) _buildSessionsList(),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Mode toggle ──────────────────────────────────────────────────────────────

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _modeBtn('Weekly', _ReportMode.weekly),
          _modeBtn('Monthly', _ReportMode.monthly),
        ],
      ),
    );
  }

  Widget _modeBtn(String label, _ReportMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_mode != mode) {
            setState(() => _mode = mode);
            _loadData();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1E3A8A) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              )),
        ),
      ),
    );
  }

  // ── Period navigator ─────────────────────────────────────────────────────────

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: _prev),
          Expanded(
            child: Column(children: [
              Text(_mode == _ReportMode.weekly ? 'Week' : 'Month',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11)),
              Text(_periodLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.white),
              onPressed: _next),
        ],
      ),
    );
  }

  // ── Summary row (4 compact tiles) ───────────────────────────────────────────

  Widget _buildSummaryRow() {
    return Row(
      children: [
        _statTile('Sessions', '${_sessions.length}', Icons.sports_tennis,
            Colors.blue),
        const SizedBox(width: 10),
        _statTile('Hours', '${_sessions.length} hr', Icons.schedule,
            Colors.indigo),
        const SizedBox(width: 10),
        _statTile('Income', '${_totalIncome.toStringAsFixed(0)} LE',
            Icons.payments_outlined, Colors.green),
        const SizedBox(width: 10),
        _statTile('Court Cost', '${_totalCost.toStringAsFixed(0)} LE',
            Icons.sports_score, Colors.orange),
      ],
    );
  }

  Widget _statTile(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color)),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // ── Net banner ────────────────────────────────────────────────────────────────

  Widget _buildNetBanner() {
    final isPositive = _net >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF065F46), const Color(0xFF10B981)]
              : [const Color(0xFF7F1D1D), const Color(0xFFEF4444)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Icon(isPositive ? Icons.trending_up : Icons.trending_down,
              color: Colors.white, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Net Profit  (Income − Court Costs)',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text(
                  '${_net >= 0 ? '+' : ''}${_net.toStringAsFixed(0)} LE',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          if (_sessions.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    '${(_net / _sessions.length).toStringAsFixed(0)} LE',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                  const Text('per session',
                      style: TextStyle(color: Colors.white70, fontSize: 9)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Generic group section (location & coach share same widget) ───────────────

  Widget _buildGroupSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Map<String, _GroupStats> stats,
    required bool showRate,
    Color accentColor = const Color(0xFF1E3A8A),
  }) {
    // Sort by sessions descending
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.sessions.compareTo(a.value.sessions));
    final double maxSessions =
        sorted.isEmpty ? 1.0 : sorted.first.value.sessions.toDouble();

    return _card(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentColor: accentColor,
      child: stats.isEmpty
          ? _emptyHint('No sessions this period')
          : Column(
              children: [
                ...sorted.map((e) => _groupRow(
                      e.value,
                      maxSessions: maxSessions,
                      showRate: showRate
                          ? _CourtCostConfig.rateDescription(e.key)
                          : null,
                      barColor: accentColor,
                    )),
                if (sorted.length > 1) ...[
                  const Divider(height: 20),
                  _totalsRow(
                    income: _totalIncome,
                    cost: _totalCost,
                    net: _net,
                    sessions: _sessions.length,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _groupRow(
    _GroupStats s, {
    required double maxSessions,
    String? showRate,
    Color barColor = const Color(0xFF1E3A8A),
  }) {
    final barFraction = maxSessions > 0 ? s.sessions / maxSessions : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + session count
          Row(
            children: [
              Expanded(
                child: Text(s.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Text('${s.sessions} hr',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 5),
          // Proportional bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: barFraction,
              minHeight: 5,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                  barColor.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(height: 8),
          // Financial chips
          Row(
            children: [
              _chip('${s.income.toStringAsFixed(0)} LE', 'Income',
                  Colors.green),
              const SizedBox(width: 6),
              _chip('${s.courtCost.toStringAsFixed(0)} LE', 'Court',
                  Colors.orange),
              const SizedBox(width: 6),
              _chip('${s.net >= 0 ? '+' : ''}${s.net.toStringAsFixed(0)} LE',
                  'Net', s.net >= 0 ? Colors.teal : Colors.red,
                  bold: true),
              const Spacer(),
              // Avg per session
              Text('avg ${s.avgNet.toStringAsFixed(0)} LE/s',
                  style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            ],
          ),
          if (showRate != null && showRate.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(showRate,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _totalsRow({
    required double income,
    required double cost,
    required double net,
    required int sessions,
  }) {
    return Row(
      children: [
        const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        _chip('${income.toStringAsFixed(0)} LE', 'Income', Colors.green),
        const SizedBox(width: 6),
        _chip('${cost.toStringAsFixed(0)} LE', 'Court', Colors.orange),
        const SizedBox(width: 6),
        _chip('${net >= 0 ? '+' : ''}${net.toStringAsFixed(0)} LE', 'Net',
            net >= 0 ? Colors.teal : Colors.red,
            bold: true),
      ],
    );
  }

  // ── Bundle breakdown ─────────────────────────────────────────────────────────

  Widget _buildBundleSection() {
    final bundles = _bundleStats;
    return _card(
      icon: Icons.card_membership,
      title: 'By Player / Bundle',
      subtitle: 'Pro-rated: price paid ÷ total sessions',
      child: bundles.isEmpty
          ? _emptyHint('No sessions this period')
          : Column(
              children: bundles.map((bs) => _bundleRow(bs)).toList(),
            ),
    );
  }

  Widget _bundleRow(_BundleStats bs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor:
                    const Color(0xFF1E3A8A).withValues(alpha: 0.12),
                child: Text('${bs.bundle.bundleType}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E3A8A),
                        fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bs.bundle.userName,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      '${bs.bundle.bundleType} sessions · '
                      'paid ${bs.bundle.price.toStringAsFixed(0)} LE · '
                      '${bs.perSessionIncome.toStringAsFixed(0)} LE/session',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              // Session count badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${bs.sessions.length} sess.',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('${bs.periodIncome.toStringAsFixed(0)} LE', 'Income',
                  Colors.green),
              const SizedBox(width: 6),
              _chip('${bs.periodCourtCost.toStringAsFixed(0)} LE', 'Court',
                  Colors.orange),
              const SizedBox(width: 6),
              _chip(
                  '${bs.periodNet >= 0 ? '+' : ''}${bs.periodNet.toStringAsFixed(0)} LE',
                  'Net',
                  bs.periodNet >= 0 ? Colors.teal : Colors.red,
                  bold: true),
            ],
          ),
        ],
      ),
    );
  }

  // ── Session list ─────────────────────────────────────────────────────────────

  Widget _buildSessionsList() {
    return _card(
      icon: Icons.list_alt,
      title: 'Attended Sessions (${_sessions.length})',
      child: Column(
        children: _sessions.map((es) => _sessionRow(es)).toList(),
      ),
    );
  }

  Widget _sessionRow(_EnrichedSession es) {
    final s = es.session;
    DateTime? parsed;
    try {
      parsed = DateTime.parse(s.date);
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session number + date column
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${s.sessionNumber}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date + venue + time
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        parsed != null
                            ? DateFormat('EEE, MMM d').format(parsed)
                            : s.date,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    // Coach chip
                    if (s.coach.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(s.coach,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.purple,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${_CourtCostConfig.displayName(s.venue)}  •  ${s.time}'
                  '${es.bundle?.userName != null ? '  •  ${es.bundle!.userName}' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  children: [
                    _tinyChip(
                        '${es.perSessionIncome.toStringAsFixed(0)} LE',
                        'income',
                        Colors.green),
                    _tinyChip('${es.courtCost.toStringAsFixed(0)} LE',
                        'court', Colors.orange),
                    _tinyChip(
                        '${es.net >= 0 ? '+' : ''}${es.net.toStringAsFixed(0)} LE',
                        'net',
                        es.net >= 0 ? Colors.teal : Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared chip widgets ───────────────────────────────────────────────────────

  Widget _chip(String value, String label, Color color,
      {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.w600,
                  color: color)),
          Text(label,
              style: TextStyle(fontSize: 9, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _tinyChip(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
                text: value,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color)),
            TextSpan(
                text: ' $label',
                style: TextStyle(
                    fontSize: 9, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // ── Card wrapper ─────────────────────────────────────────────────────────────

  Widget _card({
    required IconData icon,
    required String title,
    String? subtitle,
    Color accentColor = const Color(0xFF1E3A8A),
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: accentColor),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style:
                      const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            const Divider(height: 18),
            child,
          ],
        ),
      ),
    );
  }

  Widget _emptyHint(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(text, style: const TextStyle(color: Colors.grey)),
        ),
      );
}
