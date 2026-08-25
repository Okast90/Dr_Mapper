import 'package:dji_mapper/components/text_field.dart';
import 'package:dji_mapper/main.dart';
import 'package:dji_mapper/presets/camera_preset.dart';
import 'package:dji_mapper/presets/preset_manager.dart';
import 'package:dji_mapper/shared/value_listeneables.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CameraBar extends StatefulWidget {
  const CameraBar({super.key});

  @override
  State<CameraBar> createState() => _CameraBarState();
}

class _CameraBarState extends State<CameraBar> {
  late List<CameraPreset> _presets = PresetManager.getPresets();

  void _updatePreset(ValueListenables listenables) {
    // Only update if it's not a default preset
    if (!listenables.selectedCameraPreset!.defaultPreset) {
      PresetManager.updatePreset(
          _presets.indexOf(listenables.selectedCameraPreset!),
          CameraPreset(
              name: listenables.selectedCameraPreset!.name,
              defaultPreset: false,
              sensorWidth: listenables.sensorWidth,
              sensorHeight: listenables.sensorHeight,
              focalLength: listenables.focalLength,
              imageWidth: listenables.imageWidth,
              imageHeight: listenables.imageHeight));
    }
  }

  /// Always called from the `AlertDialog`
  void _addPreset(
      ValueListenables listenables, TextEditingController nameController) {
    final CameraPreset newPreset = CameraPreset(
        defaultPreset: false,
        name: nameController.text,
        sensorWidth: listenables.sensorWidth,
        sensorHeight: listenables.sensorHeight,
        focalLength: listenables.focalLength,
        imageWidth: listenables.imageWidth,
        imageHeight: listenables.imageHeight);
    PresetManager.addPreset(newPreset);
    _presets = PresetManager.getPresets();
    Provider.of<ValueListenables>(context, listen: false).selectedCameraPreset =
        newPreset;
    listenables.notify();
    // Update latest preset
    prefs.setString("latestPreset", listenables.selectedCameraPreset!.name);
    Navigator.pop(context);
  }

  void _updateProvider(ValueListenables listenables) {
    listenables.sensorWidth = listenables.selectedCameraPreset!.sensorWidth;
    listenables.sensorHeight = listenables.selectedCameraPreset!.sensorHeight;
    listenables.focalLength = listenables.selectedCameraPreset!.focalLength;
    listenables.imageWidth = listenables.selectedCameraPreset!.imageWidth;
    listenables.imageHeight = listenables.selectedCameraPreset!.imageHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ValueListenables>(builder: (context, listenables, child) {
      final colorScheme = Theme.of(context).colorScheme;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Container(
                padding: const EdgeInsets.all(16),
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
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    Text(
                      'Camera Preset:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.surfaceContainerHighest,
                        border: Border.all(color: colorScheme.outline.withAlpha(180)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton(
                          value: listenables.selectedCameraPreset,
                          items: List.generate(
                            _presets.length,
                            (i) => DropdownMenuItem(
                              value: _presets[i],
                              child: Text(_presets[i].name),
                            ),
                          ),
                          onChanged: (item) {
                            _presets = PresetManager.getPresets();
                            listenables.selectedCameraPreset = item ?? _presets[0];
                            _updateProvider(listenables);
                            prefs.setString('latestPreset', listenables.selectedCameraPreset!.name);
                          },
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () {
                        final nameController = TextEditingController();
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Preset Title'),
                            content: TextField(
                              autocorrect: false,
                              autofocus: true,
                              onChanged: (text) {
                                nameController.text = text;
                              },
                              onSubmitted: (_) => _addPreset(listenables, nameController),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => _addPreset(listenables, nameController),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      tooltip: 'Add',
                    ),
                    IconButton.filledTonal(
                      onPressed: listenables.selectedCameraPreset!.defaultPreset
                          ? null
                          : () {
                              final int previousIndex = _presets.indexOf(listenables.selectedCameraPreset!);
                              PresetManager.deletePreset(listenables.selectedCameraPreset!);
                              _presets = PresetManager.getPresets();

                              int newIndex = previousIndex - 1;
                              if (newIndex < 0) {
                                newIndex = 0;
                              } else if (newIndex >= _presets.length) {
                                newIndex = _presets.length - 1;
                              }

                              listenables.selectedCameraPreset = _presets[newIndex];
                              prefs.setString(
                                'latestPreset',
                                listenables.selectedCameraPreset!.name,
                              );
                              listenables.notify();
                            },
                      icon: const Icon(Icons.delete),
                      tooltip: listenables.selectedCameraPreset!.defaultPreset ? "Can't delete default preset" : 'Delete',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              context: context,
              title: 'Sensor',
              child: Column(
                children: [
                  CustomTextField(
                    labelText: 'Sensor Width (mm)',
                    min: 1,
                    max: 50,
                    onChanged: (mm) {
                      listenables.sensorWidth = mm;
                      _updatePreset(listenables);
                    },
                    defaultValue: listenables.sensorWidth,
                    decimals: 1,
                    enabled: !listenables.selectedCameraPreset!.defaultPreset,
                  ),
                  CustomTextField(
                    labelText: 'Sensor Height (mm)',
                    min: 1,
                    max: 50,
                    defaultValue: listenables.sensorHeight,
                    onChanged: (mm) {
                      listenables.sensorHeight = mm;
                      _updatePreset(listenables);
                    },
                    decimals: 1,
                    enabled: !listenables.selectedCameraPreset!.defaultPreset,
                  ),
                  CustomTextField(
                    labelText: 'Focal Length (mm)',
                    min: 1,
                    max: 50,
                    defaultValue: listenables.focalLength,
                    onChanged: (mm) {
                      listenables.focalLength = mm;
                      _updatePreset(listenables);
                    },
                    decimals: 2,
                    enabled: !listenables.selectedCameraPreset!.defaultPreset,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              context: context,
              title: 'Image output',
              child: Column(
                children: [
                  CustomTextField(
                    labelText: 'Image Width (px)',
                    min: 100,
                    max: 99999,
                    onChanged: (px) {
                      listenables.imageWidth = px.toInt();
                      _updatePreset(listenables);
                    },
                    defaultValue: listenables.imageWidth.toDouble(),
                    enabled: !listenables.selectedCameraPreset!.defaultPreset,
                    maxLength: 5,
                  ),
                  CustomTextField(
                    labelText: 'Image Height (px)',
                    min: 100,
                    max: 99999,
                    defaultValue: listenables.imageHeight.toDouble(),
                    onChanged: (px) {
                      listenables.imageHeight = px.toInt();
                      _updatePreset(listenables);
                    },
                    enabled: !listenables.selectedCameraPreset!.defaultPreset,
                    maxLength: 5,
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
        padding: const EdgeInsets.all(16),
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
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
