import 'package:flutter/material.dart';
import 'package:andotrack_app/features/race/screens/race_detail_screen.dart';
import 'package:andotrack_app/roles/runner_app/runner_dashboard_screen.dart';

class RegistrationSuccessScreen extends StatelessWidget {
  final Map<String, dynamic> race;
  final String shirtSize;
  final Map<String, dynamic> registrationData;

  const RegistrationSuccessScreen({
    super.key,
    required this.race,
    required this.shirtSize,
    required this.registrationData,
  });

  String get _raceName => race['name'] ?? 'Race';

  String get _bibNumber {
    final bib = registrationData['bib_number'] ??
        registrationData['bib'] ??
        registrationData['runner_number'];
    if (bib == null) return '—';
    return '#${bib.toString()}';
  }

  String get _claimLocation =>
      registrationData['claim_location'] ??
      '&DOTSports HQ, 2F Ayala Center Cebu';

  String get _claimDate =>
      registrationData['claim_date'] ??
      'Apr 8–9, 2025 · 10:00 AM – 8:00 PM';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // ── Success icon ──────────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00FF9C).withOpacity(0.12),
                  border: Border.all(
                      color: const Color(0xFF00FF9C).withOpacity(0.4),
                      width: 2),
                ),
                child: const Icon(Icons.check,
                    color: Color(0xFF00FF9C), size: 34),
              ),

              const SizedBox(height: 20),

              const Text(
                "You're registered!",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(_raceName,
                  style: const TextStyle(
                      color: Color(0xFF888899), fontSize: 14)),

              const SizedBox(height: 32),

              // ── Bib number card ───────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E1E30)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'BIB NUMBER',
                      style: TextStyle(
                        color: Color(0xFF666680),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _bibNumber,
                      style: const TextStyle(
                        color: Color(0xFF00FF9C),
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            color: Color(0xFF888899), fontSize: 13),
                        children: [
                          const TextSpan(text: 'Shirt Size: '),
                          TextSpan(
                            text: shirtSize,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Bib claiming card ─────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFFFB800).withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BIB CLAIMING',
                      style: TextStyle(
                        color: Color(0xFFFFB800),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: Color(0xFFFFB800), size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_claimLocation,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            color: Color(0xFFFFB800), size: 16),
                        const SizedBox(width: 10),
                        Text(_claimDate,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Buttons ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (_) => RaceDetailScreen(race: race)),
                      (route) => route.isFirst,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF9C),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('View My Race',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RunnerDashboardScreen()),
                      (route) => false,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF1E1E30)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back to Home',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}