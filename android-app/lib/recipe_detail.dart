import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'calendar_badge.dart';
import 'pill_widgets.dart';
import 'spacing.dart';
import 'ingredient_icon.dart';
import 'recipe_card.dart';
import 'symbol_field.dart';

class RecipeDetail extends StatefulWidget {
  const RecipeDetail({
    super.key,
    required this.api,
    required this.preview,
    required this.calendar,
    this.onSync,
    this.onRecipeCardsChanged,
    this.onWeekChanged,
    this.onCartChanged,
  });

  final RezeptgartenApi api;
  final Json preview;
  final bool calendar;
  final Future<void> Function()? onSync;
  final VoidCallback? onRecipeCardsChanged;
  final VoidCallback? onWeekChanged;
  final VoidCallback? onCartChanged;

  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail> {
  static const _links = MethodChannel('de.rezeptgarten/links');
  static const _buttonStyle = ButtonStyle(
    alignment: Alignment.center,
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(
        horizontal: AppSpacing.section,
        vertical: AppSpacing.related,
      ),
    ),
  );
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  late String _id = text(widget.preview['id']);
  late Json _preview = widget.preview;
  Json? _recipe;
  List<String>? _tips;
  String? _error;
  String? _noteStatus;
  String? _tipsError;
  String? _original;
  Future<bool>? _saving;
  bool _noteLoading = false;
  bool _tipsLoading = false;
  int _loadGeneration = 0;
  bool _working = false;
  bool _leaving = false;
  String get _recipePath => '/api/recipes/${Uri.encodeComponent(_id)}';
  String get _notePath => '/api/notes/${Uri.encodeComponent(_id)}';
  bool get _dirty => _original != null && _original != _note.text;
  bool get _calendarRecipe => _recipe?['is_local'] == false;

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(() {
      if (!_noteFocus.hasFocus) unawaited(_flushNote());
    });
    unawaited(_load(_id));
  }

  @override
  void dispose() {
    _noteFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load(String id) async {
    final generation = ++_loadGeneration;
    final keepContent = id == _id && _recipe != null;
    setState(() {
      if (id != _id) {
        _preview =
            objects(_recipe?['versions'])
                .where((version) => version['id'] == id)
                .firstOrNull ??
            {'id': id, 'name': _recipe?['name'] ?? _preview['name']};
      }
      _id = id;
      _error = null;
      if (!keepContent) {
        _recipe = null;
        _original = null;
        _tips = null;
        _note.clear();
      }
      _noteStatus = null;
      _tipsError = null;
      _tipsLoading = false;
      _noteLoading = false;
      _working = true;
    });
    try {
      final suffix = widget.calendar ? '?calendar=true' : '';
      final recipe = await widget.api.get('$_recipePath$suffix') as Json;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _recipe = recipe;
        _working = false;
      });
      unawaited(_loadNote());
      unawaited(_loadTips());
    } on Exception catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = error.toString();
          _working = false;
        });
      }
    }
  }

  Future<void> _loadNote() async {
    if (_noteLoading) return;
    final generation = _loadGeneration;
    final original = _original;
    setState(() {
      _noteLoading = true;
      _noteStatus = 'Notiz wird geladen …';
    });
    try {
      final result = await widget.api.get(_notePath) as Json;
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (_dirty || _original != original || _saving != null) {
          if (_noteLoading && _saving == null) _noteStatus = null;
          return;
        }
        _original = result['text'] as String;
        _note.text = _original!;
        _noteStatus = null;
      });
    } on Exception catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _noteStatus = error.toString());
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _noteLoading = false);
      }
    }
  }

  Future<void> _loadTips() async {
    final generation = _loadGeneration;
    final stored = _recipe?['tips_json'];
    if (stored == null) setState(() => _tipsLoading = true);
    try {
      final Object? tips;
      if (stored != null) {
        tips = _list(stored);
      } else {
        final result = await widget.api.get('$_recipePath/tips') as Json;
        tips = result['tips'];
      }
      if (!mounted || generation != _loadGeneration) return;
      final values = _list(tips).whereType<String>();
      setState(() {
        _tipsError = null;
        _tips =
            (_id.startsWith('creation:')
                    ? values.takeWhile((value) => !value.startsWith('Notiz:'))
                    : values)
                .where((value) => value.trim().isNotEmpty)
                .toList();
      });
    } on Exception catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _tipsError = error.toString());
      }
    } finally {
      if (mounted && generation == _loadGeneration && _tipsLoading) {
        setState(() => _tipsLoading = false);
      }
    }
  }

  Future<bool> _flushNote() async {
    while (mounted && (_dirty || _saving != null)) {
      final pending = _saving ??= _saveNote();
      final saved = await pending;
      if (identical(_saving, pending)) _saving = null;
      if (mounted) setState(() {});
      if (!saved) return false;
    }
    return mounted;
  }

  Future<bool> _saveNote() async {
    final draft = _note.text;
    final expected = _original!;
    setState(() => _noteStatus = 'Notiz wird mit Cookidoo abgeglichen …');
    try {
      final result = await widget.api.write('PUT', _notePath, {
        'text': draft,
        'expected': expected,
      }) as Json;
      if (!mounted) return false;
      setState(() {
        _original = result['text'] as String;
        if (_note.text == draft) _note.text = _original!;
        _noteStatus = 'In Cookidoo gespeichert.';
      });
      widget.onRecipeCardsChanged?.call();
      return true;
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _noteStatus = '$error Dein Text bleibt im Feld erhalten.',
        );
      }
      return false;
    }
  }

  Future<void> _close() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final saved = await _flushNote();
      if (!mounted) return;
      if (!saved) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            content: const Text(
              'Die Notiz wurde nicht gespeichert. Entwurf verwerfen?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Weiter bearbeiten'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Entwurf verwerfen'),
              ),
            ],
          ),
        );
        if (discard != true || !mounted) return;
      }
      Navigator.of(context).pop();
    } finally {
      _leaving = false;
    }
  }

  Future<void> _switchVersion(String? id) async {
    if (id == null || id == _id || _working) return;
    if (await _flushNote() && mounted && !_working) await _load(id);
  }

  Future<void> _refresh() async {
    if (_working || _leaving) return;
    setState(() => _working = true);
    try {
      if (!await _flushNote() || !mounted) return;
      await widget.onSync?.call();
      if (mounted) await _load(_id);
    } on Exception catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _action(Future<void> Function() run) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (await _flushNote() && mounted) await run();
    } on Exception catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editLocalLists() async {
    Future<void>? pending;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LocalListsSheet(
        api: widget.api,
        memberships: {
          for (final item in objects(_recipe?['collections'])) text(item['id']),
        },
        onChanged: (list, present) {
          final write = _setLocalMembership(list, present);
          pending = write;
          return write.whenComplete(() => pending = null);
        },
      ),
    );
    // A dismissed sheet can still have a write in progress.
    await pending;
  }

  Future<void> _setLocalMembership(Json list, bool present) async {
    final id = text(list['id']);
    final listId = Uri.encodeComponent(id);
    final recipeId = Uri.encodeComponent(_id);
    await widget.api.write(
      'PUT',
      '/api/local-collections/$listId/recipes/$recipeId',
      {'present': present},
    );
    if (!mounted) return;
    final recipe = _recipe!;
    setState(() {
      _recipe = {
        ...recipe,
        'collections': [
          for (final membership in objects(recipe['collections']))
            if (membership['id'] != id) membership,
          if (present) list,
        ],
      };
    });
    widget.onRecipeCardsChanged?.call();
  }

  Future<void> _planWeek() async {
    final options = await widget.api.get('/api/calendar/cooking-days') as Json;
    if (!mounted) return;
    final days = (options['days'] as List).cast<String>();
    final selected = <String>{};
    final chosen = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Diese Woche kochen'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final day in days)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    calendarDayLabel(DateTime.parse(day).weekday - 1, day),
                  ),
                  value: selected.contains(day),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) {
                      selected.add(day);
                    } else {
                      selected.remove(day);
                    }
                  }),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      days.where(selected.contains).toList(),
                    ),
              child: const Text('Einplanen'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final result = await widget.api.write(
      'POST',
      '$_recipePath/plan-week${_calendarRecipe ? '?calendar=true' : ''}',
      {'days': chosen},
    ) as Json;
    if (!mounted) return;
    widget.onWeekChanged?.call();
    final unconfirmed = (result['unconfirmed'] as List).cast<String>();
    _message(
      unconfirmed.isEmpty
          ? 'Im Cookidoo-Kalender eingeplant.'
          : 'Nicht bestätigt für ${unconfirmed.map(calendarDateLabel).join(', ')}. Bitte prüfe den Cookidoo-Kalender.',
    );
  }

  Future<void> _addToShelf() async {
    final id = _id;
    final week = await widget.api.get('/api/calendar/week') as Json;
    final monday = objects(week['days']).firstOrNull?['date'];
    if (monday is! String || monday.isEmpty) {
      throw const ApiException(
        'Die aktuelle Woche konnte nicht geladen werden.',
      );
    }
    if (!mounted) return;
    if (objects(week['shelf']).any((recipe) => recipe['id'] == id)) {
      _message('Das Rezept liegt bereits in der Ablage.');
      return;
    }
    const creationPrefix = 'creation:';
    final custom = id.startsWith(creationPrefix);
    await widget.api.write('POST', '/api/calendar/placement', {
      'week': monday,
      'source': 'preview',
      'target': 'shelf',
      'recipe_id': custom ? id.substring(creationPrefix.length) : id,
      'custom': custom,
      'recipe': <String, dynamic>{},
      'move_id': newCalendarMoveId(),
    });
    if (mounted) {
      widget.onWeekChanged?.call();
      _message('Zur Ablage der aktuellen Woche hinzugefügt.');
    }
  }

  static List<dynamic> _list(Object? value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return [];
      }
    }
    return value is List ? value : [];
  }

  Widget? _ingredients(Json recipe) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final inPantry = dark ? const Color(0xff46ed79) : const Color(0xff00853e);
    final missing = dark ? const Color(0xffff6572) : const Color(0xffd32239);
    final hidden = _list(recipe['hidden_ingredient_positions']).toSet();
    final availability = recipe['ingredient_availability'];
    final icons = recipe['ingredient_icons'];
    final rows = <Widget>[];
    for (final (index, ingredient) in _list(
      recipe['ingredients_json'],
    ).indexed) {
      if (hidden.contains(index)) continue;
      final name = ingredient is Json ? text(ingredient['name']).trim() : '';
      final description = ingredient is Json
          ? text(ingredient['description']).trim()
          : ingredient is String
          ? ingredient
          : '';
      final preparation = ingredient is Json
          ? text(ingredient['preparation']).trim()
          : '';
      var label = description.isEmpty ? name : description;
      if (description.isNotEmpty &&
          name.isNotEmpty &&
          !description.toLowerCase().contains(name.toLowerCase())) {
        label = '$label $name';
      }
      if (label.isEmpty) continue;
      if (preparation.isNotEmpty && !label.contains(preparation)) {
        label += '${preparation.startsWith(',') ? '' : ', '}$preparation';
      }
      final available = availability is Json ? availability['$index'] : null;
      rows.add(
        ListTile(
          dense: true,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: switch (available) {
                  true => 'Im Vorrat',
                  false => 'Nicht im Vorrat',
                  _ => 'Nicht zugeordnet',
                },
                child: Icon(
                  Icons.circle,
                  size: 13,
                  color: switch (available) {
                    true => inPantry,
                    false => missing,
                    _ => theme.colorScheme.outline,
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.related),
              IngredientIcon(
                name.isEmpty ? label : name,
                selected: icons is Json ? icons['$index'] : null,
              ),
            ],
          ),
          title: Text(label),
        ),
      );
    }
    return rows.isEmpty
        ? null
        : ExpansionTile(
            key: ValueKey('ingredients-$_id'),
            title: const Text('Zutaten'),
            initiallyExpanded: true,
            children: rows,
          );
  }

  Widget? _preparation(Json recipe) {
    final raw = _list(recipe['instructions_json']);
    final groups = raw.any((item) => item is Json && item['steps'] is List)
        ? objects(raw)
        : [
            {
              'steps': raw
                  .map((item) => item is Json ? item['text'] : item)
                  .toList(),
            },
          ];
    final rows = <Widget>[];
    for (final group in groups) {
      final steps = _list(group['steps'])
          .whereType<String>()
          .where((step) => step.trim().isNotEmpty);
      if (steps.isEmpty) continue;
      if (text(group['title']).isNotEmpty) {
        rows.add(ListTile(title: Text(text(group['title']))));
      }
      for (final (index, step) in steps.indexed) {
        rows.add(ListTile(leading: Text('${index + 1}.'), title: Text(step)));
      }
    }
    return rows.isEmpty
        ? null
        : ExpansionTile(
            key: ValueKey('preparation-$_id'),
            title: const Text('Zubereitung'),
            children: rows,
          );
  }

  Widget _noteEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: AppSpacing.related,
    children: [
      Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed &&
              (!_note.value.isComposingRangeValid ||
                  _note.value.composing.isCollapsed)) {
            unawaited(_flushNote());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _note,
          focusNode: _noteFocus,
          readOnly: _original == null || _working,
          maxLength: 5000,
          minLines: 1,
          maxLines: 8,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_flushNote()),
          onChanged: (_) => setState(() => _noteStatus = null),
          decoration: const InputDecoration(
            labelText: 'Meine Notiz',
            counterText: '',
          ),
        ),
      ),
      if (_noteStatus != null) Text(_noteStatus!),
      if (_recipe != null && _original == null && !_noteLoading && !_working)
        TextButton.icon(
          onPressed: _loadNote,
          style: _buttonStyle,
          icon: const Icon(Icons.refresh),
          label: const Text('Notiz erneut laden', textAlign: TextAlign.center),
        ),
      if (_dirty && _saving == null)
        TextButton.icon(
          onPressed: _flushNote,
          style: _buttonStyle,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Notiz speichern', textAlign: TextAlign.center),
        ),
    ],
  );

  Widget _content(Json recipe) {
    final loaded = _recipe != null;
    final canAct = loaded && !_working;
    final lists = objects(recipe['collections']);
    final difficulty = recipeDifficulty(recipe['difficulty']);
    final versions = objects(recipe['versions']);
    final showVersions =
        versions.length > 1 && versions.any((version) => version['id'] == _id);
    final sections = <Widget>[
      RecipeCard(api: widget.api, recipe: recipe, detail: true),
      if (lists.isNotEmpty)
        Wrap(
          spacing: AppSpacing.related,
          runSpacing: AppSpacing.tight,
          children: [
            for (final list in lists)
              InfoPill(text(list['name']), symbol: list['icon']),
          ],
        ),
      Text(
        text(recipe['name'], 'Rezept'),
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      if (!loaded && _error == null) const LinearProgressIndicator(),
      if (_error case final String error)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error),
            TextButton.icon(
              onPressed: _working ? null : () => _load(_id),
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut laden'),
            ),
          ],
        ),
      if (showVersions)
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Rezeptversion'),
          child: DropdownButton<String>(
            value: _id,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            onChanged: _working ? null : _switchVersion,
            items: [
              for (final (index, version) in versions.indexed)
                DropdownMenuItem(
                  value: text(version['id']),
                  child: Text(
                    '${version['origin_recipe_id'] == null ? 'Cookidoo-Original' : 'Meine Kreation $index'}'
                    '${version['servings'] == null ? '' : ' · ${version['servings']} Portionen'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      if (difficulty != null ||
          [
            'total_seconds',
            'active_seconds',
            'servings',
          ].any((field) => recipe[field] != null))
        Wrap(
          spacing: AppSpacing.related,
          runSpacing: AppSpacing.tight,
          children: [
            if (recipe['total_seconds'] case final num seconds)
              InfoPill('${(seconds / 60).round()} Min. gesamt'),
            if (recipe['active_seconds'] case final num seconds)
              InfoPill('${(seconds / 60).round()} Min. Arbeitszeit'),
            if (recipe['servings'] != null)
              InfoPill('${recipe['servings']} Portionen'),
            if (difficulty != null) InfoPill(difficulty),
          ],
        ),
      _noteEditor(),
      if (_ingredients(recipe) case final Widget ingredients) ingredients,
      if (_preparation(recipe) case final Widget preparation) preparation,
      if (_tips case final List<String> tips when tips.isNotEmpty)
        ExpansionTile(
          key: ValueKey('tips-$_id'),
          title: const Text('Tipps'),
          children: [for (final tip in tips) ListTile(title: Text(tip))],
        ),
      if (_tipsLoading)
        const LinearProgressIndicator(semanticsLabel: 'Tipps werden geladen')
      else if (_tipsError != null)
        TextButton.icon(
          onPressed: _working ? null : _loadTips,
          style: _buttonStyle,
          icon: const Icon(Icons.refresh),
          label: const Text('Tipps erneut laden', textAlign: TextAlign.center),
        ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.related,
        children: [
          if (loaded && !_calendarRecipe)
            OutlinedButton.icon(
              onPressed: canAct ? () => _action(_editLocalLists) : null,
              style: _buttonStyle,
              icon: const Icon(Icons.playlist_add),
              label: const Text(
                'Zu lokalen Listen hinzufügen',
                textAlign: TextAlign.center,
              ),
            ),
          FilledButton.icon(
            onPressed: canAct ? () => _action(_addToShelf) : null,
            style: _buttonStyle,
            icon: const Icon(Icons.playlist_add),
            label: const Text(
              'Zur Ablage hinzufügen',
              textAlign: TextAlign.center,
            ),
          ),
          FilledButton.icon(
            onPressed: canAct ? () => _action(_planWeek) : null,
            style: _buttonStyle,
            icon: const Icon(Icons.calendar_today_outlined),
            label: const Text(
              'Diese Woche kochen',
              textAlign: TextAlign.center,
            ),
          ),
          FilledButton.icon(
            onPressed: !canAct
                ? null
                : () => _action(() async {
                    final result = await widget.api.write(
                      'POST',
                      '/api/cart/recipes',
                      {'recipe_id': _id, 'calendar': _calendarRecipe},
                    ) as Json;
                    if (mounted) {
                      if (result['added'] != false) {
                        widget.onCartChanged?.call();
                      }
                      _message(
                        result['added'] == false
                            ? 'Rezept bereits im Einkaufswagen.'
                            : 'Rezept im Einkaufswagen.',
                      );
                    }
                  }),
            style: _buttonStyle,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text(
              'Zum Einkaufswagen hinzufügen',
              textAlign: TextAlign.center,
            ),
          ),
          if (recipe['source_url'] case final String url)
            OutlinedButton.icon(
              onPressed: !canAct
                  ? null
                  : () => _action(() async {
                      await _links.invokeMethod<void>('openCookidoo', url);
                    }),
              style: _buttonStyle,
              icon: const Icon(Icons.open_in_new),
              label: const Text(
                'In Cookidoo öffnen',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.page,
            itemCount: sections.length,
            itemBuilder: (_, index) => sections[index],
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.section),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_dirty && _saving == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _close),
        title: Text(text(_recipe?['name'] ?? _preview['name'], 'Rezept')),
      ),
      body: SafeArea(child: _content(_recipe ?? _preview)),
    ),
  );
}

class _LocalListsSheet extends StatefulWidget {
  const _LocalListsSheet({
    required this.api,
    required this.memberships,
    required this.onChanged,
  });

  final RezeptgartenApi api;
  final Set<String> memberships;
  final Future<void> Function(Json list, bool present) onChanged;

  @override
  State<_LocalListsSheet> createState() => _LocalListsSheetState();
}

class _LocalListsSheetState extends State<_LocalListsSheet> {
  late Future<List<Json>> _lists = _loadLists();
  late final _memberships = {...widget.memberships};
  bool _saving = false;
  String? _error;

  Future<List<Json>> _loadLists() async {
    final result = await widget.api.get('/api/collections') as Json;
    return objects(result['items'])
        .where((list) => list['kind'] == 'local')
        .toList();
  }

  Future<void> _toggle(Json list, bool present) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onChanged(list, present);
      if (!mounted) return;
      final id = text(list['id']);
      setState(() {
        if (present) {
          _memberships.add(id);
        } else {
          _memberships.remove(id);
        }
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.section),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Lokale Listen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Schließen',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: FutureBuilder<List<Json>>(
              future: _lists,
              builder: (context, snapshot) {
                final lists = snapshot.data;
                return ListView(
                  padding: AppSpacing.panel,
                  shrinkWrap: true,
                  children: [
                    if (_saving ||
                        snapshot.connectionState != ConnectionState.done)
                      const LinearProgressIndicator()
                    else if (snapshot.hasError) ...[
                      Text(snapshot.error.toString()),
                      TextButton(
                        onPressed: () => setState(() => _lists = _loadLists()),
                        child: const Text('Listen erneut laden'),
                      ),
                    ] else if (lists?.isEmpty == true)
                      const Text(
                        'Erstelle zuerst eine lokale Rezeptliste unter „Listen“.',
                      ),
                    if (_error case final String error)
                      Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    for (final list in lists ?? <Json>[])
                      CheckboxListTile(
                        value: _memberships.contains(list['id']),
                        title: SymbolLabel(text(list['name']), list['icon']),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _saving
                            ? null
                            : (present) => _toggle(list, present == true),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
