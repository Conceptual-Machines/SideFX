#!/usr/bin/env python3
"""
Generate SideFX Modulator preset file (.rpl).
"""

import base64
import math


def create_basic_preset(name, num_points, points):
    """For basic shapes WITHOUT curves."""
    values = ["-"] * 86

    values[0] = "0"
    values[1] = "1"
    values[2] = "5"
    values[3] = "0"
    values[4] = "0"
    values[5] = "1"

    values[19] = "0"
    values[20] = "0"
    values[21] = "0"
    values[22] = "0.5"
    values[23] = "100"
    values[24] = "500"

    values[25] = "2"
    values[26] = "1"
    values[27] = "0"
    values[28] = "0"
    values[29] = str(num_points)

    for i in range(16):
        if i < len(points):
            values[39 + i*2] = str(points[i][0])
            values[39 + i*2 + 1] = str(points[i][1])
        else:
            values[39 + i*2] = "0.5"
            values[39 + i*2 + 1] = "0.5"

    values.insert(64, f'"{name}"')

    # Explicitly set all curve positions to 0 (neutral)
    for i in range(15):
        values[72 + i] = "0"

    full = " ".join(values)
    encoded = base64.b64encode(full.encode()).decode()
    lines = [encoded[i:i+80] for i in range(0, len(encoded), 80)]
    return "\n    ".join(lines)


def create_curved_preset(name, num_points, points, curves):
    """For shapes WITH curves."""
    values = ["-"] * 86

    values[0] = "0"
    values[1] = "1"
    values[2] = "5"
    values[3] = "0"
    values[4] = "0"
    values[5] = "1"

    values[19] = "0"
    values[20] = "0"
    values[21] = "0"
    values[22] = "0.5"
    values[23] = "100"
    values[24] = "500"

    values[25] = "2"
    values[26] = "1"
    values[27] = "0"
    values[28] = "0"
    values[29] = str(num_points)

    for i in range(16):
        if i < len(points):
            values[39 + i*2] = str(points[i][0])
            values[39 + i*2 + 1] = str(points[i][1])
        else:
            values[39 + i*2] = "0.5"
            values[39 + i*2 + 1] = "0.5"

    values.insert(64, f'"{name}"')

    # Curves at positions 73-87 (indices 72-86 after insert)
    for i, curve in enumerate(curves):
        if i < 15:
            values[72 + i] = str(curve)

    full = " ".join(values)
    encoded = base64.b64encode(full.encode()).decode()
    lines = [encoded[i:i+80] for i in range(0, len(encoded), 80)]
    return "\n    ".join(lines)


def generate_sine_points(num_points):
    points = []
    for i in range(num_points):
        x = round(i / (num_points - 1), 3)
        y = round(0.5 + 0.5 * math.sin(2 * math.pi * x), 3)
        points.append((x, y))
    return points


def main():
    print('<REAPER_PRESET_LIBRARY "JS: SideFX Modulator"')

    # Basic shapes - NO curves
    basic = [
        ("Sine", 16, generate_sine_points(16)),
        ("Triangle", 3, [(0, 0), (0.5, 1), (1, 0)]),
        ("Sawtooth", 4, [(0, 0.5), (0.499, 1), (0.5, 0), (1, 0.5)]),
        ("Square", 4, [(0, 1), (0.499, 1), (0.5, 0), (1, 0)]),
        ("Ramp_Up", 2, [(0, 0), (1, 1)]),
        ("Ramp_Down", 2, [(0, 1), (1, 0)]),
        ("Growl", 6, [(0, 0.1), (0.2, 0.8), (0.4, 0.2), (0.6, 0.9), (0.8, 0.3), (1, 0)]),
        ("Exp_Rise", 2, [(0, 0), (1, 1)]),
        ("Exp_Fall", 2, [(0, 1), (1, 0)]),
    ]

    for name, num_pts, points in basic:
        encoded = create_basic_preset(name, num_pts, points)
        print(f"  <PRESET `{name}`")
        print(f"    {encoded}")
        print("  >")

    # Curved shapes - WITH curves
    curved = [
        ("Shark_Fin", 3, [(0, 0), (0.2, 1), (1, 0)], [-0.5, 0.5]),
    ]

    for name, num_pts, points, curves in curved:
        encoded = create_curved_preset(name, num_pts, points, curves)
        print(f"  <PRESET `{name}`")
        print(f"    {encoded}")
        print("  >")

    print(">")


if __name__ == "__main__":
    main()
