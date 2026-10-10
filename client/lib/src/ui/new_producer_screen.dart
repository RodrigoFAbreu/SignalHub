import 'package:flutter/material.dart';

import '../app_controller.dart';

/// _New producer_: a full screen to name a producer and choose who can see
/// it, which ends on the key screen. Placeholder: replaced by the producer
/// screens' own change.
class NewProducerScreen extends StatelessWidget {
  const NewProducerScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar());
}
