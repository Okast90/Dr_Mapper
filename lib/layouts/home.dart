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
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/aircraft_settings.dart';

enum MapLayer { streets, satellite }

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

  Widget _mapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final activeColor = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final iconColor = selected
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? activeColor : inactiveColor,
        borderRadius: BorderRadius.circular(10),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _getLocationAndMoveMap();

    _selectedMapLayer =
        prefs.getInt("mapLayer") == 1 ? MapLayer.satellite : MapLayer.streets;

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
    final index = listenables.polygon.indexOf(point);
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
        const SnackBar(content: Text('Sélectionnez un point du polygone à supprimer.')),
      );
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
      }
    });
  }

  void _applyDrawnPolygon(ValueListenables listenables, {bool fitToMap = true}) {
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
    if (listenables.polygon.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le contour doit contenir au moins 3 points.')),
      );
      return;
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
      const SnackBar(content: Text('Contour validé et activé pour la mission.')),
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

    var waypoints = droneMapping.generateWaypoints(listenables.polygon, listenables.createCameraPoints, listenables.fillGrid, listenables.homePoint);
    listenables.photoLocations = waypoints;
    if (waypoints.isEmpty) {
      _photoMarkers.clear();
      listenables.flightLine = null;
      listenables.takeoffLine = null;
      listenables.returnLine = null;
      _takeoffLineArrowMarkers.clear();
      _returnLineArrowMarkers.clear();
      _flightLineArrowMarkers.clear();
      return;
    }

    _photoMarkers.clear();

    for (int i = 0; i < waypoints.length; i++) {
      var photoLocation = waypoints[i];
      _photoMarkers.add(Marker(
        point: photoLocation,
        height: 40,  // Increased height to fit number
        alignment: Alignment.center,
        rotate: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (listenables.createCameraPoints)
                Icon(Icons.photo_camera,
                    size: 20,  // Reduced size for better fit
                    color: Theme.of(context).colorScheme.onPrimaryContainer)
              else
                Icon(Icons.place_sharp,
                    size: 20,  // Reduced size for better fit
                    color: Theme.of(context).colorScheme.onPrimaryContainer),

              Text(  // Waypoint number text
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
      color: Theme.of(context).colorScheme.tertiary
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

      // Add dashed takeoff line from home to first waypoint to designate 'Start'
      final home = listenables.homePoint!;
      final first = waypoints.first;
      final last = waypoints.last;
      //final bearing = distance.bearing(home, first);
      //final offsetDistance = 2.0; // metres offset from home
      //final offsetPoint = distance.offset(home, offsetDistance, bearing);

      listenables.takeoffLine = Polyline(
        points: [home, first],
        strokeWidth: 1,
        color: Theme.of(context).colorScheme.primary,
        pattern: StrokePattern.dotted(), 
      );

      listenables.returnLine = Polyline(
        points: [home, last],
        strokeWidth: 1,
        color: Theme.of(context).colorScheme.primary,
        pattern: StrokePattern.dotted(), 
      );

      _placeArrowMarkers(home, first, arrowSpacing, distance, 0.0, _takeoffLineArrowMarkers, Theme.of(context).colorScheme.primary, 10);
      _placeArrowMarkers(last, home, arrowSpacing, distance, 0.0, _returnLineArrowMarkers, Theme.of(context).colorScheme.primary, 10);
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

  String? _lastMissionVisualSignature;

  void _refreshMissionVisuals(ValueListenables listenables) {
    final signature = [
      listenables.polygon.length,
      ...listenables.polygon.map((point) => '${point.latitude.toStringAsFixed(7)}:${point.longitude.toStringAsFixed(7)}'),
      listenables.homePoint?.latitude.toStringAsFixed(7),
      listenables.homePoint?.longitude.toStringAsFixed(7),
      listenables.altitude,
      listenables.createCameraPoints,
      listenables.fillGrid,
      listenables.showPoints,
      listenables.forwardOverlap,
      listenables.sideOverlap,
      listenables.rotation,
      listenables.speed,
      listenables.groundOffset,
    ].join('|');

    if (signature == _lastMissionVisualSignature) {
      return;
    }

    _lastMissionVisualSignature = signature;

    if (listenables.polygon.length > 2 && listenables.altitude >= 5) {
      _buildMarkers(listenables);
    } else {
      listenables.photoLocations.clear();
      _photoMarkers.clear();
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

        var children = [
          Flexible(
            flex: 2,
            child: FlutterMap(
              mapController: mapProvider.mapController,
              options: MapOptions(
                onTap: (tapPosition, point) => setState(() {
                  if (!_isDrawingPolygon) {
                    return;
                  }

                  if (listenables.homePoint == null) {
                    listenables.homePoint = point;
                    listenables.polygon.add(point);
                    _applyDrawnPolygon(listenables, fitToMap: true);
                    return;
                  }

                  final alreadyExists = listenables.polygon.any(
                    (existing) => existing.latitude == point.latitude &&
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

                  if (listenables.homePoint == null) {
                    listenables.homePoint = point;
                    listenables.polygon.add(point);
                    _applyDrawnPolygon(listenables, fitToMap: true);
                    return;
                  }

                  final alreadyExists = listenables.polygon.any(
                    (existing) => existing.latitude == point.latitude &&
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
                }
              ),
              children: [
                TileLayer(
                    tileProvider: CancellableNetworkTileProvider(),
                    tileBuilder:
                        Theme.of(context).brightness == Brightness.dark &&
                                _selectedMapLayer == MapLayer.streets
                            ? (context, tileWidget, tile) =>
                                darkModeTileBuilder(context, tileWidget, tile)
                            : null,
                    urlTemplate: _selectedMapLayer == MapLayer.streets
                        ? 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}'
                        : 'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}',
                    userAgentPackageName: 'com.yarosfpv.dji_mapper',
                    subdomains: const ['mt0', 'mt1', 'mt2', 'mt3']
                  ),
                // flight path boundary
                PolygonLayer(polygons: [
                  if (listenables.polygon.length > 1)
                    Polygon(
                        points: listenables.polygon,
                        color:
                            Theme.of(context).colorScheme.primary.withAlpha(77),
                        borderColor: Theme.of(context).colorScheme.primary,
                        borderStrokeWidth: 3),
                ]),
                // flightLine, takeoffLine & returnLine
                if (listenables.homePoint != null) 
                  PolylineLayer(
                    polylines: [
                      if (listenables.flightLine != null) listenables.flightLine!,
                      if (listenables.takeoffLine != null) listenables.takeoffLine!,  // dotted start line from home
                      if (listenables.returnLine != null) listenables.returnLine!,  // dotted return line to home
                    ],
                  ),
                // directional flight path arrows
                MarkerLayer(markers: _flightLineArrowMarkers),
                MarkerLayer(markers: _takeoffLineArrowMarkers),
                MarkerLayer(markers: _returnLineArrowMarkers),
                // photo markers
                if (listenables.showPoints)
                  MarkerLayer(markers: _photoMarkers),
                if (_isEditingPolygon && listenables.polygon.length >= 2)
                  DragMarkers(
                    markers: [
                      for (int index = 0; index < listenables.polygon.length; index++)
                        DragMarker(
                          size: const Size(36, 36),
                          point: listenables.polygon[index],
                          alignment: Alignment.topCenter,
                          builder: (_, coords, b) {
                            final isSelected = _selectedPolygonPointIndex == index;
                            return Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.22)
                                    : Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withOpacity(0.18),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondary,
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.adjust,
                                  size: 18,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            );
                          },
                          onDragUpdate: (details, latLng) {
                            if (index >= 0 && index < listenables.polygon.length) {
                              listenables.polygon[index] = latLng;
                              _selectedPolygonPointIndex = index;
                            }
                          },
                          onTap: (latLng) {
                            _selectPolygonPoint(listenables, latLng);
                          },
                        ),
                    ],
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withOpacity(0.92),
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
                                  tooltip: 'Changer de couche de carte',
                                  onPressed: () => setState(() {
                                    _selectedMapLayer =
                                        _selectedMapLayer == MapLayer.streets
                                            ? MapLayer.satellite
                                            : MapLayer.streets;
                                    prefs.setInt(
                                        "mapLayer",
                                        _selectedMapLayer == MapLayer.streets
                                            ? 0
                                            : 1);
                                  }),
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
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
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
                                  elevation: 4.0,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 200,
                                      maxWidth: 600,
                                    ),
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final option = options.elementAt(index);
                                        return InkWell(
                                          onTap: () {
                                            onSelected(option);
                                          },
                                          child: Builder(
                                            builder: (context) {
                                              final highlight =
                                                  AutocompleteHighlightedOption
                                                          .of(context) ==
                                                      index;
                                              if (highlight) {
                                                SchedulerBinding.instance
                                                    .addPostFrameCallback(
                                                        (Duration timeStamp) {
                                                  Scrollable.ensureVisible(
                                                      context,
                                                      alignment: 0.5,
                                                  );
                                                });
                                              }
                                              return Container(
                                                color: highlight
                                                    ? Theme.of(context)
                                                        .focusColor
                                                    : null,
                                                padding: const EdgeInsets.all(16.0),
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(option.name),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      },
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
                                TextFormField(
                                  controller: textEditingController,
                                  focusNode: focusNode,
                                  onFieldSubmitted: (value) async {
                                    await _search(textEditingController.text);
                                    if (_searchLocations.isNotEmpty) {
                                      mapProvider.mapController.move(
                                          _searchLocations.first.location, 17);
                                    }
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Search location',
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () =>
                                          textEditingController.clear(),
                                    ),
                                    fillColor:
                                        Theme.of(context).colorScheme.surface,
                                  ),
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
          Flexible(
              flex: 1,
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.primary.withAlpha(125),
                    ),
                    tabs: const [
                      Tab(icon: Icon(Icons.info_outline), text: 'Info'),
                      Tab(icon: Icon(Icons.airplanemode_on), text: 'Aircraft'),
                      Tab(icon: Icon(Icons.photo_camera), text: 'Camera'),
                      Tab(icon: Icon(Icons.file_copy), text: 'File'),
                    ],
                  ),
                  Expanded(
                      child: TabBarView(
                          controller: _tabController,
                          children: const [
                        Info(),
                        AircraftBar(),
                        CameraBar(),
                        ExportBar()
                      ]))
                ],
              ))
        ];
        return Scaffold(
            appBar: const MappingAppBar(),
            body: MediaQuery.of(context).size.width < 700
                ? Column(
                    children: children,
                  )
                : Row(children: children));
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
