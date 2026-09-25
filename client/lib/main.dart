import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
    push: push,
  );
  runApp(SignalHubApp(controller: controller));
  unawaited(controller.start());
}
