import 'dart:convert';

import 'package:flutter/services.dart';

import 'api.dart';

/// In-memory responses for the Android UI. This API has no network transport.
class DebugRezeptgartenApi extends RezeptgartenApi {
  DebugRezeptgartenApi() : super(server: Uri(scheme: 'debug')) {
    _addCartRecipe('linsensuppe');
  }

  @override
  bool get usesTestData => true;

  static final _recipes = {
    'linsensuppe': _recipe('linsensuppe', 'Linsensuppe mit Möhren', 4, 35, {
      'Rote Linsen': '200 g',
      'Möhre': '3 Stück',
      'Zwiebel': '1 Stück',
    }),
    'zitronenpasta': _recipe('zitronenpasta', 'Zitronenpasta', 2, 25, {
      'Pasta': '250 g',
      'Zitrone': '1 Stück',
      'Parmesan': '60 g',
    }),
    'apfelporridge': _recipe('apfelporridge', 'Apfelporridge', 2, 15, {
      'Haferflocken': '100 g',
      'Apfel': '1 Stück',
      'Milch': '300 ml',
    }),
  };
  static const _queue = {'phase': 'idle', 'items': <Json>[]};
  final _lists = <String, Set<String>>{
    'test-alltag': {'linsensuppe', 'apfelporridge'},
  };
  final _listNames = {'test-alltag': 'Schnelle Alltagsküche'};
  final _listIcons = <String, Object?>{};
  final _notes = {'linsensuppe': 'Beim nächsten Mal mit Petersilie servieren.'};
  final _categories = <Json>[
    {'id': 1, 'name': 'Obst & Gemüse'},
    {'id': 2, 'name': 'Trockenwaren'},
  ];
  final _pantry = <int, Json>{
    3: {'id': 3, 'name': 'Zwiebel', 'category_id': 1, 'quantity': '2 Stück'},
  };
  final _cart = <String, Json>{};
  final _weeks = <String, Map<String, Set<String>>>{};
  final _placeholders = <String, List<Json>>{};
  final _removed = <String, ({String week, String source, String recipe})>{};
  var _nextId = 4;
  var _featured = 0;

  static Json _recipe(
    String id,
    String name,
    int portions,
    int minutes,
    Map<String, String> ingredients,
  ) => {
    'id': id,
    'calendar_id': id,
    'image_file': '$id.png',
    'name': name,
    'is_local': true,
    'servings': portions,
    'total_seconds': minutes * 60,
    'difficulty': minutes > 30 ? 'medium' : 'easy',
    'ingredients_json': [
      for (final entry in ingredients.entries)
        {'name': entry.key, 'description': '${entry.value} ${entry.key}'},
    ],
    'instructions_json': [
      'Zutaten vorbereiten.',
      'Zubereiten und abschmecken.',
    ],
    'tips_json': ['Vor dem Servieren nach Belieben würzen.'],
  };

  static String _date(DateTime date) => date.toIso8601String().substring(0, 10);
  String get _today => _date(DateTime.now());

  String _monday(String day) {
    final date = DateTime.parse('${day}T00:00:00Z');
    return _date(date.subtract(Duration(days: date.weekday - 1)));
  }

  Map<String, Set<String>> _week(String monday) => _weeks.putIfAbsent(
    monday,
    () => {
      if (monday == _monday(_today)) ...{
        monday: {'linsensuppe'},
        if (_today != monday) _today: {'zitronenpasta'},
        'shelf': {'apfelporridge'},
      },
    },
  );

  Json _preview(String id) => {
    ..._recipes[id]!,
    'has_note': text(_notes[id]).isNotEmpty,
  };

  List<Json> get _collections => [
    for (final entry in _lists.entries)
      {
        'id': entry.key,
        'name': _listNames[entry.key],
        'icon': _listIcons[entry.key],
        'kind': 'local',
        'recipe_count': entry.value.length,
      },
  ];

  List<Json> get _ingredients => [
    for (final (index, name)
        in _recipes.values
            .expand((recipe) => objects(recipe['ingredients_json']))
            .map((ingredient) => ingredient['name'])
            .toSet()
            .indexed)
      {'id': index + 1, 'name': name},
  ];

  Json? _pantryItem(String name) => _pantry.values
      .where((item) => text(item['name']).toLowerCase() == name.toLowerCase())
      .firstOrNull;

  bool _inPantry(String name) => _pantryItem(name) != null;

  Json _calendar(String day) {
    final monday = _monday(day);
    final week = _week(monday);
    return {
      'today': _today,
      'days': [
        for (var offset = 0; offset < 7; offset++)
          _calendarDay(
            week,
            _date(
              DateTime.parse('${monday}T00:00:00Z').add(Duration(days: offset)),
            ),
          ),
      ],
      'shelf': (week['shelf'] ?? {}).map(_preview).toList(),
      'placeholder_placements': _placeholders[monday] ?? [],
    };
  }

