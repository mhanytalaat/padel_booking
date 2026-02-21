/// Utilities for building knockout brackets with BYE support and proper seeding.
/// Top seeds get byes when odd number of teams. Seed 1 at top, Seed 2 at bottom (meet in final).

class KnockoutBracketUtils {
  /// Level order for consistent display (matches tournament_dashboard)
  static const levelOrder = ['C+', 'C-', 'D', 'Beginners', 'Seniors', 'Mix Doubles', 'Mix/Family Doubles', 'Women'];

  static int _levelIndex(String level) {
    final i = levelOrder.indexOf(level);
    return i >= 0 ? i : 999;
  }

  static List<String> sortLevels(List<String> levels) {
    return List<String>.from(levels)
      ..sort((a, b) {
        if (a == 'All levels') return 1;
        if (b == 'All levels') return -1;
        return _levelIndex(a).compareTo(_levelIndex(b));
      });
  }

  /// Expected group name format: "(level) - Group (number)", e.g. "D - Group 1", "Beginners - Group 2".
  /// Level is inferred from the part before the dash when 'level' is not stored on the group.

  /// Normalize to "Level - Group N" (single space around dash) for consistent lookup.
  static String normalizeGroupName(String name) {
    final t = name.trim();
    if (t.isEmpty) return t;
    return t.replaceAll(RegExp(r'\s*-\s*'), ' - ');
  }

  /// Extract level from a group name in format "Level - Group N" or "Level - group N".
  static String? levelFromGroupName(String groupName) {
    final match = RegExp(r'^(.+?)\s*-\s*(?:[Gg]roup\s*\d+|\d+)\s*$').firstMatch(groupName.trim());
    if (match != null) return match.group(1)?.trim();
    if (groupName.contains(' - ')) {
      final before = groupName.split(' - ').first.trim();
      if (before.isNotEmpty) return before;
    }
    final dash = RegExp(r'^(.+?)\s*-\s*').firstMatch(groupName.trim());
    return dash?.group(1)?.trim();
  }

  /// Group names by level from groups map. Returns level -> list of group names (normalized for consistent lookup).
  static Map<String, List<String>> groupGroupsByLevel(Map<String, dynamic> groups) {
    final byLevel = <String, List<String>>{};
    for (final groupName in groups.keys) {
      final name = normalizeGroupName(groupName?.toString() ?? '');
      if (name.isEmpty) continue;
      final groupValue = groups[groupName];
      String levelLabel = 'All levels';
      if (groupValue is Map) {
        final level = (groupValue as Map<String, dynamic>)['level']?.toString()?.trim();
        if (level != null && level.isNotEmpty) {
          levelLabel = level;
        }
      }
      if (levelLabel == 'All levels') {
        final inferred = levelFromGroupName(name);
        if (inferred != null && inferred.isNotEmpty) levelLabel = inferred;
      }
      byLevel.putIfAbsent(levelLabel, () => []).add(name);
    }
    for (final list in byLevel.values) {
      list.sort((a, b) {
        final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (numA != numB) return numA.compareTo(numB);
        return a.compareTo(b);
      });
    }
    return byLevel;
  }

  /// numByes = next power of 2 minus n (so bracket fills to power of 2)
  /// Uses (n-1).bitLength so powers of 2 get 0 byes correctly (e.g. n=4 → 0, n=3 → 1, n=5 → 3).
  static int _numByes(int n) {
    if (n <= 1) return 0;
    final nextPow2 = 1 << (n - 1).bitLength;
    return nextPow2 - n;
  }

  static bool _isPowerOfTwo(int n) => n > 0 && (n & (n - 1)) == 0;

  /// Standard seeded top-to-bottom order for power-of-two draws.
  /// Examples:
  /// 4  -> [1,4,3,2]
  /// 8  -> [1,8,5,4,3,6,7,2]
  /// 16 -> [1,16,9,8,5,12,13,4,3,14,11,6,7,10,15,2]
  /// 32/64 continue with the same pattern.
  /// Seed #1 stays at the very top and Seed #2 at the very bottom.
  static List<int> _seedOrderForPowerOfTwo(int size) {
    if (size <= 1) return const [1];
    if (!_isPowerOfTwo(size)) {
      throw ArgumentError('size must be a power of two');
    }

    List<int> build(int n) {
      if (n == 2) return <int>[1, 2];
      final previous = build(n ~/ 2);
      final out = <int>[];
      for (final seed in previous) {
        final opposite = n + 1 - seed;
        if (seed.isOdd) {
          out.add(seed);
          out.add(opposite);
        } else {
          out.add(opposite);
          out.add(seed);
        }
      }
      return out;
    }

    return build(size);
  }

  static String _roundNameForSize(int size) {
    if (size <= 2) return 'Final';
    if (size == 4) return 'Semi-Final';
    if (size == 8) return 'Quarter Final';
    return 'Round of $size';
  }

