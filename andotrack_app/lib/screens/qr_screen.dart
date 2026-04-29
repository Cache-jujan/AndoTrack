import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'race_list_screen.dart';

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

Future<void> _saveToGallery() async {
  setState(() => _saving = true);
  try {
    final base64Str = widget.registrationData['qr_image_base64'] as String;
    final bytes = Uint8List.fromList(base64Decode(base64Str));
    await Gal.putImageBytes(bytes,
        name: 'andotrack_qr_${widget.registrationData['race_id']}');
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
    final data = widget.registrationData;
    final runnerName = data['runner_name'] ?? 'Runner';
    final raceName = data['race_name'] ?? widget.raceName;
    final qrBase64 = data['qr_image_base64'] as String?;
    final qrToken = data['qr_token'] ?? '';

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

            // ── Success header ──────────────────────────────
            const Icon(Icons.check_circle, color: Color(0xFF00FF9C), size: 48),
            const SizedBox(height: 12),
            const Text('Registration Successful!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('$runnerName · $raceName',
                style: const TextStyle(color: Colors.white38, fontSize: 13)),

            const SizedBox(height: 32),

            // ── QR Image ────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: RepaintBoundary(
                key: _qrKey,
                child: qrBase64 != null
                    ? Image.memory(
                        base64Decode(qrBase64),
                        width: 220,
                        height: 220,
                        fit: BoxFit.contain,
                      )
                    : const SizedBox(
                        width: 220,
                        height: 220,
                        child: Center(
                          child: Text('QR not available',
                              style: TextStyle(color: Colors.black54)),
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Token ───────────────────────────────────────
            Text(
              qrToken,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontFamily: 'monospace'),
            ),

            const SizedBox(height: 12),

            const Text(
              'Show this QR code to the organizer on race day for check-in.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),

            const SizedBox(height: 32),

            // ── Save button ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _saved
                      ? const Color(0xFF00FF9C)
                      : const Color(0xFF1E1E30),
                  foregroundColor: _saved ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saving || _saved ? null : _saveToGallery,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_saved ? Icons.check : Icons.download),
                label: Text(_saved ? 'Saved to Gallery' : 'Save QR to Gallery'),
              ),
            ),

            const SizedBox(height: 12),

            // ── Done button ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF1E1E30)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const RaceListScreen()),
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