import 'package:flutter/material.dart';

import '../models/producers.dart';
import '../models/users.dart';
import 'producer_dates.dart';
import 'producer_dialogs.dart';
import 'widgets/producer_parts.dart';

/// What a producer's screen shows for one this user owns: its state, who can
/// see it, its keys and what can be done to it. It only draws and reports
/// what was chosen; the screen asks first where a design says to.
class OwnProducerView extends StatelessWidget {
  const OwnProducerView({
    super.key,
    required this.producer,
    required this.stale,
    required this.writable,
    required this.busy,
    required this.visibility,
    required this.mutedHere,
    required this.onSubscribed,
    required this.onVisibility,
    required this.onRemovePerson,
    required this.onAddPeople,
    required this.onRevoke,
    required this.onNewKey,
    required this.onEvents,
    required this.onDisable,
    required this.onEnable,
    required this.onMuted,
  });

  final OwnProducer producer;

  /// The banner that says the screen shows an older state, if it does.
  final Widget? stale;

  /// Whether anything that writes is on; off while the connection is down.
  final bool writable;

  /// A change is in flight: its controls ignore taps.
  final bool busy;
  final ProducerVisibility visibility;
  final bool mutedHere;
  final ValueChanged<bool> onSubscribed;
  final ValueChanged<ProducerVisibility> onVisibility;
  final ValueChanged<UserName> onRemovePerson;
  final VoidCallback onAddPeople;
  final ValueChanged<ProducerKeyInfo> onRevoke;
  final VoidCallback onNewKey;
  final VoidCallback onEvents;
  final VoidCallback onDisable;
  final VoidCallback onEnable;
  final VoidCallback onMuted;

  /// `Only you`, `Shared with 1 person`, `Shared with N people`: the line of a
  /// private producer. A public one has none.
  static String sharingLine(int people) => switch (people) {
    0 => 'Only you',
    1 => 'Shared with 1 person',
    _ => 'Shared with $people people',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canWrite = writable && !busy;
    final byHost = producer.isDisabled && producer.disabledByOperator;
    final byYou = producer.isDisabled && !byHost;
    final isPrivate = visibility == ProducerVisibility.private;
    final noKeyBanner = switch (producer) {
      OwnProducer(keys: final keys) when keys.isEmpty =>
        'No key yet. Nothing can send events as ${producer.name}. Make a new '
            'key to start.',
      OwnProducer(workingKeys: final working) when working.isEmpty =>
        'No working key. Nothing can send events as ${producer.name}. Make a '
            'new key to start again.',
      _ => null,
    };
    final withoutKey = noKeyBanner != null;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ?stale,
        if (byHost)
          const _TopNotice(
            icon: Icons.block,
            error: true,
            message:
                "Disabled by the host. Its keys don't work. Ask the host to "
                'enable it.',
          ),
        if (byYou)
          const _TopNotice(
            icon: Icons.pause_circle_outline,
            message:
                "Paused by you. Its keys don't work, so it sends nothing. Its "
                'events stay.',
          ),
        if (noKeyBanner != null)
          _TopNotice(icon: Icons.key_off, message: noKeyBanner),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            producer.lastEventAt == null
                ? 'No events yet'
                : 'Last event ${whenLabel(producer.lastEventAt!)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        SubscribedRow(
          subscribed: producer.subscribed,
          description: _subscribedLine(),
          onChanged: canWrite ? onSubscribed : null,
        ),
        if (producer.subscribed && mutedHere)
          DetailRow(
            icon: Icons.volume_off,
            title: 'Muted on this device',
            lines: const [
              'No pushes from it here. Its events still reach your inbox.',
            ],
            trailing: const Icon(Icons.chevron_right),
            onTap: onMuted,
          ),
        const SectionLabel('Who can see it'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: VisibilityControl(
            value: visibility,
            onChanged: canWrite ? onVisibility : null,
          ),
        ),
        if (!isPrivate)
          const Hint('Anyone on this server can find and subscribe to it.')
        else ...[
          SectionLabel(sharingLine(producer.allowedUsers.length)),
          _AllowedChips(
            people: producer.allowedUsers,
            canWrite: canWrite,
            onRemove: onRemovePerson,
            onAdd: onAddPeople,
          ),
        ],
        const SectionLabel('Keys'),
        if (producer.keys.isEmpty)
          const DetailRow(icon: Icons.key_off, title: 'No keys'),
        for (final key in producer.keys)
          _KeyRow(
            keyInfo: key,
            disabledLine: !key.isRevoked && producer.isDisabled
                ? (byHost
                      ? 'Not working while disabled'
                      : 'Not working while paused')
                : null,
            canWrite: canWrite,
            onRevoke: () => onRevoke(key),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: withoutKey
                ? FilledButton.icon(
                    key: const Key('newKey'),
                    onPressed: canWrite ? onNewKey : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New key'),
                  )
                : OutlinedButton.icon(
                    key: const Key('newKey'),
                    onPressed: canWrite ? onNewKey : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New key'),
                  ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Divider(height: 1),
        ),
        if (producer.subscribed)
          DetailRow(
            icon: Icons.filter_list,
            title: 'See its events',
            trailing: const Icon(Icons.chevron_right),
            onTap: onEvents,
          ),
        if (!producer.isDisabled)
          DetailRow(
            key: const Key('disable'),
            icon: Icons.pause_circle_outline,
            title: 'Disable',
            lines: const ['Its keys stop working. Its events stay.'],
            onTap: canWrite ? onDisable : null,
            quiet: !canWrite,
          )
        else if (byHost)
          const DetailRow(
            key: Key('enable'),
            icon: Icons.play_circle_outline,
            title: 'Enable',
            lines: ['Only the host can enable it'],
            quiet: true,
          )
        else
          DetailRow(
            key: const Key('enable'),
            icon: Icons.play_circle_outline,
            iconColor: colors.primary,
            title: 'Enable',
            lines: const ['Its keys work again'],
            onTap: canWrite ? onEnable : null,
            quiet: !canWrite,
          ),
      ],
    );
  }

  String _subscribedLine() {
    if (producer.subscribed) return 'Its events are in your inbox';
    final anyone = visibility == ProducerVisibility.public
        ? ' Anyone on this server can still subscribe.'
        : '';
    return "You own it but don't get its events.$anyone";
  }
}

