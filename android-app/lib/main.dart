import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'appearance.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RezeptgartenApp(api: RezeptgartenApi()));
}

class RezeptgartenApp extends StatefulWidget {
  const RezeptgartenApp({super.key, required this.api});

  final RezeptgartenApi api;

  @override
  State<RezeptgartenApp> createState() => _RezeptgartenAppState();
}

class _RezeptgartenAppState extends State<RezeptgartenApp> {
  final appearance = AppearanceController();

  @override
  void initState() {
    super.initState();
    unawaited(appearance.restore());
  }

  @override
  void dispose() {
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: appearance,
      builder: (context, current, _) => MaterialApp(
        title: 'Rezeptgarten',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light, current.accent),
        darkTheme: _theme(Brightness.dark, current.accent),
        themeMode: current.dark ? ThemeMode.dark : ThemeMode.light,
        home: RezeptgartenHome(api: widget.api, appearance: appearance),
      ),
    );
  }

  ThemeData _theme(Brightness brightness, int accent) {
    final light = brightness == Brightness.light;
    final selected = Color(accent);
    final colors =
        ColorScheme.fromSeed(
          seedColor: selected,
          brightness: brightness,
        ).copyWith(
          primary: light ? selected : null,
          onPrimary: light
              ? (ThemeData.estimateBrightnessForColor(selected) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black)
              : null,
          surface: light ? const Color(0xfff7f7f2) : null,
          onSurface: light ? const Color(0xff253c31) : null,
          secondaryContainer: light && accent == defaultAccent
              ? const Color(0xffedf1e5)
              : null,
        );
    return ThemeData(
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: light ? Colors.white : colors.surfaceContainer,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: light ? const Color(0xffe5e7dd) : colors.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }
}
