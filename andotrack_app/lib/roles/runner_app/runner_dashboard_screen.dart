import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/core/services/location_service.dart';
import 'package:andotrack_app/core/utils/date_utils.dart';
import 'package:andotrack_app/features/leaderboard/screens/final_results_screen.dart';
import 'package:andotrack_app/features/map/screens/runner_map_screen.dart';
import 'package:andotrack_app/features/race/screens/race_detail_screen.dart';
import 'package:andotrack_app/features/runner/screens/race_history_screen.dart';
import 'package:andotrack_app/features/runner/screens/runner_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  RunnerDashboardScreen — Bottom nav shell (Home | Race History | Profile)
// ─────────────────────────────────────────────────────────────────────────────
class RunnerDashboardScreen extends StatefulWidget {
  const RunnerDashboardScreen({super.key});

  @override
  State<RunnerDashboardScreen> createState() => _RunnerDashboardScreenState();
}

class _RunnerDashboardScreenState extends State<RunnerDashboardScreen> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: IndexedStack(
        index: _navIndex,
        children: const [
          _HomeTab(),
          RaceHistoryScreen(),
          RunnerProfileScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bottom Navigation Bar
// ─────────────────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, Icons.home_outlined, 'Home'),
      (Icons.history_rounded, Icons.history_outlined, 'Race History'),
      (Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.07), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final isSelected = i == currentIndex;
              final item = items[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isSelected ? item.$1 : item.$2,
                        color: isSelected
                            ? const Color(0xFF00FF9C)
                            : const Color(0xFF444460),
                        size: 24,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF00FF9C)
                              : const Color(0xFF444460),
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Home Tab — My Races / Browse tabs
// ─────────────────────────────────────────────────────────────────────────────
class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<Map<String, dynamic>> _allRaces = [];
  bool _loading = true;
  bool _checkingRegistrations = false;
  String? _error;
  String _userName = '';
  int? _userId;

  // raceId → runner data (qr_token, qr_image_base64, etc.)
  final Map<int, Map<String, dynamic>> _registrationByRace = {};

  // Countdown timers map: raceId → remaining duration string
  final Map<int, String> _countdowns = {};
  Timer? _countdownTimer;

  // ── Location tracking ─────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;
  int? _trackingRaceId;

  void _startLocationTracking(int raceId, int runnerId) {
    // Already tracking this race — do nothing
    if (_trackingRaceId == raceId && _locationSub != null) return;

    _locationSub?.cancel();
    _trackingRaceId = raceId;

    debugPrint('[LocationTracking] Starting GPS tracking for race=$raceId runner=$runnerId');

    _locationSub = LocationService.getLocationStream().listen(
      (Position pos) async {
        try {
          await ApiService.post(
            '/runners/$runnerId/location',
            {
              'lat':       pos.latitude,
              'lng':       pos.longitude,
              'speed':     pos.speed,
              'accuracy':  pos.accuracy,
              'race_id':   raceId,
            },
          );
          debugPrint('[LocationTracking] POST /runners/$runnerId/location with lat=${pos.latitude} lng=${pos.longitude}');
        } catch (e) {
          debugPrint('[LocationTracking] Failed to send location: $e');
        }
      },
      onError: (e) {
        debugPrint('[LocationTracking] Stream error: $e');
      },
    );
  }

  void _stopLocationTracking() {
    if (_locationSub != null) {
      debugPrint('[LocationTracking] Stopping GPS tracking');
      _locationSub?.cancel();
      _locationSub = null;
      _trackingRaceId = null;
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserAndRaces();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _updateCountdowns(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _countdownTimer?.cancel();
    _stopLocationTracking();
    super.dispose();
  }

  Future<void> _loadUserAndRaces() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Runner';
        _userId = prefs.getInt('user_id');
      });
    }
    await _loadRaces();
  }

  Future<void> _loadRaces() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final races = await ApiService.getRaces();
      if (!mounted) return;
      setState(() {
        _allRaces = races;
        _loading = false;
      });
      _updateCountdowns();
      // Check registrations in background — does NOT block the UI
      _checkRegistrations(races);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load races. Pull down to retry.';
        _loading = false;
      });
    }
  }

  void _updateCountdowns() {
    if (!mounted) return;
    final now = DateTime.now();
    final updated = <int, String>{};
    for (final race in _allRaces) {
      final id = race['id'] as int;
      final scheduled = race['scheduled_start'];
      if (scheduled == null) continue;
      try {
        final dt   = parsePht(scheduled.toString());
        final diff = dt.difference(now);
        debugPrint('[RunnerDash] countdown raceId=$id'
            '  raw="$scheduled"'
            '  parsed=$dt'
            '  now=$now'
            '  remainingSecs=${diff.inSeconds}');
        if (diff.isNegative) {
          updated[id] = '';
        } else {
          final days  = diff.inDays;
          final hours = diff.inHours % 24;
          if (days > 0) {
            updated[id] = '${days}d ${hours}h';
          } else {
            final mins = diff.inMinutes % 60;
            updated[id] = '${hours}h ${mins}m';
          }
        }
      } catch (_) {}
    }
    setState(() => _countdowns.addAll(updated));
  }

  // ── FIX: check registrations without blocking UI ──────────────────────────
  // We fetch runners for each race in parallel using Future.wait,
  // then update state once. Errors per-race are swallowed gracefully.
  Future<void> _checkRegistrations(List<Map<String, dynamic>> races) async {
    if (_userId == null || !mounted) return;
    if (_checkingRegistrations) return; // prevent concurrent calls
    _checkingRegistrations = true;

    // Only check races that aren't finished (finished ones handled by history)
    final relevant = races
        .where((r) => r['status'] != 'finished')
        .toList();

    final newRegistrations = <int, Map<String, dynamic>>{};

    await Future.wait(
      relevant.map((race) async {
        final raceId = race['id'] as int;
        final raceStatus = race['status']?.toString() ?? '';
        try {
          final runners = await ApiService.getRaceRunners(raceId);
          final match = runners
              .cast<Map<String, dynamic>>()
              .where((r) => r['user_id'] == _userId);
          if (match.isNotEmpty) {
            final runner = match.first;
            // Fetch bib + shirt from QR endpoint (includes extra fields)
            int? bib;
            String shirt = '';
            try {
              final qrData = await ApiService.getRunnerQr(
                runnerId: _userId!,
                raceId: raceId,
              );
              bib = qrData['bib_number'] as int?;
              shirt = qrData['shirt_size'] as String? ?? '';
            } catch (_) {}
            newRegistrations[raceId] = {
              'race_id': raceId,
              'race_name': race['name'],
              'runner_name': _userName,
              'qr_token': runner['qr_token'] ?? '',
              'qr_image_base64': runner['qr_image_base64'] ?? '',
              'bib_number': bib,
              'shirt_size': shirt,
              'runner_id': runner['id'] ?? runner['runner_id'] ?? _userId,
            };

            // ── Start GPS tracking if race is active ────────────────────────
            if (raceStatus == 'active') {
              final runnerId = (runner['id'] ?? runner['runner_id'] ?? _userId) as int;
              final hasPermission = await LocationService.requestPermission();
              if (hasPermission) {
                _startLocationTracking(raceId, runnerId);
              } else {
                debugPrint('[LocationTracking] Permission denied — cannot track');
              }
            }
          }
        } catch (_) {
          // Individual race failure is non-fatal — skip silently
        }
      }),
    );

    // Stop tracking if no active race found
    if (!newRegistrations.values.any((registration) =>
        relevant.any((r) =>
            r['id'] == registration['race_id'] && r['status'] == 'active'))) {
      _stopLocationTracking();
    }

    if (!mounted) return;
    setState(() {
      _registrationByRace.addAll(newRegistrations);
      _checkingRegistrations = false;
    });
  }

  Future<void> _joinRace(Map<String, dynamic> race) async {
    final raceId = race['id'] as int;
    final status = race['status']?.toString() ?? 'upcoming';
    final isRegistered = _registrationByRace.containsKey(raceId);

    if (status == 'active' && isRegistered) {
      // Go to the live map
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_race_id', raceId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RunnerMapScreen()),
      );
    } else if (status == 'finished' && isRegistered) {
      // Go to final results
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FinalResultsScreen(
            raceId: raceId,
            raceName: race['name']?.toString(),
          ),
        ),
      );
    } else {
      // Go to race detail (which handles registration + QR viewing)
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RaceDetailScreen(race: race)),
      ).then((_) => _loadRaces());
    }
  }

  // My Races = races the user is registered for
  List<Map<String, dynamic>> get _myRaces => _allRaces
      .where((r) => _registrationByRace.containsKey(r['id'] as int))
      .toList();

  // Browse = all races not yet registered for (and not finished)
  List<Map<String, dynamic>> get _browseRaces => _allRaces
      .where((r) =>
          !_registrationByRace.containsKey(r['id'] as int) &&
          r['status'] != 'finished')
      .toList();

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(),
                    style: const TextStyle(
                      color: Color(0xFF666680),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab bar ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.07)),
                ),
                child: TabBar(
                  controller: _tabController,
                  padding: const EdgeInsets.all(4),
                  indicator: BoxDecoration(
                    color: const Color(0xFF1A2A1A),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: const Color(0xFF00FF9C).withOpacity(0.4)),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: const Color(0xFF00FF9C),
                  unselectedLabelColor: const Color(0xFF555570),
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                  ),
                  tabs: const [
                    Tab(text: 'My Races'),
                    Tab(text: 'Browse'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Content ───────────────────────────────────────
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
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildMyRaces(),
                            _buildBrowse(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyRaces() {
    if (_myRaces.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                // Show subtle loading indicator while registrations load
                if (_checkingRegistrations)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF444460),
                        strokeWidth: 1.5,
                      ),
                    ),
                  ),
                Icon(
                  Icons.flag_outlined,
                  size: 56,
                  color: Colors.white.withOpacity(0.06),
                ),
                const SizedBox(height: 16),
                Text(
                  _checkingRegistrations
                      ? 'Loading your races...'
                      : 'No registered races yet',
                  style: const TextStyle(
                      color: Color(0xFF444460), fontSize: 15),
                ),
                const SizedBox(height: 6),
                if (!_checkingRegistrations)
                  const Text(
                    'Browse and register for a race',
                    style: TextStyle(color: Color(0xFF2E2E48), fontSize: 12),
                  ),
                const SizedBox(height: 20),
                if (!_checkingRegistrations)
                  TextButton(
                    onPressed: () => _tabController.animateTo(1),
                    child: const Text(
                      'Browse Races →',
                      style: TextStyle(
                          color: Color(0xFF00FF9C), fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00FF9C),
      backgroundColor: const Color(0xFF0D0D14),
      onRefresh: _loadRaces,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _myRaces.length,
        itemBuilder: (ctx, i) {
          final race = _myRaces[i];
          final raceId = race['id'] as int;
          return _MyRaceCard(
            race: race,
            countdown: _countdowns[raceId],
            registrationData: _registrationByRace[raceId],
            onTap: () => _joinRace(race),
          );
        },
      ),
    );
  }

  Widget _buildBrowse() {
    if (_browseRaces.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 60),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 56,
                  color: Colors.white.withOpacity(0.06),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No more races to browse',
                  style: TextStyle(color: Color(0xFF444460), fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF00FF9C),
      backgroundColor: const Color(0xFF0D0D14),
      onRefresh: _loadRaces,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _browseRaces.length,
        itemBuilder: (ctx, i) {
          final race = _browseRaces[i];
          return _BrowseRaceCard(
            race: race,
            onTap: () => _joinRace(race),
          );
        },
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
                style:
                    const TextStyle(color: Color(0xFF666680), fontSize: 13),
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
}

