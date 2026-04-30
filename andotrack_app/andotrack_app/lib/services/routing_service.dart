// ============================================================
// RoutingService
// ─────────────────────────────────────────────────────────────
// Provides:
//   • Road-based polyline routing via OSRM (free, no key needed)
//   • Forward & reverse geocoding via Nominatim
//   • Auto route generation from a start point + target distance
//
// OSRM public endpoint: https://router.project-osrm.org
// Nominatim endpoint:   https://nominatim.openstreetmap.org
// ============================================================

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RoutingService {
  static const String _osrmBase = 'https://router.project-osrm.org';
  static const String _nominatimBase = 'https://nominatim.openstreetmap.org';
  static const String _userAgent = 'AndoTrack/1.0 (andotrack@example.com)';

  // ── Road-based route between a list of waypoints ──────────────────────────

  /// Returns an ordered list of [LatLng] points that follow real roads
  /// between each supplied waypoint (checkpoint).
  /// Falls back to straight-line segments on failure.
  static Future<List<LatLng>> getRoutePolyline(
    List<LatLng> waypoints,
  ) async {
    if (waypoints.length < 2) return waypoints;

    // Build OSRM coords string: lng,lat;lng,lat;...
    final coords = waypoints
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');

    final uri = Uri.parse(
      '$_osrmBase/route/v1/foot/$coords'
      '?overview=full&geometries=geojson&steps=false',
    );

    try {
      final res = await http.get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return _straightLine(waypoints);

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return _straightLine(waypoints);

      final routes = body['routes'] as List;
      if (routes.isEmpty) return _straightLine(waypoints);

      final geometry = routes[0]['geometry'] as Map<String, dynamic>;
      final coords2 = geometry['coordinates'] as List;

      // GeoJSON: [lng, lat]
      return coords2
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
    } catch (_) {
      return _straightLine(waypoints);
    }
  }

  /// Straight-line fallback (original behavior).
  static List<LatLng> _straightLine(List<LatLng> pts) => pts;

  // ── Auto route generation ─────────────────────────────────────────────────

  /// Generates an out-and-back or loop route of approximately [targetKm] km
  /// starting from [start], following real roads.
  ///
  /// Strategy:
  ///   1. Picks a bearing (default: east) and computes a naive midpoint
  ///      at targetKm/2 from start (for out-and-back).
  ///   2. Snaps the midpoint to the nearest road via OSRM nearest API.
  ///   3. Routes start → midpoint → start and trims/extends to match distance.
  static Future<AutoRouteResult> generateRoute({
    required LatLng start,
    required double targetKm,
    double bearingDeg = 90.0, // default: head east
  }) async {
    // Step 1: naive midpoint (half distance in chosen direction)
    final midpoint = _offsetPoint(start, targetKm / 2 * 1000, bearingDeg);

    // Step 2: snap midpoint to nearest road
    final snapped = await _snapToRoad(midpoint) ?? midpoint;

    // Step 3: route out + back
    final outPoints = await getRoutePolyline([start, snapped]);
    final backPoints = await getRoutePolyline([snapped, start]);

    final fullRoute = [...outPoints, ...backPoints.skip(1)];

    // Step 4: measure actual distance
    final actualKm = _measureDistanceKm(fullRoute);

    // Step 5: generate auto-checkpoints at 25%, 50%, 75%, 100%
    final autoCheckpoints = _sampleAlongRoute(
      fullRoute,
      fractions: [0.0, 0.25, 0.5, 0.75, 1.0],
    );

    return AutoRouteResult(
      polyline: fullRoute,
      actualDistanceKm: actualKm,
      suggestedCheckpoints: autoCheckpoints,
    );
  }

  /// Snaps a point to the nearest road segment using OSRM /nearest.
  static Future<LatLng?> _snapToRoad(LatLng point) async {
    final uri = Uri.parse(
      '$_osrmBase/nearest/v1/foot/${point.longitude},${point.latitude}?number=1',
    );
    try {
      final res = await http.get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final waypoints = body['waypoints'] as List;
      if (waypoints.isEmpty) return null;
      final loc = waypoints[0]['location'] as List;
      return LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble());
    } catch (_) {
      return null;
    }
  }

  // ── Geocoding ─────────────────────────────────────────────────────────────

  /// Forward geocoding: text → list of candidate locations.
  static Future<List<GeocodingResult>> searchPlaces(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(
      '$_nominatimBase/search'
      '?q=${Uri.encodeComponent(query)}'
      '&format=json&limit=5&addressdetails=1',
    );

    try {
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return [];

      final list = jsonDecode(res.body) as List;
      return list.map((item) {
        return GeocodingResult(
          displayName: item['display_name'] ?? '',
          shortName: _buildShortName(item),
          lat: double.parse(item['lat'] as String),
          lng: double.parse(item['lon'] as String),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Reverse geocoding: LatLng → human-readable address.
  static Future<String?> reverseGeocode(LatLng point) async {
    final uri = Uri.parse(
      '$_nominatimBase/reverse'
      '?lat=${point.latitude}&lon=${point.longitude}'
      '&format=json&addressdetails=1',
    );

    try {
      final res = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Geometry helpers ──────────────────────────────────────────────────────

  /// Haversine distance of a polyline in km.
  static double _measureDistanceKm(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      total += _haversineKm(pts[i], pts[i + 1]);
    }
    return total;
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = _toRad(b.latitude - a.latitude);
    final dLon = _toRad(b.longitude - a.longitude);
    final sinDLat = sin(dLat / 2);
    final sinDLon = sin(dLon / 2);
    final h = sinDLat * sinDLat +
        cos(_toRad(a.latitude)) * cos(_toRad(b.latitude)) * sinDLon * sinDLon;
    return 2 * r * asin(sqrt(h));
  }

  static double _toRad(double deg) => deg * pi / 180;

  /// Projects a point [distanceM] metres from [origin] at [bearingDeg].
  static LatLng _offsetPoint(LatLng origin, double distanceM, double bearingDeg) {
    const r = 6371000.0;
    final bearing = _toRad(bearingDeg);
    final lat1 = _toRad(origin.latitude);
    final lon1 = _toRad(origin.longitude);
    final d = distanceM / r;

    final lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(bearing));
    final lon2 = lon1 +
        atan2(
          sin(bearing) * sin(d) * cos(lat1),
          cos(d) - sin(lat1) * sin(lat2),
        );

    return LatLng(lat2 * 180 / pi, lon2 * 180 / pi);
  }

  /// Samples points along a polyline at given fractions [0.0 … 1.0].
  static List<LatLng> _sampleAlongRoute(
    List<LatLng> route, {
    required List<double> fractions,
  }) {
    final totalKm = _measureDistanceKm(route);
    final result = <LatLng>[];

    for (final frac in fractions) {
      final targetKm = totalKm * frac;
      double cumKm = 0;
      for (int i = 0; i < route.length - 1; i++) {
        final segKm = _haversineKm(route[i], route[i + 1]);
        if (cumKm + segKm >= targetKm) {
          final t = (targetKm - cumKm) / segKm;
          result.add(LatLng(
            route[i].latitude + t * (route[i + 1].latitude - route[i].latitude),
            route[i].longitude +
                t * (route[i + 1].longitude - route[i].longitude),
          ));
          break;
        }
        cumKm += segKm;
      }
    }

    // Always include last point
    if (result.length < fractions.length && route.isNotEmpty) {
      result.add(route.last);
    }

    return result;
  }

  /// Builds a short readable name from Nominatim address details.
  static String _buildShortName(Map<String, dynamic> item) {
    final addr = item['address'] as Map<String, dynamic>?;
    if (addr == null) return item['display_name'] as String? ?? '';
    final parts = <String>[];
    for (final key in ['road', 'suburb', 'city', 'town', 'village', 'county']) {
      if (addr.containsKey(key)) {
        parts.add(addr[key] as String);
        if (parts.length >= 2) break;
      }
    }
    return parts.isNotEmpty ? parts.join(', ') : (item['display_name'] ?? '');
  }
}

// ── Result models ─────────────────────────────────────────────────────────────

class GeocodingResult {
  final String displayName;
  final String shortName;
  final double lat;
  final double lng;

  const GeocodingResult({
    required this.displayName,
    required this.shortName,
    required this.lat,
    required this.lng,
  });

  LatLng get latLng => LatLng(lat, lng);
}

class AutoRouteResult {
  final List<LatLng> polyline;
  final double actualDistanceKm;
  final List<LatLng> suggestedCheckpoints;

  const AutoRouteResult({
    required this.polyline,
    required this.actualDistanceKm,
    required this.suggestedCheckpoints,
  });
}