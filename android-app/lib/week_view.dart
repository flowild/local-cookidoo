import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'recipe_card.dart';

const _placeholders = {
  'restaurant': ('Im Restaurant essen', '🍴'),
  'fastfood': ('Fastfood', '🍔'),
  'sushi': ('Sushi', '🍣'),
  'pasta': ('Pasta mit Pesto', '🍝'),
  'abendbrot': ('Abendbrot', '🍞'),
  'resteessen': ('Resteessen', '🍲'),
};
const _weekdays = [
  'Montag',
  'Dienstag',
  'Mittwoch',
  'Donnerstag',
  'Freitag',
  'Samstag',
  'Sonntag',
];
final _moveRandom = Random.secure();

String _dayString(DateTime value) => value.toIso8601String().substring(0, 10);

class _WeekEntry {
  const _WeekEntry(this.source, this.data, {this.placeholder = false});
  final String source;
  final Json data;
  final bool placeholder;

  String get identity => '$source:${data['id'] ?? data['placeholder']}';
  String get id => text(data['id']);
  String get type => text(data['placeholder']);
  bool get custom => data['custom'] == true || id.startsWith('creation:');
  String get calendarId => text(
    data['calendar_id'],
    id.startsWith('creation:') ? id.substring('creation:'.length) : id,
  );
  String get name => placeholder
      ? _placeholders[type]?.$1 ?? type
      : text(data['name'], 'Rezept');
}

class WeekView extends StatefulWidget {
  const WeekView({
    super.key,
    required this.api,
    required this.openRecipe,
    required this.cartCountChanged,
    this.statusChanged,
    this.refreshCount = 0,
    this.onSync,
  });

  final RezeptgartenApi api;
  final Future<void> Function(Json recipe, bool calendar) openRecipe;
  final ValueChanged<int> cartCountChanged;
  final ValueChanged<Json>? statusChanged;
  final int refreshCount;
  final Future<void> Function()? onSync;

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  static const _preferences = MethodChannel('de.rezeptgarten/preferences');
  final _daysController = PageController(viewportFraction: .82);
  Json? _week;
  Json _queue = {};
  Map<String, List<Json>> _recipes = {};
  String? _requestedDay;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _openingRecipe = false;
  int _request = 0;
  int _visibleDay = 0;
  Timer? _poll;
  Timer? _undoExpiry;
  ({String name, String id})? _undo;
  String? _selected;
  Offset _gestureDistance = Offset.zero;
  Future<void>? _enrichment;

  String? get _monday =>
      objects(_week?['days']).firstOrNull?['date'] as String?;
  bool get _ready => !_loading && !_busy && _monday != null;
  bool get _canPlaceRecipe =>
      _ready && !['error', 'processing'].contains(_queue['phase']);

