import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'onboarding/onboarding_store.dart';
import 'ui/app_settings.dart';
import 'ui/home_shell.dart';
import 'ui/link_opener.dart';
import 'ui/pairing_scanner_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/welcome_screen.dart';

class SignalHubApp extends StatefulWidget {
  const SignalHubApp({
    super.key,
    required this.controller,
    this.scanner = scanPairingCode,
    this.linkOpener = openLink,
    this.settingsOpener = openAppSettings,
  });

  final AppController controller;

  /// The camera region of the setup screen; tests replace the camera.
  final PairingScannerBuilder scanner;

  /// Opens an event's link; tests replace the platform.
  final LinkOpener linkOpener;

  /// Opens the phone's settings of this app; tests replace the platform.
  final AppSettingsOpener settingsOpener;

  @override
  State<SignalHubApp> createState() => _SignalHubAppState();
}

class _SignalHubAppState extends State<SignalHubApp> {
  late final AppLifecycleListener _lifecycle;
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _routes = _RouteTracker();

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => controller.resumed());
    controller.addListener(_leaveScreensWhenDisconnected);
  }

  @override
  void dispose() {
    controller.removeListener(_leaveScreensWhenDisconnected);
    _lifecycle.dispose();
    super.dispose();
  }

  /// Back at setup, no screen of the old connection stays over it: they go at
  /// once, without the transition that would show their content a moment
  /// longer.
  void _leaveScreensWhenDisconnected() {
    if (controller.phase != ConnectionPhase.disconnected) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    for (final route in _routes.pushed.toList().reversed) {
      navigator.removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SignalHub',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigatorKey,
    navigatorObservers: [_routes],
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
          scanner: widget.scanner,
          openSettings: widget.settingsOpener,
        ),
        ConnectionPhase.connected =>
          controller.onboarding == OnboardingStep.welcome
              ? WelcomeScreen(controller: controller)
              : HomeShell(controller: controller, openLink: widget.linkOpener),
      },
    ),
  );
}

/// The routes pushed over the home screen, kept so they can all be removed.
class _RouteTracker extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushed.add(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.remove(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.remove(route);
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
