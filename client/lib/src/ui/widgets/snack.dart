import 'package:flutter/material.dart';

/// Shows a snackbar: one or two lines and at most one action (Retry after a
/// change that failed and went back to what it was, Undo after one that can
/// be reversed exactly), gone after 6 seconds. A newer one replaces an older
/// one.
void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        // A snack bar with an action stays until it is used by default; this
        // one goes after its time like any other.
        persist: false,
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}
