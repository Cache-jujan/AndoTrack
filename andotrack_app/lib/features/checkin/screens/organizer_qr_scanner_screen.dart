// DEPRECATED — NOT IN USE
// ═══════════════════════════════════════════════════════════════════════════
// OrganizerQrScannerScreen was the original check-in tool: a single-role,
// mobile-camera QR scanner wired directly to the organizer account.
//
// It has been superseded by two purpose-built replacements:
//
//   1. roles/checkin_staff/screens/checkin_dashboard_screen.dart
//      — Dedicated WEB dashboard for Check-in Staff. Supports search,
//        batch operations, walk-in registration, and live runner status.
//        Staff accounts are provisioned by the Race Director per-race.
//
//   2. roles/race_director/screens/live_race_dashboard_screen.dart
//      — Race Director's live map view. Shows real-time GPS positions,
//        anomaly detection, and runner status during an active race.
//        The Race Director no longer needs a hand-held QR scanner.
//
// No shells, routes, or screens import this file. It is kept here only as
// an archaeological record of the v1 check-in architecture.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/core/services/api_service.dart';

class OrganizerQrScannerScreen extends StatefulWidget {
  final int raceId;
  final String raceName;

  const OrganizerQrScannerScreen({
    super.key,
    required this.raceId,
    required this.raceName,
  });

  @override
  State<OrganizerQrScannerScreen> createState() =>
      _OrganizerQrScannerScreenState();
}

