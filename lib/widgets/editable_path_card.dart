import 'package:flutter/material.dart';

import 'package:deadbolt/cubit/project_detail_cubit.dart';
import 'package:deadbolt/data/database.dart';
import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/models/timelock_types.dart';
import 'package:deadbolt/utils/bitcoin_formatter.dart';
import 'package:deadbolt/widgets/edit_name_dialog.dart';

class EditablePathCard extends StatelessWidget {
  final int index;
  final EditableSpendPath path;
  final List<ProjectKey> availableKeys;
  final Color Function(String) mfpColorProvider;
  final ValueChanged<int> onThresholdChanged;
  final void Function(String mfp) onMfpAdded;
  final void Function(String mfp) onMfpRemoved;
  final ValueChanged<TimelockMode> onTimelockModeChanged;
  final ValueChanged<RelativeTimelockType> onRelTimelockTypeChanged;
  final ValueChanged<int> onRelTimelockValueChanged;
  final ValueChanged<AbsoluteTimelockType> onAbsTimelockTypeChanged;
  final ValueChanged<int> onAbsTimelockValueChanged;
  final VoidCallback onDelete;
  final VoidCallback onAddNewKey;
  final bool isTaproot;
  final ValueChanged<bool>? onKeyPathChanged;
  final ValueChanged<String?>? onNameEdit;
  final ValueChanged<int>? onPriorityChanged;

  const EditablePathCard({
    super.key,
    required this.index,
    required this.path,
    required this.availableKeys,
    required this.mfpColorProvider,
    required this.onThresholdChanged,
    required this.onMfpAdded,
    required this.onMfpRemoved,
    required this.onTimelockModeChanged,
    required this.onRelTimelockTypeChanged,
    required this.onRelTimelockValueChanged,
    required this.onAbsTimelockTypeChanged,
    required this.onAbsTimelockValueChanged,
    required this.onDelete,
    required this.onAddNewKey,
    this.isTaproot = false,
    this.onKeyPathChanged,
    this.onNameEdit,
    this.onPriorityChanged,
  });

  String? _getValidationError(BuildContext context) {
    final l = context.l10n;
    if (path.mfps.isEmpty) return l.mustHaveAtLeastOneKey;
    if (path.threshold < 1) return l.thresholdMustBeAtLeastOne;
    if (path.threshold > path.mfps.length) return l.thresholdCannotExceed;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final validationError = _getValidationError(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: validationError != null
          ? Colors.red.withAlpha(20)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            if (validationError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(32),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        validationError,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildTimelockAndPriorityRow(context),
            const SizedBox(height: 12),
            _buildKeysSection(context),
            const SizedBox(height: 12),
            _buildThresholdRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final l10n = context.l10n;
    final canBeKeyPath = path.canBeKeyPath;
    final showKeyPathBadge = isTaproot && canBeKeyPath;

    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Colors.orange.withAlpha(32),
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _showNameDialog(context),
            child: Text(
              path.customName ?? l10n.tapToName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: path.customName != null
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: path.customName != null
                    ? Colors.white
                    : Colors.white38,
                fontStyle: path.customName != null
                    ? FontStyle.normal
                    : FontStyle.italic,
              ),
            ),
          ),
        ),
        if (showKeyPathBadge)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              onTap: onKeyPathChanged != null
                  ? () => onKeyPathChanged!(!path.isKeyPath)
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: path.isKeyPath
                      ? Colors.blue.withAlpha(32)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: path.isKeyPath
                        ? Colors.blue.withAlpha(100)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.key,
                      size: 10,
                      color: path.isKeyPath ? Colors.blue : Colors.white38,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      path.isKeyPath ? l10n.keyPathBadge : l10n.setAsKeyPath,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: path.isKeyPath ? Colors.blue : Colors.white38,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          color: Colors.red.withAlpha(180),
          onPressed: onDelete,
          tooltip: l10n.removePathTooltip,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  String _getKeyLabel(String mfp) {
    final key = availableKeys.firstWhere(
      (k) => k.mfp == mfp,
      orElse: () => availableKeys.first,
    );
    return key.customName ?? mfp.toUpperCase();
  }

