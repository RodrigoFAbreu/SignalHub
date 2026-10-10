import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An outlined single-line text field for a name of 1 to 100 characters. An
/// error shows under it, and the border, the label and a trailing icon all
/// turn to the error colour, so it is never colour alone.
class NameField extends StatelessWidget {
  const NameField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
  });

  static const maxLength = 100;

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    textInputAction: textInputAction,
    // No counter: the limit is said in words under the field.
    inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
    decoration: InputDecoration(
      labelText: label,
      errorText: errorText,
      errorMaxLines: 3,
      border: const OutlineInputBorder(),
      suffixIcon: errorText == null
          ? null
          : Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
    ),
  );
}
