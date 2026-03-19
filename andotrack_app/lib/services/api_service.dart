import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  // Load token from shared_preferences
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<Map<String, String>> get _headers async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 401) {
      throw Exception('Invalid email or password');
    }

    final data = jsonDecode(response.body);

    // Save token to shared_preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', data['access_token']);
    await prefs.setString('role', data['role']);
    await prefs.setInt('user_id', data['user_id']);

    return data;
  }

  Future<List<dynamic>> getRaces() async {
    final response = await http.get(
      Uri.parse('$baseUrl/races'),
      headers: await _headers,
    );

    if (response.statusCode == 401) {
      throw Exception('Unauthorized — token expired');
    }

    return jsonDecode(response.body);
  }
}
