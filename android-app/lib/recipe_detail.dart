import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'ingredient_icon.dart';
import 'recipe_card.dart';

class RecipeDetail extends StatefulWidget {
  const RecipeDetail({
    super.key,
    required this.api,
    required this.preview,
    required this.calendar,
    this.onSync,
  });

  final RezeptgartenApi api;
  final Json preview;
  final bool calendar;
  final Future<void> Function()? onSync;

  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail> {
  static const _links = MethodChannel('de.rezeptgarten/links');
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  late String _id = text(widget.preview['id']);
  Json? _recipe;
  List<Json> _localLists = [];
  List<String>? _tips;
  String? _error;
  String? _noteStatus;
  String? _tipsError;
  String? _listError;
  String? _original;
  Future<bool>? _saving;
  bool _noteLoading = false;
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
    setState(() {
      _id = id;
      _error = null;
      _recipe = null;
      _original = null;
      _noteStatus = null;
      _tipsError = null;
      _listError = null;
      _tips = null;
      _localLists = [];
      _note.clear();
      _working = true;
    });
    try {
      final suffix = widget.calendar ? '?calendar=true' : '';
      final recipe = await widget.api.get('$_recipePath$suffix') as Json;
      if (!mounted) return;
      setState(() => _recipe = recipe);
      // Cookidoo serializes its requests. Fetch the note before any remote tips.
      await _loadNote();
      if (!mounted) return;
      await _loadTips();
      if (!_calendarRecipe && mounted) await _loadLists();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _loadNote() async {
    if (_noteLoading) return;
    setState(() {
      _noteLoading = true;
      _noteStatus = 'Notiz wird geladen …';
    });
    try {
      final result = await widget.api.get(_notePath) as Json;
      if (!mounted) return;
      setState(() {
        _original = result['text'] as String;
        _note.text = _original!;
        _noteStatus = null;
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _noteStatus = error.toString());
    } finally {
      if (mounted) setState(() => _noteLoading = false);
    }
  }

  Future<void> _loadTips() async {
    final stored = _recipe?['tips_json'];
    try {
      final Object? tips;
      if (stored != null) {
        tips = _list(stored);
      } else {
        final result = await widget.api.get('$_recipePath/tips') as Json;
        tips = result['tips'];
      }
      if (!mounted) return;
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
      if (mounted) setState(() => _tipsError = error.toString());
    }
  }

  Future<void> _loadLists() async {
    try {
      final result = await widget.api.get('/api/collections') as Json;
      if (!mounted) return;
      setState(() {
        _listError = null;
        _localLists = objects(result['items'])
            .where((list) => list['kind'] == 'local')
            .toList();
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _listError = error.toString());
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

  Widget _ingredients(Json recipe) {
    final hidden = _list(recipe['hidden_ingredient_positions']).toSet();
    final availability = recipe['ingredient_availability'];
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
                  size: 10,
                  color: switch (available) {
                    true => const Color(0xff528045),
                    false => Theme.of(context).colorScheme.error,
                    _ => Theme.of(context).colorScheme.outline,
                  },
                ),
              ),
              const SizedBox(width: 8),
              IngredientIcon(name.isEmpty ? label : name),
            ],
          ),
          title: Text(label),
        ),
      );
    }
    return rows.isEmpty
        ? const SizedBox.shrink()
        : ExpansionTile(
            key: ValueKey('ingredients-$_id'),
            title: const Text('Zutaten'),
            initiallyExpanded: true,
            children: rows,
          );
  }

  Widget _preparation(Json recipe) {
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
        ? const SizedBox.shrink()
        : ExpansionTile(
            key: ValueKey('preparation-$_id'),
            title: const Text('Zubereitung'),
            children: rows,
          );
  }

  Widget _noteEditor() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
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
      if (_original == null && !_noteLoading && !_working)
        TextButton(
          onPressed: () => _action(_loadNote),
          child: const Text('Notiz erneut laden'),
        ),
      if (_dirty && _saving == null)
        TextButton(onPressed: _flushNote, child: const Text('Notiz speichern')),
    ],
  );

  Widget _content(Json recipe) {
    final lists = objects(recipe['collections']);
    final memberships = lists.map((list) => list['id']).toSet();
    final versions = objects(recipe['versions']);
    final showVersions =
        versions.length > 1 && versions.any((version) => version['id'] == _id);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          RecipeCard(api: widget.api, recipe: recipe, detail: true),
          if (lists.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final list in lists) Chip(label: Text(text(list['name']))),
              ],
            ),
          Text(
            text(recipe['name'], 'Rezept'),
            style: Theme.of(context).textTheme.headlineSmall,
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
          Wrap(
            spacing: 8,
            children: [
              if (recipe['total_seconds'] case final num seconds)
                Chip(label: Text('${(seconds / 60).round()} Min. gesamt')),
              if (recipe['active_seconds'] case final num seconds)
                Chip(label: Text('${(seconds / 60).round()} Min. Arbeitszeit')),
              if (recipe['servings'] != null)
                Chip(label: Text('${recipe['servings']} Portionen')),
              if (recipe['difficulty'] != null)
                Chip(
                  label: Text(switch (text(recipe['difficulty'])
                      .toLowerCase()) {
                    'easy' => 'Einfach',
                    'medium' => 'Mittel',
                    'advanced' || 'hard' => 'Anspruchsvoll',
                    _ => text(recipe['difficulty']),
                  }),
                ),
            ],
          ),
          _noteEditor(),
          _ingredients(recipe),
          _preparation(recipe),
          if (_tips case final List<String> tips when tips.isNotEmpty)
            ExpansionTile(
              key: ValueKey('tips-$_id'),
              title: const Text('Tipps'),
              children: [for (final tip in tips) ListTile(title: Text(tip))],
            ),
          if (_tipsError != null)
            TextButton(
              onPressed: _working ? null : () => _action(_loadTips),
              child: const Text('Tipps erneut laden'),
            ),
          if (!_calendarRecipe) ...[
            const SizedBox(height: 12),
            Text(
              'Zu lokalen Listen hinzufügen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_listError != null)
              TextButton(
                onPressed: _working ? null : () => _action(_loadLists),
                child: const Text('Listen erneut laden'),
              )
            else if (!_working && _localLists.isEmpty)
              const Text(
                'Erstelle zuerst eine lokale Rezeptliste unter „Listen“.',
              ),
            for (final list in _localLists)
              CheckboxListTile(
                value: memberships.contains(list['id']),
                title: Text(text(list['name'])),
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _working
                    ? null
                    : (present) => _action(() async {
                        final listId = Uri.encodeComponent(text(list['id']));
                        final recipeId = Uri.encodeComponent(_id);
                        await widget.api.write(
                          'PUT',
                          '/api/local-collections/$listId/recipes/$recipeId',
                          {'present': present},
                        );
                        final refreshed =
                            await widget.api.get(_recipePath) as Json;
                        if (mounted) setState(() => _recipe = refreshed);
                      }),
              ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _working
                ? null
                : () => _action(() async {
                    final result = await widget.api.write(
                      'POST',
                      '$_recipePath/plan-today${_calendarRecipe ? '?calendar=true' : ''}',
                    ) as Json;
                    if (mounted) {
                      _message(
                        result['verified'] == true ? 'Für heute eingeplant.' : 'Die Planung konnte nicht bestätigt werden. Bitte prüfe den Kalender in Cookidoo.',
                      );
                    }
                  }),
            child: const Text('Heute kochen'),
          ),
          FilledButton(
            onPressed: _working
                ? null
                : () => _action(() async {
                    final result = await widget.api.write(
                      'POST',
                      '/api/cart/recipes',
                      {'recipe_id': _id, 'calendar': _calendarRecipe},
                    ) as Json;
                    if (mounted) {
                      _message(
                        result['added'] == false
                            ? 'Rezept bereits im Einkaufswagen.'
                            : 'Rezept im Einkaufswagen.',
                      );
                    }
                  }),
            child: const Text('Zum Einkaufswagen hinzufügen'),
          ),
          if (recipe['source_url'] case final String url)
            OutlinedButton(
              onPressed: _working
                  ? null
                  : () => _action(() async {
                      await _links.invokeMethod<void>('openCookidoo', url);
                    }),
              child: const Text('In Cookidoo öffnen'),
            ),
        ],
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
        title: Text(text(_recipe?['name'] ?? widget.preview['name'], 'Rezept')),
      ),
      body: SafeArea(
        child: switch (_recipe) {
          final Json recipe => _content(recipe),
          null when _error == null => const Center(
            child: CircularProgressIndicator(),
          ),
          null => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(
                  onPressed: _working ? null : () => _load(_id),
                  child: const Text('Erneut laden'),
                ),
              ],
            ),
          ),
        },
      ),
    ),
  );
}
