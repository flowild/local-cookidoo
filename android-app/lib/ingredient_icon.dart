import 'package:material_ui/material_ui.dart';

final _ingredientIcons = {
  for (final (pattern, symbol) in const [
    ('chili|cayenne|paprikapulver|paprika edels', '🌶️'),
    ('ingwer|ginger', '🫚'),
    ('öl|oil', '🫒'),
    ('paprika|bell peppers?', '🫑'),
    ('ghee|butterschmalz', '🧈'),
    ('knoblauch', '🧄'),
    ('zwiebel', '🧅'),
    ('kartoffel', '🥔'),
    ('tomate', '🍅'),
    ('karotte|möhre', '🥕'),
    ('gurke', '🥒'),
    ('brokkoli', '🥦'),
    ('pilz|champignon', '🍄'),
    ('salat', '🥬'),
    ('zitrone', '🍋'),
    ('orange', '🍊'),
    ('banane', '🍌'),
    ('apfel|äpfel', '🍎'),
    ('beere', '🫐'),
    ('salz', '🧂'),
    ('pfeffer', '⚫'),
    ('zimt', '🪵'),
    ('kreuzkümmel|kümmel|koriander', '🌱'),
    (
      'oregano|thymian|basilikum|rosmarin|petersilie|schnittlauch|dill|kräuter',
      '🌿',
    ),
    ('curry|kurkuma|muskat', '🥄'),
    ('zucker', '🍬'),
    ('mehl', '🌾'),
    ('stärke', '🥣'),
    ('milch|sahne|joghurt', '🥛'),
    ('käse', '🧀'),
    ('butter', '🧈'),
    (r'ei(?:er)?\b', '🥚'),
    ('hähnchen|huhn', '🍗'),
    ('fleisch|rind|schwein', '🥩'),
    ('fisch|lachs', '🐟'),
    ('reis', '🍚'),
    ('nudel|pasta', '🍝'),
    ('baguette', '🥖'),
    ('brot', '🍞'),
    ('honig', '🍯'),
    ('wasser', '💧'),
  ])
    RegExp(pattern): symbol,
};

class IngredientIcon extends StatelessWidget {
  const IngredientIcon(this.name, {this.category, super.key});

  final String name;
  final String? category;

  @override
  Widget build(BuildContext context) {
    const fallback = {
      'Gewürze': '🌿',
      'Gemüse': '🥕',
      'Obst': '🍎',
      'Fleisch': '🥩',
      'Fisch': '🐟',
      'Soßen': '🥫',
      'Öle und Fette': '🫒',
      'Milchprodukte': '🥛',
      'Vorräte und Konserven': '🥫',
      'Backzutaten': '🌾',
      'Getränke': '🥤',
      'Kräuter (tiefgekühlt)': '🌿',
    };
    final value = name.toLowerCase();
    final symbol =
        _ingredientIcons.entries
            .where((entry) => entry.key.hasMatch(value))
            .firstOrNull
            ?.value ??
        fallback[category] ??
        '🥣';
    return ExcludeSemantics(child: Text(symbol));
  }
}
