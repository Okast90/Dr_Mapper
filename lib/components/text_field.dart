import 'package:flutter/material.dart';
import 'package:flutter_spinbox/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

class CustomTextField extends StatelessWidget {
  const CustomTextField(
      {super.key,
      required this.labelText,
      required this.min,
      required this.max,
      required this.defaultValue,
      required this.onChanged,
      this.enabled = true,
      this.decimals,
      this.maxLength});

  final String labelText;
  final double min;
  final double max;
  final num defaultValue;
  final int? decimals;
  final int? maxLength;
  final bool enabled;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final decoration = InputDecoration(
      labelText: labelText,
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outline.withAlpha(180)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.outline.withAlpha(120)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );

    final field = maxLength != null
        ? TextFormField(
            enabled: enabled,
            initialValue: defaultValue.toStringAsFixed(decimals ?? 0),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(maxLength),
            ],
            onChanged: (value) {
              final parsedValue = double.tryParse(value);
              if (parsedValue != null) onChanged(parsedValue);
            },
            decoration: decoration,
          )
        : SpinBox(
            enabled: enabled,
            step: decimals != null ? math.pow(10.0, -decimals!).toDouble() : 1,
            decimals: decimals ?? 0,
            keyboardType: TextInputType.number,
            min: min,
            max: max,
            onChanged: onChanged,
            value: defaultValue.toDouble(),
            decoration: decoration,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: field,
    );
  }
}