  Json _calendarDay(Map<String, Set<String>> week, String date) => {
    'date': date,
    'recipes': (week[date] ?? {}).map(_preview).toList(),
  };

  Json _featuredRecipe() => {
    'recipe': _preview(_recipes.keys.elementAt(_featured)),
    'can_shuffle': true,
  };

  Json _browse(Uri uri) {
    final query = uri.queryParameters;
    final collection = _lists[query['collection']];
    final excluded = _lists[query['exclude_collection']] ?? {};
    final filters = uri.queryParametersAll['ingredient'] ?? [];
    final minimum = int.tryParse(query['min_servings'] ?? '') ?? 0;
    final maximum = int.tryParse(query['max_minutes'] ?? '') ?? 1440;
    final search = (query['q'] ?? '').toLowerCase();
    final candidate = (query['candidate_q'] ?? '').toLowerCase();
    final rows = <Json>[];
    for (final id in collection ?? _recipes.keys) {
      if (excluded.contains(id)) continue;
      final recipe = _preview(id);
      final names = objects(recipe['ingredients_json'])
          .map((item) => text(item['name']).toLowerCase());
      final name = text(recipe['name']).toLowerCase();
      final searchable = '$name ${names.join(' ')}';
      if (!searchable.contains(search) || !searchable.contains(candidate)) {
        continue;
      }
      final matches =
          filters.every(
            (filter) =>
                names.any((name) => name.contains(filter.toLowerCase())),
          ) &&
          (recipe['servings'] as int) >= minimum &&
          (recipe['total_seconds'] as int) <= maximum * 60;
      if (matches || query['show_all'] == 'true') {
        rows.add({...recipe, 'matches': matches});
      }
    }
    rows.sort((a, b) {
      final titleOrder =
          (text(b['name']).toLowerCase().contains(search) ? 1 : 0).compareTo(
            text(a['name']).toLowerCase().contains(search) ? 1 : 0,
          );
      if (titleOrder != 0) return titleOrder;
      return switch (query['sort']) {
        'time' => (a['total_seconds'] as int).compareTo(
          b['total_seconds'] as int,
        ),
        'servings' => (a['servings'] as int).compareTo(b['servings'] as int),
        'ingredients' => objects(
          a['ingredients_json'],
        ).length.compareTo(objects(b['ingredients_json']).length),
        _ => text(a['name']).compareTo(text(b['name'])),
      };
    });
    return {
      'items': rows
          .skip(int.tryParse(query['offset'] ?? '') ?? 0)
          .take(int.tryParse(query['limit'] ?? '') ?? 48)
          .toList(),
      'total': rows.length,
      'match_total': rows.where((row) => row['matches'] == true).length,
    };
  }

  Json _detail(String id) {
    final recipe = _preview(id);
    return {
      ...recipe,
      'collections': _collections
          .where((list) => _lists[list['id']]!.contains(id))
          .toList(),
      'ingredient_availability': {
        for (final (index, item) in objects(recipe['ingredients_json']).indexed)
          '$index': _inPantry(text(item['name'])),
      },
      'ingredient_icons': {
        for (final (index, item) in objects(recipe['ingredients_json']).indexed)
          if (_pantryItem(text(item['name']))?['icon'] case final String icon)
            '$index': icon,
      },
    };
  }

  bool _addCartRecipe(String id) {
    if (_cart.containsKey(id)) return false;
    final recipe = _preview(id);
    _cart[id] = {
      'id': id,
      'kind': 'recipe',
      'recipe_id': id,
      'status': 'pending',
      'data': {
        ...recipe,
        'ingredients': [
          for (final item in objects(recipe['ingredients_json']))
            {
              ...item,
              'text': item['description'],
              'owned': _inPantry(text(item['name'])),
            },
        ],
      },
    };
    return true;
  }

  String _shoppingCategory(String name) => switch (name.toLowerCase()) {
    'möhre' || 'zwiebel' => 'Gemüse',
    'apfel' || 'zitrone' => 'Obst',
    'milch' || 'parmesan' => 'Milchprodukte',
    'pasta' || 'rote linsen' || 'haferflocken' => 'Vorräte und Konserven',
    _ => 'Sonstiges',
  };

  Json _shoppingAppearance(String name) {
    final item = _pantryItem(name);
    final category = _categories
        .where((category) => category['id'] == item?['category_id'])
        .firstOrNull;
    return {
      'category': category?['name'] ?? _shoppingCategory(name),
      'category_icon': category?['icon'],
      'icon': item?['icon'],
    };
  }

