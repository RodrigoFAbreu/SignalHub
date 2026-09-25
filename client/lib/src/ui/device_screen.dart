import 'package:flutter/material.dart';

import '../app_controller.dart';

/// This installation: its registration, server and push status.
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('This device')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(controller.registration?.name ?? 'This device'),
              subtitle: controller.credentials == null
                  ? null
                  : Text(controller.credentials!.baseUrl),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(controller.pushStatus.description),
            ),
          ),
        ],
      ),
    ),
  );
}
