import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'calendar_badge.dart';
import 'expandable_list_card.dart';
import 'recipe_card.dart';
import 'spacing.dart';

const _placeholders = {
  'restaurant': ('Im Restaurant essen', '🍴'),
  'fastfood': ('Fastfood', '🍔'),
  'sushi': ('Sushi', '🍣'),
  'pasta': ('Pasta mit Pesto', '🍝'),
  'abendbrot': ('Abendbrot', '🍞'),
  'resteessen': ('Resteessen', '🍲'),
};
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
    this.onCartChanged,
    this.statusChanged,
    this.refreshCount = 0,
    this.onSync,
    this.active = true,
  });

  final RezeptgartenApi api;
  final Future<void> Function(Json recipe, bool calendar) openRecipe;
  final ValueChanged<int> cartCountChanged;
  final VoidCallback? onCartChanged;
  final ValueChanged<Json>? statusChanged;
  final int refreshCount;
  final Future<void> Function()? onSync;
  final bool active;

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
  bool _queueReady = false;
  bool _busy = false;
  bool _openingRecipe = false;
  int _request = 0;
  int _visibleDay = 0;
  bool _dayChanged = false;
  Timer? _poll;
  Timer? _undoExpiry;
  ({String name, String id})? _undo;
  String? _selected;
  final _gestureDistance = ValueNotifier(Offset.zero);
  Future<void>? _enrichment;
  Completer<void>? _detailClosed;

  String? get _monday =>
      objects(_week?['days']).firstOrNull?['date'] as String?;
  bool get _ready => !_loading && _queueReady && !_busy && _monday != null;
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
    if (!widget.active) {
      _selected = null;
      _gestureDistance.value = Offset.zero;
    }
    if (widget.refreshCount != oldWidget.refreshCount && !_busy) {
      unawaited(_load(showPrevious: true));
    }
  }

  @override
  void dispose() {
    _detailClosed?.complete();
    _detailClosed = null;
    _daysController.dispose();
    _gestureDistance.dispose();
    _poll?.cancel();
    _undoExpiry?.cancel();
    super.dispose();
  }

  Future<void> _restoreDay() async {
    if (widget.api.usesTestData) return;
    try {
      final saved = await _preferences.invokeMethod<int>('weekDay');
      if (mounted && !_dayChanged && saved != null && saved >= 0 && saved < 7) {
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
      final count = _calendarDates().length;
      if (count > 0) _daysController.jumpToPage(min(_visibleDay, count - 1));
    });
  }

  Future<void> _selectDay(int index, {bool force = false}) async {
    if (_visibleDay == index && !force) return;
    _dayChanged = true;
    _visibleDay = index;
    if (widget.api.usesTestData) return;
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

  Future<void> _load({
    bool showPrevious = false,
    bool showToday = false,
  }) async {
    final request = ++_request;
    final day = _requestedDay;
    final path = day == null
        ? '/api/calendar/week'
        : '/api/calendar/week?day=$day';
    setState(() {
      _loading = true;
      _queueReady = false;
      _error = null;
      _selected = null;
      if (!showPrevious) {
        _week = null;
        _queue = {};
        _recipes = {};
      }
    });
    _restorePage();
    final weekRead = widget.api.get(path);
    final statusRead = _status().then<Json?>(
      (status) {
        if (mounted && request == _request) _cartCount(status);
        return status;
      },
      onError: (Object error) {
        if (mounted && request == _request && _error == null) {
          setState(() => _error = error.toString());
        }
        return null;
      },
    );
    try {
      final week = await weekRead as Json;
      if (!mounted || request != _request) return;
      setState(() {
        _week = week;
        _recipes = _project(week, _queue);
        _loading = false;
      });
      if (showToday) {
        final index = objects(week['days'])
            .indexWhere((day) => day['date'] == week['today']);
        if (index >= 0) {
          unawaited(_selectDay(index, force: true));
        }
      }
      _restorePage();
      final status = await statusRead;
      if (!mounted || request != _request || status == null) return;
      final queue = status['calendar_queue'];
      setState(() {
        _queue = queue is Json ? queue : {};
        _recipes = _project(week, _queue);
        _queueReady = true;
      });
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
    if (!widget.active ||
        _busy ||
        _loading ||
        (!_queueReady && _error == null) ||
        _openingRecipe ||
        _week == null) {
      return;
    }
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
      if (!_queueReady ||
          (queue is Json && jsonEncode(queue) != jsonEncode(_queue))) {
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
          !_loading) {
        await _detailClosed?.future;
        if (!mounted || request != _request || _busy || _loading) return;
        final batch = ids.skip(index).take(8).toList();
        index += batch.length;
        final uri = Uri(
          path: '/api/calendar/badges',
          queryParameters: {'recipe_id': batch},
        );
        final result = await widget.api.get(uri.toString()) as Json;
        if (!mounted || request != _request || _busy || _loading) {
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
    await _detailClosed?.future;
    if (!mounted || request != _request || !_canPlaceRecipe) {
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
    if (_busy) return;
    final base = _requestedDay ?? _monday;
    if (offset == null) {
      _requestedDay = null;
    } else if (base != null) {
      _requestedDay = _dayString(
        DateTime.parse('${base}T12:00:00Z').add(Duration(days: 7 * offset)),
      );
    } else {
      return;
    }
    unawaited(_load(showToday: offset == null));
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
    final moveId = newCalendarMoveId();
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
      final added = response['added'];
      if (response['status'] == 'empty') {
        _message('In dieser Woche sind ab heute keine Rezepte eingeplant.');
      } else if (response['status'] == 'ok' && added is int && added >= 0) {
        if (added > 0) widget.onCartChanged?.call();
        _message(
          added == 0
              ? 'Die Rezepte dieser Woche stehen bereits im Einkaufswagen.'
              : '$added ${added == 1 ? 'Rezept wurde' : 'Rezepte wurden'} zum Einkaufswagen hinzugefügt.',
        );
      } else {
        throw const ApiException(
          'Das Ergebnis konnte nicht bestätigt werden. Bitte prüfe den Einkaufswagen.',
        );
      }
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

  String? _swipeTarget(_WeekEntry entry, Offset distance) {
    if (_selected != entry.identity ||
        distance.dy.abs() <= 10 ||
        distance.dy.abs() <= distance.dx.abs() * 1.3) {
      return null;
    }
    if (entry.source != 'shelf') return distance.dy > 0 ? 'shelf' : 'trash';
    if (distance.dy > 0) return 'trash';
    final days = objects(_week?['days']);
    return days.isEmpty
        ? null
        : days[min(_visibleDay, days.length - 1)]['date'] as String?;
  }

  void _finishSwipe(_WeekEntry entry, String monday, {bool commit = true}) {
    if (_selected != entry.identity) return;
    final distance = _gestureDistance.value;
    final target = _swipeTarget(entry, distance);
    _gestureDistance.value = Offset.zero;
    if (commit && target != null && _swipeArmed(distance)) {
      unawaited(_move(entry, target, monday));
    }
  }

  bool _swipeArmed(Offset distance) =>
      distance.dy < 0 ? distance.dy <= -140 : distance.dy >= 90;

  Future<void> _openRecipe(Json recipe, bool calendar) async {
    if (_busy || _openingRecipe) return;
    _openingRecipe = true;
    _detailClosed = Completer<void>();
    try {
      await widget.openRecipe(recipe, calendar);
    } finally {
      _openingRecipe = false;
      _detailClosed?.complete();
      _detailClosed = null;
    }
  }

  Widget _tile(_WeekEntry entry, String monday) {
    final enabled = entry.placeholder ? _ready : _canPlaceRecipe;
    final selected = _selected == entry.identity;
    final shelf = entry.source == 'shelf';
    final action = shelf
        ? null
        : RecipeCornerAction(
            tooltip: '${entry.name} in die Ablage',
            onPressed: enabled ? () => _move(entry, 'shelf', monday) : null,
            icon: Icons.playlist_add,
          );
    void open() {
      if (_selected != null) {
        setState(() => _selected = null);
      } else if (!entry.placeholder) {
        unawaited(_openRecipe(entry.data, true));
      }
    }

    final recipe = entry.placeholder && !shelf
        ? Stack(
            alignment: AlignmentDirectional.topEnd,
            children: [
              Card(
                child: ListTile(
                  leading: Text(_placeholders[entry.type]?.$2 ?? ''),
                  title: Text(entry.name),
                  contentPadding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.section,
                    end: 48,
                  ),
                  onTap: selected
                      ? () => setState(() => _selected = null)
                      : null,
                ),
              ),
              ?action,
            ],
          )
        : RecipeCard(
            api: widget.api,
            recipe: entry.placeholder ? {'name': entry.name} : entry.data,
            picture: entry.placeholder
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          _placeholders[entry.type]?.$2 ?? '🍽️',
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                  )
                : null,
            cornerAction: action,
            onTap: !entry.placeholder || selected ? open : null,
            compact: shelf,
          );
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    const touchDevices = {
      PointerDeviceKind.touch,
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    };
    final gestures = RawGestureDetector(
      key: ValueKey(entry.identity),
      gestures: {
        if (enabled)
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 250),
                  supportedDevices: touchDevices,
                ),
                (recognizer) {
                  recognizer.onLongPressStart = (_) {
                    _gestureDistance.value = Offset.zero;
                    setState(() => _selected = entry.identity);
                  };
                  recognizer.onLongPressMoveUpdate = (details) =>
                      _gestureDistance.value = details.offsetFromOrigin;
                  recognizer.onLongPressEnd = (_) =>
                      _finishSwipe(entry, monday);
                  recognizer.onLongPressCancel = () =>
                      _finishSwipe(entry, monday, commit: false);
                },
              ),
        if (selected && enabled)
          VerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                VerticalDragGestureRecognizer
              >(
                () => VerticalDragGestureRecognizer(
                  supportedDevices: touchDevices,
                ),
                (recognizer) {
                  recognizer.dragStartBehavior = DragStartBehavior.down;
                  recognizer.onStart = (_) =>
                      _gestureDistance.value = Offset.zero;
                  recognizer.onUpdate = (details) =>
                      _gestureDistance.value += details.delta;
                  recognizer.onEnd = (_) => _finishSwipe(entry, monday);
                  recognizer.onCancel = () =>
                      _finishSwipe(entry, monday, commit: false);
                },
              ),
      },
      child: ValueListenableBuilder(
        valueListenable: _gestureDistance,
        child: recipe,
        builder: (context, distance, child) {
          final preview = selected && enabled
              ? _swipeTarget(entry, distance)
              : null;
          final offset = preview == null || reduceMotion
              ? 0.0
              : (distance.dy * .35).clamp(-45.0, 45.0);
          return AnimatedContainer(
            duration: reduceMotion || preview != null
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, offset, 0),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? colors.primary : colors.primary.withAlpha(0),
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                child!,
                if (preview != null)
                  Positioned(
                    left: AppSpacing.related,
                    right: AppSpacing.related,
                    child: IgnorePointer(
                      child: Center(child: _swipeFeedback(preview, distance)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    return _draggable(
      entry,
      monday,
      enabled,
      shelf && enabled
          ? Semantics(
              customSemanticsActions: {
                CustomSemanticsAction(
                  label: '${entry.name} aus der Ablage entfernen',
                ): () =>
                    _move(entry, 'trash', monday),
              },
              child: gestures,
            )
          : gestures,
    );
  }

  Widget _swipeFeedback(String target, Offset distance) {
    final (icon, label) = switch (target) {
      'trash' => (Icons.delete_outline, 'Entfernen'),
      'shelf' => (Icons.move_to_inbox_outlined, 'In die Ablage'),
      _ => (Icons.today_outlined, 'Zum angezeigten Tag'),
    };
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final armed = _swipeArmed(distance);
    final foreground = target == 'trash'
        ? (armed ? colors.onError : colors.onErrorContainer)
        : (armed ? colors.onPrimary : colors.onPrimaryContainer);
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: target == 'trash'
          ? (armed ? colors.error : colors.errorContainer)
          : (armed ? colors.primary : colors.primaryContainer),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.related,
          vertical: AppSpacing.tight,
        ),
        child: Wrap(
          spacing: AppSpacing.tight,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, size: 16, color: foreground),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
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
          padding: AppSpacing.compactPanel,
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
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isToday = target == _week?['today'];
        final foreground = hovering.isNotEmpty
            ? colors.onSecondaryContainer
            : isToday
            ? colors.onPrimaryContainer
            : colors.onSurface;
        final shelfTileWidth = MediaQuery.textScalerOf(context).scale(1) > 1.25
            ? 168.0
            : 144.0;
        final content = [
          CalendarDayHeading(
            title,
            isToday: isToday,
            style: theme.textTheme.titleMedium?.copyWith(
              color: foreground,
              fontWeight: isToday ? FontWeight.w800 : null,
            ),
          ),
          if (entries.isEmpty && _queueReady)
            Text(
              target == 'shelf'
                  ? 'Rezepte hier ablegen, wenn der Tag noch offen ist.'
                  : 'Noch nichts geplant',
              style: TextStyle(color: foreground),
            ),
          if (target == 'shelf' && entries.isNotEmpty)
            ClipRect(
              clipper: const _ShelfClipper(),
              child: SingleChildScrollView(
                key: PageStorageKey('shelf-$monday'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  spacing: AppSpacing.tight,
                  children: [
                    for (final entry in entries)
                      SizedBox(
                        key: ValueKey(entry.identity),
                        width: shelfTileWidth,
                        child: _tile(entry, monday),
                      ),
                  ],
                ),
              ),
            )
          else
            for (final entry in entries) _tile(entry, monday),
        ];
        return Card(
          margin: EdgeInsets.zero,
          color: hovering.isNotEmpty
              ? colors.secondaryContainer
              : isToday
              ? colors.primaryContainer
              : null,
          child: scroll
              ? ListView.separated(
                  primary: false,
                  padding: AppSpacing.compactPanel,
                  itemCount: content.length,
                  itemBuilder: (_, index) => content[index],
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.related),
                )
              : Padding(
                  padding: AppSpacing.compactPanel,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.related,
                    children: content,
                  ),
                ),
        );
      },
    );
  }

  Widget _days(String monday) {
    final dates = _calendarDates();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave room for both controls in each card before showing all seven columns.
        const weekRowWidth = 7 * 124 + 6 * AppSpacing.item;
        if (constraints.maxWidth >= weekRowWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.item,
            children: [
              for (final (index, date) in dates.indexed)
                Expanded(
                  child: _section(calendarDayLabel(index, date), date, monday),
                ),
            ],
          );
        }
        return SizedBox(
          height: (MediaQuery.sizeOf(context).height * .46).clamp(250.0, 460.0),
          child: PageView.builder(
            controller: _daysController,
            itemCount: dates.length,
            onPageChanged: _selectDay,
            itemBuilder: (context, index) {
              final date = dates[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.item / 2,
                ),
                child: _section(
                  calendarDayLabel(index, date),
                  date,
                  monday,
                  scroll: true,
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<String> _calendarDates() {
    if (_week != null) {
      return [for (final day in objects(_week?['days'])) text(day['date'])];
    }
    final monday = DateTime.tryParse('${_requestedDay ?? ''}T12:00:00Z');
    return [
      for (var index = 0; index < 7; index++)
        monday == null ? '' : _dayString(monday.add(Duration(days: index))),
    ];
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
    final canNavigate = !_busy && (!_loading || _requestedDay != null);
    final canStep = canNavigate && (_monday != null || _requestedDay != null);
    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );
    final arrowStyle = IconButton.styleFrom(
      fixedSize: const Size.square(48),
      shape: controlShape,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.related,
      children: [
        Text('Meine Woche', style: Theme.of(context).textTheme.headlineMedium),
        Row(
          spacing: AppSpacing.related,
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 264),
                  child: Row(
                    spacing: AppSpacing.related,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            IconButton.outlined(
                              tooltip: 'Vorherige Woche',
                              style: arrowStyle,
                              onPressed: canStep ? () => _navigate(-1) : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: CalendarWeekLabel(
                                    date: _monday ?? _requestedDay,
                                    today: text(_week?['today']),
                                  ),
                                ),
                              ),
                            ),
                            IconButton.outlined(
                              tooltip: 'Nächste Woche',
                              style: arrowStyle,
                              onPressed: canStep ? () => _navigate(1) : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            shape: controlShape,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.related,
                              vertical: AppSpacing.tight,
                            ),
                          ),
                          onPressed: canNavigate ? () => _navigate(null) : null,
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Heute'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton.filled(
              tooltip: 'In den Einkaufswagen',
              style: IconButton.styleFrom(fixedSize: const Size.square(48)),
              onPressed: _canPlaceRecipe ? _shopping : null,
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
          ],
        ),
        if ((_loading && _week == null) || _busy)
          const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: canNavigate ? () => _load(showPrevious: true) : null,
            child: const Text('Erneut laden'),
          ),
        ],
        if (state.isNotEmpty) Text(state),
        if (queueError && objects(_queue['items']).isNotEmpty)
          OutlinedButton(
            onPressed: _ready ? _discard : null,
            child: const Text('Vormerkungen verwerfen'),
          ),
        if (_undo case (name: final String name, id: final String id))
          Card(
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.item),
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
      ],
    );
  }

  Widget _placeholderList(String monday) => ExpandableListCard(
    title: 'Platzhalter',
    body: Padding(
      padding: AppSpacing.compactPanel,
      child: Column(
        spacing: AppSpacing.related,
        children: [
          if (_week != null)
            for (final entry in _placeholders.entries)
              _draggable(
                _WeekEntry('library', {
                  'placeholder': entry.key,
                }, placeholder: true),
                monday,
                _ready,
                CompactRecipeTile(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  leading: Text(entry.value.$2),
                  title: entry.value.$1,
                  actionLabel: '${entry.value.$1} zur Wochenablage hinzufügen',
                  onAction: _ready
                      ? () => _move(
                          _WeekEntry('library', {
                            'placeholder': entry.key,
                          }, placeholder: true),
                          'shelf',
                          monday,
                        )
                      : null,
                  actionIcon: Icons.add,
                ),
              ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final monday = _monday;
    final displayedMonday = monday ?? _requestedDay ?? '';
    return RefreshIndicator(
      onRefresh: () async {
        if (_busy || _loading) return;
        await widget.onSync?.call();
        if (mounted) await _load(showPrevious: true);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (_selected != null) setState(() => _selected = null);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.page,
          children: [
            _toolbar(),
            const SizedBox(height: AppSpacing.section),
            _days(displayedMonday),
            const SizedBox(height: AppSpacing.section),
            _section('Ablage für diese Woche', 'shelf', displayedMonday),
            const SizedBox(height: AppSpacing.section),
            _placeholderList(displayedMonday),
            if (monday != null) ...[
              const SizedBox(height: AppSpacing.section),
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

class _ShelfClipper extends CustomClipper<Rect> {
  const _ShelfClipper();

  // Keep horizontal overflow hidden while the selected pill moves vertically.
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, -48, size.width, size.height + 96);

  @override
  bool shouldReclip(_ShelfClipper oldClipper) => false;
}

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
  Widget build(BuildContext context) => ExpandableListCard(
    title: 'Lokale Listen',
    onExpansionChanged: (expanded) {
      if (expanded && _collections == null) _load();
    },
    body: Padding(
      padding: AppSpacing.compactPanel,
      child: FutureBuilder<dynamic>(
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
            spacing: AppSpacing.related,
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
    ),
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
          'limit': '24',
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
  Widget build(BuildContext context) => ExpandableListCard(
    title: text(widget.list['name']),
    leading: switch (widget.list['icon']) {
      final String symbol => ExcludeSemantics(child: Text(symbol)),
      _ => const Icon(Icons.list_alt),
    },
    onExpansionChanged: (expanded) {
      if (expanded && !_requested) unawaited(_load());
    },
    body: Padding(
      padding: AppSpacing.compactPanel,
      child: Column(
        spacing: AppSpacing.related,
        children: [
          for (final recipe in _items)
            CompactRecipeTile(
              key: ValueKey(recipe['id']),
              title: text(recipe['name'], 'Rezept'),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              leading: ClipOval(
                child: SizedBox.square(
                  dimension: 40,
                  child: RecipeImage(
                    api: widget.api,
                    filename: recipe['image_file'],
                  ),
                ),
              ),
              onTap: () => widget.onOpen(recipe),
              actionLabel: widget.shelfIds.contains(recipe['id'])
                  ? '${recipe['name']} bereits in der Wochenablage'
                  : '${recipe['name']} zur Wochenablage hinzufügen',
              onAction: widget.canAdd && !widget.shelfIds.contains(recipe['id'])
                  ? () => widget.onAdd(recipe)
                  : null,
              actionIcon: widget.shelfIds.contains(recipe['id'])
                  ? Icons.check
                  : Icons.add,
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
            const ListTile(
              title: Text('Diese Liste enthält noch keine Rezepte.'),
            ),
        ],
      ),
    ),
  );
}
