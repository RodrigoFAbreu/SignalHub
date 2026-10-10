import 'package:flutter/foundation.dart';

import '../api_gateway.dart';

/// The devices this role may list and manage. Placeholder: the Devices
/// screen's own change fills it in.
class DevicesController extends ChangeNotifier {
  DevicesController(this.gateway);

  final ApiGateway gateway;

  /// One line for Settings' _Devices_ row, such as `4 devices · 1 browser`;
  /// `null` until the devices are read.
  String? get summary => null;

  /// Reads the devices this role may list.
  Future<void> load() async {}
}
