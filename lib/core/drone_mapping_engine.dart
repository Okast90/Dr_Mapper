import 'dart:math';

import 'package:latlong2/latlong.dart';

class DroneMappingEngine {
  /// Altitude in meters
  final double altitude;

  /// Forward overlap in percentage
  final double forwardOverlap;

  /// Side overlap in percentage
  final double sideOverlap;

  /// Sensor width in mm
  final double sensorWidth;

  /// Sensor height in mm
  final double sensorHeight;

  /// Focal length in mm
  final double focalLength;

  /// Image width in pixels
  final int imageWidth;

  /// Image height in pixels
  final int imageHeight;

  /// Angle of the drone in degrees
  final double angle;

  /// Ground offset in meters (e.g., height of target surface above ground)
  final double groundOffset;

  DroneMappingEngine({
    required this.altitude,
    required this.forwardOverlap,
    required this.sideOverlap,
    required this.sensorWidth,
    required this.sensorHeight,
    required this.focalLength,
    required this.imageWidth,
    required this.imageHeight,
    required this.angle,
    required this.groundOffset,
  });

  double get effectiveAltitude => altitude - groundOffset;

  double get gsdX => (effectiveAltitude * sensorWidth) / (imageWidth * focalLength);
  double get gsdY => (effectiveAltitude * sensorHeight) / (imageHeight * focalLength);

  double get footprintWidth => gsdX * imageWidth;
  double get footprintHeight => gsdY * imageHeight;

  double get effectiveFootprintWidth => footprintWidth * (1 - sideOverlap);
  double get effectiveFootprintHeight => footprintHeight * (1 - forwardOverlap);

  double get flightLineSpacing => footprintWidth * (1 - sideOverlap);
  double get pathSpacing => footprintHeight * (1 - forwardOverlap);

  // Spacing for horizontal lines
  double get horizontalLineSpacing => footprintHeight * (1 - sideOverlap);      // Y spacing (cross-track)
  double get horizontalWaypointSpacing => footprintWidth * (1 - forwardOverlap); // X spacing (along-track)

  // ==========================================
  // OPTIMAL SWEEP ANGLE
  // ==========================================

  /// Test [angleStepDeg] increments from 0 to 175° and return the angle that
  /// minimises the number of boustrophedon passes (= fewest turn-arounds).
  static double _findOptimalSweepAngle(List<Point> polygon,
      {int angleStepDeg = 5}) {
    if (polygon.length < 3) return 0.0;

    double bestAngle = 0.0;
    int bestLines = 0x7fffffff;

    for (int deg = 0; deg < 180; deg += angleStepDeg) {
      final rad = deg * pi / 180.0;
      final rotated = polygon.map((p) {
        final x = p.x * cos(rad) - p.y * sin(rad);
        final y = p.x * sin(rad) + p.y * cos(rad);
        return Point(x, y);
      }).toList();

      final minY = rotated.map((p) => p.y).reduce(min);
      final maxY = rotated.map((p) => p.y).reduce(max);
      // Use a representative spacing (will be refined in actual generation)
      // We just count how many Y-lines fall inside – lower = better
      const approxSpacing = 10.0; // arbitrary relative unit
      int lineCount = 0;
      for (double y = minY; y <= maxY; y += approxSpacing) {
        bool hasPoint = false;
        final minX = rotated.map((p) => p.x).reduce(min);
        final maxX = rotated.map((p) => p.x).reduce(max);
        for (double x = minX; x <= maxX; x += approxSpacing) {
          if (_isPointInPolygon(Point(x, y), rotated)) {
            hasPoint = true;
            break;
          }
        }
        if (hasPoint) lineCount++;
      }
      if (lineCount < bestLines) {
        bestLines = lineCount;
        bestAngle = deg.toDouble();
      }
    }
    return bestAngle;
  }

  // ==========================================
  // INSET BUFFER (negative polygon erosion)
  // ==========================================

