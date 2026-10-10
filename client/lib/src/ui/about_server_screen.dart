import 'package:flutter/material.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../app_controller.dart';
import '../models/producers.dart';
import 'welcome_screen.dart';
import 'widgets/skeleton.dart';

/// Settings › About this server: where the server is, who this device's user
/// is, the app's own build and the server's version and commit
/// (`GET /api/v1/client/server`), and who can see what, in the same sentence
/// for every role. It never says who the host is.
class AboutServerScreen extends StatefulWidget {
  const AboutServerScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<AboutServerScreen> createState() => _AboutServerScreenState();
}

class _AboutServerScreenState extends State<AboutServerScreen> {
  final _server = Resource<ServerInfo>();

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() => _server.loading = true);
    await _server.load(() => _controller.call((api) => api.getServer()));
    if (mounted) setState(() {});
  }

  /// `SignalHub 3.4.0 · commit a1b2c3d`. A build no release made has no
  /// version, and a build given no commit says so.
  static String releaseLine(String? version, String? commit) {
    final release =
        version == null || version.isEmpty || version == 'development'
        ? 'SignalHub development build'
        : 'SignalHub $version';
    final short = commit == null || commit.isEmpty
        ? 'unknown'
        : commit.length > 7
        ? commit.substring(0, 7)
        : commit;
    return '$release · commit $short';
  }

  @override
  Widget build(BuildContext context) {
    final build = _controller.build;
    final role = _controller.role.label;
    final name = _controller.userName;
    return Scaffold(
      appBar: AppBar(title: const Text('About this server')),
      body: ListView(
        padding: MediaQuery.paddingOf(context).copyWith(top: 0),
        children: [
          _Item(
            icon: Icons.dns_outlined,
            label: 'Address',
            value: _controller.credentials?.baseUrl ?? '',
          ),
          _Item(
            icon: Icons.badge_outlined,
            label: 'You are',
            value: [?name, role].join(' · '),
          ),
          _Item(
            icon: Icons.info_outline,
            label: 'This app',
            value: releaseLine(build.version, build.revision),
          ),
          _server.showSkeleton
              ? const _ServerSkeleton()
              : _Item(
                  key: const Key('serverVersion'),
                  icon: Icons.info_outline,
                  label: 'Server',
                  value: switch (_server.value) {
                    final info? => releaseLine(info.version, info.commit),
                    null => _failure(_server.error!),
                  },
                  action:
                      _server.value == null && !_isUnsupported(_server.error!)
                      ? TextButton(
                          key: const Key('retryServer'),
                          onPressed: _read,
                          child: const Text('Try again'),
                        )
                      : null,
                ),
          Container(
            key: const Key('hostSentence'),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.visibility_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text(WelcomeScreen.hostSentence)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A server released before it said its version answers `404` or `405`.
  static bool _isUnsupported(ApiException e) =>
      e.statusCode == 404 || e.statusCode == 405;

  static String _failure(ApiException e) => _isUnsupported(e)
      ? 'This server does not say'
      : "Couldn't read it from the server";
}

/// One line of facts: a label over its value, which may be copied.
class _Item extends StatelessWidget {
  const _Item({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.action,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, color: quiet)),
          const SizedBox(width: 16),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: quiet),
                  ),
                  SelectableText(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// The server's line while it is read: the shape of a line, not a spinner.
class _ServerSkeleton extends StatelessWidget {
  const _ServerSkeleton();

  @override
  Widget build(BuildContext context) =>
      const SkeletonRows(count: 1, circleLeading: false);
}
