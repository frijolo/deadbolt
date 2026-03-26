import 'package:flutter/material.dart';

/// Shows a modal bottom sheet that always respects the bottom safe area
/// (home indicator on iPhone, gesture bar on Android) without adding
/// unnecessary top inset. Use this instead of [showModalBottomSheet] for
/// all simple column-based sheets.
Future<T?> showSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    builder: (ctx) => SafeArea(
      top: false,
      child: builder(ctx),
    ),
  );
}

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
