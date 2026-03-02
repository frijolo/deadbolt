import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/theme/app_theme.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';

class TimelockDialog extends StatefulWidget {
  final TimelockMode initialMode;
  final RelativeTimelockType initialRelType;
  final int initialRelValue;
  final AbsoluteTimelockType initialAbsType;
  final int initialAbsValue;
  final void Function(
    TimelockMode mode,
    RelativeTimelockType relType,
    int relValue,
    AbsoluteTimelockType absType,
    int absValue,
  ) onSave;

  const TimelockDialog({
    super.key,
    required this.initialMode,
    required this.initialRelType,
    required this.initialRelValue,
    required this.initialAbsType,
    required this.initialAbsValue,
    required this.onSave,
  });

  @override
  State<TimelockDialog> createState() => _TimelockDialogState();
}

class _TimelockDialogState extends State<TimelockDialog> {
  late TimelockMode _mode;
  late RelativeTimelockType _relType;
  late int _relValue;
  late AbsoluteTimelockType _absType;
  late int _absValue;
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // If initial mode is none, default to relative
    _mode = widget.initialMode == TimelockMode.none
        ? TimelockMode.relative
        : widget.initialMode;
    _relType = widget.initialRelType;
    _absType = widget.initialAbsType;

    // For relative Time type, convert seconds to units
    _relValue = _relType == RelativeTimelockType.time
        ? widget.initialRelValue ~/ 512
        : widget.initialRelValue;

    _absValue = widget.initialAbsValue;

