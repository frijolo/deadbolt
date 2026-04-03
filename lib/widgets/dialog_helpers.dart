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
///
/// Set [isDismissible] to false for form sheets (sheets with a Save button)
/// to prevent accidental data loss. Always pair this with [sheetCloseTitle].
Future<T?> showSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    builder: (ctx) => SafeArea(
      top: false,
      child: builder(ctx),
    ),
  );
}

/// Builds a sheet title row with [SheetHandle] above, an [Expanded] text and
/// a compact close [IconButton].
///
/// Use this in form sheets (those with a Save button) paired with
/// [showSheet] `isDismissible: false` so users always have an explicit way
/// to dismiss without losing data.
Widget sheetCloseTitle(
  BuildContext context,
  String title, {
  required VoidCallback onClose,
  String? tooltip,
}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHandle(),
        Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: tooltip,
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
            ),
          ],
        ),
      ],
    );

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
