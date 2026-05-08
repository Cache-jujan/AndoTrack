// lib/features/auth/screens/login_screen.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/features/auth/screens/register_screen.dart';
import 'package:andotrack_app/roles/race_director/shell/race_director_shell.dart';
import 'package:andotrack_app/roles/checkin_staff/shell/checkin_staff_shell.dart';
import 'package:andotrack_app/roles/kit_staff/shell/kit_staff_shell.dart';
import 'package:andotrack_app/roles/runner_app/runner_dashboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared login screen — works on both web (staff/director) and Android (runner).
//
// Platform split is handled AFTER login via _routeByRole():
//   • Web  → RaceDirectorShell / CheckinStaffShell (TODO) / KitStaffShell (TODO)
//   • Mobile → RunnerDashboardScreen
//
// Layout split via kIsWeb:
//   • Web  → dark, centered card (440 px max-width)
//   • Mobile → white, full-screen (original runner UX, untouched)
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool    _isLoading      = false;
  bool    _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<void> _login() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email and password.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final result = await ApiService.login(email, password);

      if (result['success'] == true) {
        final token = result['token'] as String;
        final role  = result['role']  as String;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token',  token);
        await prefs.setString('user_role',  role);
        await prefs.setInt('user_id',       result['user_id'] as int);
        await prefs.setString('user_name',  result['name']    as String);

        if (!mounted) return;
        _routeByRole(role);
      } else {
        setState(() => _errorMessage = result['message'] ?? 'Login failed.');
      }
    } catch (_) {
      setState(() => _errorMessage = 'Connection error. Please check your network.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Role-based routing ────────────────────────────────────────────────────
  //
  // Single source of truth for role → shell mapping.
  // Batch 2A: organizer/race_director now routes to RaceDirectorShell.
  // Batch 2B: replace CheckinStaffShell / KitStaffShell TODOs below.

  void _routeByRole(String role) {
    Widget destination;

    switch (role) {
      case 'organizer':
      case 'race_director':
        destination = const RaceDirectorShell();
        break;

      case 'checkin_staff':
        destination = const CheckinStaffShell();
        break;

      case 'kit_staff':
        destination = const KitStaffShell();
        break;

      case 'runner':
      default:
        destination = const RunnerDashboardScreen();
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => destination),
      (_) => false,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return kIsWeb ? _webScaffold() : _mobileScaffold();
  }

  // ── Web scaffold ──────────────────────────────────────────────────────────
  // Dark background, centered card — professional SaaS feel.

  Widget _webScaffold() {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color:     Colors.black.withOpacity(0.45),
                      blurRadius: 48,
                      offset:    const Offset(0, 16),
                    ),
                  ],
                ),
                child: _buildForm(isDark: true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Mobile scaffold ───────────────────────────────────────────────────────
  // White background, full-screen — original runner login UX, fully preserved.

  Widget _mobileScaffold() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: _buildForm(isDark: false),
        ),
      ),
    );
  }

  // ── Shared form ───────────────────────────────────────────────────────────
  // Same fields, same logic — only colours and spacing change between platforms.

  Widget _buildForm({required bool isDark}) {
    final labelColor  = isDark ? Colors.white         : Colors.black87;
    final subColor    = isDark ? const Color(0xFF888899) : Colors.grey;
    final accentColor = isDark ? const Color(0xFF00FF9C) : Colors.blue;
    final borderColor = isDark ? const Color(0xFF1E1E30) : Colors.grey.shade300;
    final fillColor   = isDark ? const Color(0xFF080810) : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Logo ─────────────────────────────────────────────────────────
        Center(
          child: Column(
            children: [
              Container(
                width: 68, height: 68,
                decoration: BoxDecoration(
                  color:        accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                  border:       Border.all(
                      color: accentColor.withOpacity(0.3), width: 1.5),
                ),
                child: Icon(Icons.directions_run_rounded,
                    color: accentColor, size: 36),
              ),
              const SizedBox(height: 14),
              Text(
                'AndoTrack',
                style: TextStyle(
                  fontSize:    28,
                  fontWeight:  FontWeight.w900,
                  color:       labelColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kIsWeb
                    ? 'Race Operations Platform'
                    : 'Race Tracking System',
                style: TextStyle(color: subColor, fontSize: 13),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // ── Email ─────────────────────────────────────────────────────────
        _label('Email', labelColor),
        const SizedBox(height: 8),
        TextField(
          controller:  _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style:        TextStyle(color: labelColor),
          decoration:   _inputDeco(
            hint:        'Enter your email',
            icon:        Icons.email_outlined,
            accentColor: accentColor,
            borderColor: borderColor,
            fillColor:   fillColor,
            subColor:    subColor,
          ),
          onSubmitted:  (_) => _login(),
        ),

        const SizedBox(height: 20),

        // ── Password ──────────────────────────────────────────────────────
        _label('Password', labelColor),
        const SizedBox(height: 8),
        TextField(
          controller:  _passwordCtrl,
          obscureText: _obscurePassword,
          style:       TextStyle(color: labelColor),
          decoration:  _inputDeco(
            hint:        'Enter your password',
            icon:        Icons.lock_outline_rounded,
            accentColor: accentColor,
            borderColor: borderColor,
            fillColor:   fillColor,
            subColor:    subColor,
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: subColor, size: 18,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onSubmitted:  (_) => _login(),
        ),

        const SizedBox(height: 12),

        // ── Error ─────────────────────────────────────────────────────────
        if (_errorMessage != null)
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color:        const Color(0xFFFF4D4D).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border:       Border.all(
                  color: const Color(0xFFFF4D4D).withOpacity(0.3)),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
            ),
          ),

        const SizedBox(height: 24),

        // ── Sign In button ────────────────────────────────────────────────
        SizedBox(
          width:  double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: isDark ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.black : Colors.white,
                    ),
                  )
                : const Text('Sign In',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ),

        // ── Register link — mobile / runner only ──────────────────────────
        // Staff and directors do not self-register; their accounts are
        // provisioned by a Race Director on the web dashboard.
        if (!kIsWeb) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegisterScreen()),
              ),
              child: const Text.rich(
                TextSpan(
                  text: "Don't have an account? ",
                  style: TextStyle(color: Colors.grey),
                  children: [
                    TextSpan(
                      text: 'Register',
                      style: TextStyle(
                          color: Colors.blue, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],

        // ── Web-only footer note ──────────────────────────────────────────
        if (kIsWeb) ...[
          const SizedBox(height: 28),
          Center(
            child: Text(
              'Staff accounts are provisioned by your Race Director.',
              style: TextStyle(color: subColor, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _label(String text, Color color) => Text(
    text,
    style: TextStyle(
        fontWeight: FontWeight.w600, color: color, fontSize: 13),
  );

  InputDecoration _inputDeco({
    required String  hint,
    required IconData icon,
    required Color   accentColor,
    required Color   borderColor,
    required Color   fillColor,
    required Color   subColor,
  }) =>
      InputDecoration(
        hintText:   hint,
        hintStyle:  TextStyle(color: subColor.withOpacity(0.6), fontSize: 14),
        prefixIcon: Icon(icon, color: subColor, size: 18),
        filled:     true,
        fillColor:  fillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: accentColor, width: 1.5),
        ),
      );
}