import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatefulWidget {
  const CustomTextField({
    super.key,
    required this.labelText,
    required this.min,
    required this.max,
    required this.defaultValue,
    required this.onChanged,
    this.enabled = true,
    this.decimals,
    this.maxLength,
    this.unit,
  });

  final String labelText;
  final double min;
  final double max;
  final num defaultValue;
  final int? decimals;
  final int? maxLength;
  final String? unit;
  final bool enabled;
  final void Function(double) onChanged;

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  String _formatValue(num val) {
    if (widget.decimals != null && widget.decimals! > 0) {
      return val.toStringAsFixed(widget.decimals!);
    }
    return val.toInt().toString();
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.defaultValue));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _validateAndSubmit(_controller.text);
      }
    });
  }

  @override
  void didUpdateWidget(covariant CustomTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.defaultValue != widget.defaultValue && !_focusNode.hasFocus) {
      _controller.text = _formatValue(widget.defaultValue);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _validateAndSubmit(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      _controller.text = _formatValue(widget.defaultValue);
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    _controller.text = _formatValue(clamped);
    widget.onChanged(clamped);
  }

  void _step(double delta) {
    if (!widget.enabled) return;
    final current = double.tryParse(_controller.text) ?? widget.defaultValue.toDouble();
    final next = (current + delta).clamp(widget.min, widget.max);
    _controller.text = _formatValue(next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final step = widget.decimals != null && widget.decimals! > 0
        ? (widget.decimals == 1 ? 0.5 : 0.1)
        : 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withAlpha(widget.enabled ? 90 : 40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(widget.enabled ? 120 : 60),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  widget.labelText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.enabled
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurfaceVariant.withAlpha(120),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.unit != null)
                Text(
                  widget.unit!,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (widget.maxLength == null) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: widget.enabled ? () => _step(-step) : null,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withAlpha(180),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withAlpha(80),
                      ),
                    ),
                    child: Icon(
                      Icons.remove,
                      size: 13,
                      color: widget.enabled
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withAlpha(100),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    if (widget.maxLength != null)
                      LengthLimitingTextInputFormatter(widget.maxLength),
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 2),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                  onSubmitted: _validateAndSubmit,
                ),
              ),
              if (widget.maxLength == null) ...[
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: widget.enabled ? () => _step(step) : null,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withAlpha(180),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withAlpha(80),
                      ),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 13,
                      color: widget.enabled
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withAlpha(100),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
