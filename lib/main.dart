import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart' show NotificationService, firebaseMessagingBackgroundHandler;

void main() async {
  // Set up error handling BEFORE anything else
  FlutterError.onError = (FlutterErrorDetails details) {
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
  
  // Catch all errors including those outside Flutter
  runZonedGuarded(() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      debugPrint('WidgetsFlutterBinding initialized');
      
      // Run app immediately WITHOUT Firebase first - test if app can start
      runApp(const MyApp());
      debugPrint('MyApp started');
      
      // Initialize Firebase asynchronously after app starts
      _initializeFirebaseAsync();
    } catch (e, stackTrace) {
      debugPrint('=== CRITICAL ERROR IN MAIN ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      debugPrint('==============================');
      // Even if everything fails, try to show error screen
      runApp(const ErrorApp());
    }
  }, (error, stack) {
    // Catch all uncaught errors
    debugPrint('=== UNCAUGHT ERROR ===');
    debugPrint('Error: $error');
    debugPrint('Stack: $stack');
    debugPrint('=====================');
    // Try to show error screen
    runApp(const ErrorApp());
  });
}

// Initialize Firebase asynchronously to prevent blocking app startup
Future<void> _initializeFirebaseAsync() async {
  try {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    debugPrint('Starting Firebase initialization... (Android: $isAndroid)');
    
    // Android needs more time for initialization
    final delay = isAndroid ? 500 : 100;
    await Future.delayed(Duration(milliseconds: delay));
    
    // Safely get Firebase options with retry for Android
    FirebaseOptions? options;
    int retryCount = 0;
    const maxRetries = 3;
    
    while (options == null && retryCount < maxRetries) {
      try {
        options = DefaultFirebaseOptions.currentPlatform;
        debugPrint('Firebase options retrieved successfully (attempt ${retryCount + 1})');
        break;
      } catch (e, stackTrace) {
        retryCount++;
        debugPrint('=== ERROR GETTING FIREBASE OPTIONS (attempt $retryCount) ===');
        debugPrint('Error: $e');
        debugPrint('Stack: $stackTrace');
        debugPrint('=====================================');
        
        if (retryCount < maxRetries && isAndroid) {
          // Retry with increasing delay for Android
          await Future.delayed(Duration(milliseconds: 200 * retryCount));
        } else {
          return; // Don't try to initialize if we can't get options
        }
      }
    }
    
    if (options == null) {
      debugPrint('Failed to get Firebase options after $maxRetries attempts');
      return;
    }
    
    // Check if Firebase is already initialized
    if (Firebase.apps.isEmpty) {
      debugPrint('Initializing Firebase...');
      
      // Android-specific: Add retry logic for initialization
      if (isAndroid) {
        int initRetryCount = 0;
        const maxInitRetries = 3;
        bool initialized = false;
        
        while (!initialized && initRetryCount < maxInitRetries) {
          try {
            await Firebase.initializeApp(options: options);
            debugPrint('Firebase initialized successfully (attempt ${initRetryCount + 1})');
            initialized = true;
          } catch (e, stackTrace) {
            initRetryCount++;
            debugPrint('=== FIREBASE INIT ERROR (attempt $initRetryCount) ===');
            debugPrint('Error: $e');
            debugPrint('Stack: $stackTrace');
            debugPrint('====================================');
            
            if (initRetryCount < maxInitRetries) {
              await Future.delayed(Duration(milliseconds: 300 * initRetryCount));
            } else {
              debugPrint('Failed to initialize Firebase after $maxInitRetries attempts');
              return;
            }
          }
        }
      } else {
        // iOS/Web: Direct initialization (works fine)
        await Firebase.initializeApp(options: options);
        debugPrint('Firebase initialized successfully');
      }
    } else {
      debugPrint('Firebase already initialized');
    }

    // Initialize Firebase Cloud Messaging
    try {
      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      
      // Initialize notification service
      await NotificationService().initialize();
      debugPrint('Notification service initialized');
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  } catch (e, stackTrace) {
    // Log error but don't crash
    debugPrint('=== FIREBASE INITIALIZATION ERROR ===');
    debugPrint('Error: $e');
    debugPrint('Stack: $stackTrace');
    debugPrint('====================================');
  }
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
          primaryColor: const Color(0xFF1E3A8A), // Deep blue
          scaffoldBackgroundColor: const Color(0xFFF4F7FB),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC400), // Yellow
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        // Always show splash screen first, then AuthWrapper
        home: const SplashScreen(),
        // Add error builder to catch widget errors
        builder: (context, child) {
          ErrorWidget.builder = (FlutterErrorDetails details) {
            debugPrint('=== ERROR WIDGET BUILDER ===');
            debugPrint('Exception: ${details.exception}');
            debugPrint('===========================');
            return Scaffold(
              backgroundColor: const Color(0xFFF4F7FB),
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'An error occurred',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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

// Simple test screen - NO Firebase dependency
class TestScreen extends StatelessWidget {
  const TestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'PadelCore',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'App Started Successfully!',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () {
                  // Try to navigate to login (will fail if Firebase not ready, but app won't crash)
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const SplashScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('Continue to App'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Splash screen that shows immediately and waits for Firebase
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _firebaseReady = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkFirebase();
  }

  Future<void> _checkFirebase() async {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    // Android needs more time for initialization
    final delay = isAndroid ? 1000 : 500;
    await Future.delayed(Duration(milliseconds: delay));
    
    try {
      debugPrint('SplashScreen: Checking Firebase... (Android: $isAndroid)');
      
      // Check if Firebase is initialized - wait longer for Android
      int checkCount = 0;
      const maxChecks = 10;
      
      while (Firebase.apps.isEmpty && checkCount < maxChecks) {
        await Future.delayed(Duration(milliseconds: isAndroid ? 200 : 100));
        checkCount++;
        if (checkCount % 2 == 0) {
          debugPrint('SplashScreen: Waiting for Firebase... (check $checkCount/$maxChecks)');
        }
      }
      
      if (Firebase.apps.isEmpty) {
        debugPrint('SplashScreen: Firebase not initialized, initializing...');
        
        // Safely get Firebase options with retry for Android
        FirebaseOptions? options;
        int retryCount = 0;
        const maxRetries = 3;
        
        while (options == null && retryCount < maxRetries) {
          try {
            options = DefaultFirebaseOptions.currentPlatform;
            debugPrint('SplashScreen: Firebase options retrieved (attempt ${retryCount + 1})');
            break;
          } catch (e, stackTrace) {
            retryCount++;
            debugPrint('=== SPLASHSCREEN: ERROR GETTING FIREBASE OPTIONS (attempt $retryCount) ===');
            debugPrint('Error: $e');
            debugPrint('Stack: $stackTrace');
            debugPrint('==================================================');
            
            if (retryCount < maxRetries && isAndroid) {
              await Future.delayed(Duration(milliseconds: 200 * retryCount));
            } else {
              if (mounted) {
                setState(() {
                  _hasError = true;
                  _errorMessage = 'Failed to get Firebase configuration: $e';
                });
              }
              return;
            }
          }
        }
        
        if (options == null) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = 'Failed to get Firebase configuration after $maxRetries attempts';
            });
          }
          return;
        }
        
        // Try to initialize with retry for Android
        if (isAndroid) {
          int initRetryCount = 0;
          const maxInitRetries = 3;
          bool initialized = false;
          
          while (!initialized && initRetryCount < maxInitRetries) {
            try {
              await Firebase.initializeApp(options: options);
              debugPrint('SplashScreen: Firebase initialized successfully (attempt ${initRetryCount + 1})');
              initialized = true;
            } catch (e, stackTrace) {
              initRetryCount++;
              debugPrint('=== SPLASHSCREEN: FIREBASE INIT ERROR (attempt $initRetryCount) ===');
              debugPrint('Error: $e');
              debugPrint('Stack: $stackTrace');
              debugPrint('==========================================');
              
              if (initRetryCount < maxInitRetries) {
                await Future.delayed(Duration(milliseconds: 300 * initRetryCount));
              } else {
                if (mounted) {
                  setState(() {
                    _hasError = true;
                    _errorMessage = 'Failed to initialize Firebase: $e';
                  });
                }
                return;
              }
            }
          }
        } else {
          // iOS/Web: Direct initialization (works fine)
          await Firebase.initializeApp(options: options);
          debugPrint('SplashScreen: Firebase initialized successfully');
        }
      } else {
        debugPrint('SplashScreen: Firebase already initialized');
      }
      
      if (mounted) {
        setState(() {
          _firebaseReady = true;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('=== SPLASHSCREEN: FIREBASE CHECK ERROR ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $stackTrace');
      debugPrint('==========================================');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If error, show error screen
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
                  const Icon(
                    Icons.error_outline,
                    size: 80,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Initialization Error',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage ?? 'Unknown error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _errorMessage = null;
                      });
                      _checkFirebase();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E3A8A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
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

    // If Firebase ready, show AuthWrapper
    if (_firebaseReady) {
      return const AuthWrapper();
    }

    // Show splash screen while waiting
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'PadelCore',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'Loading...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Error screen if Firebase fails to initialize
class FirebaseErrorScreen extends StatelessWidget {
  const FirebaseErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
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
                  color: Colors.red,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Initialization Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'The app failed to initialize properly. Please try restarting the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    // Try to restart
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const AuthWrapper(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
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

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  void _initializeAuth() {
    try {
      // Check if Firebase is initialized
      if (Firebase.apps.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Firebase not initialized';
        });
        return;
      }

      // Safely get auth instance
      final auth = FirebaseAuth.instance;
      _authSubscription = auth.authStateChanges().listen(
        (user) {
          // Success - state will be handled by StreamBuilder
        },
        onError: (error) {
          debugPrint('Auth stream error: $error');
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = error.toString();
            });
          }
        },
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
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show error screen if initialization failed
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
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Authentication Error',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                      setState(() {
                        _hasError = false;
                        _errorMessage = null;
                      });
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

    // Try to build auth stream
    try {
      return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Handle errors
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
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Authentication Error',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
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
                            // Try to reload
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const AuthWrapper(),
                              ),
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

          // Show loading while checking auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
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
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // If user is logged in, show HomeScreen, otherwise show LoginScreen
          if (snapshot.hasData && snapshot.data != null) {
            return const HomeScreen();
          } else {
            return const LoginScreen();
          }
        },
      );
    } catch (e, stackTrace) {
      debugPrint('AuthWrapper build error: $e');
      debugPrint('Stack trace: $stackTrace');
      // Fallback to login screen if there's an error
      return const LoginScreen();
    }
  }
}
