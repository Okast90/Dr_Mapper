import 'dart:math';
import 'package:latlong2/latlong.dart';

/// Severity of a detected geometric issue.
enum GeometryIssueSeverity {
  /// Advisory warning (mission can proceed, but coverage/flight quality may be degraded).
  warning,

  /// Critical error (mission geometry is invalid or impossible to calculate safely).
  error,
}

/// Types of geometric issues that can be identified.
enum GeometryIssueType {
  /// Less than 3 points for a polygon or less than 2 for a corridor.
  insufficientPoints,

  /// Two or more vertices are placed at the exact same or almost identical position (< 0.5m).
  duplicatePoints,

  /// Edges cross each other (figure-8, bowtie, self-intersecting loop).
  selfIntersection,

  /// The polygon area is near zero (< 5 m²) or all points are collinear.
  collinearOrZeroArea,

  /// Extremely acute angle (< 15°) forming a narrow needle spike impossible to sweep cleanly.
  acuteNeedleSpike,

  /// Corridor path has sharp hairpin reversals (< 30° turnaround) or crosses itself.
  corridorHairpinOrCross,
}

/// A specific issue found during geometry validation.
class GeometryIssue {
  final GeometryIssueType type;
  final GeometryIssueSeverity severity;
  final String title;
  final String description;
  final LatLng? location;
  final int? vertexIndex;

  const GeometryIssue({
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    this.location,
    this.vertexIndex,
  });
}

/// Comprehensive result of geometry validation.
class GeometryValidationResult {
  final bool isValid;
  final List<GeometryIssue> issues;
  final double areaSquareMeters;
  final double perimeterMeters;
  final List<LatLng> intersectionPoints;

  const GeometryValidationResult({
    required this.isValid,
    required this.issues,
    required this.areaSquareMeters,
    required this.perimeterMeters,
    required this.intersectionPoints,
  });

  bool get hasErrors =>
      issues.any((i) => i.severity == GeometryIssueSeverity.error);

  bool get hasWarnings =>
      issues.any((i) => i.severity == GeometryIssueSeverity.warning);

  GeometryIssueSeverity get overallSeverity {
    if (hasErrors) return GeometryIssueSeverity.error;
    if (hasWarnings) return GeometryIssueSeverity.warning;
    return GeometryIssueSeverity.warning; // default when issues exist
  }

  String get summaryMessage {
    if (issues.isEmpty) {
      return 'Géométrie valide (${areaSquareMeters.toStringAsFixed(0)} m²)';
    }
    if (hasErrors) {
      final firstError =
          issues.firstWhere((i) => i.severity == GeometryIssueSeverity.error);
      return '${firstError.title} (${issues.length} problème${issues.length > 1 ? "s" : ""})';
    }
    final firstWarning = issues.first;
    return '${firstWarning.title} (${issues.length} avertissement${issues.length > 1 ? "s" : ""})';
  }
}

/// Validation and repair engine for survey polygons and corridor centerlines.
class GeometryValidator {
  static const double _earthRadius = 6378137.0; // WGS84 equatorial radius in meters

  /// Convert LatLng coordinates to local flat metric Cartesian coordinates relative to [center].
  static Point<double> _toCartesian(LatLng point, LatLng center) {
    final latRad = center.latitude * pi / 180.0;
    final dLat = (point.latitude - center.latitude) * pi / 180.0;
    final dLon = (point.longitude - center.longitude) * pi / 180.0;

    final x = dLon * cos(latRad) * _earthRadius;
    final y = dLat * _earthRadius;
    return Point<double>(x, y);
  }

  /// Convert flat Cartesian coordinates back to LatLng relative to [center].
  static LatLng _toLatLng(Point<double> p, LatLng center) {
    final latRad = center.latitude * pi / 180.0;
    final dLat = (p.y / _earthRadius) * 180.0 / pi;
    final dLon = (p.x / (_earthRadius * cos(latRad))) * 180.0 / pi;
    return LatLng(center.latitude + dLat, center.longitude + dLon);
  }

  /// Calculate polygon centroid.
  static LatLng _computeCentroid(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    double sumLat = 0.0;
    double sumLon = 0.0;
    for (final p in points) {
      sumLat += p.latitude;
      sumLon += p.longitude;
    }
    return LatLng(sumLat / points.length, sumLon / points.length);
  }

