import 'dart:async';

import 'package:flutter/material.dart';

/// Live-updating D/H/M/S countdown; hides itself when [target] is in the past.
class NextTournamentCountdownBanner extends StatefulWidget {
  final String tournamentName;
  final DateTime target;

  const NextTournamentCountdownBanner({
    super.key,
    required this.tournamentName,
    required this.target,
  });

  @override
  State<NextTournamentCountdownBanner> createState() => _NextTournamentCountdownBannerState();
}

class _NextTournamentCountdownBannerState extends State<NextTournamentCountdownBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = widget.target.difference(now);
    if (diff.isNegative) {
      return const SizedBox.shrink();
    }
    final days = diff.inDays;
    final hours = diff.inHours.remainder(24);
    final minutes = diff.inMinutes.remainder(60);
    final seconds = diff.inSeconds.remainder(60);

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF14B8A6).withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Next tournament',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.5,
              color: Colors.white.withOpacity(0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.tournamentName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _box(days, 'Days'),
              _box(hours, 'Hours'),
              _box(minutes, 'Min'),
              _box(seconds, 'Sec'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(int value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF232846),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF14B8A6),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
