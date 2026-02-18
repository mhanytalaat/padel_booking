import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Result of a force-update check.
class ForceUpdateResult {
  const ForceUpdateResult({
    required this.updateRequired,
    this.minimumVersion,
    this.minimumBuildNumber,
    this.message,
    this.androidStoreUrl,
    this.iosStoreUrl,
  });

  final bool updateRequired;
  final String? minimumVersion;
  final int? minimumBuildNumber;
  final String? message;
  final String? androidStoreUrl;
  final String? iosStoreUrl;

  String? get storeUrl => defaultTargetPlatform == TargetPlatform.android
      ? androidStoreUrl
      : iosStoreUrl;
}

/// Service that checks if the app needs to be updated based on Firestore config.
class ForceUpdateService {
  ForceUpdateService._();
  static final ForceUpdateService instance = ForceUpdateService._();

  static const _defaultAndroidUrl =
      'https://play.google.com/store/apps/details?id=com.padelcore.app';
  // Configure iosStoreUrl in Firestore (e.g. https://apps.apple.com/app/id123456789)
  static const _defaultIosUrl =
      'https://apps.apple.com/'; // Fallback - set iosStoreUrl in Firestore

  /// Checks if an update is required by comparing current version to Firestore config.
  /// Returns [ForceUpdateResult] with updateRequired=true if user must update.
  Future<ForceUpdateResult> checkUpdateRequired() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('ForceUpdate: No app_config/settings found, skipping check');
        return const ForceUpdateResult(updateRequired: false);
      }

      final data = doc.data()!;
      final isIos = defaultTargetPlatform == TargetPlatform.iOS;

      // Platform-specific minimums (fall back to generic if not set)
      final minVersion = (isIos
              ? data['minimumVersionIos'] ?? data['minimumVersion']
              : data['minimumVersionAndroid'] ?? data['minimumVersion'])
          as String?;
      final minBuildRaw = isIos
          ? data['minimumBuildNumberIos'] ?? data['minimumBuildNumber']
          : data['minimumBuildNumberAndroid'] ?? data['minimumBuildNumber'];
      final minBuild = minBuildRaw != null ? (minBuildRaw as num).toInt() : null;

      final message = data['updateMessage'] as String? ??
          'A new version of PadelCore is available. Please update to continue.';
      final androidUrl = data['androidStoreUrl'] as String? ?? _defaultAndroidUrl;
      final iosUrl = data['iosStoreUrl'] as String? ?? _defaultIosUrl;

      debugPrint(
          'ForceUpdate: current=$currentVersion ($currentBuild), minVersion=$minVersion, minBuild=$minBuild, isIos=$isIos');

      if (minVersion == null && minBuild == null) {
        debugPrint('ForceUpdate: No minimumVersion or minimumBuildNumber set');
        return const ForceUpdateResult(updateRequired: false);
      }

      bool updateRequired = false;

      if (minBuild != null && currentBuild < minBuild) {
        updateRequired = true;
        debugPrint(
            'ForceUpdate: Build $currentBuild < $minBuild (update required)');
      }

      if (minVersion != null && !updateRequired) {
        if (_compareVersions(currentVersion, minVersion) < 0) {
          updateRequired = true;
          debugPrint(
              'ForceUpdate: Version $currentVersion < $minVersion (update required)');
        }
      }

      return ForceUpdateResult(
        updateRequired: updateRequired,
        minimumVersion: minVersion,
        minimumBuildNumber: minBuild,
        message: message,
        androidStoreUrl: androidUrl,
        iosStoreUrl: iosUrl,
      );
    } catch (e, stack) {
      debugPrint('ForceUpdate: Error checking version: $e');
      debugPrint('ForceUpdate: $stack');
      if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('permission-denied')) {
        debugPrint(
            'ForceUpdate: Firestore permission denied - run: firebase deploy --only firestore:rules');
      }
      return const ForceUpdateResult(updateRequired: false);
    }
  }

  /// Compares semantic versions. Returns -1 if a < b, 0 if equal, 1 if a > b.
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map(int.tryParse).toList();
    final bParts = b.split('.').map(int.tryParse).toList();

    for (var i = 0; i < aParts.length || i < bParts.length; i++) {
      final aVal = i < aParts.length ? (aParts[i] ?? 0) : 0;
      final bVal = i < bParts.length ? (bParts[i] ?? 0) : 0;
      if (aVal < bVal) return -1;
      if (aVal > bVal) return 1;
    }
    return 0;
  }
}
