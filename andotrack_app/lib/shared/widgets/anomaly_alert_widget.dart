// MOVED TO: lib/shared/widgets/anomaly_alert_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class AnomalyAlertOverlay extends StatefulWidget {
  final int raceId;
  const AnomalyAlertOverlay({super.key, required this.raceId});

  @override
  State<AnomalyAlertOverlay> createState() => _AnomalyAlertOverlayState();
}

class _AnomalyAlertOverlayState extends State<AnomalyAlertOverlay> {
  StreamSubscription? _sub;
  final List<_AnomalyAlert> _alerts = [];

  @override
  void initState() {
    super.initState();
    _listenToAnomalies();
  }

  void _listenToAnomalies() {
    final ref = FirebaseDatabase.instance
        .ref('races/${widget.raceId}/anomalies');

    _sub = ref.onChildAdded.listen((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      final runnerId = event.snapshot.key ?? 'Unknown';
      final reason = data['reason'] ?? 'Suspicious activity detected';
      final resolved = data['resolved'] ?? false;

      if (!resolved) {
        setState(() {
          // Remove any existing alert for this runner and add fresh one
          _alerts.removeWhere((a) => a.runnerId == runnerId);
          _alerts.insert(0, _AnomalyAlert(
            runnerId: runnerId,
            reason: reason,
            timestamp: DateTime.now(),
          ));
          // Keep max 5 alerts visible
          if (_alerts.length > 5) _alerts.removeLast();
        });
      }
    });

    // Also listen to updates (e.g., resolved = true)
    ref.onChildChanged.listen((event) {
      final rawChanged = event.snapshot.value;
      if (rawChanged is! Map) return;
      final data = Map<String, dynamic>.from(rawChanged);
      final runnerId = event.snapshot.key ?? '';
      final resolved = data['resolved'] ?? false;
      if (resolved) {
        setState(() {
          _alerts.removeWhere((a) => a.runnerId == runnerId);
        });
      }
    });
  }

  void _dismissAlert(_AnomalyAlert alert) {
    setState(() => _alerts.remove(alert));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_alerts.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Column(
        children: _alerts.map((alert) => _AnomalyCard(
          alert: alert,
          onDismiss: () => _dismissAlert(alert),
        )).toList(),
      ),
    );
  }
}

class _AnomalyAlert {
  final String runnerId;
  final String reason;
  final DateTime timestamp;

  _AnomalyAlert({
    required this.runnerId,
    required this.reason,
    required this.timestamp,
  });
}

class _AnomalyCard extends StatelessWidget {
  final _AnomalyAlert alert;
  final VoidCallback onDismiss;

  const _AnomalyCard({
    required this.alert,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade900,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.amber),
        title: Text(
          'Runner ${alert.runnerId}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          alert.reason,
          style: const TextStyle(color: Colors.white70),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: onDismiss,
        ),
      ),
    );
  }
}
