import 'package:flutter/material.dart';

/// Standard drag handle for all bottom sheets.
/// Place at the top of every sheet content column.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Shows a modal bottom sheet that respects the safe area and supports
/// full-height content via [isScrollControlled].
///
/// Use this instead of [showModalBottomSheet] for all simple column-based
/// sheets. For the content layout pattern see [SheetHandle].
Future<T?> showSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
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