  /// Standardized round labels.
  /// Allowed sizes: 4, 8, 16, 32, 64, 128 plus Final.
  /// For non-standard match counts (legacy data), rounds are rounded up
  /// to the next standard draw size (e.g. 14 matches => Round of 32).
  static String standardizedRoundNameFromMatchCount(
    int matchCount, {
    String? fallbackRawName,
  }) {
    final drawSize = (matchCount <= 0) ? 2 : matchCount * 2;
    if (drawSize <= 2) return 'Final';
    if (drawSize == 4) return 'Semi-Final';
    if (drawSize == 8) return 'Quarter Final';
    const standard = <int>[4, 8, 16, 32, 64, 128];
    for (final size in standard) {
      if (drawSize <= size) return 'Round of $size';
    }
    final raw = fallbackRawName?.trim() ?? '';
    return raw.isNotEmpty ? raw : 'Round of 128';
  }

  static Map<String, dynamic> _seedSlot(int seed, int n) {
    final isBye = seed > n;
    return {
      'from': 'seed$seed',
      'type': 'seed',
      'teamKey': null,
      'teamName': isBye ? 'BYE' : null,
      'isBye': isBye,
    };
  }

  static bool _isByeSlot(Map<String, dynamic>? slot) {
    if (slot == null) return false;
    if (slot['isBye'] == true) return true;
    final name = slot['teamName']?.toString().trim().toUpperCase();
    if (name == 'BYE') return true;
    final from = slot['from']?.toString().trim().toUpperCase();
    return from == 'BYE';
  }

  static bool _hasTeam(Map<String, dynamic>? slot) {
    if (slot == null) return false;
    final key = slot['teamKey']?.toString().trim();
    if (key != null && key.isNotEmpty) return true;
    final name = slot['teamName']?.toString().trim();
    if (name != null && name.isNotEmpty && name.toUpperCase() != 'BYE') return true;
    return false;
  }

  /// Build round structure for n teams. Slots use seed1..seedN. At fill time, sort by points and assign.
  /// Seed 1 at top, Seed 2 at bottom -> meet in final. Byes go to top seeds.
  static List<Map<String, dynamic>> buildBracketWithByes(
    int n,
    String levelPrefix,
  ) {
    if (n <= 0) return [];
    if (n == 1) return [];
    final size = 1 << (n - 1).bitLength;
    final seedOrder = _seedOrderForPowerOfTwo(size);

    final rounds = <Map<String, dynamic>>[];
    final r1Matches = <Map<String, dynamic>>[];
    var prevIds = <String>[];
    for (int j = 0; j < size ~/ 2; j++) {
      final mId = '${levelPrefix}r1m${j + 1}';
      prevIds.add(mId);
      final seedA = seedOrder[2 * j];
      final seedB = seedOrder[2 * j + 1];
      r1Matches.add({
        'id': mId,
        'name': 'Match ${j + 1}',
        'team1': _seedSlot(seedA, n),
        'team2': _seedSlot(seedB, n),
        'schedule': {'court': '', 'date': '', 'startTime': '', 'endTime': ''},
        'winner': null,
      });
    }
    rounds.add({'name': _roundNameForSize(size), 'matches': r1Matches});

    var roundNum = 2;
    var roundSize = size;
    var prevCount = prevIds.length;
    while (prevCount > 1) {
      roundSize = roundSize ~/ 2;
      final nextCount = prevCount ~/ 2;
      final nextMatches = <Map<String, dynamic>>[];
      final nextIds = <String>[];
      for (int j = 0; j < nextCount; j++) {
        final mId = '${levelPrefix}r${roundNum}m${j + 1}';
        nextIds.add(mId);
        nextMatches.add({
          'id': mId,
          'name': nextCount == 1 ? 'Final' : 'Match ${j + 1}',
          'team1': {'from': prevIds[j * 2], 'type': 'winner', 'teamKey': null, 'teamName': null},
          'team2': {'from': prevIds[j * 2 + 1], 'type': 'winner', 'teamKey': null, 'teamName': null},
          'schedule': {'court': '', 'date': '', 'startTime': '', 'endTime': ''},
          'winner': null,
        });
      }
      rounds.add({'name': _roundNameForSize(roundSize), 'matches': nextMatches});
      prevIds = nextIds;
      prevCount = nextCount;
      roundNum++;
    }

    return rounds;
  }

  /// Apply BYE auto-advances for first round and propagate winners downstream.
  static void applyByesToRounds(List<Map<String, dynamic>> rounds) {
    if (rounds.isEmpty) return;
    final r1 = rounds.first;
    for (final m in r1['matches'] as List<dynamic>? ?? const []) {
      final match = m as Map<String, dynamic>;
      final t1 = match['team1'] as Map<String, dynamic>?;
      final t2 = match['team2'] as Map<String, dynamic>?;
      final bye1 = _isByeSlot(t1);
      final bye2 = _isByeSlot(t2);
      if (bye1 == bye2) continue;
      if (bye1 && _hasTeam(t2)) {
        match['winner'] = 'team2';
      } else if (bye2 && _hasTeam(t1)) {
        match['winner'] = 'team1';
      }
    }
    propagateWinners({'rounds': rounds});
  }

