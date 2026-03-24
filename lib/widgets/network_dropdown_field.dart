import 'package:flutter/material.dart';

import 'package:deadbolt/l10n/l10n.dart';
import 'package:deadbolt/src/rust/api/model.dart';
import 'package:deadbolt/utils/enum_formatters.dart';

/// A [DropdownButtonFormField] for selecting a [APINetwork].
class NetworkDropdownField extends StatelessWidget {
  final APINetwork value;
  final ValueChanged<APINetwork> onChanged;

  const NetworkDropdownField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<APINetwork>(
      key: ValueKey(value),
      initialValue: value,
      decoration: InputDecoration(
        labelText: context.l10n.networkLabel,
        border: const OutlineInputBorder(),
      ),
      items: APINetwork.values
          .map((n) => DropdownMenuItem(
                value: n,
                child: Text(localizedNetworkName(context, n)),
              ))
          .toList(),
      onChanged: (n) => onChanged(n!),
    );
  }
}