    _updateTextField();
  }

  void _updateTextField() {
    if (_mode == TimelockMode.relative) {
      _textController.text = _relValue == 0 ? '' : _relValue.toString();
    } else {
      // Absolute with timestamp uses date picker, not text field
      if (_absType == AbsoluteTimelockType.blocks) {
        _textController.text = _absValue == 0 ? '' : _absValue.toString();
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  double get _maxSliderValue {
    if (_mode == TimelockMode.relative) {
      return 65535;
    } else if (_mode == TimelockMode.absolute && _absType == AbsoluteTimelockType.blocks) {
      return 499999999;
    }
    return 0;
  }

  String? _getValidationError(BuildContext context) {
    final l = context.l10n;
    if (_mode == TimelockMode.none) return null;

    if (_mode == TimelockMode.relative) {
      if (_relValue > 65535) return l.timelockValueMax;
    } else if (_mode == TimelockMode.absolute) {
      if (_absType == AbsoluteTimelockType.blocks) {
        if (_absValue > 0 && _absValue >= 500000000) return l.blockHeightMax;
      } else {
        if (_absValue > 0 && _absValue < 500000000) return l.timestampMin;
      }
    }
    return null;
  }

  String _formatDateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final validationError = _getValidationError(context);

    return AlertDialog(
      title: Text(l10n.timelockDialogTitle),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mode selector (Relative/Absolute only)
            SegmentedButton<TimelockMode>(
              segments: [
                ButtonSegment(
                  value: TimelockMode.relative,
                  label: Text(l10n.relativeTimelock),
                  icon: const Icon(Icons.update, size: 16),
                ),
                ButtonSegment(
                  value: TimelockMode.absolute,
                  label: Text(l10n.absoluteTimelock),
                  icon: const Icon(Icons.event_available, size: 16),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (Set<TimelockMode> selection) {
                setState(() {
                  _mode = selection.first;
                  _updateTextField();
                });
              },
            ),

            const SizedBox(height: 20),
            // Type selector (Blocks/Time)
            if (_mode == TimelockMode.relative)
              SegmentedButton<RelativeTimelockType>(
                segments: [
                  ButtonSegment(
                    value: RelativeTimelockType.blocks,
                    label: Text(l10n.blocksTimelock),
                    icon: const Icon(Icons.grid_on, size: 16),
                  ),
                  ButtonSegment(
                    value: RelativeTimelockType.time,
                    label: Text(l10n.timeTimelock),
                    icon: const Icon(Icons.access_time, size: 16),
                  ),
                ],
                selected: {_relType},
                onSelectionChanged: (Set<RelativeTimelockType> selection) {
                  setState(() {
                    _relType = selection.first;
                    if (_relType == RelativeTimelockType.time && _relValue > 65535) {
                      _relValue = 0;
                    }
                    _updateTextField();
                  });
                },
              )
            else
              SegmentedButton<AbsoluteTimelockType>(
                segments: [
                  ButtonSegment(
                    value: AbsoluteTimelockType.blocks,
                    label: Text(l10n.blocksTimelock),
                    icon: const Icon(Icons.grid_on, size: 16),
                  ),
                  ButtonSegment(
                    value: AbsoluteTimelockType.timestamp,
                    label: Text(l10n.timestampTimelock),
                    icon: const Icon(Icons.calendar_today, size: 16),
                  ),
                ],
                selected: {_absType},
                onSelectionChanged: (Set<AbsoluteTimelockType> selection) {
                  setState(() {
                    _absType = selection.first;
                    _updateTextField();
                  });
                },
              ),

              const SizedBox(height: 20),
              // Value input
              if (_mode == TimelockMode.absolute && _absType == AbsoluteTimelockType.timestamp)
                // Date/time picker for timestamp
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final initialDate = _absValue > 0
                        ? DateTime.fromMillisecondsSinceEpoch(_absValue * 1000)
                        : now;

                    final date = await showDatePicker(
                      context: context,
                      initialDate: initialDate,
                      firstDate: DateTime(1985, 11, 5),
                      lastDate: DateTime(2038, 1, 19),
                    );

                    if (date != null && context.mounted) {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(initialDate),
                      );

                      if (time != null && context.mounted) {
                        final dateTime = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                        setState(() {
                          _absValue = dateTime.millisecondsSinceEpoch ~/ 1000;
                        });
                      }
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: validationError != null ? Colors.red : cs.onSurface.withAlpha(61)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _absValue > 0
                                ? _formatDateTime(_absValue)
                                : l10n.selectDateAndTime,
                            style: TextStyle(
                              color: _absValue > 0 ? cs.onSurface : cs.onSurface.withAlpha(138),
                            ),
                          ),
                        ),
                        if (_absValue > 0)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                _absValue = 0;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                )
              else
                // Text field for other types
                TextField(
                  controller: _textController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: _mode == TimelockMode.relative
                        ? (_relType == RelativeTimelockType.blocks
                            ? l10n.blocksRelHint
                            : l10n.timeUnitsHint)
                        : l10n.blocksAbsHint,
                    errorText: validationError,
                    suffixIcon: (_mode == TimelockMode.relative ? _relValue : _absValue) > 0
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() {
                                if (_mode == TimelockMode.relative) {
                                  _relValue = 0;
                                } else {
                                  _absValue = 0;
                                }
                                _textController.text = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (text) {
                    final parsed = int.tryParse(text) ?? 0;
                    setState(() {
                      if (_mode == TimelockMode.relative) {
                        _relValue = parsed;
                      } else {
                        _absValue = parsed;
                      }
                    });
                  },
                ),

              // Slider (not for timestamp)
              if (!(_mode == TimelockMode.absolute && _absType == AbsoluteTimelockType.timestamp)) ...[
                const SizedBox(height: 16),
                Slider(
                  value: (_mode == TimelockMode.relative ? _relValue : _absValue)
                      .toDouble()
                      .clamp(0, _maxSliderValue),
                  max: _maxSliderValue,
                  divisions: _mode == TimelockMode.relative ? 655 : 499,
                  label: (_mode == TimelockMode.relative ? _relValue : _absValue).toString(),
                  onChanged: (newValue) {
                    setState(() {
                      if (_mode == TimelockMode.relative) {
                        _relValue = newValue.toInt();
                        _textController.text = _relValue == 0 ? '' : _relValue.toString();
                      } else {
                        // Absolute blocks with million-rounding
                        if (newValue >= 499000000) {
                          _absValue = _maxSliderValue.toInt();
                        } else {
                          _absValue = (newValue / 1000000).round() * 1000000;
                        }
                        _textController.text = _absValue == 0 ? '' : _absValue.toString();
                      }
                    });
                  },
                ),
              ],

              const SizedBox(height: 8),
              // User-friendly display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppAccent.color.withAlpha(32),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppAccent.color.withAlpha(64)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppAccent.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _mode == TimelockMode.relative
                            ? (_relValue > 0
                                ? BitcoinFormatter.formatRelativeTimelock(
                                    _relType,
                                    _relType == RelativeTimelockType.time
                                        ? _relValue * 512
                                        : _relValue)
                                : l10n.noTimelock)
                            : (_absValue > 0
                                ? BitcoinFormatter.formatAbsoluteTimelock(
                                    _absType,
                                    _absValue)
                                : l10n.noTimelock),
                        style: TextStyle(fontSize: 13, color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _relValue = 0;
              _absValue = 0;
              _textController.text = '';
            });
          },
          child: Text(l10n.clear),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: validationError != null
              ? null
              : () {
                  // Convert units to seconds for relative Time type
                  final relValueToSave = _relType == RelativeTimelockType.time
                      ? _relValue * 512
                      : _relValue;

                  widget.onSave(
                    _mode,
                    _relType,
                    relValueToSave,
                    _absType,
                    _absValue,
                  );
                  Navigator.pop(context);
                },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
