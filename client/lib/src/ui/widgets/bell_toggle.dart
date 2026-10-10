import 'package:flutter/material.dart';

/// The one control that subscribes to a producer, in place: a 40 dp circle in
/// a 48 by 48 dp target.
///
/// Subscribed it is secondaryContainer with a filled bell; not subscribed, a
/// 1 dp outline with an outlined bell. While a change [changingTo] runs the
/// bell is replaced by a 24 dp progress ring (stroke 2.5) in the circle of
/// the state it moves to, and taps are ignored. [onPressed] `null` greys it
/// to 38 % (offline), and it ignores taps too.
class BellToggle extends StatelessWidget {
  const BellToggle({
    super.key,
    required this.name,
    required this.subscribed,
    this.changingTo,
    this.onPressed,
  });

  /// The producer's name, for the accessible name.
  final String name;
  final bool subscribed;

  /// The state a running change moves to; `null` when none runs.
  final bool? changingTo;

  /// Called to subscribe or unsubscribe; `null` greys the bell.
  final VoidCallback? onPressed;

  bool get _inFlight => changingTo != null;

  /// What a screen reader says: the state and what a double tap does, or the
  /// change that is running.
  String get semanticLabel => switch (changingTo) {
    true => 'Subscribing to $name',
    false => 'Unsubscribing from $name',
    null =>
      subscribed
          ? 'Subscribed to $name. Double tap to unsubscribe.'
          : 'Not subscribed to $name. Double tap to subscribe.',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filled = _inFlight ? changingTo! : subscribed;
    final foreground = filled
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;
    final enabled = onPressed != null;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled && !_inFlight,
      label: semanticLabel,
      onTap: enabled && !_inFlight ? onPressed : null,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.38,
        child: InkResponse(
          onTap: enabled && !_inFlight ? onPressed : null,
          customBorder: const CircleBorder(),
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? colors.secondaryContainer : null,
                  border: filled ? null : Border.all(color: colors.outline),
                ),
                // A short cross-fade between the bell and the ring.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 100),
                  child: _inFlight
                      ? _Ring(key: const Key('bellRing'), color: foreground)
                      : Icon(
                          subscribed
                              ? Icons.notifications_active
                              : Icons.notifications_outlined,
                          key: const Key('bellIcon'),
                          color: foreground,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 24 dp progress ring with a 2.5 dp stroke. Under reduced motion it stays
/// and does not turn.
class _Ring extends StatelessWidget {
  const _Ring({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    height: 24,
    child: CircularProgressIndicator(
      strokeWidth: 2.5,
      color: color,
      value: MediaQuery.disableAnimationsOf(context) ? 0.75 : null,
    ),
  );
}