// ─────────────────────────────────────────────────────────────────────────────
//  My Race Card — shows registered races with Live/Upcoming status + countdown
// ─────────────────────────────────────────────────────────────────────────────
class _MyRaceCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final String? countdown;
  final Map<String, dynamic>? registrationData;
  final VoidCallback onTap;

  const _MyRaceCard({
    required this.race,
    required this.countdown,
    required this.onTap,
    this.registrationData,
  });

  @override
  Widget build(BuildContext context) {
    final status = race['status']?.toString() ?? 'upcoming';
    final name = race['name']?.toString() ?? 'Race';
    final distance = race['distance_km'];
    final scheduled = race['scheduled_start'];
    final isActive = status == 'active';
    final isFinished = status == 'finished';

    String? dateLabel;
    if (scheduled != null) {
      try {
        final dt = DateTime.parse(scheduled);
        final now = DateTime.now();
        final isToday = dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
        if (isToday) {
          dateLabel = 'Today';
        } else {
          dateLabel =
              '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
        }
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? const Color(0xFF00FF9C).withOpacity(0.3)
                : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + Status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _StatusPill(status: status),
                ],
              ),

              const SizedBox(height: 6),

              // Date · Distance
              Row(
                children: [
                  if (dateLabel != null) ...[
                    const Icon(Icons.calendar_today_outlined,
                        size: 12, color: Color(0xFF444460)),
                    const SizedBox(width: 4),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                          color: Color(0xFF666680), fontSize: 12),
                    ),
                    if (distance != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: Color(0xFF333348),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                  if (distance != null)
                    Row(children: [
                      const Icon(Icons.place_outlined,
                          size: 12, color: Color(0xFF444460)),
                      const SizedBox(width: 4),
                      Text(
                        '${distance}K',
                        style: const TextStyle(
                            color: Color(0xFF666680), fontSize: 12),
                      ),
                    ]),
                ],
              ),

              // Bib number row
              if (registrationData?['bib_number'] != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF9C).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFF00FF9C).withOpacity(0.25)),
                      ),
                      child: Text(
                        'Bib #${registrationData!['bib_number']}',
                        style: const TextStyle(
                          color: Color(0xFF00FF9C),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if ((registrationData!['shirt_size'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Size ${registrationData!['shirt_size']}',
                          style: const TextStyle(
                              color: Color(0xFF666680), fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Action button
              if (isActive)
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00FF9C),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Join Live Race',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                )
              else if (isFinished)
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF666680),
                      side: BorderSide(color: Colors.white.withOpacity(0.1)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('View Results'),
                  ),
                )
              else if (countdown != null && countdown!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1500),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFFB800).withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: Color(0xFFFFB800)),
                      const SizedBox(width: 8),
                      Text(
                        'Starts in $countdown',
                        style: const TextStyle(
                          color: Color(0xFFFFB800),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Registered, not started yet, no countdown
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF9C).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF00FF9C).withOpacity(0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 14, color: Color(0xFF00FF9C)),
                      SizedBox(width: 8),
                      Text(
                        'Registered',
                        style: TextStyle(
                          color: Color(0xFF00FF9C),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthName(int m) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[m];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Browse Race Card — upcoming/open races with Register button
// ─────────────────────────────────────────────────────────────────────────────
class _BrowseRaceCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback onTap;

  const _BrowseRaceCard({required this.race, required this.onTap});

  String _formatDate(String? raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw);
      const months = ['','Jan','Feb','Mar','Apr','May','Jun',
          'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = race['status']?.toString() ?? 'upcoming';
    final name = race['name']?.toString() ?? 'Race';
    final distance = race['distance_km'];
    final fee = race['registration_fee'] ?? 0;
    final slots = race['slots_remaining'];
    final location = race['location']?.toString() ?? '';
    final dateLabel = _formatDate(race['scheduled_start'] as String?);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _StatusPill(status: status),
                ],
              ),

              if (location.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.place_outlined,
                      size: 12, color: Color(0xFF444460)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location,
                      style: const TextStyle(
                          color: Color(0xFF666680), fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ],

              if (dateLabel.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 12, color: Color(0xFF444460)),
                  const SizedBox(width: 4),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                        color: Color(0xFF666680), fontSize: 12),
                  ),
                ]),
              ],

              const SizedBox(height: 10),

              // Chips row
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (distance != null)
                    _InfoChip(
                      icon: Icons.straighten_outlined,
                      label: '${distance}km',
                    ),
                  if ((fee as num) > 0)
                    _InfoChip(
                      icon: Icons.payments_outlined,
                      label: '₱${(fee as num).toStringAsFixed(0)}',
                    ),
                  if (slots != null)
                    _InfoChip(
                      icon: Icons.people_outline,
                      label: '$slots slots',
                      color: (slots as int) < 10
                          ? const Color(0xFFFF4D4D)
                          : null,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4FF),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'View & Register',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
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

// ─────────────────────────────────────────────────────────────────────────────
//  Status Pill
// ─────────────────────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    bool showDot = false;

    switch (status) {
      case 'active':
        color = const Color(0xFF00FF9C);
        label = 'LIVE';
        showDot = true;
        break;
      case 'registration_open':
        color = const Color(0xFF00B4FF);
        label = 'OPEN';
        break;
      case 'race_day':
        color = const Color(0xFFFFB800);
        label = 'RACE DAY';
        break;
      case 'finished':
        color = const Color(0xFF555570);
        label = 'FINISHED';
        break;
      default:
        color = const Color(0xFFFFB800);
        label = 'UPCOMING';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Info Chip
// ─────────────────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF444460);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: c, fontSize: 12),
        ),
      ],
    );
  }
}