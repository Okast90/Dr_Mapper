import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dji_mapper/components/app_bar.dart';
import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:dji_mapper/github/update_checker.dart';
import 'package:dji_mapper/layouts/aircraft.dart';
import 'package:dji_mapper/layouts/camera.dart';
import 'package:dji_mapper/layouts/export.dart';
import 'package:dji_mapper/layouts/info.dart';
import 'package:dji_mapper/main.dart';
import 'package:dji_mapper/presets/preset_manager.dart';
import 'package:dji_mapper/shared/map_provider.dart';
import 'package:dji_mapper/shared/value_listeneables.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/aircraft_settings.dart';

enum MapLayer { streets, satellite, openStreetMap }

class HomeLayout extends StatefulWidget {
  const HomeLayout({super.key});

  @override
  State<HomeLayout> createState() => _HomeLayoutState();
}

class _HomeLayoutState extends State<HomeLayout> with TickerProviderStateMixin {
  late final TabController _tabController;

  late MapLayer _selectedMapLayer;

  final List<Marker> _photoMarkers = [];

  final _debounce = const Duration(milliseconds: 800);
  Timer? _debounceTimer;
  List<MapSearchLocation> _searchLocations = [];

  final List<Marker> _flightLineArrowMarkers = [];
  final List<Marker> _takeoffLineArrowMarkers = [];
  final List<Marker> _returnLineArrowMarkers = [];
  bool _isDrawingPolygon = false;
  bool _isEditingPolygon = false;
  int? _selectedPolygonPointIndex;
  final List<List<LatLng>> _photoFootprints = [];
  bool _showCoverageQC = false;
  double _coveragePercentage = 0.0;

  String _getMapLayerName(MapLayer layer) {
    switch (layer) {
      case MapLayer.streets:
        return 'Google Plans';
      case MapLayer.satellite:
        return 'Google Satellite';
      case MapLayer.openStreetMap:
        return 'OpenStreetMap';
    }
  }

  Widget _mapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
            : colorScheme.surface.withAlpha(235),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              icon,
              size: 20,
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverageBadge(BuildContext context) {
    final pct = _coveragePercentage;
    final colorScheme = Theme.of(context).colorScheme;
    final isGood = pct >= 95.0;
    final isFair = pct >= 80.0;

    final Color badgeColor = isGood
        ? Colors.green
        : isFair
            ? Colors.amber.shade700
            : Colors.deepOrange;

    final String qualityLabel = isGood
        ? 'Excellente'
        : isFair
            ? 'Bonne'
            : 'Incomplète';

    return Material(
      color: Theme.of(context).colorScheme.surface.withAlpha(235),
      borderRadius: BorderRadius.circular(14),
      elevation: 3,
      child: Tooltip(
        message:
            'Couverture photo : ${pct.toStringAsFixed(1)}% de la zone\nQualité : $qualityLabel',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: badgeColor.withAlpha(120),
              width: 1.2,
            ),
            color: badgeColor.withAlpha(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isGood
                    ? Icons.verified_rounded
                    : isFair
                        ? Icons.pie_chart_rounded
                        : Icons.warning_amber_rounded,
                size: 16,
                color: badgeColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Couverture : ${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _getLocationAndMoveMap();

    final savedLayer = prefs.getInt("mapLayer") ?? 0;
    if (savedLayer == 1) {
      _selectedMapLayer = MapLayer.satellite;
    } else if (savedLayer == 2) {
      _selectedMapLayer = MapLayer.openStreetMap;
    } else {
      _selectedMapLayer = MapLayer.streets;
    }

    final listenables = Provider.of<ValueListenables>(context, listen: false);

    // Preload aircraft settings
    final aircraftSettings = AircraftSettings.getAircraftSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      listenables.altitude = aircraftSettings.altitude;
      listenables.speed = aircraftSettings.speed;
      listenables.forwardOverlap = aircraftSettings.forwardOverlap;
      listenables.sideOverlap = aircraftSettings.sideOverlap;
      listenables.rotation = aircraftSettings.rotation;
      listenables.delayAtWaypoint = aircraftSettings.delay;
      listenables.cameraAngle = aircraftSettings.cameraAngle;
      listenables.onFinished = aircraftSettings.finishAction;
      listenables.rcLostAction = aircraftSettings.rcLostAction;
      listenables.groundOffset = aircraftSettings.groundOffset;
    });

    var cameraPresets = PresetManager.getPresets();

    // Load the latest camera preset
    var latestPresetName = prefs.getString("latestPreset");
    if (latestPresetName == null) {
      latestPresetName = cameraPresets[0].name;
      prefs.setString("latestPreset", latestPresetName);
    }

    // Select the latest camera preset
    listenables.selectedCameraPreset = cameraPresets.firstWhere(
        (element) => element.name == latestPresetName,
        orElse: () => cameraPresets[0]);

    // Load camera settings into the provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      listenables.sensorWidth = listenables.selectedCameraPreset!.sensorWidth;
      listenables.sensorHeight = listenables.selectedCameraPreset!.sensorHeight;
      listenables.focalLength = listenables.selectedCameraPreset!.focalLength;
      listenables.imageWidth = listenables.selectedCameraPreset!.imageWidth;
      listenables.imageHeight = listenables.selectedCameraPreset!.imageHeight;
    });

