import 'package:flutter/material.dart';

/// A 56 dp search field: surfaceContainerHigh, fully rounded, a leading
/// search icon and, once something is typed, a 48 dp _Clear search_ button.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.bottomPadding = 8,
  });

  final TextEditingController controller;

  /// The field's hint and accessible name, such as `Find a producer`.
  final String hint;
  final ValueChanged<String> onChanged;

  /// Space under the field; a strip whose own hit areas are 48 dp high
  /// (filter chips) asks for none.
  final double bottomPadding;

  /// 56 dp, and taller as the text grows past its size: 72 dp at 200 %.
  static double _height(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return scale <= 1 ? 56 : 56 + (scale - 1) * 16;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
      child: SizedBox(
        height: _height(context),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: colors.surfaceContainerHigh,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
