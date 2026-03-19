import 'dart:io';

/// App configuration for environment-specific settings
class AppConfig {
  // -----------------------------
  //  Environment URLs
  // -----------------------------

  /// Ngrok URL for mobile data testing
  static const String? _ngrokUrl = null; // Example: 'https://your-ngrok-url.ngrok-free.dev'

  /// Development base URL
  static String get _devBaseUrl {
    if (_ngrokUrl != null) {
      return _ngrokUrl!;
    }

    // Local network for emulator or device
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000'; // Android emulator localhost
    } else if (Platform.isIOS) {
      return 'http://localhost:8000'; // iOS simulator localhost
    } else {
      return 'http://192.168.1.100:8000'; // Replace with your dev machine IP
    }
  }

  /// Production base URL
  static const String _prodBaseUrl = 'https://your-app.railway.app';

  /// Flag to toggle between dev and production
  static const bool isProduction = false;

  /// The base URL to use depending on environment
  static String get baseUrl => isProduction ? _prodBaseUrl : _devBaseUrl;

  // -----------------------------
  //  API Paths
  // -----------------------------
  static const String racesPath = 'races';
  static const String runnersPath = 'runners';
  static const String anomaliesPath = 'anomalies';

  // -----------------------------
  //  App-wide Settings
  // -----------------------------
  static const Duration requestTimeout = Duration(seconds: 10);
  static const bool useRemoteServer = true;
}