import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'ingredient_icon.dart';

class PantryView extends StatefulWidget {
  const PantryView({
    super.key,
    required this.api,
    required this.collapsed,
    this.refreshCount = 0,
    this.onSync,
  });

  final RezeptgartenApi api;
  final Set<int> collapsed;
  final int refreshCount;
  final Future<void> Function()? onSync;

  @override
  State<PantryView> createState() => _PantryViewState();
}

class _PantryViewState extends State<PantryView> {
  List<Json> _categories = [];
  List<Json> _items = [];
  String _query = '';
  String? _error;
  bool _loading = true;
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
        _categories = objects(result['categories']);
        _items = objects(result['items']);
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
  }) async {
    if (_writing || _loading) return;
    if (!newCategory && _categories.isEmpty) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PantryEditor(
        api: widget.api,
        categories: newCategory ? null : _categories,
        categoryId: categoryId,
        item: item,
      ),
    );
    if (saved == true && mounted) await _load();
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
      if (expand) {
        widget.collapsed.clear();
      } else {
        widget.collapsed.addAll(
          _categories.map((category) => category['id'] as int),
        );
      }
      ++_expansionVersion;
    });
  }

  Widget _toolbar(bool enabled) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Mein Vorrat', style: Theme.of(context).textTheme.headlineMedium),
      const Text('Halte fest, welche Zutaten du zu Hause hast.'),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: enabled && _categories.isNotEmpty ? () => _edit() : null,
            child: const Text('Zutat hinzufügen'),
          ),
          OutlinedButton(
            onPressed: enabled ? () => _edit(newCategory: true) : null,
            child: const Text('Neue Kategorie'),
          ),
          TextButton(
            onPressed: () => _expandAll(false),
            child: const Text('Alle einklappen'),
          ),
          TextButton(
            onPressed: () => _expandAll(true),
            child: const Text('Alle ausklappen'),
          ),
        ],
      ),
      TextField(
        maxLength: 100,
        onChanged: (value) =>
            setState(() => _query = value.trim().toLowerCase()),
        decoration: const InputDecoration(
          labelText: 'Vorrat durchsuchen',
          prefixIcon: Icon(Icons.search),
          counterText: '',
        ),
      ),
      if (_loading || _writing) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Erneut laden')),
      ],
      if (!_loading && _error == null && _categories.isEmpty)
        const Text('Lege eine Kategorie an, um Zutaten einzutragen.'),
      const SizedBox(height: 12),
    ],
  );

  Widget _category(Json category, List<Json> items, int index, bool enabled) {
    final id = category['id'] as int;
    final name = text(category['name']);
    return Card(
      key: ValueKey(id),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey((id, _expansionVersion, _query.isNotEmpty)),
        initiallyExpanded: _query.isNotEmpty || !widget.collapsed.contains(id),
        onExpansionChanged: (expanded) {
          if (_query.isNotEmpty) return;
          if (expanded) {
            widget.collapsed.remove(id);
          } else {
            widget.collapsed.add(id);
          }
        },
        leading: _query.isEmpty && enabled
            ? ReorderableDragStartListener(
                index: index,
                child: Semantics(
                  label: '$name verschieben',
                  child: const Icon(Icons.drag_handle),
                ),
              )
            : null,
        title: Row(
          children: [
            Expanded(child: Text(name)),
            PopupMenuButton<String>(
              enabled: enabled,
              tooltip: 'Aktionen für $name',
              onSelected: (value) {
                if (value == 'add') {
                  unawaited(_edit(categoryId: id));
                } else {
                  unawaited(_removeCategory(category));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Zutat hinzufügen')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Kategorie löschen'),
                ),
              ],
            ),
          ],
        ),
        subtitle: Text('${items.length} Zutaten'),
        children: [
          if (items.isEmpty)
            const ListTile(title: Text('Noch keine Zutaten eingetragen.')),
          for (final item in items)
            ListTile(
              dense: true,
              leading: IngredientIcon(text(item['name']), category: name),
              title: Text(text(item['name'])),
              subtitle: text(item['quantity']).isNotEmpty
                  ? Text(text(item['quantity']))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '${item['name']} bearbeiten',
                    onPressed: enabled ? () => _edit(item: item) : null,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: '${item['name']} entfernen',
                    onPressed: enabled
                        ? () => _change(
                            'DELETE',
                            '/api/pantry/items/${item['id']}',
                          )
                        : null,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
        ],
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        header: _toolbar(enabled),
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
  });

  final RezeptgartenApi api;
  final List<Json>? categories;
  final int? categoryId;
  final Json? item;

  @override
  State<_PantryEditor> createState() => _PantryEditorState();
}

class _PantryEditorState extends State<_PantryEditor> {
  late final _name = TextEditingController(text: text(widget.item?['name']));
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
        await widget.api.write('POST', '/api/pantry/categories', {
          'name': name,
        });
      } else {
        final id = widget.item?['id'];
        final body = {
          'name': name,
          'quantity': _quantity.text.trim(),
          'category_id': _categoryId,
          'ingredient_id': _ingredientId,
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
            ? 'Neue Kategorie'
            : widget.item == null
            ? 'Zutat hinzufügen'
            : 'Zutat bearbeiten',
      ),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            if (!_newCategory) ...[
              Wrap(
                spacing: 8,
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
                      child: Text(text(category['name'])),
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
