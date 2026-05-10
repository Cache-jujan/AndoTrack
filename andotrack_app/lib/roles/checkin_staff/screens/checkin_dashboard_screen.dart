// lib/roles/checkin_staff/screens/checkin_dashboard_screen.dart
//
// WEB check-in display screen for a specific race.
// Three states driven by race status:
//   before — countdown + inactive QR overlay + registered count
//   open   — large QR, live counter, progress bar, live indicator
//   closed — frozen final numbers, DNS count, Race Director notified message
//
// This file is WEB-only and rebuilt cleanly for web.
// It does NOT import or depend on runner_checkin_gate_screen.dart.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/utils/date_utils.dart';

// ── State enum ────────────────────────────────────────────────────────────────

enum _CheckinState { before, open, closed }

// ── Screen ────────────────────────────────────────────────────────────────────

class CheckinDashboardScreen extends StatefulWidget {
  final int raceId;
  final String raceName;
  final Map<String, dynamic> raceData;

  const CheckinDashboardScreen({
    super.key,
    required this.raceId,
    required this.raceName,
    required this.raceData,
  });

  @override
  State<CheckinDashboardScreen> createState() => _CheckinDashboardScreenState();
}

class _CheckinDashboardScreenState extends State<CheckinDashboardScreen> {
  // Design tokens
  static const _kBg          = Color(0xFF080810);
  static const _kSurface     = Color(0xFF0D0D18);
  static const _kBorder      = Color(0xFF1E1E32);
  static const _kGreen       = Color(0xFF00FF9C);
  static const _kBlue        = Color(0xFF00B4FF);
  static const _kAmber       = Color(0xFFFFB800);
  static const _kRed         = Color(0xFFFF4D4D);
  static const _kTextPri     = Colors.white;
  static const _kTextSub     = Color(0xFF8888AA);
  static const _kTextMuted   = Color(0xFF3A3A55);

  _CheckinState _state = _CheckinState.before;

  // Live counts
  int _totalRunners   = 0;
  int _checkedInCount = 0;
  bool _polling       = false;

  // Countdown
  Timer? _countdownTimer;
  Duration _timeUntilOpen = Duration.zero;
  DateTime? _opensAt;

  // Poll / live indicator
  Timer? _pollTimer;
  Timer? _liveTickTimer;
  Timer? _statusPollTimer;
  DateTime? _lastUpdated;
  int _secondsSinceUpdate = 0;

