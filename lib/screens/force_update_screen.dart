import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:store_redirect/store_redirect.dart';
import 'package:url_launcher/url_launcher.dart';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.message,
    required this.storeUrl,
    this.onSkip,
  });

  final String message;
  final String? storeUrl;
  /// Called when user taps Skip to continue without updating.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E3A8A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.system_update,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Update Required',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (storeUrl != null && storeUrl!.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () => _openStore(storeUrl!),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Update Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC400),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    )
                  else
                    const Text(
                      'Please update the app from the App Store or Play Store.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  if (onSkip != null) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: onSkip,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openStore(String url) async {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    // Use store_redirect package - it handles iOS App Store correctly
    try {
      if (isIos) {
        final idMatch = RegExp(r'/id(\d+)').firstMatch(url);
        if (idMatch != null) {
          await StoreRedirect.redirect(iOSAppId: idMatch.group(1)!);
          return;
        }
      } else {
        // Android: extract package from play.google.com URL or use default
        final idMatch = RegExp(r'[?&]id=([^&]+)').firstMatch(url);
        final androidId = idMatch?.group(1) ?? 'com.padelcore.app';
        await StoreRedirect.redirect(androidAppId: androidId);
        return;
      }
    } catch (_) {}

    // Fallback: url_launcher with stored URL
    try {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }
}
