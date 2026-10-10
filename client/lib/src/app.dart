import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/home_shell.dart';
import 'ui/link_opener.dart';
import 'ui/pairing_scanner_screen.dart';
import 'ui/setup_screen.dart';

class SignalHubApp extends StatefulWidget {
  const SignalHubApp({
    super.key,
    required this.controller,
    this.scanner = scanPairingCode,
    this.linkOpener = openLink,
  });

  final AppController controller;

  /// Scans a pairing code on the setup screen; tests replace the camera.
  final PairingScanner scanner;

  /// Opens an event's link; tests replace the platform.
  final LinkOpener linkOpener;

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
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
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
        ConnectionPhase.connected => HomeShell(
          controller: controller,
          openLink: widget.linkOpener,
        ),
      },
    ),
  );
}

/// The app's Material 3 theme, from the indigo seed in both modes. Beyond the
/// seed, the drawings set a 64 dp app bar and a floating snackbar with a 4 dp
/// corner that rests 8 dp above the bottom bar.
ThemeData _theme(Brightness brightness) => ThemeData(
  colorSchemeSeed: Colors.indigo,
  brightness: brightness,
  appBarTheme: const AppBarTheme(toolbarHeight: 64),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    insetPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
  ),
);
