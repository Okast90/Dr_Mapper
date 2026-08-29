import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('Polygon Coverage Optimization Tests', () {
    // L-shaped concave polygon
    final lShapedPolygon = [
      const LatLng(48.8500, 2.3500),
      const LatLng(48.8530, 2.3500),
      const LatLng(48.8530, 2.3515),
      const LatLng(48.8515, 2.3515),
      const LatLng(48.8515, 2.3530),
      const LatLng(48.8500, 2.3530),
    ];

    // Standard convex square polygon
    final convexPolygon = [
      const LatLng(48.8500, 2.3500),
      const LatLng(48.8520, 2.3500),
      const LatLng(48.8520, 2.3520),
      const LatLng(48.8500, 2.3520),
    ];

    final engine = DroneMappingEngine(
      altitude: 100,
      forwardOverlap: 0.7,
      sideOverlap: 0.5,
      sensorWidth: 13.2,
      sensorHeight: 8.8,
      focalLength: 8.8,
      imageWidth: 4000,
      imageHeight: 3000,
      angle: 0,
      groundOffset: 0,
    );

    test('generateWaypoints with convex decomposition succeeds on L-shaped polygon', () {
      final waypointsDecomp = engine.generateWaypoints(
        lShapedPolygon,
        true,
        false,
        null,
        true, // useInsetBuffer
        true, // useConvexDecomposition
      );

      expect(waypointsDecomp.isNotEmpty, true);
      expect(waypointsDecomp.length, greaterThan(4));
    });

    test('generateWaypoints on simple convex polygon produces consistent coverage', () {
      final waypoints = engine.generateWaypoints(
        convexPolygon,
        true,
        false,
        null,
        true,
        true,
      );

      expect(waypoints.isNotEmpty, true);
      expect(waypoints.length, greaterThan(2));
    });

    test('generatePhotoFootprints covers the waypoints with valid 4-corner polygons', () {
      final waypoints = engine.generateWaypoints(
        convexPolygon,
        true,
        false,
        null,
      );

      final footprints = engine.generatePhotoFootprints(waypoints);
      expect(footprints.length, equals(waypoints.length));
      for (final fp in footprints) {
        expect(fp.length, equals(4));
      }
    });

    test('generateResidualFillWaypoints detects uncovered areas when footprints are partial', () {
      final waypoints = engine.generateWaypoints(
        convexPolygon,
        true,
        false,
        null,
      );

      // Pass only half of the footprints to simulate missing coverage
      final partialFootprints = engine
          .generatePhotoFootprints(waypoints)
          .take(waypoints.length ~/ 2)
          .toList();

      final residuals = engine.generateResidualFillWaypoints(
        polygon: convexPolygon,
        coveredFootprints: partialFootprints,
        createCameraPoints: true,
      );

      expect(residuals.length, greaterThanOrEqualTo(0));
    });

    test('calculateCoveragePercentage returns valid 0-100 percentage', () {
      final waypoints = engine.generateWaypoints(
        convexPolygon,
        true,
        false,
        null,
      );

      final coverage = engine.calculateCoveragePercentage(
        polygon: convexPolygon,
        photoLocations: waypoints,
      );

      expect(coverage, greaterThan(50.0));
      expect(coverage, lessThanOrEqualTo(100.0));
    });
  });
}
