import 'package:flutter/material.dart';

import 'widgets/empty_state.dart';

/// The words for an action the server refused because the person's role
/// does not allow it (`403`), as a snackbar. The app has read the role again
/// by then, so the screen follows the new one.
const roleRefusedMessage = "Your role doesn't allow this. It may have changed.";

/// What a screen shows when this role does not have it (4m): reached by a
/// stale link or a role that dropped while the screen was open. It names the
/// screen, says who it is for and who can help, and goes back to the Inbox.
/// It is not an error colour.
class RoleLacksScreen extends StatelessWidget {
  const RoleLacksScreen({
    super.key,
    this.screen = 'People',
    this.body =
        'People is for admins of this server. If you need it, ask an '
        'admin.',
    this.onBack,
  });

  /// The name of the screen that is not available, as its title.
  final String screen;

  /// Who the screen is for, and who to ask.
  final String body;

  /// Goes back to the Inbox. Without it the screen is popped, which is what a
  /// pushed screen does.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    void back() =>
        onBack != null ? onBack!() : Navigator.of(context).maybePop();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: back,
        ),
        title: Text(screen),
      ),
      body: EmptyState(
        icon: Icons.lock_outline,
        title: "You can't open this",
        body: body,
        actionLabel: 'Back to Inbox',
        onAction: back,
      ),
    );
  }
}
