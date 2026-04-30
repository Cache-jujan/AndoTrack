import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';
import '../models/runner_model.dart';

// Single shared instance of FirebaseService
final firebaseServiceProvider = Provider<FirebaseService>(
  (ref) => FirebaseService(),
);

// Stream provider — pass raceId as argument, auto-cancels on dispose
final raceRunnersProvider =
    StreamProvider.family<List<RunnerModel>, String>((ref, raceId) {
  final firebase = ref.watch(firebaseServiceProvider);

  // Wraps your existing watchRaceRunners() — no duplicate Firebase logic
  return firebase.watchRaceRunners(raceId).map((event) {
    final data = event.snapshot.value as Map<dynamic, dynamic>?;
    if (data == null) return [];

    return data.entries.map((entry) {
      return RunnerModel.fromMap(
        entry.key.toString(),
        entry.value as Map<dynamic, dynamic>,
      );
    }).toList();
  });
});