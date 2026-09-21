import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dji_mapper/components/app_bar.dart';
import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:dji_mapper/core/geometry_validator.dart';
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
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/aircraft_settings.dart';

enum MapLayer { streets, satellite, openStreetMap }
enum MapMeasureMode { distance, area, radius, coordinate }

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
  bool _isMeasuring = false;
  MapMeasureMode _measureMode = MapMeasureMode.distance;
  final List<LatLng> _measurePoints = [];
  Uint8List? _orthophotoBytes;
  LatLngBounds? _orthophotoBounds;
  double _orthophotoOpacity = 0.65;
  bool _showBaseMap = true;
  bool _showOrthophoto = true;

  Future<void> _showLayerPanel() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Couches de la carte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                value: _showBaseMap,
                title: Text(_getMapLayerName(_selectedMapLayer)),
                subtitle: const Text('Fond cartographique'),
                onChanged: (value) {
                  setState(() => _showBaseMap = value);
                  setDialogState(() {});
                },
              ),
              if (_orthophotoBytes != null)
                SwitchListTile(
                  value: _showOrthophoto,
                  title: const Text('Orthophoto'),
                  subtitle: Text('${(_orthophotoOpacity * 100).round()}% d’opacité'),
                  onChanged: (value) {
                    setState(() => _showOrthophoto = value);
                    setDialogState(() {});
                  },
                ),
              DropdownButtonFormField<MapLayer>(
                initialValue: _selectedMapLayer,
                decoration: const InputDecoration(labelText: 'Fond cartographique'),
                items: MapLayer.values
                    .map((layer) => DropdownMenuItem(
                          value: layer,
                          child: Text(_getMapLayerName(layer)),
                        ))
                    .toList(),
                onChanged: (layer) {
                  if (layer == null) return;
                  setState(() => _selectedMapLayer = layer);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importOrthophoto(MapProvider mapProvider) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'tif', 'tiff', 'png', 'jpg', 'jpeg', 'webp',
        'tfw', 'jgw', 'pgw', 'wld',
      ],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;

    final imageFile = result.files.cast<PlatformFile?>().firstWhere(
      (file) => file != null && _isRasterFile(file.name),
      orElse: () => null,
    );
    if (imageFile?.bytes == null) {
      _showMessage('Sélectionnez une image raster (.tif, .png, .jpg).');
      return;
    }
    final file = imageFile!;
    try {
      final isTiff = file.name.toLowerCase().endsWith('.tif') ||
        file.name.toLowerCase().endsWith('.tiff');
      final decoded = isTiff
        ? img.decodeTiff(file.bytes!)
        : img.decodeImage(file.bytes!);
      if (decoded == null) throw const FormatException('Image illisible');
      const maxRasterDimension = 4096;
      final displayImage = decoded.width > maxRasterDimension ||
          decoded.height > maxRasterDimension
        ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height
            ? maxRasterDimension
            : null,
          height: decoded.height > decoded.width
            ? maxRasterDimension
            : null,
        )
        : decoded;
      final pngBytes = Uint8List.fromList(img.encodePng(displayImage));
      final worldFile = result.files.cast<PlatformFile?>().firstWhere(
        (candidate) => candidate != null && _isWorldFile(candidate.name),
        orElse: () => null,
      );
      final bounds = worldFile?.bytes == null
          ? await _askOrthophotoBounds(context, file.name)
          : _boundsFromWorldFile(worldFile!.bytes!, decoded.width, decoded.height);
      if (bounds == null) {
        _showMessage(
          'Géoréférencement invalide. Fournissez un fichier world valide ou saisissez les bornes GPS.',
        );
        return;
      }
      if (!mounted) return;

      setState(() {
        _orthophotoBytes = pngBytes;
        _orthophotoBounds = bounds;
      });
      mapProvider.mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (error) {
      if (!mounted) return;
      final fileSizeMb = file.bytes!.lengthInBytes / (1024 * 1024);
      final advice = fileSizeMb > 250
          ? 'Le fichier dépasse 250 Mo: exportez une orthophoto tuilée ou réduite.'
          : 'Exportez depuis Pix4D en TIFF RGB 8 bits non BigTIFF, ou en PNG/JPEG.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'TIFF Pix4D non reconnu (${fileSizeMb.toStringAsFixed(1)} Mo). '
            '$advice Détail: $error',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  bool _isRasterFile(String name) {
    final lowerName = name.toLowerCase();
    return ['.tif', '.tiff', '.png', '.jpg', '.jpeg', '.webp']
        .any(lowerName.endsWith);
  }

  bool _isWorldFile(String name) {
    final lowerName = name.toLowerCase();
    return ['.tfw', '.jgw', '.pgw', '.wld'].any(lowerName.endsWith);
  }

  LatLngBounds? _boundsFromWorldFile(
    Uint8List bytes,
    int width,
    int height,
  ) {
    final values = String.fromCharCodes(bytes)
        .split(RegExp(r'[\s,;]+'))
        .where((value) => value.isNotEmpty)
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    if (values.length < 6) return null;

    final pixelWidth = values[0];
    final rotationY = values[1];
    final rotationX = values[2];
    final pixelHeight = values[3];
    final centerX = values[4];
    final centerY = values[5];
    final corners = [
      Offset(centerX - pixelWidth / 2, centerY - rotationY / 2),
      Offset(
        centerX + pixelWidth * (width - 0.5) + rotationX * (height - 0.5),
        centerY + rotationY * (width - 0.5) + pixelHeight * (height - 0.5),
      ),
    ];
    final west = corners.map((corner) => corner.dx).reduce((a, b) => a < b ? a : b);
    final east = corners.map((corner) => corner.dx).reduce((a, b) => a > b ? a : b);
    final south = corners.map((corner) => corner.dy).reduce((a, b) => a < b ? a : b);
    final north = corners.map((corner) => corner.dy).reduce((a, b) => a > b ? a : b);
    if (north <= south || east <= west || north.abs() > 90 || south.abs() > 90 ||
        east.abs() > 180 || west.abs() > 180) {
      return null;
    }
    return LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<LatLngBounds?> _askOrthophotoBounds(
    BuildContext context,
    String fileName,
  ) async {
    final north = TextEditingController();
    final south = TextEditingController();
    final east = TextEditingController();
    final west = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final bounds = await showDialog<LatLngBounds>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Positionner l’orthophoto'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$fileName\nEntrez les limites géographiques en degrés WGS84.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _coordinateField(north, 'Latitude nord', 90),
                _coordinateField(south, 'Latitude sud', 90),
                _coordinateField(east, 'Longitude est', 180),
                _coordinateField(west, 'Longitude ouest', 180),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final northValue = double.parse(north.text.trim());
              final southValue = double.parse(south.text.trim());
              final eastValue = double.parse(east.text.trim());
              final westValue = double.parse(west.text.trim());
              if (northValue <= southValue || eastValue <= westValue) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Les limites ne forment pas une emprise valide.')),
                );
                return;
              }
              Navigator.pop(
                dialogContext,
                LatLngBounds(
                  LatLng(southValue, westValue),
                  LatLng(northValue, eastValue),
                ),
              );
            },
            child: const Text('Importer'),
          ),
        ],
      ),
    );
    north.dispose();
    south.dispose();
    east.dispose();
    west.dispose();
    return bounds;
  }

  Widget _coordinateField(
    TextEditingController controller,
    String label,
    double limit,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(labelText: label, suffixText: '°'),
      validator: (value) {
        final parsed = double.tryParse(value?.trim() ?? '');
        if (parsed == null || parsed.abs() > limit) return 'Valeur entre -$limit et $limit';
        return null;
      },
    );
  }

    ({double easting, double northing}) _toUtm35South(LatLng point) {
    const semiMajorAxis = 6378137.0;
    const inverseFlattening = 298.257223563;
    const scaleFactor = 0.9996;
    const centralMeridian = 27.0 * math.pi / 180.0;
    const falseEasting = 500000.0;
    const falseNorthing = 10000000.0;

    final flattening = 1 / inverseFlattening;
    final eccentricitySquared = flattening * (2 - flattening);
    final secondEccentricitySquared =
      eccentricitySquared / (1 - eccentricitySquared);
    final latitude = point.latitude * math.pi / 180.0;
    final longitude = point.longitude * math.pi / 180.0;
    final sinLatitude = math.sin(latitude);
    final cosLatitude = math.cos(latitude);
    final tangentLatitude = math.tan(latitude);
    final radiusOfCurvature =
      semiMajorAxis / math.sqrt(1 - eccentricitySquared * sinLatitude * sinLatitude);
    final meridianArc = semiMajorAxis * ((1 - eccentricitySquared / 4 -
        3 * math.pow(eccentricitySquared, 2) / 64 -
        5 * math.pow(eccentricitySquared, 3) / 256) * latitude -
      (3 * eccentricitySquared / 8 +
          3 * math.pow(eccentricitySquared, 2) / 32 +
          45 * math.pow(eccentricitySquared, 3) / 1024) * math.sin(2 * latitude) +
      (15 * math.pow(eccentricitySquared, 2) / 256 +
          45 * math.pow(eccentricitySquared, 3) / 1024) * math.sin(4 * latitude) -
      (35 * math.pow(eccentricitySquared, 3) / 3072) * math.sin(6 * latitude));
    final transverse = secondEccentricitySquared * cosLatitude * cosLatitude;
    final deltaLongitude = longitude - centralMeridian;
    final deltaLongitudeSquared = deltaLongitude * deltaLongitude;

    final easting = falseEasting + scaleFactor * radiusOfCurvature *
      (deltaLongitude * cosLatitude +
        (1 - tangentLatitude * tangentLatitude + transverse) *
          math.pow(deltaLongitude, 3) * cosLatitude / 6 +
        (5 - 18 * tangentLatitude * tangentLatitude +
            math.pow(tangentLatitude, 4) +
            72 * transverse -
            58 * secondEccentricitySquared) *
          math.pow(deltaLongitude, 5) * cosLatitude / 120);
    final northing = falseNorthing + scaleFactor * (meridianArc + radiusOfCurvature *
      tangentLatitude * (deltaLongitudeSquared * cosLatitude * cosLatitude / 2 +
        (5 - tangentLatitude * tangentLatitude +
            9 * transverse +
            4 * transverse * transverse) *
          math.pow(deltaLongitude, 4) * math.pow(cosLatitude, 4) / 24 +
        (61 - 58 * tangentLatitude * tangentLatitude +
            math.pow(tangentLatitude, 4) +
            600 * transverse -
            330 * secondEccentricitySquared) *
          math.pow(deltaLongitude, 6) * math.pow(cosLatitude, 6) / 720));

    return (easting: easting, northing: northing);
    }

  ({double latitude, double longitude}) _degreeLengthsInMeters(LatLng point) {
    const semiMajorAxis = 6378137.0;
    const inverseFlattening = 298.257223563;
    final flattening = 1 / inverseFlattening;
    final eccentricitySquared = flattening * (2 - flattening);
    final latitude = point.latitude * math.pi / 180.0;
    final sinLatitude = math.sin(latitude);
    final cosLatitude = math.cos(latitude);
    final denominator = 1 - eccentricitySquared * sinLatitude * sinLatitude;
    final meridianRadius = semiMajorAxis * (1 - eccentricitySquared) /
        math.pow(denominator, 1.5);
    final primeVerticalRadius = semiMajorAxis / math.sqrt(denominator);

    return (
      latitude: meridianRadius * math.pi / 180.0,
      longitude: primeVerticalRadius * cosLatitude * math.pi / 180.0,
    );
  }

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

  GeometryValidationResult? _geometryValidationResult;

  void _updateGeometryValidation(ValueListenables listenables) {
    if (listenables.mappingMode == MappingMode.corridor) {
      final active = listenables.centerline.isNotEmpty
          ? listenables.centerline
          : listenables.polygon;
      if (active.length >= 2) {
        _geometryValidationResult = GeometryValidator.validateCorridor(active);
      } else {
        _geometryValidationResult = null;
      }
    } else if (listenables.mappingMode == MappingMode.waypoint) {
      final active = listenables.waypoints.isNotEmpty
          ? listenables.waypoints
          : (listenables.centerline.isNotEmpty
              ? listenables.centerline
              : listenables.polygon);
      if (active.length >= 2) {
        _geometryValidationResult = GeometryValidator.validateCorridor(active);
      } else {
        _geometryValidationResult = null;
      }
    } else {
      if (listenables.polygon.length >= 3) {
        _geometryValidationResult = GeometryValidator.validatePolygon(listenables.polygon);
      } else {
        _geometryValidationResult = null;
      }
    }
  }

  Widget _buildGeometryHealthBadge(BuildContext context, ValueListenables listenables) {
    final res = _geometryValidationResult;
    if (res == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final bool isError = res.hasErrors;
    final bool isWarning = res.hasWarnings && !isError;

    final Color badgeColor = isError
        ? colorScheme.error
        : isWarning
            ? Colors.orange.shade700
            : Colors.green;

    final IconData badgeIcon = isError
        ? Icons.error_outline_rounded
        : isWarning
            ? Icons.warning_amber_rounded
            : Icons.check_circle_outline_rounded;

    final String statusLabel = isError
        ? 'Géométrie invalide (${res.issues.length})'
        : isWarning
            ? 'Avertissement (${res.issues.length})'
            : 'Géométrie conforme';

    return Material(
      color: Theme.of(context).colorScheme.surface.withAlpha(235),
      borderRadius: BorderRadius.circular(14),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showGeometryDiagnosticsDialog(context, listenables),
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
                badgeIcon,
                size: 16,
                color: badgeColor,
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isError
                      ? colorScheme.error
                      : colorScheme.onSurface,
                  letterSpacing: 0.1,
                ),
              ),
              if (res.issues.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: badgeColor.withAlpha(45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${res.issues.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showGeometryDiagnosticsDialog(
    BuildContext context,
    ValueListenables listenables,
  ) async {
    final res = _geometryValidationResult;
    if (res == null) return;

    final colorScheme = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                res.hasErrors
                    ? Icons.error_outline_rounded
                    : res.hasWarnings
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded,
                color: res.hasErrors
                    ? colorScheme.error
                    : res.hasWarnings
                        ? Colors.orange.shade700
                        : Colors.green,
              ),
              const SizedBox(width: 10),
              Text(
                'Diagnostic de Géométrie',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              listenables.mappingMode == MappingMode.corridor ||
                                      listenables.mappingMode ==
                                          MappingMode.waypoint
                                  ? 'Longueur'
                                  : 'Surface',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              listenables.mappingMode ==
                                          MappingMode.corridor ||
                                      listenables.mappingMode ==
                                          MappingMode.waypoint
                                  ? '${res.perimeterMeters.toStringAsFixed(1)} m'
                                  : res.areaSquareMeters >= 10000
                                      ? '${(res.areaSquareMeters / 10000).toStringAsFixed(2)} ha'
                                      : '${res.areaSquareMeters.toStringAsFixed(0)} m²',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              'Sommets',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${listenables.mappingMode == MappingMode.corridor ? listenables.centerline.length : (listenables.mappingMode == MappingMode.waypoint ? listenables.waypoints.length : listenables.polygon.length)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          children: [
                            Text(
                              'État',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              res.isValid ? 'Conforme' : 'Non conforme',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: res.isValid ? Colors.green : colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (res.issues.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withAlpha(80)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified, color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'La forme est géométriquement parfaite pour un balayage de mission propre.',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Text(
                      'Anomalies détectées (${res.issues.length}) :',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (final issue in res.issues) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: issue.severity == GeometryIssueSeverity.error
                              ? colorScheme.error.withAlpha(15)
                              : Colors.orange.withAlpha(15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: issue.severity == GeometryIssueSeverity.error
                                ? colorScheme.error.withAlpha(70)
                                : Colors.orange.withAlpha(70),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              issue.severity == GeometryIssueSeverity.error
                                  ? Icons.cancel_rounded
                                  : Icons.warning_rounded,
                              color: issue.severity == GeometryIssueSeverity.error
                                  ? colorScheme.error
                                  : Colors.orange.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    issue.title,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: issue.severity == GeometryIssueSeverity.error
                                          ? colorScheme.error
                                          : Colors.orange.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    issue.description,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (res.issues.isNotEmpty)
                  FilledButton.icon(
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text('Auto-réparer'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _autoRepairGeometry(listenables);
                    },
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.turn_right_rounded, size: 16),
                  label: const Text('Angles 90°'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _orthogonalizePolygonGeometry(listenables);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_cut_rounded, size: 16),
                  label: const Text('Simplifier sommets'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _simplifyPolygonGeometry(listenables);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Inverser sens'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _reversePolygonGeometry(listenables);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _orthogonalizePolygonGeometry(ValueListenables listenables) {
    if (listenables.polygon.length < 3) return;
    setState(() {
      listenables.polygon = _orthogonalizePolygon(listenables.polygon);
      _selectedPolygonPointIndex = null;
      _applyDrawnPolygon(listenables, fitToMap: true);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Angles orthogonalisés à 90° avec succès.')),
    );
  }

  void _simplifyPolygonGeometry(ValueListenables listenables) {
    if (listenables.polygon.length < 4) return;
    setState(() {
      listenables.polygon = GeometryValidator.simplifyPolygon(listenables.polygon, toleranceMeters: 2.0);
      _selectedPolygonPointIndex = null;
      _applyDrawnPolygon(listenables, fitToMap: true);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Polygone simplifié : ${listenables.polygon.length} sommets restants.')),
    );
  }

  void _reversePolygonGeometry(ValueListenables listenables) {
    if (listenables.mappingMode == MappingMode.corridor) {
      if (listenables.centerline.length < 2) return;
      setState(() {
        listenables.centerline = listenables.centerline.reversed.toList();
        _applyDrawnPolygon(listenables, fitToMap: false);
      });
    } else if (listenables.mappingMode == MappingMode.waypoint) {
      if (listenables.waypoints.length < 2) return;
      setState(() {
        listenables.waypoints = listenables.waypoints.reversed.toList();
        _applyDrawnPolygon(listenables, fitToMap: false);
      });
    } else {
      if (listenables.polygon.length < 3) return;
      setState(() {
        listenables.polygon = listenables.polygon.reversed.toList();
        _applyDrawnPolygon(listenables, fitToMap: true);
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sens de parcours inversé.')),
    );
  }

  void _autoRepairGeometry(ValueListenables listenables) {
    if (listenables.mappingMode == MappingMode.corridor) {
      final active = listenables.centerline.isNotEmpty
          ? listenables.centerline
          : listenables.polygon;
      if (active.length < 2) return;
      final repaired = GeometryValidator.repairCorridor(active);
      setState(() {
        listenables.centerline = repaired;
        _selectedPolygonPointIndex = null;
        _applyDrawnPolygon(listenables, fitToMap: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracé corridor auto-réparé avec succès.')),
      );
    } else {
      if (listenables.polygon.length < 3) return;
      final repaired = GeometryValidator.repairPolygon(listenables.polygon);
      setState(() {
        listenables.polygon = repaired;
        _selectedPolygonPointIndex = null;
        _applyDrawnPolygon(listenables, fitToMap: true);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Polygone auto-réparé avec succès (croisements et points doublons nettoyés).')),
      );
    }
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

  Widget _buildMeasurementHUD(BuildContext context) {
    if (!_isMeasuring) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final totalDistance = DroneMappingEngine.calculateTotalDistance(_measurePoints);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final measurementValidation = _measureMode == MapMeasureMode.area
      ? GeometryValidator.validatePolygon(_measurePoints)
      : null;

    Widget modeButton({
      required MapMeasureMode mode,
      required String label,
      required IconData icon,
    }) {
      final isSelected = _measureMode == mode;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _measureMode = mode;
            _measurePoints.clear();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.amber.shade700
                : (isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(10)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? Colors.white
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildMetrics() {
      switch (_measureMode) {
        case MapMeasureMode.distance:
          final distStr = totalDistance >= 1000
              ? '${(totalDistance / 1000).toStringAsFixed(3)} km'
              : '${totalDistance.toStringAsFixed(1)} m';
          String formatDistance(double distance) => distance >= 1000
              ? '${(distance / 1000).toStringAsFixed(2)} km'
              : '${distance.toStringAsFixed(1)} m';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _measurePoints.length < 2
                    ? (_measurePoints.isEmpty
                        ? 'Cliquez sur la carte pour poser le 1er point de mesure'
                        : 'Cliquez pour ajouter d\'autres points')
                    : 'Distance totale : $distStr',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _measurePoints.length >= 2 ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                ),
              ),
              if (_measurePoints.length >= 2)
                Text(
                  '${_measurePoints.length} points · ${_measurePoints.length - 1} segment${_measurePoints.length > 2 ? "s" : ""}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              if (_measurePoints.length >= 2) ...[
                const SizedBox(height: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 82),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = 0; i < _measurePoints.length - 1; i++)
                          Text(
                            'P${i + 1} → P${i + 2} : ${formatDistance(const Distance().as(LengthUnit.Meter, _measurePoints[i], _measurePoints[i + 1]))}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );

        case MapMeasureMode.area:
          final hasGeometryErrors = measurementValidation?.hasErrors ?? false;
          final area = _measurePoints.length >= 3 && !hasGeometryErrors
              ? DroneMappingEngine.calculateArea(_measurePoints)
              : 0.0;
          final perimeter = DroneMappingEngine.calculateTotalDistance([
            ..._measurePoints,
            if (_measurePoints.length >= 3) _measurePoints.first,
          ]);

          final areaStr = area >= 1000000
              ? '${(area / 1000000).toStringAsFixed(3)} km²'
              : area >= 10000
                  ? '${(area / 10000).toStringAsFixed(2)} ha (${area.toStringAsFixed(0)} m²)'
                  : '${area.toStringAsFixed(1)} m²';
          final perimStr = perimeter >= 1000
              ? '${(perimeter / 1000).toStringAsFixed(2)} km'
              : '${perimeter.toStringAsFixed(1)} m';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _measurePoints.length < 3
                    ? 'Posez au moins 3 points pour mesurer une surface (${_measurePoints.length}/3)'
                    : hasGeometryErrors
                        ? 'Surface invalide : ${measurementValidation!.summaryMessage}'
                        : 'Surface : $areaStr',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: hasGeometryErrors
                      ? colorScheme.error
                      : _measurePoints.length >= 3
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                ),
              ),
              if (_measurePoints.length >= 3 && !hasGeometryErrors)
                Text(
                  'Périmètre : $perimStr · ${_measurePoints.length} sommets',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              if (_measurePoints.length >= 3 && measurementValidation!.hasWarnings)
                Text(
                  measurementValidation.summaryMessage,
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                ),
            ],
          );

        case MapMeasureMode.radius:
          if (_measurePoints.length < 2) {
            return Text(
              _measurePoints.isEmpty
                  ? 'Cliquez pour définir le CENTRE du cercle'
                  : 'Cliquez pour définir le RAYON',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            );
          }
          final radius = const Distance().as(LengthUnit.Meter, _measurePoints[0], _measurePoints[1]);
          final circleArea = 3.141592653589793 * radius * radius;
          final circ = 2 * 3.141592653589793 * radius;

          final radStr = radius >= 1000 ? '${(radius / 1000).toStringAsFixed(2)} km' : '${radius.toStringAsFixed(1)} m';
          final areaStr = circleArea >= 10000 ? '${(circleArea / 10000).toStringAsFixed(2)} ha' : '${circleArea.toStringAsFixed(0)} m²';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rayon : $radStr · Aire : $areaStr',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              Text(
                'Circonférence : ${circ >= 1000 ? (circ / 1000).toStringAsFixed(2) + " km" : circ.toStringAsFixed(1) + " m"}',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          );

        case MapMeasureMode.coordinate:
          if (_measurePoints.isEmpty) {
            return Text(
              'Cliquez sur la carte pour inspecter les coordonnées GPS d\'un point',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurfaceVariant,
              ),
            );
          }
          final pt = _measurePoints.first;
          final dms = GeometryValidator.formatCoordinatesDMS(pt);
          final utm = _toUtm35South(pt);
          final degreeLengths = _degreeLengthsInMeters(pt);
          final isInsideUtm35 = pt.longitude >= 24 && pt.longitude <= 30;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WGS84 : ${pt.latitude.toStringAsFixed(6)}°, ${pt.longitude.toStringAsFixed(6)}°',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              Text(
                'DMS : $dms',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 3),
              Text(
                'EPSG:32735 (UTM 35S) : E ${utm.easting.toStringAsFixed(2)} m · N ${utm.northing.toStringAsFixed(2)} m',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colorScheme.onSurface),
              ),
              Text(
                'Équivalence locale : 1° latitude ≈ ${degreeLengths.latitude.toStringAsFixed(2)} m · 1° longitude ≈ ${degreeLengths.longitude.toStringAsFixed(2)} m',
                style: TextStyle(fontSize: 10.8, color: colorScheme.onSurfaceVariant),
              ),
              if (!isInsideUtm35)
                Text(
                  'Attention : longitude hors de la zone UTM 35 (24°E à 30°E).',
                  style: TextStyle(fontSize: 10.5, color: Colors.orange.shade700),
                ),
            ],
          );
      }
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0, left: 16, right: 16),
        child: Material(
          color: Theme.of(context).colorScheme.surface.withAlpha(245),
          borderRadius: BorderRadius.circular(18),
          elevation: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.amber.shade600.withAlpha(160),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    modeButton(
                      mode: MapMeasureMode.distance,
                      label: 'Distance',
                      icon: Icons.straighten_rounded,
                    ),
                    const SizedBox(width: 6),
                    modeButton(
                      mode: MapMeasureMode.area,
                      label: 'Surface',
                      icon: Icons.polyline_rounded,
                    ),
                    const SizedBox(width: 6),
                    modeButton(
                      mode: MapMeasureMode.radius,
                      label: 'Rayon',
                      icon: Icons.radar_rounded,
                    ),
                    const SizedBox(width: 6),
                    modeButton(
                      mode: MapMeasureMode.coordinate,
                      label: 'Point GPS',
                      icon: Icons.location_on_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _measureMode == MapMeasureMode.distance
                            ? Icons.straighten_rounded
                            : _measureMode == MapMeasureMode.area
                                ? Icons.polyline_rounded
                                : _measureMode == MapMeasureMode.radius
                                    ? Icons.radar_rounded
                                    : Icons.location_on_rounded,
                        color: Colors.amber.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: buildMetrics(),
                    ),
                    if (_measureMode == MapMeasureMode.coordinate && _measurePoints.isNotEmpty) ...[
                      Tooltip(
                        message: 'Copier les coordonnées',
                        child: IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            final pt = _measurePoints.first;
                            final utm = _toUtm35South(pt);
                            Clipboard.setData(ClipboardData(
                              text: 'WGS84: ${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)}\n'
                                  'DMS: ${GeometryValidator.formatCoordinatesDMS(pt)}\n'
                                  'EPSG:32735 UTM 35S: E ${utm.easting.toStringAsFixed(2)} m, N ${utm.northing.toStringAsFixed(2)} m',
                            ));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Coordonnées copiées dans le presse-papiers !'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ),
                    ],
                    if (_measurePoints.isNotEmpty && _measureMode != MapMeasureMode.coordinate) ...[
                      Tooltip(
                        message: 'Annuler le dernier point',
                        child: IconButton(
                          icon: const Icon(Icons.undo_rounded, size: 19),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _measurePoints.removeLast();
                            });
                          },
                        ),
                      ),
                    ],
                    if (_measurePoints.isNotEmpty) ...[
                      Tooltip(
                        message: 'Effacer la mesure',
                        child: IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 19),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _measurePoints.clear();
                            });
                          },
                        ),
                      ),
                    ],
                    Tooltip(
                      message: 'Fermer la règle',
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 19),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _isMeasuring = false;
                            _measurePoints.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Marker _buildSegmentDistanceMarker(BuildContext context, LatLng p1, LatLng p2) {
    final dist = const Distance().as(LengthUnit.Meter, p1, p2);
    final midPoint = LatLng(
      (p1.latitude + p2.latitude) / 2,
      (p1.longitude + p2.longitude) / 2,
    );
    final label = dist >= 1000
        ? '${(dist / 1000).toStringAsFixed(2)} km'
        : '${dist.toStringAsFixed(1)} m';

    return Marker(
      point: midPoint,
      width: 80,
      height: 24,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black.withAlpha(210)
              : Colors.white.withAlpha(225),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.amber.shade700,
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.amber.shade300
                : Colors.amber.shade900,
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
    final cameraPresets = PresetManager.getPresets();

    // Load the latest camera preset
    var latestPresetName = prefs.getString("latestPreset");
    if (latestPresetName == null) {
      latestPresetName = cameraPresets[0].name;
      prefs.setString("latestPreset", latestPresetName);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      listenables.selectedCameraPreset = cameraPresets.firstWhere(
        (element) => element.name == latestPresetName,
        orElse: () => cameraPresets[0],
      );
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
      UpdateChecker.checkForUpdate().then((latestVersion) {
        if (latestVersion != null && mounted) {
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
                  ));
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
        : (listenables.mappingMode == MappingMode.waypoint
            ? listenables.waypoints
            : listenables.polygon);
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

    if (listenables.mappingMode == MappingMode.waypoint) {
      if (_selectedPolygonPointIndex! < 0 ||
          _selectedPolygonPointIndex! >= listenables.waypoints.length) {
        _selectedPolygonPointIndex = null;
        return;
      }

      setState(() {
        listenables.waypoints.removeAt(_selectedPolygonPointIndex!);
        _selectedPolygonPointIndex = null;
        if (listenables.waypoints.isEmpty) {
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
    _updateGeometryValidation(listenables);

    if (listenables.mappingMode == MappingMode.waypoint) {
      if (listenables.waypoints.isEmpty && listenables.centerline.isNotEmpty) {
        listenables.waypoints = List.from(listenables.centerline);
      } else if (listenables.waypoints.isEmpty && listenables.polygon.isNotEmpty) {
        listenables.waypoints = List.from(listenables.polygon);
      }
      final waypoints = _normalizePolygon(listenables.waypoints);
      if (waypoints.isEmpty) return;

      listenables.waypoints = waypoints;

      if (listenables.homePoint == null && waypoints.isNotEmpty) {
        listenables.homePoint = waypoints.first;
      }

      if (fitToMap && waypoints.isNotEmpty) {
        final mapProvider = Provider.of<MapProvider>(context, listen: false);
        final bounds = LatLngBounds.fromPoints(waypoints);
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
    if (listenables.mappingMode == MappingMode.waypoint) {
      if (listenables.waypoints.length < 2 &&
          listenables.centerline.length < 2 &&
          listenables.polygon.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Le plan de vol doit contenir au moins 2 waypoints.')),
        );
        return;
      }
    } else if (listenables.mappingMode == MappingMode.corridor) {
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
    _updateGeometryValidation(listenables);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _buildMarkers(listenables);
      }
    });

    if (_geometryValidationResult != null && _geometryValidationResult!.hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ ${_geometryValidationResult!.summaryMessage}'),
          action: SnackBarAction(
            label: 'Diagnostic',
            onPressed: () => _showGeometryDiagnosticsDialog(context, listenables),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(listenables.mappingMode == MappingMode.corridor
              ? 'Tracé corridor validé et conforme.'
              : 'Contour validé et conforme pour la mission.'),
        ),
      );
    }
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
    _updateGeometryValidation(listenables);
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
    if (listenables.mappingMode == MappingMode.waypoint) {
      final activeWaypoints = listenables.waypoints.isNotEmpty
          ? listenables.waypoints
          : (listenables.centerline.isNotEmpty
              ? listenables.centerline
              : listenables.polygon);
      waypoints = droneMapping.generateDirectWaypoints(
        waypoints: activeWaypoints,
        createCameraPoints: listenables.createCameraPoints,
        homePoint: listenables.homePoint,
      );
    } else if (listenables.mappingMode == MappingMode.corridor) {
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
        : (listenables.mappingMode == MappingMode.waypoint
            ? listenables.waypoints
            : listenables.polygon);
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
      listenables.waypoints.length,
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
      if (listenables.waypoints.isNotEmpty) ...[
        listenables.waypoints.first.latitude,
        listenables.waypoints.first.longitude,
        listenables.waypoints.last.latitude,
        listenables.waypoints.last.longitude,
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
    final isWaypointValid = listenables.mappingMode == MappingMode.waypoint &&
        (listenables.waypoints.isNotEmpty ||
            listenables.centerline.isNotEmpty ||
            listenables.polygon.isNotEmpty);

    if ((isCorridorValid || isGridValid || isWaypointValid) && listenables.altitude >= 5) {
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
        _updateGeometryValidation(listenables);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _refreshMissionVisuals(listenables);
        });

        final mapWidget = FlutterMap(
              mapController: mapProvider.mapController,
              options: MapOptions(
                onTap: (tapPosition, point) => setState(() {
                  if (_isMeasuring) {
                    if (_measureMode == MapMeasureMode.coordinate) {
                      _measurePoints.clear();
                      _measurePoints.add(point);
                    } else if (_measureMode == MapMeasureMode.radius) {
                      if (_measurePoints.length >= 2) {
                        _measurePoints[1] = point;
                      } else {
                        _measurePoints.add(point);
                      }
                    } else {
                      _measurePoints.add(point);
                    }
                    return;
                  }

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
                  if (_isMeasuring) {
                    if (_measurePoints.isNotEmpty) {
                      _measurePoints.removeLast();
                    }
                    return;
                  }

                  if (!_isDrawingPolygon) {
                    return;
                  }

                  if (listenables.mappingMode == MappingMode.waypoint) {
                    if (listenables.homePoint == null) {
                      listenables.homePoint = point;
                    }
                    final alreadyExists = listenables.waypoints.any(
                      (existing) =>
                          existing.latitude == point.latitude &&
                          existing.longitude == point.longitude,
                    );
                    if (!alreadyExists) {
                      listenables.waypoints.add(point);
                      _applyDrawnPolygon(listenables, fitToMap: false);
                    }
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
                if (_showBaseMap)
                  ...[
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
                  ],
                if (_showOrthophoto && _orthophotoBytes != null && _orthophotoBounds != null)
                  OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        imageProvider: MemoryImage(_orthophotoBytes!),
                        bounds: _orthophotoBounds!,
                        opacity: _orthophotoOpacity,
                        filterQuality: FilterQuality.high,
                      ),
                    ],
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
                // flightLine, takeoffLine, returnLine & centerline / waypoints
                if (listenables.homePoint != null ||
                    listenables.centerline.isNotEmpty ||
                    listenables.waypoints.isNotEmpty ||
                    listenables.flightLine != null)
                  PolylineLayer(
                    polylines: [
                      if (listenables.mappingMode == MappingMode.corridor &&
                          listenables.centerline.length >= 2)
                        Polyline(
                          points: listenables.centerline,
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      if (listenables.mappingMode == MappingMode.waypoint &&
                          listenables.waypoints.length >= 2 &&
                          listenables.flightLine == null)
                        Polyline(
                          points: listenables.waypoints,
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.primary,
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
                // Geometry intersection warnings on map
                if (_geometryValidationResult != null &&
                    _geometryValidationResult!.intersectionPoints.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (final pt in _geometryValidationResult!.intersectionPoints)
                        Marker(
                          point: pt,
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          child: Tooltip(
                            message: 'Auto-croisement détecté ici (cliquez pour diagnostic)',
                            child: GestureDetector(
                              onTap: () => _showGeometryDiagnosticsDialog(context, listenables),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.shade600,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                // Measurement layers
                if (_isMeasuring && _measureMode == MapMeasureMode.distance && _measurePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _measurePoints,
                        strokeWidth: 3.5,
                        color: Colors.amber.shade700,
                      ),
                    ],
                  ),
                if (_isMeasuring && _measureMode == MapMeasureMode.distance && _measurePoints.length >= 2)
                  MarkerLayer(
                    markers: [
                      for (int i = 0; i < _measurePoints.length - 1; i++)
                        _buildSegmentDistanceMarker(context, _measurePoints[i], _measurePoints[i + 1]),
                    ],
                  ),
                if (_isMeasuring && _measureMode == MapMeasureMode.distance && _measurePoints.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (int i = 0; i < _measurePoints.length; i++)
                        Marker(
                          point: _measurePoints[i],
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.amber.shade600,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black38,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                // Area Measurement
                if (_isMeasuring && _measureMode == MapMeasureMode.area && _measurePoints.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _measurePoints,
                        color: Colors.amber.withAlpha(45),
                        borderColor: Colors.amber.shade700,
                        borderStrokeWidth: 2.5,
                      ),
                    ],
                  ),
                if (_isMeasuring && _measureMode == MapMeasureMode.area && _measurePoints.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (int i = 0; i < _measurePoints.length; i++)
                        Marker(
                          point: _measurePoints[i],
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.amber.shade600,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_isMeasuring &&
                      _measureMode == MapMeasureMode.area &&
                      GeometryValidator.validatePolygon(_measurePoints).intersectionPoints.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        for (final point in GeometryValidator.validatePolygon(_measurePoints).intersectionPoints)
                          Marker(
                            point: point,
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            child: Tooltip(
                              message: 'Intersection détectée dans la surface mesurée',
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.red.shade600,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.close_rounded, size: 17, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                // Radius Measurement
                if (_isMeasuring && _measureMode == MapMeasureMode.radius && _measurePoints.length >= 2) ...[
                  Builder(
                    builder: (context) {
                      final center = _measurePoints[0];
                      final edge = _measurePoints[1];
                      final r = const Distance().as(LengthUnit.Meter, center, edge);
                      final circlePoints = GeometryValidator.generateCirclePoints(center, r);
                      return PolygonLayer(
                        polygons: [
                          Polygon(
                            points: circlePoints,
                            color: Colors.amber.withAlpha(40),
                            borderColor: Colors.amber.shade700,
                            borderStrokeWidth: 2.5,
                          ),
                        ],
                      );
                    },
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [_measurePoints[0], _measurePoints[1]],
                        strokeWidth: 2.5,
                        color: Colors.amber.shade800,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _measurePoints[0],
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.amber.shade700,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.adjust_rounded, size: 18, color: Colors.white),
                        ),
                      ),
                      Marker(
                        point: _measurePoints[1],
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.amber.shade500,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Coordinate Inspector Pin
                if (_isMeasuring && _measureMode == MapMeasureMode.coordinate && _measurePoints.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _measurePoints.first,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.location_on_rounded,
                          size: 38,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                // photo markers
                if (listenables.showPoints)
                  MarkerLayer(markers: _photoMarkers),
                if (_isEditingPolygon)
                  Builder(
                    builder: (context) {
                      final activePoints =
                          listenables.mappingMode == MappingMode.corridor
                              ? listenables.centerline
                              : (listenables.mappingMode == MappingMode.waypoint
                                  ? listenables.waypoints
                                  : listenables.polygon);

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
                                  } else if (listenables.mappingMode ==
                                      MappingMode.waypoint) {
                                    listenables.waypoints[index] = latLng;
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
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
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
                                  tooltip: 'Gérer les couches',
                                  onPressed: _showLayerPanel,
                                ),
                                const SizedBox(width: 4),
                                _mapActionButton(
                                  icon: Icons.add_photo_alternate_rounded,
                                  tooltip: 'Importer une orthophoto GeoTIFF ou image',
                                  onPressed: () => _importOrthophoto(mapProvider),
                                ),
                                if (_orthophotoBytes != null) ...[
                                  const SizedBox(width: 4),
                                  _mapActionButton(
                                    icon: Icons.delete_outline_rounded,
                                    tooltip: 'Retirer l’orthophoto',
                                    onPressed: () => setState(() {
                                      _orthophotoBytes = null;
                                      _orthophotoBounds = null;
                                    }),
                                  ),
                                ],
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
                                  icon: Icons.auto_fix_high_rounded,
                                  tooltip: 'Auto-réparer la géométrie (supprimer auto-croisements)',
                                  onPressed: () => _autoRepairGeometry(listenables),
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
                                  icon: Icons.straighten_rounded,
                                  tooltip: _isMeasuring
                                      ? 'Désactiver la règle de mesure'
                                      : 'Règle de mesure de distance',
                                  selected: _isMeasuring,
                                  onPressed: () {
                                    setState(() {
                                      _isMeasuring = !_isMeasuring;
                                      if (_isMeasuring) {
                                        _isDrawingPolygon = false;
                                        _isEditingPolygon = false;
                                        _measurePoints.clear();
                                      }
                                    });
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(_isMeasuring
                                            ? 'Mode mesure actif : cliquez sur la carte pour mesurer des distances.'
                                            : 'Mode mesure désactivé.'),
                                        duration: const Duration(seconds: 2),
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
                                    listenables.centerline.clear();
                                    listenables.waypoints.clear();
                                    listenables.photoLocations.clear();
                                    _photoMarkers.clear();
                                    _photoFootprints.clear();
                                    listenables.flightLine = null;
                                    listenables.takeoffLine = null;
                                    listenables.returnLine = null;
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
                        ),
                        if (_orthophotoBytes != null)
                          Material(
                            color: Theme.of(context).colorScheme.surface.withAlpha(235),
                            borderRadius: BorderRadius.circular(14),
                            elevation: 3,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.opacity_rounded, size: 18),
                                  SizedBox(
                                    width: 120,
                                    child: Slider(
                                      value: _orthophotoOpacity,
                                      min: 0.1,
                                      max: 1,
                                      onChanged: (value) => setState(() {
                                        _orthophotoOpacity = value;
                                      }),
                                    ),
                                  ),
                                  Text('${(_orthophotoOpacity * 100).round()}%'),
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
                        if (listenables.polygon.length >= 3 ||
                            listenables.centerline.length >= 2) ...[
                          const SizedBox(width: 8),
                          _buildGeometryHealthBadge(context, listenables),
                        ],
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
                _buildMeasurementHUD(context),
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
