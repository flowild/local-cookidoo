import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'spacing.dart';
import 'appearance.dart';
import 'ingredient_icon.dart';
import 'pantry_view.dart';
import 'pill_widgets.dart';
import 'recipe_card.dart';
import 'recipe_detail.dart';
import 'recipe_library.dart';
import 'settings_view.dart';
import 'symbol_field.dart';
import 'week_view.dart';
import 'telegram_service.dart';
import 'connection.dart';

typedef _CartRow = ({Json entry, Json row, int? position, String category});
typedef _CartCheck = ({bool owned, int revision});

class RezeptgartenHome extends StatefulWidget {
  const RezeptgartenHome({
    super.key,
    required this.api,
    required this.appearance,
    this.telegram,
    this.connection,
    this.onDebugModeChanged,
  });

  final RezeptgartenApi api;
  final AppearanceController appearance;
  final TelegramService? telegram;
  final ConnectionController? connection;
  final ValueChanged<bool>? onDebugModeChanged;

  @override
  State<RezeptgartenHome> createState() => _RezeptgartenHomeState();
}

class _RezeptgartenHomeState extends State<RezeptgartenHome>
    with WidgetsBindingObserver {
  static const shortRead = Duration(milliseconds: 2500);
  static const areas = [
    'Übersicht',
    'Listen',
    'Rezepte',
    'Woche',
    'Einkauf',
    'Vorrat',
  ];
  static const icons = [
    Icons.home_outlined,
    Icons.layers_outlined,
    Icons.menu_book,
    Icons.calendar_today_outlined,
    Icons.shopping_cart_outlined,
    Icons.kitchen_outlined,
  ];
  static const selectedIcons = [
    Icons.home,
    Icons.layers,
    Icons.menu_book,
    Icons.calendar_today,
    Icons.shopping_cart,
    Icons.kitchen,
  ];
  RezeptgartenApi get api => widget.api;
  int area = 3;
  late final _navigationIndex = ValueNotifier<int>(area);
  int? serverCartCount;
  bool busy = false;
  bool syncPending = false;
  bool? connected;
  bool syncRunning = false;
  bool syncPollFailed = false;
  int syncGeneration = 0;
  bool startupSyncAttempted = false;
  bool wasBackgrounded = false;
  Timer? syncPoll;
  static const _retainedAreas = {1, 2, 3, 5};
  final _dirtyAreas = <int>{};
  final _pullingAreas = <int>{};
  int _recipeRevision = 0;
  int _cartRevision = 0;
  int _overviewRevision = 0;
  final _areaRefreshes = List.filled(areas.length, 0);
  int _session = 0;
  var _pagerKey = GlobalKey<_SectionPagerState>();
  ConnectionMode? _lastMode;
  final pantryExpanded = <int>{};
  final recipeSearch = FocusNode();
  final cartItem = TextEditingController();
  final _areaData = <int, Future<dynamic>>{};
  Json? _featured;
  Json? _overviewStats;
  List<Json> _overviewPreviews = [];
  Json? _lastCart;
  final _pendingCartChecks = <String, bool>{};
  final _savedCartChecks = <String, _CartCheck>{};

  bool get _local =>
      widget.connection == null ||
      widget.connection!.mode == ConnectionMode.local;

  bool get _available =>
      _local || widget.connection?.mode == ConnectionMode.telegram;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastMode = widget.connection?.mode;
    widget.connection?.addListener(_connectionChanged);
    if (_local) unawaited(_startupSync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed) {
      final syncOnResume = wasBackgrounded;
      wasBackgrounded = false;
      unawaited(_resume(syncOnResume));
    }
  }

  Future<void> _resume(bool syncOnResume) async {
    if (syncOnResume) startupSyncAttempted = false;
    await widget.connection?.refresh();
    if (mounted && syncOnResume && _local) await _startupSync();
  }

  void _connectionChanged() {
    if (!mounted) return;
    setState(() {
      final mode = widget.connection?.mode;
      if (mode == ConnectionMode.offline && area != 3 && area != 4) {
        area = 3;
        _navigationIndex.value = area;
      }
      if (_lastMode != mode) {
        _lastMode = mode;
        _resetSession();
      }
      serverCartCount = null;
      _areaRefreshes[area]++;
      _areaData[area] = _load(area);
    });
    if (_local) unawaited(_startupSync());
  }

  void _resetSession() {
    _navigationIndex.value = area;
    _session++;
    syncGeneration++;
    syncPoll?.cancel();
    startupSyncAttempted = false;
    syncRunning = false;
    syncPending = false;
    _pullingAreas.clear();
    _pagerKey = GlobalKey<_SectionPagerState>();
    _areaData.clear();
    _featured = null;
    _overviewStats = null;
    _overviewPreviews = [];
    _lastCart = null;
    _pendingCartChecks.clear();
    _savedCartChecks.clear();
    _dirtyAreas.clear();
    pantryExpanded.clear();
    cartItem.clear();
    api.clearImageCache();
  }

  Future<void> _startupSync() async {
    if (startupSyncAttempted || !_local) return;
    startupSyncAttempted = true;
    final session = _session;
    try {
      final status = await api.get('/api/status', timeout: shortRead) as Json;
      if (!mounted || session != _session) return;
      if (!_local) {
        startupSyncAttempted = false;
        return;
      }
      _adoptStatus(status);
      if (widget.connection != null) unawaited(api.warmRecipeImages());
      if (status['connected'] == true) await _beginSync(notify: false);
    } on Exception {
      if (session == _session) startupSyncAttempted = false;
      // Normal view loading reports connection errors.
    }
  }

  Future<void> _networkPermission() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Heimnetz erkennen'),
        content: const Text(
          'Android benötigt die Standortberechtigung, damit Rezeptmix das WLAN ThomasWlan erkennen kann.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Später'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Weiter'),
          ),
        ],
      ),
    );
    if (approved == true) await widget.connection?.requestPermission();
  }

  Future<dynamic> _load(int index) async => !_available
      ? null
      : switch (index) {
          0 => _loadOverview(),
          4 => _loadCart(),
          _ => null,
        };

  Future<void> _loadOverview() async {
    final session = _session;
    final revision = ++_overviewRevision;
    Future<void> read(String path, void Function(Json) apply) async {
      final result = await api.get(path, timeout: shortRead) as Json;
      if (mounted && session == _session && revision == _overviewRevision) {
        apply(result);
      }
    }

    await Future.wait<void>([
      read('/api/featured-recipe', (result) {
        setState(() => _featured = result);
      }),
      read('/api/status', (status) {
        _adoptStatus(status);
        setState(() => _overviewStats = status['stats'] as Json?);
      }),
      read('/api/recipes?limit=8', (result) {
        setState(() => _overviewPreviews = objects(result['items']));
      }),
    ]);
  }

  Future<Json> _loadCart() async {
    final session = _session;
    final revision = ++_cartRevision;
    final cart = await api.get('/api/cart', timeout: shortRead) as Json;
    if (mounted && session == _session && revision == _cartRevision) {
      _lastCart = cart;
      final count = objects(cart['items'])
          .where((item) => item['kind'] == 'recipe')
          .length;
      if (serverCartCount != count) {
        setState(() => serverCartCount = count);
      }
    }
    return cart;
  }

  _CartCheck _cartCheck(String path, Json row) {
    final saved = _savedCartChecks[path];
    final revision = row['owned_revision'] as int? ?? 0;
    return saved != null && saved.revision >= revision
        ? saved
        : (owned: row['owned'] == true, revision: revision);
  }

  void _toggleCartCheck(String path, Json row, bool owned) {
    final saving = _pendingCartChecks.containsKey(path);
    setState(() => _pendingCartChecks[path] = owned);
    if (!saving) {
      unawaited(_saveCartCheck(path, _cartCheck(path, row), _session));
    }
  }

  Future<void> _saveCartCheck(
    String path,
    _CartCheck confirmed,
    int session,
  ) async {
    while (mounted && session == _session) {
      final requested = _pendingCartChecks[path]!;
      String? message;
      var failed = false;
      try {
        final result = await api.write('PUT', path, {
          'owned': requested,
          'owned_revision': confirmed.revision,
        }) as Json;
        confirmed = (
          owned: result['owned'] as bool? ?? requested,
          revision: result['owned_revision'] as int? ?? confirmed.revision,
        );
        if (!requested && confirmed.owned) {
          message = 'Der Eintrag wurde zwischenzeitlich abgehakt.';
        }
      } on Exception catch (error) {
        failed = true;
        message = error.toString();
      }
      if (!mounted || session != _session) return;
      final finished = failed || _pendingCartChecks[path] == requested;
      setState(() {
        if (!failed) _savedCartChecks[path] = confirmed;
        if (finished) _pendingCartChecks.remove(path);
      });
      if (finished) {
        if (message != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
        if (failed) {
          if (area == 4) {
            unawaited(_refresh());
          } else {
            _dirtyAreas.add(4);
          }
        }
        return;
      }
    }
  }

  void _adoptStatus(Json status, {bool authoritative = false}) {
    final online = status['connected'] as bool?;
    final reportedRunning =
        status['sync'] is Json && status['sync']['running'] == true;
    // Views can complete an older status request after a new sync has begun.
    // Only the monitor's fresh request may conclude a known running sync.
    final running = syncRunning && !authoritative ? true : reportedRunning;
    if (connected != online || syncRunning != running) {
      setState(() {
        connected = online;
        syncRunning = running;
      });
    }
    if (running && syncPoll?.isActive != true) _monitorSync();
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsView(
          api: api,
          appearance: widget.appearance,
          telegram: widget.telegram,
          connection: widget.connection,
          onSync: _syncFromPull,
          onDebugModeChanged: widget.onDebugModeChanged,
          onAccountChanged: () {
            if (!mounted) return;
            setState(() {
              _resetSession();
              serverCartCount = null;
              _areaData[area] = _load(area);
            });
          },
        ),
      ),
    );
    if (mounted && _dirtyAreas.contains(area)) await _refresh();
  }

  Future<void> _beginSync({bool notify = true}) async {
    if (!_available || syncPending || syncRunning || busy) return;
    final session = _session;
    setState(() {
      syncPending = true;
      syncGeneration++;
    });
    String notice;
    try {
      final result = await api.write('POST', '/api/sync') as Json;
      notice = result['started'] == true
          ? 'Synchronisierung gestartet.'
          : 'Die Synchronisierung läuft bereits.';
      if (mounted && session == _session) {
        setState(() {
          syncRunning = true;
          syncPollFailed = false;
        });
        _monitorSync();
      }
    } on Exception catch (error) {
      notice = error.toString();
    }
    if (!mounted || session != _session) return;
    setState(() => syncPending = false);
    if (notify || !syncRunning) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> _pullRefresh() async {
    final requestedArea = area;
    final session = _session;
    await _syncFromPull();
    if (!mounted || session != _session) return;
    if (requestedArea == area) {
      await _refresh();
    } else {
      _dirtyAreas.add(requestedArea);
    }
  }

  Future<void> _syncFromPull() async {
    final session = _session;
    final pullArea = ModalRoute.of(context)?.isCurrent == true ? area : null;
    if (pullArea != null) _pullingAreas.add(pullArea);
    try {
      await _beginSync();
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (mounted &&
          session == _session &&
          _available &&
          (syncPending || syncRunning) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      if (session == _session && pullArea != null) {
        _pullingAreas.remove(pullArea);
      }
    }
  }

  void _monitorSync() {
    syncPoll?.cancel();
    final generation = syncGeneration;
    syncPoll = Timer(const Duration(seconds: 3), () async {
      try {
        final result = await api.get('/api/status', timeout: shortRead) as Json;
        if (!mounted || generation != syncGeneration) return;
        syncPollFailed = false;
        final wasRunning = syncRunning;
        _adoptStatus(result, authoritative: true);
        final last = result['last_result'];
        if (wasRunning &&
            !syncRunning &&
            last is Json &&
            last['phase'] == 'error') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text(last['message'], 'Abgleich fehlgeschlagen.')),
            ),
          );
        }
        if (wasRunning && !syncRunning) {
          if (_local && widget.connection != null) {
            unawaited(api.warmRecipeImages(afterCurrent: true));
          }
          _recipeRevision++;
          _dirtyAreas.addAll([0, 1, 2, 3, 4, 5]);
          // A section's pull handler already reloads it after the sync.
          _dirtyAreas.removeAll(_pullingAreas);
          if (_dirtyAreas.contains(area) &&
              ModalRoute.of(context)?.isCurrent == true) {
            await _refresh();
          }
        }
      } on Exception {
        if (mounted && generation == syncGeneration) {
          if (_available && syncRunning) {
            if (!syncPollFailed) {
              syncPollFailed = true;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Der Abgleichstatus ist gerade nicht erreichbar und wird erneut geprüft.',
                  ),
                ),
              );
            }
            _monitorSync();
          } else {
            setState(() {
              syncRunning = false;
              connected = null;
            });
          }
        }
      }
    });
  }

  bool _canOpen(int index) =>
      !busy &&
      index >= 0 &&
      index < areas.length &&
      (_available || index == 3 || index == 4);

  void _open(int index) {
    if (!_canOpen(index) || area == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => area = index);
    if (_available && _dirtyAreas.contains(index)) unawaited(_refresh());
  }

  Future<void> _navigate(int index) async {
    if (!_canOpen(index)) return;
    await _pagerKey.currentState?.goTo(index);
  }

  Future<void> _refresh() async {
    if (busy) return;
    _dirtyAreas.remove(area);
    if (_retainedAreas.contains(area)) {
      setState(() {
        _areaRefreshes[area]++;
      });
      return;
    }
    final updated = _load(area);
    setState(() {
      _areaData[area] = updated;
    });
    try {
      await updated;
    } on Exception {
      // The view displays the load error.
    }
  }

  Future<bool> _mutate(
    String method,
    String path, [
    Json? body,
    String? success,
  ]) async {
    if (busy) return false;
    setState(() => busy = true);
    String? message = success;
    var saved = false;
    try {
      final result = await api.write(method, path, body);
      saved = true;
      if (result is Json && result['message'] is String) {
        message = result['message'] as String;
      }
    } on Exception catch (error) {
      message = error.toString();
    }
    if (!mounted) return saved;
    final updated = _load(area);
    setState(() {
      _areaData[area] = updated;
    });
    try {
      await updated;
    } on Exception {
      // The view displays the load error.
    }
    if (!mounted) return saved;
    setState(() => busy = false);
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    return saved;
  }

  Future<void> _addCartItem() async {
    if (busy) return;
    final session = _session;
    Future<dynamic>? pantry;
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        void submit() {
          final draft = cartItem.text.trim();
          if (draft.isNotEmpty && draft.runes.length <= 100) {
            Navigator.pop(context, draft);
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: AppSpacing.panel,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppSpacing.item,
                children: [
                  Text(
                    'Artikel hinzufügen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  TextField(
                    controller: cartItem,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Artikel',
                      counterText: '',
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  FutureBuilder<dynamic>(
                    future: pantry ??= api.get(
                      '/api/pantry',
                      timeout: const Duration(seconds: 3),
                    ),
                    builder: (context, snapshot) {
                      final data = snapshot.data;
                      if (data is! Json) return const SizedBox.shrink();
                      return _cartItemSuggestions(objects(data['items']));
                    },
                  ),
                  FilledButton(
                    onPressed: submit,
                    child: const Text('Hinzufügen'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (name == null || !mounted || session != _session || !_available) return;
    if (await _mutate('POST', '/api/cart/items', {'name': name}) && mounted) {
      cartItem.clear();
    }
  }

  Widget _cartItemSuggestions(List<Json> items) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: cartItem,
        builder: (context, value, _) {
          final draft = value.text.trim();
          if (draft.isEmpty) return const SizedBox.shrink();
          final query = draft.toLowerCase();
          final seen = <String>{};
          final matches = items
              .where((item) {
                final name = text(item['name']);
                final key = name.toLowerCase();
                return key.contains(query) && name != draft && seen.add(key);
              })
              .take(6)
              .toList();
          if (matches.isEmpty) return const SizedBox.shrink();
          return Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.tight,
            children: [
              for (final item in matches)
                ActionChip(
                  avatar: IngredientIcon(
                    text(item['name']),
                    selected: item['icon'],
                  ),
                  label: Text(text(item['name'])),
                  onPressed: () {
                    final name = text(item['name']);
                    cartItem.value = TextEditingValue(
                      text: name,
                      selection: TextSelection.collapsed(offset: name.length),
                    );
                  },
                ),
            ],
          );
        },
      );

  @override
  void dispose() {
    _navigationIndex.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.connection?.removeListener(_connectionChanged);
    syncPoll?.cancel();
    recipeSearch.dispose();
    cartItem.dispose();
    super.dispose();
  }

  Future<void> _recipe(Json recipe, {bool calendar = false}) async {
    if (recipe['id'] is! String) return;
    final session = _session;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetail(
          api: api,
          preview: recipe,
          calendar: calendar,
          onSync: _syncFromPull,
          onRecipeCardsChanged: () {
            if (session != _session) return;
            _recipeRevision++;
            _dirtyAreas.addAll([0, 1, 2, 3]);
          },
          onWeekChanged: () {
            if (session == _session) _dirtyAreas.add(3);
          },
          onCartChanged: () {
            if (session == _session) unawaited(_cartAdded(session));
          },
        ),
      ),
    );
    if (mounted &&
        session == _session &&
        ModalRoute.of(context)?.isCurrent == true &&
        _dirtyAreas.contains(area)) {
      await _refresh();
    }
  }

  Future<void> _cartAdded(int session) async {
    _dirtyAreas.add(4);
    final revision = ++_cartRevision;
    try {
      final status = await api.get('/api/status', timeout: shortRead) as Json;
      final count = status['cart_recipe_count'];
      if (mounted &&
          session == _session &&
          revision == _cartRevision &&
          count is int) {
        setState(() => serverCartCount = count);
      }
    } on Exception {
      // The add succeeded. The next cart read reconciles the count.
    }
  }

  Widget _heading(String title) =>
      Text(title, style: Theme.of(context).textTheme.headlineMedium);

  Widget _section(String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: AppSpacing.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          ...children,
        ],
      ),
    ),
  );

  Future<bool> _confirm(String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  List<Widget> _cart(Json cart) {
    final items = objects(cart['items']);
    final recipes = items.where((item) => item['kind'] == 'recipe').toList();
    final editable = !busy && cart['transferring'] != true;
    const statusLabels = {
      'processing': 'Wird übertragen',
      'done': 'Übertragen',
      'existing': 'Bereits in Cookidoo',
      'uncertain': 'Übertragung ungeklärt',
    };
    String entryPath(Json item) =>
        '/api/cart/${Uri.encodeComponent(text(item['id']))}';
    String checkPath(_CartRow item) =>
        '${entryPath(item.entry)}/${item.position == null ? 'owned' : 'ingredients/${item.position}'}';
    bool isSavedChecked(_CartRow item) =>
        _cartCheck(checkPath(item), item.row).owned;
    bool entrySaving(Json item) => _pendingCartChecks.keys.any(
      (path) => path.startsWith('${entryPath(item)}/'),
    );
    String removeLabel(Json item) =>
        '${text((item['data'] as Json)['name'])} entfernen';

    Widget remove(Json item) => IconButton(
      tooltip: removeLabel(item),
      onPressed: editable && !entrySaving(item)
          ? () => _mutate('DELETE', entryPath(item))
          : null,
      icon: const Icon(Icons.delete_outline),
    );

    List<Widget> status(Json item) => [
      if (statusLabels[item['status']] case final String label)
        Text(
          label,
          style: item['status'] == 'uncertain'
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
      if (item['status'] == 'uncertain') ...[
        const Text('Bitte prüfe den Eintrag in Cookidoo.'),
        ActionPillGrid(
          minColumnWidth: 164,
          children: [
            for (final (value, label) in [
              ('done', 'Dort vorhanden'),
              ('pending', 'Dort nicht vorhanden'),
            ])
              OutlinedButton(
                style: ActionPillGrid.buttonStyle,
                onPressed: editable
                    ? () async {
                        if (await _confirm(
                              'Hast du diesen Eintrag in Cookidoo geprüft?',
                              label,
                            ) &&
                            mounted) {
                          await _mutate('POST', '${entryPath(item)}/resolve', {
                            'status': value,
                          });
                        }
                      }
                    : null,
                child: Text(label),
              ),
          ],
        ),
      ],
    ];
    final rows = <_CartRow>[];
    for (final item in items) {
      final details = item['data'] as Json;
      if (item['kind'] == 'additional' && details['is_water'] != true) {
        rows.add((
          entry: item,
          row: details,
          position: null,
          category: text(details['category'], 'Sonstiges'),
        ));
      }
      for (final (position, ingredient) in objects(
        details['ingredients'],
      ).indexed) {
        if (ingredient['in_pantry'] == true || ingredient['is_water'] == true) {
          continue;
        }
        rows.add((
          entry: item,
          row: ingredient,
          position: position,
          category: text(ingredient['category'], 'Sonstiges'),
        ));
      }
    }
    rows.sort((a, b) {
      int rank(String name) => switch (name) {
        'Weitere Artikel' => 2,
        'Sonstiges' => 1,
        _ => 0,
      };
      final order = rank(a.category).compareTo(rank(b.category));
      if (order != 0) return order;
      final group = a.category.toLowerCase().compareTo(
        b.category.toLowerCase(),
      );
      return group == 0
          ? text(a.row['name'] ?? a.row['text'])
                .compareTo(text(b.row['name'] ?? b.row['text']))
          : group;
    });

    Widget shoppingRow(_CartRow item) {
      final entry = item.entry;
      final isRecipe = item.position != null;
      final path = checkPath(item);
      final checked = _pendingCartChecks[path] ?? isSavedChecked(item);
      final canCheck = editable && entry['status'] == 'pending';
      void toggle(bool? value) {
        if (value != null) _toggleCartCheck(path, item.row, value);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: MergeSemantics(
                    child: InkWell(
                      excludeFromSemantics: true,
                      onTap: canCheck ? () => toggle(!checked) : null,
                      borderRadius: BorderRadius.circular(AppSpacing.item),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Checkbox(
                              value: checked,
                              visualDensity: VisualDensity.compact,
                              onChanged: canCheck ? toggle : null,
                            ),
                            IngredientIcon(
                              text(item.row['name'] ?? item.row['text']),
                              category: item.category,
                              selected: item.row['icon'],
                            ),
                            const SizedBox(width: AppSpacing.related),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    text(item.row['text'] ?? item.row['name']),
                                  ),
                                  if (isRecipe)
                                    Text(
                                      text((entry['data'] as Json)['name']),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!isRecipe) remove(entry),
            ],
          ),
          if (!isRecipe) ...status(entry),
        ],
      );
    }

    Widget cartPanel(String title, Widget content) {
      final theme = Theme.of(context);
      return DecoratedSliver(
        decoration: ShapeDecoration(
          color: theme.cardTheme.color ?? theme.colorScheme.surfaceContainerLow,
          shape:
              theme.cardTheme.shape ??
              const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(24)),
              ),
        ),
        sliver: SliverPadding(
          padding: AppSpacing.panel,
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.related),
              ),
              content,
            ],
          ),
        ),
      );
    }

    Widget shoppingSection(String title, {required bool checked}) {
      final groups = <(String, bool, String), List<_CartRow>>{};
      for (final item in rows.where(
        (item) => isSavedChecked(item) == checked,
      )) {
        final key = item.position != null
            ? text(item.row['key'], text(item.row['name'] ?? item.row['text']))
            : text(item.entry['id']);
        (groups[(item.category, item.position != null, key)] ??= []).add(item);
      }

      if (groups.isEmpty) {
        return SliverToBoxAdapter(
          child: _section(title, [
            const Text('Keine offenen Einkaufszutaten.'),
          ]),
        );
      }

      final theme = Theme.of(context);
      final entries = groups.values.toList(growable: false);
      return cartPanel(
        title,
        SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final group = entries[index];
            final first = group.first;
            final startsCategory =
                index == 0 ||
                entries[index - 1].first.category != first.category;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (startsCategory)
                  Padding(
                    padding: EdgeInsets.only(
                      top: index == 0 ? 0 : AppSpacing.related,
                    ),
                    child: Semantics(
                      header: true,
                      child: SymbolLabel(
                        first.category,
                        shoppingCategoryIcon(
                          first.category,
                          first.row['category_icon'],
                        ),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                if (group.length > 1)
                  SymbolLabel(
                    text(first.row['name'] ?? first.row['text']),
                    first.row['icon'],
                    style: theme.textTheme.titleSmall,
                  ),
                for (final item in group) shoppingRow(item),
              ],
            );
          },
        ),
      );
    }

    const gap = SliverToBoxAdapter(child: SizedBox(height: AppSpacing.section));
    return [
      gap,
      shoppingSection('Zutaten', checked: false),
      if (rows.any(isSavedChecked)) ...[
        gap,
        shoppingSection('Abgehakt', checked: true),
      ],
      gap,
      cartPanel(
        'Rezepte',
        recipes.isEmpty
            ? const SliverToBoxAdapter(
                child: Text('Noch keine Rezepte im Einkaufswagen.'),
              )
            : SliverList.separated(
                itemCount: recipes.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.related),
                itemBuilder: (context, index) {
                  final entry = recipes[index];
                  final data = entry['data'] as Json;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.related,
                    children: [
                      CompactRecipeTile(
                        title: text(data['name'], 'Rezept'),
                        leading: ClipOval(
                          child: SizedBox.square(
                            dimension: 40,
                            child: RecipeImage(
                              api: api,
                              filename: data['image_file'],
                            ),
                          ),
                        ),
                        onTap: () => _recipe({
                          ...data,
                          'id': entry['recipe_id'],
                        }, calendar: true),
                        actionLabel: removeLabel(entry),
                        actionIcon: Icons.delete_outline,
                        onAction: editable && !entrySaving(entry)
                            ? () => _mutate('DELETE', entryPath(entry))
                            : null,
                      ),
                      if (data['ingredients_complete'] == false)
                        const Text(
                          'Zutaten fehlen. Bitte nach der Synchronisierung erneut hinzufügen.',
                        ),
                      ...status(entry),
                    ],
                  );
                },
              ),
      ),
    ];
  }

  Widget _cartHeader(Json? cart) {
    final editable = !busy && cart?['transferring'] != true;
    final pending = objects(cart?['items'])
        .any((item) => item['status'] == 'pending');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.item,
      children: [
        Row(
          spacing: AppSpacing.related,
          children: [
            Expanded(child: _heading('Mein Einkaufswagen')),
            IconButton.filledTonal(
              tooltip: 'An Cookidoo übertragen',
              onPressed: editable && _pendingCartChecks.isEmpty && pending
                  ? () => _mutate(
                      'POST',
                      '/api/cart/transfer',
                      null,
                      'Einkaufswagen an Cookidoo übertragen.',
                    )
                  : null,
              icon: const Icon(Icons.upload_outlined, size: 20),
            ),
          ],
        ),
        FilledButton.icon(
          style: ActionPillGrid.buttonStyle,
          onPressed: editable ? _addCartItem : null,
          icon: const Icon(Icons.add),
          label: const Text('Artikel hinzufügen', textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _overview() {
    final featured = _featured;
    final stats = _overviewStats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.section,
      children: [
        _heading('Dein Rezeptmix'),
        _section('Deine Sammlung', [
          ActionPillGrid(
            minColumnWidth: 130,
            children: [
              for (final (area, icon, label) in [
                (1, Icons.layers_outlined, 'Rezeptlisten'),
                (2, Icons.menu_book, 'Alle Rezepte'),
                (3, Icons.calendar_today_outlined, 'Meine Woche'),
                (4, Icons.shopping_cart_outlined, 'Einkaufswagen'),
              ])
                FilledButton.tonal(
                  style: ActionPillGrid.buttonStyle,
                  onPressed: () => _navigate(area),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: AppSpacing.tight,
                    children: [
                      Icon(icon),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(letterSpacing: 0),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (stats != null && stats.isNotEmpty)
            Text(
              '${stats['collections'] ?? 0} Rezeptlisten · ${stats['recipes'] ?? 0} gespeicherte Rezepte',
            ),
          if (stats?['last_sync'] case final String lastSync)
            Text('Letzter Abgleich: ${formatSyncDate(lastSync)}'),
        ]),
        if ((featured?['recipe'] ?? featured?['featured'])
            case final Json recipe)
          RecipeCard(
            api: api,
            recipe: recipe,
            onTap: () => _recipe(recipe),
            cornerAction: RecipeCornerAction(
              tooltip: 'Anderes Rezept',
              onPressed: busy || featured?['can_shuffle'] == false
                  ? null
                  : () => _mutate('POST', '/api/featured-recipe/shuffle'),
              icon: Icons.shuffle,
            ),
          )
        else if (featured != null)
          const Text('Kein Zufallsrezept vorhanden.'),
        if (_overviewPreviews.isNotEmpty) ...[
          Text(
            'Ein Blick in deine Sammlung',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          RecipePreviewGrid(
            api: api,
            recipes: _overviewPreviews,
            onOpen: _recipe,
          ),
        ],
      ],
    );
  }

  Widget _localArea(int index) {
    final refreshCount = _areaRefreshes[index];
    return switch (index) {
      1 => RecipeCollections(
        api: api,
        active: area == 1,
        openRecipe: _recipe,
        onSync: _syncFromPull,
        onChanged: () => _dirtyAreas.addAll([0, 2, 3]),
        recipeRevision: () => _recipeRevision,
        onManageClosed: (changed) async {
          if (changed || _dirtyAreas.contains(1)) await _refresh();
        },
        refreshCount: refreshCount,
      ),
      2 => RecipeBrowser(
        api: api,
        openRecipe: _recipe,
        onSync: _syncFromPull,
        searchFocus: recipeSearch,
        refreshCount: refreshCount,
      ),
      3 => WeekView(
        api: api,
        active: area == 3,
        onSync: _syncFromPull,
        refreshCount: refreshCount,
        openRecipe: (recipe, calendar) => _recipe(recipe, calendar: calendar),
        statusChanged: _adoptStatus,
        cartCountChanged: (count) {
          if (mounted && area == 3 && serverCartCount != count) {
            if (_areaData.containsKey(4) && serverCartCount != null) {
              _dirtyAreas.add(4);
            }
            setState(() => serverCartCount = count);
          }
        },
        onCartChanged: () => _dirtyAreas.add(4),
      ),
      5 => PantryView(
        api: api,
        onSync: _syncFromPull,
        expandedCategories: pantryExpanded,
        refreshCount: refreshCount,
        onChanged: () => _dirtyAreas.add(4),
      ),
      _ => _simpleArea(index),
    };
  }

  Widget _simpleArea(int index) => FutureBuilder<dynamic>(
    future: _areaData.putIfAbsent(index, () => _load(index)),
    builder: (context, snapshot) {
      final waiting = snapshot.connectionState != ConnectionState.done;
      final cart = index == 4 ? snapshot.data as Json? ?? _lastCart : null;
      return RefreshIndicator(
        onRefresh: _pullRefresh,
        child: CustomScrollView(
          key: PageStorageKey(index),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: AppSpacing.page,
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: index == 4 ? _cartHeader(cart) : _overview(),
                  ),
                  if ((waiting && cart == null) ||
                      (!waiting && snapshot.hasError))
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.section),
                        child: waiting
                            ? const LinearProgressIndicator()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: AppSpacing.related,
                                children: [
                                  Text(snapshot.error.toString()),
                                  OutlinedButton(
                                    onPressed: busy ? null : _refresh,
                                    child: const Text('Erneut laden'),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  if (cart != null) ..._cart(cart),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 600;
    final compactToolbar = width < 360;
    final hideNavigationLabels =
        width < 320 || width / MediaQuery.textScalerOf(context).scale(1) < 310;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: compactToolbar ? 0 : 48,
        titleSpacing: compactToolbar ? AppSpacing.section : AppSpacing.related,
        leading: compactToolbar
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.item,
                  AppSpacing.related,
                  0,
                  AppSpacing.related,
                ),
                child: Image.asset(
                  'assets/icon.png',
                  excludeFromSemantics: true,
                ),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rezeptmix',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (api.usesTestData)
              Text(
                compactToolbar ? 'Testdaten' : 'Debug-Modus · Testdaten',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              )
            else if (widget.connection != null)
              Text(
                switch (widget.connection!.mode) {
                  ConnectionMode.local => 'Heimnetz',
                  ConnectionMode.telegram => 'Telegram',
                  ConnectionMode.checking => 'Verbindung wird geprüft',
                  ConnectionMode.offline => 'Offline',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              )
            else if (connected != null)
              Text(
                connected! ? 'Cookidoo verbunden' : 'Cookidoo getrennt',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        actions: [
          if (widget.connection?.mode == ConnectionMode.telegram)
            const Icon(
              Icons.send,
              color: Colors.blue,
              semanticLabel: 'Telegram-Verbindung',
            ),
          IconButton(
            tooltip: 'Rezepte suchen',
            onPressed: busy || !_available
                ? null
                : () async {
                    await _navigate(2);
                    if (mounted && area == 2) recipeSearch.requestFocus();
                  },
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Einkaufswagen öffnen',
            onPressed: busy ? null : () => _navigate(4),
            icon: Badge(
              isLabelVisible: serverCartCount != null,
              label: Text(text(serverCartCount)),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          IconButton(
            tooltip: 'Einstellungen öffnen',
            onPressed: busy ? null : _settings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: useRail,
        child: Row(
          children: [
            if (useRail)
              ValueListenableBuilder<int>(
                valueListenable: _navigationIndex,
                builder: (context, index, _) => NavigationRail(
                  selectedIndex: index,
                  extended: width >= 1200,
                  labelType: width >= 1200
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  useIndicator: true,
                  scrollable: true,
                  onDestinationSelected: _navigate,
                  destinations: [
                    for (final (index, label) in areas.indexed)
                      NavigationRailDestination(
                        icon: Icon(icons[index]),
                        selectedIcon: Icon(selectedIcons[index]),
                        label: Text(label),
                        disabled: !_available && index != 3 && index != 4,
                      ),
                  ],
                ),
              ),
            Expanded(
              key: const ValueKey('main-content'),
              child: _SectionPager(
                key: _pagerKey,
                index: area,
                firstIndex: _available || area < 3 ? 0 : 3,
                count: _available || area < 3 ? areas.length : 2,
                swipeEnabled: !busy && (_available || area >= 3),
                canOpen: _canOpen,
                onPageChanged: (index) => _navigationIndex.value = index,
                onOpen: _open,
                builder: _available ? _localArea : _offlineArea,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: useRail
          ? null
          : ValueListenableBuilder<int>(
              valueListenable: _navigationIndex,
              builder: (context, index, _) => NavigationBar(
                selectedIndex: index,
                animationDuration: Duration.zero,
                labelBehavior: hideNavigationLabels
                    ? NavigationDestinationLabelBehavior.alwaysHide
                    : NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: _navigate,
                destinations: [
                  for (final (index, label) in areas.indexed)
                    NavigationDestination(
                      icon: Icon(icons[index]),
                      selectedIcon: Icon(selectedIcons[index]),
                      label: compactToolbar && index == 0 ? 'Start' : label,
                      enabled: _available || index == 3 || index == 4,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _offlineArea(int index) {
    final connection = widget.connection;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(connection?.error ?? 'Verbindung wird geprüft.'),
          if (connection?.hasPermission == false)
            TextButton(
              onPressed: _networkPermission,
              child: const Text('WLAN-Erkennung einrichten'),
            ),
          TextButton(
            onPressed: connection?.refresh,
            child: const Text('Erneut prüfen'),
          ),
        ],
      ),
    );
  }
}

class _SectionPager extends StatefulWidget {
  const _SectionPager({
    super.key,
    required this.index,
    required this.firstIndex,
    required this.count,
    required this.swipeEnabled,
    required this.canOpen,
    required this.onPageChanged,
    required this.onOpen,
    required this.builder,
  });

  final int index;
  final int firstIndex;
  final int count;
  final bool swipeEnabled;
  final bool Function(int) canOpen;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onOpen;
  final Widget Function(int) builder;

  @override
  State<_SectionPager> createState() => _SectionPagerState();
}

// The main pager uses full-width pages. Keep Flutter's target selection and
// slow drags, but brake a fast release according to the remaining distance.
class _SectionScrollPhysics extends PageScrollPhysics {
  const _SectionScrollPhysics({super.parent});

  @override
  _SectionScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _SectionScrollPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final normal = super.createBallisticSimulation(position, velocity);
    final tolerance = toleranceFor(position);
    if (normal is! ScrollSpringSimulation ||
        position.outOfRange ||
        velocity.abs() <= tolerance.velocity ||
        position.viewportDimension <= 0) {
      return normal;
    }
    final width = position.viewportDimension;
    final targetPage = (position.pixels / width + velocity.sign * 0.5).round();
    final target = (targetPage * width).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final distance = (target - position.pixels).abs();
    final limit = distance * math.sqrt(spring.stiffness / spring.mass);
    if (velocity.abs() <= limit) return normal;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity.sign * limit,
      tolerance: tolerance,
    );
  }
}

class _SectionPagerState extends State<_SectionPager> {
  late final _controller = PageController(
    initialPage: widget.index - widget.firstIndex,
    keepPage: false,
  );
  double _reducedMotionDistance = 0;

  @override
  void didUpdateWidget(_SectionPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.firstIndex != widget.firstIndex ||
        oldWidget.count != widget.count) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(widget.index - widget.firstIndex);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> goTo(int index) async {
    if (!_controller.hasClients || !widget.canOpen(index)) return;
    final page = index - widget.firstIndex;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(page);
    } else {
      await _controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted && _controller.hasClients && _controller.page == page) {
      _commit();
    }
  }

  void _commit() {
    if (!_controller.hasClients ||
        _controller.position.isScrollingNotifier.value) {
      return;
    }
    final page = _controller.page;
    if (page == null || (page - page.round()).abs() > 0.000001) return;
    final index = page.round() + widget.firstIndex;
    if (index == widget.index) return;
    if (widget.canOpen(index)) {
      widget.onOpen(index);
    } else {
      _controller.jumpToPage(widget.index - widget.firstIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final skipAnimation = reduceMotion && widget.swipeEnabled;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: const {PointerDeviceKind.touch},
        onHorizontalDragStart: skipAnimation
            ? (_) => _reducedMotionDistance = 0
            : null,
        onHorizontalDragUpdate: skipAnimation
            ? (details) => _reducedMotionDistance += details.delta.dx
            : null,
        onHorizontalDragEnd: skipAnimation
            ? (details) {
                final velocity = details.primaryVelocity ?? 0;
                final movement = _reducedMotionDistance;
                final direction = velocity.abs() > 20 ? velocity : movement;
                if (velocity.abs() > 20 ||
                    movement.abs() >= constraints.maxWidth / 2) {
                  unawaited(goTo(widget.index + (direction < 0 ? 1 : -1)));
                }
              }
            : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _commit();
              });
            }
            return false;
          },
          child: PageView.builder(
            key: const ValueKey('main-pager'),
            controller: _controller,
            pageSnapping: false,
            physics: !widget.swipeEnabled || reduceMotion
                ? const NeverScrollableScrollPhysics()
                : const _SectionScrollPhysics(),
            itemCount: widget.count,
            onPageChanged: (page) {
              final index = page + widget.firstIndex;
              if (widget.canOpen(index)) widget.onPageChanged(index);
            },
            itemBuilder: (context, page) {
              final index = page + widget.firstIndex;
              final active = index == widget.index;
              return _SectionPage(
                key: ValueKey(index),
                child: TickerMode(
                  enabled: active,
                  child: ExcludeFocus(
                    excluding: !active,
                    child: ExcludeSemantics(
                      excluding: !active,
                      child: IgnorePointer(
                        ignoring: !active,
                        child: PrimaryScrollController.none(
                          child: widget.builder(index),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionPage extends StatefulWidget {
  const _SectionPage({super.key, required this.child});
  final Widget child;

  @override
  State<_SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<_SectionPage>
    with AutomaticKeepAliveClientMixin<_SectionPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
