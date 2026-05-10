// lib/roles/race_director/screens/race_director_settings_screen.dart
//
// Race Director Settings — three sections:
//   1. Account Settings  — display name (editable, local only), email (unavailable), password (no backend endpoint)
//   2. App Preferences   — default GPS accuracy, default anomaly sensitivity, dark mode (locked ON)
//   3. Danger Zone       — logout

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/features/auth/screens/login_screen.dart';

class RaceDirectorSettingsScreen extends StatefulWidget {
  const RaceDirectorSettingsScreen({super.key});

  @override
  State<RaceDirectorSettingsScreen> createState() =>
      _RaceDirectorSettingsScreenState();
}

class _RaceDirectorSettingsScreenState
    extends State<RaceDirectorSettingsScreen> {
  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _kBg         = Color(0xFF080810);
  static const _kSurface    = Color(0xFF0D0D18);
  static const _kSurfaceHi  = Color(0xFF141422);
  static const _kBorder     = Color(0xFF1E1E32);
  static const _kGreen      = Color(0xFF00FF9C);
  static const _kRed        = Color(0xFFFF4D4D);
  static const _kTextPri    = Colors.white;
  static const _kTextSub    = Color(0xFF8888AA);
  static const _kTextMuted  = Color(0xFF3A3A55);

  // ── State ─────────────────────────────────────────────────────────────────
  bool   _loading       = true;
  bool   _saving        = false;
  String _savedName     = '';
  final  _nameCtrl      = TextEditingController();
  double _gpsAccuracy   = 30.0;
  String _anomalySens   = 'medium';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name  = prefs.getString('user_name') ?? '';
    final gps   = prefs.getDouble('default_gps_accuracy') ?? 30.0;
    final sens  = prefs.getString('default_anomaly_sensitivity') ?? 'medium';
    if (!mounted) return;
    setState(() {
      _savedName   = name;
      _nameCtrl.text = name;
      _gpsAccuracy = gps.clamp(10.0, 100.0);
      _anomalySens = sens;
      _loading     = false;
    });
  }

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', newName);
    await prefs.setDouble('default_gps_accuracy', _gpsAccuracy);
    await prefs.setString('default_anomaly_sensitivity', _anomalySens);
    if (!mounted) return;
    setState(() {
      _savedName = newName;
      _saving    = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Settings saved'),
        backgroundColor: Color(0xFF1E1E32),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _LogoutDialog(),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kGreen));
    }

    return ColoredBox(
      color: _kBg,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _Section(
            title: 'Account Settings',
            children: [
              _Field(
                label: 'Display Name',
                child: _TextInput(controller: _nameCtrl, hint: 'Your name'),
              ),
              const SizedBox(height: 16),
              _Field(
                label: 'Email',
                child: _ReadOnlyInfo(
                  text: 'Email is not stored locally.',
                  note: 'Re-login to update account email.',
                ),
              ),
              const SizedBox(height: 16),
              _Field(
                label: 'Change Password',
                child: _UnavailableNote(
                  text: 'Password changes are not yet available in-app.',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _Section(
            title: 'App Preferences',
            children: [
              _Field(
                label: 'Default GPS Accuracy Threshold',
                sublabel:
                    'Applied to new races when no value is set. Current: ${_gpsAccuracy.round()} m',
                child: _GpsSlider(
                  value: _gpsAccuracy,
                  onChanged: (v) => setState(() => _gpsAccuracy = v),
                ),
              ),
              const SizedBox(height: 20),
              _Field(
                label: 'Default Anomaly Sensitivity',
                sublabel:
                    'Applied to new races when no value is set.',
                child: _SensDropdown(
                  value: _anomalySens,
                  onChanged: (v) => setState(() => _anomalySens = v!),
                ),
              ),
              const SizedBox(height: 20),
              _Field(
                label: 'Dark Mode',
                child: _LockedToggle(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Save button ───────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 42,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGreen,
                  foregroundColor: const Color(0xFF080810),
                  disabledBackgroundColor: _kGreen.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF080810)),
                      )
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ),

          const SizedBox(height: 40),

          // ── Danger zone ───────────────────────────────────────────────────
          _Section(
            title: 'Danger Zone',
            titleColor: _kRed,
            children: [
              Row(
                children: [
                  const Spacer(),
                  SizedBox(
                    width: 200,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: const Text('Log Out'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kRed,
                        side: BorderSide(color: _kRed.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String   title;
  final Color    titleColor;
  final List<Widget> children;

  static const _kSurface   = Color(0xFF0D0D18);
  static const _kBorder    = Color(0xFF1E1E32);
  static const _kTextSub   = Color(0xFF8888AA);

  const _Section({
    required this.title,
    required this.children,
    this.titleColor = _kTextSub,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color:         titleColor,
            fontSize:      10,
            fontWeight:    FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(14),
            border:       Border.all(color: _kBorder),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

// ── Field row ─────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String  label;
  final String? sublabel;
  final Widget  child;

  static const _kTextPri  = Colors.white;
  static const _kTextSub  = Color(0xFF8888AA);

  const _Field({
    required this.label,
    required this.child,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              color:      _kTextPri,
              fontSize:   13,
              fontWeight: FontWeight.w600,
            )),
        if (sublabel != null) ...[
          const SizedBox(height: 3),
          Text(sublabel!,
              style: const TextStyle(color: _kTextSub, fontSize: 11)),
        ],
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

// ── Editable text input ───────────────────────────────────────────────────────

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  static const _kSurfaceHi = Color(0xFF141422);
  static const _kBorder    = Color(0xFF1E1E32);
  static const _kTextPri   = Colors.white;
  static const _kTextSub   = Color(0xFF8888AA);

  const _TextInput({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:  controller,
      style:       const TextStyle(color: _kTextPri, fontSize: 13),
      decoration: InputDecoration(
        hintText:       hint,
        hintStyle:      const TextStyle(color: _kTextSub, fontSize: 13),
        filled:         true,
        fillColor:      _kSurfaceHi,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF00FF9C), width: 1.5),
        ),
      ),
    );
  }
}

// ── Read-only info chip ───────────────────────────────────────────────────────

class _ReadOnlyInfo extends StatelessWidget {
  final String text;
  final String note;

  static const _kSurfaceHi = Color(0xFF141422);
  static const _kBorder    = Color(0xFF1E1E32);
  static const _kTextSub   = Color(0xFF8888AA);
  static const _kTextMuted = Color(0xFF3A3A55);

  const _ReadOnlyInfo({required this.text, required this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color:        _kSurfaceHi,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(color: _kTextSub, fontSize: 13)),
          const SizedBox(height: 3),
          Text(note, style: const TextStyle(color: _kTextMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Unavailable note ──────────────────────────────────────────────────────────

class _UnavailableNote extends StatelessWidget {
  final String text;

  static const _kSurfaceHi = Color(0xFF141422);
  static const _kBorder    = Color(0xFF1E1E32);
  static const _kTextMuted = Color(0xFF3A3A55);

  const _UnavailableNote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color:        _kSurfaceHi,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 14, color: _kTextMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _kTextMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── GPS accuracy slider ───────────────────────────────────────────────────────

class _GpsSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  static const _kGreen    = Color(0xFF00FF9C);
  static const _kTextSub  = Color(0xFF8888AA);
  static const _kTextMuted= Color(0xFF3A3A55);

  const _GpsSlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor:   _kGreen,
            inactiveTrackColor: const Color(0xFF1E1E32),
            thumbColor:         _kGreen,
            overlayColor:       _kGreen.withOpacity(0.12),
            trackHeight:        3,
          ),
          child: Slider(
            value: value,
            min:   10.0,
            max:   100.0,
            divisions: 18,
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('10 m', style: TextStyle(color: _kTextMuted, fontSize: 10)),
              const Text('100 m', style: TextStyle(color: _kTextMuted, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Anomaly sensitivity dropdown ──────────────────────────────────────────────

class _SensDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;

  static const _kSurfaceHi = Color(0xFF141422);
  static const _kBorder    = Color(0xFF1E1E32);
  static const _kGreen     = Color(0xFF00FF9C);
  static const _kTextPri   = Colors.white;
  static const _kTextSub   = Color(0xFF8888AA);

  const _SensDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color:        _kSurfaceHi,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value:         value,
          dropdownColor: const Color(0xFF141422),
          style:         const TextStyle(color: _kTextPri, fontSize: 13),
          iconEnabledColor: _kTextSub,
          isExpanded:    true,
          onChanged:     onChanged,
          items: const [
            DropdownMenuItem(value: 'low',    child: Text('Low')),
            DropdownMenuItem(value: 'medium', child: Text('Medium')),
            DropdownMenuItem(value: 'high',   child: Text('High')),
          ],
        ),
      ),
    );
  }
}

// ── Dark mode locked toggle ───────────────────────────────────────────────────

class _LockedToggle extends StatelessWidget {
  static const _kSurfaceHi = Color(0xFF141422);
  static const _kBorder    = Color(0xFF1E1E32);
  static const _kGreen     = Color(0xFF00FF9C);
  static const _kTextSub   = Color(0xFF8888AA);
  static const _kTextMuted = Color(0xFF3A3A55);

  const _LockedToggle();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        _kSurfaceHi,
        borderRadius: BorderRadius.circular(10),
        border:       Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          const Text('Dark Mode',
              style: TextStyle(color: _kTextSub, fontSize: 13)),
          const Spacer(),
          Switch(
            value:             true,
            onChanged:         null, // locked
            activeColor:       _kGreen,
            activeTrackColor:  _kGreen.withOpacity(0.25),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.lock_outline_rounded,
              size: 12, color: _kTextMuted),
        ],
      ),
    );
  }
}

// ── Logout confirmation dialog ────────────────────────────────────────────────

class _LogoutDialog extends StatelessWidget {
  static const _kSurface  = Color(0xFF0D0D18);
  static const _kBorder   = Color(0xFF1E1E32);
  static const _kTextPri  = Colors.white;
  static const _kTextSub  = Color(0xFF8888AA);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Log Out',
                style: TextStyle(
                    color: _kTextPri, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Are you sure you want to log out?',
                style: TextStyle(color: _kTextSub, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kTextSub,
                      side: const BorderSide(color: _kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4D4D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
    );
  }
}
