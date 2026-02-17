/// Spark Platform API configuration.
///
/// Set credentials at build time:
///   flutter run --dart-define=SPARK_API_KEY=your_api_key --dart-define=SPARK_BEARER_TOKEN=your_jwt
///   flutter build apk --dart-define=SPARK_API_KEY=xxx --dart-define=SPARK_BEARER_TOKEN=xxx
///
/// Both x-api-key and Authorization: Bearer are required per Postman collection.
/// Or set SPARK_BASE_URL if different from staging.
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

  /// JWT Bearer token (expires; refresh when needed).
  static const String _bearerToken = String.fromEnvironment(
    'SPARK_BEARER_TOKEN',
    defaultValue: '',
  );

  static String get baseUrl => _baseUrl;
  static String get apiKey => _apiKey;
  static String get bearerToken => _bearerToken;

  static bool get isConfigured => _apiKey.isNotEmpty && _bearerToken.isNotEmpty;
}
