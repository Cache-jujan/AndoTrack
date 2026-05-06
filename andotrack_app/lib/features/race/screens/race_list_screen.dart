// MOVED TO: lib/features/race/screens/race_list_screen.dart

import 'package:flutter/material.dart';
import 'package:andotrack_app/core/services/api_service.dart';
import 'package:andotrack_app/features/race/screens/race_detail_screen.dart';

class RaceListScreen extends StatefulWidget {
  const RaceListScreen({super.key});

  @override
  State<RaceListScreen> createState() => _RaceListScreenState();
}

class _RaceListScreenState extends State<RaceListScreen> {
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _ongoing = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRaces();
  }

  Future<void> _loadRaces() async {
    setState(() { _loading = true; _error = null; });
    try {
      final races = await ApiService.getRaces();
      setState(() {
        _upcoming = races.where((r) =>
          r['status'] == 'upcoming' ||
          r['status'] == 'registration_open' ||
          r['status'] == 'race_day'
        ).toList();
        _ongoing = races.where((r) => r['status'] == 'active').toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Failed to load races: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        title: const Text('Races', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadRaces,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : RefreshIndicator(
                  onRefresh: _loadRaces,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_ongoing.isNotEmpty) ...[
                        _SectionHeader(title: '🟢 Ongoing', count: _ongoing.length),
                        const SizedBox(height: 8),
                        ..._ongoing.map((r) => _RaceCard(race: r, onTap: () => _openDetail(r))),
                        const SizedBox(height: 20),
                      ],
                      if (_upcoming.isNotEmpty) ...[
                        _SectionHeader(title: '📅 Upcoming', count: _upcoming.length),
                        const SizedBox(height: 8),
                        ..._upcoming.map((r) => _RaceCard(race: r, onTap: () => _openDetail(r))),
                      ],
                      if (_ongoing.isEmpty && _upcoming.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: Text('No races available.',
                                style: TextStyle(color: Colors.white38)),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  void _openDetail(Map<String, dynamic> race) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RaceDetailScreen(race: race)),
    ).then((_) => _loadRaces()); // refresh on return
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E30),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
      ],
    );
  }
}

class _RaceCard extends StatelessWidget {
  final Map<String, dynamic> race;
  final VoidCallback onTap;
  const _RaceCard({required this.race, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = race['status'] ?? 'upcoming';
    final isActive = status == 'active';
    final name = race['name'] ?? 'Unnamed Race';
    final location = race['location'] ?? '';
    final distance = race['distance_km'];
    final slots = race['slots_remaining'];
    final fee = race['registration_fee'] ?? 0;
    final scheduled = race['scheduled_start'];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? const Color(0xFF00FF9C).withOpacity(0.4)
                : const Color(0xFF1E1E30),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                  ),
                  _StatusBadge(status: status),
                ],
              ),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.location_on, size: 12, color: Colors.white38),
                  const SizedBox(width: 4),
                  Text(location,
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (distance != null)
                    _InfoChip(label: '${distance}km'),
                  if (fee > 0)
                    _InfoChip(label: '₱${fee.toStringAsFixed(0)}'),
                  if (slots != null)
                    _InfoChip(
                      label: '$slots slots left',
                      color: slots < 10
                          ? const Color(0xFFFF4D4D)
                          : const Color(0xFF444460),
                    ),
                  if (scheduled != null)
                    _InfoChip(label: _formatDate(scheduled)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'active':
        color = const Color(0xFF00FF9C);
        label = 'Live';
        break;
      case 'registration_open':
        color = const Color(0xFF00B4FF);
        label = 'Open';
        break;
      case 'race_day':
        color = const Color(0xFFFFB800);
        label = 'Race Day';
        break;
      case 'finished':
        color = const Color(0xFF444460);
        label = 'Finished';
        break;
      default:
        color = const Color(0xFF444460);
        label = 'Upcoming';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoChip(
      {required this.label, this.color = const Color(0xFF444460)});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 11)),
    );
  }
}