  Widget _buildKeysSection(BuildContext context) {
    final l10n = context.l10n;
    final unusedKeys =
        availableKeys.where((k) => !path.mfps.contains(k.mfp)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.keysLabel,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var mfp in path.mfps)
              _buildRemovableMfpBadge(
                _getKeyLabel(mfp),
                mfpColorProvider(mfp),
                mfp,
              ),
            _buildAddKeyButton(context, unusedKeys),
          ],
        ),
      ],
    );
  }

  Widget _buildRemovableMfpBadge(String label, Color color, String mfp) {
    return Container(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2, right: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(32),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(64), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(230),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: label == mfp.toUpperCase() ? 0.5 : 0.0,
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () => onMfpRemoved(mfp),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 14, color: color.withAlpha(180)),
            ),
          ),
        ],
      ),
    );
  }

  static const _newKeysentinel = '__new_key__';

  Widget _buildAddKeyButton(BuildContext context, List<ProjectKey> unusedKeys) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      offset: const Offset(0, 32),
      onSelected: (value) {
        if (value == _newKeysentinel) {
          onAddNewKey();
        } else {
          onMfpAdded(value);
        }
      },
      itemBuilder: (context) => [
        ...unusedKeys.map((k) => PopupMenuItem<String>(
              value: k.mfp,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: mfpColorProvider(k.mfp),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    k.mfp.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (k.customName != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      k.customName!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ],
              ),
            )),
        if (unusedKeys.isNotEmpty) const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: _newKeysentinel,
          child: Row(
            children: [
              const Icon(Icons.add, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Text(l10n.newKey, style: const TextStyle(color: Colors.orange)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.orange.withAlpha(100),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Text(
              l10n.addKeyButton,
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelockAndPriorityRow(BuildContext context) {
    final isScriptPath = isTaproot && !path.isKeyPath;
    return Row(
      children: [
        _buildTimelockButton(context),
        if (isScriptPath) ...[
          const Spacer(),
          _buildPriorityBadge(context),
        ],
      ],
    );
  }

  Widget _buildThresholdRow(BuildContext context) {
    final l10n = context.l10n;
    final maxThreshold = path.mfps.isEmpty ? 1 : path.mfps.length;
    final currentThreshold = path.threshold.clamp(1, maxThreshold);

    return Row(
      children: [
        Text(
          l10n.thresholdLabel,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(width: 12),
        PopupMenuButton<int>(
          offset: const Offset(0, 32),
          onSelected: (value) => onThresholdChanged(value),
          tooltip: l10n.changeThresholdTooltip,
          itemBuilder: (context) => List.generate(
            maxThreshold,
            (i) => PopupMenuItem(
              value: i + 1,
              child: Text('${i + 1}'),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(32),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.withAlpha(64)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$currentThreshold',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 12, color: Colors.orange),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          l10n.ofCount(path.mfps.length),
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildTimelockButton(BuildContext context) {
    final l10n = context.l10n;
    final hasTimelock = path.timelockMode != TimelockMode.none &&
        ((path.timelockMode == TimelockMode.relative && path.relTimelockValue > 0) ||
         (path.timelockMode == TimelockMode.absolute && path.absTimelockValue > 0));

    final IconData timelockIcon;
    final String timelockText;

    if (!hasTimelock) {
      timelockIcon = Icons.lock_clock;
      timelockText = l10n.noTimelock;
    } else if (path.timelockMode == TimelockMode.relative) {
      timelockIcon = Icons.update;
      timelockText = BitcoinFormatter.formatRelativeTimelock(
        path.relTimelockType,
        path.relTimelockValue,
      );
    } else {
      timelockIcon = Icons.event_available;
      timelockText = BitcoinFormatter.formatAbsoluteTimelock(
        path.absTimelockType,
        path.absTimelockValue,
      );
    }

    return InkWell(
      onTap: () => _showTimelockDialog(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasTimelock ? Colors.orange.withAlpha(32) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasTimelock ? Colors.orange.withAlpha(64) : Colors.white24,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(timelockIcon, size: 14,
                color: hasTimelock ? Colors.orange : Colors.white54),
            const SizedBox(width: 4),
            Text(
              timelockText,
              style: TextStyle(
                fontSize: 11,
                color: hasTimelock ? Colors.white : Colors.white54,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 12,
                color: hasTimelock ? Colors.orange.withAlpha(180) : Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(BuildContext context) {
    final l10n = context.l10n;
    final p = path.priority;
    final maxOption = (p + 1).clamp(0, 9);
    final active = p > 0;

    return PopupMenuButton<int>(
      offset: const Offset(0, 32),
      onSelected: (value) => onPriorityChanged?.call(value),
      tooltip: l10n.changePriorityTooltip,
      itemBuilder: (context) => List.generate(
        maxOption + 1,
        (i) => PopupMenuItem(value: i, child: Text('$i')),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.orange.withAlpha(32) : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? Colors.orange.withAlpha(64) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.priorityBadge(p),
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white70 : Colors.white38,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 12,
                color: active ? Colors.orange : Colors.white38),
          ],
        ),
      ),
    );
  }

  void _showNameDialog(BuildContext context) {
    showEditNameDialog(
      context,
      title: context.l10n.spendPathNameDialogTitle,
      currentName: path.customName,
      onSave: (name) => onNameEdit?.call(name),
    );
  }

  void _showTimelockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _TimelockDialog(
        initialMode: path.timelockMode,
        initialRelType: path.relTimelockType,
        initialRelValue: path.relTimelockValue,
        initialAbsType: path.absTimelockType,
        initialAbsValue: path.absTimelockValue,
        onSave: (mode, relType, relValue, absType, absValue) {
          if (relValue == 0 && absValue == 0) {
            mode = TimelockMode.none;
          }
          if (mode != path.timelockMode) {
            onTimelockModeChanged(mode);
          }
          if (relType != path.relTimelockType) {
            onRelTimelockTypeChanged(relType);
          }
          if (relValue != path.relTimelockValue) {
            onRelTimelockValueChanged(relValue);
          }
          if (absType != path.absTimelockType) {
            onAbsTimelockTypeChanged(absType);
          }
          if (absValue != path.absTimelockValue) {
            onAbsTimelockValueChanged(absValue);
          }
        },
      ),
    );
  }
}

class _TimelockDialog extends StatefulWidget {
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

  const _TimelockDialog({
    required this.initialMode,
    required this.initialRelType,
    required this.initialRelValue,
    required this.initialAbsType,
    required this.initialAbsValue,
    required this.onSave,
  });

  @override
  State<_TimelockDialog> createState() => _TimelockDialogState();
}

class _TimelockDialogState extends State<_TimelockDialog> {
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
                      border: Border.all(color: validationError != null ? Colors.red : Colors.white24),
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
                              color: _absValue > 0 ? Colors.white : Colors.white54,
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
                  color: Colors.orange.withAlpha(32),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withAlpha(64)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.orange),
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
                        style: const TextStyle(fontSize: 13, color: Colors.white),
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
