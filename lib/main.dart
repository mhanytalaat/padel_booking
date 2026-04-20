import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/force_update_screen.dart';
import 'screens/tournaments_screen.dart';
import 'screens/my_bookings_screen.dart';
import 'screens/skills_screen.dart';
import 'screens/required_profile_update_screen.dart';
import 'services/profile_completion_service.dart';
import 'services/force_update_service.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/notification_service.dart' show NotificationService, firebaseMessagingBackgroundHandler;

void main() async {
  // Set up error handling BEFORE anything else
  FlutterError.onError = (FlutterErrorDetails details) {
    // Ignore web-specific harmless errors
    if (kIsWeb) {
      final error = details.exception.toString();
      if (error.contains('LateInitializationError') &&
          error.contains('onSnapshotUnsubscribe')) {
        return;
      }
      if (error.contains('Trying to render a disposed EngineFlutterView') ||
          (error.contains('Assertion failed') &&
           error.contains('!isDisposed') &&
           error.contains('EngineFlutterView'))) {
        return;
      }
    }

    FlutterError.presentError(details);
    debugPrint('=== FLUTTER ERROR ===');
    debugPrint('Exception: ${details.exception}');
    debugPrint('Library: ${details.library}');
    debugPrint('Context: ${details.context}');
    if (details.stack != null) {
      debugPrint('Stack trace: ${details.stack}');
    }
    debugPrint('===================');
  };

  runZonedGuarded(() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      debugPrint('WidgetsFlutterBinding initialized');

      // ✅ FIX: Initialize Firebase BEFORE runApp so it is always ready
      // when the first screen renders. This prevents "app not authorized"
      // errors on Android that occurred when users reached the login/register
      // screen before the async background initialization had completed.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('Firebase initialized successfully');

      // Silence Firestore web SDK console logs
      if (kIsWeb) {
        try {
          await FirebaseFirestore.setLoggingEnabled(false);
        } catch (_) {}
      }

      // Set up background message handler (non-web only)
      if (!kIsWeb) {
        try {
          FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
          debugPrint('FCM background handler registered');
        } catch (e) {
          debugPrint('Error registering FCM background handler: $e');
        }
      }

      runApp(const MyApp());
      debugPrint('MyApp started');
    } catch (e, stackTrace) {
      debugPrint('=== CRITICAL ERROR IN MAIN ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      debugPrint('==============================');
      runApp(const ErrorApp());
    }
  }, (error, stack) {
    // Catch all uncaught errors
    if (kIsWeb) {
      final errorStr = error.toString();
      final stackStr = stack?.toString() ?? '';
      if (errorStr.contains('LateInitializationError') &&
          errorStr.contains('onSnapshotUnsubscribe')) {
        return;
      }
      if (errorStr.contains('Trying to render a disposed EngineFlutterView') ||
          (errorStr.contains('Assertion failed') &&
           errorStr.contains('!isDisposed') &&
           errorStr.contains('EngineFlutterView'))) {
        return;
      }
      if (stackStr.contains('cloud_firestore_web') &&
          (stackStr.contains('_completeWithValue') || stackStr.contains('handleValue'))) {
        return;
      }
      if ((errorStr.contains('FIRESTORE') && errorStr.contains('INTERNAL ASSERTION FAILED')) ||
          (errorStr.contains('Unexpected state') && stackStr.contains('firebase-firestore'))) {
        return;
      }
    }

    debugPrint('=== UNCAUGHT ERROR ===');
    debugPrint('Error: $error');
    debugPrint('Stack: $stack');
    debugPrint('=====================');
    final errorStr = error.toString();
    final stackStr = stack?.toString() ?? '';
    if (errorStr.contains('Zone mismatch')) {
      debugPrint('Skipping ErrorApp - Zone mismatch would recur');
      return;
    }
    if (stackStr.contains('visitChildren') && stackStr.contains('_unmount')) {
      debugPrint('Ignoring disposal/unmount error (visitChildren/_unmount)');
      return;
    }
    if (errorStr.contains('setState()') && errorStr.contains('dispose')) {
      debugPrint('Ignoring setState-after-dispose error');
      return;
    }
    if (stackStr.contains('dispose') && stackStr.contains('visitChildren')) {
      debugPrint('Ignoring dispose/visitChildren error');
      return;
    }
    if (kIsWeb && (stackStr.contains('_handleDrawFrame') ||
        stackStr.contains('_renderFrame') ||
        stackStr.contains('invokeOnDrawFrame') ||
        stackStr.contains('frame_service') ||
        (stackStr.contains('tear') && stackStr.contains('platform_dispatcher')))) {
      debugPrint('Ignoring web frame/disposal error');
      return;
    }
    if (kIsWeb) {
      debugPrint('Web: not showing ErrorApp for zone error (log only)');
      return;
    }
    runApp(const ErrorApp());
  });
}

