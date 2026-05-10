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
      ).timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        return {
          'success': true,
          'token':   body['access_token'],
          'role':    body['role'],
          'user_id': body['user_id'],
          'name':    body['name'],
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
  required String shirtSize,
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
        'shirt_size': shirtSize,
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

  // Returns ALL races — keep plural
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

// Returns ONE race by ID — singular
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
        // Backend returns directly as a list (live leaderboard endpoint)
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
        // Backend returns {"finished": [...], "racing": [...], ...}
        if (decoded is Map<String, dynamic>) {
          final finished =
              (decoded['finished'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          if (finished.isNotEmpty) return finished;
          // Fall back to still-racing entries (live race context)
          final racing =
              (decoded['racing'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          return racing;
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
    final res = await http.get(Uri.parse(url), headers: headers);
    if (res.statusCode == 200) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
        if (decoded is Map<String, dynamic>) {
          final list = decoded['runners'] as List? ??
              decoded['registrations'] as List? ??
              decoded['data'] as List? ?? [];
          return list.cast<Map<String, dynamic>>();
        }
        return [];
      } catch (e) {
        debugPrint('[API] PARSE ERROR on getRaceRunners: $e');
        return [];
      }
    }
    if (res.statusCode == 404) return [];
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
    final res = await http.post(
      Uri.parse('$_base/checkpoints/$checkpointId/arrive?runner_id=$runnerId'),
      headers: headers,
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(
          'Checkpoint arrive failed (${res.statusCode}): ${res.body}');
    }
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

  static Future<void> selfCheckIn({required int raceId}) async {
    final headers = await _authHeaders();
    final res = await http.post(
      Uri.parse('$_base/races/$raceId/checkin/self'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      try {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        throw ApiException(body['detail']?.toString() ?? 'Check-in failed (${res.statusCode}).');
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException('Check-in failed (${res.statusCode}). Please try again.');
      }
    }
  }

  static Future<Map<String, dynamic>> getRunnerResults(int runnerId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/runners/$runnerId/results'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load results.');
  }

  // ── Staff accounts ────────────────────────────────────────────────────────



  static Future<List<Map<String, dynamic>>> getPublicRaces() async {
    final res = await http.get(Uri.parse('$_base/races/public'));
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getStaffAccounts(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId/staff'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    }
    throw ApiException('Could not load staff accounts.');
  }

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
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final detail = body['detail'];
    throw ApiException(
      detail is String ? detail : 'Failed to create staff account.',
    );
  }

  static Future<void> deactivateStaffAccount(int raceId, int staffId) async {
    final headers = await _authHeaders();
    final res = await http.patch(
      Uri.parse('$_base/races/$raceId/staff/$staffId/deactivate'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['detail'] ?? 'Failed to deactivate staff.');
    }
  }

  static Future<Map<String, dynamic>> resetStaffPassword(
      int raceId, int staffId) async {
    final headers = await _authHeaders();
    final res = await http.patch(
      Uri.parse('$_base/races/$raceId/staff/$staffId/reset-password'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    throw ApiException(body['detail'] ?? 'Failed to reset password.');
  }

  // ── Anomalies ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAnomalies(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId/anomalies'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  static Future<void> resolveAnomaly(int raceId, int anomalyId) async {
    final headers = await _authHeaders();
    await http.patch(
      Uri.parse('$_base/races/$raceId/anomalies/$anomalyId/resolve'),
      headers: headers,
    );
  }

  static Future<Map<String, dynamic>> getAnomalyReport(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId/anomalies'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      final all = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      final resolved   = all.where((a) => a['resolved'] == true).length;
      final unresolved = all.length - resolved;
      final counts = <String, int>{};
      for (final a in all) { counts[a['reason']?.toString() ?? 'unknown'] = (counts[a['reason']?.toString() ?? 'unknown'] ?? 0) + 1; }
      return {
        'total':         all.length,
        'vehicle_speed': counts['vehicle_speed'] ?? 0,
        'gps_jump':      counts['gps_jump'] ?? 0,
        'off_route':     counts['off_route'] ?? 0,
        'erratic':       counts['erratic'] ?? 0,
        'resolved':      resolved,
        'unresolved':    unresolved,
        'flagged_runners': all.map((a) => a['runner_id']).toSet().toList(),
      };
    }
    throw ApiException('Could not load anomaly report.');
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  /// Returns the full analytics payload for a finished race.
  /// Requires organizer role. Only available after race is finished.
  static Future<Map<String, dynamic>> getAnalytics(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId/analytics'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load analytics (${res.statusCode}).');
  }

  /// Returns segment-filtered runner list.
  /// [segment] must be one of: 'all', 'competitive', 'recreational', 'casual'.
  static Future<Map<String, dynamic>> exportSegment(
    int raceId,
    String segment,
  ) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/races/$raceId/analytics/export?segment=$segment'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not export segment (${res.statusCode}).');
  }

  // ── Race settings ─────────────────────────────────────────────────────────

  static Future<void> updateRaceSettings(
      int raceId, Map<String, dynamic> settings) async {
    final headers = await _authHeaders();
    await http.put(
      Uri.parse('$_base/races/$raceId'),
      headers: headers,
      body: jsonEncode(settings),
    );
  }

  // ── Kit claiming ──────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getKitRunners(int raceId) async {
    final headers = await _authHeaders();
    final res = await http.get(
      Uri.parse('$_base/kit/$raceId/runners?status=all'),
      headers: headers,
    );
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    }
    throw ApiException('Could not load registrations.');
  }

  static Future<void> claimKit(int raceId, int runnerId) async {
    final headers = await _authHeaders();
    final res = await http.patch(
      Uri.parse('$_base/kit/$raceId/runners/$runnerId/claim'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['detail'] ?? 'Claim failed.');
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
