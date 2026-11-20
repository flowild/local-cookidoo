import 'package:material_ui/material_ui.dart';

import 'spacing.dart';

ThemeData rezeptgartenTheme(Brightness brightness, int accent) {
  final seed = Color(accent);
  final accentColors = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final colors =
      ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      ).copyWith(
        primary: accentColors.primary,
        onPrimary: accentColors.onPrimary,
        primaryContainer: accentColors.primaryContainer,
        onPrimaryContainer: accentColors.onPrimaryContainer,
        inversePrimary: accentColors.inversePrimary,
      );
  const pill = StadiumBorder();
  const cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(24)),
  );
  final base = ThemeData(colorScheme: colors);
  final type = base.textTheme;
  final navigationLabel = type.labelSmall!.copyWith(letterSpacing: 0);
  final actionShape = WidgetStateProperty.resolveWith<OutlinedBorder>((states) {
    return states.contains(WidgetState.pressed)
        ? const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          )
        : pill;
  });

  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    textTheme: type.copyWith(
      headlineLarge: type.headlineLarge!.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: type.headlineMedium!.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
      ),
      titleLarge: type.titleLarge!.copyWith(fontWeight: FontWeight.w600),
      titleMedium: type.titleMedium!.copyWith(fontWeight: FontWeight.w600),
      labelLarge: type.labelLarge!.copyWith(fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
      titleTextStyle: type.titleLarge!.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.section),
      horizontalTitleGap: AppSpacing.related,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      titleTextStyle: type.headlineSmall!.copyWith(
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48))
          .copyWith(shape: actionShape, animationDuration: Durations.short4),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48))
          .copyWith(shape: actionShape, animationDuration: Durations.short4),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.section,
        vertical: AppSpacing.item,
      ),
      fillColor: colors.surfaceContainerHighest,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: colors.secondaryContainer,
      labelStyle: type.labelMedium!.copyWith(
        color: colors.onSecondaryContainer,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: pill,
      elevation: 0,
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? navigationLabel.copyWith(fontWeight: FontWeight.w700)
            : navigationLabel,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.secondaryContainer,
      indicatorShape: pill,
      selectedLabelTextStyle: navigationLabel.copyWith(
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: navigationLabel,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.primary,
      linearTrackColor: colors.primaryContainer,
      linearMinHeight: 6,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      strokeCap: StrokeCap.round,
      trackGap: 4,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );
}
