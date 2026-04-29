import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  RunnerProfileScreen — Profile tab
// ─────────────────────────────────────────────────────────────────────────────
class RunnerProfileScreen extends StatefulWidget {
  const RunnerProfileScreen({super.key});

  @override
  State<RunnerProfileScreen> createState() => _RunnerProfileScreenState();
}

class _RunnerProfileScreenState extends State<RunnerProfileScreen> {
  String? _name;
  String? _email;
  String? _phone;
  String? _city;
  int _totalRaces = 0;
  int _finishedRaces = 0;
  int _dnfRaces = 0;
  bool _loading = true;
  int? _userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('user_name');
    _userId = prefs.getInt('user_id');

    // Try to get extra user info + race stats from API
    try {
      final profile = await ApiService.getProfile();
      _email = profile['email'];
      _phone = profile['contact_number'];
      _city = profile['city'];

      // Count races
      final races = await ApiService.getRaces();
      int total = 0, finished = 0, dnf = 0;
      for (final race in races) {
        final raceId = race['id'] as int;
        final runners = await ApiService.getRaceRunners(raceId);
        final match = runners
            .cast<Map<String, dynamic>>()
            .where((r) => r['user_id'] == _userId);
        if (match.isNotEmpty) {
          total++;
          final status = race['status']?.toString();
          if (status == 'finished') {
            final runner = match.first;
            final ft = runner['finish_time'];
            if (ft != null && ft.toString().isNotEmpty) {
              finished++;
            } else {
              dnf++;
            }
          }
        }
      }
      _totalRaces = total;
      _finishedRaces = finished;
      _dnfRaces = dnf;
    } catch (_) {
      // Fall back to cached name
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D0D14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Log Out',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to log out?',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5), fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.1)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3D1010),
                        foregroundColor: const Color(0xFFFF4D4D),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Log Out',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await ApiService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00FF9C),
                  strokeWidth: 2,
                ),
              )
            : ListView(
                padding:
                    const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  // ── Title ──────────────────────────────────
                  const Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Avatar ─────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E30),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                                width: 1.5),
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            color: Colors.white.withOpacity(0.4),
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _name ?? 'Runner',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Runner',
                          style: TextStyle(
                            color: Color(0xFF555570),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Info tiles ─────────────────────────────
                  if (_email != null)
                    _InfoTile(
                        icon: Icons.mail_outline_rounded,
                        label: 'Email',
                        value: _email!),
                  if (_phone != null)
                    _InfoTile(
                        icon: Icons.phone_outlined,
                        label: 'Phone',
                        value: _phone!),
                  if (_city != null)
                    _InfoTile(
                        icon: Icons.place_outlined,
                        label: 'City',
                        value: _city!),

                  const SizedBox(height: 20),

                  // ── Stats row ──────────────────────────────
                  Row(
                    children: [
                      _StatBox(value: '$_totalRaces', label: 'Races'),
                      const SizedBox(width: 10),
                      _StatBox(
                          value: '$_finishedRaces', label: 'Finished'),
                      const SizedBox(width: 10),
                      _StatBox(value: '$_dnfRaces', label: 'DNF'),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // ── Log out ────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'Log Out',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A0A0A),
                        foregroundColor: const Color(0xFFFF4D4D),
                        elevation: 0,
                        side: BorderSide(
                            color: const Color(0xFFFF4D4D).withOpacity(0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF444460)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: Color(0xFF444460), fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;

  const _StatBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                  color: Color(0xFF444460), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}