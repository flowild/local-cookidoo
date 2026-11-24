import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'connection.dart';
import 'recipe_card.dart';
import 'spacing.dart';

class RecipeSearchState extends ChangeNotifier {
  RecipeSearchState(this.api, this.connection) {
    _mode = connection?.mode;
    connection?.addListener(_connectionChanged);
  }

  final RezeptgartenApi api;
  final ConnectionController? connection;
  final query = TextEditingController();
  final scroll = ScrollController();
  PageStorageBucket storage = PageStorageBucket();
  final List<Json> results = [];
  Timer? _timer;
  ConnectionMode? _mode;
  bool catalog = false;
  bool loading = false;
  String? error;
  int? next;
  int _generation = 0;
  bool get telegram => connection?.mode == ConnectionMode.telegram;

  void _connectionChanged() {
    final mode = connection?.mode;
    if (mode == _mode) return;
    _mode = mode;
    _timer?.cancel();
    _generation++;
    results.clear();
    next = null;
    loading = false;
    error = null;
    if (telegram) catalog = false;
    if (mode == ConnectionMode.local || mode == ConnectionMode.telegram) {
      search(immediate: true);
    } else {
      notifyListeners();
    }
  }

  void setCatalog(bool value) {
    if (value && telegram) return;
    catalog = value;
    results.clear();
    next = null;
    search(immediate: true);
  }

  void search({bool immediate = false}) {
    _timer?.cancel();
    _generation++;
    if (scroll.hasClients) scroll.jumpTo(0);
    error = null;
    next = null;
    if (query.text.trim().isEmpty) {
      results.clear();
      loading = false;
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    if (immediate) {
      unawaited(_load(false, _generation));
    } else {
      _timer = Timer(
        const Duration(milliseconds: 350),
        () => _load(false, _generation),
      );
    }
  }

  void more() {
    if (loading || next == null) return;
    loading = true;
    error = null;
    notifyListeners();
    unawaited(_load(true, ++_generation));
  }

  Future<void> _load(bool append, int generation) async {
    final source = catalog && !telegram;
    final params = {
      'q': query.text.trim(),
      if (append) (source ? 'page' : 'offset'): '$next',
    };
    final uri = Uri(
      path: source ? '/api/cookidoo/search' : '/api/search/local',
      queryParameters: params,
    );
    try {
      final data = await api.get(
        uri.toString(),
        timeout: const Duration(seconds: 32),
      ) as Json;
      if (generation != _generation) return;
      final items = objects(data['items']);
      if (!append) results.clear();
      final existing = results.map((item) => item['id']).toSet();
      results.addAll(items.where((item) => existing.add(item['id'])));
      if (source) {
        next = data['next_page'] as int?;
      } else {
        final offset = (data['offset'] as int? ?? 0) + items.length;
        final total = data['match_total'] as int? ?? data['total'] as int? ?? 0;
        next = offset < total && items.isNotEmpty ? offset : null;
      }
    } on Exception catch (failure) {
      if (generation != _generation) return;
      error = failure.toString();
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void reset() {
    _timer?.cancel();
    _generation++;
    query.clear();
    storage = PageStorageBucket();
    if (scroll.hasClients) scroll.jumpTo(0);
    results.clear();
    catalog = false;
    next = null;
    error = null;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    connection?.removeListener(_connectionChanged);
    query.dispose();
    scroll.dispose();
    super.dispose();
  }
}

class RecipeSearchPage extends StatelessWidget {
  const RecipeSearchPage({
    super.key,
    required this.state,
    required this.openRecipe,
  });
  final RecipeSearchState state;
  final Future<void> Function(Json recipe, bool catalog) openRecipe;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Rezepte suchen')),
      body: PageStorage(
        bucket: state.storage,
        child: CustomScrollView(
          key: const PageStorageKey('recipe-search'),
          controller: state.scroll,
          slivers: [
            SliverPadding(
              padding: AppSpacing.page,
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: state.query,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => state.search(),
                          onSubmitted: (_) => state.search(immediate: true),
                          decoration: const InputDecoration(
                            hintText: 'Was möchtest du kochen?',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.related),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: state.catalog,
                            onChanged: state.telegram ? null : state.setCatalog,
                          ),
                          Text(state.catalog ? 'Cookidoo' : 'Lokal'),
                        ],
                      ),
                    ],
                  ),
                  if (state.telegram)
                    const Text('Cookidoo-Suche im Heimnetz verfügbar.'),
                  const SizedBox(height: AppSpacing.related),
                  if (state.loading) const LinearProgressIndicator(),
                  if (state.error != null) ...[
                    Text(state.error!),
                    TextButton(
                      onPressed: () => state.search(immediate: true),
                      child: const Text('Erneut versuchen'),
                    ),
                  ],
                  if (!state.loading &&
                      state.error == null &&
                      state.results.isEmpty &&
                      state.query.text.trim().isNotEmpty)
                    Text(
                      state.next == null ? 'Keine passenden Rezepte gefunden.' : 'In diesem Abschnitt wurden keine passenden Rezepte gefunden.',
                    ),
                  RecipePreviewGrid(
                    api: state.api,
                    recipes: state.results,
                    onOpen: (recipe) => openRecipe(recipe, state.catalog),
                  ),
                  if (state.next != null)
                    OutlinedButton(
                      onPressed: state.loading ? null : state.more,
                      child: Text(
                        state.results.isEmpty
                            ? 'Weitere durchsuchen'
                            : 'Weitere Rezepte laden',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
