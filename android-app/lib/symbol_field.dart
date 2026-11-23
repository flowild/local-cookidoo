import 'package:material_ui/material_ui.dart';

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
      ])
        DropdownMenuItem(value: symbol, child: Text('$symbol  $label')),
    ],
  );
}
