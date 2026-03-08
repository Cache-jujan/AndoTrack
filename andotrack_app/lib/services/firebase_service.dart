import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';

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

  // Location Permission Helper
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  //Gets Location and Updates Firebase
  Future<void> updateMyLocation({
    required String raceId,
    required String runnerId,
  }) async {
    final position = await _determinePosition();

    updateRunnerLocation(
      raceId: raceId,
      runnerId: runnerId,
      lat: position.latitude,
      lng: position.longitude,
      speed: position.speed,
    );
  }

    Stream<DatabaseEvent> watchRaceRunners(String raceId) {
    return _db.ref('races/$raceId/runners').onValue;
  }

  Stream<Position> startLocationStream() {
  return Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, 
    )
  );
 }
}