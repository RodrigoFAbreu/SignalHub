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
                "Disabled by you. Its keys don't work, so it sends nothing. Its "
                'events stay.',
          ),
        if (noKeyBanner != null)
          _TopNotice(icon: Icons.key_off_outlined, message: noKeyBanner),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
          const DetailRow(icon: Icons.key_off_outlined, title: 'No keys'),
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
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
        children: [
          for (final person in people)
            _PersonChip(
              key: Key('allowed-${person.id}'),
              name: person.name,
              onRemove: canWrite ? () => onRemove(person) : null,
            ),
          _ChipFrame(
            key: const Key('addPeople'),
            onTap: canWrite ? onAdd : null,
            padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.person_add_alt_outlined,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Add people',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: colors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The outline of a chip of the allow-list: 32 dp high, fully rounded, in a
/// 48 dp high target with 8 dp to its right, so chips sit 8 dp apart.
class _ChipFrame extends StatelessWidget {
  const _ChipFrame({
    super.key,
    required this.child,
    required this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkResponse(
        onTap: onTap,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(16),
        containedInkWell: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 32,
              padding: padding,
              decoration: ShapeDecoration(
                shape: StadiumBorder(side: BorderSide(color: colors.outline)),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A person on the list: their initial, their name and an x that takes them
/// off, named _Remove NAME_. The x is a 48 dp target.
class _PersonChip extends StatelessWidget {
  const _PersonChip({super.key, required this.name, required this.onRemove});

  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Center(
              widthFactor: 1,
              child: Container(
                height: 32,
                // The x, 32 dp of it inside the outline, lies over this.
                padding: const EdgeInsets.only(left: 4, right: 32),
                decoration: ShapeDecoration(
                  shape: StadiumBorder(side: BorderSide(color: colors.outline)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PersonAvatar(name, size: 24),
                    const SizedBox(width: 8),
                    Text(name, style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 48,
              child: IconButton(
                tooltip: 'Remove $name',
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 7),
                iconSize: 18,
                color: colors.onSurfaceVariant,
                icon: const Icon(Icons.close),
                onPressed: onRemove,
              ),
            ),
          ],
        ),
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
      icon: keyInfo.isRevoked ? Icons.key_off_outlined : Icons.key_outlined,
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
