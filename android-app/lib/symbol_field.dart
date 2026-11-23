import 'package:material_ui/material_ui.dart';

class SymbolLabel extends StatelessWidget {
  const SymbolLabel(this.label, this.symbol, {super.key, this.style});

  final String label;
  final Object? symbol;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    symbol is String && symbol != '' ? '$symbol  $label' : label,
    semanticsLabel: label,
    style: style,
  );
}

class SymbolField extends StatelessWidget {
  const SymbolField({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value ?? '',
    decoration: const InputDecoration(labelText: 'Symbol'),
    isExpanded: true,
    onChanged: onChanged == null
        ? null
        : (value) => onChanged!(value == '' ? null : value),
    items: [
      const DropdownMenuItem(value: '', child: Text('Standard')),
      for (final (symbol, label) in const [
        ('🍎', 'Apfel'),
        ('🥕', 'Möhre'),
        ('🌿', 'Kräuter'),
        ('🧂', 'Gewürze'),
        ('🥩', 'Fleisch'),
        ('🐟', 'Fisch'),
        ('🥛', 'Milch'),
        ('🥚', 'Ei'),
        ('🍞', 'Brot'),
        ('🍚', 'Reis'),
        ('🍝', 'Pasta'),
        ('🥫', 'Konserve'),
        ('🧁', 'Gebäck'),
        ('🍲', 'Topf'),
        ('🥗', 'Salat'),
        ('☕', 'Tasse'),
        ('🧊', 'Tiefkühlfach'),
        ('🛒', 'Einkaufswagen'),
        ('📚', 'Bücher'),
        ('⭐', 'Stern'),
        ('❤️', 'Herz'),
        ('🍽️', 'Geschirr'),
        ('🧺', 'Korb'),
        ('🍋', 'Zitrone'),
        ('🥔', 'Kartoffel'),
        ('🍅', 'Tomate'),
        ('🧅', 'Zwiebel'),
        ('🧄', 'Knoblauch'),
        ('🫑', 'Paprika'),
        ('🥦', 'Brokkoli'),
        ('🥒', 'Gurke'),
        ('🍄', 'Pilze'),
        ('🥬', 'Blattgemüse'),
        ('🥑', 'Avocado'),
        ('🌶️', 'Chili'),
        ('🫚', 'Ingwer'),
        ('🍌', 'Banane'),
        ('🍊', 'Orange'),
        ('🍓', 'Erdbeeren'),
        ('🫐', 'Blaubeeren'),
        ('🌾', 'Mehl und Getreide'),
        ('🫘', 'Hülsenfrüchte'),
        ('🥜', 'Nüsse'),
        ('🫒', 'Oliven und Öl'),
        ('🧀', 'Käse'),
        ('🧈', 'Butter'),
        ('🍗', 'Geflügel'),
        ('🦐', 'Garnelen'),
        ('🍯', 'Honig'),
        ('🍫', 'Schokolade'),
        ('🥤', 'Getränke'),
        ('🫖', 'Tee'),
        ('🥐', 'Frühstück'),
        ('🍰', 'Kuchen'),
        ('🍕', 'Pizza'),
        ('🥘', 'Pfanne'),
        ('🥣', 'Schüssel'),
        ('🍱', 'Vorkochen'),
        ('🥡', 'Zum Mitnehmen'),
        ('🧻', 'Toilettenpapier'),
        ('🧽', 'Schwamm'),
        ('🧼', 'Seife'),
        ('🧴', 'Reinigungsmittel'),
        ('🪥', 'Zahnpflege'),
        ('🗑️', 'Müllbeutel'),
      ])
        DropdownMenuItem(value: symbol, child: Text('$symbol  $label')),
    ],
  );
}
