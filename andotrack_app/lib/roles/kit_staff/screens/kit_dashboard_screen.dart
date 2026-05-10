// lib/roles/kit_staff/screens/kit_dashboard_screen.dart
//
// WEB screen for the kit claiming workflow for a specific race.
//
// Three-panel layout (top → bottom):
//   • _KitDashboardTopBar  — race name + back button
//   • _SummaryBar          — live Registered / Claimed / Unclaimed / Walk-in counts
//   • _SearchAndFilter     — instant search + All / Unclaimed / Claimed filter tabs
//   • ListView             — _RunnerRow per runner + _WalkInSection at foot of Unclaimed
//
// All claiming state is held locally in _runners (List<Map>).
// Claiming is OPTIMISTIC: UI flips immediately, API fires in background.
// Revert-on-failure is handled by _revert().
//
// Walk-in assignment fires POST /races/{id}/walk-in.
// Kit claiming fires PATCH /runners/{id}/claim-kit.
//
// This file is WEB-only. Do NOT import runner_* or mobile widgets here.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';

// ── Filter enum ───────────────────────────────────────────────────────────────

enum _FilterTab { all, unclaimed, claimed }

// ── Screen ────────────────────────────────────────────────────────────────────

class KitDashboardScreen extends StatefulWidget {
  final int raceId;
  final String raceName;
  final Map<String, dynamic> raceData;

  const KitDashboardScreen({
    super.key,
    required this.raceId,
    required this.raceName,
    required this.raceData,
  });

  @override
  State<KitDashboardScreen> createState() => _KitDashboardScreenState();
}

class _KitDashboardScreenState extends State<KitDashboardScreen> {
  // Design tokens
  static const _kBg        = Color(0xFF080810);
  static const _kGreen     = Color(0xFF00FF9C);
  static const _kAmber     = Color(0xFFFFB800);
  static const _kRed       = Color(0xFFFF4D4D);
  static const _kTextSub   = Color(0xFF8888AA);
  static const _kTextMuted = Color(0xFF3A3A55);

  // State
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _runners = [];
  String _searchQuery  = '';
  _FilterTab _activeFilter = _FilterTab.unclaimed;

  // ── Computed counts ───────────────────────────────────────────────────────

  int get _totalCount     => _runners.length;
  int get _claimedCount   => _runners.where(_isClaimed).length;
  int get _unclaimedCount => _totalCount - _claimedCount;

  int get _walkinAvailable {
    final v = widget.raceData['walkin_slots']
           ?? widget.raceData['walkin_bibs_count']
           ?? widget.raceData['walk_in_slots']
           ?? 0;
    return v is num ? v.toInt() : 0;
  }

  // ── Filtered + searched list ──────────────────────────────────────────────

