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
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
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
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
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

class _AnomalyCard extends StatefulWidget {
  final _AnomalyAlert alert;
  final VoidCallback onDismiss;

  const _AnomalyCard({required this.alert, required this.onDismiss});

  @override
  State<_AnomalyCard> createState() => _AnomalyCardState();
}

class _AnomalyCardState extends State<_AnomalyCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    // Auto-dismiss after 8 seconds
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0A0A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF4D4D), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF4D4D).withOpacity(0.25),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D4D).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFFF4D4D),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '⚠ Runner #${widget.alert.runnerId}',
                          style: const TextStyle(
                            color: Color(0xFFFF4D4D),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatTime(widget.alert.timestamp),
                          style: const TextStyle(
                            color: Color(0xFF666680),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.alert.reason,
                      style: const TextStyle(
                        color: Color(0xFFCCCCDD),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onDismiss,
                child: const Icon(
                  Icons.close,
                  color: Color(0xFF666680),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}