  /// Validates a survey polygon for Grid mapping.
  static GeometryValidationResult validatePolygon(List<LatLng> points) {
    final issues = <GeometryIssue>[];
    final intersectionPoints = <LatLng>[];

    if (points.length < 3) {
      issues.add(GeometryIssue(
        type: GeometryIssueType.insufficientPoints,
        severity: GeometryIssueSeverity.error,
        title: 'Sommets insuffisants',
        description: 'Un polygone de mission doit comporter au moins 3 points distincts.',
        location: points.isNotEmpty ? points.first : null,
      ));
      return GeometryValidationResult(
        isValid: false,
        issues: issues,
        areaSquareMeters: 0.0,
        perimeterMeters: 0.0,
        intersectionPoints: [],
      );
    }

    final center = _computeCentroid(points);
    final localPoints = points.map((p) => _toCartesian(p, center)).toList();
    final n = localPoints.length;

    // 1. Check for duplicate or micro-distance points (< 0.5m)
    for (int i = 0; i < n; i++) {
      final p1 = localPoints[i];
      final p2 = localPoints[(i + 1) % n];
      final dist = p1.distanceTo(p2);
      if (dist < 0.5) {
        issues.add(GeometryIssue(
          type: GeometryIssueType.duplicatePoints,
          severity: GeometryIssueSeverity.warning,
          title: 'Sommets trop rapprochés',
          description: 'Les points ${i + 1} et ${(i + 1) % n + 1} sont espacés de moins de 0.5 m (${dist.toStringAsFixed(2)} m).',
          location: points[i],
          vertexIndex: i,
        ));
      }
    }

    // 2. Check for self-intersections (edges crossing each other)
    for (int i = 0; i < n; i++) {
      final a1 = localPoints[i];
      final a2 = localPoints[(i + 1) % n];

      // Test against other segments that do not share a vertex with segment i
      for (int j = i + 1; j < n; j++) {
        // Skip adjacent edges and closing edge
        if (j == i || (j + 1) % n == i || (i + 1) % n == j) continue;

        final b1 = localPoints[j];
        final b2 = localPoints[(j + 1) % n];

        final inter = _findSegmentIntersection(a1, a2, b1, b2);
        if (inter != null) {
          final interLatLng = _toLatLng(inter, center);
          intersectionPoints.add(interLatLng);
          issues.add(GeometryIssue(
            type: GeometryIssueType.selfIntersection,
            severity: GeometryIssueSeverity.error,
            title: 'Arêtes auto-sécantes (Croisement)',
            description: 'Les segments [${i + 1}-${(i + 1) % n + 1}] et [${j + 1}-${(j + 1) % n + 1}] se croisent. La forme est impossible à balayer.',
            location: interLatLng,
            vertexIndex: i,
          ));
        }
      }
    }

    // 3. Compute metric Area (Shoelace) and Perimeter
    double signedArea = 0.0;
    double perimeter = 0.0;
    for (int i = 0; i < n; i++) {
      final p1 = localPoints[i];
      final p2 = localPoints[(i + 1) % n];
      signedArea += (p1.x * p2.y - p2.x * p1.y);
      perimeter += p1.distanceTo(p2);
    }
    final area = (signedArea.abs() / 2.0);

    // Check collinearity / near zero area
    if (area < 5.0) {
      issues.add(GeometryIssue(
        type: GeometryIssueType.collinearOrZeroArea,
        severity: GeometryIssueSeverity.error,
        title: 'Surface quasi-nulle ou points alignés',
        description: 'La surface calculée est de ${area.toStringAsFixed(1)} m². Les sommets sont probablement alignés.',
        location: points.first,
      ));
    }

    // 4. Check for extreme acute needle spikes (< 15°)
    for (int i = 0; i < n; i++) {
      final prev = localPoints[(i - 1 + n) % n];
      final curr = localPoints[i];
      final next = localPoints[(i + 1) % n];

      final v1 = Point<double>(prev.x - curr.x, prev.y - curr.y);
      final v2 = Point<double>(next.x - curr.x, next.y - curr.y);

      final len1 = sqrt(v1.x * v1.x + v1.y * v1.y);
      final len2 = sqrt(v2.x * v2.x + v2.y * v2.y);

      if (len1 > 1.0 && len2 > 1.0) {
        final dot = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2);
        final clampedDot = dot.clamp(-1.0, 1.0);
        final angleDeg = acos(clampedDot) * 180.0 / pi;

        if (angleDeg < 15.0) {
          issues.add(GeometryIssue(
            type: GeometryIssueType.acuteNeedleSpike,
            severity: GeometryIssueSeverity.warning,
            title: 'Angle ultra-aigu en pointe (${angleDeg.toStringAsFixed(1)}°)',
            description: 'Le sommet ${i + 1} forme une pointe trop étroite (< 15°) pour assurer un virage et une couverture drone conformes.',
            location: points[i],
            vertexIndex: i,
          ));
        }
      }
    }