  List<Map<String, dynamic>> get _filteredRunners {
    var list = _runners;
    if (_activeFilter == _FilterTab.unclaimed) {
      list = list.where((r) => !_isClaimed(r)).toList();
    } else if (_activeFilter == _FilterTab.claimed) {
      list = list.where((r) =>  _isClaimed(r)).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) =>
        _runnerName(r).toLowerCase().contains(q) ||
        _bibNumber(r).toLowerCase().contains(q),
      ).toList();
    }
    return list;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadRunners();
  }

  Future<void> _loadRunners() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.get('/kit/${widget.raceId}/runners?status=all');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final list = decoded is List
            ? decoded.cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        setState(() {
          _runners = list.map((r) => Map<String, dynamic>.from(r)).toList();
          _loading = false;
        });
      } else {
        setState(() { _error = 'Could not load runners.'; _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load runners.'; _loading = false; });
    }
  }

  // ── Kit claim (optimistic) ────────────────────────────────────────────────

  void _claimKit(Map<String, dynamic> runner) {
    final id  = _runnerId(runner);
    final idx = _indexById(id);
    if (idx < 0) return;

    final original = Map<String, dynamic>.from(_runners[idx]);

    // Flip immediately — API fires in background
    setState(() {
      _runners[idx] = {
        ..._runners[idx],
        'claimed': true,
      };
    });

    ApiService.patch(
      '/kit/${widget.raceId}/runners/$id/claim',
      {'claimed': true},
    ).then((res) {
      if (mounted && res.statusCode != 200 && res.statusCode != 204) {
        _revert(idx, original);
      }
    }).catchError((_) {
      if (mounted) _revert(idx, original);
    });
  }

  void _revert(int idx, Map<String, dynamic> original) {
    if (!mounted) return;
    setState(() { if (idx < _runners.length) _runners[idx] = original; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Could not mark as claimed — please try again.'),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Walk-in assignment ────────────────────────────────────────────────────

  Future<void> _showWalkInDialog() async {
    String? assignedName;

    await showDialog<void>(
      context: context,
      builder: (_) => _WalkInDialog(
        onSubmit: (name, contact) async {
          final res = await ApiService.post(
            '/kit/${widget.raceId}/walkin',
            {'name': name, 'contact_number': contact},
          );
          if (res.statusCode != 200 && res.statusCode != 201) {
            throw Exception('Walk-in assignment failed (${res.statusCode})');
          }
          assignedName = name;
        },
      ),
    );

    if (assignedName != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Walk-in assigned to $assignedName.'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _indexById(int id) => _runners.indexWhere((r) => _runnerId(r) == id);

  static int _runnerId(Map<String, dynamic> r) {
    final v = r['runner_id'] ?? r['user_id'] ?? r['id'];
    if (v == null) return 0;
    return (v as num).toInt();
  }

  static bool _isClaimed(Map<String, dynamic> r) => r['claimed'] == true;

  static String _runnerName(Map<String, dynamic> r) =>
    (r['name'] ?? r['full_name'] ?? r['runner_name'] ?? 'Unknown').toString();

  static String _bibNumber(Map<String, dynamic> r) =>
    (r['bib_number'] ?? r['bib'] ?? r['bib_no'] ?? '—').toString();

  static String _shirtSize(Map<String, dynamic> r) {
    final s = (r['shirt_size'] ?? r['t_shirt_size'] ?? r['tshirt_size'] ?? '')
        .toString().toUpperCase().trim();
    return s.isEmpty ? '—' : s;
  }

  static String _contactNumber(Map<String, dynamic> r) =>
    (r['contact_number'] ?? r['phone'] ?? r['contact'] ?? '—').toString();

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _KitDashboardTopBar(raceName: widget.raceName),
          _SummaryBar(
            total:     _totalCount,
            claimed:   _claimedCount,
            unclaimed: _unclaimedCount,
            walkin:    _walkinAvailable,
          ),
          _SearchAndFilter(
            query:           _searchQuery,
            activeFilter:    _activeFilter,
            totalCount:      _totalCount,
            unclaimedCount:  _unclaimedCount,
            claimedCount:    _claimedCount,
            onQueryChanged:  (q) => setState(() => _searchQuery = q),
            onFilterChanged: (f) => setState(() => _activeFilter = f),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _kAmber, strokeWidth: 2),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: _kRed, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: _kTextSub, fontSize: 14)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _loadRunners,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kAmber,
                side: BorderSide(color: _kAmber.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
    }

    final filtered = _filteredRunners;
    final showWalkin = _activeFilter != _FilterTab.claimed;

    // All-claimed / no-results empty state
    if (filtered.isEmpty) {
      final icon = (_activeFilter != _FilterTab.claimed && _searchQuery.isEmpty)
          ? Icons.check_circle_rounded
          : Icons.search_off_rounded;
      final iconColor = (_activeFilter != _FilterTab.claimed && _searchQuery.isEmpty)
          ? _kGreen
          : _kTextMuted;
      final message = _searchQuery.isNotEmpty
          ? 'No results for "$_searchQuery"'
          : _activeFilter == _FilterTab.claimed
              ? 'No kits have been claimed yet.'
              : 'All kits have been claimed!';

      if (!showWalkin) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 44),
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(color: _kTextSub, fontSize: 14)),
            ],
          ),
        );
      }

      // showWalkin=true but list is empty — still render walk-in section
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: 44),
                  const SizedBox(height: 12),
                  Text(message, style: const TextStyle(color: _kTextSub, fontSize: 14)),
                ],
              ),
            ),
          ),
          _WalkInSection(available: _walkinAvailable, onAssign: _showWalkInDialog),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      itemCount: filtered.length + (showWalkin ? 1 : 0),
      itemBuilder: (context, i) {
        if (showWalkin && i == filtered.length) {
          return _WalkInSection(available: _walkinAvailable, onAssign: _showWalkInDialog);
        }
        final r = filtered[i];
        return _RunnerRow(
          isClaimed: _isClaimed(r),
          bibNumber: _bibNumber(r),
          name:      _runnerName(r),
          shirtSize: _shirtSize(r),
          contact:   _contactNumber(r),
          onClaim:   () => _claimKit(r),
        );
      },
    );
  }
}

