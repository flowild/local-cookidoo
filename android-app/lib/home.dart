import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'spacing.dart';
import 'appearance.dart';
import 'ingredient_icon.dart';
import 'pantry_view.dart';
import 'recipe_card.dart';
import 'recipe_detail.dart';
import 'recipe_library.dart';
import 'settings_view.dart';
import 'week_view.dart';
import 'telegram_service.dart';
import 'connection.dart';
import 'telegram_view.dart';

typedef _CartRow = ({Json entry, Json row, int? position, String category});

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
  int viewRefresh = 0;
  static const _retainedAreas = {1, 2, 3, 5};
  final _dirtyAreas = <int>{};
  final _areaRefreshes = List.filled(areas.length, 0);
  int _session = 0;
  var _pagerKey = GlobalKey<_SectionPagerState>();
  late bool _wasLocal;
  final pantryCollapsed = <int>{};
  final recipeSearch = FocusNode();
  final cartItem = TextEditingController();
  final _areaData = <int, Future<dynamic>>{};

  bool get _local =>
      widget.connection == null ||
      widget.connection!.mode == ConnectionMode.local;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _wasLocal = _local;
    widget.connection?.addListener(_connectionChanged);
    if (_local) unawaited(_startupSync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && wasBackgrounded) {
      wasBackgrounded = false;
      startupSyncAttempted = false;
      if (widget.connection == null) unawaited(_startupSync());
    }
  }

  void _connectionChanged() {
    if (!mounted) return;
    setState(() {
      final mode = widget.connection?.mode;
      if ((mode == ConnectionMode.telegram || mode == ConnectionMode.offline) &&
          area != 3 &&
          area != 4) {
        area = 3;
      }
      if (_wasLocal != _local) {
        _wasLocal = _local;
        _resetSession();
      }
      serverCartCount = null;
      viewRefresh++;
      _areaRefreshes[area]++;
      _areaData[area] = _load(area);
    });
    if (_local) unawaited(_startupSync());
  }

  void _resetSession() {
    _session++;
    _pagerKey = GlobalKey<_SectionPagerState>();
    _areaData.clear();
    _dirtyAreas.clear();
    pantryCollapsed.clear();
    cartItem.clear();
    api.clearImageCache();
  }

  Future<void> _startupSync() async {
    if (startupSyncAttempted || !_local) return;
    startupSyncAttempted = true;
    try {
      final status = await api.get('/api/status', timeout: shortRead) as Json;
      if (!mounted) return;
      if (!_local) {
        startupSyncAttempted = false;
        return;
      }
      _adoptStatus(status);
      if (status['connected'] == true) await _beginSync(notify: false);
    } on Exception {
      startupSyncAttempted = false;
      // Normal view loading reports connection errors.
    }
  }

  Future<void> _networkPermission() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Heimnetz erkennen'),
        content: const Text(
          'Android benötigt die Standortberechtigung, damit Rezeptgarten das WLAN ThomasWlan erkennen kann.',
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

  Future<dynamic> _load(int index) async => !_local
      ? null
      : switch (index) {
          0 => _loadOverview(),
          4 => _loadCart(),
          _ => null,
        };

  Future<Json> _loadOverview() async {
    final session = _session;
    final responses = await Future.wait<dynamic>([
      api.get('/api/featured-recipe', timeout: shortRead),
      api.get('/api/status', timeout: shortRead),
      api.get('/api/recipes?limit=8', timeout: shortRead),
    ]);
    final featured = responses[0] as Json;
    final status = responses[1] as Json;
    if (mounted && area == 0 && session == _session) _adoptStatus(status);
    return {
      ...featured,
      'stats': status['stats'],
      'previews': (responses[2] as Json)['items'],
    };
  }

  Future<Json> _loadCart() async {
    final session = _session;
    final cart = await api.get('/api/cart', timeout: shortRead) as Json;
    if (mounted && area == 4 && session == _session) {
      final count = objects(cart['items'])
          .where((item) => item['kind'] == 'recipe')
          .length;
      if (serverCartCount != count) {
        setState(() => serverCartCount = count);
      }
    }
    return cart;
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
    if (mounted && !busy) await _refresh();
  }

  Future<void> _beginSync({bool notify = true}) async {
    if (!_local || syncPending || syncRunning || busy) return;
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
      if (mounted) {
        setState(() {
          syncRunning = true;
          syncPollFailed = false;
        });
        _monitorSync();
      }
    } on Exception catch (error) {
      notice = error.toString();
    }
    if (!mounted) return;
    setState(() => syncPending = false);
    if (notify || !syncRunning) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> _pullRefresh() async {
    await _syncFromPull();
    if (mounted) await _refresh();
  }

  Future<void> _syncFromPull() async {
    await _beginSync();
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (mounted &&
        _local &&
        (syncPending || syncRunning) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
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
          _dirtyAreas.addAll([0, 1, 2, 3, 4, 5]);
          if (ModalRoute.of(context)?.isCurrent == true) await _refresh();
        }
      } on Exception {
        if (mounted && generation == syncGeneration) {
          if (_local && syncRunning) {
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
      (_local || index == 3 || index == 4);

  void _open(int index) {
    if (!_canOpen(index) || area == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => area = index);
    if (_local && _dirtyAreas.contains(index)) unawaited(_refresh());
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
        if (_local) {
          _areaRefreshes[area]++;
        } else {
          viewRefresh++;
        }
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
    if (name == null || !mounted || session != _session || !_local) return;
    if (await _mutate('POST', '/api/cart/items', {'name': name}) && mounted) {
      cartItem.clear();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.connection?.removeListener(_connectionChanged);
    syncPoll?.cancel();
    recipeSearch.dispose();
    cartItem.dispose();
    super.dispose();
  }

  Future<void> _recipe(Json recipe, {bool calendar = false}) async {
    if (recipe['id'] is! String) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetail(
          api: api,
          preview: recipe,
          calendar: calendar,
          onSync: _syncFromPull,
          onRecipeCardsChanged: () => _dirtyAreas.addAll([0, 1, 2, 3]),
          onWeekChanged: () => _dirtyAreas.add(3),
          onCartChanged: () => _dirtyAreas.add(4),
        ),
      ),
    );
    if (mounted && _dirtyAreas.contains(area)) await _refresh();
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
    String removeLabel(Json item) =>
        '${text((item['data'] as Json)['name'])} entfernen';

    Widget remove(Json item) => IconButton(
      tooltip: removeLabel(item),
      onPressed: editable ? () => _mutate('DELETE', entryPath(item)) : null,
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
        Wrap(
          spacing: AppSpacing.related,
          runSpacing: AppSpacing.related,
          children: [
            for (final (value, label) in [
              ('done', 'Dort vorhanden'),
              ('pending', 'Dort nicht vorhanden'),
            ])
              OutlinedButton(
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

    Widget shoppingRow(_CartRow item, bool checked) {
      final entry = item.entry;
      final isRecipe = item.position != null;
      final suffix = isRecipe ? 'ingredients/${item.position}' : 'owned';
      final canCheck = editable && entry['status'] == 'pending';
      void toggle(bool? value) {
        unawaited(
          _mutate('PUT', '${entryPath(entry)}/$suffix', {'owned': value}),
        );
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
        (item) => (item.row['owned'] == true) == checked,
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
                      child: Text(
                        first.category,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                if (group.length > 1)
                  Text(
                    text(first.row['name'] ?? first.row['text']),
                    style: theme.textTheme.titleSmall,
                  ),
                for (final item in group) shoppingRow(item, checked),
              ],
            );
          },
        ),
      );
    }

    const gap = SliverToBoxAdapter(child: SizedBox(height: AppSpacing.section));
    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.item,
          children: [
            Row(
              spacing: AppSpacing.related,
              children: [
                Expanded(child: _heading('Mein Einkaufswagen')),
                if (items.isNotEmpty)
                  PopupMenuButton<String>(
                    enabled: editable,
                    tooltip: 'Einkaufswagenaktionen',
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'clear',
                        child: Text('Einkaufswagen leeren'),
                      ),
                    ],
                    onSelected: (_) async {
                      if (await _confirm(
                            'Den gesamten lokalen Einkaufswagen leeren?',
                            'Einkaufswagen leeren',
                          ) &&
                          mounted) {
                        await _mutate(
                          'DELETE',
                          '/api/cart',
                          null,
                          'Einkaufswagen geleert.',
                        );
                      }
                    },
                  ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.related,
              runSpacing: AppSpacing.related,
              children: [
                FilledButton.icon(
                  onPressed: editable ? _addCartItem : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Artikel hinzufügen'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      editable &&
                          items.any((item) => item['status'] == 'pending')
                      ? () => _mutate(
                          'POST',
                          '/api/cart/transfer',
                          null,
                          'Einkaufswagen an Cookidoo übertragen.',
                        )
                      : null,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('An Cookidoo übertragen'),
                ),
              ],
            ),
          ],
        ),
      ),
      gap,
      shoppingSection('Zutaten', checked: false),
      if (rows.any((item) => item.row['owned'] == true)) ...[
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
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: AppSpacing.related,
                    children: [
                      CompactRecipeTile(
                        title: text(entry['data']['name'], 'Rezept'),
                        onTap: () => _recipe({
                          ...entry['data'] as Json,
                          'id': entry['recipe_id'],
                        }, calendar: true),
                        actionLabel: removeLabel(entry),
                        actionIcon: Icons.delete_outline,
                        onAction: editable
                            ? () => _mutate('DELETE', entryPath(entry))
                            : null,
                      ),
                      if ((entry['data'] as Json)['ingredients_complete'] ==
                          false)
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

  Widget _overview(Object? result) {
    final map = result is Json ? result : <String, dynamic>{};
    final stats = map['stats'] is Json
        ? map['stats'] as Json
        : <String, dynamic>{};
    final previews = objects(map['previews']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.section,
      children: [
        _heading('Dein Rezeptgarten'),
        if ((map['recipe'] ?? map['featured']) case final Json recipe) ...[
          RecipeCard(
            api: api,
            recipe: recipe,
            onTap: () => _recipe(recipe),
            cornerAction: RecipeCornerAction(
              tooltip: 'Anderes Rezept',
              onPressed: busy || map['can_shuffle'] == false
                  ? null
                  : () => _mutate('POST', '/api/featured-recipe/shuffle'),
              icon: Icons.shuffle,
            ),
          ),
        ] else
          const Text('Kein Zufallsrezept vorhanden.'),
        _section('Deine Sammlung', [
          if (stats.isNotEmpty)
            Text(
              '${stats['collections'] ?? 0} Rezeptlisten · ${stats['recipes'] ?? 0} gespeicherte Rezepte',
            ),
          if (stats['last_sync'] case final String lastSync)
            Text('Letzter Abgleich: ${formatSyncDate(lastSync)}'),
          Wrap(
            spacing: AppSpacing.related,
            runSpacing: AppSpacing.related,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _navigate(1),
                icon: const Icon(Icons.layers_outlined),
                label: const Text('Alle Listen ansehen'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _navigate(2),
                icon: const Icon(Icons.menu_book),
                label: const Text('Alle Rezepte'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _navigate(3),
                icon: const Icon(Icons.calendar_today_outlined),
                label: const Text('Meine Woche'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _navigate(4),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('Einkaufswagen'),
              ),
            ],
          ),
        ]),
        if (previews.isNotEmpty) ...[
          Text(
            'Ein Blick in deine Sammlung',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          RecipePreviewGrid(api: api, recipes: previews, onOpen: _recipe),
        ],
      ],
    );
  }

  Widget _localArea(int index) {
    final refreshCount = _areaRefreshes[index];
    return switch (index) {
      1 => RecipeCollections(
        api: api,
        openRecipe: _recipe,
        onSync: _syncFromPull,
        onChanged: () => _dirtyAreas.addAll([0, 2, 3]),
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
        collapsed: pantryCollapsed,
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
                  if (waiting && !snapshot.hasData)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (snapshot.hasError && !waiting)
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: AppSpacing.related,
                        children: [
                          _heading(
                            index == 4 ? 'Mein Einkaufswagen' : areas[index],
                          ),
                          Text(snapshot.error.toString()),
                          OutlinedButton(
                            onPressed: busy ? null : _refresh,
                            child: const Text('Erneut laden'),
                          ),
                        ],
                      ),
                    )
                  else if (snapshot.hasData)
                    if (index == 4)
                      ..._cart(snapshot.data as Json)
                    else
                      SliverToBoxAdapter(child: _overview(snapshot.data)),
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
              'Rezeptgarten',
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
            onPressed: busy || !_local
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
            tooltip: syncRunning ? 'Synchronisierung läuft' : 'Synchronisieren',
            onPressed: busy || syncPending || syncRunning || !_local
                ? null
                : _beginSync,
            icon: syncPending || syncRunning
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
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
              NavigationRail(
                selectedIndex: area,
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
                      disabled: !_local && index != 3 && index != 4,
                    ),
                ],
              ),
            Expanded(
              key: const ValueKey('main-content'),
              child: _SectionPager(
                key: _pagerKey,
                index: area,
                firstIndex: _local || area < 3 ? 0 : 3,
                count: _local || area < 3 ? areas.length : 2,
                swipeEnabled: !busy && (_local || area >= 3),
                canOpen: _canOpen,
                onOpen: _open,
                builder: _local ? _localArea : _remoteArea,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: area,
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
                    enabled: _local || index == 3 || index == 4,
                  ),
              ],
            ),
    );
  }

  Widget _remoteArea(int index) {
    final connection = widget.connection;
    final telegram = widget.telegram;
    if (connection?.mode == ConnectionMode.telegram && telegram != null) {
      return TelegramView(
        key: ValueKey('telegram-$index-$viewRefresh'),
        telegram: telegram,
        cart: index == 4,
        notice: connection?.error,
      );
    }
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
    required this.onOpen,
    required this.builder,
  });

  final int index;
  final int firstIndex;
  final int count;
  final bool swipeEnabled;
  final bool Function(int) canOpen;
  final ValueChanged<int> onOpen;
  final Widget Function(int) builder;

  @override
  State<_SectionPager> createState() => _SectionPagerState();
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
    if (page == null) return;
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
            physics: !widget.swipeEnabled || reduceMotion
                ? const NeverScrollableScrollPhysics()
                : null,
            itemCount: widget.count,
            onPageChanged: (page) {
              final index = page + widget.firstIndex;
              if (widget.canOpen(index)) widget.onOpen(index);
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
