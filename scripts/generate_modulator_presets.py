#!/usr/bin/env python3
"""
Generate SideFX Modulator preset file (.rpl).

Uses slider NUMBER positions with dashes for gaps.
This format works for 4 and 8 points.
"""

import base64
import math


def create_preset(name, num_points, points):
    """
    Slider NUMBER positions (1-86) with dashes for gaps.
    Name goes at position 64 (after slider64/P13X, before slider65/P13Y).
    """
    values = ["-"] * 86

    # Position 1-6: slider1-6 (Rate section)
    values[0] = "0"
    values[1] = "1"
    values[2] = "5"
    values[3] = "0"
    values[4] = "0"
    values[5] = "1"

    # Position 20-25: slider20-25 (Trigger section)
    values[19] = "0"
    values[20] = "0"
    values[21] = "0"
    values[22] = "0.5"
    values[23] = "100"
    values[24] = "500"

    # Position 26-27: slider26-27 (Grid, Snap)
    values[25] = "2"
    values[26] = "1"

    # Position 28-29: slider28-29 (LFO Mode, Curve Shape)
    values[27] = "0"
    values[28] = "0"

    # Position 30: slider30 (Num Points)
    values[29] = str(num_points)

    # Position 40-71: slider40-71 (Point data)
    for i in range(16):
        if i < len(points):
            values[39 + i*2] = str(points[i][0])
            values[39 + i*2 + 1] = str(points[i][1])
        else:
            values[39 + i*2] = "0.5"
            values[39 + i*2 + 1] = "0.5"

    # Insert quoted name at position 64 (after P13X, before P13Y)
    # Positions 0-63 are indices 0-63, name goes at index 64
    values.insert(64, f'"{name}"')

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


def generate_presets():
    """Generate all preset definitions."""
    presets = []

    # Sine (16 points for smooth curve)
    presets.append(("Sine", 16, generate_sine_points(16)))

    # Triangle: 3 points - up and down
    presets.append(("Triangle", 3, [(0, 0), (0.5, 1), (1, 0)]))

    # Sawtooth: 4 points - ramp up then instant drop
    presets.append(("Sawtooth", 4, [(0, 0.5), (0.499, 1), (0.5, 0), (1, 0.5)]))

    # Square: 4 points - high, instant drop, low, instant rise
    presets.append(("Square", 4, [(0, 1), (0.499, 1), (0.5, 0), (1, 0)]))

    # Ramp Up: 2 points - simple linear rise
    presets.append(("Ramp_Up", 2, [(0, 0), (1, 1)]))

    # Ramp Down: 2 points - simple linear fall
    presets.append(("Ramp_Down", 2, [(0, 1), (1, 0)]))

    # Shark Fin: 3 points - fast attack, slow decay
    presets.append(("Shark_Fin", 3, [(0, 0), (0.2, 1), (1, 0)]))

    # Growl: 6 points - irregular wobble
    presets.append(("Growl", 6, [(0, 0.1), (0.2, 0.8), (0.4, 0.2), (0.6, 0.9), (0.8, 0.3), (1, 0)]))

    # Exponential Rise: 2 points (curve applied via segment)
    presets.append(("Exp_Rise", 2, [(0, 0), (1, 1)]))

    # Exponential Fall: 2 points (curve applied via segment)
    presets.append(("Exp_Fall", 2, [(0, 1), (1, 0)]))

    return presets


def main():
    presets = generate_presets()

    print('<REAPER_PRESET_LIBRARY "JS: SideFX Modulator"')
    for name, num_pts, points in presets:
        encoded = create_preset(name, num_pts, points)
        print(f"  <PRESET `{name}`")
        print(f"    {encoded}")
        print("  >")
    print(">")


if __name__ == "__main__":
    main()
