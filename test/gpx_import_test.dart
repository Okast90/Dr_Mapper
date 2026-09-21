import 'package:dji_mapper/core/drone_mapper_format.dart';
import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('GPX Import & Waypoint Flight Plan Tests', () {
    const sampleGpxTrack = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="DJI-Mapper Test" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Mission Inspection Ligne</name>
    <desc>Trace le long d'une infrastructure</desc>
    <trkseg>
      <trkpt lat="48.8566" lon="2.3522">
        <ele>120.5</ele>
        <time>2026-09-21T10:00:00Z</time>
      </trkpt>
      <trkpt lat="48.8576" lon="2.3532">
        <ele>125.0</ele>
        <time>2026-09-21T10:01:00Z</time>
      </trkpt>
      <trkpt lat="48.8586" lon="2.3542">
        <ele>130.0</ele>
        <time>2026-09-21T10:02:00Z</time>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

    const sampleGpxRoute = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="DJI-Mapper Test" xmlns="http://www.topografix.com/GPX/1/1">
  <rte>
    <name>Itinéraire Survey</name>
    <rtept lat="43.6047" lon="1.4442">
      <ele>150.0</ele>
      <name>Point A</name>
    </rtept>
    <rtept lat="43.6057" lon="1.4452">
      <ele>155.0</ele>
      <name>Point B</name>
    </rtept>
  </rte>
</gpx>''';

    const sampleGpxWaypoints = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="DJI-Mapper Test" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="45.7640" lon="4.8357">
    <ele>200.0</ele>
    <name>Pylone 1</name>
  </wpt>
  <wpt lat="45.7650" lon="4.8367">
    <ele>205.0</ele>
    <name>Pylone 2</name>
  </wpt>
  <wpt lat="45.7660" lon="4.8377">
    <ele>210.0</ele>
    <name>Pylone 3</name>
  </wpt>
</gpx>''';

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

    test('parseGpxFeatures extracts track points, elevations and name correctly', () async {
      final features = await DroneMapperXml.parseGpxFeatures(sampleGpxTrack);
      expect(features.length, equals(1));

      final track = features.first;
      expect(track.name, equals('Mission Inspection Ligne'));
      expect(track.type, equals(GpxFeatureType.track));
      expect(track.pointCount, equals(3));
      expect(track.points.first.latitude, closeTo(48.8566, 0.0001));
      expect(track.points.last.longitude, closeTo(2.3542, 0.0001));
      expect(track.elevations.first, equals(120.5));
    });

    test('parseGpxFeatures extracts routes correctly', () async {
      final features = await DroneMapperXml.parseGpxFeatures(sampleGpxRoute);
      expect(features.length, equals(1));

      final route = features.first;
      expect(route.name, equals('Itinéraire Survey'));
      expect(route.type, equals(GpxFeatureType.route));
      expect(route.pointCount, equals(2));
      expect(route.points.first.latitude, closeTo(43.6047, 0.0001));
    });

    test('parseGpxFeatures extracts standalone waypoints correctly', () async {
      final features = await DroneMapperXml.parseGpxFeatures(sampleGpxWaypoints);
      expect(features.length, equals(1));

      final wpts = features.first;
      expect(wpts.type, equals(GpxFeatureType.waypoints));
      expect(wpts.pointCount, equals(3));
      expect(wpts.pointNames?.first, equals('Pylone 1'));
    });

    test('generateDirectWaypoints preserves points and optimizes takeoff with homePoint', () {
      final points = [
        const LatLng(48.8566, 2.3522),
        const LatLng(48.8576, 2.3532),
        const LatLng(48.8586, 2.3542),
      ];

      // Home point is close to the start (points[0])
      final homeNearStart = const LatLng(48.8565, 2.3521);
      final directResult = engine.generateDirectWaypoints(
        waypoints: points,
        createCameraPoints: true,
        homePoint: homeNearStart,
      );

      expect(directResult.length, equals(3));
      expect(directResult.first.latitude, closeTo(48.8566, 0.0001));

      // Home point is close to the end (points[2]) -> should reverse to minimize takeoff distance
      final homeNearEnd = const LatLng(48.8587, 2.3543);
      final reversedResult = engine.generateDirectWaypoints(
        waypoints: points,
        createCameraPoints: true,
        homePoint: homeNearEnd,
      );

      expect(reversedResult.first.latitude, closeTo(48.8586, 0.0001));
      expect(reversedResult.last.latitude, closeTo(48.8566, 0.0001));
    });

    test('DroneMapperXml fromGpxString loads waypoints and tracks', () async {
      final dmXml = await DroneMapperXml.fromGpxString(sampleGpxTrack);
      expect(dmXml.trks.length, equals(1));
      expect(dmXml.trks.first.trksegs.first.trkpts.length, equals(3));
    });
  });
}
