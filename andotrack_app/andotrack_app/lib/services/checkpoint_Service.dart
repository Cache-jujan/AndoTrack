import '../config/app_config.dart';
import '../services/api_service.dart';
import 'dart:convert';

class CheckpointService {
  // ── Create a checkpoint ───────────────────────────────

  static Future<Map<String, dynamic>> createCheckpoint({
    required int raceId,
    required String name,
    required double lat,
    required double lng,
    required int radiusMeters,
    required int orderNumber,
  }) async {
    try {
      final response = await ApiService.post('/checkpoints/', {
        'race_id': raceId,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius_meters': radiusMeters,
        'order_number': orderNumber,
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to save checkpoint.',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ── Get checkpoints for a race ────────────────────────

  static Future<List<dynamic>> getCheckpoints(int raceId) async {
    try {
      final response = await ApiService.get('/checkpoints/$raceId');
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ── Delete a checkpoint ───────────────────────────────

  static Future<Map<String, dynamic>> deleteCheckpoint(int id) async {
    try {
      final response = await ApiService.delete('/checkpoints/$id');
      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['detail'] ?? 'Failed to delete checkpoint.',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}