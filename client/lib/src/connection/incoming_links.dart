import 'dart:async';

import 'package:flutter/services.dart';

/// The links the phone opens this app with (`signalhub://signin?...`, from
/// the page's _Open the app_ button), which Android hands to the app's
/// activity (`MainActivity`).
abstract interface class IncomingLinks {
  /// The link the app was started with, once; `null` if it was not started by
  /// one.
  Future<String?> initialLink();

  /// The links opened while the app is running.
  Stream<String> get links;
}

/// [IncomingLinks] over a method channel to the Android app.
class MethodChannelIncomingLinks implements IncomingLinks {
  MethodChannelIncomingLinks() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) {
        _links.add(call.arguments as String);
      }
    });
  }

  static const _channel = MethodChannel(
    'io.github.rodrigofabreu.signalhub/links',
  );

  final _links = StreamController<String>.broadcast();

  @override
  Future<String?> initialLink() async {
    try {
      return await _channel.invokeMethod<String>('initialLink');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<String> get links => _links.stream;
}
