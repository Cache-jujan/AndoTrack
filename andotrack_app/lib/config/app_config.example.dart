import 'dart:io';

class AppConfig {
  // ── Set this when testing on mobile data via ngrok ────
  // Get URL from: ngrok http 8000  →  copy the https://xxx.ngrok-free.app URL
  // Set to null when testing on WiFi (uses local IP instead)
  static const String? _ngrokUrl = null; // ← paste ngrok URL here when needed

  static String get _devBaseUrl {
    // If ngrok URL is set, use it (mobile data testing)
    if (_ngrokUrl != null) {
      return _ngrokUrl!;
    }

    // Otherwise use local network (WiFi)
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000';  // emulator
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