import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  final int raceId;

  const LeaderboardScreen({super.key, required this.raceId});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<Map<String, dynamic>> _leaderboard = [];
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
      final data = await ApiService.getLeaderboard(widget.raceId);
      setState(() {
        _leaderboard = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Color _rankColor(int index) {
    if (index == 0) return const Color(0xFFFFD700); // gold
    if (index == 1) return const Color(0xFFC0C0C0); // silver
    if (index == 2) return const Color(0xFFCD7F32); // bronze
    return Colors.white.withOpacity(0.4);
  }

  String _speedDisplay(dynamic speed) {
    final s = (speed as num?)?.toDouble() ?? 0.0;
    return (s * 3.6).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leaderboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Race ${widget.raceId} · Live rankings',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
              ),
            ),
          ],
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
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFFF4D4D),
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white38),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _load,
                        child: const Text(
                          'Try again',
                          style: TextStyle(color: Color(0xFF00FF9C)),
                        ),
                      ),
                    ],
                  ),
                )
              : _leaderboard.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.leaderboard_rounded,
                            size: 64,
                            color: Colors.white.withOpacity(0.1),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No runners yet',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Rankings appear once runners are active',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.2),
                              fontSize: 12,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _leaderboard.length,
                        itemBuilder: (context, index) {
                          final entry = _leaderboard[index];
                          final rankColor = _rankColor(index);
                          final isTop3 = index < 3;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: isTop3
                                  ? rankColor.withOpacity(0.05)
                                  : Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isTop3
                                    ? rankColor.withOpacity(0.25)
                                    : Colors.white.withOpacity(0.07),
                              ),
                            ),
                            child: Row(
                              children: [
                                // Rank badge
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: rankColor.withOpacity(
                                      isTop3 ? 0.15 : 0.08,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: rankColor.withOpacity(
                                        isTop3 ? 0.5 : 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: rankColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Runner info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry['runner_id']?.toString() ??
                                            'Unknown runner',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.85),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (entry['lat'] != null &&
                                          entry['lng'] != null)
                                        Text(
                                          '${(entry['lat'] as num).toStringAsFixed(4)}, '
                                          '${(entry['lng'] as num).toStringAsFixed(4)}',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.25),
                                            fontSize: 10,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // Speed
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _speedDisplay(entry['speed']),
                                          style: TextStyle(
                                            color: isTop3
                                                ? rankColor
                                                : const Color(0xFF00FF9C),
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 3),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            'km/h',
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.3),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (entry['timestamp'] != null)
                                      Text(
                                        _formatTimestamp(entry['timestamp']),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.2),
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    } catch (_) {
      return ts.toString();
    }
  }
}