  @override
  void initState() {
    super.initState();
    unawaited(_restoreDay());
    unawaited(_load());
    _poll = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_pollQueue()),
    );
  }

  @override
  void didUpdateWidget(WeekView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshCount != oldWidget.refreshCount && !_busy) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _daysController.dispose();
    _poll?.cancel();
    _undoExpiry?.cancel();
    super.dispose();
  }

  Future<void> _restoreDay() async {
    try {
      final saved = await _preferences.invokeMethod<int>('weekDay');
      if (mounted && saved != null && saved >= 0 && saved < 7) {
        _visibleDay = saved;
        _restorePage();
      }
    } on PlatformException {
      // The week remains usable with the default day.
    } on MissingPluginException {
      // SharedPreferences are only available on Android.
    }
  }

  void _restorePage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_daysController.hasClients) return;
      final count = objects(_week?['days']).length;
      if (count > 0) _daysController.jumpToPage(min(_visibleDay, count - 1));
    });
  }

  Future<void> _selectDay(int index) async {
    if (_visibleDay == index) return;
    _visibleDay = index;
    try {
      await _preferences.invokeMethod<void>('setWeekDay', index);
    } on PlatformException {
      // The selected day is retained in memory.
    } on MissingPluginException {
      // SharedPreferences are only available on Android.
    }
  }

  Future<Json> _status() async => await widget.api.get(
    '/api/status',
    timeout: const Duration(milliseconds: 2500),
  ) as Json;

  void _cartCount(Json status) {
    widget.statusChanged?.call(status);
    final count = status['cart_recipe_count'];
    if (count is int) widget.cartCountChanged(count);
  }

  Future<void> _load({bool showPrevious = false}) async {
    final request = ++_request;
    final day = _requestedDay;
    final path = day == null
        ? '/api/calendar/week'
        : '/api/calendar/week?day=$day';
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
      if (!showPrevious) {
        _week = null;
        _queue = {};
      }
    });
    try {
      await _enrichment;
      if (!mounted || request != _request) return;
      final status = await _status();
      if (!mounted || request != _request) return;
      _cartCount(status);
      final week = await widget.api.get(path) as Json;
      if (!mounted || request != _request) return;
      final queue = status['calendar_queue'];
      setState(() {
        _week = week;
        _queue = queue is Json ? queue : {};
        _recipes = _project(week, _queue);
        _loading = false;
      });
      _restorePage();
      if (status['connected'] == true && !_busy) {
        final work = _enrich(week, request);
        _enrichment = work;
        unawaited(
          work.whenComplete(() {
            if (identical(_enrichment, work)) _enrichment = null;
          }),
        );
      }
    } on Exception catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _week = null;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted && request == _request && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pollQueue() async {
    if (_busy || _loading || _openingRecipe || _week == null) return;
    final request = _request;
    try {
      final status = await _status();
      if (!mounted ||
          request != _request ||
          _busy ||
          _loading ||
          _openingRecipe) {
        return;
      }
      final queue = status['calendar_queue'];
      _cartCount(status);
      if (queue is Json && jsonEncode(queue) != jsonEncode(_queue)) {
        await _load(showPrevious: true);
      }
    } on Exception {
      // An explicit refresh will display network errors.
    }
  }

  Future<void> _enrich(Json week, int request) async {
    final days = objects(week['days']);
    final recipes = {
      for (final items in _recipes.values)
        for (final item in items) text(item['id']): item,
    };
    final ids = recipes.keys.where((id) => id.isNotEmpty).toList();
    var index = 0;
    try {
      while (index < ids.length &&
          mounted &&
          request == _request &&
          !_busy &&
          !_openingRecipe &&
          !_loading) {
        final batch = ids.skip(index).take(8).toList();
        index += batch.length;
        final uri = Uri(
          path: '/api/calendar/badges',
          queryParameters: {'recipe_id': batch},
        );
        final result = await widget.api.get(uri.toString()) as Json;
        if (!mounted ||
            request != _request ||
            _busy ||
            _loading ||
            _openingRecipe) {
          return;
        }
        final badges = {
          for (final badge in objects(result['items'])) badge['id']: badge,
        };
        setState(() {
          for (final recipes in _recipes.values) {
            for (final recipe in recipes) {
              final badge = badges[recipe['id']];
              if (badge != null) {
                for (final key in [
                  'has_note',
                  'total_seconds',
                  'servings',
                  'difficulty',
                ]) {
                  if (badge[key] != null) recipe[key] = badge[key];
                }
              }
            }
          }
        });
      }
    } on Exception {
      // The calendar is still usable while optional badges are unavailable.
    }
    if (!mounted || request != _request || !_canPlaceRecipe || _openingRecipe) {
      return;
    }
    final unfiled =
        week['needs_collection_setup'] == true ||
        days.any(
          (day) =>
              objects(day['recipes']).any((item) => item['unfiled'] == true),
        );
    if (!unfiled || _monday == null) return;
    try {
      // This endpoint itself rechecks the current account and Cookidoo list.
      final response = await widget.api.write(
        'POST',
        '/api/calendar/save-unfiled',
        {'day': _monday},
      ) as Json;
      if (mounted &&
          request == _request &&
          response['added'] is int &&
          response['added'] > 0) {
        _message('Wochenrezepte ohne Liste wurden in Cookidoo gespeichert.');
      }
    } on Exception catch (error) {
      if (mounted && request == _request) _message(error.toString());
    }
  }

  Map<String, List<Json>> _project(Json week, Json queue) {
    final days = objects(week['days']);
    final result = {
      'shelf': [
        for (final item in objects(week['shelf'])) {...item},
      ],
      for (final day in days)
        text(day['date']): [
          for (final item in objects(day['recipes'])) {...item},
        ],
    };
    final monday = days.firstOrNull?['date'];
    for (final move in objects(queue['items'])) {
      if (move['week'] != null && move['week'] != monday) continue;
      final source = text(move['source']);
      final target = text(move['target']);
      final from = result[source];
      final to = result[target];
      if (from == null || (to == null && target != 'trash')) continue;
      bool matches(Json item) {
        final entry = _WeekEntry(source, item);
        return entry.calendarId == move['recipe_id'] &&
            entry.custom == (move['custom'] == true);
      }

      if (target != 'shelf' && to?.any(matches) == true) continue;
      final index = from.indexWhere(matches);
      final recipe = source == 'shelf'
          ? move['recipe']
          : index < 0
          ? null
          : from.removeAt(index);
      // The backend's shelf is already updated when a placement is queued.
      if (target != 'shelf' && to != null && recipe is Json) {
        to.add({...recipe});
      }
    }
    return result;
  }

  void _navigate(int? offset) {
    if (_busy || _loading) return;
    final base = _monday ?? _requestedDay;
    if (offset == null) {
      _requestedDay = null;
    } else if (base != null) {
      _requestedDay = _dayString(
        DateTime.parse('${base}T12:00:00Z').add(Duration(days: 7 * offset)),
      );
    } else {
      return;
    }
    unawaited(_load());
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _perform(Future<void> Function() write) async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _selected = null;
    });
    try {
      await write();
    } on Exception catch (error) {
      if (!mounted) return;
      _message(error.toString());
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(_WeekEntry entry, String target, String monday) async {
    if (_monday != monday || entry.source == target || !_ready) return;
    if (entry.placeholder) {
      await _perform(() async {
        final result = await widget.api.write(
          'PUT',
          '/api/calendar/placeholders',
          {
            'week': monday,
            'placeholder': entry.type,
            'present': target != 'trash',
            'target': target == 'trash' ? 'shelf' : target,
            'instance_id': entry.data['id'],
            'create': entry.source == 'library',
          },
        ) as Json;
        if (mounted) {
          setState(
            () => _week!['placeholder_placements'] = result['placements'],
          );
        }
      });
      return;
    }
    if (!_canPlaceRecipe) return;
    if (entry.source != 'library' &&
        _recipes[entry.source]?.any((item) => item['id'] == entry.id) != true) {
      return;
    }
    final destination = _recipes[target];
    final exists = destination?.any((item) => item['id'] == entry.id) == true;
    if (exists && (target != 'shelf' || entry.source == 'library')) {
      _message(
        target == 'shelf'
            ? 'Das Rezept liegt bereits in der Ablage.'
            : 'Das Rezept ist dort bereits eingeplant.',
      );
      return;
    }
    final moveId = List.generate(
      16,
      (_) => _moveRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _perform(() async {
      setState(() {
        _recipes[entry.source]?.removeWhere(
          (recipe) => recipe['id'] == entry.id,
        );
        if (!exists) {
          destination?.add({
            ...entry.data,
            'calendar_id': entry.calendarId,
            'custom': entry.custom,
          });
        }
      });
      final result = await widget.api.write('POST', '/api/calendar/placement', {
        'week': monday,
        'source': entry.source,
        'target': target,
        'recipe_id': entry.calendarId,
        'custom': entry.custom,
        'move_id': moveId,
        'recipe': {
          for (final key in [
            'name',
            'image_file',
            'total_seconds',
            'servings',
            'difficulty',
            'has_note',
          ])
            key: entry.data[key],
        },
      }) as Json;
      if (!mounted) return;
      setState(() => _queue = result);
      if (target == 'trash' ||
          objects(result['items']).any(
            (item) => item['move_id'] == moveId && item['target'] == 'trash',
          )) {
        _offerUndo(entry.name, moveId);
      }
    });
  }

  void _offerUndo(String name, String id) {
    _undoExpiry?.cancel();
    setState(() => _undo = (name: name, id: id));
    _undoExpiry = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _undo = null);
    });
  }

  Future<void> _undoRemoval(String id) async {
    if (!_ready || _undo?.id != id) return;
    _undoExpiry?.cancel();
    setState(() => _undo = null);
    await _perform(() async {
      await widget.api.write('POST', '/api/calendar/undo-removal', {
        'move_id': id,
      });
      if (mounted) await _load(showPrevious: true);
    });
  }

  Future<void> _shopping() async {
    final monday = _monday;
    if (!_canPlaceRecipe || monday == null) return;
    await _perform(() async {
      await _enrichment;
      if (!mounted) return;
      final response = await widget.api.write(
        'POST',
        '/api/calendar/shopping',
        {'day': monday},
      ) as Json;
      if (!mounted) return;
      _message(
        text(
          response['message'],
          'Die Wochenrezepte wurden für den Einkaufswagen übernommen.',
        ),
      );
      final status = await _status();
      if (mounted) _cartCount(status);
    });
  }

  Future<void> _discard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Vormerkungen verwerfen?'),
        content: const Text(
          'Bereits in Cookidoo übernommene Änderungen bleiben dort bestehen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await _perform(() async {
      await widget.api.write('DELETE', '/api/calendar/queue');
      if (mounted) await _load(showPrevious: true);
    });
  }

  void _swipe(_WeekEntry entry, Offset distance, String monday) {
    if (_selected != entry.identity ||
        distance.dy.abs() < 90 ||
        distance.dy.abs() <= distance.dx.abs() * 1.3) {
      return;
    }
    final days = objects(_week?['days']);
    final target = entry.source == 'shelf'
        ? (distance.dy > 0 || days.isEmpty
              ? 'trash'
              : text(days[min(_visibleDay, days.length - 1)]['date']))
        : distance.dy > 0
        ? 'shelf'
        : 'trash';
    unawaited(_move(entry, target, monday));
  }

  Future<void> _openRecipe(Json recipe, bool calendar) async {
    if (_busy || _openingRecipe) return;
    _openingRecipe = true;
    try {
      await _enrichment;
      if (mounted) await widget.openRecipe(recipe, calendar);
    } finally {
      _openingRecipe = false;
    }
    if (mounted && !_busy) await _load(showPrevious: true);
  }

  Widget _tile(_WeekEntry entry, String monday) {
    final enabled = entry.placeholder ? _ready : _canPlaceRecipe;
    final selected = _selected == entry.identity;
    final shelf = entry.source == 'shelf';
    final target = shelf ? 'trash' : 'shelf';
    final recipe = entry.placeholder
        ? Card(
            child: ListTile(
              leading: Text(_placeholders[entry.type]?.$2 ?? ''),
              title: Text(entry.name),
              onTap: selected ? () => setState(() => _selected = null) : null,
            ),
          )
        : RecipeCard(
            api: widget.api,
            recipe: entry.data,
            onTap: () async {
              if (_selected != null) {
                setState(() => _selected = null);
                return;
              }
              await _openRecipe(entry.data, true);
            },
          );
    final card = Stack(
      alignment: Alignment.topRight,
      children: [
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: recipe,
        ),
        Material(
          color: Theme.of(context).colorScheme.surface,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: shelf
                ? '${entry.name} entfernen'
                : '${entry.name} in die Ablage',
            onPressed: enabled ? () => _move(entry, target, monday) : null,
            icon: Icon(shelf ? Icons.delete_outline : Icons.close),
          ),
        ),
      ],
    );
    final gestures = GestureDetector(
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
      onLongPressStart: enabled
          ? (_) {
              _gestureDistance = Offset.zero;
              setState(() => _selected = entry.identity);
            }
          : null,
      onLongPressMoveUpdate: enabled
          ? (details) => _gestureDistance = details.offsetFromOrigin
          : null,
      onLongPressEnd: enabled
          ? (_) => _swipe(entry, _gestureDistance, monday)
          : null,
      onVerticalDragStart: selected && enabled
          ? (_) => _gestureDistance = Offset.zero
          : null,
      onVerticalDragUpdate: selected && enabled
          ? (details) => _gestureDistance += details.delta
          : null,
      onVerticalDragEnd: selected && enabled
          ? (_) => _swipe(entry, _gestureDistance, monday)
          : null,
      child: card,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _draggable(entry, monday, enabled, gestures),
    );
  }

  Widget _draggable(
    _WeekEntry entry,
    String monday,
    bool enabled,
    Widget child,
  ) {
    if (!enabled) return child;
    return _MouseWeekDrag(
      data: (item: entry, monday: monday),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(entry.name),
        ),
      ),
      child: child,
    );
  }

  Widget _section(
    String title,
    String target,
    String monday, {
    bool scroll = false,
  }) {
    final recipes = _recipes[target] ?? [];
    final placeholders = objects(_week?['placeholder_placements'])
        .where((item) => item['target'] == target);
    final entries = [
      for (final recipe in recipes) _WeekEntry(target, recipe),
      for (final item in placeholders)
        _WeekEntry(target, item, placeholder: true),
    ];
    return DragTarget<_WeekDrag>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return data.monday == monday &&
            data.item.source != target &&
            (data.item.placeholder ||
                data.item.source != 'library' ||
                target == 'shelf') &&
            (data.item.placeholder ? _ready : _canPlaceRecipe);
      },
      onAcceptWithDetails: (details) =>
          _move(details.data.item, target, details.data.monday),
      builder: (context, hovering, rejected) {
        final content = [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (entries.isEmpty)
            Text(
              target == 'shelf'
                  ? 'Rezepte hier ablegen, wenn der Tag noch offen ist.'
                  : 'Noch nichts geplant',
            ),
          for (final entry in entries) _tile(entry, monday),
        ];
        return Card(
          margin: const EdgeInsets.fromLTRB(5, 0, 5, 12),
          color: hovering.isNotEmpty
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          child: scroll
              ? ListView(
                  primary: false,
                  padding: const EdgeInsets.all(12),
                  children: content,
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: content,
                  ),
                ),
        );
      },
    );
  }

  String _dayLabel(int index, String date) =>
      '${_weekdays[index % 7]}, ${date.split('-').reversed.join('.')}${date == _week?['today'] ? ' · Heute' : ''}';

  Widget _days(String monday) {
    final days = objects(_week?['days']);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, day) in days.indexed)
                Expanded(
                  child: _section(
                    _dayLabel(index, text(day['date'])),
                    text(day['date']),
                    monday,
                  ),
                ),
            ],
          );
        }
        return SizedBox(
          height: (MediaQuery.sizeOf(context).height * .46).clamp(250.0, 460.0),
          child: PageView.builder(
            controller: _daysController,
            itemCount: days.length,
            onPageChanged: _selectDay,
            itemBuilder: (context, index) {
              final date = text(days[index]['date']);
              return _section(
                _dayLabel(index, date),
                date,
                monday,
                scroll: true,
              );
            },
          ),
        );
      },
    );
  }

  Widget _toolbar() {
    final queueError = _queue['phase'] == 'error';
    final state = switch (_queue['phase']) {
      'processing' => 'Änderungen werden mit Cookidoo abgeglichen …',
      'waiting' => 'Änderungen vorgemerkt. Abgleich fünf Minuten nach der letzten Änderung.',
      'error' => text(
        _queue['error'],
        'Der Wochenabgleich konnte nicht bestätigt werden.',
      ),
      _ => '',
    };
    final canNavigate = !_busy && !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Meine Woche', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            IconButton.outlined(
              tooltip: 'Vorherige Woche',
              icon: const Icon(Icons.chevron_left),
              onPressed:
                  canNavigate && (_monday != null || _requestedDay != null)
                  ? () => _navigate(-1)
                  : null,
            ),
            IconButton.outlined(
              tooltip: 'Nächste Woche',
              icon: const Icon(Icons.chevron_right),
              onPressed:
                  canNavigate && (_monday != null || _requestedDay != null)
                  ? () => _navigate(1)
                  : null,
            ),
            OutlinedButton(
              onPressed: canNavigate ? () => _navigate(null) : null,
              child: const Text('Diese Woche'),
            ),
            FilledButton.icon(
              onPressed: _canPlaceRecipe ? _shopping : null,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('In den Einkaufswagen'),
            ),
          ],
        ),
        if (_loading || _busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: canNavigate ? _load : null,
            child: const Text('Erneut laden'),
          ),
        ],
        if (state.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(state),
          ),
        if (queueError && objects(_queue['items']).isNotEmpty)
          OutlinedButton(
            onPressed: _ready ? _discard : null,
            child: const Text('Vormerkungen verwerfen'),
          ),
        if (_undo case (name: final String name, id: final String id))
          Card(
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(child: Text('„$name“ entfernt')),
                TweenAnimationBuilder<double>(
                  key: ValueKey(id),
                  tween: Tween(begin: 1, end: 0),
                  duration: const Duration(seconds: 5),
                  builder: (context, value, _) => SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _ready ? () => _undoRemoval(id) : null,
                  child: const Text('Rückgängig'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _placeholderList(String monday) => ExpansionTile(
    title: const Text('Platzhalter'),
    children: [
      for (final entry in _placeholders.entries)
        _draggable(
          _WeekEntry('library', {'placeholder': entry.key}, placeholder: true),
          monday,
          _ready,
          ListTile(
            leading: Text(entry.value.$2),
            title: Text(entry.value.$1),
            trailing: IconButton(
              tooltip: '${entry.value.$1} zur Wochenablage hinzufügen',
              onPressed: _ready
                  ? () => _move(
                      _WeekEntry('library', {
                        'placeholder': entry.key,
                      }, placeholder: true),
                      'shelf',
                      monday,
                    )
                  : null,
              icon: const Icon(Icons.add),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final monday = _monday;
    return RefreshIndicator(
      onRefresh: () async {
        if (_busy || _loading) return;
        await widget.onSync?.call();
        if (mounted) await _load();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_selected != null) setState(() => _selected = null);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _toolbar(),
            if (monday != null) ...[
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Kachel halten und wischen. Tag ↑ entfernen, ↓ Ablage. Ablage ↑ zum angezeigten Tag, ↓ entfernen.',
                ),
              ),
              _days(monday),
              _section('Ablage für diese Woche', 'shelf', monday),
              _placeholderList(monday),
              _WeekLists(
                key: ValueKey(monday),
                api: widget.api,
                canAdd: _canPlaceRecipe,
                shelfIds: {
                  for (final item in _recipes['shelf'] ?? <Json>[])
                    text(item['id']),
                },
                onOpen: (recipe) => _openRecipe(recipe, false),
                onAdd: (recipe) =>
                    _move(_WeekEntry('library', recipe), 'shelf', monday),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef _WeekDrag = ({_WeekEntry item, String monday});

class _MouseWeekDrag extends Draggable<_WeekDrag> {
  const _MouseWeekDrag({
    required super.data,
    required super.feedback,
    required super.child,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {PointerDeviceKind.mouse},
    allowedButtonsFilter: (buttons) => buttons == kPrimaryMouseButton,
  )..onStart = onStart;
}

class _WeekLists extends StatefulWidget {
  const _WeekLists({
    super.key,
    required this.api,
    required this.canAdd,
    required this.shelfIds,
    required this.onOpen,
    required this.onAdd,
  });

  final RezeptgartenApi api;
  final bool canAdd;
  final Set<String> shelfIds;
  final Future<void> Function(Json) onOpen;
  final Future<void> Function(Json) onAdd;

  @override
  State<_WeekLists> createState() => _WeekListsState();
}

class _WeekListsState extends State<_WeekLists> {
  Future<dynamic>? _collections;

  void _load() {
    setState(() {
      _collections = widget.api.get('/api/collections');
    });
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Lokale Listen'),
    onExpansionChanged: (expanded) {
      if (expanded && _collections == null) _load();
    },
    children: [
      if (_collections != null)
        FutureBuilder<dynamic>(
          future: _collections,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: _load,
                child: Text('${snapshot.error} · Erneut laden'),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final lists = objects((snapshot.data as Json)['items'])
                .where((item) => item['kind'] == 'local');
            if (lists.isEmpty) {
              return const ListTile(
                title: Text('Noch keine lokalen Listen vorhanden.'),
              );
            }
            return Column(
              children: [
                for (final list in lists)
                  _WeekList(
                    key: ValueKey(list['id']),
                    list: list,
                    api: widget.api,
                    canAdd: widget.canAdd,
                    shelfIds: widget.shelfIds,
                    onOpen: widget.onOpen,
                    onAdd: widget.onAdd,
                  ),
              ],
            );
          },
        ),
    ],
  );
}

class _WeekList extends StatefulWidget {
  const _WeekList({
    super.key,
    required this.list,
    required this.api,
    required this.canAdd,
    required this.shelfIds,
    required this.onOpen,
    required this.onAdd,
  });
  final Json list;
  final RezeptgartenApi api;
  final bool canAdd;
  final Set<String> shelfIds;
  final Future<void> Function(Json) onOpen;
  final Future<void> Function(Json) onAdd;

  @override
  State<_WeekList> createState() => _WeekListState();
}

class _WeekListState extends State<_WeekList> {
  final _items = <Json>[];
  bool _loading = false;
  bool _requested = false;
  String? _error;
  int _total = 0;

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _requested = true;
      _error = null;
    });
    try {
      final uri = Uri(
        path: '/api/recipes',
        queryParameters: {
          'collection': text(widget.list['id']),
          'limit': '100',
          'offset': '${_items.length}',
        },
      );
      final result = await widget.api.get(uri.toString()) as Json;
      if (!mounted) return;
      setState(() {
        _items.addAll(objects(result['items']));
        _total = result['total'] as int;
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(text(widget.list['name'])),
    onExpansionChanged: (expanded) {
      if (expanded && !_requested) unawaited(_load());
    },
    children: [
      for (final recipe in _items)
        ListTile(
          title: Text(text(recipe['name'])),
          onTap: () => widget.onOpen(recipe),
          trailing: IconButton(
            tooltip: '${recipe['name']} zur Wochenablage hinzufügen',
            onPressed: widget.canAdd && !widget.shelfIds.contains(recipe['id'])
                ? () => widget.onAdd(recipe)
                : null,
            icon: Icon(
              widget.shelfIds.contains(recipe['id']) ? Icons.check : Icons.add,
            ),
          ),
        ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Erneut laden')),
      ] else if (!_loading && _items.length < _total)
        TextButton(
          onPressed: _load,
          child: const Text('Weitere Rezepte anzeigen'),
        )
      else if (_requested && !_loading && _items.isEmpty)
        const ListTile(title: Text('Diese Liste enthält noch keine Rezepte.')),
    ],
  );
}
