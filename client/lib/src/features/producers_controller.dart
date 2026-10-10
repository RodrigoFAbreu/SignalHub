import 'package:flutter/foundation.dart';

import '../api_gateway.dart';
import '../models/producers.dart';

/// The producers this user sees and subscribes to
/// (`/api/v1/client/visible-producers`). Placeholder: the Producers tab's own
/// change fills it in.
class ProducersController extends ChangeNotifier {
  ProducersController(this.gateway);

  final ApiGateway gateway;

  /// Every producer this user sees, as last read.
  final Resource<List<VisibleProducer>> list = Resource();

  /// Reads the list again; the older one stays if that fails.
  Future<void> load() async {
    list.loading = true;
    notifyListeners();
    await list.load(() => gateway.call((api) => api.listVisibleProducers()));
    notifyListeners();
  }

  /// The producers this user is subscribed to, by name: the ones whose events
  /// the inbox holds, and the only ones it can be filtered by.
  List<VisibleProducer> get subscribed => [
    for (final p in list.value ?? const <VisibleProducer>[])
      if (p.subscribed) p,
  ];

  VisibleProducer? byId(String id) =>
      list.value?.where((p) => p.id == id).firstOrNull;
}
