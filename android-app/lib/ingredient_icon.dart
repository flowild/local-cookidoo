import 'package:material_ui/material_ui.dart';

final _ingredientIcons = {
  for (final (pattern, symbol) in const [
    (r'avocado', '🥑'),
    (r'erdbeer', '🍓'),
    (r'heidelbeer|blaubeer', '🫐'),
    (r'linse|kichererbse|bohne', '🫘'),
    (r'nuss|nüsse|mandel', '🥜'),
    (r'garnele|shrimp', '🦐'),
    (r'schokolade|kuvertüre', '🍫'),
    (r'limonade|cola', '🥤'),
    (r'schwarztee|grüntee|kräutertee|^tee$', '🫖'),
    (r'croissant', '🥐'),
    (r'kuchen|torte', '🍰'),
    (r'pizza', '🍕'),
    (r'toilettenpapier|klopapier|wc.papier|küchenrolle|küchenpapier', '🧻'),
    (r'schwamm|scheuerschw', '🧽'),
    (r'seife', '🧼'),
    (r'reiniger|waschmittel|spülmittel|shampoo', '🧴'),
    (r'zahnbürste|zahnpasta', '🪥'),
    (r'müllbeutel|mülltüte|müllsack', '🗑️'),
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

const _categoryIcons = {
  'Gewürze': '🌿',
  'Gemüse': '🥕',
  'Obst': '🍎',
  'Fleisch': '🥩',
  'Fisch': '🐟',
  'Soßen': '🥣',
  'Öle und Fette': '🫒',
  'Milchprodukte': '🥛',
  'Vorräte und Konserven': '🥫',
  'Backzutaten': '🌾',
  'Brot und Backwaren': '🍞',
  'Getränke': '🥤',
  'Eier': '🥚',
  'Kräuter (tiefgekühlt)': '🌿',
  'Haushalt': '🧽',
};

String shoppingCategoryIcon(String category, Object? selected) =>
    selected is String && selected.isNotEmpty
    ? selected
    : _categoryIcons[category] ?? '🧺';

class IngredientIcon extends StatelessWidget {
  const IngredientIcon(this.name, {this.category, this.selected, super.key});

  final String name;
  final String? category;
  final Object? selected;

  @override
  Widget build(BuildContext context) {
    final custom = selected;
    if (custom is String && custom.isNotEmpty) {
      return ExcludeSemantics(child: Text(custom));
    }
    final value = name.toLowerCase();
    final symbol =
        _ingredientIcons.entries
            .where((entry) => entry.key.hasMatch(value))
            .firstOrNull
            ?.value ??
        _categoryIcons[category] ??
        '🥣';
    return ExcludeSemantics(child: Text(symbol));
  }
}
