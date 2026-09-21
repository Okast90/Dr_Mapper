import 'package:geoxml/geoxml.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

class DroneMapperXml extends GeoXml {
  DroneMapperXml();

  @override
  String get version => "1.0";

  @override
  String get creator => "DroneMapper";

  @override
  Metadata get metadata => Metadata(
      name: "DroneMapper Mission", desc: "Mission created by DroneMapper");

  static Future<DroneMapperXml> fromKmlString(String kml) async {
    final flattenedKml = _flattenKml(kml);
    GeoXml geoXml = await GeoXml.fromKmlString(flattenedKml);
    var dmXml = DroneMapperXml();
    dmXml.polygons = geoXml.polygons;
    dmXml.rtes = geoXml.rtes;
    dmXml.trks = geoXml.trks;
    dmXml.wpts = geoXml.wpts;
    return dmXml;
  }

  static Future<DroneMapperXml> fromGpxString(String gpx) async {
    GeoXml geoXml = await GeoXml.fromGpxString(gpx);
    var dmXml = DroneMapperXml();
    dmXml.polygons = geoXml.polygons;
    dmXml.rtes = geoXml.rtes;
    dmXml.trks = geoXml.trks;
    dmXml.wpts = geoXml.wpts;
    return dmXml;
  }

  /// Extracts all playable features (tracks, routes, waypoints) from GPX content
  static Future<List<GpxFeature>> parseGpxFeatures(String gpx) async {
    final geoXml = await GeoXml.fromGpxString(gpx);
    final features = <GpxFeature>[];

    // 1. Process Tracks (<trk>)
    for (int i = 0; i < geoXml.trks.length; i++) {
      final trk = geoXml.trks[i];
      final points = <LatLng>[];
      final elevations = <double?>[];

      for (final seg in trk.trksegs) {
        for (final pt in seg.trkpts) {
          if (pt.lat != null && pt.lon != null) {
            points.add(LatLng(pt.lat!, pt.lon!));
            elevations.add(pt.ele);
          }
        }
      }

      if (points.isNotEmpty) {
        features.add(GpxFeature(
          name: trk.name?.trim().isNotEmpty == true
              ? trk.name!.trim()
              : 'Trace ${i + 1}',
          type: GpxFeatureType.track,
          points: points,
          elevations: elevations,
          description: trk.desc ?? '',
        ));
      }
    }

    // 2. Process Routes (<rte>)
    for (int i = 0; i < geoXml.rtes.length; i++) {
      final rte = geoXml.rtes[i];
      final points = <LatLng>[];
      final elevations = <double?>[];

      for (final pt in rte.rtepts) {
        if (pt.lat != null && pt.lon != null) {
          points.add(LatLng(pt.lat!, pt.lon!));
          elevations.add(pt.ele);
        }
      }

      if (points.isNotEmpty) {
        features.add(GpxFeature(
          name: rte.name?.trim().isNotEmpty == true
              ? rte.name!.trim()
              : 'Itinéraire ${i + 1}',
          type: GpxFeatureType.route,
          points: points,
          elevations: elevations,
          description: rte.desc ?? '',
        ));
      }
    }

    // 3. Process Standalone Waypoints (<wpt>)
    if (geoXml.wpts.isNotEmpty) {
      final points = <LatLng>[];
      final elevations = <double?>[];
      final names = <String>[];

      for (final pt in geoXml.wpts) {
        if (pt.lat != null && pt.lon != null) {
          points.add(LatLng(pt.lat!, pt.lon!));
          elevations.add(pt.ele);
          names.add(pt.name ?? '');
        }
      }

      if (points.isNotEmpty) {
        features.add(GpxFeature(
          name: 'Waypoints (${points.length} points)',
          type: GpxFeatureType.waypoints,
          points: points,
          elevations: elevations,
          pointNames: names,
          description: '${points.length} waypoints isolés',
        ));
      }
    }

    return features;
  }
}

enum GpxFeatureType { track, route, waypoints }

class GpxFeature {
  final String name;
  final GpxFeatureType type;
  final List<LatLng> points;
  final List<double?> elevations;
  final List<String>? pointNames;
  final String description;

  GpxFeature({
    required this.name,
    required this.type,
    required this.points,
    this.elevations = const [],
    this.pointNames,
    this.description = '',
  });

  int get pointCount => points.length;

  /// Check if the feature points form a closed polygon
  bool get isClosedLoop {
    if (points.length < 3) return false;
    final first = points.first;
    final last = points.last;
    const eps = 0.00001; // ~1 meter
    return (first.latitude - last.latitude).abs() < eps &&
        (first.longitude - last.longitude).abs() < eps;
  }
}

/// Flatten KML by removing wrappers because of bug in GeoXML parser:
/// https://github.com/sun-jiao/geoxml/issues/5
String _flattenKml(String kml) {
  final doc = XmlDocument.parse(kml);

  // Unwrap a tag but preserve its children
  void unwrapElements(String tagName) {
    for (final element in doc.findAllElements(tagName).toList()) {
      final parent = element.parent;
      if (parent != null) {
        // Create deep copies of the children before moving them
        final clonedChildren = element.children.map((c) => c.copy()).toList();

        final index = parent.children.indexOf(element);
        parent.children.replaceRange(index, index + 1, clonedChildren);
      }
    }
  }

  // Unwrap common KML wrappers
  unwrapElements('MultiGeometry');
  unwrapElements('Folder');

  return doc.toXmlString(pretty: false);
}
