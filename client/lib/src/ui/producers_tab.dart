import 'package:flutter/material.dart';

import '../app_controller.dart';

/// The Producers tab: search, filter chips and every producer this user sees,
/// with the bell that subscribes in place. Replaced by its own change.
class ProducersTab extends StatelessWidget {
  const ProducersTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Producers')),
    body: const SizedBox.shrink(),
  );
}
