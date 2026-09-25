import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/event.dart';
import '../push/push_service.dart';

/// The connected app: this installation, its push status, the newest event
/// and the pushes received while the app runs.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final registration = controller.registration;
    final latest = controller.latestEvent;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SignalHub'),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('disconnect'),
                onTap: controller.disconnect,
                child: const Text('Disconnect this device'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.error case final error?)
              _Section(
                icon: Icons.error_outline,
                title: error,
                subtitle: 'Pull down to retry.',
              ),
            _Section(
              icon: Icons.phone_android,
              title: registration?.name ?? 'This device',
              subtitle: controller.credentials?.baseUrl,
            ),
            _Section(
              icon: Icons.notifications_outlined,
              title: controller.pushStatus.description,
            ),
            _Section(
              icon: Icons.inbox_outlined,
              title: latest?.title ?? 'No events yet',
              subtitle: latest == null ? null : _describe(latest),
              label: 'Latest event',
            ),
            if (controller.notices.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Received while open',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final notice in controller.notices) _NoticeTile(notice),
            ],
          ],
        ),
      ),
    );
  }

  static String _describe(Event event) =>
      '${event.category.label} · ${event.severity.label} · '
      '${event.producer.name} · ${formatTimestamp(event.createdAt)}';
}

/// A local date and time to the minute, e.g. `2026-09-25 14:03`.
String formatTimestamp(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    this.subtitle,
    this.label,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? label;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: label == null ? null : Text(label!),
    ),
  );
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile(this.notice);

  final PushNotice notice;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      notice.opened ? Icons.touch_app_outlined : Icons.notifications_active,
    ),
    title: Text(notice.title),
    subtitle: notice.body == null ? null : Text(notice.body!),
  );
}
