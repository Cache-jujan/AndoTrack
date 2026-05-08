import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
      static const String _base = 'https://andotrack-production.up.railway.app';  
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

  // ── Generic HTTP helpers ──────────────────────────────────────────────────

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

  static Future<http.Response> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await _authHeaders();
    return http.patch(
      Uri.parse('$_base$path'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  /// PUT helper — full replacement, used by CheckpointService.replaceCheckpoint
  static Future<http.Response> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final headers = await _authHeaders();
    return http.put(
      Uri.parse('$_base$path'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

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

  static Future<Map<String, dynamic>> getRace(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception(body['detail'] ?? 'Failed to load race');
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

  static Future<List<Map<String, dynamic>>> getLeaderboard(int raceId) async {
    try {
      final headers = await _authHeaders();
      final res = await http.get(
        Uri.parse('$_base/leaderboard/$raceId'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        // Backend may return {"leaderboard": [...]} or directly [...]
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
        if (decoded is Map<String, dynamic>) {
          final list = decoded['leaderboard'] as List? ?? [];
          return list.cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getRunnerStats(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/runners/stats/$raceId'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load stats (${res.statusCode})');
  }

  // ── Runners ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRaceRunners(int raceId) async {
    final headers = await _authHeaders();
    final url = '$_base/races/$raceId/runners';
    debugPrint('[API] GET $url');
    final res = await http.get(Uri.parse(url), headers: headers);
    debugPrint('[API] GET $url → ${res.statusCode}');
    debugPrint('[API] Body (first 500): ${res.body.substring(0, res.body.length.clamp(0, 500))}');
    if (res.statusCode == 200) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          debugPrint('[API] Parsed as List — ${decoded.length} runners');
          return decoded.cast<Map<String, dynamic>>();
        }
        if (decoded is Map<String, dynamic>) {
          final list = decoded['runners'] as List? ??
              decoded['registrations'] as List? ??
              decoded['data'] as List? ?? [];
          debugPrint('[API] Parsed as Map — key runners/registrations/data — ${list.length} items');
          return list.cast<Map<String, dynamic>>();
        }
        debugPrint('[API] WARNING: Unexpected response shape: ${decoded.runtimeType}');
        return [];
      } catch (e) {
        debugPrint('[API] PARSE ERROR on getRaceRunners: $e');
        debugPrint('[API] Raw body: ${res.body}');
        return [];
      }
    }
    if (res.statusCode == 404) {
      debugPrint('[API] 404 on $url — treating as empty list');
      return [];
    }
    debugPrint('[API] ERROR ${res.statusCode} on $url — body: ${res.body}');
    throw Exception('Failed to load runners (${res.statusCode}): ${res.body}');
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

    final prefs = await SharedPreferences.getInstance();
    return {
      'email': null,
      'contact_number': null,
      'city': null,
      'name': prefs.getString('user_name'),
    };
  }

  // ── Checkpoints ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCheckpoints(int raceId) async {
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
      Uri.parse('$_base/checkpoints/$checkpointId/arrive?runner_id=$runnerId'),
      headers: headers,
    );
  }

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

  // ── QR Check-In ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> checkInRunner({
    required int raceId,
    required String qrToken,
  }) async {
    final headers = await _authHeaders();
    final response = await http.post(
      Uri.parse('$_base/races/$raceId/checkin'),
      headers: headers,
      body: jsonEncode({'qr_token': qrToken}),
    );
    final body = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return body as Map<String, dynamic>;
    }
    final detail = body['detail']?.toString() ?? 'Check-in failed.';
    throw ApiException(detail);
  }

  static Future<Map<String, dynamic>> getRunnerQr({
    required int runnerId,
    required int raceId,
  }) async {
    final headers = await _authHeaders();
    final response = await http.get(
      Uri.parse('$_base/runners/$runnerId/qr?race_id=$raceId'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not fetch QR status.');
  }

  // ── Staff Accounts ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getStaffAccounts(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId/staff'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is List) return decoded.cast<Map<String, dynamic>>();
      return [];
    }
    if (res.statusCode == 404) return [];
    throw Exception('Failed to load staff (${res.statusCode})');
  }

  /// Creates a staff account for [raceId].
  /// Backend generates the temp password and returns it as `temp_password`.
  /// Params are sent as query params — the backend route uses FastAPI defaults.
  static Future<Map<String, dynamic>> createStaffAccount(
    int raceId, {
    required String name,
    required String email,
    required String role,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$_base/races/$raceId/staff').replace(
      queryParameters: {'name': name, 'email': email, 'role': role},
    );
    final res = await http.post(uri, headers: headers);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to create staff account');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to create staff account (${res.statusCode})');
    }
  }

  static Future<void> deactivateStaffAccount(int raceId, int staffId) async {
    final headers = await _authHeaders();
    final res = await http.patch(
      Uri.parse('$_base/races/$raceId/staff/$staffId/deactivate'),
      headers: headers,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        throw Exception(body['detail'] ?? 'Failed to deactivate staff account');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Failed to deactivate staff account (${res.statusCode})');
      }
    }
  }

  // ── Anomalies ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAnomalies(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/anomalies/$raceId'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list.cast<Map<String, dynamic>>();
    }
    if (res.statusCode == 404) return [];
    throw Exception('Failed to load anomalies (${res.statusCode})');
  }

  static Future<void> resolveAnomaly(int anomalyId) async {
    final headers = await _authHeaders();
    final res = await http.patch(
      Uri.parse('$_base/anomalies/$anomalyId/resolve'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to resolve anomaly');
    }
  }

  static Future<Map<String, dynamic>> getAnomalyReport(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/anomalies/$raceId/report'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    // Return a zeroed-out report when the endpoint isn't live yet
    return {
      'total': 0, 'vehicle_speed': 0, 'gps_jump': 0,
      'off_route': 0, 'erratic': 0,
      'resolved': 0, 'unresolved': 0,
      'flagged_runners': <dynamic>[],
    };
  }

  // ── Race settings update ──────────────────────────────────────────────────

  static Future<void> updateRaceSettings(
      int raceId, Map<String, dynamic> settings) async {
    final headers = await _authHeaders();
    final res = await http.patch(
      Uri.parse('$_base/races/$raceId'),
      headers: headers,
      body: jsonEncode(settings),
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(body['detail'] ?? 'Failed to update race settings');
    }
  }
}

// ── ApiException ──────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}