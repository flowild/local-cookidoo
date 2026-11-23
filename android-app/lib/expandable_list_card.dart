import 'package:material_ui/material_ui.dart';

class ExpandableListCard extends StatelessWidget {
  const ExpandableListCard({
    super.key,
    this.expansionKey,
    required this.title,
    this.leading,
    this.action,
    this.subtitle,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.wrapTitle,
    required this.body,
  });

  final Key? expansionKey;
  final String title;
  final Widget? leading;
  final Widget? action;
  final Widget? subtitle;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final Widget Function(Widget)? wrapTitle;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.onSecondaryContainer,
      ),
    );
    final label = wrapTitle?.call(text) ?? text;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: expansionKey,
        backgroundColor: colors.secondaryContainer,
        collapsedBackgroundColor: colors.secondaryContainer,
        textColor: colors.onSecondaryContainer,
        collapsedTextColor: colors.onSecondaryContainer,
        iconColor: colors.onSecondaryContainer,
        collapsedIconColor: colors.onSecondaryContainer,
        shape: const Border(),
        collapsedShape: const Border(),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        leading: leading,
        title: action == null
            ? label
            : Row(
                children: [
                  Expanded(child: label),
                  action!,
                ],
              ),
        subtitle: subtitle,
        children: [Material(color: colors.surfaceContainerLow, child: body)],
      ),
    );
  }
}
