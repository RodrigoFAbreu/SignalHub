import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/action_failure.dart';
import '../features/pairing_code_controller.dart';
import '../models/users.dart';
import 'pairing_code_view.dart';
import 'widgets/app_row.dart';
import 'widgets/busy_button.dart';
import 'widgets/callout.dart';
import 'widgets/name_field.dart';
import 'widgets/person_avatar.dart';
import 'widgets/role_gate.dart';
import 'widgets/skeleton.dart';
import 'widgets/tags.dart';

/// _Connect a device_, for a mod or an admin: step one types the new device's
/// name (the device that redeems the code cannot name itself), and an admin
/// first chooses who it is for: themselves or anyone who is not removed.
/// Step two is the code screen an invitation shares, titled for whoever the
/// device is for.
///
/// [forPerson] fixes who the device is for, as a person's page does with
/// _Pair a device for Ana_: there is no chooser then.
class ConnectDeviceScreen extends StatelessWidget {
  const ConnectDeviceScreen({
    super.key,
    required this.controller,
    this.forPerson,
  });

  final AppController controller;
  final ({String id, String name})? forPerson;

  @override
  Widget build(BuildContext context) => RoleGate(
    screen: 'Connect a device',
    lacking:
        'Connecting a device is for mods and admins of this server. If you '
        'need it, ask an admin.',
    controller: controller,
    allows: (role) => role.managesDevices,
    child: _Connect(controller: controller, forPerson: forPerson),
  );
}

class _Connect extends StatefulWidget {
  const _Connect({required this.controller, required this.forPerson});

  final AppController controller;
  final ({String id, String name})? forPerson;

  @override
  State<_Connect> createState() => _ConnectState();
}

class _ConnectState extends State<_Connect> {
  final _name = TextEditingController();
  late final PairingCodeController _code = PairingCodeController(
    widget.controller,
    serverUrl: widget.controller.credentials?.baseUrl ?? '',
    now: () => widget.controller.clock(),
  );

  bool _touched = false;

  /// Who an admin chose; `null` is themselves.
  String? _chosen;

  AppController get _app => widget.controller;
  bool get _isAdmin => _app.role.isAdmin;

