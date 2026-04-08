import 'package:flutter/material.dart';

/// Global key for the root Navigator (assigned in MaterialApp).
/// Used to insert OverlayEntries above all routes, including modal bottom
/// sheets and dialogs.
final rootNavigatorKey = GlobalKey<NavigatorState>();