  /// Erode [polygon] inward by [insetDist] metres using edge-offset intersection.
  /// Returns the original polygon if the inset collapses or inverts it.
  static List<Point> _insetPolygon(List<Point> polygon, double insetDist) {
    if (polygon.length < 3 || insetDist <= 0) return polygon;

    final minX = polygon.map((p) => p.x).reduce(min);
    final maxX = polygon.map((p) => p.x).reduce(max);
    final minY = polygon.map((p) => p.y).reduce(min);
    final maxY = polygon.map((p) => p.y).reduce(max);
    final maxSafeInset = min(maxX - minX, maxY - minY) * 0.15;
    final effectiveInset = min(insetDist, maxSafeInset);
    if (effectiveInset <= 0.5) return polygon;

    final n = polygon.length;
    final originalArea = _signedArea(polygon);
    if (originalArea.abs() < 10.0) return polygon;

    // Compute inward-offset edges
    final offsetEdges = <({Point a, Point b})>[];
    for (int i = 0; i < n; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % n];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-9) continue;
      // Inward normal: if CCW (originalArea > 0), (-dy, dx) is inward. If CW, (dy, -dx) is inward.
      final nx = originalArea > 0 ? -dy / len : dy / len;
      final ny = originalArea > 0 ? dx / len : -dx / len;
      offsetEdges.add((
        a: Point(p1.x + nx * effectiveInset, p1.y + ny * effectiveInset),
        b: Point(p2.x + nx * effectiveInset, p2.y + ny * effectiveInset),
      ));
    }
    if (offsetEdges.length < 3) return polygon;

    // Intersect consecutive offset edges to get inset vertices
    final inset = <Point>[];
    final m = offsetEdges.length;
    for (int i = 0; i < m; i++) {
      final e1 = offsetEdges[i];
      final e2 = offsetEdges[(i + 1) % m];
      final inter = _lineIntersection(e1.a, e1.b, e2.a, e2.b);
      if (inter != null) inset.add(inter);
    }

    // Sanity checks: same orientation and at least 30% area retained
    if (inset.length < 3) return polygon;
    final insetArea = _signedArea(inset);
    if (insetArea * originalArea <= 0 || insetArea.abs() < originalArea.abs() * 0.3) {
      return polygon;
    }
    return inset;
  }

  static double _signedArea(List<Point> poly) {
    double area = 0;
    final n = poly.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += poly[i].x * poly[j].y;
      area -= poly[j].x * poly[i].y;
    }
    return area / 2;
  }

  static Point? _lineIntersection(Point a1, Point a2, Point b1, Point b2) {
    final d1x = a2.x - a1.x;
    final d1y = a2.y - a1.y;
    final d2x = b2.x - b1.x;
    final d2y = b2.y - b1.y;
    final denom = d1x * d2y - d1y * d2x;
    if (denom.abs() < 1e-12) return null; // parallel
    final t =
        ((b1.x - a1.x) * d2y - (b1.y - a1.y) * d2x) / denom;
    return Point(a1.x + t * d1x, a1.y + t * d1y);
  }

  // ==========================================
  // CONVEX DECOMPOSITION (Ear-Clip + Hertel-Mehlhorn)
  // ==========================================

  /// Returns true if [polygon] is convex (all cross-products same sign).
  static bool _isConvexPolygon(List<Point> poly) {
    final n = poly.length;
    if (n < 3) return false;
    double sign = 0;
    for (int i = 0; i < n; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % n];
      final c = poly[(i + 2) % n];
      final cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
      if (cross.abs() < 1e-9) continue;
      final currentSign = cross.sign.toDouble();
      if (sign == 0) {
        sign = currentSign;
      } else if (currentSign != sign) {
        return false;
      }
    }
    return true;
  }

  /// Ear-clipping triangulation → list of triangles (each = 3 Point indices into [poly]).
  static List<List<int>> _earClip(List<Point> poly) {
    final n = poly.length;
    if (n < 3) return [];
    final indices = List<int>.generate(n, (i) => i);
    final triangles = <List<int>>[];
    int attempts = 0;
    while (indices.length > 3 && attempts < indices.length * indices.length) {
      bool earFound = false;
      for (int i = 0; i < indices.length; i++) {
        final prev = indices[(i - 1 + indices.length) % indices.length];
        final curr = indices[i];
        final next = indices[(i + 1) % indices.length];
        final a = poly[prev];
        final b = poly[curr];
        final c = poly[next];
        // Must be a convex ear (CCW cross > 0)
        final cross =
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
        if (cross <= 0) continue;
        // No other vertex inside this triangle
        bool hasInside = false;
        for (int j = 0; j < indices.length; j++) {
          if (j == i - 1 || j == i || j == (i + 1) % indices.length) continue;
          final idx = indices[j];
          if (idx == prev || idx == curr || idx == next) continue;
          if (_pointInTriangle(poly[idx], a, b, c)) {
            hasInside = true;
            break;
          }
        }
        if (!hasInside) {
          triangles.add([prev, curr, next]);
          indices.removeAt(i);
          earFound = true;
          break;
        }
      }
      if (!earFound) attempts++;
    }
    if (indices.length == 3) triangles.add(List<int>.from(indices));
    return triangles;
  }

  static bool _pointInTriangle(Point p, Point a, Point b, Point c) {
    double sign(Point p1, Point p2, Point p3) =>
        ((p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y))
            .toDouble();
    final d1 = sign(p, a, b);
    final d2 = sign(p, b, c);
    final d3 = sign(p, c, a);
    final hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
    final hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
    return !(hasNeg && hasPos);
  }

  /// Hertel-Mehlhorn: merge triangles into convex polygons greedily.
  /// [triangles] is a list of index-triplets into [poly].
  static List<List<Point>> _hertelMehlhorn(
      List<Point> poly, List<List<int>> triangles) {
    if (triangles.isEmpty) return [poly];

    // Build adjacency: for each triangle store its polygon as Point list
    final parts = triangles
        .map((t) => [poly[t[0]], poly[t[1]], poly[t[2]]])
        .toList();

    bool merged = true;
    while (merged) {
      merged = false;
      outer:
      for (int i = 0; i < parts.length; i++) {
        for (int j = i + 1; j < parts.length; j++) {
          final candidate = _tryMerge(parts[i], parts[j]);
          if (candidate != null && _isConvexPolygon(candidate)) {
            parts[i] = candidate;
            parts.removeAt(j);
            merged = true;
            break outer;
          }
        }
      }
    }
    return parts;
  }

  /// Attempt to merge two convex polygons that share an edge.
  /// Returns the merged polygon or null if no shared edge found.
  static List<Point>? _tryMerge(List<Point> a, List<Point> b) {
    final na = a.length;
    final nb = b.length;
    for (int i = 0; i < na; i++) {
      final p1 = a[i];
      final p2 = a[(i + 1) % na];
      for (int j = 0; j < nb; j++) {
        final q1 = b[j];
        final q2 = b[(j + 1) % nb];
        // Shared edge: p1==q2 and p2==q1 (opposite orientation)
        if (_ptEq(p1, q2) && _ptEq(p2, q1)) {
          // Merge: take a[0..i] + b[(j+1)..] + b[0..j-1] skipping shared pts
          final merged = <Point>[];
          for (int k = 0; k <= i; k++) merged.add(a[k]);
          for (int k = 1; k < nb - 1; k++) merged.add(b[(j + 1 + k) % nb]);
          for (int k = i + 2; k < na; k++) merged.add(a[k]);
          // Remove collinear vertices
          return _removeCollinear(merged);
        }
      }
    }
    return null;
  }

  static bool _ptEq(Point a, Point b) =>
      (a.x - b.x).abs() < 1e-6 && (a.y - b.y).abs() < 1e-6;

  static List<Point> _removeCollinear(List<Point> poly) {
    final result = <Point>[];
    final n = poly.length;
    for (int i = 0; i < n; i++) {
      final prev = poly[(i - 1 + n) % n];
      final curr = poly[i];
      final next = poly[(i + 1) % n];
      final cross = (curr.x - prev.x) * (next.y - prev.y) -
          (curr.y - prev.y) * (next.x - prev.x);
      if (cross.abs() > 1e-6) result.add(curr);
    }
    return result.length >= 3 ? result : poly;
  }

  // ==========================================
  // SUTHERLAND-HODGMAN CLIP & RESIDUAL FILL
  // ==========================================

  /// Clip [subject] polygon against [clip] polygon (convex) using Sutherland-Hodgman.
  static List<Point> _sutherlandHodgman(
      List<Point> subject, List<Point> clip) {
    if (subject.isEmpty || clip.length < 3) return subject;
    var output = List<Point>.from(subject);
    final n = clip.length;
    for (int i = 0; i < n; i++) {
      if (output.isEmpty) break;
      final edgeStart = clip[i];
      final edgeEnd = clip[(i + 1) % n];
      final input = List<Point>.from(output);
      output.clear();
      for (int j = 0; j < input.length; j++) {
        final current = input[j];
        final prev = input[(j - 1 + input.length) % input.length];
        final currInside = _isInsideEdge(current, edgeStart, edgeEnd);
        final prevInside = _isInsideEdge(prev, edgeStart, edgeEnd);
        if (currInside) {
          if (!prevInside) {
            final inter = _lineIntersection(prev, current, edgeStart, edgeEnd);
            if (inter != null) output.add(inter);
          }
          output.add(current);
        } else if (prevInside) {
          final inter = _lineIntersection(prev, current, edgeStart, edgeEnd);
          if (inter != null) output.add(inter);
        }
      }
    }
    return output;
  }

  static bool _isInsideEdge(Point p, Point edgeA, Point edgeB) {
    return (edgeB.x - edgeA.x) * (p.y - edgeA.y) -
            (edgeB.y - edgeA.y) * (p.x - edgeA.x) >=
        0;
  }

  /// Generate waypoints to fill uncovered residual areas after the main grid.
  /// Computes the difference between [polygon] and the union of [coveredFootprints],
  /// then sweeps remaining cells.
  List<List<LatLng>> generateResidualFillWaypoints({
    required List<LatLng> polygon,
    required List<List<LatLng>> coveredFootprints,
    required bool createCameraPoints,
  }) {
    if (polygon.length < 3 || coveredFootprints.isEmpty) return [];
    final origin = polygon[0];
    final localPoly = _latLngToMeters(polygon);
    final effectiveAngle = angle == 0
        ? _findOptimalSweepAngle(localPoly)
        : angle.toDouble();
    final rotated = _rotatePolygon(localPoly, effectiveAngle);

    final minX = rotated.map((p) => p.x).reduce(min);
    final maxX = rotated.map((p) => p.x).reduce(max);
    final minY = rotated.map((p) => p.y).reduce(min);
    final maxY = rotated.map((p) => p.y).reduce(max);

    // Build a Set of grid cells (in rotated space) already covered
    final covered = <String>{};
    final hw = footprintWidth / 2;
    final hh = footprintHeight / 2;
    for (final fp in coveredFootprints) {
      final localFp = _latLngToMeters(fp);
      final rotFp = _rotatePolygon(localFp, effectiveAngle);
      final cx = rotFp.map((p) => p.x).reduce((a, b) => a + b) / rotFp.length;
      final cy = rotFp.map((p) => p.y).reduce((a, b) => a + b) / rotFp.length;
      // Snap to grid
      final col = ((cx - minX) / effectiveFootprintWidth).round();
      final row = ((cy - minY) / effectiveFootprintHeight).round();
      covered.add('$col:$row');
    }

    // Find uncovered cells that are inside the polygon
    final residualCenters = <List<LatLng>>[];
    int row = 0;
    for (double y = minY + hh;
        y <= maxY - hh;
        y += effectiveFootprintHeight, row++) {
      int col = 0;
      for (double x = minX + hw;
          x <= maxX - hw;
          x += effectiveFootprintWidth, col++) {
        final key = '$col:$row';
        if (covered.contains(key)) continue;
        final p = Point(x, y);
        if (!_isPointInPolygon(p, rotated)) continue;
        // This cell is inside the polygon but not covered → generate fill wp
        final unrotated = _rotatePolygon([p], -effectiveAngle);
        final latlng = _metersToLatLng(unrotated, origin);
        residualCenters.add(latlng);
      }
    }
    return residualCenters;
  }

  static bool _preferHorizontalSweep(List<Point> polygon) {
    if (polygon.length < 3) return true;

    final minX = polygon.map((p) => p.x).reduce(min);
    final maxX = polygon.map((p) => p.x).reduce(max);
    final minY = polygon.map((p) => p.y).reduce(min);
    final maxY = polygon.map((p) => p.y).reduce(max);

    final width = (maxX - minX).abs();
    final height = (maxY - minY).abs();

    return width >= height;
  }


  // Convert LatLng to local coordinate system (in meters)
  static List<Point> _latLngToMeters(List<LatLng> polygon) {
    var origin = polygon[0];
    double originLat = origin.latitude;
    double originLng = origin.longitude;
    return polygon.map((latLng) {
      double x = (latLng.longitude - originLng) *
          (40075000 * cos((originLat * pi) / 180) / 360);
      double y = (latLng.latitude - originLat) * (40075000 / 360);
      return Point(x, y);
    }).toList();
  }

  // Convert local coordinates (in meters) back to LatLng
  static List<LatLng> _metersToLatLng(List<Point> points, LatLng origin) {
    double originLat = origin.latitude;
    double originLng = origin.longitude;
    return points.map((point) {
      double lat = originLat + (point.y / (40075000 / 360));
      double lng = originLng +
          (point.x / (40075000 * cos((originLat * pi) / 180) / 360));
      return LatLng(lat, lng);
    }).toList();
  }

  // Rotate a point around the origin by a given angle
  static Point _rotatePoint(Point point, double angle) {
    double radians = angle * (pi / 180);
    double cosTheta = cos(radians);
    double sinTheta = sin(radians);
    double x = point.x * cosTheta - point.y * sinTheta;
    double y = point.x * sinTheta + point.y * cosTheta;
    return Point(x, y);
  }

  // Rotate a list of points around the origin by a given angle
  static List<Point> _rotatePolygon(List<Point> polygon, double angle) {
    return polygon.map((point) => _rotatePoint(point, angle)).toList();
  }

  // Check if a point is inside a polygon
  static bool _isPointInPolygon(Point point, List<Point> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if (((polygon[i].y > point.y) != (polygon[j].y > point.y)) &&
          (point.x <
              (polygon[j].x - polygon[i].x) *
                      (point.y - polygon[i].y) /
                      (polygon[j].y - polygon[i].y) +
                  polygon[i].x)) {
        inside = !inside;
      }
    }
    return inside;
  }

  static Point _latLngToPoint(LatLng latLng, LatLng origin) {
    double x = (latLng.longitude - origin.longitude) * (40075000 * cos((origin.latitude * pi) / 180) / 360);
    double y = (latLng.latitude - origin.latitude) * (40075000 / 360);
    return Point(x, y);
  }

  static double _distance(Point a, Point b) {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  }

  // Calculate the area of a polygon using the Shoelace formula
  static double calculateArea(List<LatLng> polygon) {
    var localPolygon = _latLngToMeters(polygon);
    double area = 0.0;
    for (int i = 0; i < localPolygon.length - 1; i++) {
      area += localPolygon[i].x * localPolygon[i + 1].y -
          localPolygon[i + 1].x * localPolygon[i].y;
    }
    area += localPolygon.last.x * localPolygon.first.y -
        localPolygon.first.x * localPolygon.last.y;
    return area.abs() / 2.0;
  }

  // Generate waypoints within the polygon in a boustrophedon pattern.
  // Integrates: (1) optimal sweep angle, (2) inset buffer, (3) convex decomposition.
  List<LatLng> generateWaypoints(
    List<LatLng> polygon,
    bool createCameraPoints, [
    bool fillGrid = false,
    LatLng? homePoint,
    bool useInsetBuffer = true,
    bool useConvexDecomposition = true,
  ]) {
    if (polygon.length < 3) return [];

    var localPolygon = _latLngToMeters(polygon);
    var origin = polygon[0];

    // ── Technique 2: Inset buffer ─────────────────────────────────
    // Erode the polygon by half the footprint width so camera centres
    // stay inside and the physical footprints still reach the boundary.
    List<Point> workPolygon = localPolygon;
    if (useInsetBuffer && footprintWidth > 0) {
      final inset = _insetPolygon(localPolygon, footprintWidth * 0.1);
      if (inset.length >= 3) workPolygon = inset;
    }

    // ── Technique 1: Optimal sweep angle ─────────────────────────
    final effectiveAngle =
        angle == 0 ? _findOptimalSweepAngle(workPolygon) : angle.toDouble();
    final shouldUseHorizontalSweep = _preferHorizontalSweep(workPolygon);

    // ── Technique 3: Convex decomposition ────────────────────────
    // If the polygon is non-convex, decompose into convex sub-polygons
    // and sweep each one independently.
    List<List<Point>> subPolygons;
    if (useConvexDecomposition && !_isConvexPolygon(workPolygon)) {
      // Ensure CCW winding for ear-clip
      final ccw = _signedArea(workPolygon) >= 0
          ? workPolygon
          : workPolygon.reversed.toList();
      final triangles = _earClip(ccw);
      if (triangles.isNotEmpty) {
        subPolygons = _hertelMehlhorn(ccw, triangles);
      } else {
        subPolygons = [workPolygon];
      }
    } else {
      subPolygons = [workPolygon];
    }

    // ── Sweep each sub-polygon and concatenate results ────────────
    final allWaypoints = <Point>[];
    for (final subPoly in subPolygons) {
      final rotated = _rotatePolygon(subPoly, effectiveAngle);
      final rOrigin = subPoly.isNotEmpty ? subPoly[0] : workPolygon[0];

      num minX = rotated.map((p) => p.x).reduce(min);
      num maxX = rotated.map((p) => p.x).reduce(max);
      num minY = rotated.map((p) => p.y).reduce(min);
      num maxY = rotated.map((p) => p.y).reduce(max);

      List<Point> subWaypoints;

      if (homePoint == null) {
        subWaypoints = [];
        bool reverse = false;
        for (num y = minY; y <= maxY; y += horizontalLineSpacing) {
          List<Point> line = [];
          if (createCameraPoints) {
            for (num x = minX; x <= maxX; x += horizontalWaypointSpacing) {
              final p = Point(x, y);
              if (_isPointInPolygon(p, rotated)) line.add(p);
            }
            if (line.isNotEmpty) {
              final candidate = Point(maxX, y);
              if ((maxX - line.last.x).abs() > 1e-6 &&
                  _isPointInPolygon(candidate, rotated)) {
                line.add(candidate);
              }
            }
          } else {
            Point? firstPoint;
            Point? lastPoint;
            for (num x = minX; x <= maxX; x += horizontalWaypointSpacing) {
              final p = Point(x, y);
              if (_isPointInPolygon(p, rotated)) {
                firstPoint ??= p;
                lastPoint = p;
              }
            }
            if (firstPoint != null) {
              if (lastPoint != null && (maxX - lastPoint.x).abs() > 1e-6) {
                final candidate = Point(maxX, y);
                if (_isPointInPolygon(candidate, rotated)) {
                  lastPoint = candidate;
                }
              }
              line.add(firstPoint);
              if (lastPoint != null && lastPoint != firstPoint) {
                line.add(lastPoint);
              }
            }
          }
          if (reverse) line = line.reversed.toList();
          subWaypoints.addAll(line);
          reverse = !reverse;
        }

        if (fillGrid && subWaypoints.isNotEmpty) {
          final verticalWaypoints = _generateVerticalWaypoints(
              rotated, createCameraPoints, subWaypoints.last,
              minX, maxX, minY, maxY);
          subWaypoints.addAll(verticalWaypoints);
        }
      } else {
        Point homeP = _latLngToPoint(homePoint, origin);
        // rotate homeP into sub-polygon space
        final rotHomeP = _rotatePoint(homeP, effectiveAngle);

        List<Point> selected;
        if (!fillGrid) {
          if (shouldUseHorizontalSweep) {
            var horiz = _generateHorizontalWaypoints(
                rotated, createCameraPoints, rotHomeP, minX, maxX, minY, maxY);
            if (horiz.isEmpty) {
              var vert = _generateVerticalWaypoints(
                  rotated, createCameraPoints, rotHomeP, minX, maxX, minY, maxY);
              subWaypoints = vert;
            } else {
              var horizRev = horiz.reversed.toList();
              selected = _distance(horiz.last, rotHomeP) <
                      _distance(horizRev.last, rotHomeP)
                  ? horiz
                  : horizRev;
              subWaypoints = selected;
            }
          } else {
            var vert = _generateVerticalWaypoints(
                rotated, createCameraPoints, rotHomeP, minX, maxX, minY, maxY);
            if (vert.isEmpty) {
              var horiz = _generateHorizontalWaypoints(
                  rotated, createCameraPoints, rotHomeP, minX, maxX, minY, maxY);
              subWaypoints = horiz;
            } else {
              var vertRev = vert.reversed.toList();
              selected = _distance(vert.last, rotHomeP) <
                      _distance(vertRev.last, rotHomeP)
                  ? vert
                  : vertRev;
              subWaypoints = selected;
            }
          }
        } else {
          var horiz = _generateHorizontalWaypoints(
              rotated, createCameraPoints, rotHomeP, minX, maxX, minY, maxY);
          if (horiz.isEmpty) {
            var fallbackVert = _generateVerticalWaypoints(
                rotated, createCameraPoints, rotHomeP, minX, maxX, minY, maxY);
            subWaypoints = fallbackVert;
          } else {
            var vert = _generateVerticalWaypoints(
                rotated, createCameraPoints, horiz.last, minX, maxX, minY, maxY);
            var pathHF = [...horiz, ...vert];

            var vertF = _generateVerticalWaypoints(
                rotated, createCameraPoints, rotHomeP, minX, maxX, minY, maxY);
            var horizA = vertF.isNotEmpty
                ? _generateHorizontalWaypoints(
                    rotated, createCameraPoints, vertF.last, minX, maxX, minY, maxY)
                : <Point>[];
            var pathVF = [...vertF, ...horizA];

            final paths = [pathHF, pathHF.reversed.toList(),
                           pathVF, pathVF.reversed.toList()]
                .where((p) => p.isNotEmpty)
                .toList();
            if (paths.isEmpty) {
              subWaypoints = [];
            } else {
              var best = paths.first;
              var bestDist = _distance(best.last, rotHomeP);
              for (final p in paths.skip(1)) {
                final d = _distance(p.last, rotHomeP);
                if (d < bestDist) {
                  bestDist = d;
                  best = p;
                }
              }
              subWaypoints = best;
            }
          }
        }
      }

      // Un-rotate this sub-polygon's waypoints back to local (unrotated) space
      final unrotated = _rotatePolygon(subWaypoints, -effectiveAngle);
      allWaypoints.addAll(unrotated);
    }

    return _metersToLatLng(allWaypoints, origin);
  }


  List<Point> _generateVerticalWaypoints(List<Point> polygon, bool createCameraPoints,Point lastHorizontal, num minHorizontalX, num maxHorizontalX, num minHorizontalY, num maxHorizontalY) {
    var verticalLineSpacing = footprintWidth * (1 - sideOverlap);  // Fixed bug: Use width for side overlap in vertical lines
    var verticalWaypointSpacing = footprintHeight * (1 - forwardOverlap);
    num offset = verticalWaypointSpacing * 0.1;

    List<num> verticalYCoords = [];
    num adjustedMinY = minHorizontalY - verticalWaypointSpacing / 2 - offset;
    for (num y = adjustedMinY; y <= maxHorizontalY + verticalWaypointSpacing / 2; y += verticalWaypointSpacing) {
      verticalYCoords.add(y);
    }

    num xLeft = minHorizontalX + verticalLineSpacing / 2;
    List<num> yLeft = verticalYCoords.where((y) => _isPointInPolygon(Point(xLeft, y), polygon)).toList();
    num minDistLeft = double.infinity;
    num distBottomLeft = double.infinity;
    num distTopLeft = double.infinity;
    if (yLeft.isNotEmpty) {
      num yBottomLeft = yLeft.first;
      num yTopLeft = yLeft.last;
      distBottomLeft = sqrt(pow(xLeft - lastHorizontal.x, 2) + pow(yBottomLeft - lastHorizontal.y, 2));
      distTopLeft = sqrt(pow(xLeft - lastHorizontal.x, 2) + pow(yTopLeft - lastHorizontal.y, 2));
      minDistLeft = min(distBottomLeft, distTopLeft);
    }

    num xRight = maxHorizontalX - verticalLineSpacing / 2;
    List<num> yRight = verticalYCoords.where((y) => _isPointInPolygon(Point(xRight, y), polygon)).toList();
    num minDistRight = double.infinity;
    num distBottomRight = double.infinity;
    num distTopRight = double.infinity;
    if (yRight.isNotEmpty) {
      num yBottomRight = yRight.first;
      num yTopRight = yRight.last;
      distBottomRight = sqrt(pow(xRight - lastHorizontal.x, 2) + pow(yBottomRight - lastHorizontal.y, 2));
      distTopRight = sqrt(pow(xRight - lastHorizontal.x, 2) + pow(yTopRight - lastHorizontal.y, 2));
      minDistRight = min(distBottomRight, distTopRight);
    }

    num startX;
    num deltaX;
    bool reverse;
    if (minDistLeft < minDistRight) {
      startX = xLeft;
      deltaX = verticalLineSpacing;
      reverse = distTopLeft < distBottomLeft;
    } else {
      startX = xRight;
      deltaX = -verticalLineSpacing;
      reverse = distTopRight < distBottomRight;
    }

    List<Point> verticalWaypoints = [];
    bool condition(num x) => deltaX > 0 ? x <= maxHorizontalX + verticalLineSpacing / 2 : x >= minHorizontalX - verticalLineSpacing / 2;
    for (num x = startX; condition(x); x += deltaX) {
      List<Point> column = [];
      for (num y in verticalYCoords) {
        Point p = Point(x, y);
        if (_isPointInPolygon(p, polygon)) {
          column.add(p);
        }
      }
      if (column.isEmpty) continue;

      if (reverse) column = column.reversed.toList();

      if (createCameraPoints) {
        verticalWaypoints.addAll(column);
      } else {
        verticalWaypoints.add(column.first);
        if (column.first != column.last) {
          verticalWaypoints.add(column.last);
        }
      }
      reverse = !reverse;
    }

    return verticalWaypoints;
  }

  List<Point> _generateHorizontalWaypoints(List<Point> polygon, bool createCameraPoints, Point previous, num minX, num maxX, num minY, num maxY) {
    num lineSpacing = footprintHeight * (1 - sideOverlap);
    num waypointSpacing = footprintWidth * (1 - forwardOverlap);
    num offset = waypointSpacing * 0.1;

    List<num> alongCoords = [];
    num adjustedMinAlong = minX - waypointSpacing / 2 - offset;
    for (num x = adjustedMinAlong; x <= maxX + waypointSpacing / 2; x += waypointSpacing) {
      alongCoords.add(x);
    }

    num yBottom = minY + lineSpacing / 2;
    List<num> xBottom = alongCoords.where((x) => _isPointInPolygon(Point(x, yBottom), polygon)).toList();
    num minDistBottom = double.infinity;
    num distLeftBottom = double.infinity;
    num distRightBottom = double.infinity;
    if (xBottom.isNotEmpty) {
      num xLeftBottom = xBottom.first;
      num xRightBottom = xBottom.last;
      distLeftBottom = sqrt(pow(previous.x - xLeftBottom, 2) + pow(previous.y - yBottom, 2));
      distRightBottom = sqrt(pow(previous.x - xRightBottom, 2) + pow(previous.y - yBottom, 2));
      minDistBottom = min(distLeftBottom, distRightBottom);
    }

    num yTop = maxY - lineSpacing / 2;
    List<num> xTop = alongCoords.where((x) => _isPointInPolygon(Point(x, yTop), polygon)).toList();
    num minDistTop = double.infinity;
    num distLeftTop = double.infinity;
    num distRightTop = double.infinity;
    if (xTop.isNotEmpty) {
      num xLeftTop = xTop.first;
      num xRightTop = xTop.last;
      distLeftTop = sqrt(pow(previous.x - xLeftTop, 2) + pow(previous.y - yTop, 2));
      distRightTop = sqrt(pow(previous.x - xRightTop, 2) + pow(previous.y - yTop, 2));
      minDistTop = min(distLeftTop, distRightTop);
    }

    num startY;
    num deltaY;
    bool reverse;
    if (minDistBottom < minDistTop) {
      startY = yBottom;
      deltaY = lineSpacing;
      reverse = distRightBottom < distLeftBottom;
    } else {
      startY = yTop;
      deltaY = -lineSpacing;
      reverse = distRightTop < distLeftTop;
    }

    List<Point> horizontalWaypoints = [];
    bool condition(num y) => deltaY > 0 ? y <= maxY + lineSpacing / 2 : y >= minY - lineSpacing / 2;
    for (num y = startY; condition(y); y += deltaY) {
      List<Point> line = [];
      for (num x in alongCoords) {
        Point p = Point(x, y);
        if (_isPointInPolygon(p, polygon)) {
          line.add(p);
        }
      }
      if (line.isEmpty) continue;

      if (reverse) line = line.reversed.toList();

      if (createCameraPoints) {
        horizontalWaypoints.addAll(line);
      } else {
        horizontalWaypoints.add(line.first);
        if (line.first != line.last) {
          horizontalWaypoints.add(line.last);
        }
      }
      reverse = !reverse;
    }

    return horizontalWaypoints;
  }

  static double calculateTotalDistance(List<LatLng> waypoints) {
    if (waypoints.length < 2) return 0.0;
    double totalDistance = 0.0;

    for (int i = 0; i < waypoints.length - 1; i++) {
      totalDistance += _haversineDistance(waypoints[i], waypoints[i + 1]);
    }

    return totalDistance;
  }

  static String calculateRecommendedShutterSpeed({
    required int altitude, // in meters
    required double sensorWidth, // in meters
    required double focalLength, // in meters
    required int imageWidth, // in pixels
    required double droneSpeed, // in meters per second (m/s)
  }) {
    // Calculate Ground Sampling Distance (GSD) in meters/pixel
    double gsd = (altitude * sensorWidth) / (imageWidth * focalLength);

    // Calculate recommended shutter speed to avoid motion blur (in seconds)
    double shutterSpeed = gsd / droneSpeed;

    // Find the closest standard speed
    double closest = _standardSpeeds.first;
    for (double speed in _standardSpeeds) {
      if ((shutterSpeed - speed).abs() < (shutterSpeed - closest).abs()) {
        closest = speed;
      }
    }

    return '1/${(1 / closest).toInt()}';
  }

  // if photo points aren't being generated then the operator will need to know
  // the photo time interval for the timelapse/hyperlapse forward overlap
  static double calculatePhotoTimeInterval({
    required int altitude,
    required double sensorHeight,
    required double focalLength,
    required int imageHeight,
    required double forwardOverlap,
    required double droneSpeed,
    int groundOffset = 0,
  }) {
    double effectiveAltitude = altitude - groundOffset.toDouble();
    double gsdY = (effectiveAltitude * sensorHeight) / (imageHeight * focalLength);
    double footprintHeight = gsdY * imageHeight;
    double spacing = footprintHeight * (1 - forwardOverlap);
    return spacing / droneSpeed;
  }

  static double _haversineDistance(LatLng p1, LatLng p2) {
    const R = 6371e3; // Earth radius in meters
    final phi1 = p1.latitudeInRad;
    final phi2 = p2.latitudeInRad;
    final deltaPhi = (p2.latitude - p1.latitude).toRadians();
    final deltaLambda = (p2.longitude - p1.longitude).toRadians();

    final a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return R * c; // Distance in meters
  }

  // ==========================================
  // CORRIDOR (LINEAR) MAPPING METHODS
  // ==========================================

  /// Calculate the total length of a polyline/centerline in meters
  static double calculatePolylineLength(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      total += _haversineDistance(points[i], points[i + 1]);
    }
    return total;
  }

  /// Calculate the total area of a corridor in square meters
  static double calculateCorridorArea(List<LatLng> centerline, double widthInMeters) {
    if (centerline.length < 2) return 0.0;
    final length = calculatePolylineLength(centerline);
    return length * widthInMeters;
  }

  /// Generates a closed buffer polygon around the centerline
  static List<LatLng> generateCorridorBufferPolygon(List<LatLng> centerline, double widthInMeters) {
    if (centerline.length < 2) return [];

    final origin = centerline[0];
    final localPoints = _latLngToMeters(centerline);
    final halfWidth = widthInMeters / 2.0;

    final n = localPoints.length;
    final leftOffsets = <Point>[];
    final rightOffsets = <Point>[];

    // Compute segment normal vectors
    final segmentNormals = <Point>[];
    for (int i = 0; i < n - 1; i++) {
      final p1 = localPoints[i];
      final p2 = localPoints[i + 1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-6) {
        segmentNormals.add(const Point(0.0, 1.0));
      } else {
        // Normal to the left of the segment
        segmentNormals.add(Point(-dy / len, dx / len));
      }
    }

    // Compute vertex offsets for left and right
    for (int i = 0; i < n; i++) {
      Point normal;
      double scale = 1.0;

      if (i == 0) {
        normal = segmentNormals[0];
      } else if (i == n - 1) {
        normal = segmentNormals[n - 2];
      } else {
        final n1 = segmentNormals[i - 1];
        final n2 = segmentNormals[i];
        final nx = n1.x + n2.x;
        final ny = n1.y + n2.y;
        final len = sqrt(nx * nx + ny * ny);
        if (len < 1e-6) {
          normal = n1;
        } else {
          normal = Point(nx / len, ny / len);
          final dot = normal.x * n1.x + normal.y * n1.y;
          if (dot > 0.3) {
            scale = (1.0 / dot).clamp(1.0, 2.5);
          }
        }
      }

      final p = localPoints[i];
      final offsetDist = halfWidth * scale;
      leftOffsets.add(Point(p.x + normal.x * offsetDist, p.y + normal.y * offsetDist));
      rightOffsets.add(Point(p.x - normal.x * offsetDist, p.y - normal.y * offsetDist));
    }

    // Closed polygon = Left side (start to end) + Right side (end to start)
    final bufferLocal = <Point>[
      ...leftOffsets,
      ...rightOffsets.reversed,
    ];

    return _metersToLatLng(bufferLocal, origin);
  }

  /// Generates waypoints for corridor linear mapping
  List<LatLng> generateCorridorWaypoints({
    required List<LatLng> centerline,
    required double corridorWidth,
    required int flightLines,
    required bool createCameraPoints,
    LatLng? homePoint,
  }) {
    if (centerline.length < 2) return [];

    final origin = centerline[0];
    final localCenterline = _latLngToMeters(centerline);
    final alongSpacing = pathSpacing > 0 ? pathSpacing : 20.0;

    final n = localCenterline.length;
    final passes = <List<Point>>[];

    // Compute segment normal vectors for offset lines
    final segmentNormals = <Point>[];
    for (int i = 0; i < n - 1; i++) {
      final p1 = localCenterline[i];
      final p2 = localCenterline[i + 1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 1e-6) {
        segmentNormals.add(const Point(0.0, 1.0));
      } else {
        segmentNormals.add(Point(-dy / len, dx / len));
      }
    }

    // Calculate vertex normals
    final vertexNormals = <Point>[];
    final vertexScales = <double>[];
    for (int i = 0; i < n; i++) {
      if (i == 0) {
        vertexNormals.add(segmentNormals[0]);
        vertexScales.add(1.0);
      } else if (i == n - 1) {
        vertexNormals.add(segmentNormals[n - 2]);
        vertexScales.add(1.0);
      } else {
        final n1 = segmentNormals[i - 1];
        final n2 = segmentNormals[i];
        final nx = n1.x + n2.x;
        final ny = n1.y + n2.y;
        final len = sqrt(nx * nx + ny * ny);
        if (len < 1e-6) {
          vertexNormals.add(n1);
          vertexScales.add(1.0);
        } else {
          final norm = Point(nx / len, ny / len);
          vertexNormals.add(norm);
          final dot = norm.x * n1.x + norm.y * n1.y;
          vertexScales.add(dot > 0.3 ? (1.0 / dot).clamp(1.0, 2.5) : 1.0);
        }
      }
    }

    // Determine offset distances for the passes
    final offsetDistances = <double>[];
    if (flightLines <= 1) {
      offsetDistances.add(0.0); // single centerline pass
    } else if (flightLines == 2) {
      final halfW = corridorWidth / 4.0;
      offsetDistances.add(-halfW);
      offsetDistances.add(halfW);
    } else {
      final step = corridorWidth / (flightLines - 1);
      final startOffset = -corridorWidth / 2.0;
      for (int i = 0; i < flightLines; i++) {
        offsetDistances.add(startOffset + i * step);
      }
    }

    // Generate each flight pass along the polyline
    for (int passIdx = 0; passIdx < offsetDistances.length; passIdx++) {
      final dist = offsetDistances[passIdx];
      final passVertices = <Point>[];

      for (int i = 0; i < n; i++) {
        final p = localCenterline[i];
        final norm = vertexNormals[i];
        final scale = vertexScales[i];
        passVertices.add(Point(p.x + norm.x * dist * scale, p.y + norm.y * dist * scale));
      }

      // If odd pass index (e.g. return pass 2), reverse direction
      final orderedVertices = passIdx % 2 == 1 ? passVertices.reversed.toList() : passVertices;

      // Subdivide segments for photo points or turn waypoints
      final passWaypoints = <Point>[];
      for (int i = 0; i < orderedVertices.length - 1; i++) {
        final p1 = orderedVertices[i];
        final p2 = orderedVertices[i + 1];
        final segDist = _distance(p1, p2);

        passWaypoints.add(p1);

        if (createCameraPoints && segDist > alongSpacing) {
          final steps = (segDist / alongSpacing).floor();
          for (int s = 1; s <= steps; s++) {
            final t = (s * alongSpacing) / segDist;
            if (t < 0.98) {
              passWaypoints.add(Point(p1.x + (p2.x - p1.x) * t, p1.y + (p2.y - p1.y) * t));
            }
          }
        }
      }
      passWaypoints.add(orderedVertices.last);
      passes.add(passWaypoints);
    }

    // Combine passes into a continuous mission trajectory
    List<Point> allWaypoints = [];
    for (final pass in passes) {
      allWaypoints.addAll(pass);
    }

    if (homePoint != null && allWaypoints.isNotEmpty) {
      final homeP = _latLngToPoint(homePoint, origin);
      final distStart = _distance(allWaypoints.first, homeP);
      final distEnd = _distance(allWaypoints.last, homeP);

      // If reversing the whole mission makes takeoff closer to home, reverse it
      if (distEnd < distStart) {
        allWaypoints = allWaypoints.reversed.toList();
      }
    }

    return _metersToLatLng(allWaypoints, origin);
  }

  static final List<double> _standardSpeeds = [
    1 / 16000,
    1 / 8000,
    1 / 6400,
    1 / 5000,
    1 / 4000,
    1 / 3200,
    1 / 2500,
    1 / 2000,
    1 / 1600,
    1 / 1250,
    1 / 1000,
    1 / 800,
    1 / 640,
    1 / 500,
    1 / 400,
    1 / 320,
    1 / 240,
    1 / 200,
    1 / 160,
    1 / 120,
    1 / 100,
    1 / 80,
    1 / 60,
    1 / 50,
    1 / 40,
    1 / 30,
    1 / 25,
    1 / 20,
    1 / 15,
    1 / 12.5,
    1 / 10,
    1 / 8,
    1 / 6.25,
    1 / 5,
    1 / 4,
    1 / 3,
    1 / 2,
  ];

  /// Generates the ground footprint polygon (4 corners) for each photo location
  List<List<LatLng>> generatePhotoFootprints(List<LatLng> photoLocations) {
    if (photoLocations.isEmpty || effectiveAltitude <= 0) return [];

    final halfW = footprintWidth / 2;
    final halfH = footprintHeight / 2;
    final rad = (angle * pi) / 180.0;
    final cosA = cos(rad);
    final sinA = sin(rad);

    // 4 local corners relative to photo center (in meters)
    final localCorners = [
      Point(-halfW, -halfH),
      Point(halfW, -halfH),
      Point(halfW, halfH),
      Point(-halfW, halfH),
    ];

    return photoLocations.map((center) {
      final originLat = center.latitude;
      final metersPerDegreeLat = 40075000.0 / 360.0;
      final metersPerDegreeLng =
          40075000.0 * cos((originLat * pi) / 180.0) / 360.0;

      return localCorners.map((corner) {
        final rx = corner.x * cosA - corner.y * sinA;
        final ry = corner.x * sinA + corner.y * cosA;

        final lat = center.latitude + (ry / metersPerDegreeLat);
        final lng = center.longitude + (rx / metersPerDegreeLng);
        return LatLng(lat, lng);
      }).toList();
    }).toList();
  }

  /// Calculate the percentage of polygon area covered by photo footprints (0% to 100%)
  double calculateCoveragePercentage({
    required List<LatLng> polygon,
    required List<LatLng> photoLocations,
  }) {
    if (polygon.length < 3 || photoLocations.isEmpty || effectiveAltitude <= 0) {
      return 0.0;
    }

    final localPoly = _latLngToMeters(polygon);
    final totalArea = calculateArea(polygon);
    if (totalArea <= 1.0) return 0.0;

    final minX = localPoly.map((p) => p.x).reduce(min).toDouble();
    final maxX = localPoly.map((p) => p.x).reduce(max).toDouble();
    final minY = localPoly.map((p) => p.y).reduce(min).toDouble();
    final maxY = localPoly.map((p) => p.y).reduce(max).toDouble();

    final width = maxX - minX;
    final height = maxY - minY;
    if (width <= 0 || height <= 0) return 0.0;

    // Sample polygon with ~25-35 grid steps on each axis
    final stepX = max(2.0, width / 30.0);
    final stepY = max(2.0, height / 30.0);

    final localPhotos = _latLngToMeters(photoLocations);
    final hw = footprintWidth / 2.0;
    final hh = footprintHeight / 2.0;
    final rad = (angle * pi) / 180.0;
    final cosA = cos(rad);
    final sinA = sin(rad);

    int totalInside = 0;
    int totalCovered = 0;

    for (double y = minY; y <= maxY; y += stepY) {
      for (double x = minX; x <= maxX; x += stepX) {
        final pt = Point(x, y);
        if (!_isPointInPolygon(pt, localPoly)) continue;

        totalInside++;

        // Check if pt is inside at least one photo footprint
        bool covered = false;
        for (final photo in localPhotos) {
          final dx = pt.x - photo.x;
          final dy = pt.y - photo.y;
          final rx = (dx * cosA + dy * sinA).abs();
          final ry = (-dx * sinA + dy * cosA).abs();

          if (rx <= hw && ry <= hh) {
            covered = true;
            break;
          }
        }
        if (covered) totalCovered++;
      }
    }

    if (totalInside == 0) return 0.0;
    final pct = (totalCovered / totalInside) * 100.0;
    return pct.clamp(0.0, 100.0);
  }
}

extension on double {
  double toRadians() => this * pi / 180;
}
