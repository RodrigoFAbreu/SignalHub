import 'package:flutter/material.dart';

import '../models/producer_name.dart';

/// The words under a producer's name field, shown while the name is typed, on
/// _New producer_ and in the rename dialog alike.
abstract final class NameMessages {
  static const taken =
      'That name is taken. Names are shared by everyone on this server.';
  static const notAllowed =
      'Use letters, numbers and . _ : / - only, starting with a letter or '
      'number.';
  static const empty = 'Give it a name.';
  static const tooLong = 'Use 100 characters or fewer.';
  static const help =
      'Letters, numbers and . _ : / - only, starting with a letter or number. '
      'Others see this name.';

  static String of(NameProblem problem) => switch (problem) {
    NameProblem.empty => empty,
    NameProblem.notAllowed => notAllowed,
    NameProblem.tooLong => tooLong,
  };
}

/// A producer's name: an outlined field named _Name_ whose problems show
/// under it while the person types. Its border, label, help line and a
/// trailing icon all turn to the error colour, so it is never colour alone.
/// An empty field is a problem only once it was left.
///
/// [serverError] is what the server said about the name last asked, shown in
/// place of the typed name's own problems until the name changes.
class ProducerNameField extends StatefulWidget {
  const ProducerNameField({
    super.key,
    required this.controller,
    this.serverError,
    this.help,
    this.autofocus = false,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? serverError;

  /// Shown under the field while it has no error.
  final String? help;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onSubmitted;

  @override
  State<ProducerNameField> createState() => _ProducerNameFieldState();
}

class _ProducerNameFieldState extends State<ProducerNameField> {
  final _focus = FocusNode();
  bool _left = false;
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_noticeLeaving);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _noticeLeaving() {
    if (_hadFocus && !_focus.hasFocus) setState(() => _left = true);
    _hadFocus = _focus.hasFocus;
  }

  String? _error() {
    if (widget.serverError case final error?) return error;
    final problem = ProducerName.check(widget.controller.text);
    if (problem == NameProblem.empty && !_left) return null;
    return problem == null ? null : NameMessages.of(problem);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color, width: width),
    );
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final error = _error();
        return TextField(
          key: const Key('producerName'),
          controller: widget.controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.onSubmitted?.call(),
          decoration: InputDecoration(
            labelText: 'Name',
            helperText: widget.help,
            helperMaxLines: 4,
            errorText: error,
            errorMaxLines: 4,
            suffixIcon: error == null
                ? null
                : Icon(Icons.error_outline, color: colors.error),
            enabledBorder: border(colors.outline, 1),
            focusedBorder: border(colors.primary, 2),
            errorBorder: border(colors.error, 2),
            focusedErrorBorder: border(colors.error, 2),
          ),
        );
      },
    );
  }
}
