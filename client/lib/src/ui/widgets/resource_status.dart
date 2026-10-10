import 'package:flutter/material.dart';

import '../../api_gateway.dart';
import 'banners.dart';
import 'empty_state.dart';

/// The older list stays under a neutral banner when a refresh failed: its
/// time says how old it is, and Try again reads it once more.
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.resource, required this.onRetry});

  final Resource<Object?> resource;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final at = resource.loadedAt;
    final since = at == null ? '' : ' from ${clockTime(at)}';
    final lead = resource.offline ? "You're offline." : "Couldn't refresh.";
    return AppBanner(
      icon: resource.offline ? Icons.cloud_off_outlined : Icons.sync_problem,
      message: '$lead Showing the list$since.',
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

/// What a list shows when its first read failed: why, and Try again.
class LoadFailed extends StatelessWidget {
  const LoadFailed({
    super.key,
    required this.resource,
    required this.what,
    required this.onRetry,
  });

  final Resource<Object?> resource;

  /// What could not be read, such as `people`.
  final String what;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: resource.offline ? Icons.cloud_off_outlined : Icons.error_outline,
    title: resource.offline ? "Can't reach the server" : "Couldn't load $what",
    body: resource.offline
        ? 'Check your connection and try again.'
        : resource.error?.message,
    actionLabel: 'Try again',
    onAction: onRetry,
  );
}

/// A local time to the minute, `10:42`.
String clockTime(DateTime when) {
  final local = when.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
