import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class RunnerCheckinGateScreen extends StatefulWidget {
  final int raceId;
  final int runnerId;
  final String raceName;

  const RunnerCheckinGateScreen({
    super.key,
    required this.raceId,
    required this.runnerId,
    required this.raceName,
  });

  @override
  State<RunnerCheckinGateScreen> createState() =>
      _RunnerCheckinGateScreenState();
}

class _RunnerCheckinGateScreenState
    extends State<RunnerCheckinGateScreen>
    with SingleTickerProviderStateMixin {
  // ── Poll timer ────────────────────────────────────────────
  Timer? _pollTimer;
  bool _polling = false;
  bool _validated = false;
  bool _initialLoading = true;
  String? _error;
  int _secondsUntilNextPoll = 10;
  Timer? _countdownTimer;

  // ── QR image ──────────────────────────────────────────────
  Uint8List? _qrBytes;
  String? _qrToken;

  // ── Animation (pulse when validated) ─────────────────────
  late AnimationController _animCtrl;
  late Animation<double> _pulseAnim;

  // ── INIT / DISPOSE ────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
    _animCtrl.repeat(reverse: true);

    _loadQrAndCheck();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Load QR from cache or API ─────────────────────────────

  Future<void> _loadQrAndCheck() async {
    // Try local cache first
    final prefs = await SharedPreferences.getInstance();
    final cachedB64 = prefs.getString('qr_base64_${widget.raceId}');
    final cachedToken = prefs.getString('qr_token_${widget.raceId}');

    if (cachedB64 != null && cachedB64.isNotEmpty) {
      try {
        _qrBytes = Uint8List.fromList(base64Decode(cachedB64));
        _qrToken = cachedToken;
      } catch (_) {}
    }

    // Always check validation status from API
    await _checkValidation();

    // Start polling only if not yet validated
    if (!_validated) {
      _startPolling();
    }
  }

  Future<void> _checkValidation() async {
    if (_polling) return;
    setState(() {
      _polling = true;
      _error = null;
    });

    try {
      final data = await ApiService.getRunnerQr(
        runnerId: widget.runnerId,
        raceId: widget.raceId,
      );

      final isPresent = data['is_present'] == true;

      // Update QR image if we didn't have it
      if (_qrBytes == null) {
        final b64 = data['qr_image_base64']?.toString() ?? '';
        if (b64.isNotEmpty) {
          try {
            _qrBytes = Uint8List.fromList(base64Decode(b64));
            _qrToken = data['qr_token']?.toString();
            // Cache it
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('qr_base64_${widget.raceId}', b64);
            await prefs.setString(
                'qr_token_${widget.raceId}', _qrToken ?? '');
          } catch (_) {}
        }
      }

      if (isPresent) {
        await _handleValidated();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not reach server.');
    } finally {
      if (mounted) {
        setState(() {
          _polling = false;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _handleValidated() async {
    // Persist so next app open skips the gate entirely
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('qr_validated_${widget.raceId}', true);

    _pollTimer?.cancel();
    _countdownTimer?.cancel();

    if (mounted) {
      setState(() => _validated = true);
      // Brief celebration pause before popping
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, true); // true = validated
    }
  }

  // ── Polling ───────────────────────────────────────────────

  void _startPolling() {
    const interval = 10;
    _secondsUntilNextPoll = interval;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsUntilNextPoll--;
        if (_secondsUntilNextPoll <= 0) {
          _secondsUntilNextPoll = interval;
        }
      });
    });

    _pollTimer = Timer.periodic(
      const Duration(seconds: interval),
      (_) => _checkValidation(),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0D0D14),
          title: const Text('Race Check-In',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarBrightness: Brightness.dark),
        ),
        body: _validated ? _buildValidated() : _buildWaiting(),
      ),
    );
  }

  // ── Validated state ───────────────────────────────────────

  Widget _buildValidated() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF00FF9C).withOpacity(0.12),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF00FF9C), width: 2),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: Color(0xFF00FF9C),
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'You\'re Validated!',
            style: TextStyle(
              color: Color(0xFF00FF9C),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Starting race tracking…',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Waiting state ─────────────────────────────────────────

  Widget _buildWaiting() {
    if (_initialLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00FF9C),
          strokeWidth: 2,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        children: [
          // ── Status card ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: const Color(0xFFFFB800).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      color: Color(0xFFFFB800), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Waiting for Check-In',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Show your QR code to the organizer\nto be validated for ${widget.raceName}.',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── QR code display ─────────────────────────────
          const Text(
            'YOUR CHECK-IN QR',
            style: TextStyle(
              color: Color(0xFF444460),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _qrBytes != null ? Colors.white : const Color(0xFF0D0D14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withOpacity(0.08)),
            ),
            child: _qrBytes != null
                ? Image.memory(_qrBytes!,
                    width: 200, height: 200, fit: BoxFit.contain)
                : SizedBox(
                    width: 200,
                    height: 200,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2_rounded,
                            size: 64,
                            color: Colors.white.withOpacity(0.08)),
                        const SizedBox(height: 12),
                        const Text(
                          'QR code not available.\nGo to Race Details → View QR.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF444460), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
          ),

          if (_qrToken != null && _qrToken!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _qrToken!,
              style: const TextStyle(
                  color: Colors.white24,
                  fontSize: 9,
                  fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 28),

          // ── Instructions ────────────────────────────────
          _InstructionRow(
            step: '1',
            text: 'Find the race organizer at the check-in desk.',
          ),
          const SizedBox(height: 10),
          _InstructionRow(
            step: '2',
            text: 'Show them this QR code so they can scan it.',
          ),
          const SizedBox(height: 10),
          _InstructionRow(
            step: '3',
            text: 'This screen will update automatically once validated.',
          ),

          const SizedBox(height: 28),

          // ── Auto-refresh indicator ───────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _polling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFF00B4FF),
                        ),
                      )
                    : const Icon(Icons.sync,
                        color: Color(0xFF444460), size: 14),
                const SizedBox(width: 8),
                Text(
                  _polling
                      ? 'Checking status…'
                      : 'Next check in ${_secondsUntilNextPoll}s',
                  style: const TextStyle(
                      color: Color(0xFF444460), fontSize: 12),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                _error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Manual refresh ───────────────────────────────
          TextButton.icon(
            onPressed: _polling ? null : _checkValidation,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Check Now'),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00B4FF)),
          ),
        ],
      ),
    );
  }
}

// ── Instruction row ───────────────────────────────────────────────────────────

class _InstructionRow extends StatelessWidget {
  final String step;
  final String text;

  const _InstructionRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF00B4FF).withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(
                color: const Color(0xFF00B4FF).withOpacity(0.3)),
          ),
          child: Center(
            child: Text(step,
                style: const TextStyle(
                    color: Color(0xFF00B4FF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 13)),
        ),
      ],
    );
  }
}