  @override
  void initState() {
    super.initState();
    _chosen = widget.forPerson?.id;
    if (_isAdmin && widget.forPerson == null) {
      // For the chooser. Not while building: reading notifies listeners.
      WidgetsBinding.instance.addPostFrameCallback((_) => _app.people.load());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Who the device is for: their ID (`null` for this device's own user),
  /// their name and whether that is you.
  ({String? id, String name, bool you}) get _target {
    final myName = _app.userName ?? 'you';
    final fixed = widget.forPerson;
    final id = _isAdmin ? (fixed?.id ?? _chosen) : null;
    if (id == null || id == _app.userId) {
      return (id: _isAdmin ? _app.userId : null, name: myName, you: true);
    }
    final name = fixed?.id == id ? fixed!.name : _app.people.byId(id)?.name;
    return (id: id, name: name ?? 'them', you: false);
  }

  String? get _nameError =>
      _touched && _name.text.trim().isEmpty ? 'Enter a name.' : null;

  bool get _valid => _name.text.trim().isNotEmpty;

  Future<void> _show() async {
    if (!_valid || _code.creating) return;
    final target = _target;
    await _code.create(_name.text, userId: target.id, personName: target.name);
    if (!mounted) return;
    if (_code.failure?.kind == FailureKind.removed) {
      // They were removed: the chooser no longer lists them.
      setState(() => _chosen = null);
      unawaited(_app.people.load());
    }
  }

  Future<void> _newCode() async {
    final target = _target;
    final name = _code.pairing!.name;
    await _code.create(name, userId: target.id, personName: target.name);
    if (!mounted) return;
    if (_code.failure?.kind == FailureKind.removed) {
      // Back to the first step with why, to choose someone else.
      _name.text = name;
      _code.forget();
      setState(() => _chosen = null);
      unawaited(_app.people.load());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const Text('Connect a device'),
      titleSpacing: 0,
    ),
    body: ListenableBuilder(
      listenable: Listenable.merge([_code, _app.people]),
      builder: (context, _) =>
          _code.pairing == null ? _form(context) : _codeScreen(context),
    ),
  );

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.paddingOf(context);
    final target = _target;
    final failure = _code.failure;
    final field = NameField(
      key: const Key('pairingName'),
      controller: _name,
      label: 'Name of the new device',
      autofocus: !_isAdmin || widget.forPerson != null,
      errorText: _nameError,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() => _touched = true),
      onSubmitted: (_) => _show(),
    );
    final hint = Text(
      '1 to 100 characters. You can rename it later.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final button = BusyFilledButton(
      key: const Key('showCode'),
      label: _isAdmin && widget.forPerson == null && !target.you
          ? 'Show code for ${target.name}'
          : 'Show code',
      busy: _code.creating,
      onPressed: _valid ? _show : null,
    );
    final banner = failure == null || failure.isQuiet
        ? null
        : Callout.text(
            failure.message,
            kind: CalloutKind.error,
            icon: failure.kind == FailureKind.removed
                ? Icons.person_off
                : Icons.error_outline,
            live: true,
          );
    if (_isAdmin && widget.forPerson == null) {
      return Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                if (banner != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: banner,
                  ),
                const SectionLabel('For'),
                _chooser(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [field, const SizedBox(height: 8), hint],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + insets.bottom),
            child: Align(alignment: Alignment.centerRight, child: button),
          ),
        ],
      );
    }
    return ListView(
      padding: screenPadding(context),
      children: [
        ?banner,
        if (banner != null) const SizedBox(height: 16),
        Text(
          'For ${target.name}${target.you ? ' (you)' : ''}.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        field,
        const SizedBox(height: 8),
        hint,
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerRight, child: button),
      ],
    );
  }

  /// Everyone who is not removed, you first. If the list has not been read,
  /// there is at least you.
  Widget _chooser(BuildContext context) {
    final list = _app.people.list;
    if (list.showSkeleton && _app.people.people.isEmpty) {
      return const SkeletonRows(count: 3);
    }
    final me = _app.userId ?? '';
    final people = [
      (id: me, name: _app.userName ?? 'You', role: _app.role),
      for (final p in _app.people.people)
        if (p.id != me)
          (id: p.id, name: p.name, role: p.role ?? UserRole.basic),
    ];
    final selected = _chosen ?? me;
    return RadioGroup<String>(
      groupValue: selected,
      onChanged: (id) => setState(() => _chosen = id == me ? null : id),
      child: Column(
        children: [
          for (final p in people)
            AppRow(
              key: Key('for-${p.id}'),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<String>(
                    value: p.id,
                    // The row is the target; the radio keeps its 20 dp.
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  PersonAvatar(p.name, you: p.id == me, size: 32),
                ],
              ),
              title: p.name,
              tags: [
                if (p.id == me)
                  const LabelTag('You', style: LabelTagStyle.primary),
              ],
              trailing: RoleTag(p.role),
              onTap: () => setState(() => _chosen = p.id == me ? null : p.id),
            ),
        ],
      ),
    );
  }

  Widget _codeScreen(BuildContext context) {
    final target = _target;
    final name = target.name;
    final device = _code.pairing!.name;
    return PairingCodeView(
      controller: _code,
      intro: TextSpan(
        text:
            'For $name${target.you ? ' (you)' : ''}. New '
            'device: $device. Scan this in SignalHub on the other device, or '
            'open the link there.',
      ),
      countdownLead: 'Works once.',
      warning: target.you
          ? 'Whoever uses this code gets a device of yours. Share it only '
                'with yourself.'
          : 'Whoever uses this code gets a device of ${possessive(name)}. '
                'Share it only with $name.',
      joined: (used) => TextSpan(
        children: [
          const TextSpan(
            text: 'Connected.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: " $used used this code. It can't be used again."),
        ],
      ),
      ranOut: 'This code ran out. Make a new one.',
      onNewCode: _newCode,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}
