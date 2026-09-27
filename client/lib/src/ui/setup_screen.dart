import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'pairing_scanner_screen.dart';

/// Connects the app to a SignalHub server: with a pairing code the operator
/// made (`POST /api/v1/admin/pairings`), scanned or pasted, or with a server
/// address and a client key issued by the operator
/// (`POST /api/v1/admin/clients`).
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.controller,
    this.scan = scanPairingCode,
  });

  final AppController controller;
  final PairingScanner scan;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pairingUri = TextEditingController();
  final _serverUrl = TextEditingController();
  final _clientKey = TextEditingController();
  bool _connecting = false;
  String? _error;

  /// Whether [_error] and the progress are about manual setup, so they show
  /// next to it rather than next to pairing.
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    // Why the app came back here, e.g. a revoked key.
    _error = widget.controller.error;
  }

  @override
  void dispose() {
    _pairingUri.dispose();
    _serverUrl.dispose();
    _clientKey.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final scanned = await widget.scan(context);
    if (scanned == null || !mounted) return;
    await _setUp(() => widget.controller.pair(scanned));
  }

  Future<void> _pair() =>
      _setUp(() => widget.controller.pair(_pairingUri.text));

  Future<void> _connect() => _setUp(
    () => widget.controller.connect(_serverUrl.text, _clientKey.text),
    manual: true,
  );

  /// Runs one way of setting up; it returns an error message, or `null`.
  Future<void> _setUp(
    Future<String?> Function() attempt, {
    bool manual = false,
  }) async {
    setState(() {
      _connecting = true;
      _error = null;
      _manual = manual;
    });
    final error = await attempt();
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = error;
    });
  }

  List<Widget> _status(ThemeData theme) => [
    if (_error case final error?) ...[
      const SizedBox(height: 16),
      Text(error, style: TextStyle(color: theme.colorScheme.error)),
    ],
    if (_connecting) ...[
      const SizedBox(height: 16),
      const Center(child: CircularProgressIndicator()),
    ],
  ];

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
              'Scan the pairing code the operator made for this device, or '
              'paste its link.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('scanPairing'),
              onPressed: _connecting ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan pairing code'),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('pairingUri'),
              controller: _pairingUri,
              enabled: !_connecting,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Pairing link',
                hintText: 'signalhub://pair?…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('pair'),
              onPressed: _connecting ? null : _pair,
              child: const Text('Pair'),
            ),
            if (!_manual) ..._status(theme),
            const SizedBox(height: 32),
            Text('Or set up by hand', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Enter your SignalHub server and the client key the operator '
              'registered for this device.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('connect'),
              onPressed: _connecting ? null : _connect,
              child: const Text('Connect'),
            ),
            if (_manual) ..._status(theme),
          ],
        ),
      ),
    );
  }
}
