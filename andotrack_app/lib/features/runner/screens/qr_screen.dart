import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/roles/runner_app/runner_dashboard_screen.dart';

class QrScreen extends StatefulWidget {
  final Map<String, dynamic> registrationData;
  final String raceName;

  const QrScreen({
    super.key,
    required this.registrationData,
    required this.raceName,
  });

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  final GlobalKey _qrKey = GlobalKey();
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _cacheQrData();
  }

  /// Persists QR base64 + token to SharedPreferences keyed by race_id.
  /// Called once on registration success so race_detail_screen can
  /// retrieve it on subsequent "View QR Code" taps.
  Future<void> _cacheQrData() async {
    final raceId = widget.registrationData['race_id'];
    final base64 = widget.registrationData['qr_image_base64']?.toString() ?? '';
    final token  = widget.registrationData['qr_token']?.toString() ?? '';
    if (raceId == null || base64.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('qr_base64_$raceId', base64);
    await prefs.setString('qr_token_$raceId', token);
  }

  Uint8List? get _qrBytes {
    final raw = widget.registrationData['qr_image_base64'];
    if (raw == null || raw.toString().trim().isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(raw.toString().trim()));
    } catch (_) {
      return null;
    }
  }

  bool get _hasQr => _qrBytes != null && _qrBytes!.isNotEmpty;

  Future<void> _saveToGallery() async {
    if (!_hasQr) return;
    setState(() => _saving = true);
    try {
      await Gal.putImageBytes(
        _qrBytes!,
        name: 'andotrack_qr_${widget.registrationData['race_id']}',
      );
      if (mounted) setState(() { _saving = false; _saved = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data       = widget.registrationData;
    final runnerName = data['runner_name'] ?? 'Runner';
    final raceName   = data['race_name']   ?? widget.raceName;
    final qrToken    = data['qr_token']    ?? '';
    final bytes      = _qrBytes;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        title: const Text('Your QR Code', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF00FF9C), size: 48),
            const SizedBox(height: 12),
            const Text(
              'Registration Successful!',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '$runnerName · $raceName',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),

            const SizedBox(height: 32),

            RepaintBoundary(
              key: _qrKey,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _hasQr ? Colors.white : const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(16),
                  border: _hasQr ? null : Border.all(color: const Color(0xFF1E1E30)),
                ),
                child: _hasQr
                    ? Image.memory(bytes!, width: 220, height: 220, fit: BoxFit.contain)
                    : SizedBox(
                        width: 220,
                        height: 220,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2_rounded, size: 64, color: Colors.white.withOpacity(0.1)),
                            const SizedBox(height: 12),
                            const Text('QR code not available yet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF444460), fontSize: 12)),
                            const SizedBox(height: 6),
                            const Text('The organizer will share it\nbefore race day.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF333348), fontSize: 11)),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            if (qrToken.isNotEmpty)
              Text(qrToken,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),

            const SizedBox(height: 12),

            const Text(
              'Show this QR code to the organizer on race day for check-in.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _saved ? const Color(0xFF00FF9C) : const Color(0xFF1E1E30),
                  foregroundColor: _saved ? Colors.black : Colors.white,
                  disabledBackgroundColor: const Color(0xFF0D0D14),
                  disabledForegroundColor: const Color(0xFF333348),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: (_saving || _saved || !_hasQr) ? null : _saveToGallery,
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_saved ? Icons.check : Icons.download),
                label: Text(_saved ? 'Saved to Gallery' : _hasQr ? 'Save QR to Gallery' : 'QR Not Available'),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF1E1E30)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const RunnerDashboardScreen()),
                    (_) => false,
                  );
                },
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
