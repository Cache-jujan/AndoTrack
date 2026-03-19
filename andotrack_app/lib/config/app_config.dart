import 'dart:io';

class AppConfig {
  // SETUP: Copy this file to app_config.dart and update line 15 with your PC's IP
  static String get _devBaseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    } else if (Platform.isIOS) {
      return 'http://localhost:8000';
    } else {
      // TODO: Replace with your PC's IP from `ipconfig`
      return 'http://YOUR_IP_HERE:8000';
    }
  }

  static const String _prodBaseUrl = 'https://your-app.railway.app';
  static const bool isProduction = false;
  static String get baseUrl => isProduction ? _prodBaseUrl : _devBaseUrl;

  static const String racesPath = 'races';
  static const String runnersPath = 'runners';
  static const String anomaliesPath = 'anomalies';
  static const Duration requestTimeout = Duration(seconds: 10);
}