/// A notice at the top of the screen, 16 dp from its edges.
class _TopNotice extends StatelessWidget {
  const _TopNotice({
    required this.icon,
    required this.message,
    this.error = false,
  });

  final IconData icon;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: NoticeBox(icon: icon, message: message, error: error),
  );
}

class _AllowedChips extends StatelessWidget {
  const _AllowedChips({
    required this.people,
    required this.canWrite,
    required this.onRemove,
    required this.onAdd,
  });

  final List<UserName> people;
  final bool canWrite;
  final ValueChanged<UserName> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Wrap(
        spacing: 8,
        children: [
          for (final person in people)
            InputChip(
              key: Key('allowed-${person.id}'),
              avatar: PersonAvatar(person.name, size: 24),
              label: Text(person.name),
              deleteIcon: const Icon(Icons.close, size: 18),
              deleteButtonTooltipMessage: 'Remove ${person.name}',
              onDeleted: canWrite ? () => onRemove(person) : null,
              shape: const StadiumBorder(),
              side: BorderSide(color: colors.outline),
              backgroundColor: Colors.transparent,
            ),
          ActionChip(
            key: const Key('addPeople'),
            avatar: Icon(Icons.person_add, size: 18, color: colors.primary),
            label: Text('Add people', style: TextStyle(color: colors.primary)),
            onPressed: canWrite ? onAdd : null,
            shape: const StadiumBorder(),
            side: BorderSide(color: colors.outline),
            backgroundColor: Colors.transparent,
          ),
        ],
      ),
    );
  }
}

/// One key by its prefix: when it was made and last used, with Revoke while
/// it works. A revoked key stays listed, quiet and without Revoke, so the
/// history is honest.
class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.keyInfo,
    required this.disabledLine,
    required this.canWrite,
    required this.onRevoke,
  });

  final ProducerKeyInfo keyInfo;

  /// Why a working key does not work now, if the producer is disabled.
  final String? disabledLine;
  final bool canWrite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = ProducerDialogs.keyLabel(keyInfo);
    final lines = [
      if (keyInfo.isRevoked)
        'Revoked ${whenLabel(keyInfo.revokedAt!)}'
      else
        'Created ${whenLabel(keyInfo.createdAt)} · '
            '${keyInfo.lastUsedAt == null ? 'not used yet' : 'last used ${whenLabel(keyInfo.lastUsedAt!)}'}',
      ?disabledLine,
    ];
    return DetailRow(
      key: Key('key-${keyInfo.id}'),
      icon: keyInfo.isRevoked ? Icons.key_off : Icons.key,
      title: label,
      monoTitle: true,
      lines: lines,
      quiet: keyInfo.isRevoked,
      minHeight: lines.length > 1 ? 72 : 56,
      trailing: keyInfo.isRevoked
          ? null
          : Semantics(
              label: 'Revoke key $label',
              button: true,
              enabled: canWrite,
              onTap: canWrite ? onRevoke : null,
              excludeSemantics: true,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.error,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: canWrite ? onRevoke : null,
                child: const Text('Revoke'),
              ),
            ),
    );
  }
}
