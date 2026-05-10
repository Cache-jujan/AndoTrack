"""
tests/test_segmentation_and_tracker.py
======================================

Tests for:
  1. utils.distance_tracker — in-memory GPS tracking
  2. utils.segmentation     — assign_segments() + compute_analytics()
  3. finish_race fallback   — when _tracker is empty at finish time
  4. _calculate_rank fix    — removed broken distance_store import

Run from andotrack_api/ root:

    python -m pytest tests/test_segmentation_and_tracker.py -v
"""

import math

from utils.distance_tracker import (
    record_position,
    get_distance_metres,
    get_distance_km,
    get_distance_summary,
    get_all_runners_distance,
    reset_runner,
    reset_race,
    get_last_position,
    get_distance,
)

from utils.segmentation import (
    assign_segments,
    compute_analytics,
)


def _reset(*pairs):
    for race_id, runner_id in pairs:
        reset_runner(race_id, str(runner_id))


# ═════════════════════════════════════════════════════════════════════════════
# Section 1 — distance_tracker
# ═════════════════════════════════════════════════════════════════════════════

def test_tracker_first_ping_returns_zero():
    _reset((100, "a"))
    assert record_position(100, "a", 10.3157, 123.8854) == 0.0


def test_tracker_first_ping_records_zero_distance():
    _reset((100, "b"))
    record_position(100, "b", 10.3157, 123.8854)
    assert get_distance_metres(100, "b") == 0.0


def test_tracker_known_distance_accumulates():
    """0.001° lat ≈ 111 m."""
    _reset((100, "c"))
    record_position(100, "c", 10.3157, 123.8854)
    record_position(100, "c", 10.3167, 123.8854)

    dist = get_distance_metres(100, "c")
    assert 100 < dist < 120, f"Expected ~111 m, got {dist}"


def test_tracker_multiple_pings_accumulate():
    _reset((100, "d"))

    record_position(100, "d", 10.3157, 123.8854)
    record_position(100, "d", 10.3167, 123.8854)
    record_position(100, "d", 10.3177, 123.8854)

    dist = get_distance_metres(100, "d")
    assert 200 < dist < 240, f"Expected ~222 m, got {dist}"


def test_tracker_jitter_ignored():
    _reset((100, "e"))

    record_position(100, "e", 10.3157000, 123.8854000)
    before = get_distance_metres(100, "e")

    # ~0.1m jitter
    record_position(100, "e", 10.3157001, 123.8854001)

    assert before == get_distance_metres(
        100,
        "e",
    ), "Sub-metre jitter must not inflate total"


def test_tracker_runners_isolated():
    _reset((200, "r1"), (200, "r2"))

    record_position(200, "r1", 10.3157, 123.8854)
    record_position(200, "r1", 10.3167, 123.8854)

    record_position(200, "r2", 10.3157, 123.8854)

    assert get_distance_metres(200, "r1") > 100
    assert get_distance_metres(200, "r2") == 0.0


def test_tracker_races_isolated():
    _reset((10, "runner"), (20, "runner"))

    record_position(10, "runner", 10.3157, 123.8854)
    record_position(10, "runner", 10.3167, 123.8854)

    record_position(20, "runner", 10.3157, 123.8854)

    assert get_distance_metres(10, "runner") > 100
    assert get_distance_metres(20, "runner") == 0.0


def test_tracker_get_distance_km():
    _reset((300, "km"))

    record_position(300, "km", 10.3157, 123.8854)
    record_position(300, "km", 10.3167, 123.8854)

    metres = get_distance_metres(300, "km")

    assert abs(get_distance_km(300, "km") - metres / 1000) < 0.001


def test_tracker_missing_key_returns_zero():
    reset_runner(999, "ghost")

    assert get_distance_metres(999, "ghost") == 0.0
    assert get_distance_km(999, "ghost") == 0.0


def test_tracker_summary_structure():
    _reset((400, "s"))

    record_position(400, "s", 10.3157, 123.8854)
    record_position(400, "s", 10.3167, 123.8854)

    summary = get_distance_summary(400, "s")

    for key in (
        "race_id",
        "runner_id",
        "distance_metres",
        "distance_km",
        "distance_formatted",
        "gps_points_recorded",
    ):
        assert key in summary

    assert summary["gps_points_recorded"] == 2
    assert summary["distance_metres"] > 0


def test_tracker_get_all_runners_sorted():
    _reset((500, "fast"), (500, "slow"))

    record_position(500, "fast", 10.3157, 123.8854)
    record_position(500, "fast", 10.3177, 123.8854)

    record_position(500, "slow", 10.3157, 123.8854)
    record_position(500, "slow", 10.3162, 123.8854)

    results = get_all_runners_distance(500)

    assert len(results) == 2
    assert results[0]["distance_metres"] >= results[1]["distance_metres"]


def test_tracker_reset_runner():
    _reset((600, "del"))

    record_position(600, "del", 10.3157, 123.8854)
    record_position(600, "del", 10.3167, 123.8854)

    assert get_distance_metres(600, "del") > 0

    reset_runner(600, "del")

    assert get_distance_metres(600, "del") == 0.0


def test_tracker_reset_race():
    _reset((700, "r1"), (700, "r2"))

    record_position(700, "r1", 10.3157, 123.8854)
    record_position(700, "r1", 10.3167, 123.8854)

    record_position(700, "r2", 10.3157, 123.8854)
    record_position(700, "r2", 10.3167, 123.8854)

    reset_race(700)

    assert get_distance_metres(700, "r1") == 0.0
    assert get_distance_metres(700, "r2") == 0.0


def test_tracker_last_position():
    _reset((800, "pos"))

    record_position(800, "pos", 10.3157, 123.8854)
    assert get_last_position(800, "pos") == (10.3157, 123.8854)

    record_position(800, "pos", 10.3167, 123.8854)
    assert get_last_position(800, "pos") == (10.3167, 123.8854)


def test_tracker_get_distance_helper_none_before_first_ping():
    _reset((900, 42))

    assert get_distance(900, 42) is None


def test_tracker_get_distance_helper_returns_metres():
    _reset((900, 42))

    record_position(900, "42", 10.3157, 123.8854)
    record_position(900, "42", 10.3167, 123.8854)

    assert get_distance(900, 42) > 100


def test_tracker_empty_race_returns_empty_list():
    assert get_all_runners_distance(99999) == []