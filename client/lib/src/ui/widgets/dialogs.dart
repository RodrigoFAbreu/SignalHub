import 'package:flutter/material.dart';

/// How far a dialog stays from the screen's edges: 24 dp, as drawn.
const dialogInsets = EdgeInsets.symmetric(horizontal: 24, vertical: 24);

/// A confirmation dialog: a question that names the thing and is never
/// truncated, one or two sentences on who is affected and whether it can be
/// undone, a quiet Cancel on the left and the action in words on the right.
/// The action is an error-coloured text button when [destructive] (it cannot
/// be taken back), otherwise primary; never a filled button, never "OK". It
/// closes on Cancel or a tap outside, never on the action by accident.
/// Returns whether the action was chosen.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
  String cancel = 'Cancel',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          // The designs leave 24 dp beside a dialog, not Material's 40.
          insetPadding: dialogInsets,
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancel),
            ),
            TextButton(
              key: const Key('confirm'),
              style: destructive
                  ? TextButton.styleFrom(foregroundColor: colors.error)
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        );
      },
    ) ??
    false;
