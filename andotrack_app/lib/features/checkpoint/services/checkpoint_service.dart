// lib/features/checkpoint/services/checkpoint_service.dart

import 'dart:convert';
import 'package:andotrack_app/core/services/api_service.dart';

class CheckpointService {
  // ── Create a single checkpoint ────────────────────────────────────────────

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
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to save checkpoint.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ── Bulk create checkpoints ───────────────────────────────────────────────
  // Backend has no /bulk endpoint — delete existing one-by-one then recreate.

  static Future<Map<String, dynamic>> createCheckpointsBulk({
    required int raceId,
    required List<Map<String, dynamic>> checkpoints,
    bool replaceExisting = true,
  }) async {
    try {
      if (replaceExisting) {
        final existing = await getCheckpoints(raceId);
        for (final cp in existing) {
          await ApiService.delete('/checkpoints/${cp['id']}');
        }
      }

      int created = 0;
      for (final cp in checkpoints) {
        final response = await ApiService.post('/checkpoints/', {
          'race_id': raceId,
          'name': cp['name'],
          'lat': cp['lat'],
          'lng': cp['lng'],
          'radius_meters': cp['radius_meters'] ?? 20,
          'order_number': cp['order_number'],
        });
        if (response.statusCode == 200 || response.statusCode == 201) {
          created++;
        }
      }

      return {
        'success': true,
        'data': {'message': '$created checkpoint(s) saved.'},
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ── GET checkpoints for a race ────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCheckpoints(int raceId) async {
    try {
      final response = await ApiService.get('/checkpoints/$raceId');
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        return list.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ── Full replace a checkpoint ─────────────────────────────────────────────
  // Backend has no PUT — delete then recreate with new values.

  static Future<Map<String, dynamic>> replaceCheckpoint({
    required int id,
    required int raceId,
    required String name,
    required double lat,
    required double lng,
    required int radiusMeters,
    required int orderNumber,
  }) async {
    try {
      await ApiService.delete('/checkpoints/$id');

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
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to update checkpoint.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ── Partial update a checkpoint ───────────────────────────────────────────
  // Backend has no PATCH — fetch current data, delete, then recreate merged.

  static Future<Map<String, dynamic>> updateCheckpoint({
    required int id,
    required int raceId,
    String? name,
    double? lat,
    double? lng,
    int? radiusMeters,
    int? orderNumber,
  }) async {
    try {
      // Fetch current values so we can merge with the partial update
      final existing = await getCheckpoints(raceId);
      final current = existing.firstWhere(
        (c) => c['id'] == id,
        orElse: () => <String, dynamic>{},
      );

      if (current.isEmpty) {
        return {'success': false, 'message': 'Checkpoint not found.'};
      }

      // Delete the old record
      await ApiService.delete('/checkpoints/$id');

      // Recreate with merged values (supplied value wins, falls back to current)
      final response = await ApiService.post('/checkpoints/', {
        'race_id': raceId,
        'name': name ?? current['name'],
        'lat': lat ?? (current['lat'] as num).toDouble(),
        'lng': lng ?? (current['lng'] as num).toDouble(),
        'radius_meters': radiusMeters ?? (current['radius_meters'] as num).toInt(),
        'order_number': orderNumber ?? (current['order_number'] as num).toInt(),
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to update checkpoint.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ── DELETE /checkpoints/{id} ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> deleteCheckpoint(int id) async {
    try {
      final response = await ApiService.delete('/checkpoints/$id');

      if (response.statusCode == 200 || response.statusCode == 204) {
        return {'success': true};
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to delete checkpoint.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ── Record arrival at a checkpoint ────────────────────────────────────────

  static Future<Map<String, dynamic>> recordArrival({
    required int checkpointId,
    required int runnerId,
  }) async {
    try {
      final response = await ApiService.post(
        '/checkpoints/$checkpointId/arrive?runner_id=$runnerId',
        {},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(response.body)};
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {
        'success': false,
        'message': data['detail'] ?? 'Failed to record arrival.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // ── Get runner checkpoint progress ────────────────────────────────────────

  static Future<Map<String, dynamic>?> getProgress({
    required int raceId,
    required int runnerId,
  }) async {
    try {
      final response = await ApiService.get(
        '/checkpoints/$raceId/runner/$runnerId/progress',
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}