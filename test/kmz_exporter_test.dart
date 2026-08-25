import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dji_mapper/core/drone_mapper_format.dart';
import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:dji_mapper/services/kmz_exporter.dart';
import 'package:dji_waypoint_engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('KMZ exporter creates a DJI-compatible archive with template.kml and waylines.wpml', () async {
    final missionConfig = MissionConfig(
      flyToWaylineMode: FlyToWaylineMode.safely,
      finishAction: FinishAction.autoLand,
      exitOnRCLost: ExitOnRCLost.executeLostAction,
      rcLostAction: RCLostAction.goBack,
      globalTransitionalSpeed: 5.0,
      droneInfo: DroneInfo(droneEnumValue: 68),
    );

    final template = TemplateKml(
      document: KmlDocumentElement(
        author: 'fly',
        creationTime: DateTime.now(),
        modificationTime: DateTime.now(),
        missionConfig: missionConfig,
      ),
    );

    final waylines = WaylinesWpml(
      document: WpmlDocumentElement(
        missionConfig: missionConfig,
        folderElement: FolderElement(
          templateId: 0,
          waylineId: 0,
          speed: 5,
          placemarks: [
            Placemark(
              point: WaypointPoint(longitude: 12.5, latitude: 45.7),
              index: 0,
              height: 20,
              speed: 8,
              headingParam: HeadingParam(
                headingMode: HeadingMode.fixed,
                headingPathMode: HeadingPathMode.clockwise,
              ),
              turnParam: TurnParam(
                waypointTurnMode: WaypointTurnMode.toPointAndPassWithContinuityCurvature,
                turnDampingDistance: 0,
              ),
              useStraightLine: true,
            )
          ],
        ),
      ),
    );

    final bytes = KMZExporter.generateDjiKmzBytes(template: template, waylines: waylines);
    final archive = ZipDecoder().decodeBytes(bytes);

    expect(archive.files.map((f) => f.name).toList(), containsAll(['template.kml', 'waylines.wpml']));
    expect(archive.files.map((f) => f.name).toList(), isNot(contains('doc.kml')));

    final outputFile = File('${Directory.systemTemp.path}/dji-mapper-kmz-test.kmz');
    await outputFile.writeAsBytes(bytes);
    expect(outputFile.existsSync(), isTrue);
    await outputFile.delete();
  });

  test('KMZ exporter stores a valid KML document for a simple mission', () {
    final kml = KMZExporter.generateKML(
      missionName: 'mission',
      waypoints: [
        Waypoint(latitude: 42.0, longitude: 3.0, altitude: 10),
        Waypoint(latitude: 42.1, longitude: 3.1, altitude: 12),
      ],
    );

    expect(kml, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
    expect(kml, contains('Waypoint 1'));
    expect(kml, contains('42.0'));
  });

  test('fill-grid waypoint generation does not crash on an empty path scenario', () {
    final engine = DroneMappingEngine(
      altitude: 80,
      forwardOverlap: 0.6,
      sideOverlap: 0.4,
      sensorWidth: 13.2,
      sensorHeight: 8.8,
      focalLength: 8.8,
      imageWidth: 4000,
      imageHeight: 3000,
      angle: 0,
      groundOffset: 0,
    );

    final polygon = [
      const LatLng(48.8566, 2.3522),
      const LatLng(48.8566, 2.3528),
      const LatLng(48.8566, 2.3534),
    ];

    final homePoint = const LatLng(48.8568, 2.3529);

    expect(
      () => engine.generateWaypoints(polygon, false, true, homePoint),
      returnsNormally,
    );

    final waypoints = engine.generateWaypoints(polygon, false, true, homePoint);
    expect(waypoints, isEmpty);
  });

  test('drawn polygon keeps valid geographic coordinates through normalization, mission generation and KML export', () async {
    final polygon = [
      const LatLng(48.8566, 2.3522),
      const LatLng(48.8567, 2.3531),
      const LatLng(48.8571, 2.3527),
      const LatLng(48.8569, 2.3523),
    ];

    final normalized = polygon
        .map((point) => LatLng(
              point.latitude.clamp(-90.0, 90.0),
              point.longitude.clamp(-180.0, 180.0),
            ))
        .toList();

    expect(normalized.every((point) => point.latitude.isFinite && point.longitude.isFinite), isTrue);
    expect(normalized.every((point) => point.latitude >= -90 && point.latitude <= 90), isTrue);
    expect(normalized.every((point) => point.longitude >= -180 && point.longitude <= 180), isTrue);

    final engine = DroneMappingEngine(
      altitude: 80,
      forwardOverlap: 0.6,
      sideOverlap: 0.4,
      sensorWidth: 13.2,
      sensorHeight: 8.8,
      focalLength: 8.8,
      imageWidth: 4000,
      imageHeight: 3000,
      angle: 0,
      groundOffset: 0,
    );

    final homePoint = const LatLng(48.8568, 2.3528);
    final missionWaypoints = engine.generateWaypoints(normalized, true, false, homePoint);

    expect(missionWaypoints, isNotEmpty);
    expect(missionWaypoints.every((point) => point.latitude.isFinite && point.longitude.isFinite), isTrue);
    expect(missionWaypoints.every((point) => point.latitude >= -90 && point.latitude <= 90), isTrue);
    expect(missionWaypoints.every((point) => point.longitude >= -180 && point.longitude <= 180), isTrue);

    final polygonKml = '''
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Mapping Area</name>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              2.3522,48.8566,0 2.3531,48.8567,0 2.3527,48.8571,0 2.3523,48.8569,0 2.3522,48.8566,0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
  </Document>
</kml>
''';

    final parsed = await DroneMapperXml.fromKmlString(polygonKml);
    expect(parsed.polygons, isNotEmpty);
    expect(parsed.polygons.first.outerBoundaryIs.rtepts, isNotEmpty);
    expect(parsed.polygons.first.outerBoundaryIs.rtepts.first.lat, closeTo(48.8566, 1e-6));
    expect(parsed.polygons.first.outerBoundaryIs.rtepts.first.lon, closeTo(2.3522, 1e-6));

    final missionKml = KMZExporter.generateKML(
      missionName: 'mission-check',
      waypoints: missionWaypoints
          .map((point) => Waypoint(latitude: point.latitude, longitude: point.longitude, altitude: 80))
          .toList(),
    );

    expect(missionKml, contains('<kml xmlns="http://www.opengis.net/kml/2.2">'));
    expect(missionKml, contains('mission-check'));
  });
}
