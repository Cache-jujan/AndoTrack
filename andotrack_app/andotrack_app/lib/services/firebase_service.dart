import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  final _db = FirebaseDatabase.instance;

  void updateRunnerLocation({
    required String raceId,
    required String runnerId,
    required double lat,
    required double lng,
    required double speed,
  }) {
    _db.ref('races/$raceId/runners/$runnerId').set({
      'lat': lat,
      'lng': lng,
      'speed': speed,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<DatabaseEvent> watchRaceRunners(String raceId) {
    return _db.ref('races/$raceId/runners').onValue;
  }
}