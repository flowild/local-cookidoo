import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'spacing.dart';

class RecipeCard extends StatefulWidget {
  const RecipeCard({
    super.key,
    required this.api,
    required this.recipe,
    this.onTap,
    this.cornerAction,
    this.detail = false,
  });

  final RezeptgartenApi api;
  final Json recipe;
  final VoidCallback? onTap;
  final RecipeCornerAction? cornerAction;
  final bool detail;

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  static const _titleLines = 2;
  static const _badgeLines = 2;
  bool _pressed = false;
  late Future<Uint8List?> image = widget.api.image(
    widget.recipe['image_file'],
    full: widget.detail,
  );

  @override
  void didUpdateWidget(RecipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.api != oldWidget.api ||
        widget.recipe['image_file'] != oldWidget.recipe['image_file'] ||
        widget.detail != oldWidget.detail) {
      image = widget.api.image(
        widget.recipe['image_file'],
        full: widget.detail,
      );
    }
  }

  Widget _picture(ThemeData theme, String? duration, String? portions) {
    final colors = theme.colorScheme;
    final hasNote = !widget.detail && widget.recipe['has_note'] == true;
    final action = widget.cornerAction;
    final badgeStyle = theme.textTheme.labelSmall!.copyWith(
      color: colors.onInverseSurface,
      letterSpacing: 0,
    );
    final badgeHeight = widget.detail
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
            child: FutureBuilder<Uint8List?>(
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
                  : AnimatedScale(
                      scale:
                          _pressed && !MediaQuery.disableAnimationsOf(context)
                          ? 1.025
                          : 1,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        cacheWidth: _decodeWidth(context, constraints.maxWidth),
                      ),
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
                spacing: AppSpacing.tight,
                children: [
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.bottomStart,
                      child: duration == null
                          ? null
                          : _metadataBadge(theme, badgeStyle, duration),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.bottomEnd,
                      child: portions == null
                          ? null
                          : _metadataBadge(theme, badgeStyle, portions),
                    ),
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

  int _decodeWidth(BuildContext context, double width) {
    final pixels = width * MediaQuery.devicePixelRatioOf(context);
    final sizes = widget.detail ? const [480, 720, 960] : const [240, 360, 480];
    return sizes.firstWhere((size) => size >= pixels, orElse: () => sizes.last);
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
    final titleStyle = theme.textTheme.titleMedium!;
    final difficultyStyle = theme.textTheme.bodySmall!.copyWith(
      color: colors.onSurfaceVariant,
    );
    final seconds = recipe['total_seconds'];
    final offeredServings = recipe['version_servings'];
    final servings = offeredServings is List && offeredServings.isNotEmpty
        ? offeredServings.join(' / ')
        : recipe['servings'];
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerHigh,
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
                  !widget.detail && seconds is num
                      ? '${(seconds / 60).round()} Min.'
                      : null,
                  !widget.detail && servings != null ? '$servings Port.' : null,
                ),
              ),
            ),
            if (!widget.detail)
              Padding(
                padding: AppSpacing.compactPanel,
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
                    SizedBox(
                      height: _lineHeight(context, difficultyStyle),
                      child: recipe['difficulty'] == null
                          ? null
                          : Text(
                              switch (text(recipe['difficulty'])
                                  .toLowerCase()
                                  .split('.')
                                  .last) {
                                'easy' => 'Einfach',
                                'medium' => 'Mittel',
                                'advanced' || 'hard' => 'Anspruchsvoll',
                                _ => text(recipe['difficulty']),
                              },
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
    this.onTap,
    this.onAction,
  });

  final String title;
  final String actionLabel;
  final IconData actionIcon;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Card(
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
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
