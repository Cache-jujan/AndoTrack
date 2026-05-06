import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/features/runner/screens/qr_screen.dart';

class RaceRegistrationScreen extends StatefulWidget {
  final Map<String, dynamic> race;
  const RaceRegistrationScreen({super.key, required this.race});

  @override
  State<RaceRegistrationScreen> createState() => _RaceRegistrationScreenState();
}

class _RaceRegistrationScreenState extends State<RaceRegistrationScreen> {
  final _cityController = TextEditingController();
  final _contactController = TextEditingController();
  final _emergencyController = TextEditingController();
  final _emailController = TextEditingController();
  String _sex = 'prefer_not_to_say';
  bool _isFirstMarathon = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _cityController.dispose();
    _contactController.dispose();
    _emergencyController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_cityController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty || 
        _contactController.text.trim().isEmpty ||
        _emergencyController.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final raceId = widget.race['id'] as int;
      final result = await ApiService.registerForRace(
        raceId: raceId,
        city: _cityController.text.trim(),
        email: _emailController.text.trim(),
        contactNumber: _contactController.text.trim(),
        emergencyContact: _emergencyController.text.trim(),
        isFirstMarathon: _isFirstMarathon,
        sex: _sex,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => QrScreen(
            registrationData: result,
            raceName: widget.race['name'] ?? 'Race',
          ),
        ),
      );
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        title: const Text('Register', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Race name header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E1E30)),
              ),
              child: Text(
                widget.race['name'] ?? 'Race',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 24),

            _Label('City'),
            _Field(
              controller: _cityController,
              hint: 'e.g. Cebu City',
              icon: Icons.location_city,
            ),

            const SizedBox(height: 16),

            _Label('Email'),
            _Field(
              controller: _emailController,
              hint: 'e.g. runner@email.com',
              icon: Icons.email_outlined,
              keyboard: TextInputType.emailAddress,
            ),

            const SizedBox(height: 16),

            _Label('Contact Number'),
            _Field(
              controller: _contactController,
              hint: 'e.g. 09171234567',
              icon: Icons.phone,
              keyboard: TextInputType.phone,
            ),

            const SizedBox(height: 16),

            _Label('Emergency Contact'),
            _Field(
              controller: _emergencyController,
              hint: 'Name and number',
              icon: Icons.emergency,
            ),

            const SizedBox(height: 16),

            _Label('Sex'),
            const SizedBox(height: 8),
            Row(
              children: [
                _SexChip(
                  label: 'Male',
                  selected: _sex == 'male',
                  onTap: () => setState(() => _sex = 'male'),
                ),
                const SizedBox(width: 8),
                _SexChip(
                  label: 'Female',
                  selected: _sex == 'female',
                  onTap: () => setState(() => _sex = 'female'),
                ),
                const SizedBox(width: 8),
                _SexChip(
                  label: 'Prefer not to say',
                  selected: _sex == 'prefer_not_to_say',
                  onTap: () => setState(() => _sex = 'prefer_not_to_say'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // First marathon toggle
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E1E30)),
              ),
              child: SwitchListTile(
                title: const Text('First Marathon?',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                subtitle: const Text('Let organizers know this is your first race',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                value: _isFirstMarathon,
                activeColor: const Color(0xFF00FF9C),
                onChanged: (v) => setState(() => _isFirstMarathon = v),
              ),
            ),

            const SizedBox(height: 24),

            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Register',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboard;
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        filled: true,
        fillColor: const Color(0xFF0D0D14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF1E1E30)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF1E1E30)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF00B4FF)),
        ),
      ),
    );
  }
}

class _SexChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SexChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00B4FF).withOpacity(0.2)
              : const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF00B4FF)
                : const Color(0xFF1E1E30),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? const Color(0xFF00B4FF) : Colors.white38,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            )),
      ),
    );
  }
}