  /// Propagate match winners to downstream matches (e.g. semi-final winners -> final).
  /// Mutates the knockout map in place. Call after saving a match result.
  static void propagateWinners(Map<String, dynamic> knockout) {
    void processRounds(List<dynamic> rounds) {
      for (final r in rounds) {
        final roundMap = r as Map<String, dynamic>;
        for (final m in roundMap['matches'] as List<dynamic>? ?? []) {
          final match = m as Map<String, dynamic>;
          final winner = match['winner']?.toString();
          if (winner == null) continue;
          final t1 = match['team1'] as Map<String, dynamic>?;
          final t2 = match['team2'] as Map<String, dynamic>?;
          final winnerSlot = winner == 'team1' ? t1 : t2;
          final winnerKey = winnerSlot?['teamKey']?.toString();
          final winnerName = winnerSlot?['teamName']?.toString();
          if (winnerKey == null || winnerName == null) continue;
          final matchId = match['id']?.toString();
          if (matchId == null) continue;
          for (final r2 in rounds) {
            final roundMap2 = r2 as Map<String, dynamic>;
            for (final m2 in roundMap2['matches'] as List<dynamic>? ?? []) {
              final match2 = m2 as Map<String, dynamic>;
              if (match2['id']?.toString() == matchId) continue;
              for (final slotName in ['team1', 'team2']) {
                final slot = match2[slotName] as Map<String, dynamic>?;
                if (slot == null) continue;
                if (slot['from']?.toString() == matchId) {
                  slot['teamKey'] = winnerKey;
                  slot['teamName'] = winnerName;
                }
              }
            }
          }
        }
      }
    }

    final lb = knockout['levelBrackets'] as Map<String, dynamic>?;
    if (lb != null) {
      for (final level in lb.keys) {
        final rounds = lb[level] as List<dynamic>?;
        if (rounds != null) processRounds(rounds);
      }
    }

    final rounds = knockout['rounds'] as List<dynamic>?;
    if (rounds != null) processRounds(rounds);

    // Legacy: quarterFinals -> semiFinals -> final
    final qf = knockout['quarterFinals'] as List<dynamic>? ?? [];
    final sf = knockout['semiFinals'] as List<dynamic>? ?? [];
    final finalMatch = knockout['final'] as Map<String, dynamic>?;
    for (final m in qf) {
      final match = m as Map<String, dynamic>;
      final winner = match['winner']?.toString();
      if (winner == null) continue;
      final t1 = match['team1'] as Map<String, dynamic>?;
      final t2 = match['team2'] as Map<String, dynamic>?;
      final winnerSlot = winner == 'team1' ? t1 : t2;
      final winnerKey = winnerSlot?['teamKey']?.toString();
      final winnerName = winnerSlot?['teamName']?.toString();
      if (winnerKey == null || winnerName == null) continue;
      final matchId = match['id']?.toString();
      if (matchId == null) continue;
      for (final sfMatch in sf) {
        final sm = sfMatch as Map<String, dynamic>;
        for (final slotName in ['team1', 'team2']) {
          final slot = sm[slotName] as Map<String, dynamic>?;
          if (slot != null && slot['from']?.toString() == matchId) {
            slot['teamKey'] = winnerKey;
            slot['teamName'] = winnerName;
          }
        }
      }
    }
    for (final m in sf) {
      final match = m as Map<String, dynamic>;
      final winner = match['winner']?.toString();
      if (winner == null) continue;
      final t1 = match['team1'] as Map<String, dynamic>?;
      final t2 = match['team2'] as Map<String, dynamic>?;
      final winnerSlot = winner == 'team1' ? t1 : t2;
      final winnerKey = winnerSlot?['teamKey']?.toString();
      final winnerName = winnerSlot?['teamName']?.toString();
      if (winnerKey == null || winnerName == null) continue;
      final matchId = match['id']?.toString();
      if (matchId == null) continue;
      if (finalMatch != null && finalMatch.isNotEmpty) {
        for (final slotName in ['team1', 'team2']) {
          final slot = finalMatch[slotName] as Map<String, dynamic>?;
          if (slot != null && slot['from']?.toString() == matchId) {
            slot['teamKey'] = winnerKey;
            slot['teamName'] = winnerName;
          }
        }
      }
    }
  }

  /// Fill seed slots. Returns count filled.
  static int fillSeedSlots(List<Map<String, dynamic>> rounds, List<Map<String, dynamic>> advancingTeams) {
    int filled = 0;
    for (final round in rounds) {
      for (final m in round['matches'] as List) {
        final match = m as Map<String, dynamic>;
        for (final slotName in ['team1', 'team2']) {
          final slot = match[slotName] as Map<String, dynamic>?;
          if (slot == null) continue;
          final from = (slot['from'] ?? '').toString();
          if (from.startsWith('seed')) {
            final idx = int.tryParse(from.replaceFirst('seed', '')) ?? 0;
            if (idx >= 1 && idx <= advancingTeams.length) {
              final team = advancingTeams[idx - 1];
              slot['teamKey'] = team['teamKey'];
              slot['teamName'] = team['teamName'];
              filled++;
            }
          }
        }
      }
    }
    return filled;
  }
}

