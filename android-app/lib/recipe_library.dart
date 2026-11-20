import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'spacing.dart';
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
    this.onSync,
  });

  final RezeptgartenApi api;
  final OpenRecipe openRecipe;
  final Json? collection;
  final int refreshCount;
  final FocusNode? searchFocus;
  final Future<void> Function()? onSync;

  @override
  State<RecipeBrowser> createState() => _RecipeBrowserState();
}

class _RecipeBrowserState extends State<RecipeBrowser> {
  static const _pageSize = 48;
  final _recipes = <Json>[];
  final _searchField = TextEditingController();
  Timer? _searchTimer;
  int _request = 0;
  String _query = '';
  String _sort = 'name';
  _Filters _filters = const _Filters();
  int _total = 0;
  int _matched = 0;
  bool _loading = true;
  bool _deleting = false;
  bool _appendFailed = false;
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
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool append = false}) async {
    _searchTimer?.cancel();
    final request = ++_request;
    final collection = _collection;
    setState(() {
      _loading = true;
      _error = null;
      _appendFailed = false;
    });
    try {
      final result = await _recipePage(widget.api, {
        'collection': ?collection,
        'q': _query,
        'sort': _sort,
        'offset': '${append ? _recipes.length : 0}',
        'limit': '$_pageSize',
        ..._filters.parameters,
      });
      if (!mounted || request != _request) return;
      setState(() {
        if (!append) _recipes.clear();
        _recipes.addAll(objects(result['items']));
        _total = result['total'] as int;
        _matched = result['match_total'] as int;
      });
    } on Exception catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _appendFailed = append;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _search(String value) {
    final query = value.trim();
    if (query == _query) return;
    _searchTimer?.cancel();
    // Invalidate requests immediately, including a page that is still loading.
    _request++;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 300), _fetch);
  }

  Future<void> _chooseFilters() async {
    final compact = MediaQuery.sizeOf(context).width < 600;
    Widget editor(BuildContext _) => _FilterDialog(
      api: widget.api,
      collection: _collection,
      initial: _filters,
      asSheet: compact,
    );
    final filters = compact
        ? await showModalBottomSheet<_Filters>(
            context: context,
            builder: editor,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
          )
        : await showDialog<_Filters>(context: context, builder: editor);
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
          onSync: widget.onSync,
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

  Future<void> _chooseSort() async {
    final sort = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: AppSpacing.panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sortieren', style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.related),
              for (final option in _sorts.entries)
                ListTile(
                  title: Text(option.value),
                  selected: option.key == _sort,
                  trailing: option.key == _sort
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(sheet, option.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (sort == null || !mounted || sort == _sort) return;
    _sort = sort;
    await _fetch();
  }

  Widget _searchInput() => TextField(
    controller: _searchField,
    focusNode: widget.searchFocus,
    maxLength: 200,
    onChanged: _search,
    onSubmitted: (_) {
      if (_searchTimer?.isActive == true || _error != null) {
        unawaited(_fetch());
      }
    },
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      labelText: 'Titel oder Zutaten suchen',
      prefixIcon: const Icon(Icons.search),
      counterText: '',
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: 'Suche leeren',
              onPressed: () {
                _searchField.clear();
                _search('');
              },
              icon: const Icon(Icons.close),
            ),
    ),
  );

  Widget _controls() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.item,
    children: [
      Text(
        text(widget.collection?['name'], 'Alle Rezepte'),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      if (_collection == null)
        Card(
          child: Padding(
            padding: AppSpacing.compactPanel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppSpacing.related,
              children: [
                _searchInput(),
                Wrap(
                  spacing: AppSpacing.related,
                  runSpacing: AppSpacing.related,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _chooseSort,
                      icon: const Icon(Icons.sort),
                      label: Text(_sorts[_sort]!),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _chooseFilters,
                      icon: const Icon(Icons.filter_list),
                      label: Text(
                        _filters.active ? 'Filter bearbeiten' : 'Filtern',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
      else
        _searchInput(),
      if (_local)
        Wrap(
          spacing: AppSpacing.related,
          runSpacing: AppSpacing.related,
          children: [
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
        ),
      if (_filters.active)
        Wrap(
          spacing: AppSpacing.related,
          runSpacing: AppSpacing.related,
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
          onPressed: () => _fetch(append: _appendFailed),
          child: const Text('Erneut laden'),
        ),
      ] else if (!_loading || _recipes.isNotEmpty)
        Text(
          _collection != null && (_filters.active || _query.isNotEmpty)
              ? '$_matched von $_total Rezepten passen zum Filter'
              : '$_total ${_total == 1 ? 'Rezept' : 'Rezepte'}',
        ),
      if (_recipes.isEmpty && !_loading && _error == null)
        const Text('Keine passenden Rezepte gefunden.'),
    ],
  );

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () async {
      await widget.onSync?.call();
      if (mounted) await _fetch();
    },
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: AppSpacing.page,
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.section),
                  child: _controls(),
                ),
              ),
              if (_loading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              _RecipeGrid(
                api: widget.api,
                recipes: _recipes,
                openRecipe: _open,
              ),
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
      const gap = AppSpacing.item;
      final compact =
          MediaQuery.sizeOf(context).width < 600 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.25;
      final minimum = compact ? 144 : 182;
      final columns = ((constraints.crossAxisExtent + gap) / (minimum + gap))
          .floor()
          .clamp(1, 5);
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
              spacing: gap,
              children: [
                for (final recipe in row)
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
    required this.asSheet,
  });
  final RezeptgartenApi api;
  final String? collection;
  final _Filters initial;
  final bool asSheet;

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const title = Text('Rezepte filtern');
    final form = Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.item,
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
          if (ingredients.isNotEmpty)
            Wrap(
              spacing: AppSpacing.related,
              runSpacing: AppSpacing.related,
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
    );
    final actions = [
      TextButton(
        onPressed: () => Navigator.pop(context, const _Filters()),
        child: const Text('Zurücksetzen'),
      ),
      FilledButton(onPressed: _apply, child: const Text('Anwenden')),
    ];
    if (!widget.asSheet) {
      return AlertDialog(
        title: title,
        scrollable: true,
        content: form,
        actions: actions,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.section,
            0,
            AppSpacing.section,
            AppSpacing.section,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpacing.section,
            children: [
              DefaultTextStyle(
                style: theme.textTheme.titleLarge!,
                child: title,
              ),
              form,
              OverflowBar(
                spacing: AppSpacing.related,
                overflowSpacing: AppSpacing.related,
                alignment: MainAxisAlignment.end,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Candidates extends StatefulWidget {
  const _Candidates({
    required this.api,
    required this.collection,
    required this.query,
    required this.filters,
    required this.openRecipe,
    this.onSync,
  });
  final RezeptgartenApi api;
  final String collection;
  final String query;
  final _Filters filters;
  final OpenRecipe openRecipe;
  final Future<void> Function()? onSync;

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
      child: RefreshIndicator(
        onRefresh: () async {
          if (_adding) return;
          await widget.onSync?.call();
          if (mounted) await _load();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.page,
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
            const SizedBox(height: AppSpacing.section),
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
    ),
  );
}

class RecipeCollections extends StatefulWidget {
  const RecipeCollections({
    super.key,
    required this.api,
    required this.openRecipe,
    this.refreshCount = 0,
    this.onSync,
  });
  final RezeptgartenApi api;
  final OpenRecipe openRecipe;
  final int refreshCount;
  final Future<void> Function()? onSync;

  @override
  State<RecipeCollections> createState() => _RecipeCollectionsState();
}

class _RecipeCollectionsState extends State<RecipeCollections> {
  late Future<dynamic> _lists = widget.api.get('/api/collections');
  bool _creating = false;
  String _query = '';

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
              onSync: widget.onSync,
            ),
          ),
        ),
      ),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _lists,
    builder: (context, snapshot) {
      final result = snapshot.data;
      final lists = objects(result is Json ? result['items'] : null)
          .where((list) => text(list['name']).toLowerCase().contains(_query));
      return RefreshIndicator(
        onRefresh: () async {
          await widget.onSync?.call();
          if (mounted) await _reload();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.page,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.section,
              children: [
                Text(
                  'Deine Rezeptlisten',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                TextField(
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    labelText: 'Listen suchen',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('Neue Liste'),
                  ),
                ),
                if (_creating ||
                    snapshot.connectionState != ConnectionState.done)
                  const LinearProgressIndicator(),
                if (snapshot.hasError) ...[
                  Text(snapshot.error.toString()),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Erneut laden'),
                  ),
                ] else if (snapshot.hasData) ...[
                  if (lists.isEmpty)
                    const Text('Keine passenden Listen gefunden.'),
                  for (final list in lists)
                    _CollectionPreview(
                      key: ValueKey(list['id']),
                      api: widget.api,
                      list: list,
                      refreshCount: widget.refreshCount,
                      onOpen: () => _open(list),
                      onRecipe: widget.openRecipe,
                    ),
                ],
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _CollectionPreview extends StatefulWidget {
  const _CollectionPreview({
    super.key,
    required this.api,
    required this.list,
    required this.refreshCount,
    required this.onOpen,
    required this.onRecipe,
  });

  final RezeptgartenApi api;
  final Json list;
  final int refreshCount;
  final VoidCallback onOpen;
  final OpenRecipe onRecipe;

  @override
  State<_CollectionPreview> createState() => _CollectionPreviewState();
}

class _CollectionPreviewState extends State<_CollectionPreview> {
  Future<Json>? _items;

  void _load() {
    setState(() {
      _items = _recipePage(widget.api, {
        'collection': text(widget.list['id']),
        'limit': '12',
      });
    });
  }

  @override
  void didUpdateWidget(_CollectionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_items != null &&
        (oldWidget.refreshCount != widget.refreshCount ||
            oldWidget.list['recipe_count'] != widget.list['recipe_count'])) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(text(widget.list['name'])),
    onExpansionChanged: (expanded) {
      if (expanded && _items == null) _load();
    },
    children: [
      FutureBuilder<Json>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: _load,
              child: const Text('Erneut laden'),
            );
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final recipes = objects(snapshot.requireData['items']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (recipes.isEmpty)
                const ListTile(title: Text('Keine Rezepte in dieser Liste.')),
              for (final recipe in recipes)
                ListTile(
                  title: Text(text(recipe['name'])),
                  onTap: () => widget.onRecipe(recipe),
                ),
            ],
          );
        },
      ),
      TextButton(onPressed: widget.onOpen, child: const Text('Liste öffnen')),
    ],
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
