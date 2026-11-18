import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'recipe_card.dart';

typedef OpenRecipe = Future<void> Function(Json recipe);

const _sorts = {
  'name': 'Name · A bis Z',
  'time': 'Kürzeste Gesamtzeit',
  'servings': 'Wenigste Portionen',
  'ingredients': 'Wenigste Zutaten',
};

class RecipeBrowser extends StatefulWidget {
  const RecipeBrowser({
    super.key,
    required this.api,
    required this.openRecipe,
    this.collection,
    this.refreshCount = 0,
    this.searchFocus,
  });

  final RezeptgartenApi api;
  final OpenRecipe openRecipe;
  final Json? collection;
  final int refreshCount;
  final FocusNode? searchFocus;

  @override
  State<RecipeBrowser> createState() => _RecipeBrowserState();
}

class _RecipeBrowserState extends State<RecipeBrowser> {
  static const _pageSize = 48;
  final _recipes = <Json>[];
  Timer? _searchTimer;
  int _request = 0;
  String _query = '';
  String _sort = 'name';
  _Filters _filters = const _Filters();
  int _total = 0;
  int _matched = 0;
  bool _loading = true;
  bool _deleting = false;
  String? _error;

  String? get _collection => widget.collection?['id'] as String?;
  bool get _local => widget.collection?['kind'] == 'local';

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  @override
  void didUpdateWidget(RecipeBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshCount != oldWidget.refreshCount) unawaited(_fetch());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool append = false}) async {
    final request = ++_request;
    final collection = _collection;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) _recipes.clear();
    });
    try {
      final result = await _recipePage(widget.api, {
        'collection': ?collection,
        if (collection != null) 'show_all': 'true',
        'q': _query,
        'sort': _sort,
        'offset': '${_recipes.length}',
        'limit': '$_pageSize',
        ..._filters.parameters,
      });
      if (!mounted || request != _request) return;
      setState(() {
        _recipes.addAll(objects(result['items']));
        _total = result['total'] as int;
        _matched = result['match_total'] as int;
      });
    } on Exception catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _search(String value) {
    _searchTimer?.cancel();
    // Invalidate requests immediately, including a page that is still loading.
    _request++;
    _query = value.trim();
    setState(() {
      _recipes.clear();
      _loading = true;
      _error = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 300), _fetch);
  }

  Future<void> _chooseFilters() async {
    final filters = await showDialog<_Filters>(
      context: context,
      builder: (_) => _FilterDialog(
        api: widget.api,
        collection: _collection,
        initial: _filters,
      ),
    );
    if (filters == null || !mounted) return;
    _filters = filters;
    await _fetch();
  }

  Future<void> _addRecipes() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _Candidates(
          api: widget.api,
          collection: _collection!,
          query: _query,
          filters: _filters,
          openRecipe: widget.openRecipe,
        ),
      ),
    );
    if (mounted) await _fetch();
  }

  Future<void> _removeCollection() async {
    if (_deleting) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Liste löschen?'),
        content: Text(
          '„${widget.collection!['name']}“ und ihre Zuordnungen werden gelöscht. Die Rezepte bleiben erhalten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Liste löschen'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || _deleting) return;
    setState(() => _deleting = true);
    try {
      await widget.api.write(
        'DELETE',
        '/api/local-collections/${Uri.encodeComponent(_collection!)}',
      );
      if (mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      _showError(context, error);
    }
  }

  Future<void> _open(Json recipe) async {
    if (_deleting) return;
    await widget.openRecipe(recipe);
    if (mounted) await _fetch();
  }

  Widget _controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        text(widget.collection?['name'], 'Alle Rezepte'),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 12),
      TextField(
        focusNode: widget.searchFocus,
        maxLength: 200,
        onChanged: _search,
        onSubmitted: (_) {
          _searchTimer?.cancel();
          unawaited(_fetch());
        },
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          labelText: 'Titel oder Zutaten suchen',
          prefixIcon: Icon(Icons.search),
          counterText: '',
        ),
      ),
      Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: _sort,
            onChanged: (sort) {
              if (sort == null || sort == _sort) return;
              _sort = sort;
              unawaited(_fetch());
            },
            items: [
              for (final entry in _sorts.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _chooseFilters,
            icon: const Icon(Icons.filter_list),
            label: Text(_filters.active ? 'Filter bearbeiten' : 'Filtern'),
          ),
          if (_local) ...[
            OutlinedButton.icon(
              onPressed: _deleting ? null : _addRecipes,
              icon: const Icon(Icons.add),
              label: const Text('Rezepte hinzufügen'),
            ),
            TextButton.icon(
              onPressed: _deleting ? null : _removeCollection,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Liste löschen'),
            ),
          ],
        ],
      ),
      if (_filters.active)
        Wrap(
          spacing: 8,
          children: [
            for (final ingredient in _filters.ingredients)
              Chip(label: Text(ingredient)),
            if (_filters.servings case final int servings)
              Chip(label: Text('Ab $servings Portionen')),
            if (_filters.minutes case final int minutes)
              Chip(label: Text('Bis $minutes Min.')),
          ],
        ),
      if (_error != null) ...[
        Text(_error!),
        OutlinedButton(
          onPressed: () => _fetch(append: _recipes.isNotEmpty),
          child: const Text('Erneut laden'),
        ),
      ] else if (!_loading || _recipes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _collection != null && (_filters.active || _query.isNotEmpty)
                ? '$_matched von $_total Rezepten passen zum Filter'
                : '$_total ${_total == 1 ? 'Rezept' : 'Rezepte'}',
          ),
        ),
      if (_recipes.isEmpty && !_loading && _error == null)
        const Text('Keine passenden Rezepte gefunden.'),
    ],
  );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _fetch,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: _controls()),
              _RecipeGrid(
                api: widget.api,
                recipes: _recipes,
                openRecipe: _open,
              ),
              if (_loading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (!_loading && _error == null && _recipes.length < _total)
                SliverToBoxAdapter(
                  child: OutlinedButton(
                    onPressed: () => _fetch(append: true),
                    child: const Text('Weitere Rezepte laden'),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<Json> _recipePage(
  RezeptgartenApi api,
  Map<String, Object> params,
) async {
  final path = Uri(path: '/api/recipes', queryParameters: params);
  return await api.get(path.toString()) as Json;
}

class _RecipeGrid extends StatelessWidget {
  const _RecipeGrid({
    required this.api,
    required this.recipes,
    required this.openRecipe,
  });
  final RezeptgartenApi api;
  final List<Json> recipes;
  final OpenRecipe openRecipe;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      const gap = 12.0;
      final columns = (constraints.crossAxisExtent / 182).floor().clamp(1, 5);
      final width =
          (constraints.crossAxisExtent - (columns - 1) * gap) / columns;
      return SliverList.builder(
        itemCount: (recipes.length / columns).ceil(),
        itemBuilder: (context, index) {
          final row = recipes.skip(index * columns).take(columns);
          return Padding(
            padding: const EdgeInsets.only(bottom: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (position, recipe) in row.indexed) ...[
                  if (position != 0) const SizedBox(width: gap),
                  SizedBox(
                    key: ValueKey(recipe['id']),
                    width: width,
                    child: Opacity(
                      opacity: recipe['matches'] == false ? 0.48 : 1,
                      child: RecipeCard(
                        api: api,
                        recipe: recipe,
                        onTap: () => openRecipe(recipe),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

class _Filters {
  const _Filters({this.ingredients = const [], this.servings, this.minutes});
  final List<String> ingredients;
  final int? servings;
  final int? minutes;

  bool get active =>
      ingredients.isNotEmpty || servings != null || minutes != null;
  Map<String, Object> get parameters => {
    if (ingredients.isNotEmpty) 'ingredient': ingredients,
    if (servings != null) 'min_servings': '$servings',
    if (minutes != null) 'max_minutes': '$minutes',
  };
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({
    required this.api,
    required this.collection,
    required this.initial,
  });
  final RezeptgartenApi api;
  final String? collection;
  final _Filters initial;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late final ingredients = [...widget.initial.ingredients];
  late final _servings = TextEditingController(
    text: text(widget.initial.servings),
  );
  late final _minutes = TextEditingController(
    text: text(widget.initial.minutes),
  );
  late final Future<Json?> _options = _loadOptions();
  TextEditingController? _ingredientField;
  final _form = GlobalKey<FormState>();

  Future<Json?> _loadOptions() async {
    final collection = widget.collection;
    if (collection == null) return null;
    try {
      return await widget.api.get(
        '/api/collections/${Uri.encodeComponent(collection)}/filter-options',
      ) as Json;
    } on Exception {
      return null;
    }
  }

  @override
  void dispose() {
    _servings.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _ingredient(String value) {
    final name = value.trim();
    if (name.isEmpty || name.runes.length > 100 || ingredients.length >= 20) {
      return;
    }
    if (ingredients.any((item) => item.toLowerCase() == name.toLowerCase())) {
      _ingredientField?.clear();
      return;
    }
    setState(() => ingredients.add(name));
    _ingredientField?.clear();
  }

  String? _numberError(String? value, int max) {
    if (value == null || value.trim().isEmpty) return null;
    final number = int.tryParse(value.trim());
    return number != null && number >= 1 && number <= max
        ? null
        : 'Bitte gib eine Zahl zwischen 1 und $max ein.';
  }

  void _apply() {
    if (!_form.currentState!.validate()) return;
    _ingredient(_ingredientField?.text ?? '');
    Navigator.pop(
      context,
      _Filters(
        ingredients: List.unmodifiable(ingredients),
        servings: int.tryParse(_servings.text.trim()),
        minutes: int.tryParse(_minutes.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rezepte filtern'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FutureBuilder<Json?>(
            future: _options,
            builder: (context, snapshot) {
              final options = snapshot.data;
              final names = options?['ingredients'];
              final aliases = options?['ingredient_aliases'];
              return Autocomplete<String>(
                onSelected: _ingredient,
                optionsBuilder: (input) {
                  final query = input.text.trim().toLowerCase();
                  if (query.isEmpty || names is! List) return const [];
                  return names
                      .whereType<String>()
                      .where((name) {
                        final other = aliases is Json ? aliases[name] : null;
                        return name.toLowerCase().contains(query) ||
                            (other is List &&
                                other.whereType<String>().any(
                                  (alias) =>
                                      alias.toLowerCase().contains(query),
                                ));
                      })
                      .take(8);
                },
                fieldViewBuilder: (context, controller, focus, submit) {
                  _ingredientField = controller;
                  return TextField(
                    controller: controller,
                    focusNode: focus,
                    enabled: ingredients.length < 20,
                    maxLength: 100,
                    onSubmitted: (value) {
                      submit();
                      // A selected suggestion clears the controller first.
                      if (controller.text.isNotEmpty) {
                        _ingredient(controller.text);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Zutat',
                      counterText: '',
                      suffixIcon: IconButton(
                        tooltip: 'Zutat zum Filter hinzufügen',
                        onPressed: ingredients.length < 20
                            ? () => _ingredient(controller.text)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final name in ingredients)
                InputChip(
                  label: Text(name),
                  onDeleted: () => setState(() => ingredients.remove(name)),
                ),
            ],
          ),
          TextFormField(
            controller: _servings,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Mindestens Portionen',
            ),
            validator: (value) => _numberError(value, 1000),
          ),
          TextFormField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Gesamtzeit höchstens (Min.)',
            ),
            validator: (value) => _numberError(value, 10080),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, const _Filters()),
        child: const Text('Zurücksetzen'),
      ),
      FilledButton(onPressed: _apply, child: const Text('Anwenden')),
    ],
  );
}

class _Candidates extends StatefulWidget {
  const _Candidates({
    required this.api,
    required this.collection,
    required this.query,
    required this.filters,
    required this.openRecipe,
  });
  final RezeptgartenApi api;
  final String collection;
  final String query;
  final _Filters filters;
  final OpenRecipe openRecipe;

  @override
  State<_Candidates> createState() => _CandidatesState();
}

class _CandidatesState extends State<_Candidates> {
  final recipes = <Json>[];
  Timer? _timer;
  int _request = 0;
  int _total = 0;
  String _query = '';
  bool _loading = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) recipes.clear();
    });
    try {
      final result = await _recipePage(widget.api, {
        'exclude_collection': widget.collection,
        'show_all': 'true',
        'q': widget.query,
        'candidate_q': _query,
        'offset': '${recipes.length}',
        'limit': '48',
        ...widget.filters.parameters,
      });
      if (!mounted || request != _request) return;
      setState(() {
        recipes.addAll(objects(result['items']));
        _total = result['total'] as int;
      });
    } on Exception catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _add(Json recipe) async {
    if (_adding || _loading) return;
    setState(() => _adding = true);
    try {
      final list = Uri.encodeComponent(widget.collection);
      final id = Uri.encodeComponent(text(recipe['id']));
      await widget.api.write(
        'PUT',
        '/api/local-collections/$list/recipes/$id',
        {'present': true},
      );
      if (mounted) await _load();
    } on Exception catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Weitere Rezepte hinzufügen')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            enabled: !_adding,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Rezepte suchen',
              counterText: '',
            ),
            onChanged: (value) {
              _query = value.trim();
              _timer?.cancel();
              _request++;
              setState(() {
                recipes.clear();
                _loading = true;
                _error = null;
              });
              _timer = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: () => _load(append: recipes.isNotEmpty),
              child: const Text('Erneut laden'),
            ),
          ],
          if (_loading || _adding) const LinearProgressIndicator(),
          if (!_loading && _error == null && recipes.isEmpty)
            const Text('Keine weiteren Rezepte gefunden.'),
          for (final recipe in recipes)
            ListTile(
              title: Opacity(
                opacity: recipe['matches'] == false ? 0.48 : 1,
                child: Text(text(recipe['name'])),
              ),
              onTap: _adding
                  ? null
                  : () async {
                      await widget.openRecipe(recipe);
                      if (mounted) await _load();
                    },
              trailing: IconButton(
                tooltip: '${text(recipe['name'])} zur Liste hinzufügen',
                icon: const Icon(Icons.add),
                onPressed: _adding || _loading ? null : () => _add(recipe),
              ),
            ),
          if (!_loading && _error == null && recipes.length < _total)
            OutlinedButton(
              onPressed: () => _load(append: true),
              child: const Text('Weitere Rezepte anzeigen'),
            ),
        ],
      ),
    ),
  );
}

class RecipeCollections extends StatefulWidget {
  const RecipeCollections({
    super.key,
    required this.api,
    required this.openRecipe,
    this.refreshCount = 0,
  });
  final RezeptgartenApi api;
  final OpenRecipe openRecipe;
  final int refreshCount;

  @override
  State<RecipeCollections> createState() => _RecipeCollectionsState();
}

class _RecipeCollectionsState extends State<RecipeCollections> {
  late Future<dynamic> _lists = widget.api.get('/api/collections');
  bool _creating = false;

  Future<void> _reload() async {
    final lists = widget.api.get('/api/collections');
    setState(() {
      _lists = lists;
    });
    try {
      await lists;
    } on Exception {
      // FutureBuilder presents the error.
    }
  }

  @override
  void didUpdateWidget(RecipeCollections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshCount != widget.refreshCount) unawaited(_reload());
  }

  Future<void> _create() async {
    if (_creating) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CollectionNameDialog(),
    );
    if (name == null || !mounted || _creating) return;
    setState(() => _creating = true);
    try {
      await widget.api.write('POST', '/api/local-collections', {'name': name});
      if (mounted) await _reload();
    } on Exception catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _open(Json list) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Rezeptlisten')),
          body: SafeArea(
            child: RecipeBrowser(
              api: widget.api,
              openRecipe: widget.openRecipe,
              collection: list,
            ),
          ),
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Widget _group(String title, Iterable<Json> lists, String empty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (lists.isEmpty) Text(empty),
        for (final list in lists)
          Card(
            child: ListTile(
              title: Text(text(list['name'])),
              subtitle: Text('${list['recipe_count'] ?? 0} Rezepte'),
              leading: Icon(
                list['kind'] == 'local'
                    ? Icons.list_alt
                    : Icons.layers_outlined,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(list),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _lists,
    builder: (context, snapshot) {
      final result = snapshot.data;
      final lists = result is Json ? objects(result['items']) : <Json>[];
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Text(
              'Deine Rezeptlisten',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _creating ? null : _create,
                icon: const Icon(Icons.add),
                label: const Text('Neue Liste'),
              ),
            ),
            if (_creating || snapshot.connectionState != ConnectionState.done)
              const LinearProgressIndicator(),
            if (snapshot.hasError) ...[
              Text(snapshot.error.toString()),
              TextButton(onPressed: _reload, child: const Text('Erneut laden')),
            ] else if (snapshot.hasData) ...[
              _group(
                'Meine lokalen Listen',
                lists.where((list) => list['kind'] == 'local'),
                'Noch keine lokalen Listen vorhanden.',
              ),
              _group(
                'Aus Cookidoo',
                lists.where((list) => list['kind'] != 'local'),
                'Noch keine Cookidoo-Sammlungen vorhanden.',
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _CollectionNameDialog extends StatefulWidget {
  const _CollectionNameDialog();
  @override
  State<_CollectionNameDialog> createState() => _CollectionNameDialogState();
}

class _CollectionNameDialogState extends State<_CollectionNameDialog> {
  String name = '';

  void _submit() {
    if (name.isNotEmpty && name.runes.length <= 100) {
      Navigator.pop(context, name);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Neue lokale Liste'),
    content: TextField(
      autofocus: true,
      maxLength: 100,
      onChanged: (value) => setState(() => name = value.trim()),
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(labelText: 'Listenname'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: name.isEmpty ? null : _submit,
        child: const Text('Anlegen'),
      ),
    ],
  );
}

void _showError(BuildContext context, Exception error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));
}
