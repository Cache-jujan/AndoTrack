// MOVED TO: lib/core/models/runner_model.dart

class RunnerModel {
  final String runnerId;
  final double lat;
  final double lng;
  final double speed;
  final DateTime lastUpdated;

  RunnerModel({
    required this.runnerId,
    required this.lat,
    required this.lng,
    required this.speed,
    required this.lastUpdated,
  });

  factory RunnerModel.fromMap(String id, Map<dynamic, dynamic> data) {
    return RunnerModel(
      runnerId: id,
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
      speed: (data['speed'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        data['timestamp'] ?? 0,
      ),
    );
  }
}
