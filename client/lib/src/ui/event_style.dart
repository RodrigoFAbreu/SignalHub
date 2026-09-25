import 'package:flutter/material.dart';

import '../models/event.dart';

/// How categories and severities look. Generic: they depend only on the
/// event's category and severity, never on its producer.
extension CategoryStyle on EventCategory {
  IconData get icon => switch (this) {
    EventCategory.actionRequired => Icons.pan_tool_outlined,
    EventCategory.blocked => Icons.block,
    EventCategory.completed => Icons.check_circle_outline,
    EventCategory.info => Icons.info_outline,
    EventCategory.unknown => Icons.label_outline,
  };
}

extension SeverityStyle on EventSeverity {
  /// The color of the event's icon and severity label; `null` for the
  /// theme's default.
  Color? color(ColorScheme colors) => switch (this) {
    EventSeverity.critical || EventSeverity.high => colors.error,
    EventSeverity.normal => colors.primary,
    EventSeverity.low || EventSeverity.unknown => null,
  };
}

/// A local date and time to the minute, e.g. `2026-09-25 14:03`.
String formatTimestamp(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
