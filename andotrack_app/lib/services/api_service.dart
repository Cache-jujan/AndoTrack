import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/app_config.dart';


class ApiService {
  // ── Auth ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(AppConfig.requestTimeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Save token to shared_preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', data['access_token']);
        await prefs.setString('user_role', data['role'] ?? 'runner');
        await prefs.setInt('user_id', data['user_id'] ?? 0);

        return {
          'success': true,
          'token': data['access_token'],
          'role': data['role'] ?? 'runner',
        };
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Invalid credentials.',
        };
      }
    } on Exception {
      return {
        'success': false,
        'message': 'Cannot connect to server. Is FastAPI running?',
      };
    }
  }

  // ── Register ────────────────────────────────────────
  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name,
              'email': email,
              'password': password,
              'role': role,
            }),
          )
          .timeout(AppConfig.requestTimeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'token': data['access_token'],
          'role': data['role'] ?? role,
        };
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Registration failed.',
        };
      }
    } on Exception {
      return {
        'success': false,
        'message': 'Cannot connect to server. Is FastAPI running?',
      };
    }
  }

  // ── Token storage ────────────────────────────────────

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  static Future<void> saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
  }

  // ── Authenticated requests ───────────────────────────

  static Future<http.Response> get(String endpoint) async {
    final token = await getToken();
    return http
        .get(
          Uri.parse('${AppConfig.baseUrl}$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        )
        .timeout(AppConfig.requestTimeout);
  }

  static Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final token = await getToken();
    return http
        .post(
          Uri.parse('${AppConfig.baseUrl}$endpoint'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(AppConfig.requestTimeout);
  }

  // ── Races ────────────────────────────────────────────

  static Future<List<dynamic>> getRaces() async {
    final response = await get('/races');
    return jsonDecode(response.body);
  }
}