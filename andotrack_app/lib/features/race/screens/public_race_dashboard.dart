import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/utils/date_utils.dart';
import 'package:andotrack_app/features/auth/screens/login_screen.dart';
import 'package:andotrack_app/features/race/screens/public_race_detail_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kBg        = Color(0xFF0A0A0F);
const _kSurface   = Color(0xFF0D0D18);
const _kBorder    = Color(0xFF1E1E32);
const _kGreen     = Color(0xFF00FF9C);
const _kBlue      = Color(0xFF00B4FF);
const _kPurple    = Color(0xFF8B5CF6);
const _kTextPri   = Colors.white;
const _kTextSub   = Color(0xFF8888AA);
const _kTextMuted = Color(0xFF3A3A55);

// ─────────────────────────────────────────────────────────────────────────────

class PublicRaceDashboard extends StatefulWidget {
  const PublicRaceDashboard({super.key});

  @override
  State<PublicRaceDashboard> createState() => _PublicRaceDashboardState();
}

class _PublicRaceDashboardState extends State<PublicRaceDashboard> {
  List<Map<String, dynamic>> _races = [];
  bool    _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRaces();
  }

  Future<void> _loadRaces() async {
    setState(() { _loading = true; _error = null; });
    try {
      final races = await ApiService.getPublicRaces();
      if (!mounted) return;
      races.sort((a, b) => _statusOrder(a['status']?.toString() ?? '')
          .compareTo(_statusOrder(b['status']?.toString() ?? '')));
      setState(() { _races = races; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  int _statusOrder(String status) {
    if (status == 'active')   return 0;
    if (status == 'finished') return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: _kGreen, strokeWidth: 2))
                : _error != null
                    ? _buildError()
                    : _buildRaceList(),
          ),
        ],
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Image.asset('assets/images/favicon.png', width: 28, height: 28),
          const SizedBox(width: 10),
          const Text(
            'AndoTrack',
            style: TextStyle(
              color:         _kGreen,
              fontSize:      18,
              fontWeight:    FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kTextSub,
              side:  const BorderSide(color: _kBorder),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('Staff Login'),
          ),
        ],
      ),
    );
  }

  // ── Race list ───────────────────────────────────────────────────────────────

  Widget _buildRaceList() {
    if (_races.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy_rounded, color: _kTextMuted, size: 48),
            SizedBox(height: 12),
            Text('No races available',
                style: TextStyle(color: _kTextSub, fontSize: 14)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _kGreen,
      onRefresh: _loadRaces,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: _races.length,
        itemBuilder: (_, i) => _RaceCard(
          race:  _races[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PublicRaceDetailScreen(race: _races[i]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Error state ─────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: _kTextMuted, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              style: const TextStyle(color: _kTextSub, fontSize: 13)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loadRaces,
            child: const Text('Retry',
                style: TextStyle(color: _kBlue)),
          ),
        ],
      ),
    );
  }
}

// ── Race card ─────────────────────────────────────────────────────────────────

class _RaceCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback          onTap;
  const _RaceCard({required this.race, required this.onTap});

  String _statusLabel(String? status) {
    switch (status) {
      case 'active':   return 'LIVE';
      case 'finished': return 'FINISHED';
      default:         return 'UPCOMING';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'active':   return _kGreen;
      case 'finished': return _kTextMuted;
      default:         return _kPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status   = race['status']?.toString();
    final name     = race['name']?.toString() ?? 'Unnamed Race';
    final location = race['location']?.toString();
    final distKm   = race['distance_km'];
    final dateRaw  = race['scheduled_start']?.toString()
        ?? race['date']?.toString();
    final regCount = race['runner_count']
        ?? race['registered_count']
        ?? race['registration_count'];
    final isLive   = status == 'active';
    final color    = _statusColor(status);
    final label    = _statusLabel(status);

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color:        _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLive ? _kGreen.withOpacity(0.4) : _kBorder,
              width: isLive ? 1.5 : 1,
            ),
            boxShadow: isLive
                ? [BoxShadow(
                    color:      _kGreen.withOpacity(0.06),
                    blurRadius: 16,
                  )]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(label: label, color: color, isLive: isLive),
                  const SizedBox(width: 10),
                  if (dateRaw != null)
                    Text(
                      formatDatePht(dateRaw),
                      style: const TextStyle(
                          color: _kTextMuted, fontSize: 12),
                    ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      size: 13, color: _kTextMuted),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                name,
                style: const TextStyle(
                  color:         _kTextPri,
                  fontSize:      16,
                  fontWeight:    FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (location != null) ...[
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: _kTextSub),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(location,
                          style: const TextStyle(
                              color: _kTextSub, fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  if (location != null && distKm != null)
                    const Text(' · ',
                        style: TextStyle(color: _kTextMuted)),
                  if (distKm != null)
                    Text(
                      '${(distKm as num).toStringAsFixed(0)} km',
                      style: const TextStyle(
                          color: _kTextSub, fontSize: 12),
                    ),
                  if (regCount != null) ...[
                    const Spacer(),
                    const Icon(Icons.people_outline_rounded,
                        size: 13, color: _kTextMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${(regCount as num).toInt()} registered',
                      style: const TextStyle(
                          color: _kTextMuted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color  color;
  final bool   isLive;
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.isLive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color:  _kGreen,
                shape:  BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: _kGreen.withOpacity(0.6), blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color:         color,
              fontSize:      9,
              fontWeight:    FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
