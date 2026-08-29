import 'package:dji_mapper/core/drone_mapping_engine.dart';
import 'package:dji_mapper/shared/value_listeneables.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Info extends StatefulWidget {
  const Info({super.key});

  @override
  State<Info> createState() => _InfoState();
}

class _InfoState extends State<Info> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(child:
        Consumer<ValueListenables>(builder: (context, listenables, child) {
      var totalDistance = 0;
      var area = 0;
      var recommendedShutterSpeed = "0";
      var photoTimeInterval = 0.0;
      var estimatedFlightLabel = '0h 00m 00s';
      var photoIntervalLabel = '0h 00m 00s';
      var missionWaypoints = listenables.photoLocations;

      final isCorridorValid = listenables.mappingMode == MappingMode.corridor &&
          (listenables.centerline.length >= 2 || listenables.polygon.length >= 2);
      final isGridValid = listenables.mappingMode == MappingMode.grid &&
          listenables.polygon.length > 2;

      if (isCorridorValid || isGridValid) {
        final engine = DroneMappingEngine(
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

        if (listenables.mappingMode == MappingMode.corridor) {
          final activeCenterline = listenables.centerline.isNotEmpty
              ? listenables.centerline
              : listenables.polygon;
          missionWaypoints = engine.generateCorridorWaypoints(
            centerline: activeCenterline,
            corridorWidth: listenables.corridorWidth.toDouble(),
            flightLines: listenables.corridorFlightLines,
            createCameraPoints: listenables.createCameraPoints,
            homePoint: listenables.homePoint,
          );
          area = DroneMappingEngine.calculateCorridorArea(
            activeCenterline,
            listenables.corridorWidth.toDouble(),
          ).round();
        } else {
          missionWaypoints = engine.generateWaypoints(
            listenables.polygon,
            listenables.createCameraPoints,
            listenables.fillGrid,
            listenables.homePoint,
          );
          area = DroneMappingEngine.calculateArea(listenables.polygon).round();
        }

        final mainDistance = DroneMappingEngine.calculateTotalDistance(missionWaypoints);
        final takeoffDistance = listenables.homePoint != null && missionWaypoints.isNotEmpty
            ? DroneMappingEngine.calculateTotalDistance([
                listenables.homePoint!,
                missionWaypoints.first,
              ])
            : 0.0;
        final returnDistance = listenables.homePoint != null && missionWaypoints.isNotEmpty
            ? DroneMappingEngine.calculateTotalDistance([
                missionWaypoints.last,
                listenables.homePoint!,
              ])
            : 0.0;

        totalDistance = (mainDistance + takeoffDistance + returnDistance).round();
        recommendedShutterSpeed =
          DroneMappingEngine.calculateRecommendedShutterSpeed(
            altitude: listenables.altitude - listenables.groundOffset,
            sensorWidth: listenables.sensorWidth,
            focalLength: listenables.focalLength,
            imageWidth: listenables.imageWidth,
            droneSpeed: listenables.speed,
          );
        photoTimeInterval = DroneMappingEngine.calculatePhotoTimeInterval(
          altitude: listenables.altitude,
          sensorHeight: listenables.sensorHeight,
          focalLength: listenables.focalLength,
          imageHeight: listenables.imageHeight,
          forwardOverlap: listenables.forwardOverlap / 100.0,
          droneSpeed: listenables.speed,
          groundOffset: listenables.groundOffset,
        );

        final estimatedSeconds =
            (totalDistance / listenables.speed) +
            (missionWaypoints.length * listenables.delayAtWaypoint) +
            (missionWaypoints.isNotEmpty ? 30.0 : 0.0);

        final secondsValue = estimatedSeconds.ceil();
        final hours = (secondsValue ~/ 3600);
        final minutes = (secondsValue % 3600) ~/ 60;
        final seconds = secondsValue % 60;
        estimatedFlightLabel = '${hours}h ${minutes}m ${seconds}s';

        final photoIntervalSeconds = photoTimeInterval.ceil();
        final intervalHours = (photoIntervalSeconds ~/ 3600);
        final intervalMinutes = (photoIntervalSeconds % 3600) ~/ 60;
        final intervalSeconds = photoIntervalSeconds % 60;
        photoIntervalLabel = '${intervalHours}h ${intervalMinutes}m ${intervalSeconds}s';
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mission Options',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.2,
                      children: [
                        _buildGridToggle(
                          context: context,
                          title: 'Photo Points',
                          icon: Icons.camera_alt_outlined,
                          value: listenables.createCameraPoints,
                          onChanged: (val) {
                            setState(() {
                              listenables.createCameraPoints = val;
                            });
                          },
                        ),
                        _buildGridToggle(
                          context: context,
                          title: listenables.createCameraPoints ? 'Show Photos' : 'Show Waypts',
                          icon: Icons.visibility_outlined,
                          value: listenables.showPoints,
                          onChanged: (val) {
                            setState(() {
                              listenables.showPoints = val;
                            });
                          },
                        ),
                        _buildGridToggle(
                          context: context,
                          title: 'Fill Grid',
                          icon: Icons.grid_on_rounded,
                          value: listenables.fillGrid,
                          onChanged: (val) {
                            setState(() {
                              listenables.fillGrid = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(120),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mission Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.6,
                      children: [
                        _buildStatGridTile(
                          context: context,
                          icon: listenables.createCameraPoints
                              ? Icons.photo_library_outlined
                              : Icons.pin_drop_outlined,
                          label: listenables.createCameraPoints ? 'Photos' : 'Waypoints',
                          value: '${listenables.photoLocations.length}',
                        ),
                        _buildStatGridTile(
                          context: context,
                          icon: Icons.straighten_outlined,
                          label: 'Distance',
                          value: '$totalDistance m',
                        ),
                        _buildStatGridTile(
                          context: context,
                          icon: Icons.crop_free_outlined,
                          label: 'Area',
                          value: '$area m²',
                        ),
                        _buildStatGridTile(
                          context: context,
                          icon: Icons.timer_outlined,
                          label: 'Est. Time',
                          value: estimatedFlightLabel,
                        ),
                        _buildStatGridTile(
                          context: context,
                          icon: Icons.speed_outlined,
                          label: 'Shutter',
                          value: '$recommendedShutterSpeed or faster',
                        ),
                        _buildStatGridTile(
                          context: context,
                          icon: Icons.timelapse_outlined,
                          label: 'Interval',
                          value: photoIntervalLabel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }));
  }

  Widget _buildGridToggle({
    required BuildContext context,
    required String title,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: value
          ? colorScheme.primary.withAlpha(28)
          : colorScheme.surfaceContainerHighest.withAlpha(80),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value
                  ? colorScheme.primary.withAlpha(180)
                  : colorScheme.outlineVariant.withAlpha(90),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withAlpha(25),
                ),
                child: Icon(
                  value ? Icons.check_rounded : icon,
                  size: 14,
                  color: value
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: value ? FontWeight.w700 : FontWeight.w500,
                    color: value ? colorScheme.primary : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatGridTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(100),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withAlpha(24),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 13, color: colorScheme.primary),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
