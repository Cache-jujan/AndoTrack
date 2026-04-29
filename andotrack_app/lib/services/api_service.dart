// ============================================================
// ApiService — Central HTTP client for AndoTrack
// ─────────────────────────────────────────────────────────────
// • Auth: login, register, logout, token/role persistence
// • Races: list, create (full schema), start, stop
// • Leaderboard: fetch by raceId
// • Runners: list by raceId, profile
// • Checkpoints: list, arrive, delete
// • Generic helpers: get, post, delete (used by CheckpointService)
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiService {
  static String get _base => AppConfig.baseUrl;

  // ── Auth ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        return {
          'success': true,
          'token': body['access_token'],
          'role': body['role'],
          'user_id': body['user_id'],
          'name': body['name'],
        };
      }
      return {
        'success': false,
        'message': body['detail'] ?? 'Login failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password,
    String role,
  ) async {
    try {
      final res = await http.post(
        Uri.parse('$_base/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'role': role,
        }),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 || res.statusCode == 201) {
        return {
          'success': true,
          'token': body['access_token'],
          'role': body['role'],
          'user_id': body['user_id'],
          'name': body['name'],
        };
      }
      return {
        'success': false,
        'message': body['detail'] ?? 'Registration failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> registerForRace({
    required int raceId,
    required String city,
    required String contactNumber,
    required String emergencyContact,
    required String email,
    required bool isFirstMarathon,
    required String sex,
  }) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_base/races/$raceId/register'),
      headers: headers,
      body: jsonEncode({
        'city': city,
        'contact_number': contactNumber,
        'emergency_contact': emergencyContact,
        'is_first_marathon': isFirstMarathon,
        'sex': sex,
        'email': email,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception(body['detail'] ?? 'Registration failed');
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
  }

  // ── Token / Role / User persistence ──────────────────────────────────────

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  static Future<void> saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
  }

  // ── Auth header helper ────────────────────────────────────────────────────

  static Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Generic HTTP helpers (used by CheckpointService etc.) ─────────────────

  static Future<http.Response> get(String path) async {
    final headers = await _authHeaders();
    return http.get(Uri.parse('$_base$path'), headers: headers);
  }

  static Future<http.Response> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await _authHeaders();
    return http.post(
      Uri.parse('$_base$path'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  /// DELETE helper — used by CheckpointService.deleteCheckpoint
  static Future<http.Response> delete(String path) async {
    final headers = await _authHeaders();
    return http.delete(Uri.parse('$_base$path'), headers: headers);
  }

  // ── Races ─────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRaces() async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load races (${res.statusCode})');
  }

  static Future<void> createRace(Map<String, dynamic> payload) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_base/races/'),
      headers: headers,
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to create race');
    }
  }

  static Future<void> startRace(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_base/races/$raceId/start'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to start race');
    }
  }

  static Future<void> stopRace(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_base/races/$raceId/stop'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to stop race');
    }
  }

  // ── Leaderboard ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getLeaderboard(
      int raceId) async {
    final res = await http.get(
      Uri.parse('$_base/leaderboard/$raceId'),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = body['leaderboard'] as List? ?? [];
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load leaderboard (${res.statusCode})');
  }

  // ── Runners ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRaceRunners(
      int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId/runners'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load runners (${res.statusCode})');
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final headers = await _authHeaders();
      final res = await http.get(
        Uri.parse('$_base/users/profile'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    // Graceful offline fallback — return what we cached locally
    final prefs = await SharedPreferences.getInstance();
    return {
      'email': null,
      'contact_number': null,
      'city': null,
      'name': prefs.getString('user_name'),
    };
  }

  // ── Checkpoints ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCheckpoints(
      int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/checkpoints/$raceId'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load checkpoints (${res.statusCode})');
  }

  static Future<void> arriveAtCheckpoint(
    int checkpointId,
    int runnerId,
  ) async {
    final headers = await _authHeaders();
    await http.post(
      Uri.parse(
          '$_base/checkpoints/$checkpointId/arrive?runner_id=$runnerId'),
      headers: headers,
    );
  }

  /// Delete a single checkpoint by ID.
  static Future<void> deleteCheckpoint(int checkpointId) async {
    final headers = await _authHeaders();
    final res = await http.delete(
      Uri.parse('$_base/checkpoints/$checkpointId'),
      headers: headers,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to delete checkpoint');
    }
  }
}