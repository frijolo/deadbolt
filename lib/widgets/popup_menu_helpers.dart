import 'package:flutter/material.dart';

/// Creates a [PopupMenuItem] with an [Icon] and [Text] in a [Row].
PopupMenuItem<T> iconMenuItem<T>({
  required T value,
  required IconData icon,
  required String label,
  bool enabled = true,
  Color? color,
}) =>
    PopupMenuItem<T>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: color != null ? TextStyle(color: color) : null),
        ],
      ),
    );
