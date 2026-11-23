import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'spacing.dart';
import 'ingredient_icon.dart';
import 'symbol_field.dart';
import 'expandable_list_card.dart';

class PantryView extends StatefulWidget {
  const PantryView({
    super.key,
    required this.api,
    required this.expandedCategories,
    this.refreshCount = 0,
    this.onSync,
    this.onChanged,
  });

  final RezeptgartenApi api;
  final Set<int> expandedCategories;
  final int refreshCount;
  final Future<void> Function()? onSync;
  final VoidCallback? onChanged;

  @override
  State<PantryView> createState() => _PantryViewState();
}

class _PantryViewState extends State<PantryView> {
  final _searchField = TextEditingController();
  List<Json> _categories = [];
  List<Json> _items = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _loaded = false;
  bool _writing = false;
  int _request = 0;
  int _expansionVersion = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PantryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshCount != oldWidget.refreshCount && !_writing) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.get('/api/pantry') as Json;
      if (!mounted || request != _request) return;
      setState(() {
        _loaded = true;
        _categories = objects(result['categories']);
        _items = objects(result['items']);
        final categoryIds = {for (final category in _categories) category['id']};
        widget.expandedCategories.retainAll(categoryIds);
      });
    } on Exception catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _change(String method, String path, [Json? body]) async {
    if (_writing || _loading) return;
    setState(() => _writing = true);
    try {
      await widget.api.write(method, path, body);
      if (mounted) widget.onChanged?.call();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _writing = false);
      }
    }
  }

  Future<void> _edit({
    bool newCategory = false,
    int? categoryId,
    Json? item,
    Json? category,
  }) async {
    if (_writing || _loading) return;
    final categoryEditor = newCategory || category != null;
    if (!categoryEditor && _categories.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PantryEditor(
        api: widget.api,
        categories: categoryEditor ? null : _categories,
        categoryId: categoryId,
        item: item,
        category: category,
      ),
    );
    if (saved == true && mounted) {
      widget.onChanged?.call();
      await _load();
    }
  }

  Future<void> _removeCategory(Json category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Kategorie löschen?'),
        content: Text(
          '„${category['name']}“ und alle Zutaten in dieser Kategorie werden gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Kategorie löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _change('DELETE', '/api/pantry/categories/${category['id']}');
  }

  void _reorder(int from, int to) {
    if (_loading || _writing || _query.isNotEmpty || from == to) return;
    final categories = [..._categories];
    categories.insert(to, categories.removeAt(from));
    setState(() => _categories = categories);
    unawaited(
      _change('PUT', '/api/pantry/categories/order', {
        'category_ids': categories.map((category) => category['id']).toList(),
      }),
    );
  }

  void _expandAll(bool expand) {
    setState(() {
      widget.expandedCategories.clear();
      if (expand) {
        widget.expandedCategories.addAll(
          _categories.map((category) => category['id'] as int),
        );
      }
      ++_expansionVersion;
    });
  }

  Widget _toolbar(bool enabled) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppSpacing.item,
    children: [
      Row(
        spacing: AppSpacing.related,
        children: [
          Expanded(
            child: Text(
              'Mein Vorrat',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          if (_categories.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Vorratsaktionen',
              onSelected: (action) {
                if (action == 'new') {
                  unawaited(_edit(newCategory: true));
                } else {
                  _expandAll(action == 'expand');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: enabled,
                  value: 'new',
                  child: const Text('Neue Kategorie'),
                ),
                PopupMenuItem(
                  enabled: _query.isEmpty,
                  value: 'collapse',
                  child: const Text('Alle einklappen'),
                ),
                PopupMenuItem(
                  enabled: _query.isEmpty,
                  value: 'expand',
                  child: const Text('Alle ausklappen'),
                ),
              ],
            ),
        ],
      ),
      if (_categories.isNotEmpty)
        TextField(
          controller: _searchField,
          maxLength: 100,
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          decoration: InputDecoration(
            labelText: 'Vorrat durchsuchen',
            prefixIcon: const Icon(Icons.search),
            counterText: '',
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
      FilledButton.icon(
        onPressed: enabled
            ? () => _edit(newCategory: _categories.isEmpty)
            : null,
        icon: const Icon(Icons.add),
        label: Text(
          _categories.isEmpty ? 'Neue Kategorie' : 'Zutat hinzufügen',
        ),
      ),
      if ((_loading && !_loaded) || _writing) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Erneut laden')),
      ],
      if (_loaded && _error == null && _categories.isEmpty)
        const Text('Lege eine Kategorie an, um Zutaten einzutragen.'),
    ],
  );

  Widget _category(Json category, List<Json> items, int index, bool enabled) {
    const iconWidth = 36.0;
    final id = category['id'] as int;
    final name = text(category['name']);
    final symbol = category['icon'] as String?;
    final categoryIcon = symbol == null
        ? null
        : Center(heightFactor: 1, child: ExcludeSemantics(child: Text(symbol)));
    return Padding(
      key: ValueKey(id),
      padding: const EdgeInsets.only(bottom: AppSpacing.item),
      child: ListTileTheme.merge(
        minLeadingWidth: iconWidth,
        horizontalTitleGap: AppSpacing.related,
        titleAlignment: ListTileTitleAlignment.center,
        child: ExpandableListCard(
          title: name,
          expansionKey: ValueKey((id, _expansionVersion, _query.isNotEmpty)),
          initiallyExpanded:
              _query.isNotEmpty || widget.expandedCategories.contains(id),
          onExpansionChanged: (expanded) {
            if (_query.isNotEmpty) return;
            if (expanded) {
              widget.expandedCategories.add(id);
            } else {
              widget.expandedCategories.remove(id);
            }
          },
          leading: SizedBox(
            width: iconWidth,
            child: _query.isEmpty
                ? ReorderableDragStartListener(
                    index: index,
                    enabled: enabled,
                    child: Semantics(
                      label: '$name verschieben',
                      child: categoryIcon ?? const Icon(Icons.drag_handle),
                    ),
                  )
                : categoryIcon,
          ),
          action: PopupMenuButton<String>(
            enabled: enabled,
            tooltip: 'Aktionen für $name',
            onSelected: (value) {
              if (value == 'add') {
                unawaited(_edit(categoryId: id));
              } else if (value == 'edit') {
                unawaited(_edit(category: category));
              } else {
                unawaited(_removeCategory(category));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'add', child: Text('Zutat hinzufügen')),
              PopupMenuItem(value: 'edit', child: Text('Kategorie bearbeiten')),
              PopupMenuItem(value: 'delete', child: Text('Kategorie löschen')),
            ],
          ),
          subtitle: Text('${items.length} Zutaten'),
          body: Column(
            children: [
              if (items.isEmpty)
                const ListTile(
                  leading: SizedBox(width: iconWidth),
                  title: Text('Noch keine Zutaten eingetragen.'),
                ),
              for (final item in items)
                ListTile(
                  dense: true,
                  leading: SizedBox(
                    width: iconWidth,
                    child: Center(
                      heightFactor: 1,
                      child: IngredientIcon(
                        text(item['name']),
                        category: name,
                        selected: item['icon'],
                      ),
                    ),
                  ),
                  title: Text(text(item['name'])),
                  subtitle: text(item['quantity']).isNotEmpty
                      ? Text(text(item['quantity']))
                      : null,
                  onTap: enabled ? () => _edit(item: item) : null,
                  trailing: IconButton(
                    tooltip: '${item['name']} entfernen',
                    onPressed: enabled
                        ? () => _change(
                            'DELETE',
                            '/api/pantry/items/${item['id']}',
                          )
                        : null,
                    icon: const Icon(Icons.close),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_writing && !_loading && _error == null;
    final itemsByCategory = <int, List<Json>>{};
    for (final item in _items) {
      if (text(item['name']).toLowerCase().contains(_query)) {
        (itemsByCategory[item['category_id'] as int] ??= []).add(item);
      }
    }
    final categories = _query.isEmpty
        ? _categories
        : _categories
              .where((category) => itemsByCategory.containsKey(category['id']))
              .toList();
    return RefreshIndicator(
      onRefresh: () async {
        if (_writing) return;
        await widget.onSync?.call();
        if (mounted) await _load();
      },
      child: ReorderableListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.page,
        header: Padding(
          padding: EdgeInsets.only(
            bottom: categories.isNotEmpty || _query.isNotEmpty
                ? AppSpacing.section
                : 0,
          ),
          child: _toolbar(enabled),
        ),
        footer: _query.isNotEmpty && categories.isEmpty
            ? const Text('Keine passenden Zutaten gefunden.')
            : null,
        buildDefaultDragHandles: false,
        onReorderItem: _reorder,
        itemCount: categories.length,
        itemBuilder: (_, index) {
          final category = categories[index];
          return _category(
            category,
            itemsByCategory[category['id']] ?? [],
            index,
            enabled,
          );
        },
      ),
    );
  }
}

class _PantryEditor extends StatefulWidget {
  const _PantryEditor({
    required this.api,
    this.categories,
    this.categoryId,
    this.item,
    this.category,
  });

  final RezeptgartenApi api;
  final List<Json>? categories;
  final int? categoryId;
  final Json? item;
  final Json? category;

  @override
  State<_PantryEditor> createState() => _PantryEditorState();
}

class _PantryEditorState extends State<_PantryEditor> {
  late final _name = TextEditingController(
    text: text((widget.item ?? widget.category)?['name']),
  );
  late String? _symbol = (widget.item ?? widget.category)?['icon'] as String?;
  late final _quantity = TextEditingController(
    text: text(widget.item?['quantity']),
  );
  late int? _ingredientId = widget.item?['ingredient_id'] as int?;
  late int? _categoryId =
      (widget.item?['category_id'] as int?) ??
      widget.categoryId ??
      (widget.categories?.first['id'] as int?);
  final _form = GlobalKey<FormState>();
  Timer? _timer;
  int _request = 0;
  bool _saving = false;
  String? _error;
  List<Json> _suggestions = [];

  bool get _newCategory => widget.categories == null;

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _search(String value) {
    _timer?.cancel();
    final request = ++_request;
    setState(() {
      _ingredientId = null;
      _suggestions = [];
    });
    final query = value.trim();
    if (query.isEmpty || query.runes.length > 100) return;
    _timer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final uri = Uri(
          path: '/api/ingredients/suggestions',
          queryParameters: {'q': query},
        );
        final result = await widget.api.get(uri.toString()) as Json;
        if (mounted && request == _request && !_saving) {
          setState(() => _suggestions = objects(result['items']));
        }
      } on Exception catch (error) {
        if (mounted && request == _request && !_saving) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    });
  }

  void _select(Json suggestion) {
    _timer?.cancel();
    ++_request;
    setState(() {
      _name.text = text(suggestion['name']);
      _ingredientId = suggestion['id'] as int;
      _suggestions = [];
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    _timer?.cancel();
    ++_request;
    setState(() {
      _saving = true;
      _error = null;
      _suggestions = [];
    });
    final name = _name.text.trim();
    try {
      if (_newCategory) {
        final id = widget.category?['id'];
        await widget.api.write(
          id == null ? 'POST' : 'PUT',
          id == null ? '/api/pantry/categories' : '/api/pantry/categories/$id',
          {'name': name, 'icon': _symbol},
        );
      } else {
        final id = widget.item?['id'];
        final body = {
          'name': name,
          'quantity': _quantity.text.trim(),
          'category_id': _categoryId,
          'ingredient_id': _ingredientId,
          'icon': _symbol,
        };
        await widget.api.write(
          id == null ? 'POST' : 'PUT',
          id == null ? '/api/pantry/items' : '/api/pantry/items/$id',
          body,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  String? _validateName(String? value) {
    final length = (value ?? '').trim().runes.length;
    if (length == 0) {
      return _newCategory
          ? 'Bitte gib einen Kategorienamen ein.'
          : 'Bitte gib einen Zutatennamen ein.';
    }
    return length > (_newCategory ? 60 : 100) ? 'Der Name ist zu lang.' : null;
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(
        _newCategory
            ? (widget.category == null
                  ? 'Neue Kategorie'
                  : 'Kategorie bearbeiten')
            : widget.item == null
            ? 'Zutat hinzufügen'
            : 'Zutat bearbeiten',
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.item,
          children: [
            TextFormField(
              autofocus: true,
              controller: _name,
              enabled: !_saving,
              maxLength: _newCategory ? 60 : 100,
              decoration: InputDecoration(
                labelText: _newCategory ? 'Kategoriename' : 'Zutat',
                counterText: '',
              ),
              validator: _validateName,
              onChanged: _newCategory ? null : _search,
              onFieldSubmitted: _newCategory ? (_) => _save() : null,
            ),
            SymbolField(
              value: _symbol,
              onChanged: _saving
                  ? null
                  : (symbol) => setState(() => _symbol = symbol),
            ),
            if (!_newCategory) ...[
              if (_suggestions.isNotEmpty)
                Wrap(
                  spacing: AppSpacing.related,
                  runSpacing: AppSpacing.related,
                  children: [
                    for (final suggestion in _suggestions)
                      ActionChip(
                        label: Text(text(suggestion['name'])),
                        onPressed: () => _select(suggestion),
                      ),
                  ],
                ),
              TextFormField(
                controller: _quantity,
                enabled: !_saving,
                maxLength: 80,
                validator: (value) => (value ?? '').trim().runes.length > 80
                    ? 'Die Mengenangabe ist zu lang.'
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Menge (optional)',
                  counterText: '',
                ),
              ),
              DropdownButtonFormField<int>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kategorie'),
                onChanged: _saving ? null : (id) => _categoryId = id,
                validator: (id) => id == null ? 'Wähle eine Kategorie.' : null,
                items: [
                  for (final category in widget.categories!)
                    DropdownMenuItem(
                      value: category['id'] as int,
                      child: SymbolLabel(
                        text(category['name']),
                        category['icon'],
                      ),
                    ),
                ],
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_saving) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
}
