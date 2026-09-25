import 'package:flutter/material.dart';

import '../app_controller.dart';

/// Connects the app to a SignalHub server with a client key issued by the
/// operator (`POST /api/v1/admin/clients`).
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _serverUrl = TextEditingController();
  final _clientKey = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Why the app came back here, e.g. a revoked key.
    _error = widget.controller.error;
  }

  @override
  void dispose() {
    _serverUrl.dispose();
    _clientKey.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final error = await widget.controller.connect(
      _serverUrl.text,
      _clientKey.text,
    );
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to SignalHub')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Enter your SignalHub server and the client key the operator '
              'registered for this device.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('serverUrl'),
              controller: _serverUrl,
              enabled: !_connecting,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server',
                hintText: 'https://signalhub.example.org',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('clientKey'),
              controller: _clientKey,
              enabled: !_connecting,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Client key',
                hintText: 'shck1_…',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('connect'),
              onPressed: _connecting ? null : _connect,
              child: _connecting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
