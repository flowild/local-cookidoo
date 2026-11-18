import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'ingredient_icon.dart';
import 'pantry_view.dart';
import 'recipe_card.dart';
import 'recipe_detail.dart';
import 'recipe_library.dart';
import 'week_view.dart';

typedef _CartRow = ({Json entry, Json row, int? position, String category});

class RezeptgartenHome extends StatefulWidget {
  const RezeptgartenHome({super.key, required this.api});

  final RezeptgartenApi api;

  @override
  State<RezeptgartenHome> createState() => _RezeptgartenHomeState();
}

class _RezeptgartenHomeState extends State<RezeptgartenHome> {
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
  RezeptgartenApi get api => widget.api;
  int area = 3;
  int? serverCartCount;
  bool busy = false;
  int viewRefresh = 0;
  final pantryCollapsed = <int>{};
  final recipeSearch = FocusNode();
  final cartItem = TextEditingController();
  late Future<dynamic> data = _load();

  Future<dynamic> _load() async => switch (area) {
    0 => api.get('/api/featured-recipe'),
    4 => api.get('/api/cart', timeout: shortRead),
    _ => null,
  };

  void _open(int index) {
    if (busy || (area == index && index != 3)) return;
    setState(() {
      area = index;
      data = _load();
    });
  }

  Future<void> _refresh() async {
    if (busy) return;
    if (area == 1 || area == 2 || area == 3 || area == 5) {
      setState(() => viewRefresh++);
      return;
    }
    final updated = _load();
    setState(() {
      data = updated;
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
    final updated = _load();
    setState(() {
      data = updated;
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
    final name = cartItem.text.trim();
    if (name.isEmpty || name.length > 100) return;
    if (await _mutate('POST', '/api/cart/items', {'name': name}) && mounted) {
      cartItem.clear();
    }
  }

  @override
  void dispose() {
    recipeSearch.dispose();
    cartItem.dispose();
    super.dispose();
  }

  Future<void> _recipe(Json recipe, {bool calendar = false}) async {
    if (recipe['id'] is! String) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RecipeDetail(api: api, preview: recipe, calendar: calendar),
      ),
    );
    if (mounted && area != 1 && area != 2 && area != 3) await _refresh();
  }

  Widget _heading(String title, [String? description]) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (description != null) Text(description),
      ],
    ),
  );

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );

  List<Widget> _entriesOrHint(List<Widget> entries, String hint) =>
      entries.isEmpty ? [Text(hint)] : entries;

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

  Widget _cart(Json cart) {
    final items = objects(cart['items']);
    final recipes = items.where((item) => item['kind'] == 'recipe').toList();
    serverCartCount = recipes.length;
    final editable = !busy && cart['transferring'] != true;
    const statusLabels = {
      'processing': 'Wird übertragen',
      'done': 'Übertragen',
      'existing': 'Bereits in Cookidoo',
      'uncertain': 'Übertragung ungeklärt',
    };
    String entryPath(Json item) =>
        '/api/cart/${Uri.encodeComponent(text(item['id']))}';

    Widget remove(Json item) => IconButton(
      tooltip: '${text((item['data'] as Json)['name'])} entfernen',
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
          spacing: 8,
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
          category: 'Weitere Artikel',
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

    List<Widget> shoppingRows(bool checked) {
      final rendered = <Widget>[];
      String? category;
      final grouped = <(String, bool, String), List<_CartRow>>{};
      for (final item in rows.where(
        (item) => (item.row['owned'] == true) == checked,
      )) {
        final key = item.position != null
            ? text(item.row['key'], text(item.row['name'] ?? item.row['text']))
            : text(item.entry['id']);
        (grouped[(item.category, item.position != null, key)] ??= []).add(item);
      }
      for (final group in grouped.values) {
        final first = group.first;
        if (category != first.category) {
          category = first.category;
          rendered.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                first.category,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          );
        }
        if (group.length > 1) {
          rendered.add(
            Text(
              text(first.row['name'] ?? first.row['text']),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          );
        }
        for (final item in group) {
          final entry = item.entry;
          final isRecipe = item.position != null;
          final suffix = isRecipe ? 'ingredients/${item.position}' : 'owned';
          rendered.add(
            Row(
              children: [
                Checkbox(
                  value: checked,
                  visualDensity: VisualDensity.compact,
                  onChanged: !editable || entry['status'] != 'pending'
                      ? null
                      : (value) => _mutate(
                          'PUT',
                          '${entryPath(entry)}/$suffix',
                          {'owned': value},
                        ),
                ),
                IngredientIcon(
                  text(item.row['name'] ?? item.row['text']),
                  category: item.category,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text(item.row['text'] ?? item.row['name'])),
                      if (isRecipe)
                        Text(
                          text((entry['data'] as Json)['name']),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (!isRecipe) remove(entry),
              ],
            ),
          );
          if (!isRecipe) rendered.addAll(status(entry));
        }
      }
      return rendered;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Mein Einkaufswagen',
          'Ein Häkchen bedeutet: bereits vorhanden.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed:
                  editable && items.any((item) => item['status'] == 'pending')
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
            OutlinedButton(
              onPressed: editable && items.isNotEmpty
                  ? () async {
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
                    }
                  : null,
              child: const Text('Einkaufswagen leeren'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _section(
          'Rezepte',
          _entriesOrHint([
            for (final entry in recipes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        RecipeCard(
                          api: api,
                          recipe: entry['data'] as Json,
                          onTap: () => _recipe({
                            ...entry['data'] as Json,
                            'id': entry['recipe_id'],
                          }, calendar: true),
                        ),
                        Material(
                          color: Theme.of(context).colorScheme.surface,
                          shape: const CircleBorder(),
                          child: remove(entry),
                        ),
                      ],
                    ),
                    if ((entry['data'] as Json)['ingredients_complete'] ==
                        false)
                      const Text(
                        'Zutaten fehlen. Bitte nach der Synchronisierung erneut hinzufügen.',
                      ),
                    ...status(entry),
                  ],
                ),
              ),
          ], 'Noch keine Rezepte im Einkaufswagen.'),
        ),
        _section(
          'Zutaten',
          _entriesOrHint(shoppingRows(false), 'Keine offenen Einkaufszutaten.'),
        ),
        if (rows.any((item) => item.row['owned'] == true))
          _section('Abgehakt', shoppingRows(true)),
        _section('Artikel hinzufügen', [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: cartItem,
                  enabled: editable,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Artikel',
                    counterText: '',
                  ),
                  onSubmitted: editable ? (_) => _addCartItem() : null,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: editable ? _addCartItem : null,
                child: const Text('Hinzufügen'),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _overview(Object? result) {
    final map = result is Json ? result : <String, dynamic>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Dein Rezeptgarten'),
        if ((map['recipe'] ?? map['featured']) case final Json recipe) ...[
          RecipeCard(api: api, recipe: recipe, onTap: () => _recipe(recipe)),
          OutlinedButton.icon(
            onPressed: busy || map['can_shuffle'] == false
                ? null
                : () => _mutate('POST', '/api/featured-recipe/shuffle'),
            icon: const Icon(Icons.shuffle),
            label: const Text('Anderes Rezept'),
          ),
        ] else
          const Text('Kein Zufallsrezept vorhanden.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: data,
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState != ConnectionState.done;
        final body = waiting
            ? const Center(child: CircularProgressIndicator())
            : snapshot.hasError
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _heading(area == 3 ? 'Meine Woche' : areas[area]),
                  Text(snapshot.error.toString()),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: busy ? null : _refresh,
                        child: const Text('Erneut laden'),
                      ),
                    ],
                  ),
                ],
              )
            : switch (area) {
                4 => _cart(snapshot.data as Json),
                _ => _overview(snapshot.data),
              };
        return Scaffold(
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.all(10),
              child: Image.asset('assets/icon.png'),
            ),
            title: const Text('Rezeptgarten'),
            actions: [
              IconButton(
                tooltip: 'Rezepte suchen',
                onPressed: busy
                    ? null
                    : () {
                        _open(2);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && area == 2) recipeSearch.requestFocus();
                        });
                      },
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Einkaufswagen öffnen',
                onPressed: busy ? null : () => _open(4),
                icon: Badge(
                  isLabelVisible: serverCartCount != null,
                  label: Text(text(serverCartCount)),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
              ),
              IconButton(
                tooltip: 'Neu laden',
                onPressed: busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: switch (area) {
              1 => RecipeCollections(
                api: api,
                openRecipe: _recipe,
                refreshCount: viewRefresh,
              ),
              2 => RecipeBrowser(
                api: api,
                openRecipe: _recipe,
                searchFocus: recipeSearch,
                refreshCount: viewRefresh,
              ),
              3 => WeekView(
                api: api,
                refreshCount: viewRefresh,
                openRecipe: (recipe, calendar) =>
                    _recipe(recipe, calendar: calendar),
                cartCountChanged: (count) {
                  if (mounted && area == 3 && serverCartCount != count) {
                    setState(() => serverCartCount = count);
                  }
                },
              ),
              5 => PantryView(
                api: api,
                collapsed: pantryCollapsed,
                refreshCount: viewRefresh,
              ),
              _ => RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [if (busy) const LinearProgressIndicator(), body],
                ),
              ),
            },
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: area,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: _open,
            destinations: [
              for (final (index, label) in areas.indexed)
                NavigationDestination(icon: Icon(icons[index]), label: label),
            ],
          ),
        );
      },
    );
  }
}
