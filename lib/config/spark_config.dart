/// Spark Platform API configuration.
///
/// Set at build/run time (do not commit secrets):
///   flutter run --dart-define=SPARK_API_KEY=your_api_key
///   flutter build apk --dart-define=SPARK_API_KEY=your_api_key
///
/// Optional: SPARK_BASE_URL (default: staging), SPARK_BEARER_TOKEN (if API requires Bearer).
/// Auth: x-api-key header is required; Bearer is optional per Integrations Postman collection.
class SparkConfig {
  SparkConfig._();

  static const String _baseUrl = String.fromEnvironment(
    'SPARK_BASE_URL',
    defaultValue: 'https://external-client-staging.sparkplatform.app',
  );

  static const String _apiKey = String.fromEnvironment(
    'SPARK_API_KEY',
    defaultValue: '',
  );

  /// Optional JWT Bearer token (if required by environment).
  static const String _bearerToken = String.fromEnvironment(
    'SPARK_BEARER_TOKEN',
    defaultValue: '',
  );

  static String get baseUrl => _baseUrl;
  static String get apiKey => _apiKey;
  static String get bearerToken => _bearerToken;

  /// Enabled when API key is set (Bearer optional for Integrations API).
  static bool get isConfigured => _apiKey.isNotEmpty;
}
