import 'package:flutter/material.dart';

/// An app bar's title that follows the system text size up to 200 %, which
/// [AppBar] itself stops at about 1.34x, and the toolbar height that fits it
/// (64 dp, 72 dp at 200 %).
///
/// Call both from the screen's own `build`: inside the [AppBar] the text
/// scale is already stopped.
class AppBarTitle {
  const AppBarTitle._();

  /// The title text at the system's text scale.
  static Widget text(BuildContext context, String title) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textScaler: MediaQuery.textScalerOf(context),
  );

  /// A title and a smaller line under it.
  static Widget withSubtitle(
    BuildContext context,
    String title,
    String subtitle,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      text(context, title),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: MediaQuery.textScalerOf(context),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  /// 64 dp, and taller as the text grows: 72 dp at 200 %.
  static double height(BuildContext context, {bool subtitle = false}) {
    final scale = (MediaQuery.textScalerOf(context).scale(22) / 22).clamp(1, 2);
    return 64 + (scale - 1) * (subtitle ? 40 : 8);
  }
}
