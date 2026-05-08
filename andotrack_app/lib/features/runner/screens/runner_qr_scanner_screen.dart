import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:andotrack_app/core/services/api_service.dart';

class RunnerQrScannerScreen extends StatefulWidget {
  const RunnerQrScannerScreen({super.key});

  @override
  State<RunnerQrScannerScreen> createState() => _RunnerQrScannerScreenState();
}

class _RunnerQrScannerScreenState extends State<RunnerQrScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;
    final raw = barcode.rawValue ?? '';
    if (raw.isEmpty) return;

    // Organizer QR payload: "andotrack://checkin/{race_id}"
    final match = RegExp(r'andotrack://checkin/(\d+)').firstMatch(raw);
    if (match == null) {
      _showError('Not a valid AndoTrack check-in QR.');
      return;
    }

    setState(() => _processing = true);
    await _ctrl.stop();

    final raceId = int.parse(match.group(1)!);
    try {
      await ApiService.selfCheckIn(raceId: raceId);
      if (!mounted) return;
      Navigator.pop(context, true); // true = checked in successfully
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      _showError(e.message);
      await _ctrl.start();
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      _showError('Check-in failed. Try again.');
      await _ctrl.start();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF2A0A0A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera ─────────────────────────────────────────
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
          ),

          // ── Dark overlay with cutout ────────────────────────
          CustomPaint(
            painter: _ScanOverlayPainter(),
            child: const SizedBox.expand(),
          ),

          // ── Top bar ────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Scan to Check In',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Instruction ────────────────────────────────────
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_processing) ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Color(0xFF00FF9C), strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Checking you in…',
                    style: TextStyle(color: Color(0xFF00FF9C), fontSize: 14),
                  ),
                ] else
                  const Text(
                    'Point at the organizer\'s QR code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan frame overlay ────────────────────────────────────────────────────────

class _ScanOverlayPainter extends CustomPainter {
  static const double _frameSize = 240;
  static const double _cornerLen = 28;
  static const double _cornerWidth = 4;
  static const double _cornerRadius = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 40);
    final frameLeft = center.dx - _frameSize / 2;
    final frameTop = center.dy - _frameSize / 2;
    final frameRect =
        Rect.fromLTWH(frameLeft, frameTop, _frameSize, _frameSize);

    // Semi-transparent dark overlay
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.6);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
          frameRect, const Radius.circular(_cornerRadius)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    // Corner guides
    final cornerPaint = Paint()
      ..color = const Color(0xFF00FF9C)
      ..strokeWidth = _cornerWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corners = [
      [frameRect.topLeft, Offset(frameRect.left + _cornerLen, frameRect.top),
          Offset(frameRect.left, frameRect.top + _cornerLen)],
      [frameRect.topRight,
          Offset(frameRect.right - _cornerLen, frameRect.top),
          Offset(frameRect.right, frameRect.top + _cornerLen)],
      [frameRect.bottomLeft,
          Offset(frameRect.left + _cornerLen, frameRect.bottom),
          Offset(frameRect.left, frameRect.bottom - _cornerLen)],
      [frameRect.bottomRight,
          Offset(frameRect.right - _cornerLen, frameRect.bottom),
          Offset(frameRect.right, frameRect.bottom - _cornerLen)],
    ];

    for (final c in corners) {
      canvas.drawLine(c[1], c[0], cornerPaint);
      canvas.drawLine(c[0], c[2], cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
