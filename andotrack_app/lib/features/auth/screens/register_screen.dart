// lib/features/auth/screens/register_screen.dart
//
// Runner-only self-registration.
// Staff and Race Director accounts are provisioned by Race Directors
// through the web dashboard. Do NOT add organizer/staff registration here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/roles/runner_app/runner_dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool    _isLoading       = false;
  bool    _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name     = _nameCtrl.text.trim();
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }
    if (password.length < 6) {
      setState(() =>
          _errorMessage = 'Password must be at least 6 characters.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      // Role is always 'runner' here — staff/director accounts are
      // created by Race Directors via the web dashboard, not self-service.
      final result =
          await ApiService.register(name, email, password, 'runner');

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', result['token'] as String);
        await prefs.setString('user_role', result['role']  as String);
        await prefs.setInt('user_id',      result['user_id'] as int);
        await prefs.setString('user_name', result['name']  as String);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RunnerDashboardScreen()),
        );
      } else {
        setState(() =>
            _errorMessage = result['message'] ?? 'Registration failed.');
      }
    } catch (_) {
      setState(() =>
          _errorMessage = 'Connection error. Is the server running?');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _kBg      = Color(0xFF0A0A0F);
  static const _kSurface = Color(0xFF080810);
  static const _kBorder  = Color(0xFF1E1E30);
  static const _kAccent  = Color(0xFF00FF9C);
  static const _kLabel   = Colors.white;
  static const _kSub     = Color(0xFF888899);
  static const _kMuted   = Color(0xFF666680);

  InputDecoration _inputDeco({
    required String   hint,
    required IconData icon,
    Widget?           suffix,
  }) =>
      InputDecoration(
        hintText:    hint,
        hintStyle:   const TextStyle(color: _kMuted, fontSize: 14),
        prefixIcon:  Icon(icon, color: _kSub, size: 18),
        suffixIcon:  suffix,
        filled:      true,
        fillColor:   _kSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   const BorderSide(color: _kAccent, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation:       0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness:     Brightness.dark,
          statusBarIconBrightness: Brightness.light,
        ),
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back, color: _kSub),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Header ────────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'android/favicon.png',
                      width:  80,
                      height: 80,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize:     28,
                        fontWeight:   FontWeight.w900,
                        color:        _kLabel,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Join AndoTrack as a Runner',
                      style: TextStyle(color: _kSub, fontSize: 13),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // ── Full Name ─────────────────────────────────────────────
              const Text('Full Name',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:      _kLabel,
                      fontSize:   13)),
              const SizedBox(height: 8),
              TextField(
                controller:         _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style:              const TextStyle(color: _kLabel),
                decoration:         _inputDeco(
                  hint: 'Enter your name',
                  icon: Icons.person_outline_rounded,
                ),
              ),

              const SizedBox(height: 20),

              // ── Email ─────────────────────────────────────────────────
              const Text('Email',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:      _kLabel,
                      fontSize:   13)),
              const SizedBox(height: 8),
              TextField(
                controller:   _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style:        const TextStyle(color: _kLabel),
                decoration:   _inputDeco(
                  hint: 'Enter your email',
                  icon: Icons.email_outlined,
                ),
              ),

              const SizedBox(height: 20),

              // ── Password ──────────────────────────────────────────────
              const Text('Password',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:      _kLabel,
                      fontSize:   13)),
              const SizedBox(height: 8),
              TextField(
                controller:  _passwordCtrl,
                obscureText: _obscurePassword,
                style:       const TextStyle(color: _kLabel),
                decoration:  _inputDeco(
                  hint:   'At least 6 characters',
                  icon:   Icons.lock_outline_rounded,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _kSub, size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Error ─────────────────────────────────────────────────
              if (_errorMessage != null)
                Container(
                  width:   double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color:        const Color(0xFFFF4D4D).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(
                        color: const Color(0xFFFF4D4D).withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                        color: Color(0xFFFF6B6B), fontSize: 13),
                  ),
                ),

              const SizedBox(height: 24),

              // ── Submit ────────────────────────────────────────────────
              SizedBox(
                width:  double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                              fontSize:   15,
                              fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Back to login ─────────────────────────────────────────
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text.rich(
                    TextSpan(
                      text:  'Already have an account? ',
                      style: TextStyle(color: _kMuted),
                      children: [
                        TextSpan(
                          text:  'Sign In',
                          style: TextStyle(
                              color:      _kAccent,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}