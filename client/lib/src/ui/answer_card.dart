import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../features/answer_outcome.dart';
import '../models/event.dart';
import '../models/question.dart';
import 'question_words.dart';
import 'widgets/snack.dart';

const _maxText = 3000;
const _otherId = '\u0000other';

int _length(String text) => text.runes.length;

/// What the person typed and picked, kept per event while the app runs so a
/// rebuilt screen, or one left and opened again, does not lose it.
class _Draft {
  Set<String> picked = {};
  bool otherOn = false;
  String note = '';
  String other = '';
}

final _drafts = <String, _Draft>{};

/// Forgets every draft; tests start from nothing typed.
@visibleForTesting
void clearAnswerDrafts() => _drafts.clear();

/// The card under an event's message that answers its question (DESIGN.md
/// section 10, option A): select, then _Send answer_, which is the one
/// deliberate step. The same card becomes the result (answered, closed), or a
/// disabled list for a person who may only read, in the same place, so a
/// state never moves.
///
/// It sends through [answer] and tells the screen what the server decided
/// through [onState], so the event the screen holds follows.
class AnswerCard extends StatefulWidget {
  const AnswerCard({
    super.key,
    required this.event,
    required this.myUserId,
    required this.answer,
    required this.onState,
    required this.onRead,
    required this.onGone,
    this.now = DateTime.now,
  });

  /// The event, with a question; the card follows it as it changes.
  final Event event;
  final String? myUserId;

  /// Sends the answer (the choices' ids and the typed text).
  final Future<AnswerOutcome> Function(List<String> choices, String? text)
  answer;

  /// A new state of the question: an accepted answer, the winner of a `409`.
  final void Function(QuestionState state) onState;

  /// The event read again from the server: after a refusal that may be
  /// "not allowed", or when the question closes by its time.
  final void Function(Event event) onRead;

  /// The event is not in the inbox any more.
  final VoidCallback onGone;

  /// The clock, for the closing time; tests replace it.
  final DateTime Function() now;

  @override
  State<AnswerCard> createState() => _AnswerCardState();
}

class _AnswerCardState extends State<AnswerCard> {
  late final _Draft _draft = _drafts.putIfAbsent(widget.event.id, _Draft.new);
  late final _note = TextEditingController(text: _draft.note);
  late final _other = TextEditingController(text: _draft.other);
  final _firstChoice = FocusNode();
  final _noteFocus = FocusNode();
  final _otherFocus = FocusNode();
  final _resultTitle = FocusNode();

  bool _sending = false;
  String? _pickError;
  String? _noteError;
  String? _otherError;
  Attempt _attempt = Attempt.none;
  bool _lostRight = false;
  Timer? _timer;

  Ask get _ask => widget.event.ask!;

  bool get _open => widget.event.answerState == AnswerState.open;

  @override
  void initState() {
    super.initState();
    // A controller also notifies when only the cursor moves; only typing
    // changes what is said about the text.
    _note.addListener(() {
      if (_note.text == _draft.note) return;
      _draft.note = _note.text;
      _check(_note, (e) => _noteError = e);
    });
    _other.addListener(() {
      if (_other.text == _draft.other) return;
      _draft.other = _other.text;
      _check(_other, (e) => _otherError = e);
    });
    _tick();
  }

  @override
  void didUpdateWidget(AnswerCard old) {
    super.didUpdateWidget(old);
    _tick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _note.dispose();
    _other.dispose();
    _firstChoice.dispose();
    _noteFocus.dispose();
    _otherFocus.dispose();
    _resultTitle.dispose();
    super.dispose();
  }

