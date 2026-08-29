import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('Corridor Mapping Engine Tests', () {
    final centerline = [
      const LatLng(48.8566, 2.3522),
      const LatLng(48.8576, 2.3532),
      const LatLng(48.8586, 2.3542),
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

    test('calculatePolylineLength computes distance correctly', () {
      final length = DroneMappingEngine.calculatePolylineLength(centerline);
      expect(length, greaterThan(200));
      expect(length, lessThan(400));
    });

    test('calculateCorridorArea computes area based on length and width', () {
      final length = DroneMappingEngine.calculatePolylineLength(centerline);
      final area = DroneMappingEngine.calculateCorridorArea(centerline, 50.0);
      expect(area, closeTo(length * 50.0, 1.0));
    });

    test('generateCorridorBufferPolygon produces a closed polygon wrapping the centerline', () {
      final polygon = DroneMappingEngine.generateCorridorBufferPolygon(centerline, 40.0);
      expect(polygon.length, greaterThanOrEqualTo(centerline.length * 2));
      // First point on left, opposite point on right
      expect(polygon.first.latitude, isNot(polygon.last.latitude));
    });

    test('generateCorridorWaypoints generates 1-line centerline pass with photo triggers', () {
      final waypoints = engine.generateCorridorWaypoints(
        centerline: centerline,
        corridorWidth: 40.0,
        flightLines: 1,
        createCameraPoints: true,
      );

      expect(waypoints.isNotEmpty, true);
      expect(waypoints.length, greaterThanOrEqualTo(centerline.length));
    });

    test('generateCorridorWaypoints generates multi-line passes with correct count', () {
      final waypoints1Line = engine.generateCorridorWaypoints(
        centerline: centerline,
        corridorWidth: 80.0,
        flightLines: 1,
        createCameraPoints: true,
      );

      final waypoints2Lines = engine.generateCorridorWaypoints(
        centerline: centerline,
        corridorWidth: 80.0,
        flightLines: 2,
        createCameraPoints: true,
      );

      expect(waypoints2Lines.length, greaterThan(waypoints1Line.length));
    });

    test('generatePhotoFootprints generates 4-corner ground polygons for photo locations', () {
      final footprints = engine.generatePhotoFootprints(centerline);
      expect(footprints.length, equals(centerline.length));
      for (final footprint in footprints) {
        expect(footprint.length, equals(4));
        expect(footprint.first.latitude, isNot(footprint[2].latitude));
      }
    });
  });
}
