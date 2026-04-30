import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'race_registration_screen.dart';
import 'runner_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RaceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  const RaceDetailScreen({super.key, required this.race});

  @override
  State<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends State<RaceDetailScreen> {
  bool _isRegistered = false;
  bool _checkingRegistration = true;

  @override
  void initState() {
    super.initState();
    _checkIfRegistered();
  }

  Future<void> _checkIfRegistered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final raceId = widget.race['id'] as int;
      final runners = await ApiService.getRaceRunners(raceId);
      final registered = runners.any((r) => r['user_id'] == userId);
      if (mounted) {
        setState(() {
          _isRegistered = registered;
          _checkingRegistration = false;
        });
      }
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
      return '${months[dt.month]} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  Duration? _countdown() {
    final raw = widget.race['scheduled_start'];
    if (raw == null) return null;
    try {
      final dt = DateTime.parse(raw);
      final diff = dt.difference(DateTime.now());
      return diff.isNegative ? null : diff;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final race = widget.race;
    final status = race['status'] ?? 'upcoming';
    final isActive = status == 'active';
    final isFinished = status == 'finished';
    final canRegister = !isFinished && !isActive && !_isRegistered;
    final countdown = _countdown();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        title: Text(race['name'] ?? 'Race Detail',
            style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Status + countdown ──────────────────────────
            Row(
              children: [
                _StatusBadge(status: status),
                const Spacer(),
                if (countdown != null)
                  _CountdownChip(countdown: countdown),
              ],
            ),

            const SizedBox(height: 20),

            // ── Info grid ───────────────────────────────────
            _InfoRow(
              icon: Icons.calendar_today,
              label: 'Date',
              value: _formatDate(race['scheduled_start']),
            ),
            if (race['location'] != null)
              _InfoRow(
                icon: Icons.location_on,
                label: 'Location',
                value: race['location'],
              ),
            if (race['distance_km'] != null)
              _InfoRow(
                icon: Icons.straighten,
                label: 'Distance',
                value: '${race['distance_km']} km',
              ),
            if (race['category'] != null)
              _InfoRow(
                icon: Icons.category,
                label: 'Category',
                value: race['category'],
              ),
            _InfoRow(
              icon: Icons.attach_money,
              label: 'Fee',
              value: (race['registration_fee'] ?? 0) == 0
                  ? 'Free'
                  : '₱${race['registration_fee'].toStringAsFixed(0)}',
            ),
            if (race['max_participants'] != null)
              _InfoRow(
                icon: Icons.people,
                label: 'Slots',
                value: race['slots_remaining'] != null
                    ? '${race['slots_remaining']} / ${race['max_participants']} remaining'
                    : '${race['max_participants']} total',
              ),
            if (race['participant_count'] != null)
              _InfoRow(
                icon: Icons.how_to_reg,
                label: 'Registered',
                value: '${race['participant_count']} runners',
              ),

            // ── Description ─────────────────────────────────
            if (race['description'] != null) ...[
              const SizedBox(height: 20),
              const Text('About',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(race['description'],
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13, height: 1.5)),
            ],

            // ── Sponsors ────────────────────────────────────
            if (race['sponsors'] != null) ...[
              const SizedBox(height: 16),
              const Text('Sponsors',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(race['sponsors'],
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ],

            const SizedBox(height: 32),

            // ── Action button ────────────────────────────────
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

                  // Pre-fetch so RunnerMapScreen opens with data ready
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
              )
            else if (_isRegistered)
              const _InfoBanner(
                message: '✅ You are registered for this race.',
                color: Color(0xFF00FF9C),
              )
            else if (canRegister)
              _ActionButton(
                label: 'Register',
                color: const Color(0xFF00B4FF),
                textColor: Colors.black,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RaceRegistrationScreen(race: race),
                    ),
                  ).then((_) => _checkIfRegistered());
                },
              )
            else if (isFinished)
              const _InfoBanner(
                message: 'This race has finished.',
                color: Color(0xFF444460),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white38),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  final Duration countdown;
  const _CountdownChip({required this.countdown});

  @override
  Widget build(BuildContext context) {
    final d = countdown.inDays;
    final h = countdown.inHours % 24;
    final m = countdown.inMinutes % 60;
    final label = d > 0 ? '${d}d ${h}h' : '${h}h ${m}m';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB800).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFB800).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, size: 12, color: Color(0xFFFFB800)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Color(0xFFFFB800),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'active':
        color = const Color(0xFF00FF9C);
        label = '● Live';
        break;
      case 'registration_open':
        color = const Color(0xFF00B4FF);
        label = 'Registration Open';
        break;
      case 'race_day':
        color = const Color(0xFFFFB800);
        label = 'Race Day';
        break;
      case 'finished':
        color = const Color(0xFF444460);
        label = 'Finished';
        break;
      default:
        color = const Color(0xFF444460);
        label = 'Upcoming';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

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
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
        child: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;
  final Color color;
  const _InfoBanner({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(message,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}