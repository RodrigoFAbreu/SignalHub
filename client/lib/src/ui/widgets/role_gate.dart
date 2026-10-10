import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../models/users.dart';
import '../role_lacks_screen.dart';

/// A pushed screen only some roles have. The app learns of a role that
/// changed under the person when a request is refused, and then the screen
/// they are on is the "not available to your role" one, with the way back.
class RoleGate extends StatelessWidget {
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => allows(controller.role)
        ? child
        : Scaffold(appBar: AppBar(), body: const RoleLacksScreen()),
  );
}
