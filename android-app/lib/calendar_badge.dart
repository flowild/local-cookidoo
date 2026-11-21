import 'package:material_ui/material_ui.dart';

import 'spacing.dart';

class CalendarWeekBadge extends StatelessWidget {
  const CalendarWeekBadge({super.key, required this.date, required this.today});

  final String date;
  final String today;

  DateTime _monday(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day - day.weekday + 1);

  @override
  Widget build(BuildContext context) {
    final displayed = DateTime.tryParse(date);
    if (displayed == null) return const SizedBox.shrink();
    final monday = _monday(displayed);
    // The Thursday determines the ISO week year, even if Monday is in December.
    final thursday = monday.add(const Duration(days: 3));
    final week =
        1 + thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7;
    final current = DateTime.tryParse(today);
    final isCurrent = current != null && _monday(current) == monday;
    return Semantics(
      container: true,
      label: isCurrent ? 'Aktuelle Kalenderwoche $week' : 'Kalenderwoche $week',
      excludeSemantics: true,
      child: _CalendarBadge(label: 'KW $week', highlighted: isCurrent),
    );
  }
}

class TodayBadge extends StatelessWidget {
  const TodayBadge({super.key});

  @override
  Widget build(BuildContext context) =>
      const _CalendarBadge(label: 'Heute', highlighted: true);
}

class _CalendarBadge extends StatelessWidget {
  const _CalendarBadge({required this.label, required this.highlighted});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.related,
        vertical: AppSpacing.tight,
      ),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: highlighted ? colors.primary : colors.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: highlighted ? colors.onPrimary : colors.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