// Minimal error app that shows if everything else fails
class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E3A8A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'App Initialization Error',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'The app encountered an error during startup. Please restart the app.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'PadelCore',
        theme: ThemeData(
          primaryColor: const Color(0xFF1E3A8A),
          scaffoldBackgroundColor: const Color(0xFFF4F7FB),
          textTheme: ThemeData.light().textTheme,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC400),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        home: const SplashScreen(),
        routes: {
          '/home': (context) => const AuthWrapper(),
          '/tournaments': (context) => const TournamentsScreen(),
          '/my_bookings': (context) => const MyBookingsScreen(),
          '/skills': (context) => const SkillsScreen(),
        },
        builder: (context, child) {
          ErrorWidget.builder = (FlutterErrorDetails details) {
            debugPrint('=== ERROR WIDGET BUILDER ===');
            debugPrint('Exception: ${details.exception}');
            debugPrint('===========================');
            if (details.exception.toString().contains('overflowed')) {
              return const SizedBox.shrink();
            }
            return Scaffold(
              backgroundColor: const Color(0xFFF4F7FB),
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'An error occurred',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${details.exception}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          };
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
            child: child ?? const SizedBox(),
          );
        },
      );
    } catch (e, stackTrace) {
      debugPrint('=== ERROR BUILDING MyApp ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      debugPrint('===========================');
      return const ErrorApp();
    }
  }
}

