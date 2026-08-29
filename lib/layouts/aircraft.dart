import 'package:dji_mapper/shared/aircraft_settings.dart';
import 'package:dji_waypoint_engine/engine.dart';
import 'package:dji_mapper/components/text_field.dart';
import 'package:dji_mapper/shared/value_listeneables.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AircraftBar extends StatefulWidget {
  const AircraftBar({super.key});

  @override
  State<AircraftBar> createState() => _AircraftBarState();
}

class _AircraftBarState extends State<AircraftBar> {
  void _updateSettings(ValueListenables listenables) {
    AircraftSettings.saveAircraftSettings(AircraftSettings(
      altitude: listenables.altitude,
      groundOffset: listenables.groundOffset,
      speed: listenables.speed,
      forwardOverlap: listenables.forwardOverlap,
      sideOverlap: listenables.sideOverlap,
      rotation: listenables.rotation,
      delay: listenables.delayAtWaypoint,
      cameraAngle: listenables.cameraAngle,
      finishAction: listenables.onFinished,
      rcLostAction: listenables.rcLostAction,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<ValueListenables>(builder: (context, listenables, child) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            _buildSectionCard(
              context: context,
              title: "Survey Mode",
              child: Row(
                children: [
                  Expanded(
                    child: _buildModeSelectorCard(
                      context: context,
                      title: "Grid (Area)",
                      subtitle: "Surface 2D/3D",
                      icon: Icons.grid_on_rounded,
                      isSelected: listenables.mappingMode == MappingMode.grid,
                      onTap: () {
                        setState(() {
                          listenables.mappingMode = MappingMode.grid;
                        });
                        _updateSettings(listenables);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildModeSelectorCard(
                      context: context,
                      title: "Corridor",
                      subtitle: "Linear path",
                      icon: Icons.alt_route_rounded,
                      isSelected:
                          listenables.mappingMode == MappingMode.corridor,
                      onTap: () {
                        setState(() {
                          listenables.mappingMode = MappingMode.corridor;
                        });
                        _updateSettings(listenables);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context: context,
              title: "Flight Parameters",
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          labelText: "Altitude",
                          unit: "m",
                          min: ValueListenables.minAltitude.toDouble(),
                          max: ValueListenables.maxAltitude.toDouble(),
                          onChanged: (m) {
                            listenables.altitude = m.round();
                            _updateSettings(listenables);
                          },
                          defaultValue: listenables.altitude.clamp(
                            ValueListenables.minAltitude,
                            ValueListenables.maxAltitude,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomTextField(
                          labelText: "Ground Offset",
                          unit: "m",
                          min: 0,
                          max: (listenables.altitude - 1)
                              .clamp(0, ValueListenables.maxAltitude - 1)
                              .toDouble(),
                          onChanged: (m) {
                            listenables.groundOffset = m.round();
                            _updateSettings(listenables);
                          },
                          defaultValue: listenables.groundOffset.clamp(
                            0,
                            (listenables.altitude - 1)
                                .clamp(0, ValueListenables.maxAltitude - 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextField(
                          labelText: "Flight Speed",
                          unit: "m/s",
                          min: 0.1,
                          max: 15,
                          defaultValue: listenables.speed,
                          onChanged: (speed) {
                            listenables.speed = speed;
                            _updateSettings(listenables);
                          },
                          decimals: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomTextField(
                          labelText: "Waypoint Delay",
                          unit: "s",
                          min: 0,
                          max: 10,
                          defaultValue: listenables.delayAtWaypoint,
                          onChanged: (delaySeconds) {
                            listenables.delayAtWaypoint = delaySeconds.round();
                            _updateSettings(listenables);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (listenables.mappingMode == MappingMode.corridor)
              _buildSectionCard(
                context: context,
                title: "Corridor Parameters",
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            labelText: "Corridor Width",
                            unit: "m",
                            min: 10,
                            max: 1000,
                            defaultValue: listenables.corridorWidth,
                            onChanged: (val) {
                              listenables.corridorWidth = val.round();
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CustomTextField(
                            labelText: "Forward Overlap",
                            unit: "%",
                            min: 1,
                            max: 90,
                            defaultValue: listenables.forwardOverlap,
                            onChanged: (percent) {
                              listenables.forwardOverlap = percent.round();
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Flight Passes:",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionChip(
                            context: context,
                            label: "1 Line",
                            isSelected: listenables.corridorFlightLines == 1,
                            onTap: () {
                              setState(() {
                                listenables.corridorFlightLines = 1;
                              });
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildActionChip(
                            context: context,
                            label: "2 Lines",
                            isSelected: listenables.corridorFlightLines == 2,
                            onTap: () {
                              setState(() {
                                listenables.corridorFlightLines = 2;
                              });
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildActionChip(
                            context: context,
                            label: "3 Lines",
                            isSelected: listenables.corridorFlightLines == 3,
                            onTap: () {
                              setState(() {
                                listenables.corridorFlightLines = 3;
                              });
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                      ],
                    ),
                    CustomTextField(
                      labelText: "Gimbal Angle",
                      unit: "°",
                      min: -90,
                      max: 0,
                      defaultValue: listenables.cameraAngle,
                      onChanged: (degrees) {
                        listenables.cameraAngle = degrees.round();
                        _updateSettings(listenables);
                      },
                    ),
                  ],
                ),
              )
            else
              _buildSectionCard(
                context: context,
                title: "Mapping Coverage",
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            labelText: "Overlap",
                            unit: "%",
                            min: 1,
                            max: 90,
                            defaultValue: listenables.forwardOverlap,
                            onChanged: (percent) {
                              listenables.forwardOverlap = percent.round();
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CustomTextField(
                            labelText: "Sidelap",
                            unit: "%",
                            min: 1,
                            max: 90,
                            defaultValue: listenables.sideOverlap,
                            onChanged: (percent) {
                              listenables.sideOverlap = percent.round();
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                      ],
                    ),
                    CustomTextField(
                      labelText: "Gimbal Angle",
                      unit: "°",
                      min: -90,
                      max: 0,
                      defaultValue: listenables.cameraAngle,
                      onChanged: (degrees) {
                        listenables.cameraAngle = degrees.round();
                        _updateSettings(listenables);
                      },
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colorScheme.outlineVariant.withAlpha(120),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.surfaceContainerHighest.withAlpha(80),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Flight Path Rotation",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                listenables.rotation == 0
                                    ? "Auto (Optimal)"
                                    : "${listenables.rotation}°",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                            ),
                            child: Slider(
                              value: listenables.rotation.toDouble(),
                              min: -180,
                              max: 180,
                              divisions: 360,
                              label: listenables.rotation == 0
                                  ? 'Auto'
                                  : '${listenables.rotation.toStringAsFixed(0)}°',
                              onChanged: (value) {
                                setState(() {
                                  listenables.rotation = value.round();
                                  _updateSettings(listenables);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Geometric Optimization:",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionChip(
                            context: context,
                            label: "Convex Split",
                            isSelected: listenables.useConvexDecomposition,
                            onTap: () {
                              setState(() {
                                listenables.useConvexDecomposition =
                                    !listenables.useConvexDecomposition;
                              });
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildActionChip(
                            context: context,
                            label: "Border Margin",
                            isSelected: listenables.useInsetBuffer,
                            onTap: () {
                              setState(() {
                                listenables.useInsetBuffer =
                                    !listenables.useInsetBuffer;
                              });
                              _updateSettings(listenables);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _buildSectionCard(
              context: context,
              title: "Actions & Safety",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "On Finished:",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 3.4,
                    children: [
                      _buildActionChip(
                        context: context,
                        label: 'Hover',
                        isSelected:
                            listenables.onFinished == FinishAction.noAction,
                        onTap: () {
                          setState(() {
                            listenables.onFinished = FinishAction.noAction;
                          });
                          _updateSettings(listenables);
                        },
                      ),
                      _buildActionChip(
                        context: context,
                        label: 'RTH',
                        isSelected:
                            listenables.onFinished == FinishAction.goHome,
                        onTap: () {
                          setState(() {
                            listenables.onFinished = FinishAction.goHome;
                          });
                          _updateSettings(listenables);
                        },
                      ),
                      _buildActionChip(
                        context: context,
                        label: 'Land',
                        isSelected:
                            listenables.onFinished == FinishAction.autoLand,
                        onTap: () {
                          setState(() {
                            listenables.onFinished = FinishAction.autoLand;
                          });
                          _updateSettings(listenables);
                        },
                      ),
                      _buildActionChip(
                        context: context,
                        label: '1st Waypoint',
                        isSelected: listenables.onFinished ==
                            FinishAction.gotoFirstWaypoint,
                        onTap: () {
                          setState(() {
                            listenables.onFinished =
                                FinishAction.gotoFirstWaypoint;
                          });
                          _updateSettings(listenables);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    "On Signal Loss:",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 2.2,
                    children: [
                      _buildActionChip(
                        context: context,
                        label: 'Hover',
                        isSelected:
                            listenables.rcLostAction == RCLostAction.hover,
                        onTap: () {
                          setState(() {
                            listenables.rcLostAction = RCLostAction.hover;
                          });
                          _updateSettings(listenables);
                        },
                      ),
                      _buildActionChip(
                        context: context,
                        label: 'RTH',
                        isSelected:
                            listenables.rcLostAction == RCLostAction.goBack,
                        onTap: () {
                          setState(() {
                            listenables.rcLostAction = RCLostAction.goBack;
                          });
                          _updateSettings(listenables);
                        },
                      ),
                      _buildActionChip(
                        context: context,
                        label: 'Land',
                        isSelected:
                            listenables.rcLostAction == RCLostAction.landing,
                        onTap: () {
                          setState(() {
                            listenables.rcLostAction = RCLostAction.landing;
                          });
                          _updateSettings(listenables);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest.withAlpha(120),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primary
          : colorScheme.surfaceContainerHighest.withAlpha(100),
      borderRadius: BorderRadius.circular(10),
      elevation: isSelected ? 1 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelectorCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected
          ? colorScheme.primary.withAlpha(28)
          : colorScheme.surfaceContainerHighest.withAlpha(80),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withAlpha(90),
              width: isSelected ? 1.6 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                ),
                maxLines: 1,
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
