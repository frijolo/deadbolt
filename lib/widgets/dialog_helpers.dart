import 'package:flutter/material.dart';

/// Standard padding for AlertDialog titles that include a close button.
const kDialogTitlePadding = EdgeInsets.fromLTRB(24, 16, 8, 0);

/// Builds an AlertDialog title row with an [Expanded] text and a compact close [IconButton].
Widget dialogCloseTitle(
  String title, {
  required VoidCallback onClose,
  String? tooltip,
}) =>
    Row(
      children: [
        Expanded(child: Text(title)),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: onClose,
        ),
      ],
    );