    // Check for updates
    if (!kIsWeb) {
      UpdateChecker.checkForUpdate().then((latestVersion) => {
            if (latestVersion != null && mounted)
              {
                showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                          title: const Text('Update available'),
                          content: Text('Version $latestVersion is available. '
                              'Do you want to download it?'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Later')),
                            TextButton(
                                onPressed: () {
                                  prefs.setString(
                                      "ignoreVersion", latestVersion);
                                  Navigator.pop(context);
                                },
                                child: const Text("Ignore this version")),
                            ElevatedButton(
                                child: const Text('Download'),
                                onPressed: () {
                                  launchUrl(Uri.https("github.com",
                                      "YarosMallorca/DJI-Mapper/releases/latest"));
                                  Navigator.pop(context);
                                })
                          ],
                        ))
              }
          });
    }
  }

  Future<void> _search(String query) async {
    try {
      var response = await Dio().get(
        "https://nominatim.openstreetmap.org/search",
        queryParameters: {
          "q": query,
          "format": "jsonv2",
        },
        options: Options(
          headers: {
            "User-Agent": "DJI-Mapper/1.5.0 (https://github.com/YarosMallorca/DJI-Mapper)",
          },
        ),
      );

      List<MapSearchLocation> locations = [];
      for (var location in response.data) {
        locations.add(MapSearchLocation(
          name: location["display_name"],
          type: location["type"],
          location: LatLng(
              double.parse(location["lat"]), double.parse(location["lon"])),
        ));
      }

      setState(() {
        _searchLocations = locations;
      });
    } catch (e) {
      // Silently fail on search errors - network issues or API rate limits
      setState(() {
        _searchLocations = [];
      });
    }
  }

  void _onSearchChanged(
      String query, Function(List<MapSearchLocation>) callback) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(_debounce, () async {
      await _search(query);

      callback(_searchLocations);
    });
  }

  void _getLocationAndMoveMap() async {
    try {
      if (await Geolocator.isLocationServiceEnabled() == false) return;
      if (await Geolocator.checkPermission() == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final location = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.low));
      if (!mounted) return;
      Provider.of<MapProvider>(context, listen: false)
          .mapController
          .move(LatLng(location.latitude, location.longitude), 17);
    } catch (e) {
      // Location services not available (e.g., in WSL or without GeoClue2)
      // Silently ignore - location is an optional feature
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _selectPolygonPoint(ValueListenables listenables, LatLng point) {
    final targetList = listenables.mappingMode == MappingMode.corridor
        ? listenables.centerline
        : listenables.polygon;
    final index = targetList.indexOf(point);
    if (index < 0) return;

    setState(() {
      _selectedPolygonPointIndex = index;
    });
  }

  List<LatLng> _normalizePolygon(List<LatLng> points) {
    final normalized = <LatLng>[];
    for (final point in points) {
      final lat = point.latitude.isFinite ? point.latitude.clamp(-90.0, 90.0) : 0.0;
      final lng = point.longitude.isFinite ? point.longitude.clamp(-180.0, 180.0) : 0.0;
      normalized.add(LatLng(lat, lng));
    }
    return normalized;
  }

  void _deleteSelectedPolygonPoint(ValueListenables listenables) {
    if (_selectedPolygonPointIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez un point à supprimer.')),
      );
      return;
    }

    if (listenables.mappingMode == MappingMode.corridor) {
      if (_selectedPolygonPointIndex! < 0 ||
          _selectedPolygonPointIndex! >= listenables.centerline.length) {
        _selectedPolygonPointIndex = null;
        return;
      }

      setState(() {
        listenables.centerline.removeAt(_selectedPolygonPointIndex!);
        _selectedPolygonPointIndex = null;
        if (listenables.centerline.length < 2) {
          listenables.polygon.clear();
          listenables.homePoint = null;
          listenables.photoLocations.clear();
          _photoMarkers.clear();
          listenables.flightLine = null;
          listenables.takeoffLine = null;
          listenables.returnLine = null;
        } else {
          _applyDrawnPolygon(listenables, fitToMap: false);
        }
      });
      return;
    }

    if (_selectedPolygonPointIndex! < 0 ||
        _selectedPolygonPointIndex! >= listenables.polygon.length) {
      _selectedPolygonPointIndex = null;
      return;
    }

    setState(() {
      listenables.polygon.removeAt(_selectedPolygonPointIndex!);
      _selectedPolygonPointIndex = null;
      if (listenables.polygon.length < 3) {
        listenables.homePoint = null;
        listenables.photoLocations.clear();
        _photoMarkers.clear();
        listenables.flightLine = null;
        listenables.takeoffLine = null;
        listenables.returnLine = null;
      }
    });
  }

  void _applyDrawnPolygon(ValueListenables listenables, {bool fitToMap = true}) {
    if (listenables.mappingMode == MappingMode.corridor) {
      if (listenables.centerline.isEmpty && listenables.polygon.isNotEmpty) {
        listenables.centerline = List.from(listenables.polygon);
      }
      final centerline = _normalizePolygon(listenables.centerline);
      if (centerline.length < 2) {
        return;
      }

      listenables.centerline = centerline;
      listenables.polygon = DroneMappingEngine.generateCorridorBufferPolygon(
        centerline,
        listenables.corridorWidth.toDouble(),
      );

      if (listenables.homePoint == null && centerline.isNotEmpty) {
        listenables.homePoint = centerline.first;
      }

      if (fitToMap) {
        final mapProvider = Provider.of<MapProvider>(context, listen: false);
        final bounds = LatLngBounds.fromPoints(listenables.polygon.isNotEmpty
            ? listenables.polygon
            : centerline);
        mapProvider.mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(80),
            maxZoom: 18,
          ),
        );
      }

      listenables.notify();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _buildMarkers(listenables);
      });
      return;
    }

    final polygon = _normalizePolygon(listenables.polygon);
    if (polygon.length < 3) {
      return;
    }

    if (listenables.homePoint == null && polygon.isNotEmpty) {
      listenables.homePoint = polygon.first;
    }

    if (fitToMap) {
      final mapProvider = Provider.of<MapProvider>(context, listen: false);
      final bounds = LatLngBounds.fromPoints(polygon);
      mapProvider.mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
          maxZoom: 18,
        ),
      );
    }

    listenables.polygon = polygon;
    listenables.notify();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildMarkers(listenables);
    });
  }

  void _validateContour(ValueListenables listenables) {
    if (listenables.mappingMode == MappingMode.corridor) {
      if (listenables.centerline.length < 2 && listenables.polygon.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Le corridor doit contenir au moins 2 points de tracé.')),
        );
        return;
      }
    } else {
      if (listenables.polygon.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Le contour doit contenir au moins 3 points.')),
        );
        return;
      }
    }

    setState(() {
      _isDrawingPolygon = false;
      _isEditingPolygon = false;
      _selectedPolygonPointIndex = null;
      listenables.showPoints = true;
    });

    _applyDrawnPolygon(listenables, fitToMap: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _buildMarkers(listenables);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(listenables.mappingMode == MappingMode.corridor
            ? 'Tracé corridor validé et activé.'
            : 'Contour validé et activé pour la mission.'),
      ),
    );
  }

  List<LatLng> _straightenPolygon(List<LatLng> points) {
    if (points.length < 3) return _normalizePolygon(points);

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

    return _normalizePolygon(result);
  }

  List<LatLng> _orthogonalizePolygon(List<LatLng> points) {
    if (points.length < 3) return _normalizePolygon(points);

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

    return _normalizePolygon(result);
  }

  void _buildMarkers(ValueListenables listenables) {
    var droneMapping = DroneMappingEngine(
      altitude: listenables.altitude.toDouble(),
      forwardOverlap: listenables.forwardOverlap / 100,
      sideOverlap: listenables.sideOverlap / 100,
      sensorWidth: listenables.sensorWidth,
      sensorHeight: listenables.sensorHeight,
      focalLength: listenables.focalLength,
      imageWidth: listenables.imageWidth,
      imageHeight: listenables.imageHeight,
      angle: listenables.rotation.toDouble(),
      groundOffset: listenables.groundOffset.toDouble(),
    );

    List<LatLng> waypoints;
    if (listenables.mappingMode == MappingMode.corridor) {
      final activeCenterline = listenables.centerline.isNotEmpty
          ? listenables.centerline
          : listenables.polygon;

      if (activeCenterline.length >= 2) {
        listenables.centerline = activeCenterline;
        listenables.polygon = DroneMappingEngine.generateCorridorBufferPolygon(
          activeCenterline,
          listenables.corridorWidth.toDouble(),
        );
        waypoints = droneMapping.generateCorridorWaypoints(
          centerline: activeCenterline,
          corridorWidth: listenables.corridorWidth.toDouble(),
          flightLines: listenables.corridorFlightLines,
          createCameraPoints: listenables.createCameraPoints,
          homePoint: listenables.homePoint,
        );
      } else {
        waypoints = [];
      }
    } else {
      waypoints = droneMapping.generateWaypoints(
        listenables.polygon,
        listenables.createCameraPoints,
        listenables.fillGrid,
        listenables.homePoint,
        listenables.useInsetBuffer,
        listenables.useConvexDecomposition,
      );
    }
    
    listenables.photoLocations = waypoints;
    if (waypoints.isEmpty) {
      _photoMarkers.clear();
      _photoFootprints.clear();
      _coveragePercentage = 0.0;
      listenables.flightLine = null;
      listenables.takeoffLine = null;
      listenables.returnLine = null;
      _takeoffLineArrowMarkers.clear();
      _returnLineArrowMarkers.clear();
      _flightLineArrowMarkers.clear();
      return;
    }

    _photoMarkers.clear();
    _photoFootprints.clear();
    _photoFootprints.addAll(droneMapping.generatePhotoFootprints(waypoints));

    final targetPolygon = listenables.mappingMode == MappingMode.corridor
        ? (listenables.polygon.isNotEmpty
            ? listenables.polygon
            : listenables.centerline)
        : listenables.polygon;
    if (targetPolygon.length >= 3) {
      _coveragePercentage = droneMapping.calculateCoveragePercentage(
        polygon: targetPolygon,
        photoLocations: waypoints,
      );
    } else {
      _coveragePercentage = waypoints.isNotEmpty ? 100.0 : 0.0;
    }

    for (int i = 0; i < waypoints.length; i++) {
      var photoLocation = waypoints[i];
      _photoMarkers.add(Marker(
        point: photoLocation,
        height: 40,
        alignment: Alignment.center,
        rotate: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (listenables.createCameraPoints)
              Icon(Icons.photo_camera,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer)
            else
              Icon(Icons.place_sharp,
                  size: 20,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            Text(
              "${i + 1}",
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ));
    }
    listenables.flightLine = Polyline(
      points: waypoints,
      strokeWidth: 3,
      color: Theme.of(context).colorScheme.tertiary,
    );

    // Draw directional arrow markers
    _flightLineArrowMarkers.clear();
    _takeoffLineArrowMarkers.clear();
    _returnLineArrowMarkers.clear();

    if (waypoints.length > 1 && listenables.homePoint != null) {
      const double arrowSpacing = 40.0; // Metres between arrows
      LatLng lastPoint = waypoints[0];
      const distance = Distance();
      double cumulativeDistance = 0.0;

      for (int i = 1; i < waypoints.length; i++) {
        cumulativeDistance = _placeArrowMarkers(lastPoint, waypoints[i], arrowSpacing, distance, cumulativeDistance, _flightLineArrowMarkers, Theme.of(context).colorScheme.tertiary, 15);
        lastPoint = waypoints[i];
      }

      // Draw takeoffLine & returnLine
      listenables.takeoffLine = Polyline(
        points: [listenables.homePoint!, waypoints.first],
        strokeWidth: 3,
        color: Theme.of(context).colorScheme.primary,
        pattern: const StrokePattern.dotted(),
      );

      listenables.returnLine = Polyline(
        points: [waypoints.last, listenables.homePoint!],
        strokeWidth: 3,
        color: Theme.of(context).colorScheme.error,
        pattern: const StrokePattern.dotted(),
      );

      _placeArrowMarkers(listenables.homePoint!, waypoints.first, arrowSpacing, distance, 0, _takeoffLineArrowMarkers, Theme.of(context).colorScheme.primary, 15);
      _placeArrowMarkers(waypoints.last, listenables.homePoint!, arrowSpacing, distance, 0, _returnLineArrowMarkers, Theme.of(context).colorScheme.error, 15);

    } else {
      listenables.takeoffLine = null;
      listenables.returnLine = null;
      _flightLineArrowMarkers.clear();
      _takeoffLineArrowMarkers.clear();
      _returnLineArrowMarkers.clear();
    }
  }

  // Add directional arrows along a given segment of fromPoint to toPoint facing the arrows to the toPoint
  double _placeArrowMarkers(LatLng fromPoint, LatLng toPoint, double arrowSpacing, var distance, double cumulativeDistance, List<Marker> targetArrowMarkers, Color arrowColour, double arrowSize) {
    double segmentDistance = distance.as(LengthUnit.Meter, fromPoint, toPoint);
    double distAlong = arrowSpacing - (cumulativeDistance % arrowSpacing);

    while (distAlong < segmentDistance) {
      double fraction = distAlong / segmentDistance;
      double bearing = distance.bearing(fromPoint, toPoint);

      // Interpolate position along the segment
      LatLng arrowPos = LatLng(
        fromPoint.latitude + fraction * (toPoint.latitude - fromPoint.latitude),
        fromPoint.longitude + fraction * (toPoint.longitude - fromPoint.longitude),
      );

      targetArrowMarkers.add(Marker(
        point: arrowPos,
        width: arrowSize + 5,
        height: arrowSize + 5,
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: ((bearing - 90) * pi / 180),
          child: Icon(
            Icons.arrow_forward,
            size: arrowSize,
            color: arrowColour,
          ),
        ),
      ));

      distAlong += arrowSpacing;
    }

    cumulativeDistance += segmentDistance;

    return cumulativeDistance;
  }

  String _lastMissionVisualSignature = "";

  void _refreshMissionVisuals(ValueListenables listenables) {
    final signature = [
      listenables.mappingMode.name,
      listenables.polygon.length,
      listenables.centerline.length,
      listenables.corridorWidth,
      listenables.corridorFlightLines,
      listenables.altitude,
      listenables.forwardOverlap,
      listenables.sideOverlap,
      listenables.sensorWidth,
      listenables.sensorHeight,
      listenables.focalLength,
      listenables.imageWidth,
      listenables.imageHeight,
      listenables.rotation,
      listenables.groundOffset,
      listenables.createCameraPoints,
      listenables.fillGrid,
      listenables.useInsetBuffer,
      listenables.useConvexDecomposition,
      listenables.homePoint?.latitude,
      listenables.homePoint?.longitude,
      listenables.speed,
      listenables.delayAtWaypoint,
      if (listenables.polygon.isNotEmpty) ...[
        listenables.polygon.first.latitude,
        listenables.polygon.first.longitude,
        listenables.polygon.last.latitude,
        listenables.polygon.last.longitude,
      ],
      if (listenables.centerline.isNotEmpty) ...[
        listenables.centerline.first.latitude,
        listenables.centerline.first.longitude,
        listenables.centerline.last.latitude,
        listenables.centerline.last.longitude,
      ],
    ].join("|");

    if (signature == _lastMissionVisualSignature) {
      return;
    }

    _lastMissionVisualSignature = signature;

    final isCorridorValid = listenables.mappingMode == MappingMode.corridor &&
        (listenables.centerline.length >= 2 || listenables.polygon.length >= 2);
    final isGridValid = listenables.mappingMode == MappingMode.grid &&
        listenables.polygon.length > 2;

    if ((isCorridorValid || isGridValid) && listenables.altitude >= 5) {
      _buildMarkers(listenables);
    } else {
      listenables.photoLocations.clear();
      _photoMarkers.clear();
      _photoFootprints.clear();
      listenables.flightLine = null;
      listenables.takeoffLine = null;
      listenables.returnLine = null;
      _takeoffLineArrowMarkers.clear();
      _returnLineArrowMarkers.clear();
      _flightLineArrowMarkers.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ValueListenables, MapProvider>(
      builder: (context, listenables, mapProvider, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _refreshMissionVisuals(listenables);
        });

        final mapWidget = FlutterMap(
              mapController: mapProvider.mapController,
              options: MapOptions(
                onTap: (tapPosition, point) => setState(() {
                  if (!_isDrawingPolygon) {
                    return;
                  }

                  if (listenables.mappingMode == MappingMode.corridor) {
                    if (listenables.homePoint == null) {
                      listenables.homePoint = point;
                    }
                    final alreadyExists = listenables.centerline.any(
                      (existing) =>
                          existing.latitude == point.latitude &&
                          existing.longitude == point.longitude,
                    );
                    if (!alreadyExists) {
                      listenables.centerline.add(point);
                      _applyDrawnPolygon(listenables, fitToMap: false);
                    }
                    return;
                  }

                  if (listenables.homePoint == null) {
                    listenables.homePoint = point;
                    listenables.polygon.add(point);
                    _applyDrawnPolygon(listenables, fitToMap: true);
                    return;
                  }

                  final alreadyExists = listenables.polygon.any(
                    (existing) =>
                        existing.latitude == point.latitude &&
                        existing.longitude == point.longitude,
                  );

                  if (!alreadyExists) {
                    listenables.polygon.add(point);
                    _applyDrawnPolygon(listenables, fitToMap: true);
                  }
                }),
                onLongPress: (tapPosition, point) => setState(() {
                  if (!_isDrawingPolygon) {
                    return;
                  }

                  if (listenables.mappingMode == MappingMode.corridor) {
                    if (listenables.homePoint == null) {
                      listenables.homePoint = point;
                    }
                    final alreadyExists = listenables.centerline.any(
                      (existing) =>
                          existing.latitude == point.latitude &&
                          existing.longitude == point.longitude,
                    );
                    if (!alreadyExists) {
                      listenables.centerline.add(point);
                      _applyDrawnPolygon(listenables, fitToMap: false);
                    }
                    return;
                  }

                  if (listenables.homePoint == null) {
                    listenables.homePoint = point;
                    listenables.polygon.add(point);
                    _applyDrawnPolygon(listenables, fitToMap: true);
                    return;
                  }

                  final alreadyExists = listenables.polygon.any(
                    (existing) =>
                        existing.latitude == point.latitude &&
                        existing.longitude == point.longitude,
                  );

                  if (!alreadyExists) {
                    listenables.polygon.add(point);
                    _applyDrawnPolygon(listenables, fitToMap: true);
                  }
                }),
                onSecondaryTap: (tapPosition, point) {
                  setState(() {
                    listenables.homePoint = point;
                  });
                },
              ),
              children: [
                TileLayer(
                  key: ValueKey(_selectedMapLayer),
                  tileProvider: CancellableNetworkTileProvider(),
                  tileBuilder: Theme.of(context).brightness == Brightness.dark &&
                          (_selectedMapLayer == MapLayer.streets ||
                              _selectedMapLayer == MapLayer.openStreetMap)
                      ? (context, tileWidget, tile) =>
                          darkModeTileBuilder(context, tileWidget, tile)
                      : null,
                  urlTemplate: _selectedMapLayer == MapLayer.streets
                      ? 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}'
                      : _selectedMapLayer == MapLayer.satellite
                          ? 'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yarosfpv.dji_mapper',
                  subdomains: _selectedMapLayer == MapLayer.openStreetMap
                      ? const ['a', 'b', 'c']
                      : const ['mt0', 'mt1', 'mt2', 'mt3'],
                ),
                // flight path boundary (or corridor buffer polygon)
                PolygonLayer(polygons: [
                  if (listenables.polygon.length > 1)
                    Polygon(
                      points: listenables.polygon,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withAlpha(77),
                      borderColor: Theme.of(context).colorScheme.primary,
                      borderStrokeWidth: 3,
                    ),
                ]),
                // Photo coverage footprints / shadows (Quality Control)
                if (_showCoverageQC && _photoFootprints.isNotEmpty)
                  PolygonLayer(
                    polygons: [
                      for (final footprint in _photoFootprints)
                        Polygon(
                          points: footprint,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.cyanAccent.withAlpha(35)
                              : Colors.indigo.withAlpha(38),
                          borderColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.cyanAccent.withAlpha(100)
                                  : Colors.indigo.withAlpha(90),
                          borderStrokeWidth: 1.0,
                        ),
                    ],
                  ),
                // flightLine, takeoffLine, returnLine & centerline
                if (listenables.homePoint != null ||
                    listenables.centerline.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      if (listenables.mappingMode == MappingMode.corridor &&
                          listenables.centerline.length >= 2)
                        Polyline(
                          points: listenables.centerline,
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      if (listenables.flightLine != null)
                        listenables.flightLine!,
                      if (listenables.takeoffLine != null)
                        listenables.takeoffLine!,
                      if (listenables.returnLine != null)
                        listenables.returnLine!,
                    ],
                  ),
                // directional flight path arrows
                MarkerLayer(markers: _flightLineArrowMarkers),
                MarkerLayer(markers: _takeoffLineArrowMarkers),
                MarkerLayer(markers: _returnLineArrowMarkers),
                // photo markers
                if (listenables.showPoints)
                  MarkerLayer(markers: _photoMarkers),
                if (_isEditingPolygon)
                  Builder(
                    builder: (context) {
                      final activePoints =
                          listenables.mappingMode == MappingMode.corridor
                              ? listenables.centerline
                              : listenables.polygon;

                      if (activePoints.length < 2) {
                        return const SizedBox.shrink();
                      }

                      return DragMarkers(
                        markers: [
                          for (int index = 0; index < activePoints.length; index++)
                            DragMarker(
                              size: const Size(36, 36),
                              point: activePoints[index],
                              alignment: Alignment.topCenter,
                              builder: (_, coords, b) {
                                final isSelected =
                                    _selectedPolygonPointIndex == index;
                                return Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withAlpha(56)
                                        : Theme.of(context)
                                            .colorScheme
                                            .secondary
                                            .withAlpha(46),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.adjust,
                                      size: 18,
                                      color: isSelected
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                    ),
                                  ),
                                );
                              },
                              onDragUpdate: (details, latLng) {
                                if (index >= 0 && index < activePoints.length) {
                                  if (listenables.mappingMode ==
                                      MappingMode.corridor) {
                                    listenables.centerline[index] = latLng;
                                    _selectedPolygonPointIndex = index;
                                    _applyDrawnPolygon(listenables,
                                        fitToMap: false);
                                  } else {
                                    listenables.polygon[index] = latLng;
                                    _selectedPolygonPointIndex = index;
                                  }
                                }
                              },
                              onTap: (latLng) {
                                _selectPolygonPoint(listenables, latLng);
                              },
                            ),
                        ],
                      );
                    },
                  ),
                // home point icon
                if (listenables.homePoint != null) 
                  DragMarkers(
                    // home marker
                    markers: [
                      DragMarker(
                        point: listenables.homePoint!,
                        size: const Size(50, 50),
                        offset: const Offset(0.0, -8.0),
                        onDragUpdate: (details, latLng) {
                          listenables.homePoint = latLng;
                        },
                        builder: (context, coords, isDragging) => GestureDetector(
                          onSecondaryTap: () {
                            if (listenables.polygon.isEmpty) {
                              listenables.homePoint = null;
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Cannot delete home point while boundary markers exist. Remove all boundary markers first.")),
                              );
                            }
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.home,
                              size: 30,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),  
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withAlpha(235),
                          borderRadius: BorderRadius.circular(14),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 6.0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _mapActionButton(
                                  icon: Icons.draw_rounded,
                                  tooltip: 'Dessiner le polygone',
                                  selected: _isDrawingPolygon,
                                  onPressed: () => setState(() {
                                    if (_isDrawingPolygon) {
                                      _applyDrawnPolygon(listenables, fitToMap: true);
                                    }
                                    _isDrawingPolygon = !_isDrawingPolygon;
                                    if (_isDrawingPolygon) {
                                      _isEditingPolygon = false;
                                    }
                                  }),
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.edit_rounded,
                                  tooltip: 'Modifier le contour',
                                  selected: _isEditingPolygon,
                                  onPressed: () => setState(() {
                                    _isEditingPolygon = !_isEditingPolygon;
                                    if (_isEditingPolygon) {
                                      _isDrawingPolygon = false;
                                    }
                                  }),
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.layers_rounded,
                                  tooltip:
                                      'Couche : ${_getMapLayerName(_selectedMapLayer)}',
                                  onPressed: () {
                                    setState(() {
                                      switch (_selectedMapLayer) {
                                        case MapLayer.streets:
                                          _selectedMapLayer = MapLayer.satellite;
                                          prefs.setInt("mapLayer", 1);
                                          break;
                                        case MapLayer.satellite:
                                          _selectedMapLayer =
                                              MapLayer.openStreetMap;
                                          prefs.setInt("mapLayer", 2);
                                          break;
                                        case MapLayer.openStreetMap:
                                          _selectedMapLayer = MapLayer.streets;
                                          prefs.setInt("mapLayer", 0);
                                          break;
                                      }
                                    });
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Couche active : ${_getMapLayerName(_selectedMapLayer)}'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.zoom_out_map_rounded,
                                  tooltip: 'Dézoomer la carte',
                                  onPressed: () {
                                    final camera = mapProvider.mapController.camera;
                                    final nextZoom = camera.zoom - 1;
                                    mapProvider.mapController.move(
                                      camera.center,
                                      nextZoom,
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.check_rounded,
                                  tooltip: 'Valider le contour',
                                  onPressed: () => _validateContour(listenables),
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.delete_sweep_rounded,
                                  tooltip: 'Supprimer le point sélectionné',
                                  onPressed: () => _deleteSelectedPolygonPoint(listenables),
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.align_horizontal_left_rounded,
                                  tooltip: 'Aligner droitement',
                                  onPressed: () => setState(() {
                                    if (listenables.polygon.length >= 3) {
                                      listenables.polygon = _straightenPolygon(listenables.polygon);
                                      _selectedPolygonPointIndex = null;
                                    }
                                  }),
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.turn_right_rounded,
                                  tooltip: 'Angles à 90°',
                                  onPressed: () => setState(() {
                                    if (listenables.polygon.length >= 3) {
                                      listenables.polygon = _orthogonalizePolygon(listenables.polygon);
                                      _selectedPolygonPointIndex = null;
                                    }
                                  }),
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.radar_rounded,
                                  tooltip: _showCoverageQC
                                      ? 'Masquer le contrôle qualité (Ombre de couverture)'
                                      : 'Contrôle qualité (Ombre de couverture)',
                                  selected: _showCoverageQC,
                                  onPressed: () {
                                    setState(() {
                                      _showCoverageQC = !_showCoverageQC;
                                    });
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_showCoverageQC
                                            ? 'Contrôle qualité activé : affichage de l\'ombre de couverture'
                                            : 'Contrôle qualité désactivé'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.delete_outline_rounded,
                                  tooltip: 'Effacer le polygone',
                                  onPressed: () => setState(() {
                                    listenables.polygon.clear();
                                    _photoMarkers.clear();
                                    listenables.homePoint = null;
                                    _isDrawingPolygon = false;
                                    _isEditingPolygon = false;
                                    _selectedPolygonPointIndex = null;
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withAlpha(235),
                          borderRadius: BorderRadius.circular(14),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 6.0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  child: Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 220,
                                  child: Autocomplete<MapSearchLocation>(
                                    optionsBuilder: (textEditingValue) {
                                      return Future.delayed(_debounce, () async {
                                        _onSearchChanged(textEditingValue.text,
                                            (locations) => locations);
                                        return _searchLocations;
                                      });
                                    },
                                    onSelected: (option) =>
                                        mapProvider.mapController.move(option.location, 17),
                                    optionsViewBuilder: (context, onSelected, options) {
                                      return Align(
                                        alignment: Alignment.topLeft,
                                        child: Material(
                                          color: Theme.of(context).colorScheme.surface,
                                          borderRadius: BorderRadius.circular(14),
                                          elevation: 6.0,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outlineVariant
                                                    .withAlpha(120),
                                              ),
                                            ),
                                            constraints: const BoxConstraints(
                                              maxHeight: 220,
                                              maxWidth: 320,
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(14),
                                              child: ListView.separated(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                shrinkWrap: true,
                                                itemCount: options.length,
                                                separatorBuilder: (context, index) =>
                                                    Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60)),
                                                itemBuilder: (context, index) {
                                                  final option = options.elementAt(index);
                                                  return InkWell(
                                                    onTap: () {
                                                      onSelected(option);
                                                    },
                                                    child: Padding(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.location_on_outlined,
                                                            size: 16,
                                                            color: Theme.of(context).colorScheme.primary,
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              option.name,
                                                              style: TextStyle(
                                                                fontSize: 12.5,
                                                                color: Theme.of(context).colorScheme.onSurface,
                                                              ),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    displayStringForOption: (option) => option.name,
                                    fieldViewBuilder: (
                                      context,
                                      textEditingController,
                                      focusNode,
                                      onFieldSubmitted,
                                    ) =>
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: textEditingController,
                                                focusNode: focusNode,
                                                style: const TextStyle(fontSize: 13),
                                                onSubmitted: (value) async {
                                                  await _search(textEditingController.text);
                                                  if (_searchLocations.isNotEmpty) {
                                                    mapProvider.mapController.move(
                                                        _searchLocations.first.location, 17);
                                                  }
                                                },
                                                decoration: const InputDecoration(
                                                  hintText: 'Rechercher un lieu...',
                                                  hintStyle: TextStyle(fontSize: 13),
                                                  isDense: true,
                                                  contentPadding: EdgeInsets.symmetric(
                                                      horizontal: 4, vertical: 8),
                                                  border: InputBorder.none,
                                                  focusedBorder: InputBorder.none,
                                                  enabledBorder: InputBorder.none,
                                                ),
                                              ),
                                            ),
                                            if (textEditingController.text.isNotEmpty)
                                              InkWell(
                                                borderRadius: BorderRadius.circular(8),
                                                onTap: () {
                                                  textEditingController.clear();
                                                  setState(() {});
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.all(4.0),
                                                  child: Icon(
                                                    Icons.close_rounded,
                                                    size: 16,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (listenables.photoLocations.isNotEmpty &&
                            (listenables.polygon.length >= 3 ||
                                listenables.centerline.length >= 2)) ...[
                          const SizedBox(width: 8),
                          _buildCoverageBadge(context),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );

        final sideMenuWidget = SizedBox(
          width: 350,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withAlpha(90),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withAlpha(90),
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  labelColor: Theme.of(context).colorScheme.onPrimary,
                  unselectedLabelColor:
                      Theme.of(context).colorScheme.onSurfaceVariant,
                  labelStyle:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  unselectedLabelStyle:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  tabs: const [
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 16),
                          SizedBox(width: 4),
                          Text('Info'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.airplanemode_on, size: 16),
                          SizedBox(width: 4),
                          Text('Drone'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_camera, size: 16),
                          SizedBox(width: 4),
                          Text('Cam'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.file_copy, size: 16),
                          SizedBox(width: 4),
                          Text('File'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    Info(),
                    AircraftBar(),
                    CameraBar(),
                    ExportBar(),
                  ],
                ),
              ),
            ],
          ),
        );

        return Scaffold(
          appBar: const MappingAppBar(),
          body: MediaQuery.of(context).size.width < 700
              ? Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: mapWidget,
                    ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withAlpha(90),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withAlpha(90),
                        ),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: TabBar(
                        controller: _tabController,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        labelColor: Theme.of(context).colorScheme.onPrimary,
                        unselectedLabelColor:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                        labelStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                        unselectedLabelStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                        tabs: const [
                          Tab(
                            height: 38,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline, size: 16),
                                SizedBox(width: 4),
                                Text('Info'),
                              ],
                            ),
                          ),
                          Tab(
                            height: 38,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.airplanemode_on, size: 16),
                                SizedBox(width: 4),
                                Text('Drone'),
                              ],
                            ),
                          ),
                          Tab(
                            height: 38,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.photo_camera, size: 16),
                                SizedBox(width: 4),
                                Text('Cam'),
                              ],
                            ),
                          ),
                          Tab(
                            height: 38,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.file_copy, size: 16),
                                SizedBox(width: 4),
                                Text('File'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: TabBarView(
                        controller: _tabController,
                        children: const [
                          Info(),
                          AircraftBar(),
                          CameraBar(),
                          ExportBar(),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: mapWidget),
                    const VerticalDivider(width: 1, thickness: 1),
                    sideMenuWidget,
                  ],
                ),
        );
      },
    );
  }
}

class MapSearchLocation {
  final String name;
  final String type;
  final LatLng location;

  MapSearchLocation(
      {required this.name, required this.type, required this.location});
}
