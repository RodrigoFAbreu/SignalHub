import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'src/alert/alert_platform.dart';
import 'src/api/signalhub_api.dart';
import 'src/app.dart';
import 'src/app_controller.dart';
import 'src/connection/server_credentials.dart';
import 'src/push/firebase_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final push = await FirebasePushService.start();
  final httpClient = http.Client();
  final controller = AppController(
    store: SecureCredentialsStore(),
    apiFactory: (credentials) => SignalHubApi(credentials, httpClient),
    redeemPairing: (serverUrl, code) =>
        SignalHubApi.redeemPairing(httpClient, serverUrl, code),
    push: push,
    startServedPush: FirebasePushService.startServed,
    // Only the Android app plays an alert of its own (client/README.md).
    alertPlatform: defaultTargetPlatform == TargetPlatform.android
        ? MethodChannelAlertPlatform()
        : null,
  );
  runApp(SignalHubApp(controller: controller));
  unawaited(controller.start());
}