class _OrganizerQrScannerScreenState
    extends State<OrganizerQrScannerScreen> {
  // ── Scanner controller ────────────────────────────────────
  final MobileScannerController _scannerCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  // ── State ─────────────────────────────────────────────────
  bool _processing = false;
  bool _torchOn = false;

  // Scan result shown as overlay until dismissed
  _ScanResult? _lastResult;

  // ── Offline queue ─────────────────────────────────────────
  // Stores QR tokens that couldn't be sent due to no internet.
  // Re-sent automatically when connectivity returns.
  final List<String> _offlineQueue = [];
  StreamSubscription<List<ConnectivityResult>>? _connectSub;

  // ── Counters shown in top bar ─────────────────────────────
  int _successCount = 0;
  int _failCount = 0;

  // ── INIT / DISPOSE ────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadOfflineQueue();
    _listenConnectivity();
  }

  @override
  void dispose() {
    _scannerCtrl.dispose();
    _connectSub?.cancel();
    super.dispose();
  }

  // ── Offline queue persistence ─────────────────────────────

  Future<void> _loadOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final saved =
        prefs.getStringList('offline_checkin_queue_${widget.raceId}') ?? [];
    if (saved.isNotEmpty) {
      setState(() => _offlineQueue.addAll(saved));
      // Attempt immediate sync
      _syncOfflineQueue();
    }
  }

  Future<void> _saveOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'offline_checkin_queue_${widget.raceId}', _offlineQueue);
  }

  void _listenConnectivity() {
    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.isNotEmpty &&
          !results.contains(ConnectivityResult.none);
      if (online && _offlineQueue.isNotEmpty) {
        _syncOfflineQueue();
      }
    });
  }

  Future<void> _syncOfflineQueue() async {
    if (_offlineQueue.isEmpty) return;
    final toSync = List<String>.from(_offlineQueue);
    for (final token in toSync) {
      try {
        await ApiService.checkInRunner(
          raceId: widget.raceId,
          qrToken: token,
        );
        _offlineQueue.remove(token);
        if (mounted) setState(() => _successCount++);
      } catch (_) {
        // Keep in queue — will retry next time
      }
    }
    await _saveOfflineQueue();
  }

  // ── QR detection handler ──────────────────────────────────

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing || _lastResult != null) return;

    final raw = capture.barcodes
        .where((b) => b.rawValue != null)
        .map((b) => b.rawValue!)
        .firstOrNull;

    if (raw == null) return;

    // Validate AndoTrack token format before sending to server
    if (!raw.startsWith('ANDOTRACK:')) {
      _showResult(_ScanResult(
        success: false,
        title: 'Invalid QR',
        subtitle: 'This QR code is not an AndoTrack check-in token.',
        token: raw,
      ));
      return;
    }

    // Validate that the token belongs to this race
    final parts = raw.split(':');
    if (parts.length == 4) {
      final tokenRaceId = int.tryParse(parts[1]);
      if (tokenRaceId != null && tokenRaceId != widget.raceId) {
        _showResult(_ScanResult(
          success: false,
          title: 'Wrong Race',
          subtitle:
              'This QR is for race #$tokenRaceId, not race #${widget.raceId}.',
          token: raw,
        ));
        return;
      }
    }

    setState(() => _processing = true);

    // Check connectivity
    final conn = await Connectivity().checkConnectivity();
    final isOnline = conn != ConnectivityResult.none;

    if (!isOnline) {
      // Queue for later and show a pending result
      _offlineQueue.add(raw);
      await _saveOfflineQueue();
      if (mounted) {
        setState(() => _processing = false);
        _showResult(_ScanResult(
          success: true,
          title: 'Queued (Offline)',
          subtitle:
              'No internet. Scan recorded — will sync automatically when you reconnect.',
          token: raw,
          isPending: true,
        ));
      }
      return;
    }

    // Online — call the check-in endpoint
    try {
      final response = await ApiService.checkInRunner(
        raceId: widget.raceId,
        qrToken: raw,
      );
      final runnerName =
          response['runner_name']?.toString() ?? 'Runner';
      if (mounted) {
        setState(() {
          _processing = false;
          _successCount++;
        });
        _showResult(_ScanResult(
          success: true,
          title: '✓ Checked In',
          subtitle: '$runnerName is now validated for ${widget.raceName}.',
          token: raw,
        ));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _processing = false;
          _failCount++;
        });
        _showResult(_ScanResult(
          success: false,
          title: 'Check-In Failed',
          subtitle: e.message,
          token: raw,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _processing = false;
          _failCount++;
        });
        _showResult(_ScanResult(
          success: false,
          title: 'Error',
          subtitle: e.toString(),
          token: raw,
        ));
      }
    }
  }

  void _showResult(_ScanResult result) {
    // Pause scanner while showing result
    _scannerCtrl.stop();
    setState(() => _lastResult = result);
  }

  void _dismissResult() {
    setState(() => _lastResult = null);
    _scannerCtrl.start();
  }

  void _toggleTorch() {
    _scannerCtrl.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  // ── BUILD ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Camera feed ───────────────────────────────
            MobileScanner(
              controller: _scannerCtrl,
              onDetect: _onDetect,
            ),

            // ── Dark vignette + scan frame ─────────────────
            _buildScanOverlay(),

            // ── Top bar ────────────────────────────────────
            _buildTopBar(),

            // ── Bottom controls ────────────────────────────
            _buildBottomBar(),

            // ── Processing spinner ─────────────────────────
            if (_processing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF00FF9C),
                    strokeWidth: 2,
                  ),
                ),
              ),

            // ── Result overlay ─────────────────────────────
            if (_lastResult != null)
              _buildResultOverlay(_lastResult!),
          ],
        ),
      ),
    );
  }

  // ── Scan frame overlay ────────────────────────────────────

  Widget _buildScanOverlay() {
    return CustomPaint(
      size: MediaQuery.of(context).size,
      painter: _ScanFramePainter(),
    );
  }

  // ── Top bar ───────────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // Back
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.arrow_back,
                    color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),

            // Title + race name
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('QR Check-In Scanner',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    Text(
                      widget.raceName,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Counters
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _CountBadge(
                    count: _successCount,
                    color: const Color(0xFF00FF9C),
                    icon: Icons.check),
                const SizedBox(height: 4),
                _CountBadge(
                    count: _failCount,
                    color: const Color(0xFFFF4D4D),
                    icon: Icons.close),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 32,
      left: 0,
      right: 0,
      child: Column(
        children: [
          // Hint text
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Point the camera at a runner\'s QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),

          // Torch toggle
          GestureDetector(
            onTap: _toggleTorch,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _torchOn
                    ? const Color(0xFF00FF9C).withOpacity(0.2)
                    : Colors.black54,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _torchOn
                      ? const Color(0xFF00FF9C)
                      : Colors.white24,
                ),
              ),
              child: Icon(
                _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                color: _torchOn
                    ? const Color(0xFF00FF9C)
                    : Colors.white54,
                size: 24,
              ),
            ),
          ),

          // Offline queue indicator
          if (_offlineQueue.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFFFB800).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off,
                      color: Color(0xFFFFB800), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '${_offlineQueue.length} scan(s) queued offline',
                    style: const TextStyle(
                        color: Color(0xFFFFB800), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Result overlay ────────────────────────────────────────

  Widget _buildResultOverlay(_ScanResult result) {
    final color = result.isPending
        ? const Color(0xFFFFB800)
        : result.success
            ? const Color(0xFF00FF9C)
            : const Color(0xFFFF4D4D);

    final icon = result.isPending
        ? Icons.cloud_off_rounded
        : result.success
            ? Icons.check_circle_rounded
            : Icons.error_rounded;

    return Container(
      color: Colors.black.withOpacity(0.85),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 72),
              const SizedBox(height: 16),
              Text(
                result.title,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                result.subtitle,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _dismissResult,
                  child: const Text(
                    'Scan Next Runner',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _ScanResult {
  final bool success;
  final String title;
  final String subtitle;
  final String token;
  final bool isPending;

  _ScanResult({
    required this.success,
    required this.title,
    required this.subtitle,
    required this.token,
    this.isPending = false,
  });
}

// ── Count badge ───────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final IconData icon;

  const _CountBadge(
      {required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text('$count',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ── Scan frame painter ────────────────────────────────────────────────────────

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..style = PaintingStyle.fill;

    // Frame dimensions
    final frameSize = size.width * 0.68;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final left = cx - frameSize / 2;
    final top = cy - frameSize / 2;
    final right = cx + frameSize / 2;
    final bottom = cy + frameSize / 2;
    final frameRect = Rect.fromLTRB(left, top, right, bottom);

    // Dark vignette around frame
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
          frameRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    // Corner brackets
    const cornerLen = 24.0;
    const cornerStroke = 3.5;
    const cornerRadius = 4.0;
    final cornerPaint = Paint()
      ..color = const Color(0xFF00FF9C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cornerStroke
      ..strokeCap = StrokeCap.round;

    // Top-left
    canvas.drawPath(
        Path()
          ..moveTo(left + cornerRadius, top)
          ..lineTo(left + cornerLen, top)
          ..moveTo(left, top + cornerRadius)
          ..lineTo(left, top + cornerLen),
        cornerPaint);
    // Top-right
    canvas.drawPath(
        Path()
          ..moveTo(right - cornerLen, top)
          ..lineTo(right - cornerRadius, top)
          ..moveTo(right, top + cornerRadius)
          ..lineTo(right, top + cornerLen),
        cornerPaint);
    // Bottom-left
    canvas.drawPath(
        Path()
          ..moveTo(left, bottom - cornerLen)
          ..lineTo(left, bottom - cornerRadius)
          ..moveTo(left + cornerRadius, bottom)
          ..lineTo(left + cornerLen, bottom),
        cornerPaint);
    // Bottom-right
    canvas.drawPath(
        Path()
          ..moveTo(right, bottom - cornerLen)
          ..lineTo(right, bottom - cornerRadius)
          ..moveTo(right - cornerLen, bottom)
          ..lineTo(right - cornerRadius, bottom),
        cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
