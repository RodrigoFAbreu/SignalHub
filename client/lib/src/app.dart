import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/inbox_screen.dart';
import 'ui/pairing_scanner_screen.dart';
import 'ui/setup_screen.dart';

class SignalHubApp extends StatefulWidget {
  const SignalHubApp({
    super.key,
    required this.controller,
    this.scanner = scanPairingCode,
  });

  final AppController controller;

  /// Scans a pairing code on the setup screen; tests replace the camera.
  final PairingScanner scanner;

  @override
  State<SignalHubApp> createState() => _SignalHubAppState();
}

class _SignalHubAppState extends State<SignalHubApp> {
  late final AppLifecycleListener _lifecycle;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => controller.resumed());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

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
        ConnectionPhase.disconnected => SetupScreen(
          controller: controller,
          scan: widget.scanner,
        ),
        ConnectionPhase.connected => InboxScreen(controller: controller),
      },
    ),
  );
}
