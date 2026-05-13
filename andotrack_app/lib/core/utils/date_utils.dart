// lib/core/utils/date_utils.dart
//
// Centralised PHT-safe datetime parsing helpers.
//
// ROOT CAUSE — Pydantic v2 UTC suffix problem:
//   The FastAPI backend stores user-input timestamps (scheduled_start,
//   check_in_opens_at, etc.) as naive Python datetime objects in the
//   database — they are PHT in intent but have no tzinfo attached.
//   Pydantic v2 treats naive datetimes as UTC and appends "+00:00" when
//   serialising to JSON, e.g.:
//
//     stored in DB:  2025-05-09 05:00:00  (naive, intended as PHT 5 AM)
//     sent to client: "2025-05-09T05:00:00+00:00"  (tagged as UTC 5 AM)
//
//   Flutter's DateTime.parse() honours the "+00:00" suffix and stores the
//   value as a UTC instant. A subsequent .toLocal() call then converts
//   UTC 5 AM → PHT 1 PM (+8 hours), producing a full 8-hour forward shift
//   in every display widget and countdown that touches scheduled_start.
//
// THE FIX:
//   Strip any timezone suffix before parsing. Dart then creates a local
//   DateTime whose .hour/.minute/.day fields are the literal PHT values the
//   race director originally entered — no further conversion needed.
//
// WHICH FIELDS TO USE THIS FOR:
//   ✓ scheduled_start    — user-input PHT race start time
//   ✓ check_in_opens_at  — user-configured PHT check-in window
//   ✗ checked_in_at      — backend-computed, genuinely UTC → use .toLocal()
//   ✗ claimed_at         — backend-computed, genuinely UTC → use .toLocal()
//   ✗ created_at         — backend-computed, genuinely UTC → use .toLocal()

import 'package:flutter/foundation.dart';

/// Parses a timestamp that was stored as a naive PHT datetime but may arrive
/// from the API with a spurious UTC suffix appended by Pydantic v2
/// (e.g. "+00:00" or "Z").
///
/// Strips any trailing "+HH:MM", "-HH:MM", "Z", or "z" before calling
/// [DateTime.parse], so Dart treats the literal time value as local PHT
/// rather than converting it from UTC and adding 8 hours.
///
/// **Do NOT use this for backend-computed UTC fields** (checked_in_at,
/// claimed_at, created_at). Those are genuine UTC values; call
/// `DateTime.parse(raw).toLocal()` on them instead.
DateTime parsePht(String raw) {
  // Strip offset suffix (+HH:MM or -HH:MM) by splitting on '+' or '-'
  // that appears after the time portion, then remove any trailing Z/z.
  final clean = raw.split('+').first.replaceAll(RegExp(r'[Zz]$'), '');
  return DateTime.parse(clean);
}

/// Returns true if [raw] contains an explicit timezone designator
/// ("Z", "z", or a numeric offset such as "+08:00" or "-05:00").
///
/// Use this to branch between [parsePht] (no suffix → naive PHT) and
/// `DateTime.parse(raw).toLocal()` (has suffix → genuine UTC conversion).
bool hasTimezoneSuffix(String raw) {
  return raw.endsWith('Z') ||
      raw.endsWith('z') ||
      RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
}

/// Formats a user-input PHT timestamp as a short date string
/// (e.g. "May 9, 2025").
///
/// Applies [parsePht] internally so the calendar date extracted is the
/// PHT date, not the UTC date (which can differ by one day for events
/// scheduled near PHT midnight, i.e. UTC 4 PM the previous day).
///
/// Returns [fallback] if [raw] is null; returns [raw] as-is if parsing fails.
String formatDatePht(String? raw, {String fallback = 'TBA'}) {
  if (raw == null) return fallback;
  try {
    final dt = parsePht(raw);
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}';
  } catch (e) {
    debugPrint('[date_utils] formatDatePht: failed to parse "$raw": $e');
    return raw;
  }
}