  Json _shoppingCart() => {
    'items': [
      for (final entry in _cart.values)
        if (entry['kind'] == 'recipe')
          {
            ...entry,
            'data': {
              ...entry['data'] as Json,
              'has_note': text(_notes[entry['recipe_id']]).isNotEmpty,
              'ingredients': [
                for (final item in objects(entry['data']['ingredients']))
                  {
                    ...item,
                    ..._shoppingAppearance(text(item['name'])),
                    'in_pantry': _inPantry(text(item['name'])),
                  },
              ],
            },
          }
        else
          {
            ...entry,
            'data': {
              ...entry['data'] as Json,
              ..._shoppingAppearance(text(entry['data']['name'])),
            },
          },
    ],
  };

  @override
  Future<dynamic> get(String path, {Duration? timeout}) async {
    final uri = Uri.parse(path);
    final result = switch (uri.pathSegments) {
      ['api', 'status'] => {
        'connected': false,
        'sync': {'running': false},
        'calendar_queue': _queue,
        'stats': {'recipes': _recipes.length, 'collections': _lists.length},
        'cart_recipe_count': _cart.values
            .where((entry) => entry['kind'] == 'recipe')
            .length,
      },
      ['api', 'calendar', 'cooking-days'] => {
        'days': objects(_calendar(_today)['days'])
            .map((day) => text(day['date']))
            .where((day) => day.compareTo(_today) >= 0)
            .toList(),
      },
      ['api', 'recipes'] => _browse(uri),
      ['api', 'recipes', final id] when _recipes.containsKey(id) => _detail(id),
      ['api', 'notes', final id] => {'text': _notes[id] ?? ''},
      ['api', 'featured-recipe'] => _featuredRecipe(),
      ['api', 'collections'] => {'items': _collections},
      ['api', 'collections', _, 'filter-options'] => {
        'ingredients': _ingredients.map((item) => item['name']).toList(),
      },
      ['api', 'pantry'] => {
        'categories': _categories,
        'items': _pantry.values.toList(),
      },
      ['api', 'ingredients', 'suggestions'] => {
        'items': _ingredients
            .where(
              (item) =>
                  text(item['name'])
                      .toLowerCase()
                      .contains((uri.queryParameters['q'] ?? '').toLowerCase()),
            )
            .toList(),
      },
      ['api', 'calendar', 'week'] => _calendar(
        uri.queryParameters['day'] ?? _today,
      ),
      ['api', 'cart'] => _shoppingCart(),
      _ => throw const ApiException(
        'Diese Ansicht ist im Debug-Modus nicht verfügbar.',
      ),
    };
    return jsonDecode(jsonEncode(result));
  }

