import 'dart:convert';

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
  static String? externalBookingIdFromCreateResponse(dynamic data) {
    if (data is! Map) return null;
    final id = data['id'] ?? data['bookingId'] ?? data['externalBookingId'];
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
    if (!result.isSuccess || result.data == null) return [];

    final slots = _parseSlotsFromResponse(result.data);
    if (slots.isEmpty) return [];

    final slotIds = <String>[];
    for (final entry in selectedSlots.entries) {
      final courtId = entry.key;
      final spaceId = courtToSpaceId?[courtId];

      for (final timeSlot in entry.value) {
        final normalized = _normalizeTimeSlot(timeSlot);
        for (final s in slots) {
          if (_timesMatch(normalized, s['startTime']?.toString() ?? '')) {
            if (spaceId == null || s['spaceId'] == spaceId) {
              final id = s['id'];
              if (id != null) slotIds.add(id.toString());
              break;
            }
          }
        }
      }
    }
    return slotIds;
  }

  /// Parse slots from Spark API response (flexible structure).
  List<Map<String, dynamic>> _parseSlotsFromResponse(dynamic data) {
    if (data is! Map) return [];
    dynamic list = data['data'] ?? data['slots'] ?? data['items'];
    if (list == null) return [];
    if (list is! List) return [];
    final slots = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = item['id'] ?? item['slotId'];
      final start = item['startTime'] ?? item['start_time'] ?? item['time'];
      final spaceId = item['spaceId'] ?? item['space_id'];
      if (id != null) {
        slots.add({
          'id': id is int ? id : int.tryParse(id.toString()),
          'startTime': start?.toString() ?? '',
          'spaceId': spaceId,
        });
      }
    }
    return slots;
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
