import 'package:material_ui/material_ui.dart';

import 'appearance.dart';
import 'spacing.dart';

ThemeData rezeptgartenTheme(Brightness brightness, int accent) {
  // The default roles follow the light and dark variables in app/static/style.css.
  final dark = brightness == Brightness.dark;
  final seed = Color(accent);
  final customAccent = accent != defaultAccent;
  final paper = dark ? const Color(0xff102729) : const Color(0xfff7f7f2);
  final card = dark ? const Color(0xff1b383a) : Colors.white;
  final ink = dark ? const Color(0xffe4f1ef) : const Color(0xff253c31);
  final soft = dark ? const Color(0xff294a4b) : const Color(0xffedf1e5);
  final line = dark ? const Color(0xff36585a) : const Color(0xffe5e7dd);
  final standardAccent = dark
      ? const Color(0xff8fc9c5)
      : const Color(defaultAccent);
  final accentScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final primary = customAccent ? accentScheme.primary : standardAccent;
  final onPrimary = customAccent
      ? accentScheme.onPrimary
      : (dark ? const Color(0xff102b2c) : Colors.white);
  final accentSurface = customAccent
      ? Color.alphaBlend(seed.withValues(alpha: .14), card)
      : soft;
  final colors = accentScheme.copyWith(
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: accentSurface,
    onPrimaryContainer: ink,
    secondary: primary,
    onSecondary: onPrimary,
    secondaryContainer: accentSurface,
    onSecondaryContainer: ink,
    tertiary: primary,
    onTertiary: onPrimary,
    tertiaryContainer: soft,
    onTertiaryContainer: ink,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: dark ? const Color(0xffaec8c6) : const Color(0xff59665b),
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: card,
    surfaceContainerHigh: card,
    surfaceContainerHighest: soft,
    outline: dark ? const Color(0xff789996) : const Color(0xff788376),
    outlineVariant: line,
    inverseSurface: ink,
    onInverseSurface: paper,
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
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
      ).copyWith(shape: actionShape, animationDuration: Durations.short4),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
      ).copyWith(shape: actionShape, animationDuration: Durations.short4),
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
