import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Hardcoded app identifiers — no URL parsing needed.
const _kIosAppId = '6757525957';
const _kAndroidPackage = 'com.padelcore.app';

// iOS: itms-apps opens App Store directly on the app page (no Safari redirect)
const _kIosItmsUrl = 'itms-apps://itunes.apple.com/app/id$_kIosAppId';
const _kIosHttpsUrl = 'https://apps.apple.com/app/id$_kIosAppId';
const _kAndroidUrl =
    'https://play.google.com/store/apps/details?id=$_kAndroidPackage';

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.message,
    required this.storeUrl,
    this.onSkip,
  });

  final String message;
  final String? storeUrl;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E3A8A),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.system_update,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Update Required',
                    textAlign: TextAlign.center,
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
                      color: Colors.white,
                      fontSize: 17,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _openStore,
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

  Future<void> _openStore() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Try itms-apps:// first — opens App Store directly on the PadelCore page
      final itmsUri = Uri.parse(_kIosItmsUrl);
      if (await canLaunchUrl(itmsUri)) {
        await launchUrl(itmsUri, mode: LaunchMode.externalApplication);
        return;
      }
      // Fallback: https link (iOS will still open App Store)
      await launchUrl(
        Uri.parse(_kIosHttpsUrl),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    // Android — open Play Store market:// first, then https fallback
    final marketUri = Uri.parse('market://details?id=$_kAndroidPackage');
    if (await canLaunchUrl(marketUri)) {
      await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(
      Uri.parse(_kAndroidUrl),
      mode: LaunchMode.externalApplication,
    );
  }
}
