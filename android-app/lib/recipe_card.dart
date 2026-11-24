import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'spacing.dart';

String? recipeDifficulty(Object? value) {
  final label = text(value).trim();
  return switch (label.toLowerCase().split('.').last) {
    'easy' => 'Einfach',
    'medium' => 'Mittel',
    'advanced' || 'hard' => 'Anspruchsvoll',
    _ when label.isNotEmpty => label,
    _ => null,
  };
}

({int columns, double width}) recipeGridLayout(
  BuildContext context,
  double width,
) {
  const gap = AppSpacing.item;
  final compact =
      MediaQuery.sizeOf(context).width < 600 &&
      MediaQuery.textScalerOf(context).scale(1) <= 1.25;
  final minimum = compact ? 132 : 182;
  final columns = ((width + gap) / (minimum + gap)).floor().clamp(
    1,
    compact ? 2 : 5,
  );
  return (columns: columns, width: (width - (columns - 1) * gap) / columns);
}

class RecipePreviewGrid extends StatelessWidget {
  const RecipePreviewGrid({
    super.key,
    required this.api,
    required this.recipes,
    required this.onOpen,
  });

  final RezeptgartenApi api;
  final List<Json> recipes;
  final ValueChanged<Json> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final layout = recipeGridLayout(context, bounds.maxWidth);
      return Wrap(
        spacing: AppSpacing.item,
        runSpacing: AppSpacing.item,
        children: [
          for (final recipe in recipes)
            SizedBox(
              key: ValueKey(recipe['id']),
              width: layout.width,
              child: RecipeCard(
                api: api,
                recipe: recipe,
                onTap: () => onOpen(recipe),
              ),
            ),
        ],
      );
    },
  );
}

class RecipeCard extends StatefulWidget {
  const RecipeCard({
    super.key,
    required this.api,
    required this.recipe,
    this.onTap,
    this.cornerAction,
    this.picture,
    this.detail = false,
    this.compact = false,
  });

