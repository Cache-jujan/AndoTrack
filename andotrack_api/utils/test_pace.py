"""
Quick unit tests for andotrack_api/utils/pace.py
Run with:  python -m pytest utils/test_pace.py -v
       or:  python utils/test_pace.py
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from utils.pace import (
    record_speed,
    get_pace_min_per_km,
    format_pace,
    get_runner_pace_summary,
    clear_runner_history,
    _speed_history,
)


def _reset(runner_id: str):
    clear_runner_history(runner_id)


# ── Helpers ───────────────────────────────────────────────

def test_no_readings_returns_none():
    _reset("r0")
    assert get_pace_min_per_km("r0") is None


def test_single_reading():
    _reset("r1")
    # 3 m/s  →  pace = 1000 / (3 * 60) = 5.555... ≈ 5.56 min/km
    record_speed("r1", 3.0)
    pace = get_pace_min_per_km("r1")
    assert pace is not None
    assert abs(pace - 5.56) < 0.01, f"Expected ~5.56, got {pace}"


def test_rolling_window_caps_at_5():
    _reset("r2")
    for speed in [2.0, 2.5, 3.0, 3.5, 4.0, 99.0]:   # 6 readings; first should drop
        record_speed("r2", speed)
    history = _speed_history["r2"]
    assert len(history) == 5
    assert 99.0 in history
    assert 2.0 not in history          # oldest reading evicted


def test_rolling_average_uses_last_5():
    _reset("r3")
    # Push 5 identical readings of 2.778 m/s ≈ 10 km/h → pace ≈ 6 min/km
    for _ in range(5):
        record_speed("r3", 2.778)
    pace = get_pace_min_per_km("r3")
    assert pace is not None
    assert abs(pace - 6.0) < 0.1, f"Expected ~6.0 min/km, got {pace}"


def test_stationary_runner_returns_none():
    _reset("r4")
    record_speed("r4", 0.0)
    assert get_pace_min_per_km("r4") is None


def test_format_pace_none():
    assert format_pace(None) == "—"


def test_format_pace_normal():
    # 5.5 min/km → 5 min 30 sec
    assert format_pace(5.5) == "5:30 /km"


def test_format_pace_round_seconds():
    # 5.0 min/km → 5 min 00 sec
    assert format_pace(5.0) == "5:00 /km"


def test_format_pace_59_seconds():
    # 5 min 59 sec = 5 + 59/60 ≈ 5.9833
    assert format_pace(5.9833) == "5:59 /km"


def test_summary_dict_keys():
    _reset("r5")
    record_speed("r5", 3.0)
    summary = get_runner_pace_summary("r5")
    for key in ("runner_id", "sample_count", "avg_speed_ms",
                "avg_speed_kmh", "pace_min_per_km", "pace_formatted"):
        assert key in summary, f"Missing key: {key}"


def test_negative_speed_ignored():
    _reset("r6")
    record_speed("r6", -1.0)   # invalid GPS artefact, should be ignored
    assert get_pace_min_per_km("r6") is None


def test_clear_history():
    _reset("r7")
    record_speed("r7", 3.0)
    clear_runner_history("r7")
    assert get_pace_min_per_km("r7") is None


# ── Run directly ──────────────────────────────────────────

if __name__ == "__main__":
    tests = [fn for name, fn in list(globals().items()) if name.startswith("test_")]
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