// Splash screen — Firebase is already initialized by the time this runs,
// so we only need to check force update and initialize notifications here.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _firebaseReady = false;
  bool _hasError = false;
  String? _errorMessage;
  ForceUpdateResult? _forceUpdateResult;
  Timer? _webTimeout;

  @override
  void initState() {
    super.initState();
    _onFirebaseReady();
    if (kIsWeb) {
      _webTimeout = Timer(const Duration(seconds: 5), () {
        if (mounted && !_firebaseReady && !_hasError) {
          debugPrint('SplashScreen: Web timeout - proceeding to app');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_firebaseReady && !_hasError) {
              setState(() { _firebaseReady = true; });
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _webTimeout?.cancel();
    super.dispose();
  }

  // ✅ Firebase is already initialized — just handle notifications + force update
  Future<void> _onFirebaseReady() async {
    try {
      debugPrint('SplashScreen: Firebase already initialized, setting up services...');

      // Initialize notification service (non-web only)
      if (!kIsWeb) {
        try {
          await NotificationService().initialize();
          debugPrint('Notification service initialized');
        } catch (e) {
          debugPrint('Error initializing notifications: $e');
          // Non-fatal — continue
        }
      }

      // Check for force update (skip on web - no app store)
      if (mounted && !kIsWeb) {
        try {
          final result = await ForceUpdateService.instance.checkUpdateRequired();
          if (mounted && result.updateRequired) {
            setState(() { _forceUpdateResult = result; });
            return;
          }
        } catch (e) {
          debugPrint('SplashScreen: Force update check failed: $e');
          // Non-fatal — continue
        }
      }

      if (mounted) {
        _webTimeout?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() { _firebaseReady = true; });
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('=== SPLASHSCREEN ERROR ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      debugPrint('=========================');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = e.toString();
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: const Color(0xFF1E3A8A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 80, color: Colors.white),
                  const SizedBox(height: 24),
                  const Text(
                    'Initialization Error',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      setState(() { _hasError = false; _errorMessage = null; });
                      _onFirebaseReady();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E3A8A),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_forceUpdateResult != null) {
      return ForceUpdateScreen(
        message: _forceUpdateResult!.message ??
            'A new version of PadelCore is available. Please update to continue.',
        storeUrl: _forceUpdateResult!.storeUrl,
        onSkip: () {
          setState(() {
            _forceUpdateResult = null;
            _firebaseReady = true;
          });
        },
      );
    }

    if (_firebaseReady) {
      return const AuthWrapper();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'PadelCore',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  StreamSubscription<User?>? _authSubscription;
  bool _hasError = false;
  String? _errorMessage;
  Widget? _cachedHomeScreen;
  String? _lastRefreshedUserId;
  Timer? _webAuthWaitTimer;
  bool _webAssumeGuest = false;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  void _initializeAuth() {
    try {
      final auth = FirebaseAuth.instance;
      _authSubscription = auth.authStateChanges().listen(
        (user) {},
        onError: (error) {
          debugPrint('Auth stream error: $error');
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _hasError = true;
                  _errorMessage = error.toString();
                });
              }
            });
          }
        },
        cancelOnError: false,
      );
    } catch (e, stackTrace) {
      debugPrint('AuthWrapper initialization error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _webAuthWaitTimer?.cancel();
    _webAuthWaitTimer = null;
    _authSubscription?.cancel();
    _cachedHomeScreen = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F7FB),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Authentication Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() { _hasError = false; _errorMessage = null; });
                      _initializeAuth();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (!mounted) return const SizedBox.shrink();

          if (snapshot.hasError) {
            debugPrint('Auth stream error: ${snapshot.error}');
            return Scaffold(
              backgroundColor: const Color(0xFFF4F7FB),
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text(
                          'Authentication Error',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const AuthWrapper()),
                            );
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            if (_cachedHomeScreen != null) return _cachedHomeScreen!;
            if (kIsWeb) {
              _webAuthWaitTimer ??= Timer(const Duration(seconds: 6), () {
                if (mounted) setState(() { _webAssumeGuest = true; });
              });
              if (_webAssumeGuest) {
                _webAuthWaitTimer?.cancel();
                _webAuthWaitTimer = null;
                _cachedHomeScreen ??= const HomeScreen();
                return _cachedHomeScreen!;
              }
            }
            return Scaffold(
              backgroundColor: const Color(0xFF1E3A8A),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Loading...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            );
          }

          if (kIsWeb) {
            _webAuthWaitTimer?.cancel();
            _webAuthWaitTimer = null;
            _webAssumeGuest = false;
          }

          if (snapshot.hasData && snapshot.data != null) {
            final currentUser = snapshot.data!;
            if (!kIsWeb && _lastRefreshedUserId != currentUser.uid) {
              _lastRefreshedUserId = currentUser.uid;
              NotificationService().refreshToken().then((_) {
                debugPrint('✅ FCM token refreshed for user: ${currentUser.uid}');
              }).catchError((e) {
                debugPrint('❌ Failed to refresh FCM token: $e');
              });
            }
            _cachedHomeScreen ??= const HomeScreen();
            return _cachedHomeScreen!;
          } else {
            _lastRefreshedUserId = null;
            _cachedHomeScreen ??= const HomeScreen();
            return _cachedHomeScreen!;
          }
        },
      );
    } catch (e, stackTrace) {
      debugPrint('AuthWrapper build error: $e');
      debugPrint('Stack trace: $stackTrace');
      return const HomeScreen();
    }
  }
}
