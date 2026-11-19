import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'api.dart';

class RecipeCard extends StatefulWidget {
  const RecipeCard({
    super.key,
    required this.api,
    required this.recipe,
    this.onTap,
    this.detail = false,
  });

  final RezeptgartenApi api;
  final Json recipe;
  final VoidCallback? onTap;
  final bool detail;

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  late Future<Uint8List?> image = widget.api.image(
    widget.recipe['image_file'],
    full: widget.detail,
  );

  @override
  void didUpdateWidget(RecipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recipe['image_file'] != oldWidget.recipe['image_file'] ||
        widget.detail != oldWidget.detail) {
      image = widget.api.image(
        widget.recipe['image_file'],
        full: widget.detail,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    final theme = Theme.of(context);
    final seconds = recipe['total_seconds'];
    final offeredServings = recipe['version_servings'];
    final servings = offeredServings is List && offeredServings.isNotEmpty
        ? offeredServings.join(' / ')
        : recipe['servings'];
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1.8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: image,
                    builder: (context, snapshot) => snapshot.data == null
                        ? ColoredBox(
                            color: theme.colorScheme.secondaryContainer,
                            child: const Icon(Icons.eco_outlined),
                          )
                        : Image.memory(snapshot.data!, fit: BoxFit.cover),
                  ),
                  if (!widget.detail && recipe['has_note'] == true)
                    const Positioned(
                      top: 6,
                      left: 6,
                      child: Tooltip(
                        message: 'Persönliche Notiz vorhanden',
                        child: CircleAvatar(
                          radius: 13,
                          child: Icon(Icons.sticky_note_2_outlined, size: 15),
                        ),
                      ),
                    ),
                  if (!widget.detail && (seconds is num || servings != null))
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xbb192e25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Text(
                            [
                              if (seconds is num)
                                '${(seconds / 60).round()} Min.',
                              if (servings != null) '$servings Port.',
                            ].join(' · '),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.detail)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(recipe['name'], 'Rezept'),
                      style: theme.textTheme.titleSmall,
                    ),
                    if (recipe['difficulty'] != null)
                      Text(switch (text(recipe['difficulty'])
                          .toLowerCase()
                          .split('.')
                          .last) {
                        'easy' => 'Einfach',
                        'medium' => 'Mittel',
                        'advanced' || 'hard' => 'Anspruchsvoll',
                        _ => text(recipe['difficulty']),
                      }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
