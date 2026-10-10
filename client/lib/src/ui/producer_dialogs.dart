import 'package:flutter/material.dart';

import '../features/own_producers_controller.dart';
import '../models/producer_name.dart';
import '../models/producers.dart';
import 'producer_name_field.dart';
import 'widgets/dialogs.dart';

/// The confirmations of a producer's screen, each with the words the designs
/// give: a question that names the thing, who is affected and whether it can
/// be undone, and the action in words. Each returns whether it was chosen.
abstract final class ProducerDialogs {
  /// Revoking a key is for good. The only working key says what follows.
  static Future<bool> revokeKey(
    BuildContext context, {
    required ProducerKeyInfo key,
    required OwnProducer producer,
  }) {
    final shown = keyLabel(key);
    final only =
        producer.workingKeys.length == 1 &&
        producer.workingKeys.single.id == key.id;
    return showConfirmDialog(
      context,
      title: only ? 'Revoke the only key?' : 'Revoke this key?',
      message: only
          ? '$shown is the only working key of ${producer.name}. Once it is '
                'revoked, nothing can send its events until you make a new '
                "key. This can't be undone."
          : '$shown stops working at once, and whatever sends with it is '
                "turned away. This can't be undone.",
      action: 'Revoke',
      destructive: true,
    );
  }

  /// Disabling can be undone, so its action is the primary colour.
  static Future<bool> disable(BuildContext context, OwnProducer producer) =>
      showConfirmDialog(
        context,
        title: 'Disable ${producer.name}?',
        message:
            'Its keys stop working. Its events stay. You can enable it '
            'again.',
        action: 'Disable',
      );

  /// Taking someone off the list ends their subscription for good: adding
  /// them back does not restore it.
  static Future<bool> removePerson(
    BuildContext context, {
    required String person,
    required OwnProducer producer,
  }) => showConfirmDialog(
    context,
    title: 'Remove $person?',
    message:
        "$person can't see ${producer.name} any more. If they were "
        'subscribed, they stop getting its events, and they have to subscribe '
        'again after you add them back.',
    action: 'Remove',
    destructive: true,
  );

  /// Making a public producer private ends the subscriptions of everyone not
  /// on the list. A reversible change, so the primary colour.
  static Future<bool> makePrivate(BuildContext context, OwnProducer producer) {
    final others = producer.allowedUsers.isEmpty
        ? 'Only you will see it. Everyone else stops getting its events'
        : 'Only you and the people you add will see it. Everyone not on your '
              'list stops getting its events';
    return showConfirmDialog(
      context,
      title: 'Make ${producer.name} private?',
      message: "$others, and you'd have to add them to bring it back.",
      action: 'Make private',
    );
  }

  /// Saving a list that takes someone off it, in the words of removing one.
  static Future<bool> saveAllowList(
    BuildContext context, {
    required OwnProducer producer,
    required List<String> removed,
    required List<String> added,
  }) {
    final text = StringBuffer(
      "${joinNames(removed)} can't see ${producer.name} any more. If they "
      'were subscribed, they stop getting its events.',
    );
    if (added.isNotEmpty) {
      text.write(
        ' ${joinNames(added)} ${added.length == 1 ? 'is' : 'are'} added.',
      );
    }
    return showConfirmDialog(
      context,
      title: 'Save these changes?',
      message: text.toString(),
      action: 'Save',
    );
  }

  /// Leaving the key screen before the key was copied or shared. Asked once;
  /// _Stay_ is the default, on the right, and a tap outside is _Stay_.
  static Future<bool> leaveWithoutKey(
    BuildContext context, {
    required String producerName,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          insetPadding: dialogInsets,
          title: const Text('Did you copy the key?'),
          content: SingleChildScrollView(
            child: Text(
              "It's shown once. If you leave now, you'll need to make a new "
              'key for $producerName.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const Key('leave'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave'),
            ),
            TextButton(
              key: const Key('stay'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Stay'),
            ),
          ],
        ),
      ) ??
      false;

  /// The rename dialog; returns the producer as renamed, or `null` if it was
  /// cancelled.
  static Future<OwnProducer?> rename(
    BuildContext context, {
    required OwnProducersController controller,
    required OwnProducer producer,
  }) => showDialog<OwnProducer>(
    context: context,
    builder: (context) =>
        _RenameDialog(controller: controller, producer: producer),
  );

  /// How a key is named in a sentence and a button: its prefix, cut.
  static String keyLabel(ProducerKeyInfo key) => '${key.prefix}…';

  /// `Ana`, `Ana and Marta`, `Ana, Marta and Rui`.
  static String joinNames(List<String> names) => switch (names.length) {
    0 => '',
    1 => names.single,
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.controller, required this.producer});

  final OwnProducersController controller;
  final OwnProducer producer;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.producer.name)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.producer.name.length,
    );
  bool _busy = false;

  /// What the server answered about [_asked], until the name changes.
  String? _asked;
  ProducerFailure? _failure;
  String? _message;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      ProducerName.check(_name.text) == null &&
      _name.text != widget.producer.name &&
      !_refused;

  bool get _refused =>
      _name.text == _asked &&
      (_failure == ProducerFailure.taken ||
          _failure == ProducerFailure.notAllowed);

  String? get _serverError => !_refused
      ? null
      : _failure == ProducerFailure.taken
      ? NameMessages.taken
      : NameMessages.notAllowed;

  Future<void> _rename() async {
    if (!_valid || _busy) return;
    final name = _name.text;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await widget.controller.rename(widget.producer.id, name);
    if (!mounted) return;
    if (outcome.ok) {
      Navigator.of(context).pop(outcome.value);
      return;
    }
    setState(() {
      _busy = false;
      _asked = name;
      _failure = outcome.failure;
      _message = _refused
          ? null
          : outcome.message('rename ${widget.producer.name}');
    });
    // The producer is gone or the key was revoked: nothing to rename.
    if (outcome.failure == ProducerFailure.notFound ||
        outcome.failure == ProducerFailure.signedOut) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      insetPadding: dialogInsets,
      title: const Text('Rename producer'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            ProducerNameField(
              controller: _name,
              serverError: _serverError,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: _rename,
            ),
            const SizedBox(height: 12),
            Text(
              'Events keep the producer. They show the new name, and so does '
              'everyone it is shared with.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_message case final message?) ...[
              const SizedBox(height: 12),
              Text(
                message,
                key: const Key('renameError'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('rename'),
          onPressed: _valid && !_busy ? _rename : null,
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
