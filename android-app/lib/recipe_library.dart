import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'pill_widgets.dart';
import 'expandable_list_card.dart';
import 'spacing.dart';
import 'recipe_card.dart';
import 'symbol_field.dart';

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
    this.onCollectionChanged,
    this.recipeRevision,
  });

  final RezeptgartenApi api;
  final OpenRecipe openRecipe;
  final Json? collection;
  final int refreshCount;
  final FocusNode? searchFocus;
  final Future<void> Function()? onSync;
  final VoidCallback? onCollectionChanged;
  final int Function()? recipeRevision;

  @override
  State<RecipeBrowser> createState() => _RecipeBrowserState();
}

enum _RecipeLoad { first, moreRecipes, moreAvailable }

class _RecipeBrowserState extends State<RecipeBrowser>
    with SingleTickerProviderStateMixin<RecipeBrowser> {
  static const _pageSize = 48;
  static const _searchActionStyle = ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.all(AppSpacing.related)),
  );
  final _recipes = <Json>[];
  final _available = <Json>[];
  final _searchField = TextEditingController();
  late final _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Timer? _searchTimer;
  int _request = 0;
  String _query = '';
  String _sort = 'name';
  _Filters _filters = const _Filters();
  int _total = 0;
  int _matched = 0;
  bool _loading = true;
  bool _saving = false;
  bool _removing = false;
  int _availableTotal = 0;
  _RecipeLoad _retry = _RecipeLoad.first;
  String? _error;

  late Json? _collectionDetails = widget.collection;
  String? get _collection => widget.collection?['id'] as String?;
  bool get _local => widget.collection?['kind'] == 'local';

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWiggle();
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
    _wiggle.dispose();
    super.dispose();
  }

  void _updateWiggle() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_removing && _recipes.isNotEmpty && !reduceMotion) {
      if (!_wiggle.isAnimating) _wiggle.repeat();
    } else if (_wiggle.isAnimating) {
      _wiggle.reset();
    }
  }

  void _toggleRemoving() {
    setState(() => _removing = !_removing);
    _updateWiggle();
  }

  Future<Json> _loadPage({required bool available, required int offset}) =>
      _recipePage(widget.api, {
        if (available) 'exclude_collection': _collection!,
        if (!available) 'collection': ?_collection,
        'q': _query,
        'sort': _sort,
        'offset': '$offset',
        'limit': '${_local && !available ? 12 : _pageSize}',
        ..._filters.parameters,
      });

  Future<void> _fetch([_RecipeLoad load = _RecipeLoad.first]) async {
    _searchTimer?.cancel();
    final request = ++_request;
    final first = load == _RecipeLoad.first;
    setState(() {
      _loading = true;
      _error = null;
    });
    Future<void> loadPage({required bool available}) async {
      final items = available ? _available : _recipes;
      final result = await _loadPage(
        available: available,
        offset: first ? 0 : items.length,
      );
      if (!mounted || request != _request) return;
      setState(() {
        if (first) items.clear();
        items.addAll(objects(result['items']));
        if (available) {
          _availableTotal = result['total'] as int;
        } else {
          _total = result['total'] as int;
          _matched = result['match_total'] as int;
        }
      });
      _updateWiggle();
    }

    try {
      await Future.wait<void>([
        if (load != _RecipeLoad.moreAvailable) loadPage(available: false),
        if (_local && load != _RecipeLoad.moreRecipes)
          loadPage(available: true),
      ]);
    } on Exception catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _retry = load;
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

  Future<void> _setMembership(Json recipe, {required bool present}) async {
    if (_saving || _loading || _error != null) return;
    setState(() => _saving = true);
    try {
      final list = Uri.encodeComponent(_collection!);
      final id = Uri.encodeComponent(text(recipe['id']));
      await widget.api.write(
        'PUT',
        '/api/local-collections/$list/recipes/$id',
        {'present': present},
      );
      if (!mounted) return;
      widget.onCollectionChanged?.call();
      await _fetch();
      if (mounted) {
        final name = text(recipe['name']);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              present
                  ? '$name zur Liste hinzugefügt.'
                  : '$name aus der Liste entfernt.',
            ),
          ),
        );
      }
    } on Exception catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeCollection() async {
    if (_saving) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Liste löschen?'),
        content: Text(
          '„${_collectionDetails!['name']}“ und ihre Zuordnungen werden gelöscht. Die Rezepte bleiben erhalten.',
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
    if (confirm != true || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.api.write(
        'DELETE',
        '/api/local-collections/${Uri.encodeComponent(_collection!)}',
      );
      if (mounted) {
        widget.onCollectionChanged?.call();
        Navigator.of(context).pop();
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(context, error);
    }
  }

  Future<void> _open(Json recipe) async {
    if (_saving) return;
    final revision = widget.recipeRevision?.call();
    await widget.openRecipe(recipe);
    if (mounted && revision != widget.recipeRevision?.call()) await _fetch();
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

  Future<void> _editCollection() async {
    final details = await showDialog<Json>(
      context: context,
      builder: (_) => _CollectionNameDialog(collection: _collectionDetails),
    );
    if (details == null || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.api.write(
        'PUT',
        '/api/local-collections/${Uri.encodeComponent(_collection!)}',
        details,
      );
      if (!mounted) return;
      setState(() => _collectionDetails = {..._collectionDetails!, ...details});
      widget.onCollectionChanged?.call();
    } on Exception catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _searchInput() => TextField(
    controller: _searchField,
    enabled: !_saving,
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
      SymbolLabel(
        text(_collectionDetails?['name'], 'Alle Rezepte'),
        _collectionDetails?['icon'],
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
                IntrinsicHeight(
                  child: Row(
                    spacing: AppSpacing.related,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _chooseSort,
                          style: _searchActionStyle,
                          icon: const Icon(Icons.sort),
                          label: Text(
                            _sorts[_sort]!,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _chooseFilters,
                          style: _searchActionStyle,
                          icon: const Icon(Icons.filter_list),
                          label: Text(
                            _filters.active ? 'Filter bearbeiten' : 'Filtern',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
      else
        _searchInput(),
      if (_filters.active)
        Wrap(
          spacing: AppSpacing.related,
          runSpacing: AppSpacing.tight,
          children: [
            for (final ingredient in _filters.ingredients) InfoPill(ingredient),
            if (_filters.servings case final int servings)
              InfoPill('Ab $servings Portionen'),
            if (_filters.minutes case final int minutes)
              InfoPill('Bis $minutes Min.'),
          ],
        ),
      if (_error != null) ...[
        Text(_error!),
        OutlinedButton(
          onPressed: _saving ? null : () => _fetch(_retry),
          child: const Text('Erneut laden'),
        ),
      ] else if (!_local && (!_loading || _recipes.isNotEmpty))
        Text(
          _collection != null && (_filters.active || _query.isNotEmpty)
              ? '$_matched von $_total Rezepten passen zum Filter'
              : '$_total ${_total == 1 ? 'Rezept' : 'Rezepte'}',
        ),
      if (_local)
        Text('Alle Rezepte', style: Theme.of(context).textTheme.titleLarge),
      if (_recipes.isEmpty && _available.isEmpty && !_loading && _error == null)
        const Text('Keine passenden Rezepte gefunden.'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    if (!_local) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezeptlisten'),
        actions: [
          IconButton(
            tooltip: 'Name und Symbol bearbeiten',
            onPressed: _saving ? null : _editCollection,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Liste löschen',
            onPressed: _saving ? null : _removeCollection,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildContent() => RefreshIndicator(
    onRefresh: () async {
      if (_saving) return;
      await widget.onSync?.call();
      if (mounted && !_saving) await _fetch();
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
              if (_loading || _saving)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (_local && (_recipes.isNotEmpty || _removing))
                _membershipHeading(),
              _RecipeGrid(
                api: widget.api,
                recipes: _recipes,
                openRecipe: _removing ? null : _open,
                wiggle: _local ? _wiggle : null,
                cornerAction: _removing
                    ? (recipe) => RecipeCornerAction(
                        tooltip:
                            '${text(recipe['name'])} aus der Liste entfernen',
                        icon: Icons.close,
                        onPressed: _saving || _loading || _error != null
                            ? null
                            : () => _setMembership(recipe, present: false),
                      )
                    : null,
              ),
              if (!_loading && _error == null && _recipes.length < _total)
                SliverToBoxAdapter(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _fetch(_RecipeLoad.moreRecipes),
                    child: Text(
                      _local
                          ? 'Weitere aus dieser Liste laden'
                          : 'Weitere Rezepte laden',
                    ),
                  ),
                ),
              if (_available.isNotEmpty) ...[
                _sectionHeading('Zum Hinzufügen'),
                _RecipeGrid(
                  api: widget.api,
                  recipes: _available,
                  openRecipe: _open,
                  cornerAction: (recipe) => RecipeCornerAction(
                    tooltip: '${text(recipe['name'])} zur Liste hinzufügen',
                    icon: Icons.add,
                    onPressed: _saving || _loading || _error != null
                        ? null
                        : () => _setMembership(recipe, present: true),
                  ),
                ),
                if (!_loading &&
                    _error == null &&
                    _available.length < _availableTotal)
                  SliverToBoxAdapter(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _fetch(_RecipeLoad.moreAvailable),
                      child: const Text('Weitere zum Hinzufügen laden'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _membershipHeading() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.related),
      child: Row(
        spacing: AppSpacing.related,
        children: [
          Expanded(
            child: Text(
              'In dieser Liste',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton.filledTonal(
            tooltip: _removing ? 'Fertig' : 'Rezepte entfernen',
            onPressed: _saving ? null : _toggleRemoving,
            icon: Icon(_removing ? Icons.check : Icons.delete_outline),
          ),
        ],
      ),
    ),
  );

  Widget _sectionHeading(String label) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.related),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
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
    this.cornerAction,
    this.wiggle,
  });
  final RezeptgartenApi api;
  final List<Json> recipes;
  final OpenRecipe? openRecipe;
  final RecipeCornerAction Function(Json recipe)? cornerAction;
  final Animation<double>? wiggle;

  Widget _rotateCard(Widget card, int column) {
    final animation = wiggle;
    if (animation == null) return card;
    final direction = column.isEven ? 1 : -1;
    return AnimatedBuilder(
      animation: animation,
      child: card,
      builder: (context, child) => Transform.rotate(
        angle: math.sin(animation.value * 2 * math.pi) * 0.025 * direction,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
    builder: (context, constraints) {
      final open = openRecipe;
      const gap = AppSpacing.item;
      final (:columns, :width) = recipeGridLayout(
        context,
        constraints.crossAxisExtent,
      );
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
                for (final (column, recipe) in row.indexed)
                  SizedBox(
                    key: ValueKey(recipe['id']),
                    width: width,
                    child: Opacity(
                      opacity: recipe['matches'] == false ? 0.48 : 1,
                      child: _rotateCard(
                        RecipeCard(
                          api: api,
                          recipe: recipe,
                          onTap: open == null ? null : () => open(recipe),
                          cornerAction: cornerAction?.call(recipe),
                        ),
                        column,
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

class RecipeCollections extends StatefulWidget {
  const RecipeCollections({
    super.key,
    required this.api,
    required this.openRecipe,
    this.active = true,
    this.refreshCount = 0,
    this.onSync,
    this.onChanged,
    this.recipeRevision,
    this.onManageClosed,
  });
  final RezeptgartenApi api;
  final OpenRecipe openRecipe;
  final bool active;
  final int refreshCount;
  final Future<void> Function()? onSync;
  final VoidCallback? onChanged;
  final int Function()? recipeRevision;
  final Future<void> Function(bool changed)? onManageClosed;

  @override
  State<RecipeCollections> createState() => _RecipeCollectionsState();
}

class _RecipeCollectionsState extends State<RecipeCollections>
    with SingleTickerProviderStateMixin {
  static const _preferences = MethodChannel('de.rezeptgarten/preferences');
  late Future<dynamic> _lists = widget.api.get('/api/collections');
  Json? _lastLists;
  final _searchField = TextEditingController();
  late final _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 390),
  );
  List<String> _listOrder = [];
  bool _orderLoaded = false;
  bool _sorting = false;
  bool _creating = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_restoreOrder());
  }

  Future<void> _restoreOrder() async {
    try {
      final saved = await _preferences.invokeMethod<String>(
        'collectionOrder',
        widget.api.usesTestData,
      );
      if (saved != null) {
        final order = jsonDecode(saved);
        if (order is List) _listOrder = order.whereType<String>().toList();
      }
    } on Exception {
      // The server's original order is the default.
    }
    if (mounted) setState(() => _orderLoaded = true);
  }

  void _setSorting(bool sorting) {
    if (_sorting == sorting) return;
    if (sorting) FocusScope.of(context).unfocus();
    setState(() => _sorting = sorting);
    _updateWiggle();
  }

  void _updateWiggle() {
    if (_sorting && !MediaQuery.disableAnimationsOf(context)) {
      if (!_wiggle.isAnimating) _wiggle.repeat();
    } else if (_wiggle.isAnimating) {
      _wiggle.reset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateWiggle();
  }

  Future<void> _reorder(
    List<Json> all,
    List<Json> visible,
    int from,
    int to,
  ) async {
    if (from == to) return;
    final reordered = List<Json>.of(visible);
    reordered.insert(to, reordered.removeAt(from));
    final visibleIds = visible.map((list) => list['id']).toSet();
    final remaining = reordered.iterator;
    setState(() {
      _listOrder = [
        for (final list in all)
          if (visibleIds.contains(list['id']))
            (remaining..moveNext()).current['id'] as String
          else
            list['id'] as String,
      ];
    });
    try {
      await _preferences.invokeMethod<void>('setCollectionOrder', {
        'order': jsonEncode(_listOrder),
        'debug': widget.api.usesTestData,
      });
    } on Exception {
      if (mounted) {
        _showError(
          context,
          const ApiException(
            'Die Listenreihenfolge konnte nicht gespeichert werden.',
          ),
        );
      }
    }
  }

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
    if (!widget.active) _setSorting(false);
    if (oldWidget.refreshCount != widget.refreshCount) unawaited(_reload());
  }

  @override
  void dispose() {
    _wiggle.dispose();
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating) return;
    final details = await showDialog<Json>(
      context: context,
      builder: (_) => const _CollectionNameDialog(),
    );
    if (details == null || !mounted || _creating) return;
    setState(() => _creating = true);
    try {
      await widget.api.write('POST', '/api/local-collections', details);
      if (mounted) {
        widget.onChanged?.call();
        await _reload();
      }
    } on Exception catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _open(Json list) async {
    var changed = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecipeBrowser(
          api: widget.api,
          openRecipe: widget.openRecipe,
          collection: list,
          onSync: widget.onSync,
          recipeRevision: widget.recipeRevision,
          onCollectionChanged: () {
            changed = true;
            widget.onChanged?.call();
          },
        ),
      ),
    );
    if (!mounted) return;
    if (widget.onManageClosed case final notify?) {
      await notify(changed);
    } else if (changed) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _lists,
    builder: (context, snapshot) {
      if (snapshot.data case final Json result) _lastLists = result;
      final byId = {
        for (final list in objects(_lastLists?['items'])) list['id']: list,
      };
      final ordered = [
        for (final id in _listOrder) ?byId.remove(id),
        ...byId.values,
      ];
      final lists = ordered
          .where((list) => text(list['name']).toLowerCase().contains(_query))
          .toList();
      return RefreshIndicator(
        onRefresh: () async {
          await widget.onSync?.call();
          if (mounted) await _reload();
        },
        child: ReorderableListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.page,
          buildDefaultDragHandles: false,
          onReorderStart: (_) => _setSorting(true),
          onReorderItem: (from, to) => _reorder(ordered, lists, from, to),
          itemCount: lists.length,
          header: Padding(
            padding: EdgeInsets.only(
              bottom: lists.isEmpty ? 0 : AppSpacing.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.section,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Deine Rezeptlisten',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (_sorting)
                      IconButton(
                        tooltip: 'Reihenfolge fertig',
                        onPressed: () => _setSorting(false),
                        icon: const Icon(Icons.check),
                      ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _creating ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'Neue Liste',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                TextField(
                  controller: _searchField,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    labelText: 'Listen suchen',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Suche leeren',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchField.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                if (_creating ||
                    (_lastLists == null &&
                        snapshot.connectionState != ConnectionState.done))
                  const LinearProgressIndicator(),
                if (snapshot.hasError) ...[
                  Text(snapshot.error.toString()),
                  TextButton(
                    onPressed: _reload,
                    child: const Text('Erneut laden'),
                  ),
                ] else if (snapshot.hasData && lists.isEmpty)
                  const Text('Keine passenden Listen gefunden.'),
              ],
            ),
          ),
          itemBuilder: (context, index) {
            final list = lists[index];
            return Padding(
              key: ValueKey(list['id']),
              padding: const EdgeInsets.only(bottom: AppSpacing.section),
              child: AnimatedBuilder(
                animation: _wiggle,
                child: _CollectionPreview(
                  api: widget.api,
                  list: list,
                  refreshCount: widget.refreshCount,
                  dragIndex: _orderLoaded && lists.length > 1 ? index : null,
                  sorting: _sorting,
                  onManage: list['kind'] == 'local' ? () => _open(list) : null,
                  onRecipe: widget.openRecipe,
                ),
                builder: (context, child) => Transform.rotate(
                  angle:
                      math.sin(_wiggle.value * 2 * math.pi) *
                      (index.isEven ? 0.008 : -0.008),
                  child: child,
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _CollectionPreview extends StatefulWidget {
  const _CollectionPreview({
    required this.api,
    required this.list,
    required this.refreshCount,
    required this.onManage,
    required this.onRecipe,
    this.dragIndex,
    this.sorting = false,
  });

  final RezeptgartenApi api;
  final Json list;
  final int refreshCount;
  final VoidCallback? onManage;
  final OpenRecipe onRecipe;
  final int? dragIndex;
  final bool sorting;

  @override
  State<_CollectionPreview> createState() => _CollectionPreviewState();
}

class _CollectionPreviewState extends State<_CollectionPreview> {
  static const _links = MethodChannel('de.rezeptgarten/links');

  Future<void> _openCookidoo(String url) async {
    try {
      await _links.invokeMethod<void>('openCookidoo', url);
    } on Exception {
      if (mounted) {
        _showError(
          context,
          const ApiException('Cookidoo konnte nicht geöffnet werden.'),
        );
      }
    }
  }

  Widget _dragTitle(Widget label) {
    final index = widget.dragIndex;
    if (index == null) return label;
    return widget.sorting
        ? ReorderableDragStartListener(index: index, child: label)
        : ReorderableDelayedDragStartListener(index: index, child: label);
  }

  final _items = <Json>[];
  int _request = 0;
  int? _total;
  bool _loading = false;
  bool _retryAppend = false;
  String? _error;

  Future<void> _load({bool append = false}) async {
    if (append && _loading) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _recipePage(widget.api, {
        'collection': text(widget.list['id']),
        'limit': '12',
        'offset': '${append ? _items.length : 0}',
      });
      if (!mounted || request != _request) return;
      setState(() {
        if (!append) _items.clear();
        _items.addAll(objects(result['items']));
        _total = result['total'] as int;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _retryAppend = append;
        _error = error.toString();
      });
    }
  }

  @override
  void didUpdateWidget(_CollectionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_request > 0 &&
        (oldWidget.refreshCount != widget.refreshCount ||
            oldWidget.list['recipe_count'] != widget.list['recipe_count'])) {
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) => ExpandableListCard(
    title: text(widget.list['name']),
    leading: _dragTitle(
      widget.sorting
          ? const Icon(Icons.drag_handle)
          : widget.list['icon'] is String
          ? ExcludeSemantics(child: Text(widget.list['icon'] as String))
          : const Icon(Icons.list_alt),
    ),
    wrapTitle: _dragTitle,
    action: switch ((widget.onManage, widget.list['source_url'])) {
      (final manage?, _) => IconButton(
        tooltip: 'Liste verwalten',
        onPressed: manage,
        icon: const Icon(Icons.edit_outlined),
      ),
      (_, final String url) => IconButton(
        tooltip: 'Zu Cookidoo',
        onPressed: () => _openCookidoo(url),
        icon: const Icon(Icons.open_in_new),
      ),
      _ => null,
    },
    onExpansionChanged: (expanded) {
      if (expanded && _total == null && !_loading) unawaited(_load());
    },
    body: Padding(padding: AppSpacing.compactPanel, child: _recipeRows()),
  );

  Widget _recipeRows() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.related,
    children: [
      if (_items.isNotEmpty)
        RecipePreviewGrid(
          api: widget.api,
          recipes: _items,
          onOpen: widget.onRecipe,
        ),
      if (_loading && _total == null)
        const LinearProgressIndicator()
      else if (_error case final String error) ...[
        Text(error),
        TextButton(
          onPressed: () => _load(append: _retryAppend),
          child: const Text('Erneut laden'),
        ),
      ] else if (_total case final int total)
        if (total == 0)
          const Text('Keine Rezepte in dieser Liste.')
        else if (_items.length < total)
          TextButton(
            onPressed: _loading ? null : () => _load(append: true),
            child: const Text('Weitere Rezepte laden'),
          ),
    ],
  );
}

class _CollectionNameDialog extends StatefulWidget {
  const _CollectionNameDialog({this.collection});
  final Json? collection;
  @override
  State<_CollectionNameDialog> createState() => _CollectionNameDialogState();
}

class _CollectionNameDialogState extends State<_CollectionNameDialog> {
  late String name = text(widget.collection?['name']);
  late String? symbol = widget.collection?['icon'] as String?;

  void _submit() {
    if (name.isNotEmpty && name.runes.length <= 100) {
      Navigator.pop(context, <String, dynamic>{'name': name, 'icon': symbol});
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.collection == null ? 'Neue lokale Liste' : 'Liste bearbeiten',
    ),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.item,
      children: [
        TextFormField(
          initialValue: name,
          autofocus: true,
          maxLength: 100,
          onChanged: (value) => setState(() => name = value.trim()),
          onFieldSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Listenname'),
        ),
        SymbolField(
          value: symbol,
          onChanged: (value) => setState(() => symbol = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: name.isEmpty ? null : _submit,
        child: Text(widget.collection == null ? 'Anlegen' : 'Speichern'),
      ),
    ],
  );
}

void _showError(BuildContext context, Exception error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error.toString())));
}