    final isValid = !issues.any((i) => i.severity == GeometryIssueSeverity.error);

    return GeometryValidationResult(
      isValid: isValid,
      issues: issues,
      areaSquareMeters: area,
      perimeterMeters: perimeter,
      intersectionPoints: intersectionPoints,
    );
  }

  /// Validates a Corridor centerline.
  static GeometryValidationResult validateCorridor(List<LatLng> centerline) {
    final issues = <GeometryIssue>[];
    final intersectionPoints = <LatLng>[];

    if (centerline.length < 2) {
      issues.add(GeometryIssue(
        type: GeometryIssueType.insufficientPoints,
        severity: GeometryIssueSeverity.error,
        title: 'Tracé insuffisant',
        description: 'Le corridor doit comporter au moins 2 points de tracé.',
        location: centerline.isNotEmpty ? centerline.first : null,
      ));
      return GeometryValidationResult(
        isValid: false,
        issues: issues,
        areaSquareMeters: 0.0,
        perimeterMeters: 0.0,
        intersectionPoints: [],
      );
    }

    final center = _computeCentroid(centerline);
    final localPoints = centerline.map((p) => _toCartesian(p, center)).toList();
    final n = localPoints.length;

    // 1. Duplicate points
    for (int i = 0; i < n - 1; i++) {
      final dist = localPoints[i].distanceTo(localPoints[i + 1]);
      if (dist < 0.5) {
        issues.add(GeometryIssue(
          type: GeometryIssueType.duplicatePoints,
          severity: GeometryIssueSeverity.warning,
          title: 'Points consécutifs trop rapprochés',
          description: 'Les points ${i + 1} et ${i + 2} sont espacés de moins de 0.5 m.',
          location: centerline[i],
          vertexIndex: i,
        ));
      }
    }

    // 2. Self-intersections along the line
    for (int i = 0; i < n - 1; i++) {
      final a1 = localPoints[i];
      final a2 = localPoints[i + 1];

      for (int j = i + 2; j < n - 1; j++) {
        final b1 = localPoints[j];
        final b2 = localPoints[j + 1];

        final inter = _findSegmentIntersection(a1, a2, b1, b2);
        if (inter != null) {
          final interLatLng = _toLatLng(inter, center);
          intersectionPoints.add(interLatLng);
          issues.add(GeometryIssue(
            type: GeometryIssueType.corridorHairpinOrCross,
            severity: GeometryIssueSeverity.error,
            title: 'Croisement de tracé corridor',
            description: 'Le tracé se croise lui-même entre les segments [${i + 1}-${i + 2}] et [${j + 1}-${j + 2}].',
            location: interLatLng,
            vertexIndex: i,
          ));
        }
      }
    }

    // 3. Hairpin turns (< 30° interior turn / > 150° deflection)
    for (int i = 1; i < n - 1; i++) {
      final prev = localPoints[i - 1];
      final curr = localPoints[i];
      final next = localPoints[i + 1];

      final v1 = Point<double>(curr.x - prev.x, curr.y - prev.y);
      final v2 = Point<double>(next.x - curr.x, next.y - curr.y);

      final len1 = sqrt(v1.x * v1.x + v1.y * v1.y);
      final len2 = sqrt(v2.x * v2.x + v2.y * v2.y);

      if (len1 > 1.0 && len2 > 1.0) {
        final dot = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2);
        final clampedDot = dot.clamp(-1.0, 1.0);
        final angleDeg = acos(clampedDot) * 180.0 / pi; // 0° is straight, 180° is full reversal

        if (angleDeg > 150.0) {
          issues.add(GeometryIssue(
            type: GeometryIssueType.corridorHairpinOrCross,
            severity: GeometryIssueSeverity.warning,
            title: 'Demi-tour trop serré au point ${i + 1}',
            description: 'Virage à ${(180.0 - angleDeg).toStringAsFixed(1)}° : risque de collision de buffer ou d\'instabilité de virage drone.',
            location: centerline[i],
            vertexIndex: i,
          ));
        }
      }
    }

    // Calculate length
    double totalLength = 0.0;
    for (int i = 0; i < n - 1; i++) {
      totalLength += localPoints[i].distanceTo(localPoints[i + 1]);
    }

    final isValid = !issues.any((i) => i.severity == GeometryIssueSeverity.error);

    return GeometryValidationResult(
      isValid: isValid,
      issues: issues,
      areaSquareMeters: 0.0,
      perimeterMeters: totalLength,
      intersectionPoints: intersectionPoints,
    );
  }

  /// Finds the intersection point between segment [p1]-[p2] and [p3]-[p4] strictly on both segments.
  static Point<double>? _findSegmentIntersection(
    Point<double> p1,
    Point<double> p2,
    Point<double> p3,
    Point<double> p4,
  ) {
    final d1x = p2.x - p1.x;
    final d1y = p2.y - p1.y;
    final d2x = p4.x - p3.x;
    final d2y = p4.y - p3.y;

    final denom = d1x * d2y - d1y * d2x;
    if (denom.abs() < 1e-11) return null; // Parallel or collinear

    final t = ((p3.x - p1.x) * d2y - (p3.y - p1.y) * d2x) / denom;
    final u = ((p3.x - p1.x) * d1y - (p3.y - p1.y) * d1x) / denom;

    // Strict intersection within [0.001, 0.999] to avoid shared vertex false-positives
    if (t > 0.001 && t < 0.999 && u > 0.001 && u < 0.999) {
      return Point<double>(p1.x + t * d1x, p1.y + t * d1y);
    }
    return null;
  }

  /// Automatically repairs a polygon by:
  /// 1. Removing duplicate/micro-distance points (< 0.5m)
  /// 2. If self-intersections or extreme spikes exist, reconstructing a clean Convex Hull or uncrossed simple contour.
  static List<LatLng> repairPolygon(List<LatLng> points) {
    if (points.length < 3) return List<LatLng>.from(points);

    // 1. Remove duplicate/close points
    final cleaned = <LatLng>[];
    const distance = Distance();
    for (int i = 0; i < points.length; i++) {
      final curr = points[i];
      if (cleaned.isEmpty) {
        cleaned.add(curr);
      } else {
        final dist = distance.as(LengthUnit.Meter, cleaned.last, curr);
        if (dist >= 0.5) {
          cleaned.add(curr);
        }
      }
    }
    if (cleaned.length >= 2) {
      final wrapDist = distance.as(LengthUnit.Meter, cleaned.first, cleaned.last);
      if (wrapDist < 0.5) {
        cleaned.removeLast();
      }
    }

    if (cleaned.length < 3) return cleaned;

    // Check if cleaned is already valid
    final val = validatePolygon(cleaned);
    if (val.isValid && !val.hasWarnings) {
      return cleaned;
    }

    // If there are self-intersections or errors, build the 2D Monotone Chain Convex Hull
    return _computeConvexHull(cleaned);
  }

  /// Computes the 2D Convex Hull of [points] using Monotone Chain (Andrew's algorithm).
  static List<LatLng> _computeConvexHull(List<LatLng> points) {
    if (points.length <= 3) return points;

    final center = _computeCentroid(points);
    final pts = points.map((p) => _toCartesian(p, center)).toList();

    // Sort points lexicographically by x, then y
    pts.sort((a, b) {
      if (a.x != b.x) return a.x.compareTo(b.x);
      return a.y.compareTo(b.y);
    });

    double crossProduct(Point<double> o, Point<double> a, Point<double> b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final lower = <Point<double>>[];
    for (final p in pts) {
      while (lower.length >= 2 &&
          crossProduct(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <Point<double>>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 &&
          crossProduct(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    final hullCartesian = [...lower, ...upper];

    return hullCartesian.map((p) => _toLatLng(p, center)).toList();
  }

  /// Automatically repairs a corridor centerline by removing duplicate/close points and loops.
  static List<LatLng> repairCorridor(List<LatLng> centerline) {
    if (centerline.length < 2) return List<LatLng>.from(centerline);

    final cleaned = <LatLng>[];
    const distance = Distance();
    for (int i = 0; i < centerline.length; i++) {
      final curr = centerline[i];
      if (cleaned.isEmpty) {
        cleaned.add(curr);
      } else {
        final dist = distance.as(LengthUnit.Meter, cleaned.last, curr);
        if (dist >= 0.5) {
          cleaned.add(curr);
        }
      }
    }
    return cleaned;
  }

  /// Simplifies a polygon using Ramer-Douglas-Peucker algorithm with a metric tolerance.
  static List<LatLng> simplifyPolygon(List<LatLng> points, {double toleranceMeters = 1.0}) {
    if (points.length <= 3) return List<LatLng>.from(points);

    final center = _computeCentroid(points);
    final pts = points.map((p) => _toCartesian(p, center)).toList();

    List<Point<double>> rdp(List<Point<double>> list, double epsilon) {
      if (list.length <= 2) return list;

      double maxDist = 0.0;
      int index = 0;
      final start = list.first;
      final end = list.last;

      for (int i = 1; i < list.length - 1; i++) {
        final p = list[i];
        final num = ((end.y - start.y) * p.x - (end.x - start.x) * p.y + end.x * start.y - end.y * start.x).abs();
        final den = sqrt(pow(end.y - start.y, 2) + pow(end.x - start.x, 2));
        final dist = den == 0 ? start.distanceTo(p) : num / den;
        if (dist > maxDist) {
          maxDist = dist;
          index = i;
        }
      }

      if (maxDist > epsilon) {
        final rec1 = rdp(list.sublist(0, index + 1), epsilon);
        final rec2 = rdp(list.sublist(index), epsilon);
        return [...rec1.sublist(0, rec1.length - 1), ...rec2];
      } else {
        return [start, end];
      }
    }

    final simplifiedCartesian = rdp(pts, toleranceMeters);
    if (simplifiedCartesian.length < 3) return points;
    return simplifiedCartesian.map((p) => _toLatLng(p, center)).toList();
  }

  /// Generates a circle approximation of [radiusMeters] around [center].
  static List<LatLng> generateCirclePoints(LatLng center, double radiusMeters, {int pointsCount = 36}) {
    final points = <LatLng>[];
    for (int i = 0; i < pointsCount; i++) {
      final angle = 2 * pi * i / pointsCount;
      final dx = radiusMeters * cos(angle);
      final dy = radiusMeters * sin(angle);
      points.add(_toLatLng(Point<double>(dx, dy), center));
    }
    return points;
  }

  /// Formats GPS coordinates to standard DMS (Degrees Minutes Seconds) string.
  static String formatCoordinatesDMS(LatLng point) {
    String formatDms(double val, bool isLat) {
      final dir = isLat ? (val >= 0 ? 'N' : 'S') : (val >= 0 ? 'E' : 'O');
      final absVal = val.abs();
      final deg = absVal.floor();
      final minVal = (absVal - deg) * 60;
      final min = minVal.floor();
      final sec = ((minVal - min) * 60).toStringAsFixed(1);
      return '$deg° $min\' $sec" $dir';
    }

    return '${formatDms(point.latitude, true)}, ${formatDms(point.longitude, false)}';
  }

  /// Orthogonalizes nearly orthogonal polygon angles to sharp 90° corners.
  static List<LatLng> orthogonalizePolygon(List<LatLng> points) {
    if (points.length < 3) return List<LatLng>.from(points);

    final result = <LatLng>[];
    for (int i = 0; i < points.length; i++) {
      final previous = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];

      final horizontalBias =
          (next.longitude - previous.longitude).abs() >=
              (next.latitude - previous.latitude).abs();

      if (horizontalBias) {
        result.add(LatLng(current.latitude, (previous.longitude + next.longitude) / 2));
      } else {
        result.add(LatLng((previous.latitude + next.latitude) / 2, current.longitude));
      }
    }

    return result;
  }

  /// Straightens zigzag variations along collinear sections.
  static List<LatLng> straightenPolygon(List<LatLng> points) {
    if (points.length < 3) return List<LatLng>.from(points);

    final result = <LatLng>[];
    for (int i = 0; i < points.length; i++) {
      final previous = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];

      final latDelta = (next.latitude - previous.latitude).abs();
      final lonDelta = (next.longitude - previous.longitude).abs();

      if (lonDelta >= latDelta) {
        result.add(LatLng(current.latitude, (previous.longitude + next.longitude) / 2));
      } else {
        result.add(LatLng((previous.latitude + next.latitude) / 2, current.longitude));
      }
    }

    return result;
  }
}
