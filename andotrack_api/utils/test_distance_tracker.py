"""
Unit tests for andotrack_api/utils/distance_tracker.py
Run with:  python utils/test_distance_tracker.py
       or: python -m pytest utils/test_distance_tracker.py -v
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from utils.distance_tracker import (
    record_position,
    get_distance_metres,
    get_distance_km,
    get_distance_summary,
    get_all_runners_distance,
    reset_runner,
    reset_race,
    _tracker,
)


# ── Helper ────────────────────────────────────────────────

def reset(*args):
    """reset_runner for each (race_id, runner_id) pair passed as tuples."""
    for race_id, runner_id in args:
        reset_runner(race_id, str(runner_id))


# ── Tests ─────────────────────────────────────────────────

def test_first_ping_returns_zero_delta():
    reset((1, "a"))
    delta = record_position(1, "a", 10.3157, 123.8854)
    assert delta == 0.0, f"First ping should return 0.0, got {delta}"


def test_first_ping_records_zero_distance():
    reset((1, "b"))
    record_position(1, "b", 10.3157, 123.8854)
    assert get_distance_metres(1, "b") == 0.0


def test_known_distance_accumulates():
    """
    Move ~111 m north (0.001° latitude ≈ 111 m).
    Haversine should give us a value between 100 m and 120 m.
    """
    reset((1, "c"))
    record_position(1, "c", 10.3157, 123.8854)
    record_position(1, "c", 10.3167, 123.8854)
    dist = get_distance_metres(1, "c")
    assert 100 < dist < 120, f"Expected ~111 m, got {dist}"


def test_multiple_points_accumulate():
    """
    Three pings each ~111 m apart should give ~222 m total.
    """
    reset((1, "d"))
    record_position(1, "d", 10.3157, 123.8854)
    record_position(1, "d", 10.3167, 123.8854)
    record_position(1, "d", 10.3177, 123.8854)
    dist = get_distance_metres(1, "d")
    assert 200 < dist < 240, f"Expected ~222 m, got {dist}"


def test_jitter_ignored():
    """
    A second ping less than 1 m away should not increase the total.
    """
    reset((1, "e"))
    record_position(1, "e", 10.3157000, 123.8854000)
    before = get_distance_metres(1, "e")
    # Move ~0.2 m (well below 1 m threshold)
    record_position(1, "e", 10.3157002, 123.8854002)
    after = get_distance_metres(1, "e")
    assert before == after, "Sub-metre jitter should be ignored"


def test_runners_isolated_by_runner_id():
    """Two different runners in the same race should not share state."""
    reset((2, "r1"), (2, "r2"))
    record_position(2, "r1", 10.3157, 123.8854)
    record_position(2, "r1", 10.3167, 123.8854)  # ~111 m

    record_position(2, "r2", 10.3157, 123.8854)  # r2 has only 1 ping

    assert get_distance_metres(2, "r1") > 100
    assert get_distance_metres(2, "r2") == 0.0


def test_races_isolated_by_race_id():
    """Same runner in two different races should not share distance."""
    reset((10, "runner"), (20, "runner"))
    record_position(10, "runner", 10.3157, 123.8854)
    record_position(10, "runner", 10.3167, 123.8854)   # ~111 m in race 10

    record_position(20, "runner", 10.3157, 123.8854)   # only 1 ping in race 20

    assert get_distance_metres(10, "runner") > 100
    assert get_distance_metres(20, "runner") == 0.0


def test_get_distance_km():
    reset((3, "km"))
    record_position(3, "km", 10.3157, 123.8854)
    record_position(3, "km", 10.3167, 123.8854)
    metres = get_distance_metres(3, "km")
    km = get_distance_km(3, "km")
    assert abs(km - metres / 1000) < 0.001


def test_no_data_returns_zero():
    reset((99, "ghost"))
    assert get_distance_metres(99, "ghost") == 0.0
    assert get_distance_km(99, "ghost") == 0.0


def test_summary_dict_structure():
    reset((4, "s"))
    record_position(4, "s", 10.3157, 123.8854)
    record_position(4, "s", 10.3167, 123.8854)
    summary = get_distance_summary(4, "s")

    for key in ("race_id", "runner_id", "distance_metres",
                "distance_km", "distance_formatted", "gps_points_recorded"):
        assert key in summary, f"Missing key: {key}"

    assert summary["race_id"] == 4
    assert summary["runner_id"] == "s"
    assert summary["gps_points_recorded"] == 2
    assert summary["distance_metres"] > 0


def test_format_distance_metres():
    reset((5, "fmt_m"))
    record_position(5, "fmt_m", 10.3157, 123.8854)
    record_position(5, "fmt_m", 10.3160, 123.8854)   # ~33 m
    summary = get_distance_summary(5, "fmt_m")
    assert summary["distance_formatted"].endswith(" m"), \
        f"Expected metres format, got: {summary['distance_formatted']}"


def test_format_distance_km():
    reset((5, "fmt_km"))
    record_position(5, "fmt_km", 10.3157, 123.8854)
    # Move 1.5° lat ≈ 166 km — definitely over 1000 m
    record_position(5, "fmt_km", 11.8157, 123.8854)
    summary = get_distance_summary(5, "fmt_km")
    assert summary["distance_formatted"].endswith(" km"), \
        f"Expected km format, got: {summary['distance_formatted']}"


def test_get_all_runners_sorted_furthest_first():
    reset((6, "slow"), (6, "fast"))
    # fast runner goes further
    record_position(6, "fast", 10.3157, 123.8854)
    record_position(6, "fast", 10.3177, 123.8854)   # ~222 m

    record_position(6, "slow", 10.3157, 123.8854)
    record_position(6, "slow", 10.3162, 123.8854)   # ~55 m

    results = get_all_runners_distance(6)
    assert len(results) == 2
    assert results[0]["distance_metres"] >= results[1]["distance_metres"], \
        "Results should be sorted furthest first"


def test_reset_runner_clears_data():
    reset((7, "todelete"))
    record_position(7, "todelete", 10.3157, 123.8854)
    record_position(7, "todelete", 10.3167, 123.8854)
    assert get_distance_metres(7, "todelete") > 0

    reset_runner(7, "todelete")
    assert get_distance_metres(7, "todelete") == 0.0


def test_reset_race_clears_all_runners():
    reset((8, "r1"), (8, "r2"))
    record_position(8, "r1", 10.3157, 123.8854)
    record_position(8, "r1", 10.3167, 123.8854)
    record_position(8, "r2", 10.3157, 123.8854)
    record_position(8, "r2", 10.3167, 123.8854)

    reset_race(8)

    assert get_distance_metres(8, "r1") == 0.0
    assert get_distance_metres(8, "r2") == 0.0


def test_gps_point_count_increments():
    reset((9, "counter"))
    record_position(9, "counter", 10.3157, 123.8854)
    record_position(9, "counter", 10.3167, 123.8854)
    record_position(9, "counter", 10.3177, 123.8854)
    summary = get_distance_summary(9, "counter")
    assert summary["gps_points_recorded"] == 3


def test_delta_returned_correctly():
    reset((11, "delta"))
    record_position(11, "delta", 10.3157, 123.8854)
    delta = record_position(11, "delta", 10.3167, 123.8854)
    assert 100 < delta < 120, f"Expected delta ~111 m, got {delta}"


def test_jitter_delta_is_zero():
    reset((12, "jitter"))
    record_position(12, "jitter", 10.3157000, 123.8854000)
    delta = record_position(12, "jitter", 10.3157001, 123.8854001)  # sub-metre
    assert delta == 0.0, "Jitter delta should be 0.0"


# ── Run directly ──────────────────────────────────────────

if __name__ == "__main__":
    tests = [fn for name, fn in globals().items() if name.startswith("test_")]
    passed = failed = 0
    for test in tests:
        try:
            test()
            print(f"  ✅  {test.__name__}")
            passed += 1
        except Exception as exc:
            print(f"  ❌  {test.__name__}  →  {exc}")
            failed += 1
    print(f"\n{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)