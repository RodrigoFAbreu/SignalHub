import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/users.dart';
import 'widgets/fact_row.dart';

/// Said once after a device connects, before the bar appears: which server
/// and device this is, what producers and the inbox are, and what the role
/// can do. The last line says who can see what, in the words Settings › About
/// this server uses. _Find producers_ opens the Producers tab; _Later_ opens
/// the inbox.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.controller});

  final AppController controller;

  /// The one sentence decided for the host; it never names a person.
  static const hostSentence =
      'The host runs this server and can see every event on it.';

  /// What the welcome says a [role] can do, in order.
  static List<Fact> facts(UserRole role) => switch (role) {
    UserRole.basic => const [
      Fact(
        Icons.sensors,
        'Producers',
        ' send events: a script, a CI pipeline, a home server. Subscribe to '
            'the ones you want.',
      ),
      Fact(
        Icons.inbox_outlined,
        'Your inbox',
        ' holds their events; your phone is notified as your filters allow.',
      ),
      Fact(
        Icons.add_circle_outline,
        'Your own producers',
        ': make one and send yourself events.',
      ),
    ],
    UserRole.mod || UserRole.admin => [
      if (role.isAdmin)
        const Fact(
          Icons.group_outlined,
          'People',
          ': invite people, set them to Basic or Mod, and manage their '
              'devices.',
        ),
      const Fact(
        Icons.devices_outlined,
        'Devices',
        ' in Settings connects your other phones.',
      ),
      const Fact(
        Icons.language,
        'Sign in a browser',
        ' puts SignalHub on a computer.',
      ),
      const Fact(
        Icons.sensors,
        'Producers',
        ' send events. Subscribe to the ones you want, or make your own.',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final name = controller.userName;
      final host = Uri.tryParse(controller.credentials?.baseUrl ?? '')
          ?.authority;
      final device = controller.registration?.name;
      final who = device ?? name;
      final connected = [
        "You're connected",
        if (host != null && host.isNotEmpty) ' to $host',
        if (who != null) ' as $who',
        if (controller.role.isAdmin) ', an admin device',
        '.',
      ].join();
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        name == null ? 'Welcome' : 'Welcome, $name',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      Text(connected, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 16),
                      Container(
                        key: const Key('welcomeFacts'),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            for (final (i, fact) in facts(
                              controller.role,
                            ).indexed)
                              Padding(
                                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                                child: FactRow(
                                  fact,
                                  iconColor: colors.primary,
                                  textColor: colors.onSurface,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        hostSentence,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      key: const Key('welcomeLater'),
                      onPressed: controller.finishWelcome,
                      child: const Text('Later'),
                    ),
                    FilledButton(
                      key: const Key('welcomeFindProducers'),
                      onPressed: () =>
                          controller.finishWelcome(findProducers: true),
                      child: const Text('Find producers'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