  final RezeptgartenApi api;
  final Json recipe;
  final VoidCallback? onTap;
  final RecipeCornerAction? cornerAction;
  final Widget? picture;
  final bool detail;
  final bool compact;

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  static const _titleLines = 2;
  static const _badgeLines = 2;
  bool _pressed = false;
  Widget _picture(ThemeData theme, String? duration, String? portions) {
    final colors = theme.colorScheme;
    final hasNote =
        !widget.detail && !widget.compact && widget.recipe['has_note'] == true;
    final action = widget.cornerAction;
    final badgeStyle = theme.textTheme.labelSmall!.copyWith(
      color: colors.onInverseSurface,
      letterSpacing: 0,
    );
    final badgeHeight = widget.detail || widget.compact
        ? 0.0
        : (action != null ? 48.0 : 28.0) +
              _lineHeight(context, badgeStyle) * _badgeLines +
              AppSpacing.tight +
              AppSpacing.connected * 2;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child:
                widget.picture ??
                AnimatedScale(
                  scale: _pressed && !MediaQuery.disableAnimationsOf(context)
                      ? 1.025
                      : 1,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: RecipeImage(
                    api: widget.api,
                    filename:
                        widget.recipe['catalog_image'] ??
                        widget.recipe['image_file'],
                    catalog: widget.recipe['catalog_image'] != null,
                    full: widget.detail,
                  ),
                ),
          ),
          SizedBox(height: max(constraints.maxWidth / 1.8, badgeHeight)),
          if (duration != null || portions != null)
            Positioned(
              left: AppSpacing.tight,
              right: AppSpacing.tight,
              bottom: AppSpacing.tight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: duration == null
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.spaceBetween,
                spacing: AppSpacing.tight,
                children: [
                  if (duration != null)
                    Flexible(
                      child: _metadataBadge(theme, badgeStyle, duration),
                    ),
                  if (portions != null)
                    Flexible(
                      child: _metadataBadge(theme, badgeStyle, portions),
                    ),
                ],
              ),
            ),
          if (hasNote)
            const PositionedDirectional(
              top: AppSpacing.tight,
              start: AppSpacing.tight,
              child: Tooltip(
                message: 'Persönliche Notiz vorhanden',
                child: CircleAvatar(
                  radius: 11,
                  child: Icon(Icons.sticky_note_2_outlined, size: 13),
                ),
              ),
            ),
          if (action != null)
            PositionedDirectional(top: 0, end: 0, child: action),
        ],
      ),
    );
  }

  double _lineHeight(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    final height = painter.preferredLineHeight;
    painter.dispose();
    return height;
  }

  Widget _metadataBadge(ThemeData theme, TextStyle style, String label) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.tight,
            vertical: AppSpacing.connected,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: _badgeLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final recipe = widget.recipe;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final titleStyle = widget.compact
        ? theme.textTheme.labelLarge!
        : theme.textTheme.titleMedium!;
    final difficulty = recipeDifficulty(recipe['difficulty']);
    final difficultyStyle = theme.textTheme.bodySmall!.copyWith(
      color: colors.onSurfaceVariant,
    );
    final seconds = recipe['total_seconds'];
    final offeredServings = recipe['version_servings'];
    final servings = offeredServings is List && offeredServings.isNotEmpty
        ? offeredServings.join(' / ')
        : recipe['servings'];
    final cardShape = theme.cardTheme.shape;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerHigh,
      shape: !widget.detail
          ? (cardShape is OutlinedBorder
                    ? cardShape
                    : const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ))
                .copyWith(side: BorderSide(color: colors.outline))
          : null,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: widget.onTap == null
            ? null
            : (pressed) => setState(() => _pressed = pressed),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: widget.detail
                  ? EdgeInsets.zero
                  : const EdgeInsets.all(AppSpacing.tight),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _picture(
                  theme,
                  !widget.detail && !widget.compact && seconds is num
                      ? '${(seconds / 60).round()} Min.'
                      : null,
                  !widget.detail && !widget.compact && servings != null
                      ? '$servings Port.'
                      : null,
                ),
              ),
            ),
            if (!widget.detail)
              Padding(
                padding: widget.compact
                    ? const EdgeInsets.fromLTRB(8, 4, 8, 8)
                    : AppSpacing.compactPanel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: AppSpacing.tight,
                  children: [
                    SizedBox(
                      height: _lineHeight(context, titleStyle) * _titleLines,
                      child: Text(
                        text(recipe['name'], 'Rezept'),
                        style: titleStyle,
                        maxLines: _titleLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!widget.compact)
                      SizedBox(
                        height: _lineHeight(context, difficultyStyle),
                        child: difficulty == null
                            ? null
                            : Text(
                                difficulty,
                                style: difficultyStyle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RecipeImage extends StatefulWidget {
  const RecipeImage({
    super.key,
    required this.api,
    required this.filename,
    this.full = false,
    this.catalog = false,
  });
  final RezeptgartenApi api;
  final Object? filename;
  final bool full;
  final bool catalog;
  @override
  State<RecipeImage> createState() => _RecipeImageState();
}

class _RecipeImageState extends State<RecipeImage> {
  late Future<Uint8List?> image = _loadImage();

  Future<Uint8List?> _loadImage() => widget.catalog
      ? widget.api.catalogImage(widget.filename, full: widget.full)
      : widget.api.image(widget.filename, full: widget.full);

  @override
  void didUpdateWidget(RecipeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.api != oldWidget.api ||
        widget.filename != oldWidget.filename ||
        widget.catalog != oldWidget.catalog ||
        widget.full != oldWidget.full) {
      image = _loadImage();
    }
  }

  int _decodeWidth(BuildContext context, double width) {
    final pixels = width * MediaQuery.devicePixelRatioOf(context);
    final sizes = widget.full
        ? const [480, 720, 960]
        : const [96, 160, 240, 360, 480];
    return sizes.firstWhere((size) => size >= pixels, orElse: () => sizes.last);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, bounds) => FutureBuilder<Uint8List?>(
        key: ObjectKey(image),
        future: image,
        builder: (context, snapshot) => snapshot.data == null
            ? ColoredBox(
                color: colors.tertiaryContainer,
                child: Center(
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: colors.surfaceContainerLowest,
                    foregroundColor: colors.onSurface,
                    child: const Icon(Icons.eco_outlined, size: 23),
                  ),
                ),
              )
            : Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                cacheWidth: _decodeWidth(context, bounds.maxWidth),
              ),
      ),
    );
  }
}

class RecipeCornerAction extends StatelessWidget {
  const RecipeCornerAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      fixedSize: const Size.square(48),
      minimumSize: const Size.square(48),
      padding: const EdgeInsets.all(AppSpacing.tight),
      alignment: AlignmentDirectional.topEnd,
    ),
    icon: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.tight),
        child: Icon(icon, size: 18),
      ),
    ),
  );
}

class CompactRecipeTile extends StatelessWidget {
  const CompactRecipeTile({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.actionIcon,
    this.leading,
    this.color,
    this.onTap,
    this.onAction,
  });

  final String title;
  final String actionLabel;
  final IconData actionIcon;
  final Widget? leading;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Card(
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    color: color ?? Theme.of(context).colorScheme.surfaceContainerHigh,
    child: ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: AppSpacing.item),
      minTileHeight: 48,
      minLeadingWidth: 0,
      horizontalTitleGap: AppSpacing.tight,
      leading: leading,
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      onTap: onTap,
      trailing: IconButton(
        tooltip: actionLabel,
        onPressed: onAction,
        icon: Icon(actionIcon, size: 18),
      ),
    ),
  );
}
