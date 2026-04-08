import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class RacesScreen extends StatefulWidget {
  /// Called when the organizer taps a race card to switch the active race.
  final void Function(int id, String name, String status)? onRaceSelected;

  const RacesScreen({super.key, this.onRaceSelected});

  @override
  State<RacesScreen> createState() => _RacesScreenState();
}

class _RacesScreenState extends State<RacesScreen> {
  List<Map<String, dynamic>> _races = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final races = await ApiService.getRaces();
      setState(() {
        _races = races;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _startRace(int raceId, String raceName) async {
    final confirmed = await _confirm(
      'Start "$raceName"?',
      'Runners will be able to join and track their position.',
      confirmText: 'Start Race',
      confirmColor: const Color(0xFF00FF9C),
    );
    if (!confirmed) return;

    try {
      await ApiService.startRace(raceId);
      _showSnack('Race started!', isError: false);
      _load();
    } catch (e) {
      _showSnack('Failed to start race: $e', isError: true);
    }
  }

  Future<void> _stopRace(int raceId, String raceName) async {
    final confirmed = await _confirm(
      'Stop "$raceName"?',
      'This will end the race. This action cannot be undone.',
      confirmText: 'Stop Race',
      confirmColor: const Color(0xFFFF4D4D),
    );
    if (!confirmed) return;

    try {
      await ApiService.stopRace(raceId);
      _showSnack('Race stopped.', isError: false);
      _load();
    } catch (e) {
      _showSnack('Failed to stop race: $e', isError: true);
    }
  }

  Future<bool> _confirm(
    String title,
    String message, {
    required String confirmText,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D0D14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white38,
                        side: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        confirmText,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold),
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
    return result ?? false;
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? const Color(0xFFFF4D4D) : const Color(0xFF00FF9C),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return const Color(0xFF00FF9C);
      case 'finished':
        return const Color(0xFFFF4D4D);
      default:
        return const Color(0xFFFFB800);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Races',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: const Color(0xFF00FF9C),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00FF9C),
                strokeWidth: 2,
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Color(0xFFFF4D4D), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white38),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Try again',
                            style: TextStyle(color: Color(0xFF00FF9C))),
                      ),
                    ],
                  ),
                )
              : _races.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.flag_outlined,
                              size: 64,
                              color: Colors.white.withOpacity(0.1)),
                          const SizedBox(height: 16),
                          Text(
                            'No races found',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF00FF9C),
                      backgroundColor: const Color(0xFF0D0D14),
                      onRefresh: _load,
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _races.length,
                        itemBuilder: (context, index) {
                          final race = _races[index];
                          final raceId = race['id'] as int;
                          final name =
                              race['name']?.toString() ?? 'Race #$raceId';
                          final status =
                              race['status']?.toString() ?? 'upcoming';
                          final distance = race['distance_km'];
                          final statusColor = _statusColor(status);

                          return GestureDetector(
                            onTap: widget.onRaceSelected != null
                                ? () => widget.onRaceSelected!(
                                      raceId,
                                      name,
                                      status,
                                    )
                                : null,
                            child: Container(
                              margin:
                                  const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.07),
                                ),
                              ),
                              child: Column(
                                children: [
                                  // Race info header
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: statusColor
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: statusColor
                                                  .withOpacity(0.3),
                                            ),
                                          ),
                                          child: Icon(
                                            status == 'active'
                                                ? Icons
                                                    .play_circle_outline_rounded
                                                : status == 'finished'
                                                    ? Icons.flag_rounded
                                                    : Icons.schedule_rounded,
                                            color: statusColor,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight:
                                                      FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  if (distance != null) ...[
                                                    Text(
                                                      '${(distance as num).toStringAsFixed(1)} km',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(
                                                                0.4),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                    Text(
                                                      '  ·  ',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withOpacity(
                                                                0.2),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(6),
                                                    ),
                                                    child: Text(
                                                      status.toUpperCase(),
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        letterSpacing: 0.8,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Tap-to-select indicator
                                        if (widget.onRaceSelected != null)
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: Colors.white
                                                .withOpacity(0.2),
                                            size: 14,
                                          ),
                                      ],
                                    ),
                                  ),

                                  // Action buttons
                                  if (status != 'finished')
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 0, 12, 12),
                                      child: Row(
                                        children: [
                                          if (status == 'upcoming')
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: () =>
                                                    _startRace(raceId, name),
                                                icon: const Icon(
                                                  Icons.play_arrow_rounded,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                    'Start Race'),
                                                style:
                                                    ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFF00FF9C),
                                                  foregroundColor:
                                                      Colors.black,
                                                  shape:
                                                      RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  textStyle: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (status == 'active') ...[
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () =>
                                                    _stopRace(raceId, name),
                                                icon: const Icon(
                                                  Icons.stop_rounded,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                    'Stop Race'),
                                                style:
                                                    OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      const Color(0xFFFF4D4D),
                                                  side: const BorderSide(
                                                    color: Color(0xFFFF4D4D),
                                                  ),
                                                  shape:
                                                      RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}