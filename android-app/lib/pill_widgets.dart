import 'package:material_ui/material_ui.dart';

import 'spacing.dart';

/// Equal-width rows for the pairs of related actions shown on a page.
class ActionPillGrid extends StatelessWidget {
  const ActionPillGrid({
    super.key,
    required this.minColumnWidth,
    required this.children,
  });

  final double minColumnWidth;
  final List<Widget> children;

  static const buttonStyle = ButtonStyle(
    alignment: Alignment.center,
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 6, vertical: AppSpacing.tight),
    ),
    iconSize: WidgetStatePropertyAll(18),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      const gap = AppSpacing.related;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final minWidth = minColumnWidth * scale.clamp(1.0, double.infinity);
      final columns = [4, 2, 1].firstWhere(
        (n) =>
            n == 1 ||
            (n <= children.length &&
                n * minWidth + (n - 1) * gap <= bounds.maxWidth),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.tight,
        children: [
          for (var i = 0; i < children.length; i += columns)
            if (columns == 1)
              children[i]
            else
              IntrinsicHeight(
                child: Row(
                  spacing: gap,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns; j++)
                      Expanded(
                        child: i + j < children.length
                            ? children[i + j]
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
        ],
      );
    },
  );
}

/// A read-only label that wraps at the available width.
class InfoPill extends StatelessWidget {
  const InfoPill(this.label, {super.key, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: highlighted ? colors.primary : colors.secondaryContainer,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.related,
          vertical: AppSpacing.tight,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: highlighted ? colors.onPrimary : colors.onSecondaryContainer,
            fontWeight: highlighted ? FontWeight.w700 : null,
          ),
        ),
      ),
    );
  }
}
