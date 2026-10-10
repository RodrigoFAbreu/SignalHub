import 'package:flutter/material.dart';

import 'widgets/empty_state.dart';

/// What a screen shows when this role does not have it (4m): reached by a
/// stale link or a role that dropped while the screen was open.
class RoleLacksScreen extends StatelessWidget {
  const RoleLacksScreen({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.lock_outline,
    title: 'This screen is not available to your role',
    body: 'Ask an admin of this server.',
  );
}
