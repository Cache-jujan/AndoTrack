import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'runner_map_screen.dart';

class RaceJoinScreen extends StatefulWidget {
  const RaceJoinScreen({super.key});

  @override
  State<RaceJoinScreen> createState() => _RaceJoinScreenState();
}

class _RaceJoinScreenState extends State<RaceJoinScreen> {
  List<dynamic> _races = [];
  bool _loading = true;
  String? _error;
  int? _joiningRaceId;

  @override
  void initState() {
    super.initState();
    _loadRaces();
  }

  Future<void> _loadRaces() async {
    try {
      final races = await ApiService.getRaces();
      setState(() {
        _races = races;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load races: $e';
        _loading = false;
      });
    }
  }

  Future<void> _joinRace(Map<String, dynamic> race) async {
    final raceId = race['id'] as int;
    setState(() => _joiningRaceId = raceId);

    try {
      // Save the selected race so RunnerMapScreen can read it
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('active_race_id', raceId);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RunnerMapScreen()),
      );
    } catch (e) {
      setState(() => _joiningRaceId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to join race: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        title: const Text('Available Races',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)))
              : _races.isEmpty
                  ? const Center(
                      child: Text('No races available right now.',
                          style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _races.length,
                      itemBuilder: (context, index) {
                        final race = _races[index];
                        final raceId = race['id'] as int;
                        final isJoining = _joiningRaceId == raceId;
                        final status = race['status'] ?? 'unknown';
                        final isActive = status == 'active' || status == 'upcoming';

                        return Container(
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
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            title: Text(
                              race['name'] ?? 'Unnamed Race',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Status: $status',
                              style: TextStyle(
                                color: isActive
                                    ? const Color(0xFF00FF9C)
                                    : Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            trailing: isJoining
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isActive
                                          ? const Color(0xFF00FF9C)
                                          : const Color(0xFF1E1E30),
                                      foregroundColor: isActive
                                          ? Colors.black
                                          : Colors.white38,
                                    ),
                                    onPressed: isActive
                                        ? () => _joinRace(race)
                                        : null,
                                    child: const Text('Join'),
                                  ),
                          ),
                        );
                      },
                    ),
    );
  }
}