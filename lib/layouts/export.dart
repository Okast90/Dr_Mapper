import 'package:dji_mapper/core/drone_mapper_format.dart';
import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:dji_mapper/shared/map_provider.dart';
import 'package:flutter_map/flutter_map.dart' hide Polygon;
import 'package:geoxml/geoxml.dart';
import 'package:latlong2/latlong.dart';
import 'package:universal_io/io.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dji_mapper/components/popups/dji_load_alert.dart';
import 'package:dji_mapper/components/popups/litchi_load_alert.dart';
import 'package:dji_mapper/main.dart';
import 'package:dji_mapper/services/kmz_exporter.dart';
import 'package:litchi_waypoint_engine/engine.dart' as litchi;
import 'package:archive/archive.dart';
import 'package:dji_waypoint_engine/engine.dart';
import 'package:dji_mapper/shared/value_listeneables.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Action;
import 'package:provider/provider.dart';
import 'dart:html' as html;

class ExportBar extends StatefulWidget {
  const ExportBar({super.key});

  @override
  State<ExportBar> createState() => ExportBarState();
}

class ExportBarState extends State<ExportBar> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<String?> _promptForExportFilename({
    required String defaultName,
    required String extension,
    required String title,
  }) async {
    final controller = TextEditingController(
      text: defaultName.endsWith('.$extension')
          ? defaultName.replaceFirst(RegExp(r'\.$extension$'), '')
          : defaultName,
    );

    final chosenName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Nom du fichier',
              hintText: 'mission',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final rawName = controller.text.trim();
                if (rawName.isEmpty) {
                  Navigator.of(context).pop();
                  return;
                }
                final safeName = rawName.endsWith('.$extension')
                    ? rawName
                    : '$rawName.$extension';
                Navigator.of(context).pop(safeName);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    return chosenName;
  }

  Future<void> _importKmlContent(String kmlContent) async {
    final kml = await DroneMapperXml.fromKmlString(kmlContent);

    if (kml.polygons.isEmpty) {
      if (kml.rtes.isNotEmpty || kml.trks.isNotEmpty) {
        final pts = kml.rtes.isNotEmpty
            ? kml.rtes.first.rtepts
                .map((e) => LatLng(e.lat!, e.lon!))
                .toList()
            : kml.trks.first.trksegs
                .expand((s) => s.trkpts)
                .map((e) => LatLng(e.lat!, e.lon!))
                .toList();
        if (pts.isNotEmpty) {
          final listenables =
              Provider.of<ValueListenables>(context, listen: false);
          listenables.mappingMode = MappingMode.corridor;
          _loadPolygon(pts);
          return;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("No polygons or routes found in KML. Import cancelled")));
      }
      return;
    }

    if (kml.polygons.length > 1) {
      if (!mounted) return;

      int selectedPolygon = 0;
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Select Polygon"),
            content: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        "Multiple polygons found in the KML file, please select one"),
                    const Divider(),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      width: 400,
                      child: ListView.separated(
                        itemCount: kml.polygons.length,
                        itemBuilder: (context, index) => CheckboxListTile(
                          value: selectedPolygon == index,
                          onChanged: (value) {
                            setState(() {
                              selectedPolygon = index;
                            });
                          },
                          title: Text(
                              kml.polygons[index].name ?? "Polygon $index"),
                        ),
                        separatorBuilder: (context, index) => const Divider(),
                        shrinkWrap: true,
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text("Cancel")),
              FilledButton(
                  onPressed: () {
                    if (selectedPolygon >= 0 &&
                        selectedPolygon < kml.polygons.length) {
                      _loadPolygon(
                        kml.polygons[selectedPolygon].outerBoundaryIs.rtepts
                            .map((e) => LatLng(e.lat!, e.lon!))
                            .toList(),
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text("Load")),
            ],
          );
        },
      );
      return;
    }

    _loadPolygon(kml.polygons.first.outerBoundaryIs.rtepts
        .map((e) => LatLng(e.lat!, e.lon!))
        .toList());
  }

  Future<void> _importKmlFromPlatformFile(PlatformFile file) async {
    if (file.name.toLowerCase().endsWith('.kml') == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Only .kml files can be imported here")));
      }
      return;
    }

    String content;
    if (file.bytes != null) {
      content = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      content = await File(file.path!).readAsString();
    } else {
      return;
    }

    await _importKmlContent(content);
  }

  Future<void> _exportForDJIFly(ValueListenables listenables) async {
    final exportFilename = await _promptForExportFilename(
      defaultName: 'mission',
      extension: 'kmz',
      title: 'Nom du fichier KMZ',
    );

    if (exportFilename == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export KMZ annulé')),
        );
      }
      return;
    }

    var missionConfig = MissionConfig(

        /// Always fly safely
        /// This is the default for DJI Fly anyway
        flyToWaylineMode: FlyToWaylineMode.safely,

        /// This will be added later
        finishAction: listenables.onFinished,

        /// To comply with EU regulations
        /// Always execute lost action on RC signal lost
        /// do not continue the mission
        exitOnRCLost: ExitOnRCLost.executeLostAction,

        /// For now it's deafult to go back home on RC signal lost
        rcLostAction: listenables.rcLostAction,

        /// The speed to the first waypoint
        /// For now this is the general speed of the mission
        globalTransitionalSpeed: listenables.speed,

        /// Drone information for DJI Fly is default at 68
        /// Unsure what other values there can be
        /// Can't find official documentation
        droneInfo: DroneInfo(droneEnumValue: 68));

    var template = TemplateKml(
        document: KmlDocumentElement(

            /// The author is always `fly` for now
            author: "fly",
            creationTime: DateTime.now(),
            modificationTime: DateTime.now(),

            /// The template and waylines take the same mission config
            /// Not sure why duplication is necessary
            missionConfig: missionConfig));

    var placemarks = _generateDjiPlacemarks(listenables);

    if (placemarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No waypoints to export. Please add waypoints first")));
      return;
    }

    var waylines = WaylinesWpml(
        document: WpmlDocumentElement(
            missionConfig: missionConfig,
            folderElement: FolderElement(
                templateId: 0, // Only one mission, so this is always 0
                waylineId: 0, // Only one wayline, so this is always 0
                speed: listenables.speed,
                placemarks: placemarks)));

    final zipBytes = KMZExporter.generateDjiKmzBytes(
      template: template,
      waylines: waylines,
    );

    String? outputPath;

    if (!kIsWeb) {
      outputPath = await FilePicker.platform.saveFile(
          type: FileType.custom,
          fileName: exportFilename,
          allowedExtensions: ["kmz"],
          dialogTitle: "Enregistrer la mission KMZ");

      if (outputPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Mission export cancelled")));
        }
        return;
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        if (!outputPath.endsWith(".kmz")) {
          outputPath += ".kmz";
        }
        final file = File(outputPath);
        await file.writeAsBytes(zipBytes);
      }
    } else {
      final safeName = exportFilename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      outputPath = safeName;
      final blob = html.Blob([zipBytes], 'application/octet-stream');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", safeName)
        ..click();
      html.Url.revokeObjectUrl(url);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mission exported successfully")));

      if (!(prefs.getBool("djiWarningDoNotShow") ?? false)) {
        showDialog(
            context: context, builder: (context) => const DjiLoadAlert());
      }
    }
  }

  Future<void> _exportForLithi(ValueListenables listenables) async {
    final exportFilename = await _promptForExportFilename(
      defaultName: 'litchi_mission',
      extension: 'csv',
      title: 'Nom du fichier CSV',
    );

    if (exportFilename == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export Litchi annulé')),
        );
      }
      return;
    }

    final waypoints = _generateLitchiWaypoints(listenables);

    if (waypoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No waypoints to export. Please add waypoints first")));
      return;
    }

    String csvContent = litchi.LitchiCsv.generateCsv(waypoints);

    String? outputPath;

    if (!kIsWeb) {
      outputPath = await FilePicker.platform.saveFile(
          type: FileType.custom,
          fileName: exportFilename,
          allowedExtensions: ["csv"],
          dialogTitle: "Enregistrer la mission Litchi");

      if (outputPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Mission export cancelled")));
        }
        return;
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        if (!outputPath.endsWith(".csv")) {
          outputPath += ".csv";
        }
        final file = File(outputPath);
        await file.writeAsString(csvContent);
      }
    } else {
      final safeName = exportFilename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      outputPath = safeName;
      final blob = html.Blob([csvContent], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", safeName)
        ..click();
      html.Url.revokeObjectUrl(url);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mission exported successfully")));
      if (!(prefs.getBool("litchiWarningDoNotShow") ?? false)) {
        showDialog(
            context: context, builder: (context) => const LitchiLoadAlert());
      }
    }
  }

  List<litchi.Waypoint> _generateLitchiWaypoints(ValueListenables listenables) {
    var waypoints = <litchi.Waypoint>[];

    for (var photoLocation in listenables.photoLocations) {
      waypoints.add(litchi.Waypoint(
          latitude: photoLocation.latitude,
          longitude: photoLocation.longitude,
          altitude: listenables.altitude,
          speed: listenables.speed.toInt(),
          gimbalPitch: listenables.cameraAngle,
          gimbalMode: litchi.GimbalMode.interpolate,
          actions: [
            if (listenables.delayAtWaypoint > 0)
              litchi.Action(
                  actionType: litchi.ActionType.stayFor,

                  // Litchi uses milliseconds for delay time
                  actionParam: listenables.delayAtWaypoint.toDouble() * 1000),
            if (listenables.createCameraPoints)
              litchi.Action(actionType: litchi.ActionType.takePhoto)
          ]));
    }

    return waypoints;
  }

  List<Placemark> _generateDjiPlacemarks(ValueListenables listenables) {
    var placemarks = <Placemark>[];

    for (var photoLocation in listenables.photoLocations) {
      int id = listenables.photoLocations.indexOf(photoLocation);
      placemarks.add(Placemark(
          point: WaypointPoint(
              longitude: photoLocation.longitude,
              latitude: photoLocation.latitude),
          index: id,
          height: listenables.altitude,
          speed: listenables.speed,
          headingParam: HeadingParam(
              headingMode: HeadingMode.followWayline,
              headingPathMode: HeadingPathMode.followBadArc),
          turnParam: TurnParam(
              waypointTurnMode:
                  WaypointTurnMode.toPointAndStopWithDiscontinuityCurvature,
              turnDampingDistance: 0),
          useStraightLine: true,
          actionGroup: ActionGroup(
              id: 0,
              startIndex: id,
              endIndex: id,
              actions: [
                if (id == 0)
                  Action(
                      id: id,
                      actionFunction: ActionFunction.gimbalEvenlyRotate,
                      actionParams: GimbalRotateParams(
                          pitch: listenables.cameraAngle.toDouble(),
                          payloadPosition: 0)),
                if (listenables.delayAtWaypoint > 0)
                  Action(
                      id: id,
                      actionFunction: ActionFunction.hover,
                      actionParams:
                          HoverParams(hoverTime: listenables.delayAtWaypoint)),
                if (listenables.createCameraPoints)
                  Action(
                      id: id,
                      actionFunction: ActionFunction.takePhoto,
                      actionParams: CameraControlParams(payloadPosition: 0)),
              ],
              mode: ActionMode.sequence,
              trigger: ActionTriggerType.reachPoint)));
    }

    return placemarks;
  }

  Future<void> _importFromKml(ValueListenables listenables) async {
    var file = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ["kml"],
        dialogTitle: "Load Area");

    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("No file selected. Import cancelled")));
      }
      return;
    }

    await _importKmlFromPlatformFile(file.files.single);
  }

  Future<void> _loadPolygon(List<LatLng> polygon) async {
    final mapProvider = Provider.of<MapProvider>(context, listen: false);
    final mapController = mapProvider.mapController;
    final listenables = Provider.of<ValueListenables>(context, listen: false);

    listenables.polygon = polygon;
    if (listenables.mappingMode == MappingMode.corridor) {
      listenables.centerline = List.from(polygon);
      listenables.polygon = DroneMappingEngine.generateCorridorBufferPolygon(
        polygon,
        listenables.corridorWidth.toDouble(),
      );
    }

    final targetPoints = listenables.polygon.isNotEmpty
        ? listenables.polygon
        : listenables.centerline;

    if (targetPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(targetPoints);

      mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
          maxZoom: 18.0,
        ),
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(listenables.mappingMode == MappingMode.corridor
              ? "Corridor imported successfully"
              : "Area imported successfully"),
        ),
      );
    }
  }

  Future<void> _exportAreaToKml(ValueListenables listenables) async {
    final exportFilename = await _promptForExportFilename(
      defaultName: 'area',
      extension: 'kml',
      title: 'Nom du fichier KML',
    );

    if (exportFilename == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export KML annulé')),
        );
      }
      return;
    }

    final points = listenables.polygon.isNotEmpty
        ? listenables.polygon
        : listenables.centerline;

    if (points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("No area to export. Please add waypoints first")));
      return;
    }
    var kml = DroneMapperXml();
    if (listenables.mappingMode == MappingMode.corridor &&
        listenables.centerline.length >= 2) {
      kml.rtes = [
        Rte(
          name: "Corridor Centerline",
          rtepts: listenables.centerline
              .map((element) =>
                  Wpt(lat: element.latitude, lon: element.longitude))
              .toList(),
        )
      ];
      if (listenables.polygon.length >= 3) {
        kml.polygons = [
          Polygon(
            name: "Corridor Boundary",
            outerBoundaryIs: Rte(
              rtepts: listenables.polygon
                  .map((element) =>
                      Wpt(lat: element.latitude, lon: element.longitude))
                  .toList(),
            ),
          )
        ];
      }
    } else {
      kml.polygons = [
        Polygon(
          name: "Mapping Area",
          outerBoundaryIs: Rte(
            rtepts: listenables.polygon
                .map((element) =>
                    Wpt(lat: element.latitude, lon: element.longitude))
                .toList(),
          ),
        )
      ];
    }

    var kmlString = kml.toKmlString(pretty: true);

    String? outputPath;

    if (!kIsWeb) {
      outputPath = await FilePicker.platform.saveFile(
          type: FileType.custom,
          fileName: exportFilename,
          allowedExtensions: ["kml"],
          dialogTitle: "Enregistrer l'aire KML");

      if (outputPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Area export cancelled")));
        }
        return;
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        if (!outputPath.endsWith(".kml")) {
          outputPath += ".kml";
        }
        final file = File(outputPath);
        await file.writeAsBytes(Uint8List.fromList(kmlString.codeUnits));
      }
    } else {
      final safeName = exportFilename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      outputPath = safeName;
      final blob = html.Blob([Uint8List.fromList(kmlString.codeUnits)],
          'application/octet-stream');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", safeName)
        ..click();
      html.Url.revokeObjectUrl(url);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Area exported successfully")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        child: Consumer<ValueListenables>(builder: (context, listenables, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.primaryContainer.withAlpha(170),
                      colorScheme.surfaceContainerHighest.withAlpha(170),
                    ],
                  ),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withAlpha(180),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withAlpha(18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.primary.withAlpha(25),
                      ),
                      child: Icon(
                        Icons.file_open_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Exports & imports',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Prepare and transfer your mission in a clean, professional format.',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                context: context,
                title: 'Survey mission',
                subtitle: 'Export to drone mission formats',
                icon: Icons.flight_takeoff_rounded,
                accent: colorScheme.primary,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildGridActionButton(
                        context: context,
                        title: 'DJI Fly',
                        subtitle: 'KMZ Waylines',
                        icon: Icons.flight,
                        onPressed: () => _exportForDJIFly(listenables),
                        accent: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildGridActionButton(
                        context: context,
                        title: 'Litchi',
                        subtitle: 'CSV Mission',
                        icon: Icons.map_outlined,
                        onPressed: () => _exportForLithi(listenables),
                        accent: colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _buildSectionCard(
                context: context,
                title: 'Mapping area',
                subtitle: 'Import or export polygon boundary',
                icon: Icons.map_rounded,
                accent: colorScheme.tertiary,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Tooltip(
                            message:
                                'This will override the current mapping area',
                            child: _buildGridActionButton(
                              context: context,
                              title: 'Import KML',
                              subtitle: 'Load boundary',
                              icon: Icons.upload_file,
                              onPressed: () => _importFromKml(listenables),
                              accent: colorScheme.tertiary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildGridActionButton(
                            context: context,
                            title: 'Export KML',
                            subtitle: 'Save boundary',
                            icon: Icons.download,
                            onPressed: () => _exportAreaToKml(listenables),
                            accent: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DragTarget<String>(
                      onWillAcceptWithDetails: (details) =>
                          details.data.toLowerCase().endsWith('.kml'),
                      onAcceptWithDetails: (details) async {
                        final filePath = details.data;
                        if (filePath.isEmpty) return;
                        final file = File(filePath);
                        if (!file.existsSync()) return;
                        await _importKmlContent(await file.readAsString());
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isActive = candidateData.isNotEmpty;

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              width: 1.6,
                              color: isActive
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                            ),
                            color: isActive
                                ? colorScheme.primaryContainer.withAlpha(110)
                                : colorScheme.surfaceContainerHighest.withAlpha(120),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isActive
                                      ? colorScheme.primary.withAlpha(26)
                                      : colorScheme.surfaceVariant,
                                ),
                                child: Icon(
                                  Icons.drive_folder_upload_rounded,
                                  color: isActive
                                      ? colorScheme.primary
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  'Drop a .kml file here to import the mapping area',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isActive
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    width: 1.5,
                    color: colorScheme.error.withAlpha(200),
                  ),
                  color: colorScheme.errorContainer.withAlpha(25),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.error.withAlpha(25),
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: colorScheme.error,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Warning',
                              style: TextStyle(
                                fontSize: 20,
                                color: colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'I am not responsible for any damage or loss of equipment or data. Use at your own risk.',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onErrorContainer,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'If you notice any issues during the mission, please stop the mission immediately.',
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onErrorContainer,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest.withAlpha(130),
            ],
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(180),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: accent.withAlpha(26),
                    ),
                    child: Icon(icon, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildGridActionButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onPressed,
    required Color accent,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: accent.withAlpha(24),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: accent.withAlpha(120),
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withAlpha(40),
                ),
                child: Icon(icon, color: accent, size: 17),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
