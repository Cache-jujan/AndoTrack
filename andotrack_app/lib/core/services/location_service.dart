// MOVED TO: lib/core/services/location_service.dart

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// Requests location permission and returns true if granted.
  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Returns true if location permission is currently granted (no prompt).
  static Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Returns true if location services are enabled on the device.
  static Future<bool> isServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  /// Gets the current position once (high accuracy).
  /// Returns null if permission is denied or service unavailable.
  static Future<LatLng?> getCurrentLatLng() async {
    try {
      final granted = await requestPermission();
      if (!granted) return null;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Continuous GPS stream, filtered to ≥5 m movement, high accuracy.
  static Stream<Position> getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );
  }
}
