import 'package:flutter/material.dart';

import '../app_controller.dart';

/// The People tab, an admin's: everyone on the server in sections by role.
/// Replaced by its own change.
class PeopleTab extends StatelessWidget {
  const PeopleTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('People')),
    body: const SizedBox.shrink(),
  );
}
