import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'calendar_badge.dart';
import 'expandable_list_card.dart';
import 'spacing.dart';
import 'ingredient_icon.dart';
import 'symbol_field.dart';
import 'telegram_service.dart';

const _placeholderNames = {
  'restaurant': 'Im Restaurant essen',
  'fastfood': 'Fastfood',
  'sushi': 'Sushi',
  'pasta': 'Pasta mit Pesto',
  'abendbrot': 'Abendbrot',
  'resteessen': 'Resteessen',
};

class TelegramView extends StatefulWidget {
  const TelegramView({
    super.key,
    required this.telegram,
    required this.cart,
    this.notice,
  });
  final TelegramService telegram;
  final bool cart;
  final String? notice;

  @override
  State<TelegramView> createState() => _TelegramViewState();
}

class _TelegramViewState extends State<TelegramView> {
  final _todayHeading = GlobalKey();
  late DateTime monday;
  late Future<Json> snapshot;
  late Map<String, bool> checks;
  bool checksLoaded = false;
  bool initialWeek = true;
  int _request = 0;
  int? _scrollToTodayRequest;

  DateTime _monday(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day - date.weekday + 1);

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    monday = _monday(DateTime.now());
    snapshot = _load();
  }

  @override
  void didUpdateWidget(TelegramView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cart != widget.cart) snapshot = _load();
  }

  Future<Json> _load() async {
    final request = ++_request;
    if (widget.cart && !checksLoaded) {
      try {
        checks = await widget.telegram.loadChecks();
        checksLoaded = true;
      } catch (_) {
        throw const ApiException(
          'Die gespeicherten Häkchen konnten nicht geladen werden.',
        );
      }
    }
    final data = await widget.telegram.snapshot(
      widget.cart ? 'cart' : 'week',
      day: widget.cart ? null : _date(monday),
    );
    if (mounted && request == _request && !widget.cart && initialWeek) {
      initialWeek = false;
      final today = DateTime.tryParse(text(data['today']));
      if (today != null && _date(_monday(today)) != _date(monday)) {
        monday = _monday(today);
        return widget.telegram.snapshot('week', day: _date(monday));
      }
    }
    return data;
  }

  void _refresh() {
    setState(() {
      snapshot = _load();
    });
  }

  void _showToday(String today) {
    monday = _monday(DateTime.tryParse(today) ?? DateTime.now());
    initialWeek = true;
    _refresh();
    _scrollToTodayRequest = _request;
  }

  void _saveChecks() {
    widget.telegram.saveChecks(checks).catchError((Object _) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Die Häkchen konnten nicht auf diesem Gerät gespeichert werden.',
            ),
          ),
        );
      }
    });
  }

  Widget _week(Json data, {required bool loaded}) {
    final days = objects(data['days']);
    final today = text(data['today']);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (loaded && _scrollToTodayRequest == _request) {
      final request = _request;
      _scrollToTodayRequest = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _request != request) return;
        final heading = _todayHeading.currentContext;
        if (heading != null) Scrollable.ensureVisible(heading);
      });
    }

    Widget? entries(Object? raw, {bool placeholders = false}) {
      final items = raw is List ? raw.whereType<String>() : const <String>[];
      if (items.isEmpty) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppSpacing.tight,
        children: [
          for (final item in items)
            Text(placeholders ? _placeholderNames[item] ?? item : item),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.item,
      children: [
        Text('Meine Woche', style: theme.textTheme.headlineMedium),
        Row(
          spacing: AppSpacing.related,
          children: [
            IconButton(
              tooltip: 'Vorherige Woche',
              onPressed: () {
                monday = monday.subtract(const Duration(days: 7));
                _refresh();
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Column(
                children: [
                  CalendarWeekLabel(date: _date(monday), today: today),
                  Text(
                    calendarDateLabel(_date(monday)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Flexible(
              child: TextButton(
                onPressed: () => _showToday(today),
                child: const Text('Heute', textAlign: TextAlign.center),
              ),
            ),
            IconButton(
              tooltip: 'Nächste Woche',
              onPressed: () {
                monday = monday.add(const Duration(days: 7));
                _refresh();
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        if (data['queue_error'] == true ||
            ['error', 'uncertain'].contains(data['queue_phase']))
          const Text(
            'Wochenänderungen konnten nicht vollständig übertragen werden.',
          )
        else if (data['queue_phase'] != 'idle')
          const Text(
            'Vorgemerkte Änderungen sind berücksichtigt und warten auf den Abgleich.',
          ),
        for (final (index, day) in days.indexed)
          Card(
            color: day['date'] == today ? colors.primaryContainer : null,
            child: Padding(
              padding: AppSpacing.compactPanel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppSpacing.related,
                children: [
                  CalendarDayHeading(
                    calendarDayLabel(index, text(day['date'])),
                    key: day['date'] == today ? _todayHeading : null,
                    isToday: day['date'] == today,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: day['date'] == today
                          ? colors.onPrimaryContainer
                          : null,
                      fontWeight: day['date'] == today ? FontWeight.w800 : null,
                    ),
                  ),
                  if (entries(day['recipes']) case final Widget recipes)
                    recipes,
                  if (entries(day['placeholders'], placeholders: true)
                      case final Widget placeholders)
                    placeholders,
                ],
              ),
            ),
          ),
        Card(
          child: Padding(
            padding: AppSpacing.compactPanel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.related,
              children: [
                Text('Ablage', style: Theme.of(context).textTheme.titleMedium),
                if (entries(data['shelf']) case final Widget recipes) recipes,
                if (entries(data['shelf_placeholders'], placeholders: true)
                    case final Widget placeholders)
                  placeholders,
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _cart(Json data) {
    final rows = <Json>[];
    final items = objects(data['items']);
    final recipes = items.where((item) => item['kind'] == 'recipe').toList();
    for (final item in items) {
      if (item['kind'] == 'additional') {
        rows.add({...item, 'text': item['name'], 'icon_name': item['name']});
      }
      if (item['kind'] == 'recipe') {
        for (final ingredient in objects(item['ingredients'])) {
          if (ingredient['in_pantry'] != true) {
            rows.add({...ingredient, 'recipe': item['name']});
          }
        }
      }
    }
    bool checked(Json row) =>
        checks[text(row['check_id'])] ?? (row['owned'] == true);
    rows.sort((a, b) {
      final order = (checked(a) ? 1 : 0).compareTo(checked(b) ? 1 : 0);
      if (order != 0) return order;
      return text(a['category']).compareTo(text(b['category']));
    });
    return [
      SliverToBoxAdapter(
        child: Row(
          spacing: AppSpacing.related,
          children: [
            Expanded(
              child: Text(
                'Mein Einkaufswagen',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              tooltip: 'Häkchen zurücksetzen',
              onPressed: () {
                setState(() => checks = {});
                _saveChecks();
              },
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
      ),
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (index == 0 || checked(row) != checked(rows[index - 1]))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.section),
                  child: Text(
                    checked(row) ? 'Abgehakt' : 'Zutaten',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              if (index == 0 ||
                  checked(row) != checked(rows[index - 1]) ||
                  text(row['category']) != text(rows[index - 1]['category']))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.related),
                  child: SymbolLabel(
                    text(row['category'], 'Sonstiges'),
                    shoppingCategoryIcon(
                      text(row['category'], 'Sonstiges'),
                      row['category_icon'],
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: checked(row),
                onChanged: (value) {
                  setState(() => checks[text(row['check_id'])] = value == true);
                  _saveChecks();
                },
                title: Row(
                  children: [
                    IngredientIcon(
                      text(row['icon_name']),
                      category: text(row['category']),
                      selected: row['icon'],
                    ),
                    const SizedBox(width: AppSpacing.related),
                    Expanded(child: Text(text(row['text']))),
                  ],
                ),
                subtitle: row['recipe'] == null
                    ? null
                    : Text(text(row['recipe'])),
              ),
            ],
          );
        },
      ),
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isEmpty) ...[
              const SizedBox(height: AppSpacing.section),
              const Text('Der Einkaufswagen enthält keine benötigten Zutaten.'),
            ],
            const SizedBox(height: AppSpacing.section),
            ExpandableListCard(
              title: 'Rezepte (${recipes.length})',
              leading: const Icon(Icons.menu_book_outlined),
              body: Column(
                children: [
                  if (recipes.isEmpty)
                    const ListTile(
                      title: Text('Keine Rezepte im Einkaufswagen.'),
                    ),
                  for (final recipe in recipes)
                    ListTile(title: Text(text(recipe['name'], 'Rezept'))),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    key: ValueKey(widget.cart),
    future: snapshot,
    builder: (context, result) => RefreshIndicator(
      onRefresh: () async {
        _refresh();
        try {
          await snapshot;
        } on Exception {
          /* The view shows the error. */
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: AppSpacing.page,
            sliver: SliverMainAxisGroup(
              slivers: [
                if (widget.notice != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: AppSpacing.section,
                      ),
                      child: Text(widget.notice!),
                    ),
                  ),
                if (result.connectionState != ConnectionState.done &&
                    !(result.hasData &&
                        (widget.cart ||
                            objects(result.data?['days'])
                                    .firstOrNull?['date'] ==
                                _date(monday))))
                  const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (result.hasError)
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Text(
                          widget.cart && !checksLoaded
                              ? 'Die gespeicherten Häkchen konnten nicht geladen werden.'
                              : 'Telegram-Daten konnten nicht geladen werden.',
                        ),
                        const SizedBox(height: AppSpacing.related),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Erneut laden'),
                        ),
                      ],
                    ),
                  )
                else if (widget.cart)
                  ..._cart(result.requireData)
                else
                  SliverToBoxAdapter(
                    child: _week(
                      result.requireData,
                      loaded: result.connectionState == ConnectionState.done,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
