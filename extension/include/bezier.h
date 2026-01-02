#pragma once

#include <array>
#include <vector>
#include <cmath>

namespace sidefx {

// A 2D point for Bezier control points
struct Point {
    double x = 0.0;
    double y = 0.0;

    Point() = default;
    Point(double x_, double y_) : x(x_), y(y_) {}
};

// Cubic Bezier curve with 4 control points
// P0 = start, P1 = control1, P2 = control2, P3 = end
class CubicBezier {
public:
    std::array<Point, 4> points;

    CubicBezier() {
        // Default: linear ramp 0->1
        points[0] = {0.0, 0.0};
        points[1] = {0.33, 0.33};
        points[2] = {0.66, 0.66};
        points[3] = {1.0, 1.0};
    }

    CubicBezier(Point p0, Point p1, Point p2, Point p3) {
        points[0] = p0;
        points[1] = p1;
        points[2] = p2;
        points[3] = p3;
    }

    // Evaluate the curve at parameter t (0-1)
    // Returns the Y value (the modulation output)
    double evaluate(double t) const {
        // Clamp t to [0, 1] - use parens to avoid SWELL macro conflict
        if (t < 0.0) t = 0.0;
        if (t > 1.0) t = 1.0;

        // Cubic Bezier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
        double mt = 1.0 - t;
        double mt2 = mt * mt;
        double mt3 = mt2 * mt;
        double t2 = t * t;
        double t3 = t2 * t;

        double y = mt3 * points[0].y
                 + 3.0 * mt2 * t * points[1].y
                 + 3.0 * mt * t2 * points[2].y
                 + t3 * points[3].y;

        return y;
    }

    // Evaluate both X and Y (for drawing)
    Point evaluatePoint(double t) const {
        if (t < 0.0) t = 0.0;
        if (t > 1.0) t = 1.0;

        double mt = 1.0 - t;
        double mt2 = mt * mt;
        double mt3 = mt2 * mt;
        double t2 = t * t;
        double t3 = t2 * t;

        return Point{
            mt3 * points[0].x + 3.0 * mt2 * t * points[1].x + 3.0 * mt * t2 * points[2].x + t3 * points[3].x,
            mt3 * points[0].y + 3.0 * mt2 * t * points[1].y + 3.0 * mt * t2 * points[2].y + t3 * points[3].y
        };
    }

    // Set from flat array [x0,y0, x1,y1, x2,y2, x3,y3]
    void setFromArray(const double* arr) {
        for (int i = 0; i < 4; i++) {
            points[i].x = arr[i * 2];
            points[i].y = arr[i * 2 + 1];
        }
    }
};

// Multi-segment Bezier curve for complex LFO shapes
// Each segment is a cubic Bezier, segments are joined end-to-end
class BezierCurve {
public:
    std::vector<CubicBezier> segments;

    BezierCurve() {
        // Default: single segment (simple curve)
        segments.emplace_back();
    }

    // Evaluate the full curve at phase (0-1)
    double evaluate(double phase) const {
        if (segments.empty()) return 0.0;

        // Clamp phase
        if (phase < 0.0) phase = 0.0;
        if (phase > 1.0) phase = 1.0;

        // Find which segment we're in
        double segmentPhase = phase * segments.size();
        size_t segmentIndex = static_cast<size_t>(segmentPhase);
        if (segmentIndex >= segments.size()) segmentIndex = segments.size() - 1;

        // Local t within segment
        double t = segmentPhase - segmentIndex;

        return segments[segmentIndex].evaluate(t);
    }

    // Add a segment
    void addSegment(const CubicBezier& seg) {
        segments.push_back(seg);
    }

    // Clear and set single segment
    void setSingleSegment(const CubicBezier& seg) {
        segments.clear();
        segments.push_back(seg);
    }
};

// Preset curve shapes
namespace presets {

inline CubicBezier sine() {
    // Approximate sine wave with Bezier (one quarter)
    // For full sine, use 4 segments
    return CubicBezier(
        {0.0, 0.5},
        {0.33, 1.0},
        {0.66, 1.0},
        {1.0, 0.5}
    );
}

inline CubicBezier triangle() {
    return CubicBezier(
        {0.0, 0.0},
        {0.25, 0.5},
        {0.75, 0.5},
        {1.0, 0.0}
    );
}

inline CubicBezier sawUp() {
    return CubicBezier(
        {0.0, 0.0},
        {0.33, 0.33},
        {0.66, 0.66},
        {1.0, 1.0}
    );
}

inline CubicBezier sawDown() {
    return CubicBezier(
        {0.0, 1.0},
        {0.33, 0.66},
        {0.66, 0.33},
        {1.0, 0.0}
    );
}

inline CubicBezier square() {
    // Square wave approximation (steep transitions)
    return CubicBezier(
        {0.0, 0.0},
        {0.01, 1.0},
        {0.99, 1.0},
        {1.0, 0.0}
    );
}

inline CubicBezier easeInOut() {
    return CubicBezier(
        {0.0, 0.0},
        {0.42, 0.0},
        {0.58, 1.0},
        {1.0, 1.0}
    );
}

} // namespace presets

} // namespace sidefx

