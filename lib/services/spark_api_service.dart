import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../config/spark_config.dart';

/// Spark Platform external court booking API.
/// Matches Postman collection: External Integration.
class SparkApiService {
  SparkApiService._();
  static final SparkApiService instance = SparkApiService._();

  String get _base => SparkConfig.baseUrl.replaceAll(RegExp(r'/$'), '');

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-api-key': SparkConfig.apiKey,
    };
    if (SparkConfig.bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${SparkConfig.bearerToken}';
    }
    return headers;
  }

  bool get isEnabled => SparkConfig.isConfigured;

  /// POST /api/v1/external-bookings
  /// Body: { slotIds, firstName, lastName, phoneNumber }
  Future<SparkApiResult> createBooking({
    required List<String> slotIds,
    required String firstName,
    required String lastName,
    required String phoneNumber,
  }) async {
    if (!isEnabled) {
      return SparkApiResult.skipped(
        'Spark API not configured (set SPARK_API_KEY via --dart-define)',
      );
    }

    if (slotIds.isEmpty) {
      return SparkApiResult.skipped(
        'No slotIds to book (location may not have sparkLocationId mapping)',
      );
    }

    try {
      final body = {
        'slotIds': slotIds,
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phoneNumber,
      };

      final uri = Uri.parse('$_base/api/v1/external-bookings');
      final res = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
        return SparkApiResult.success(data: json);
      }

      return SparkApiResult.failure(
        statusCode: res.statusCode,
        body: res.body,
      );
    } catch (e, st) {
      return SparkApiResult.failure(
        statusCode: -1,
        body: e.toString(),
        stackTrace: st,
      );
    }
  }

  /// Returns the Spark external booking ID from a successful create response, if present.
  /// Spark may return id at root or inside data[0].id (e.g. {data: [{id: 1114, ...}], statusCode: 200}).
  static String? externalBookingIdFromCreateResponse(dynamic data) {
    if (data is! Map) return null;
    var id = data['id'] ?? data['bookingId'] ?? data['externalBookingId'];
    if (id == null) {
      final dataList = data['data'];
      if (dataList is List && dataList.isNotEmpty) {
        final first = dataList.first;
        if (first is Map) id = first['id'] ?? first['bookingId'] ?? first['externalBookingId'];
      }
    }
    if (id == null) return null;
    return id is int ? id.toString() : id.toString();
  }

  /// DELETE /api/v1/external-bookings/{id}
  Future<SparkApiResult> cancelBooking(String externalBookingId) async {
    if (!isEnabled) {
      return SparkApiResult.skipped('Spark API not configured');
    }

    try {
      final uri = Uri.parse('$_base/api/v1/external-bookings/$externalBookingId');
      final res = await http
          .delete(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return SparkApiResult.success();
      }

      return SparkApiResult.failure(statusCode: res.statusCode, body: res.body);
    } catch (e, st) {
      return SparkApiResult.failure(
        statusCode: -1,
        body: e.toString(),
        stackTrace: st,
      );
    }
  }

  /// GET /api/v1/locations
  Future<SparkApiResult> getLocations() async {
    if (!isEnabled) {
      return SparkApiResult.skipped('Spark API not configured');
    }

    try {
      final uri = Uri.parse('$_base/api/v1/locations');
      final res =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json =
            res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};
        return SparkApiResult.success(data: json);
      }

      return SparkApiResult.failure(statusCode: res.statusCode, body: res.body);
    } catch (e, st) {
      return SparkApiResult.failure(
        statusCode: -1,
        body: e.toString(),
        stackTrace: st,
      );
    }
  }

  /// GET /api/v1/locations/{id}/spaces
  Future<SparkApiResult> getLocationSpaces(int sparkLocationId, {String? spaceType}) async {
    if (!isEnabled) {
      return SparkApiResult.skipped('Spark API not configured');
    }

    try {
      var uri = Uri.parse('$_base/api/v1/locations/$sparkLocationId/spaces');
      if (spaceType != null && spaceType.isNotEmpty) {
        uri = uri.replace(queryParameters: {'spaceType': spaceType});
      }
      final res =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json =
            res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};
        return SparkApiResult.success(data: json);
      }

      return SparkApiResult.failure(statusCode: res.statusCode, body: res.body);
    } catch (e, st) {
      return SparkApiResult.failure(
        statusCode: -1,
        body: e.toString(),
        stackTrace: st,
      );
    }
  }

  /// Resolves our court+slot selections to Spark slot IDs.
  /// Requires sparkLocationId on the court location.
  /// Fetches slots from Spark and matches by time (and optionally space).
  Future<List<String>> resolveSlotIds({
    required int sparkLocationId,
    required String date,
    required Map<String, List<String>> selectedSlots,
    Map<String, int>? courtToSpaceId,
  }) async {
    final result = await getLocationSlots(sparkLocationId: sparkLocationId, date: date);
    if (!result.isSuccess || result.data == null) {
      debugPrint('[Spark] getLocationSlots failed or no data: ${result.statusCode} ${result.message}');
      return [];
    }

    final slots = _parseSlotsFromResponse(result.data);
    final data = result.data as Map<String, dynamic>;
    if (slots.isEmpty) {
      debugPrint('[Spark] No slots parsed. Response keys: ${data.keys.toList()}. '
          'Expected list under "data", "slots", or "items". '
          'First slot sample: ${data['data'] is List && (data['data'] as List).isNotEmpty ? (data['data'] as List).first : data['slots'] is List && (data['slots'] as List).isNotEmpty ? (data['slots'] as List).first : "n/a"}');
      return [];
    }

    if (kDebugMode && selectedSlots.isNotEmpty) {
      final sample = slots.first;
      debugPrint('[Spark] Slots for $date: ${slots.length}. Sample slot: id=${sample['id']}, startTime=${sample['startTime']}, spaceId=${sample['spaceId']}. '
          'courtToSpaceId: $courtToSpaceId. Selected: ${selectedSlots.entries.map((e) => '${e.key}=${e.value}').join('; ')}');
    }

    final slotIds = <String>[];
    for (final entry in selectedSlots.entries) {
      final courtId = entry.key;
      final spaceId = courtToSpaceId?[courtId];

      for (final timeSlot in entry.value) {
        final normalized = _normalizeTimeSlot(timeSlot);
        bool found = false;
        for (final s in slots) {
          if (_timesMatch(normalized, s['startTime']?.toString() ?? '')) {
            final slotSpaceId = s['spaceId'];
            final spaceMatch = spaceId == null ||
                slotSpaceId == spaceId ||
                slotSpaceId?.toString() == spaceId.toString();
            if (spaceMatch) {
              final id = s['id'];
              if (id != null) {
                slotIds.add(id.toString());
                found = true;
              }
              break;
            }
          }
        }
        if (kDebugMode && !found && slotIds.length < 3) {
          final sparkTimes = slots.map((s) => s['startTime']?.toString()).take(5).toList();
          debugPrint('[Spark] No match for "$timeSlot" (normalized: $normalized). Spark sample startTimes: $sparkTimes. courtId=$courtId spaceId=$spaceId');
        }
      }
    }
    return slotIds;
  }

  /// Parse slots from Spark API response.
  /// Spark returns: data = [ { id: 497, schedule: [ { id: "497#...", from: "2026-10-14 10:00", to: "...", available: true }, ... ] }, ... ].
  /// We flatten to a list of { id, startTime (HH:mm from "from"), spaceId } for matching.
  List<Map<String, dynamic>> _parseSlotsFromResponse(dynamic data) {
    if (data is! Map) return [];
    final list = data['data'] ?? data['slots'] ?? data['items'];
    if (list == null || list is! List) return [];

    final slots = <Map<String, dynamic>>[];
    final first = list.isNotEmpty ? list.first : null;
    if (first is Map && first.containsKey('schedule')) {
      for (final item in list) {
        if (item is! Map) continue;
        final spaceId = item['id'];
        final schedule = item['schedule'];
        if (spaceId == null || schedule == null || schedule is! List) continue;
        for (final s in schedule) {
          if (s is! Map) continue;
          final id = s['id'];
          final from = s['from']?.toString() ?? '';
          if (id == null || id.toString().isEmpty) continue;
          slots.add({
            'id': id,
            'startTime': _extractTimeFromSparkFrom(from),
            'spaceId': spaceId,
          });
        }
      }
    } else {
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['id'] ?? item['slotId'];
        final start = item['startTime'] ?? item['start_time'] ?? item['time'];
        final spaceId = item['spaceId'] ?? item['space_id'];
        if (id != null && id.toString().isNotEmpty) {
          slots.add({
            'id': id,
            'startTime': start?.toString() ?? '',
            'spaceId': spaceId,
          });
        }
      }
    }
    return slots;
  }

  /// Extract "HH:mm" from Spark "from" (e.g. "2026-10-14 10:00" or "2026-10-14T10:00:00.000+03:00").
  String _extractTimeFromSparkFrom(String from) {
    if (from.isEmpty) return '';
    final spaceIdx = from.indexOf(' ');
    if (spaceIdx >= 0 && spaceIdx < from.length - 1) {
      final timePart = from.substring(spaceIdx + 1).trim();
      final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(timePart);
      if (match != null) {
        final h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(from);
    if (match != null) {
      final h = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return from;
  }

  bool _timesMatch(String normalized, String sparkTime) {
    if (normalized.isEmpty || sparkTime.isEmpty) return false;
    if (normalized == sparkTime) return true;
    final extracted = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(sparkTime);
    if (extracted != null) {
      final h = int.parse(extracted.group(1)!);
      final m = int.parse(extracted.group(2)!);
      return normalized == '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return false;
  }

  String _normalizeTimeSlot(String slot) {
    try {
      final parts = slot.toUpperCase().replaceAll('.', '').split(RegExp(r'\s+'));
      if (parts.length < 2) return slot;
      final time = parts[0];
      final ampm = parts[1];
      final colon = time.indexOf(':');
      final hour = int.parse(colon >= 0 ? time.substring(0, colon) : time);
      final minute = colon >= 0 ? int.parse(time.substring(colon + 1)) : 0;
      var h = hour;
      if (ampm == 'PM' && hour != 12) h += 12;
      if (ampm == 'AM' && hour == 12) h = 0;
      return '${h.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return slot;
    }
  }

  /// Returns [spaceId, time24] for each slot that is unavailable (booked) on Spark.
  /// Used by the court booking screen to mark Spark-booked slots.
  Future<List<MapEntry<int, String>>> getUnavailableSlotTimes({
    required int sparkLocationId,
    required String date,
  }) async {
    final result = await getLocationSlots(sparkLocationId: sparkLocationId, date: date);
    if (!result.isSuccess || result.data == null) return [];
    final data = result.data as Map<String, dynamic>;
    final list = data['data'] ?? data['slots'] ?? data['items'];
    if (list == null || list is! List) return [];
    final out = <MapEntry<int, String>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final spaceIdRaw = item['id'];
      final spaceId = spaceIdRaw is int ? spaceIdRaw : int.tryParse(spaceIdRaw?.toString() ?? '');
      if (spaceId == null) continue;
      final schedule = item['schedule'];
      if (schedule == null || schedule is! List) continue;
      for (final s in schedule) {
        if (s is! Map) continue;
        if (s['available'] == true) continue;
        final from = s['from']?.toString() ?? '';
        final time24 = _extractTimeFromSparkFrom(from);
        if (time24.isNotEmpty) out.add(MapEntry(spaceId, time24));
      }
    }
    return out;
  }

  /// GET /api/v1/locations/{id}/slots?date=YYYY-MM-DD
  /// Returns available slots for the given date.
  Future<SparkApiResult> getLocationSlots({
    required int sparkLocationId,
    required String date,
    String? spaceType,
  }) async {
    if (!isEnabled) {
      return SparkApiResult.skipped('Spark API not configured');
    }

    try {
      final queryParams = <String, String>{'date': date};
      if (spaceType != null && spaceType.isNotEmpty) {
        queryParams['spaceType'] = spaceType;
      }
      final uri = Uri.parse('$_base/api/v1/locations/$sparkLocationId/slots')
          .replace(queryParameters: queryParams);
      final res =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json =
            res.body.isNotEmpty ? jsonDecode(res.body) : <String, dynamic>{};
        return SparkApiResult.success(data: json);
      }

      return SparkApiResult.failure(statusCode: res.statusCode, body: res.body);
    } catch (e, st) {
      return SparkApiResult.failure(
        statusCode: -1,
        body: e.toString(),
        stackTrace: st,
      );
    }
  }
}

enum SparkApiStatus { success, failure, skipped }

class SparkApiResult {
  final SparkApiStatus status;
  final int? statusCode;
  final String? message;
  final dynamic data;
  final StackTrace? stackTrace;

  SparkApiResult._({
    required this.status,
    this.statusCode,
    this.message,
    this.data,
    this.stackTrace,
  });

  factory SparkApiResult.success({dynamic data}) => SparkApiResult._(
        status: SparkApiStatus.success,
        data: data,
      );

  factory SparkApiResult.failure({
    required int statusCode,
    required String body,
    StackTrace? stackTrace,
  }) =>
      SparkApiResult._(
        status: SparkApiStatus.failure,
        statusCode: statusCode,
        message: body,
        stackTrace: stackTrace,
      );

  factory SparkApiResult.skipped(String reason) => SparkApiResult._(
        status: SparkApiStatus.skipped,
        message: reason,
      );

  bool get isSuccess => status == SparkApiStatus.success;
  bool get isSkipped => status == SparkApiStatus.skipped;
  bool get isFailure => status == SparkApiStatus.failure;
}
