import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dji_waypoint_engine/engine.dart';

/// Modèle simple d'un point GPS (adaptez avec votre propre modèle d'altitude/coordonnées si nécessaire)
class Waypoint {
  final double latitude;
  final double longitude;
  final double altitude;

  Waypoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
  });
}

class KMZExporter {
  /// Génère le contenu texte du fichier KML
  static String generateKML({
    required String missionName,
    required List<Waypoint> waypoints,
  }) {
    final coordinatesString = waypoints
        .map((wp) => '${wp.longitude},${wp.latitude},${wp.altitude}')
        .join(' ');

    final placemarkNodes = waypoints.asMap().entries.map((entry) {
      final index = entry.key;
      final wp = entry.value;
      return '''
    <Placemark>
      <name>Waypoint ${index + 1}</name>
      <Point>
        <altitudeMode>relativeToGround</altitudeMode>
        <coordinates>${wp.longitude},${wp.latitude},${wp.altitude}</coordinates>
      </Point>
    </Placemark>''';
    }).join('\n');

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>$missionName</name>
    <description>Mission de vol générée par YMapper</description>

    <Style id="flightPathStyle">
      <LineStyle>
        <color>ff0000ff</color>
        <width>3</width>
      </LineStyle>
    </Style>

    <Placemark>
      <name>Trajectoire du vol</name>
      <styleUrl>#flightPathStyle</styleUrl>
      <LineString>
        <extrude>1</extrude>
        <tessellate>1</tessellate>
        <altitudeMode>relativeToGround</altitudeMode>
        <coordinates>
          $coordinatesString
        </coordinates>
      </LineString>
    </Placemark>

    $placemarkNodes

  </Document>
</kml>''';
  }

  static Uint8List generateDjiKmzBytes({
    required TemplateKml template,
    required WaylinesWpml waylines,
  }) {
    final templateString = template.toXmlString(pretty: true);
    final waylinesString = waylines.toXmlString(pretty: true);

    final archive = Archive();
    archive.addFile(
      ArchiveFile('template.kml', templateString.length, utf8.encode(templateString)),
    );
    archive.addFile(
      ArchiveFile('waylines.wpml', waylinesString.length, utf8.encode(waylinesString)),
    );

    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception('Erreur lors de la compression KMZ');
    }

    return Uint8List.fromList(zipData);
  }

  /// Exporte la mission vers un fichier .kmz
  static Future<File> exportToKMZ({
    required String missionName,
    required List<Waypoint> waypoints,
    required String outputPath,
  }) async {
    final kmlContent = generateKML(
      missionName: missionName,
      waypoints: waypoints,
    );

    final kmlBytes = utf8.encode(kmlContent);

    final archive = Archive();
    archive.addFile(ArchiveFile('doc.kml', kmlBytes.length, kmlBytes));

    final kmzBytes = ZipEncoder().encode(archive);
    if (kmzBytes == null) {
      throw Exception('Erreur lors de la compression KMZ');
    }

    final file = File('$outputPath/$missionName.kmz');
    return file.writeAsBytes(kmzBytes);
  }
}
