import 'package:flutter/material.dart';

import '../app_controller.dart';

/// A producer's own screen: everything about one this user owns, or the
/// subscription to one somebody else owns. Placeholder: replaced by the
/// producer screens' own change.
class ProducerScreen extends StatelessWidget {
  const ProducerScreen({
    super.key,
    required this.controller,
    required this.producerId,
  });

  final AppController controller;
  final String producerId;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar());
}
