import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/users.dart';
import '../role_lacks_screen.dart';

/// A pushed screen only some roles have, which also ends when the app
/// disconnects.
///
/// The app learns of a role that changed under the person when a request is
/// refused, and then the screen they are on is the "not available to your
/// role" one, with the way back. When the server no longer accepts the key,
/// setup says why and this screen is simply closed.
class RoleGate extends StatefulWidget {
  const RoleGate({
    super.key,
    required this.controller,
    required this.allows,
    required this.child,
  });

  final AppController controller;
  final bool Function(UserRole role) allows;
  final Widget child;

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      if (widget.controller.phase != ConnectionPhase.connected) {
        if (!_closing) {
          _closing = true;
          final route = ModalRoute.of(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // This route, not whatever is on top of it.
            if (mounted && route != null && route.isActive) {
              Navigator.of(context).removeRoute(route);
            }
          });
        }
        return const SizedBox.shrink();
      }
      return widget.allows(widget.controller.role)
          ? widget.child
          : Scaffold(appBar: AppBar(), body: const RoleLacksScreen());
    },
  );
}
