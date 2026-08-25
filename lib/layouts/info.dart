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

      if (listenables.polygon.length > 2) {
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

        missionWaypoints = engine.generateWaypoints(
          listenables.polygon,
          listenables.createCameraPoints,
          listenables.fillGrid,
          listenables.homePoint,
        );

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
        area = DroneMappingEngine.calculateArea(listenables.polygon).round();
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

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          _buildToggleCard(
            context: context,
            children: [
              SwitchListTile(
                title: const Text('Create Photo Points'),
                value: listenables.createCameraPoints,
                onChanged: (value) {
                  setState(() {
                    listenables.createCameraPoints = value;
                  });
                },
              ),
              SwitchListTile(
                title: Text(listenables.createCameraPoints ? 'Show Photo Points' : 'Show Waypoints'),
                value: listenables.showPoints,
                onChanged: (value) {
                  setState(() {
                    listenables.showPoints = value;
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Fill Grid'),
                value: listenables.fillGrid,
                onChanged: (value) {
                  setState(() {
                    listenables.fillGrid = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Container(
              padding: const EdgeInsets.all(16),
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
                    'Mission summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (listenables.createCameraPoints)
                    _statRow('Number of photos', '${listenables.photoLocations.length}')
                  else
                    _statRow('Number of waypoints', '${listenables.photoLocations.length}'),
                  const Divider(height: 24),
                  _statRow('Flight distance', '$totalDistance m'),
                  const Divider(height: 24),
                  _statRow('Area', '$area m²'),
                  const Divider(height: 24),
                  _statRow('Flight time estimate', estimatedFlightLabel),
                  const Divider(height: 24),
                  _statRow('Recommended shutter speed', '$recommendedShutterSpeed or faster'),
                  const Divider(height: 24),
                  _statRow('Photo interval', photoIntervalLabel),
                ],
              ),
            ),
          ),
        ],
      );
    }));
  }
  Widget _buildToggleCard({
    required BuildContext context,
    required List<Widget> children,
  }) {
    return Card(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
        child: Column(children: children),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }}
