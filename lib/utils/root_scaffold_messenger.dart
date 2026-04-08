import 'package:flutter/material.dart';

/// Global key for the root ScaffoldMessenger (assigned in MaterialApp).
/// Using this key ensures snackbars appear above modal bottom sheets and
/// dialogs, which render as overlays above any individual Scaffold.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
