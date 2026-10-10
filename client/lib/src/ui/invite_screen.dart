import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/action_failure.dart';
import '../features/pairing_code_controller.dart';
import '../features/people_controller.dart';
import '../models/users.dart';
import 'pairing_code_view.dart';
import 'widgets/app_row.dart';
import 'widgets/busy_button.dart';
import 'widgets/callout.dart';
import 'widgets/name_field.dart';
import 'widgets/role_gate.dart';

/// _Invite someone_, an admin's: a name, Basic or Mod and an optional first
/// device name make the person and the pairing code of their first device;
/// the code screen follows, shared with _Connect a device_. The person is in
/// People as _Invited · not paired yet_ from then on, whether or not the code
/// is used.
class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key, required this.controller});

  final AppController controller;

  /// What the optional first device is called when no name is typed.
  static const defaultDeviceName = 'First device';

  @override
  Widget build(BuildContext context) => RoleGate(
    controller: controller,
    allows: (role) => role.isAdmin,
    child: _Invite(controller: controller),
  );
}

class _Invite extends StatefulWidget {
  const _Invite({required this.controller});

  final AppController controller;

  @override
  State<_Invite> createState() => _InviteState();
}

class _InviteState extends State<_Invite> {
  final _name = TextEditingController();
  final _device = TextEditingController(text: InviteScreen.defaultDeviceName);
  late final PairingCodeController _code = PairingCodeController(
    widget.controller,
    serverUrl: widget.controller.credentials?.baseUrl ?? '',
    now: () => widget.controller.clock(),
  );

  UserRole _role = UserRole.basic;
  bool _touched = false;
  bool _busy = false;
  ActionFailure? _failure;

  /// Names the server said are taken, lower-cased: it compares ignoring case.
  final _taken = <String>{};

  /// Who was invited, once the invitation is made.
  UserRef? _invited;

  PeopleController get _people => widget.controller.people;

  @override
  void dispose() {
    _name.dispose();
    _device.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _typedName => _name.text.trim();

  String? get _nameError {
    if (_taken.contains(_typedName.toLowerCase())) {
      return PeopleController.nameTakenMessage;
    }
    if (_touched && _typedName.isEmpty) return 'Enter their name.';
    return null;
  }

  bool get _valid =>
      _typedName.isNotEmpty && !_taken.contains(_typedName.toLowerCase());

  Future<void> _make() async {
    if (!_valid || _busy) return;
    final name = _typedName;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final device = _device.text.trim();
    final result = await _people.invite(
      name,
      role: _role,
      deviceName: device.isEmpty ? null : device,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.user case final user? when result.pairing != null) {
        _invited = user;
        _code.show(result.pairing!);
        // The list shows them, invited, at once.
        unawaited(_people.load());
        return;
      }
      final failure = result.failure!;
      if (failure.kind == FailureKind.nameTaken) {
        _taken.add(name.toLowerCase());
      } else if (!failure.isQuiet) {
        _failure = failure;
      }
    });
  }

  Future<void> _newCode() {
    final invited = _invited!;
    return _code.create(
      _code.pairing!.name,
      userId: invited.id,
      personName: invited.name,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const Text('Invite someone'),
      titleSpacing: 0,
    ),
    body: _invited == null ? _form(context) : _codeScreen(context),
  );

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: screenPadding(context, top: 12),
      children: [
        NameField(
          key: const Key('inviteName'),
          controller: _name,
          label: 'Their name',
          autofocus: true,
          errorText: _nameError,
          onChanged: (_) => setState(() => _touched = true),
        ),
        const SizedBox(height: 16),
        NameField(
          key: const Key('inviteDevice'),
          controller: _device,
          label: 'First device name (optional)',
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _make(),
        ),
        const SizedBox(height: 16),
        SegmentedButton<UserRole>(
          key: const Key('inviteRole'),
          segments: const [
            ButtonSegment(value: UserRole.basic, label: Text('Basic')),
            ButtonSegment(value: UserRole.mod, label: Text('Mod')),
          ],
          selected: {_role},
          onSelectionChanged: (chosen) => setState(() => _role = chosen.single),
        ),
        const SizedBox(height: 16),
        Text(
          'Basic: their own producers and subscriptions. Mod: also pairs and '
          'removes their own devices.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_failure case final failure?) ...[
          const SizedBox(height: 16),
          Callout.text(
            failure.message,
            kind: CalloutKind.error,
            icon: Icons.error_outline,
            live: true,
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: BusyFilledButton(
            key: const Key('makeInvitation'),
            label: 'Make invitation',
            busy: _busy,
            onPressed: _valid ? _make : null,
          ),
        ),
      ],
    );
  }

  Widget _codeScreen(BuildContext context) {
    final invited = _invited!;
    final name = invited.name;
    return PairingCodeView(
      controller: _code,
      intro: TextSpan(
        children: [
          const TextSpan(text: 'Invitation for '),
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text:
                ' · ${invited.role.label} · first device '
                '“${_code.pairing?.name ?? ''}”',
          ),
        ],
      ),
      countdownLead: '$name scans this in SignalHub on their phone.',
      warning:
          'Whoever uses this code joins as $name. Share it only with '
          '$name.',
      joined: (device) => TextSpan(
        children: [
          TextSpan(
            text: '$name joined',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: " on $device. The code can't be used again."),
        ],
      ),
      ranOut:
          'This code ran out. Make a new one for $name; the old one no longer '
          'works.',
      ranOutNote:
          'Leaving now keeps $name in the list as "Invited · not paired '
          'yet". Open $name any time and choose "Pair a device for $name".',
      centerNewCode: true,
      onNewCode: _newCode,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}
