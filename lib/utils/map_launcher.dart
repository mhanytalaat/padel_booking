import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches map apps for a location. On iOS shows Apple Maps and Google Maps
/// options to satisfy App Store guidelines (native Apple Maps option).
class MapLauncher {
  /// Opens a map for the given location. On iOS shows a dialog to choose
  /// Apple Maps or Google Maps; on Android launches the chosen map.
  static Future<void> openLocation({
    required BuildContext context,
    double? lat,
    double? lng,
    String? addressQuery,
  }) async {
    final hasCoords = lat != null && lng != null;
    final query = addressQuery?.trim() ?? (hasCoords ? '$lat,$lng' : null);
    if (!hasCoords && (query == null || query.isEmpty)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No location or address available'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final appleMapsUrl = _buildAppleMapsUrl(lat: lat, lng: lng, query: query);
    final googleMapsUrl = _buildGoogleMapsUrl(lat: lat, lng: lng, query: query);

    // Offer Apple Maps and Google Maps (required by App Store for iOS)
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open in Maps'),
        content: const Text(
          'Choose an app to open the location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'apple'),
            child: const Text('Apple Maps'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'google'),
            child: const Text('Google Maps'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final url = choice == 'apple' ? appleMapsUrl : googleMapsUrl;
    await _launch(url, context);
  }

  /// Opens location when you have a stored Google Maps URL (e.g. from Firestore).
  /// Parses the URL for coordinates or query and shows Apple/Google Maps choice.
  static Future<void> openLocationFromUrl(
    BuildContext context, {
    required String? url,
    String? fallbackAddressQuery,
  }) async {
    if ((url == null || url.isEmpty) && (fallbackAddressQuery == null || fallbackAddressQuery.isEmpty)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No location or address available'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    double? lat;
    double? lng;
    String? query = fallbackAddressQuery?.trim();
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        final q = uri.queryParameters['query'];
        if (q != null && q.isNotEmpty) {
          final parts = q.split(',');
          if (parts.length == 2) {
            final la = double.tryParse(parts[0].trim());
            final ln = double.tryParse(parts[1].trim());
            if (la != null && ln != null) {
              lat = la;
              lng = ln;
              query = q;
            } else {
              query = q;
            }
          } else {
            query = q;
          }
        }
      }
    }
    return openLocation(context: context, lat: lat, lng: lng, addressQuery: query);
  }

  /// Builds Apple Maps URL (for direct use if needed).
  static String buildAppleMapsUrl({
    double? lat,
    double? lng,
    String? addressQuery,
  }) {
    return _buildAppleMapsUrl(
      lat: lat,
      lng: lng,
      query: addressQuery?.trim() ?? (lat != null && lng != null ? '$lat,$lng' : null),
    );
  }

  static String _buildAppleMapsUrl({
    double? lat,
    double? lng,
    String? query,
  }) {
    if (lat != null && lng != null) {
      final q = query != null ? '&q=${Uri.encodeComponent(query)}' : '';
      return 'https://maps.apple.com/?ll=$lat,$lng$q';
    }
    if (query != null && query.isNotEmpty) {
      return 'https://maps.apple.com/?q=${Uri.encodeComponent(query)}';
    }
    return 'https://maps.apple.com/';
  }

  static String _buildGoogleMapsUrl({
    double? lat,
    double? lng,
    String? query,
  }) {
    if (lat != null && lng != null) {
      return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    if (query != null && query.isNotEmpty) {
      return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}';
    }
    return 'https://www.google.com/maps';
  }

  static Future<void> _launch(String url, BuildContext context) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open maps'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening map: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