// ── Dashboard top bar ─────────────────────────────────────────────────────────

class _KitDashboardTopBar extends StatelessWidget {
  final String raceName;

  static const _kSurface = Color(0xFF0D0D18);
  static const _kBorder  = Color(0xFF1E1E32);
  static const _kTextPri = Colors.white;
  static const _kTextSub = Color(0xFF8888AA);

  const _KitDashboardTopBar({required this.raceName});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBorder),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: _kTextSub, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            raceName,
            style: const TextStyle(
              color: _kTextPri,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          const Text(
            'Kit Distribution Dashboard',
            style: TextStyle(color: _kTextSub, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final int total;
  final int claimed;
  final int unclaimed;
  final int walkin;

  static const _kSurface = Color(0xFF0D0D18);
  static const _kBorder  = Color(0xFF1E1E32);
  static const _kGreen   = Color(0xFF00FF9C);
  static const _kBlue    = Color(0xFF00B4FF);
  static const _kAmber   = Color(0xFFFFB800);
  static const _kPurple  = Color(0xFF8B5CF6);
  static const _kTextSub = Color(0xFF8888AA);

  const _SummaryBar({
    required this.total,
    required this.claimed,
    required this.unclaimed,
    required this.walkin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          _StatChip(label: 'Registered', value: total.toString(),    color: _kBlue),
          const SizedBox(width: 10),
          _StatChip(label: 'Claimed',    value: claimed.toString(),  color: _kGreen),
          const SizedBox(width: 10),
          _StatChip(
            label: 'Unclaimed',
            value: unclaimed.toString(),
            color: unclaimed > 0 ? _kAmber : _kGreen,
          ),
          const SizedBox(width: 10),
          _StatChip(label: 'Walk-in Available', value: walkin.toString(), color: _kPurple),
          const Spacer(),
          if (total > 0)
            Text(
              '${(claimed / total * 100).toStringAsFixed(0)}% claimed',
              style: const TextStyle(color: _kTextSub, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Search + filter bar ───────────────────────────────────────────────────────

class _SearchAndFilter extends StatelessWidget {
  final String query;
  final _FilterTab activeFilter;
  final int totalCount;
  final int unclaimedCount;
  final int claimedCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_FilterTab> onFilterChanged;

  static const _kSurface = Color(0xFF0D0D18);
  static const _kBg      = Color(0xFF080810);
  static const _kBorder  = Color(0xFF1E1E32);
  static const _kGreen   = Color(0xFF00FF9C);
  static const _kAmber   = Color(0xFFFFB800);
  static const _kTextSub = Color(0xFF8888AA);

  const _SearchAndFilter({
    required this.query,
    required this.activeFilter,
    required this.totalCount,
    required this.unclaimedCount,
    required this.claimedCount,
    required this.onQueryChanged,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      decoration: const BoxDecoration(
        color: _kSurface,
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field
          SizedBox(
            height: 40,
            child: TextField(
              onChanged: onQueryChanged,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search by runner name or bib number…',
                hintStyle: TextStyle(color: _kTextSub.withOpacity(0.6), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: _kTextSub, size: 18),
                filled: true,
                fillColor: _kBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                  borderSide: BorderSide(color: _kAmber.withOpacity(0.5), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Filter tabs
          Row(
            children: [
              _FilterChip(
                label:  'All',
                count:  totalCount,
                active: activeFilter == _FilterTab.all,
                color:  _kTextSub,
                onTap:  () => onFilterChanged(_FilterTab.all),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label:  'Unclaimed',
                count:  unclaimedCount,
                active: activeFilter == _FilterTab.unclaimed,
                color:  _kAmber,
                onTap:  () => onFilterChanged(_FilterTab.unclaimed),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label:  'Claimed',
                count:  claimedCount,
                active: activeFilter == _FilterTab.claimed,
                color:  _kGreen,
                onTap:  () => onFilterChanged(_FilterTab.claimed),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  static const _kBorder = Color(0xFF1E1E32);
  static const _kTextSub = Color(0xFF8888AA);

  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color.withOpacity(0.4) : _kBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color:      active ? color : _kTextSub,
                fontSize:   12,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color:        active ? color.withOpacity(0.2) : _kBorder,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  color:      active ? color : _kTextSub,
                  fontSize:   10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Runner row ────────────────────────────────────────────────────────────────

class _RunnerRow extends StatefulWidget {
  final bool isClaimed;
  final String bibNumber;
  final String name;
  final String shirtSize;
  final String contact;
  final VoidCallback onClaim;

  const _RunnerRow({
    required this.isClaimed,
    required this.bibNumber,
    required this.name,
    required this.shirtSize,
    required this.contact,
    required this.onClaim,
  });

  @override
  State<_RunnerRow> createState() => _RunnerRowState();
}

class _RunnerRowState extends State<_RunnerRow> {
  bool _hovered = false;

  static const _kSurface     = Color(0xFF0D0D18);
  static const _kSurfaceHigh = Color(0xFF141422);
  static const _kBorder      = Color(0xFF1E1E32);
  static const _kGreen       = Color(0xFF00FF9C);
  static const _kAmber       = Color(0xFFFFB800);
  static const _kTextPri     = Colors.white;
  static const _kTextSub     = Color(0xFF8888AA);

  // Distinct colour per shirt size for instant visual scanning
  static Color _sizeColor(String size) {
    switch (size) {
      case 'XS':              return const Color(0xFF8B5CF6); // purple
      case 'S':               return const Color(0xFF00B4FF); // blue
      case 'M':               return const Color(0xFF00FF9C); // green
      case 'L':               return const Color(0xFFFFB800); // amber
      case 'XL':              return const Color(0xFFFF8C00); // orange
      case 'XXL': case '2XL': return const Color(0xFFFF4D4D); // red
      default:                return const Color(0xFF8888AA); // grey
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeColor = _sizeColor(widget.shirtSize);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: _hovered ? _kSurfaceHigh : _kSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered ? _kAmber.withOpacity(0.2) : _kBorder,
          ),
        ),
        child: Row(
          children: [
            // ── Bib number ──────────────────────────────────────────────
            SizedBox(
              width: 58,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF141422),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF1E1E32)),
                ),
                child: Text(
                  widget.bibNumber,
                  style: const TextStyle(
                    color:       _kTextPri,
                    fontSize:    13,
                    fontWeight:  FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // ── Runner name ──────────────────────────────────────────────
            Expanded(
              flex: 3,
              child: Text(
                widget.name,
                style: const TextStyle(
                  color: _kTextPri, fontSize: 13, fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),

            // ── Shirt size badge ─────────────────────────────────────────
            SizedBox(
              width: 52,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: sizeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: sizeColor.withOpacity(0.3)),
                ),
                child: Text(
                  widget.shirtSize,
                  style: TextStyle(
                    color: sizeColor, fontSize: 11, fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Contact ──────────────────────────────────────────────────
            SizedBox(
              width: 130,
              child: Text(
                widget.contact,
                style: const TextStyle(color: _kTextSub, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),

            // ── Status badge ─────────────────────────────────────────────
            SizedBox(
              width: 106,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.isClaimed
                      ? _kGreen.withOpacity(0.1)
                      : _kAmber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isClaimed
                        ? _kGreen.withOpacity(0.3)
                        : _kAmber.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isClaimed
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: widget.isClaimed ? _kGreen : _kAmber,
                      size: 11,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.isClaimed ? 'CLAIMED' : 'UNCLAIMED',
                      style: TextStyle(
                        color:      widget.isClaimed ? _kGreen : _kAmber,
                        fontSize:   9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Mark as Claimed button (hidden once claimed) ──────────────
            SizedBox(
              width: 126,
              child: widget.isClaimed
                  ? const SizedBox.shrink()
                  : SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: widget.onClaim,
                        icon: const Icon(Icons.check_rounded, size: 13),
                        label: const Text(
                          'Mark Claimed',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAmber.withOpacity(0.12),
                          foregroundColor: _kAmber,
                          elevation: 0,
                          side: BorderSide(color: _kAmber.withOpacity(0.4)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Walk-in section ───────────────────────────────────────────────────────────

class _WalkInSection extends StatelessWidget {
  final int available;
  final VoidCallback onAssign;

  static const _kBorder   = Color(0xFF1E1E32);
  static const _kPurple   = Color(0xFF8B5CF6);
  static const _kTextMuted= Color(0xFF3A3A55);

  const _WalkInSection({required this.available, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Section divider with label
          Row(
            children: [
              Expanded(child: Container(height: 1, color: _kBorder)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _kPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kPurple.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_add_rounded, color: _kPurple, size: 13),
                    const SizedBox(width: 6),
                    Text(
                      'Walk-in Pool — $available bibs available',
                      style: const TextStyle(
                        color: _kPurple, fontSize: 11, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 1, color: _kBorder)),
            ],
          ),
          const SizedBox(height: 16),
          // Assign button
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: available > 0 ? onAssign : null,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text(
                'Assign Walk-in Bib',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple.withOpacity(0.15),
                foregroundColor: _kPurple,
                disabledBackgroundColor: const Color(0xFF141422),
                disabledForegroundColor: _kTextMuted,
                elevation: 0,
                side: BorderSide(
                  color: available > 0 ? _kPurple.withOpacity(0.4) : _kBorder,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),
          if (available == 0) ...[
            const SizedBox(height: 8),
            Text(
              'No walk-in bibs configured for this race.',
              style: TextStyle(color: _kTextMuted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ── Walk-in dialog ────────────────────────────────────────────────────────────

class _WalkInDialog extends StatefulWidget {
  // onSubmit fires the API. Throws on failure. Closes dialog itself on success.
  final Future<void> Function(String name, String contact) onSubmit;

  const _WalkInDialog({required this.onSubmit});

  @override
  State<_WalkInDialog> createState() => _WalkInDialogState();
}

class _WalkInDialogState extends State<_WalkInDialog> {
  final _nameCtrl    = TextEditingController();
  final _contactCtrl = TextEditingController();
  String? _error;
  bool _submitting = false;

  static const _kSurface = Color(0xFF0D0D18);
  static const _kBg      = Color(0xFF080810);
  static const _kBorder  = Color(0xFF1E1E32);
  static const _kPurple  = Color(0xFF8B5CF6);
  static const _kTextPri = Colors.white;
  static const _kTextSub = Color(0xFF8888AA);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name    = _nameCtrl.text.trim();
    final contact = _contactCtrl.text.trim();

    if (name.isEmpty || contact.isEmpty) {
      setState(() => _error = 'Name and contact number are required.');
      return;
    }

    setState(() { _submitting = true; _error = null; });

    try {
      await widget.onSubmit(name, contact);
      if (mounted) Navigator.pop(context); // success — close
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _error = 'Assignment failed. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _kBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _kPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kPurple.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.person_add_rounded, color: _kPurple, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Assign Walk-in Bib',
                        style: TextStyle(
                            color: _kTextPri, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Enter walk-in runner details',
                        style: TextStyle(color: _kTextSub, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Name field
              const Text(
                'Runner Name',
                style: TextStyle(color: _kTextSub, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              _field(
                controller: _nameCtrl,
                hint: 'e.g. Juan dela Cruz',
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: 14),

              // Contact field
              const Text(
                'Contact Number',
                style: TextStyle(color: _kTextSub, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              _field(
                controller:   _contactCtrl,
                hint:         'e.g. +63 912 345 6789',
                icon:         Icons.phone_rounded,
                keyboardType: TextInputType.phone,
              ),

              // Error
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4D4D).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF4D4D).withOpacity(0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context),
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
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Assign Bib',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller:   controller,
      keyboardType: keyboardType,
      onSubmitted:  (_) => _submit(),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText:   hint,
        hintStyle:  TextStyle(color: _kTextSub.withOpacity(0.6), fontSize: 13),
        prefixIcon: Icon(icon, color: _kTextSub, size: 16),
        filled:     true,
        fillColor:  _kBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          borderSide: BorderSide(color: _kPurple.withOpacity(0.5), width: 1.5),
        ),
      ),
    );
  }
}
