class AppConfig {
  // ── Change this to YOUR PC's IP address ──────────────
  // Run `ipconfig` in PowerShell → IPv4 Address under WiFi
  static const String _devBaseUrl = '#';

  // ── Production URL (Railway) — fill in during Sprint 4 ──
  static const String _prodBaseUrl = 'https://your-app.railway.app';

  // ── Set to true only when deploying to Railway ────────
  static const bool isProduction = false;

  // ── Use this everywhere in the app ───────────────────
  static String get baseUrl => isProduction ? _prodBaseUrl : _devBaseUrl;

  // ── Firebase paths ────────────────────────────────────
  static const String racesPath = 'races';
  static const String runnersPath = 'runners';
  static const String anomaliesPath = 'anomalies';

  // ── Request timeout ───────────────────────────────────
  static const Duration requestTimeout = Duration(seconds: 10);
}