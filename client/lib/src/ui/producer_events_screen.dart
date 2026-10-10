import 'package:flutter/material.dart';

import '../app_controller.dart';

/// The events of one producer: the inbox narrowed to it, opened from the
/// producer's screen. Placeholder: replaced by the Producers tab's own change.
class ProducerEventsScreen extends StatelessWidget {
  const ProducerEventsScreen({
    super.key,
    required this.controller,
    required this.producerId,
    required this.producerName,
  });

  final AppController controller;
  final String producerId;
  final String producerName;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar());
}
