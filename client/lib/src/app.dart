import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/inbox_screen.dart';
import 'ui/setup_screen.dart';

class SignalHubApp extends StatelessWidget {
  const SignalHubApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SignalHub',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
    ),
    home: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => switch (controller.phase) {
        ConnectionPhase.starting => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        ConnectionPhase.disconnected => SetupScreen(controller: controller),
        ConnectionPhase.connected => InboxScreen(controller: controller),
      },
    ),
  );
}