  @override
  void initState() {
    super.initState();
    _state  = _deriveState(widget.raceData['status']?.toString());
    _opensAt = _parseOpensAt();

    // Fetch initial runner counts in all states for the registered-count display
    _fetchCounts();

    if (_state == _CheckinState.before) {
      _startCountdown();
      _startStatusPoll();
    } else if (_state == _CheckinState.open) {
      _startPolling();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollTimer?.cancel();
    _liveTickTimer?.cancel();
    _statusPollTimer?.cancel();
    super.dispose();
  }

  // ── State derivation ──────────────────────────────────────────────────────

  _CheckinState _deriveState(String? status) {
    switch (status) {
      case 'race_day':
        return _CheckinState.open;
      case 'active':
      case 'finished':
        return _CheckinState.closed;
      default: // upcoming, registration_open, or unknown
        return _CheckinState.before;
    }
  }

  DateTime? _parseOpensAt() {
    // Prefer a dedicated check-in timestamp; fall back to race date fields
    final iso = widget.raceData['check_in_opens_at']
        ?? widget.raceData['scheduled_start']
        ?? widget.raceData['date']
        ?? widget.raceData['race_date'];
    if (iso == null) return null;
    final raw = iso.toString();
    try {
      final parsed = parsePht(raw);
      debugPrint('[CheckinDashboard] _parseOpensAt:'
          '  raw="$raw"'
          '  parsed=$parsed'
          '  now=${DateTime.now()}');
      return parsed;
    } catch (_) {
      return null;
    }
  }

  // ── Countdown ─────────────────────────────────────────────────────────────

  void _startCountdown() {
    if (_opensAt == null) return;
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    if (_opensAt == null) return;
    final now       = DateTime.now();
    final remaining = _opensAt!.difference(now);
    debugPrint('[CheckinDashboard] _updateCountdown:'
        '  opensAt=$_opensAt'
        '  now=$now'
        '  remaining=${remaining.inSeconds}s'
        '  isNegative=${remaining.isNegative}');
    if (remaining.isNegative) {
      _countdownTimer?.cancel();
      _statusPollTimer?.cancel();
      setState(() {
        _state = _CheckinState.open;
        _timeUntilOpen = Duration.zero;
      });
      _startPolling();
    } else {
      setState(() => _timeUntilOpen = remaining);
    }
  }

  // Polls the race status every 30 s while in the before state so the screen
  // transitions to open as soon as the Race Director sets the race to race_day,
  // independent of whether a check_in_opens_at time is configured.
  void _startStatusPoll() {
    _statusPollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted || _state != _CheckinState.before) {
        _statusPollTimer?.cancel();
        return;
      }
      try {
        final race = await ApiService.getRace(widget.raceId);
        if (!mounted) return;
        final newState = _deriveState(race['status']?.toString());
        if (newState != _CheckinState.before) {
          _countdownTimer?.cancel();
          _statusPollTimer?.cancel();
          setState(() => _state = newState);
          if (newState == _CheckinState.open) _startPolling();
        }
      } catch (_) {
        // Silent fail — keep current state
      }
    });
  }

  // ── Live polling ──────────────────────────────────────────────────────────

  Future<void> _fetchCounts() async {
    if (_polling) return;
    if (mounted) setState(() { _polling = true; _secondsSinceUpdate = 0; });
    try {
      final runners = await ApiService.getRaceRunners(widget.raceId);
      final checked = runners.where((r) =>
        r['is_present'] == true ||
        r['checked_in'] == true ||
        r['checkin_status'] == 'checked_in',
      ).length;
      if (mounted) {
        setState(() {
          _totalRunners   = runners.length;
          _checkedInCount = checked;
          _lastUpdated    = DateTime.now();
        });
      }
    } catch (_) {
      // Silent fail — last known counts remain visible
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchCounts(),
    );
    _liveTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsSinceUpdate++);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _liveIndicatorText() {
    if (_polling) return 'Updating…';
    if (_lastUpdated == null) return 'Connecting…';
    if (_secondsSinceUpdate < 5) return 'updated just now';
    return 'updated ${_secondsSinceUpdate}s ago';
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return '00:00:00';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatCount(int n) {
    if (n < 1000) return n.toString();
    final thousands = n ~/ 1000;
    final remainder = (n % 1000).toString().padLeft(3, '0');
    return '$thousands,$remainder';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _DashboardTopBar(raceName: widget.raceName, state: _state),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: KeyedSubtree(
                key: ValueKey(_state),
                child: switch (_state) {
                  _CheckinState.before => _buildBeforeState(),
                  _CheckinState.open   => _buildOpenState(),
                  _CheckinState.closed => _buildClosedState(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── State 1: Before check-in opens ────────────────────────────────────────

  Widget _buildBeforeState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Countdown or static waiting message
            if (_opensAt != null) ...[
              const Text(
                'Check-in opens in',
                style: TextStyle(color: _kTextSub, fontSize: 14, letterSpacing: 0.2),
              ),
              const SizedBox(height: 10),
              Text(
                _formatCountdown(_timeUntilOpen),
                style: const TextStyle(
                  color: _kAmber,
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: _kAmber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kAmber.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_top_rounded, color: _kAmber, size: 22),
                    const SizedBox(width: 12),
                    const Text(
                      'Check-in not yet open',
                      style: TextStyle(
                        color: _kAmber,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),

            // QR visible but blocked with overlay
            _QrWithOverlay(
              raceId: widget.raceId,
              overlayColor: _kBg.withOpacity(0.88),
            ),

            const SizedBox(height: 32),

            // Registered count
            _CounterChip(
              icon: Icons.people_rounded,
              color: _kBlue,
              label: '${_formatCount(_totalRunners)} registered',
            ),
          ],
        ),
      ),
    );
  }

  // ── State 2: Check-in is open ─────────────────────────────────────────────

  Widget _buildOpenState() {
    final remaining = (_totalRunners - _checkedInCount).clamp(0, 9999999);
    final progress  = _totalRunners > 0 ? _checkedInCount / _totalRunners : 0.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Live indicator pill
            _LivePill(text: 'Live · ${_liveIndicatorText()}'),
            const SizedBox(height: 28),

            // Large QR code — display only
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _kGreen.withOpacity(0.18),
                    blurRadius: 48,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: QrImageView(
                data: 'andotrack://checkin/${widget.raceId}',
                version: QrVersions.auto,
                size: 280.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 28),

            // Live counters
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CounterChip(
                  icon: Icons.check_circle_rounded,
                  color: _kGreen,
                  label: '${_formatCount(_checkedInCount)} checked in',
                  large: true,
                ),
                const SizedBox(width: 14),
                _CounterChip(
                  icon: Icons.schedule_rounded,
                  color: _kTextSub,
                  label: '${_formatCount(remaining)} remaining',
                  large: true,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Progress bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Check-in progress',
                      style: TextStyle(color: _kTextSub, fontSize: 12),
                    ),
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: _kTextSub, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: _kBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(_kGreen),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── State 3: Check-in closed ──────────────────────────────────────────────

  Widget _buildClosedState() {
    final dns = (_totalRunners - _checkedInCount).clamp(0, 9999999);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Closed icon
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: _kRed.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: _kRed.withOpacity(0.3)),
              ),
              child: const Icon(Icons.lock_rounded, color: _kRed, size: 32),
            ),
            const SizedBox(height: 20),
            const Text(
              'Check-in Closed',
              style: TextStyle(
                color: _kTextPri,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'No further check-ins can be processed.',
              style: TextStyle(color: _kTextSub, fontSize: 13),
            ),

            // Final numbers card
            Container(
              margin: const EdgeInsets.symmetric(vertical: 28),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: _kGreen, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatCount(_checkedInCount)} checked in',
                    style: const TextStyle(
                      color: _kGreen,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      '·',
                      style: TextStyle(color: _kTextMuted, fontSize: 20),
                    ),
                  ),
                  const Icon(Icons.cancel_rounded, color: _kTextSub, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatCount(dns)} DNS',
                    style: const TextStyle(
                      color: _kTextSub,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            // Race Director notified
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: _kBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _kBlue.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications_active_rounded, color: _kBlue, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'Race Director has been notified',
                    style: TextStyle(
                      color: _kBlue,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dashboard top bar ─────────────────────────────────────────────────────────

class _DashboardTopBar extends StatelessWidget {
  final String raceName;
  final _CheckinState state;

  static const _kSurface = Color(0xFF0D0D18);
  static const _kBorder  = Color(0xFF1E1E32);
  static const _kGreen   = Color(0xFF00FF9C);
  static const _kAmber   = Color(0xFFFFB800);
  static const _kTextPri = Colors.white;
  static const _kTextSub = Color(0xFF8888AA);

  const _DashboardTopBar({required this.raceName, required this.state});

  @override
  Widget build(BuildContext context) {
    final (stateColor, stateLabel) = switch (state) {
      _CheckinState.before => (_kAmber,               'Not Open'),
      _CheckinState.open   => (_kGreen,               'Open'),
      _CheckinState.closed => (const Color(0xFFFF4D4D), 'Closed'),
    };

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          // Back to shell
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: _kTextSub,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            raceName,
            style: const TextStyle(
              color: _kTextPri,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 12),
          // State badge with live dot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: stateColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: stateColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  stateLabel,
                  style: TextStyle(
                    color: stateColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const Text(
            'Check-in Dashboard',
            style: TextStyle(color: _kTextSub, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── QR with "not active" overlay ──────────────────────────────────────────────

class _QrWithOverlay extends StatelessWidget {
  final int raceId;
  final Color overlayColor;

  const _QrWithOverlay({required this.raceId, required this.overlayColor});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // QR code beneath the overlay
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: QrImageView(
            data: 'andotrack://checkin/$raceId',
            version: QrVersions.auto,
            size: 200.0,
            backgroundColor: Colors.white,
          ),
        ),
        // Overlay — blocks QR until check-in opens
        Container(
          width: 224, height: 224,
          decoration: BoxDecoration(
            color: overlayColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.lock_clock_rounded, color: Color(0xFFFFB800), size: 28),
              SizedBox(height: 8),
              Text(
                'Not active yet',
                style: TextStyle(
                  color: Color(0xFFFFB800),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Counter chip ──────────────────────────────────────────────────────────────

class _CounterChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool large;

  const _CounterChip({
    required this.icon,
    required this.color,
    required this.label,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 18 : 14,
        vertical:   large ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: large ? 18 : 14),
          SizedBox(width: large ? 8 : 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: large ? 15 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live pill ─────────────────────────────────────────────────────────────────

class _LivePill extends StatelessWidget {
  final String text;

  static const _kGreen  = Color(0xFF00FF9C);
  static const _kBorder = Color(0xFF1E1E32);

  const _LivePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _kGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kGreen.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(color: _kGreen, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              color: _kGreen,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
