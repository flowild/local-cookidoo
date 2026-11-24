import 'package:material_ui/material_ui.dart';

import 'pill_widgets.dart';
import 'spacing.dart';

String calendarDateLabel(String date) => date.split('-').reversed.join('.');

String calendarDayLabel(int index, String date) {
  const days = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];
  final weekday = days[index % 7];
  return date.isEmpty ? weekday : '$weekday, ${calendarDateLabel(date)}';
}

class CalendarWeekLabel extends StatelessWidget {
  const CalendarWeekLabel({super.key, required this.date, required this.today});

  final String? date;
  final String today;

  DateTime _monday(DateTime day) =>
      DateTime.utc(day.year, day.month, day.day - day.weekday + 1);

  @override
  Widget build(BuildContext context) {
    final displayed = DateTime.tryParse(date ?? '');
    final monday = displayed == null ? null : _monday(displayed);
    // The Thursday determines the ISO week year, even if Monday is in December.
    final thursday = monday?.add(const Duration(days: 3));
    final week = thursday == null
        ? null
        : 1 + thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7;
    final current = DateTime.tryParse(today);
    final isCurrent = current != null && _monday(current) == monday;
    final theme = Theme.of(context);
    final color = isCurrent
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      label: week == null
          ? 'Kalenderwoche wird geladen'
          : '${isCurrent ? 'Aktuelle Kalenderwoche' : 'Kalenderwoche'} $week',
      excludeSemantics: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.related),
            child: Text(
              week == null ? 'KW –' : 'KW $week',
              style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          if (isCurrent)
            Positioned(
              bottom: 0,
              width: 16,
              height: 2,
              child: ColoredBox(color: color),
            ),
        ],
      ),
    );
  }
}

class CalendarDayHeading extends StatelessWidget {
  const CalendarDayHeading(
    this.title, {
    super.key,
    required this.isToday,
    this.style,
  });

  final String title;
  final bool isToday;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final heading = Text(title, style: style);
    if (!isToday) return heading;
    return Wrap(
      spacing: AppSpacing.related,
      runSpacing: AppSpacing.tight,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [heading, const InfoPill('Heute', highlighted: true)],
    );
  }
}
