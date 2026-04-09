import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'runner_map_screen.dart';
import 'settings_screen.dart';
import 'leaderboard_screen.dart';
import 'final_results_screen.dart';

class RunnerDashboardScreen extends StatefulWidget {
  const RunnerDashboardScreen({super.key});

  @override
  State<RunnerDashboardScreen> createState() => _RunnerDashboardScreenState();
}

class _RunnerDashboardScreenState extends State<RunnerDashboardScreen> {
  List<Map<String, dynamic>> _races = [];
  bool _loading = true;
  String? _error;
  String _userName = '';
  int? _userId;

  // Which status filter is active
  String _filter = 'all'; // all | active | upcoming | finished

  @override
  void initState() {
    super.initState();
    _loadUserAndRaces();
  }

  Future<void> _loadUserAndRaces() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('user_name') ?? 'Runner';
      _userId = prefs.getInt('user_id');
    });
    await _loadRaces();
  }

  Future<void> _loadRaces() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final races = await ApiService.getRaces();
      if (mounted) {
        setState(() {
          _races = races;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load races. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _joinRace(Map<String, dynamic> race) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('active_race_id', race['id'] as int);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunnerMapScreen()),
    );
  }

  List<Map<String, dynamic>> get _filteredRaces {
    if (_filter == 'all') return _races;
    return _races.where((r) => r['status'] == _filter).toList();
  }

  int _countByStatus(String status) =>
      _races.where((r) => r['status'] == status).length;

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF00FF9C);
      case 'finished':
        return const Color(0xFF666680);
      default:
        return const Color(0xFFFFB800);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'active':
        return '● Live';
      case 'finished':
        return 'Finished';
      default:
        return 'Upcoming';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildStatCards(),
            _buildFilterChips(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00FF9C),
                        strokeWidth: 2,
                      ),
                    )
                  : _error != null
                      ? _buildError()
                      : RefreshIndicator(
                          color: const Color(0xFF00FF9C),
                          backgroundColor: const Color(0xFF0D0D14),
                          onRefresh: _loadRaces,
                          child: _filteredRaces.isEmpty
                              ? _buildEmpty()
                              : _buildRaceList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hi, $_userName!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _greeting(),
                  style: const TextStyle(
                    color: Color(0xFF666680),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Leaderboard shortcut
          _HeaderIconBtn(
            icon: Icons.leaderboard_outlined,
            onTap: () {
              final active = _races.where((r) => r['status'] == 'active');
              if (active.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No active race to show leaderboard for.'),
                    backgroundColor: Color(0xFF1E1E30),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      LeaderboardScreen(raceId: active.first['id'] as int),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          _HeaderIconBtn(
            icon: Icons.settings_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          _StatCard(
            value: '${_countByStatus('active')}',
            label: 'Active',
            color: const Color(0xFF00FF9C),
          ),
          const SizedBox(width: 8),
          _StatCard(
            value: '${_countByStatus('upcoming')}',
            label: 'Upcoming',
            color: const Color(0xFFFFB800),
          ),
          const SizedBox(width: 8),
          _StatCard(
            value: '${_countByStatus('finished')}',
            label: 'Finished',
            color: const Color(0xFF666680),
          ),
          const SizedBox(width: 8),
          _StatCard(
            value: '${_races.length}',
            label: 'Total',
            color: const Color(0xFF00B4FF),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    const filters = [
      ('all', 'All'),
      ('active', 'Live'),
      ('upcoming', 'Upcoming'),
      ('finished', 'Finished'),
    ];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: filters.map((f) {
          final isSelected = _filter == f.$1;
          return GestureDetector(
            onTap: () => setState(() => _filter = f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00FF9C).withOpacity(0.15)
                    : const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF00FF9C).withOpacity(0.5)
                      : const Color(0xFF1E1E30),
                ),
              ),
              child: Center(
                child: Text(
                  f.$2,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF00FF9C)
                        : const Color(0xFF666680),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRaceList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _filteredRaces.length,
      itemBuilder: (context, i) => _RaceCard(
        race: _filteredRaces[i],
        statusColor: _statusColor(_filteredRaces[i]['status'] ?? 'upcoming'),
        statusLabel: _statusLabel(_filteredRaces[i]['status'] ?? 'upcoming'),
        onJoin: () => _joinRace(_filteredRaces[i]),
        onResults: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FinalResultsScreen(
              raceId: _filteredRaces[i]['id'] as int,
              raceName: _filteredRaces[i]['name']?.toString(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              const Icon(Icons.wifi_off, color: Color(0xFF444460), size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFF666680), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadRaces,
                child: const Text('Retry',
                    style: TextStyle(color: Color(0xFF00B4FF))),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.flag_outlined,
                size: 56,
                color: Colors.white.withOpacity(0.08),
              ),
              const SizedBox(height: 16),
              const Text(
                'No races found',
                style: TextStyle(color: Color(0xFF444460), fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Check back soon or ask your organizer',
                style: TextStyle(color: Color(0xFF333348), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning · Runner';
    if (h < 17) return 'Good afternoon · Runner';
    return 'Good evening · Runner';
  }
}

// ─── RACE CARD ──────────────────────────────────────────────────────────────
class _RaceCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onJoin;
  final VoidCallback onResults;

  const _RaceCard({
    required this.race,
    required this.statusColor,
    required this.statusLabel,
    required this.onJoin,
    required this.onResults,
  });

  @override
  Widget build(BuildContext context) {
    final status = race['status']?.toString() ?? 'upcoming';
    final name = race['name']?.toString() ?? 'Race #${race['id']}';
    final distance = race['distance_km'];
    final isActive = status == 'active';
    final isFinished = status == 'finished';
    final isUpcoming = status == 'upcoming';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF00FF9C).withOpacity(0.04)
            : const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00FF9C).withOpacity(0.3)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Status icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.play_circle_outline_rounded
                        : isFinished
                            ? Icons.flag_rounded
                            : Icons.schedule_rounded,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (distance != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${(distance as num).toStringAsFixed(1)} km',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Action button
            if (isActive || isUpcoming) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isActive || isUpcoming ? onJoin : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive
                        ? const Color(0xFF00FF9C)
                        : const Color(0xFF1E1E30),
                    foregroundColor:
                        isActive ? Colors.black : const Color(0xFF666680),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                  child: Text(
                    isActive ? '▶  Continue Race' : 'Join Race',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            if (isFinished) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onResults,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF666680),
                    side: BorderSide(color: Colors.white.withOpacity(0.08)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('View Results'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── STAT CARD ──────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatCard(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color.withOpacity(0.6),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── HEADER ICON BUTTON ─────────────────────────────────────────────────────
class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HeaderIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF1E1E30)),
        ),
        child: Icon(icon, color: Colors.white54, size: 20),
      ),
    );
  }
}