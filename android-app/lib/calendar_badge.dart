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
      child: InfoPill('KW $week', highlighted: isCurrent),
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
