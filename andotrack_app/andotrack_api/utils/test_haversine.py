from haversine import haversine

def test_same_point():
    assert haversine(10.3157, 123.8854, 10.3157, 123.8854) == 0.0

def test_known_distance():
    # ~111 meters per 0.001 degree latitude
    dist = haversine(10.3157, 123.8854, 10.3167, 123.8854)
    assert 100 < dist < 120, f"Expected ~111m, got {dist:.1f}m"

def test_checkpoint_radius():
    # Runner is 15m away from checkpoint — within 20m radius
    dist = haversine(10.31570, 123.88540, 10.31583, 123.88540)
    assert dist < 20

if __name__ == "__main__":
    test_same_point()
    test_known_distance()
    test_checkpoint_radius()
    print("✅ All Haversine tests passed")