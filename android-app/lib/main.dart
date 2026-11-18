import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(RezeptgartenApp(api: RezeptgartenApi()));
}

class RezeptgartenApp extends StatelessWidget {
  const RezeptgartenApp({super.key, required this.api});

  final RezeptgartenApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rezeptgarten',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: RezeptgartenHome(api: api),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final light = brightness == Brightness.light;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff234d3c),
          brightness: brightness,
        ).copyWith(
          primary: light ? const Color(0xff234d3c) : null,
          surface: light ? const Color(0xfff7f7f2) : null,
          onSurface: light ? const Color(0xff253c31) : null,
          secondaryContainer: light ? const Color(0xffedf1e5) : null,
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
