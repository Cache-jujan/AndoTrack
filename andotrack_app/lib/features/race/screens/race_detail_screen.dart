import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/features/map/screens/runner_map_screen.dart';
import 'package:andotrack_app/features/runner/screens/qr_screen.dart';
import 'package:andotrack_app/features/runner/screens/race_registration_screen.dart';
import 'package:andotrack_app/features/runner/screens/runner_qr_scanner_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RaceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  const RaceDetailScreen({super.key, required this.race});

  @override
  State<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends State<RaceDetailScreen>
    with WidgetsBindingObserver {
  bool _isRegistered = false;
  bool _checkingRegistration = true;
  Map<String, dynamic>? _registrationData;

  // Live countdown
  Duration? _remaining;
  Timer? _timer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkIfRegistered();
    _startCountdown();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkIfRegistered(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkIfRegistered();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    final raw = widget.race['scheduled_start'];
    if (raw == null) return;
    _updateRemaining(raw);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemaining(raw);
    });
  }

  void _updateRemaining(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final diff = dt.difference(DateTime.now());
      setState(() => _remaining = diff.isNegative ? null : diff);
    } catch (_) {}
  }

  Future<void> _checkIfRegistered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final userName = prefs.getString('user_name') ?? '';
      final raceId = widget.race['id'] as int;

      // Use the QR endpoint — it now returns bib, shirt, claimed, race_status too
      if (userId == null) {
        if (mounted) setState(() => _checkingRegistration = false);
        return;
      }

      final qrData = await ApiService.getRunnerQr(
        runnerId: userId,
        raceId: raceId,
      );

      debugPrint('[RaceDetail] userId=$userId raceId=$raceId claimed=${qrData['claimed']} bib=${qrData['bib_number']}');

      // Cache QR for offline display
      final b64 = qrData['qr_image_base64']?.toString() ?? '';
      final token = qrData['qr_token']?.toString() ?? '';
      if (b64.isNotEmpty) {
        await prefs.setString('qr_base64_$raceId', b64);
        await prefs.setString('qr_token_$raceId', token);
      }

      if (mounted) {
        setState(() {
          _isRegistered = true;
          _checkingRegistration = false;
          _registrationData = {
            'race_id': raceId,
            'race_name': widget.race['name'],
            'runner_name': userName,
            'qr_token': token,
            'qr_image_base64': b64,
            'bib_number': qrData['bib_number'],
            'shirt_size': qrData['shirt_size'] ?? '',
            'claimed': qrData['claimed'] == true || qrData['claimed'] == 1 || qrData['claimed'] == '1',
            'claimed_at': qrData['claimed_at'],
            'race_status': qrData['race_status'] ?? 'registered',
            'is_present': qrData['is_present'] == true || qrData['is_present'] == 1,
            'checked_in_at': qrData['checked_in_at'],
          };
        });
      }
    } on ApiException {
      // 404 = not registered
      if (mounted) setState(() => _checkingRegistration = false);
    } catch (_) {
      if (mounted) setState(() => _checkingRegistration = false);
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return 'TBA';
    try {
      final dt = DateTime.parse(raw);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  String _formatTime(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:$m $ampm';
    } catch (_) {
      return '';
    }
  }

  String _countdownLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _scanToCheckIn() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const RunnerQrScannerScreen()),
    );
    if (result == true) {
      // Refresh registration data to show checked-in state
      await _checkIfRegistered();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Checked in successfully!'),
            backgroundColor: Color(0xFF00FF9C),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final race = widget.race;
    final status = race['status']?.toString() ?? 'upcoming';
    final isActive = status == 'active';
    final isFinished = status == 'finished';
    final isRaceDay = status == 'race_day';
    final canRegister = !isFinished && !isActive && !_isRegistered;

    final regStatus = _registrationData?['race_status'] as String? ?? 'registered';
    final isClaimed = _registrationData?['claimed'] == true;
    final isPresent = _registrationData?['is_present'] == true;
    final checkedInAt = _registrationData?['checked_in_at'] as String?;
    final canCheckIn = _isRegistered && isClaimed && !isPresent && !isFinished;
    final checkInEnabled = _isRegistered && !isFinished;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Race Details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF00FF9C),
        backgroundColor: const Color(0xFF0D0D14),
        onRefresh: _checkIfRegistered,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Status + countdown row ──────────────────────
            Row(
              children: [
                _StatusPill(status: status),
                const Spacer(),
                if (_remaining != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1500),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFFB800).withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 12, color: Color(0xFFFFB800)),
                        const SizedBox(width: 5),
                        Text(
                          'Starts in ${_countdownLabel(_remaining!)}',
                          style: const TextStyle(
                            color: Color(0xFFFFB800),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Race name ────────────────────────────────────
            Text(
              race['name']?.toString() ?? 'Race',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),

            if (race['description'] != null) ...[
              const SizedBox(height: 6),
              Text(
                race['description'],
                style: const TextStyle(
                    color: Color(0xFF555570), fontSize: 13, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 20),

            // ── Info grid (2×3 cards) ────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: [
                _InfoCard(
                  label: 'Date',
                  value: _formatDate(race['scheduled_start']),
                  icon: Icons.calendar_today_outlined,
                ),
                _InfoCard(
                  label: 'Location',
                  value: race['location']?.toString() ?? 'TBA',
                  icon: Icons.place_outlined,
                ),
                _InfoCard(
                  label: 'Distance',
                  value: race['distance_km'] != null
                      ? '${race['distance_km']} km'
                      : 'TBA',
                  icon: Icons.straighten_outlined,
                ),
                _InfoCard(
                  label: 'Category',
                  value: race['category']?.toString() ?? 'TBA',
                  icon: Icons.category_outlined,
                ),
                _InfoCard(
                  label: 'Fee',
                  value: (race['registration_fee'] ?? 0) == 0
                      ? 'Free'
                      : '₱${(race['registration_fee'] as num).toStringAsFixed(0)}',
                  icon: Icons.payments_outlined,
                ),
                _InfoCard(
                  label: 'Slots',
                  value: _slotsLabel(race),
                  icon: Icons.people_outline,
                ),
              ],
            ),

            // ── Full description ─────────────────────────────
            if (race['description'] != null &&
                (race['description'] as String).length > 80) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'About',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      race['description'],
                      style: const TextStyle(
                          color: Color(0xFF888890),
                          fontSize: 13,
                          height: 1.55),
                    ),
                  ],
                ),
              ),
            ],

            // ── Runner Registration Section ───────────────────
            if (_isRegistered && _registrationData != null) ...[
              const SizedBox(height: 24),

              // Bib + Shirt + Status
              _buildRegistrationCard(regStatus),

              const SizedBox(height: 12),

              // Claiming Section
              _buildClaimingCard(isClaimed),

              const SizedBox(height: 12),

              // Check-in Section
              _buildCheckinCard(
                isPresent: isPresent,
                canCheckIn: canCheckIn,
                checkInEnabled: checkInEnabled,
                checkedInAt: checkedInAt,
              ),
            ],

            const SizedBox(height: 32),

            // ── Unregistered action area (body) ──────────────
            if (_checkingRegistration)
              const Center(child: CircularProgressIndicator())
            else if (isActive && _isRegistered)
              _ActionButton(
                label: 'Join Race →',
                color: const Color(0xFF00FF9C),
                textColor: Colors.black,
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  final raceId = race['id'] as int;
                  await prefs.setInt('active_race_id', raceId);
                  await Future.wait([
                    ApiService.getCheckpoints(raceId),
                    ApiService.getRaces(),
                  ]);
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const RunnerMapScreen()),
                    (_) => false,
                  );
                },
              ),

            // ── Sponsors ─────────────────────────────────────
            if (race['sponsors'] != null &&
                (race['sponsors'] as String).isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.handshake_outlined,
                        size: 14, color: Color(0xFF444460)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        race['sponsors'],
                        style: const TextStyle(
                            color: Color(0xFF666680), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      ),

      // ── Sticky bottom action ──────────────────────────────
      bottomNavigationBar: _checkingRegistration
          ? const SizedBox(height: 80)
          : Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0F),
                border: Border(
                  top: BorderSide(
                      color: Colors.white.withOpacity(0.06), width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // View QR button (if registered)
                  if (_isRegistered && _registrationData != null) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => QrScreen(
                                registrationData: _registrationData!,
                                raceName:
                                    race['name']?.toString() ?? 'Race',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: const Text('View QR Code'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF888890),
                          side: BorderSide(
                              color: Colors.white.withOpacity(0.12)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Primary CTA
                  if (isActive && _isRegistered)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setInt(
                              'active_race_id', race['id'] as int);
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RunnerMapScreen()),
                            (_) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FF9C),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Join Race',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                      ),
                    )
                  else if (canRegister)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  RaceRegistrationScreen(race: race),
                            ),
                          ).then((_) => _checkIfRegistered());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00FF9C),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Register',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else if (_isRegistered && !isActive)
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF9C).withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF00FF9C).withOpacity(0.25)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline,
                              color: Color(0xFF00FF9C), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'You\'re registered!',
                            style: TextStyle(
                              color: Color(0xFF00FF9C),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isFinished)
                    Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: const Center(
                        child: Text(
                          'Race has ended',
                          style: TextStyle(
                              color: Color(0xFF444460), fontSize: 14),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // ── YOUR REGISTRATION card ──────────────────────────────────────────────────
  Widget _buildRegistrationCard(String regStatus) {
    final bib = _registrationData?['bib_number'];
    final shirt = _registrationData?['shirt_size'] as String? ?? '';
    final bibLabel = bib != null ? '#${bib.toString()}' : '—';

    Color statusColor;
    String statusLabel;
    switch (regStatus) {
      case 'present':
        statusColor = const Color(0xFF00B4FF);
        statusLabel = 'Checked In';
        break;
      case 'finished':
        statusColor = const Color(0xFF00FF9C);
        statusLabel = 'Finished';
        break;
      default:
        statusColor = const Color(0xFFFFB800);
        statusLabel = 'Registered';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'YOUR REGISTRATION',
                style: TextStyle(
                  color: Color(0xFF666680),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Bib Number
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BIB NUMBER',
                      style: TextStyle(
                          color: Color(0xFF444460), fontSize: 9, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bibLabel,
                      style: const TextStyle(
                        color: Color(0xFF00FF9C),
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 44, color: const Color(0xFF1E1E30)),
              const SizedBox(width: 16),
              // Shirt Size
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SHIRT SIZE',
                    style: TextStyle(
                        color: Color(0xFF444460), fontSize: 9, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shirt.isNotEmpty ? shirt : '—',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── CLAIMING card ───────────────────────────────────────────────────────────
  Widget _buildClaimingCard(bool isClaimed) {
    final race = widget.race;
    final venue = race['location']?.toString() ?? '&DOTSports HQ';
    final startRaw = race['scheduled_start'] as String?;
    final claimDate = startRaw != null
        ? '${_formatDate(startRaw)} · 10:00 AM – 5:00 PM'
        : 'See event details';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isClaimed
            ? const Color(0xFF00FF9C).withOpacity(0.05)
            : const Color(0xFFFFB800).withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isClaimed
              ? const Color(0xFF00FF9C).withOpacity(0.25)
              : const Color(0xFFFFB800).withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'BIB CLAIMING',
                style: TextStyle(
                  color: isClaimed
                      ? const Color(0xFF00FF9C)
                      : const Color(0xFFFFB800),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isClaimed
                      ? const Color(0xFF00FF9C).withOpacity(0.12)
                      : const Color(0xFFFFB800).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isClaimed)
                      const Icon(Icons.check_circle_outline,
                          size: 11, color: Color(0xFF00FF9C)),
                    if (isClaimed) const SizedBox(width: 4),
                    Text(
                      isClaimed ? 'CLAIMED ✓' : 'UNCLAIMED',
                      style: TextStyle(
                        color: isClaimed
                            ? const Color(0xFF00FF9C)
                            : const Color(0xFFFFB800),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 14,
                  color: isClaimed
                      ? const Color(0xFF00FF9C)
                      : const Color(0xFFFFB800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(venue,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, height: 1.4)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 14,
                  color: isClaimed
                      ? const Color(0xFF00FF9C)
                      : const Color(0xFFFFB800)),
              const SizedBox(width: 8),
              Text(claimDate,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ── CHECK-IN card ───────────────────────────────────────────────────────────
  Widget _buildCheckinCard({
    required bool isPresent,
    required bool canCheckIn,
    required bool checkInEnabled,
    required String? checkedInAt,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RACE CHECK-IN',
            style: TextStyle(
              color: Color(0xFF666680),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),

          if (isPresent)
            // Confirmed state
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF00FF9C).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF00FF9C).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      color: Color(0xFF00FF9C), size: 20),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Checked In ✓',
                        style: TextStyle(
                          color: Color(0xFF00FF9C),
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (checkedInAt != null)
                        Text(
                          '${_formatDate(checkedInAt)} at ${_formatTime(checkedInAt)}',
                          style: const TextStyle(
                              color: Color(0xFF666680), fontSize: 11),
                        ),
                    ],
                  ),
                ],
              ),
            )
          else if (checkInEnabled && !canCheckIn && !isPresent)
            // Bib not yet claimed — show grayed scan button with hint
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Color(0xFF333348)),
                  SizedBox(width: 8),
                  Text(
                    'Claim your bib first to check in',
                    style: TextStyle(color: Color(0xFF444460), fontSize: 13),
                  ),
                ],
              ),
            )
          else if (checkInEnabled)
            // Bib claimed — scan button active
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: canCheckIn ? _scanToCheckIn : null,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('Scan to Check In',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4FF),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      const Color(0xFF00B4FF).withOpacity(0.3),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            )
          else
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flag_outlined, size: 16, color: Color(0xFF333348)),
                  SizedBox(width: 8),
                  Text(
                    'Race has ended',
                    style: TextStyle(color: Color(0xFF333348), fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _slotsLabel(Map<String, dynamic> race) {
    final slots = race['slots_remaining'];
    final max = race['max_participants'];
    final count = race['participant_count'];
    if (slots != null && max != null) return '$count / $max';
    if (max != null) return '$max total';
    return 'Open';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Info Card
// ─────────────────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoCard(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: const Color(0xFF444460)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                    color: Color(0xFF444460), fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Status Pill
// ─────────────────────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    bool showDot = false;

    switch (status) {
      case 'active':
        color = const Color(0xFF00FF9C);
        label = 'LIVE';
        showDot = true;
        break;
      case 'registration_open':
        color = const Color(0xFF00B4FF);
        label = 'OPEN';
        break;
      case 'race_day':
        color = const Color(0xFFFFB800);
        label = 'RACE DAY';
        break;
      case 'finished':
        color = const Color(0xFF555570);
        label = 'FINISHED';
        break;
      default:
        color = const Color(0xFFFFB800);
        label = 'UPCOMING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Action Button
// ─────────────────────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