  /// Keeps the closing line current once a minute and reads the event again
  /// when the question closes by its time. The minutes are not announced.
  void _tick() {
    _timer?.cancel();
    final closes = _ask.closesAt;
    if (!_open || closes == null) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (!widget.now().isBefore(closes)) {
        _timer?.cancel();
        widget.onRead(widget.event);
      }
      setState(() {});
    });
  }

  /// Said as soon as the text passes 3000, never by cutting it.
  void _check(TextEditingController controller, void Function(String?) set) {
    final over = _length(controller.text) - _maxText;
    final before = _tooLongShown(controller);
    setState(() => set(over > 0 ? _tooLong(over) : null));
    if (over > 0 && !before) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          _tooLong(over),
          Directionality.of(context),
        ),
      );
    }
  }

  bool _tooLongShown(TextEditingController controller) =>
      identical(controller, _note)
      ? _noteError?.startsWith('Too long') ?? false
      : _otherError?.startsWith('Too long') ?? false;

  static String _tooLong(int over) =>
      'Too long: $over ${over == 1 ? 'character' : 'characters'} over the '
      'limit.';

  // ---- Choosing

  void _pick(String id, bool on) {
    setState(() {
      _pickError = null;
      if (_ask.multiple) {
        if (id == _otherId) {
          _draft.otherOn = on;
        } else {
          on ? _draft.picked.add(id) : _draft.picked.remove(id);
        }
      } else {
        _draft.picked = id == _otherId ? {} : {id};
        _draft.otherOn = id == _otherId;
      }
      if (!_draft.otherOn) _otherError = null;
    });
    // Picking Other moves the focus to its field.
    if (id == _otherId && _draft.otherOn) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _otherFocus.requestFocus(),
      );
    }
  }

  // ---- Sending

  /// The first thing wrong with what is picked and typed, or `null`. It moves
  /// the focus there; the message is that control's own.
  bool _blocked() {
    final ask = _ask;
    final pickedNone = _draft.picked.isEmpty && !_draft.otherOn;
    if (!ask.isTyped && pickedNone) {
      setState(
        () => _pickError = ask.multiple
            ? 'Pick at least one answer.'
            : 'Pick an answer to send.',
      );
      _firstChoice.requestFocus();
      return true;
    }
    if (_draft.otherOn) {
      if (_other.text.trim().isEmpty) {
        setState(() => _otherError = 'Type your answer for Other.');
        _otherFocus.requestFocus();
        return true;
      }
      if (_length(_other.text) > _maxText) {
        _otherFocus.requestFocus();
        return true;
      }
    }
    if (ask.isTyped || ask.hasNote) {
      final required = ask.isTyped || ask.text == AskText.required;
      if (required && _note.text.trim().isEmpty) {
        setState(
          () => _noteError = ask.isTyped
              ? 'Type an answer to send.'
              : 'Type a note to send.',
        );
        _noteFocus.requestFocus();
        return true;
      }
      if (_length(_note.text) > _maxText) {
        _noteFocus.requestFocus();
        return true;
      }
    }
    return false;
  }

  Future<void> _send() async {
    if (_sending || _blocked()) return;
    final ask = _ask;
    final choices = [
      for (final c in ask.choices)
        if (_draft.picked.contains(c.id)) c.id,
    ];
    final text = ask.hasOtherRow
        ? (_draft.otherOn ? _other.text.trim() : '')
        : (ask.isTyped || ask.hasNote ? _note.text.trim() : '');
    setState(() => _sending = true);
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Sending answer',
        Directionality.of(context),
      ),
    );
    final outcome = await widget.answer(choices, text.isEmpty ? null : text);
    if (!mounted) return;
    setState(() => _sending = false);
    switch (outcome) {
      case AnswerAccepted(:final state):
        _drafts.remove(widget.event.id);
        _decided(state);
      case AnswerRefused(:final state):
        _attempt = state.state == AnswerState.answered
            ? Attempt.answeredFirst
            : Attempt.closedWhileChoosing;
        _drafts.remove(widget.event.id);
        _decided(state);
      case AnswerNotAllowed(:final event):
        if (!event.canAnswer && event.answerState == AnswerState.open) {
          setState(() => _lostRight = true);
          widget.onRead(event);
        } else {
          widget.onRead(event);
          _failed();
        }
      case AnswerGone():
        widget.onGone();
      case AnswerFailed():
        _failed();
    }
  }

  void _failed() {
    showAppSnackBar(
      context,
      'Answer not sent',
      actionLabel: 'Retry',
      onAction: () => unawaited(_send()),
    );
  }

  /// The card turns into the result without animation, said once, and the
  /// focus goes to its title so it is never lost.
  void _decided(QuestionState state) {
    widget.onState(state);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resultTitle.requestFocus();
    });
  }

  // ---- Building

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final result = resultOf(
      event,
      myUserId: widget.myUserId,
      attempt: _attempt,
      now: widget.now(),
    );
    final Widget body;
    if (result != null) {
      body = _Result(result: result, focus: _resultTitle);
    } else if (_open && event.canAnswer) {
      body = _form(context);
    } else if (_open) {
      body = _readOnly(context);
    } else {
      body = const SizedBox.shrink();
    }
    return Container(
      key: const Key('answerCard'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: body,
    );
  }

  Widget _readOnly(BuildContext context) {
    final theme = Theme.of(context);
    final ask = _ask;
    return Column(
      key: const Key('readOnlyCard'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          liveRegion: _lostRight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      readOnlyTitle(ask),
                      style: theme.textTheme.titleMedium,
                    ),
                    _Quiet('You can read the question.'),
                    if (_lostRight)
                      _Quiet(
                        "Your answer wasn't sent. You can no longer answer "
                        'this question.',
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // The choices as a disabled list: nothing here looks pressable.
        Column(
          children: [
            for (final c in ask.choices) _ReadOnlyRow(c.label, c.description),
            if (ask.hasOtherRow) const _ReadOnlyRow('Other', null),
          ],
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ask = _ask;
    final producer = widget.event.producer.name;
    final rule = ask.isTyped
        ? 'Type your answer.'
        : ask.multiple
        ? 'Pick one or more.'
        : 'Pick one.';
    final closes = ask.closesAt;
    final left = closes?.difference(widget.now());
    final soon = left != null && !left.isNegative && left.inMinutes < 60;
    final choiceRows = <Widget>[
      for (final (i, c) in ask.choices.indexed)
        _ChoiceRow(
          key: Key('choice-${c.id}'),
          label: c.label,
          description: c.description,
          multiple: ask.multiple,
          selected: _draft.picked.contains(c.id),
          focusNode: i == 0 ? _firstChoice : null,
          onChanged: (on) => _pick(c.id, on),
        ),
      if (ask.hasOtherRow)
        _ChoiceRow(
          key: const Key('choice-other'),
          label: 'Other',
          multiple: ask.multiple,
          selected: _draft.otherOn,
          focusNode: ask.choices.isEmpty ? _firstChoice : null,
          onChanged: (on) => _pick(_otherId, on),
        ),
    ];
    final dim = _sending ? 0.55 : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (closes != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 18,
                  color: soon ? colors.error : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    soon
                        ? '${closesText(closes, widget.now())} · in '
                              '${left.inMinutes < 1 ? 1 : left.inMinutes + 1} '
                              'min'
                        : closesText(closes, widget.now()),
                    key: const Key('closesLine'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: soon ? colors.error : colors.onSurfaceVariant,
                      fontWeight: soon ? FontWeight.w500 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Text('Your answer', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        _Quiet("$rule It goes to $producer and can't be changed once sent."),
        Opacity(
          opacity: dim,
          child: IgnorePointer(
            ignoring: _sending,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (choiceRows.isNotEmpty)
                  Semantics(
                    container: true,
                    label: 'Your answer',
                    child: Column(children: choiceRows),
                  ),
                if (_pickError != null) _FieldError(_pickError!),
                if (_draft.otherOn)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 40,
                      top: 8,
                      bottom: 8,
                    ),
                    child: _TextArea(
                      key: const Key('otherField'),
                      controller: _other,
                      focusNode: _otherFocus,
                      label: 'Your answer',
                      semanticLabel: 'Your answer for Other',
                      minLines: 1,
                      maxLines: 4,
                      error: _otherError,
                    ),
                  ),
                if (ask.isTyped || ask.hasNote)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _TextArea(
                      key: const Key('noteField'),
                      controller: _note,
                      focusNode: _noteFocus,
                      label: ask.isTyped
                          ? 'Your answer'
                          : ask.text == AskText.required
                          ? 'Note'
                          : 'Note (optional)',
                      hint: ask.isTyped ? null : 'Add a note for $producer',
                      minLines: ask.isTyped ? 3 : 1,
                      maxLines: ask.isTyped ? 6 : 4,
                      error: _noteError,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            label: _sending ? 'Sending answer' : null,
            child: FilledButton.icon(
              key: const Key('sendAnswer'),
              onPressed: _sending ? () {} : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              label: Text(_sending ? 'Sending' : 'Send answer'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Padding(
      key: const Key('pickError'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.error_outline, size: 16, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// One choice: a whole 48 dp row is the target, not the 20 dp control. The
/// description is its accessible hint, read after its name.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    super.key,
    required this.label,
    required this.multiple,
    required this.selected,
    required this.onChanged,
    this.description,
    this.focusNode,
  });

  final String label;
  final String? description;
  final bool multiple;
  final bool selected;
  final FocusNode? focusNode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyLarge),
        if (description != null)
          Text(
            description!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    return Semantics(
      container: true,
      inMutuallyExclusiveGroup: !multiple,
      checked: selected,
      label: label,
      hint: description,
      excludeSemantics: true,
      onTap: () => onChanged(multiple ? !selected : true),
      child: InkWell(
        focusNode: focusNode,
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(multiple ? !selected : true),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: description == null ? 0 : 12,
            ),
            child: Row(
              crossAxisAlignment: description == null
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                _Control(multiple: multiple, selected: selected),
                const SizedBox(width: 16),
                Expanded(child: text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 20 dp radio or checkbox: drawn, not a widget of its own, so the whole
/// row is the one target.
class _Control extends StatelessWidget {
  const _Control({required this.multiple, required this.selected});

  final bool multiple;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return SizedBox.square(
      dimension: 24,
      child: Center(
        child: multiple
            ? Container(
                key: Key(selected ? 'checked' : 'unchecked'),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: selected ? colors.primary : null,
                  border: Border.all(color: color, width: 2),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: selected
                    ? Icon(Icons.check, size: 14, color: colors.onPrimary)
                    : null,
              )
            : Container(
                key: Key(selected ? 'selected' : 'unselected'),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary,
                          ),
                        ),
                      )
                    : null,
              ),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow(this.label, this.description);

  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: description == null ? 0 : 12),
        child: Row(
          crossAxisAlignment: description == null
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: 24,
              child: Icon(
                Icons.remove,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(color: grey),
                  ),
                  if (description != null)
                    Text(
                      description!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A multi-line outlined field with a counter. It starts at [minLines], grows
/// to [maxLines] and then scrolls; Enter adds a line. Text past 3000 is never
/// cut: the counter and the message turn to the error colour.
class _TextArea extends StatelessWidget {
  const _TextArea({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.minLines,
    required this.maxLines,
    this.hint,
    this.error,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String? semanticLabel;
  final String? hint;
  final int minLines;
  final int maxLines;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final over = _length(controller.text) > _maxText;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      minLines: minLines,
      maxLines: maxLines,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        semanticCounterText: '${_length(controller.text)} of $_maxText',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hint,
        border: const OutlineInputBorder(),
        errorText: error,
        errorMaxLines: 3,
        counterText: '${_length(controller.text)} / $_maxText',
        counterStyle: over ? TextStyle(color: colors.error) : null,
      ),
    );
  }
}

/// A decided question: its icon and words, said once in a live region.
class _Result extends StatelessWidget {
  const _Result({required this.result, required this.focus});

  final QuestionResult result;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = result.mine ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        key: const Key('questionResult'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(result.icon, color: color)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Focus(
                  focusNode: focus,
                  child: Text(
                    result.title,
                    key: const Key('resultTitle'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                for (final (i, line) in result.lines.indexed)
                  Text(
                    line,
                    key: i == result.textLine ? const Key('resultText') : null,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