  @override
  Future<dynamic> write(String method, String path, [Json? body]) async {
    final segments = Uri.parse(path).pathSegments;
    final data = body ?? {};
    switch ((method, segments)) {
      case ('POST', ['api', 'sync']):
        return {'started': true};
      case ('POST', ['api', 'featured-recipe', 'shuffle']):
        _featured = (_featured + 1) % _recipes.length;
        return _featuredRecipe();
      case ('PUT', ['api', 'notes', final id]):
        if (data['expected'] != (_notes[id] ?? '')) {
          throw const ApiException('Die Testnotiz wurde inzwischen geändert.');
        }
        _notes[id] = text(data['text']);
        return {'text': _notes[id]};
      case ('POST', ['api', 'local-collections']):
        final id = 'test-${_nextId++}';
        _lists[id] = {};
        _listNames[id] = text(data['name']);
        _listIcons[id] = data['icon'];
      case ('PUT', ['api', 'local-collections', final id]):
        _listNames[id] = text(data['name']);
        _listIcons[id] = data['icon'];
      case ('DELETE', ['api', 'local-collections', final id]):
        _lists.remove(id);
        _listNames.remove(id);
        _listIcons.remove(id);
      case (
        'PUT',
        ['api', 'local-collections', final id, 'recipes', final recipe],
      ):
        if (data['present'] == true) {
          _lists[id]?.add(recipe);
        } else {
          _lists[id]?.remove(recipe);
        }
      case ('POST', ['api', 'recipes', final id, 'plan-week']):
        final days = (data['days'] as List).cast<String>();
        for (final day in days) {
          (_week(_monday(day))[day] ??= {}).add(id);
        }
        return {'confirmed': days, 'unconfirmed': <String>[]};
      case ('POST', ['api', 'calendar', 'placement']):
        return _placeRecipe(data);
      case ('POST', ['api', 'calendar', 'undo-removal']):
        if (_removed.remove(data['move_id']) case final removal?) {
          (_week(removal.week)[removal.source] ??= {}).add(removal.recipe);
        }
      case ('PUT', ['api', 'calendar', 'placeholders']):
        return _placePlaceholder(data);
      case ('POST', ['api', 'calendar', 'shopping']):
        final week = _week(_monday(text(data['day'], _today)));
        final recipes = {
          for (final entry in week.entries)
            if (entry.key == 'shelf' || entry.key.compareTo(_today) >= 0)
              ...entry.value,
        };
        return {
          'status': recipes.isEmpty ? 'empty' : 'ok',
          'added': recipes.where(_addCartRecipe).length,
        };
      case ('POST', ['api', 'cart', 'recipes']):
        return {'added': _addCartRecipe(text(data['recipe_id']))};
      case ('POST', ['api', 'cart', 'items']):
        final id = 'artikel-${_nextId++}';
        _cart[id] = {
          'id': id,
          'kind': 'additional',
          'status': 'pending',
          'data': {'name': data['name'], 'owned': false},
        };
      case ('DELETE', ['api', 'cart']):
        _cart.clear();
      case ('DELETE', ['api', 'cart', final id]):
        _cart.remove(id);
      case ('PUT', ['api', 'cart', final id, 'owned']):
        (_cart[id]?['data'] as Json?)?['owned'] = data['owned'];
      case ('PUT', ['api', 'cart', final id, 'ingredients', final position]):
        final ingredients = objects(_cart[id]?['data']['ingredients']);
        ingredients[int.parse(position)]['owned'] = data['owned'];
      case ('POST', ['api', 'cart', 'transfer']):
        for (final entry in _cart.values.where(
          (entry) => entry['status'] == 'pending',
        )) {
          entry['status'] = 'done';
        }
        return {'message': 'Cookidoo-Übertragung simuliert.'};
      case ('POST', ['api', 'pantry', 'categories']):
        _categories.add({'id': _nextId++, ...data});
      case ('DELETE', ['api', 'pantry', 'categories', final id]):
        final category = int.parse(id);
        _categories.removeWhere((item) => item['id'] == category);
        _pantry.removeWhere((_, item) => item['category_id'] == category);
      case ('PUT', ['api', 'pantry', 'categories', 'order']):
        final ids = data['category_ids'] as List;
        _categories.sort(
          (a, b) => ids.indexOf(a['id']).compareTo(ids.indexOf(b['id'])),
        );
      case ('PUT', ['api', 'pantry', 'categories', final id]):
        final category = _categories.firstWhere(
          (item) => item['id'] == int.parse(id),
        );
        category.addAll(data);
      case ('POST', ['api', 'pantry', 'items']):
        final id = _nextId++;
        _pantry[id] = {...data, 'id': id};
      case ('PUT', ['api', 'pantry', 'items', final id]):
        final number = int.parse(id);
        _pantry[number] = {...data, 'id': number};
      case ('DELETE', ['api', 'pantry', 'items', final id]):
        _pantry.remove(int.parse(id));
      default:
        throw const ApiException(
          'Diese Aktion ist im Debug-Modus nicht verfügbar.',
        );
    }
    return {'status': 'ok'};
  }

  Json _placeRecipe(Json data) {
    final monday = data['week'] as String;
    final source = data['source'] as String;
    final target = data['target'] as String;
    final id = data['recipe_id'] as String;
    final week = _week(monday);
    final wasOnShelf = week['shelf']?.contains(id) == true;
    if (source == 'preview' && target == 'shelf' && wasOnShelf) {
      throw const ApiException('Das Rezept liegt bereits in der Ablage.');
    }
    week[source]?.remove(id);
    if (target != 'trash') (week[target] ??= {}).add(id);
    if (target == 'trash' ||
        (target == 'shelf' && wasOnShelf && source != 'library')) {
      _removed[data['move_id'] as String] = (
        week: monday,
        source: source,
        recipe: id,
      );
      return {
        ..._queue,
        'items': [
          {'move_id': data['move_id'], 'target': 'trash'},
        ],
      };
    }
    return _queue;
  }

  Json _placePlaceholder(Json data) {
    final placements = _placeholders[data['week'] as String] ??= [];
    final id = data['instance_id'];
    if (id != null) placements.removeWhere((item) => item['id'] == id);
    if (data['present'] == true) {
      placements.add({
        'id': id ?? 'platzhalter-${_nextId++}',
        'placeholder': data['placeholder'],
        'target': data['target'],
      });
    }
    return {
      'placements': [
        for (final item in placements) {...item},
      ],
    };
  }

  @override
  Future<dynamic> probeHealth() async => {'ok': true};

  @override
  Future<Uint8List?> image(Object? filename, {bool full = false}) async {
    if (!_recipes.values.any((recipe) => recipe['image_file'] == filename)) {
      return null;
    }
    final image = await rootBundle.load('assets/debug/$filename');
    return image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes);
  }

  @override
  Future<void> close() async {}
}
