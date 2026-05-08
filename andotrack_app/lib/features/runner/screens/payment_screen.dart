import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/features/runner/screens/registration_success_screen.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  final String shirtSize;
  final String city;
  final String email;
  final String contactNumber;
  final String emergencyContact;
  final String sex;
  final bool isFirstMarathon;

  const PaymentScreen({
    super.key,
    required this.race,
    required this.shirtSize,
    required this.city,
    required this.email,
    required this.contactNumber,
    required this.emergencyContact,
    required this.sex,
    required this.isFirstMarathon,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _paying = false;

  String get _fee {
    final f = widget.race['registration_fee'];
    if (f == null || f == 0) return 'Free';
    return '₱${(f as num).toStringAsFixed(0)}';
  }

  Future<void> _pay() async {
    setState(() => _paying = true);
    try {
      // Simulated payment delay — pilot mode
      await Future.delayed(const Duration(seconds: 1));

      final result = await ApiService.registerForRace(
        raceId: widget.race['id'] as int,
        city: widget.city,
        email: widget.email,
        contactNumber: widget.contactNumber,
        emergencyContact: widget.emergencyContact,
        sex: widget.sex,
        isFirstMarathon: widget.isFirstMarathon,
        shirtSize: widget.shirtSize,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RegistrationSuccessScreen(
            race: widget.race,
            shirtSize: widget.shirtSize,
            registrationData: result,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFF2A0A0A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        title: const Text('Payment', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Order summary ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E1E30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ORDER SUMMARY',
                    style: TextStyle(
                      color: Color(0xFF666680),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _OrderRow(label: 'Race', value: widget.race['name'] ?? 'Race'),
                  const SizedBox(height: 10),
                  _OrderRow(label: 'Shirt Size', value: widget.shirtSize),
                  const SizedBox(height: 10),
                  _OrderRow(label: 'Registration Fee', value: _fee),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(color: Color(0xFF1E1E30), thickness: 1),
                  ),
                  Row(
                    children: [
                      const Text('Total',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text(_fee,
                          style: const TextStyle(
                              color: Color(0xFF00FF9C),
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Simulated payment notice ────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E1E30)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B4FF).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.credit_card_outlined,
                        color: Color(0xFF00B4FF), size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Simulated Payment',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: 6),
                        Text(
                          'For the pilot, payments are processed instantly without a real card. In production this connects to GCash, Maya, and card processors.',
                          style: TextStyle(
                              color: Color(0xFF888899),
                              fontSize: 12,
                              height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            
            // ── Pay button ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _paying ? null : _pay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF9C),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      const Color(0xFF00FF9C).withOpacity(0.4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _paying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.lock_outline, size: 16),
                          const SizedBox(width: 8),
                          Text('Pay $_fee',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Secured by AndoSports • Pilot mode',
              style: TextStyle(color: Color(0xFF444460), fontSize: 11),
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final String label;
  final String value;
  const _OrderRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF888899), fontSize: 13)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}