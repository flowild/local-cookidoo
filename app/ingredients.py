"""Conservative ingredient names for suggestions and future recipe matching."""
import re
import unicodedata


def ingredient_key(name):
    return ' '.join(unicodedata.normalize('NFKC', name).split()).casefold()


_PREPARATION = re.compile(r'^\s*(?:gemahlen|gerieben|gehackt|zerkleinert|in stücken|gewürfelt|geschnitten|geschält|frisch|getrocknet|tiefgekühlt|tk|kalt|heiss|warm|lauwarm|kochend|ohne knochen|ground|grated|chopped|diced|sliced|peeled|fresh|dried|frozen)\b', re.IGNORECASE)
_ALIASES = {
    'stärke': 'speisestärke',
    'bio-vanille': 'vanilleextrakt',
    'bio vanille': 'vanilleextrakt',
    'bio-vanilleextrakt': 'vanilleextrakt',
    'bio vanilleextrakt': 'vanilleextrakt',
    'vanilla extract': 'vanilleextrakt',
    'cumin': 'kreuzkümmel',
    'kreuzkümmelsamen': 'kreuzkümmel',
    'muskat': 'muskatnuss',
    'paprikapulver edelsüss': 'paprika edelsüss',
    'paprikapulver, edelsüss': 'paprika edelsüss',
    'paprika edelsuss': 'paprika edelsüss',
    'pfeffer': 'schwarzer pfeffer',
    'pfeffer schwarz': 'schwarzer pfeffer',
    'chicken': 'hähnchen', 'chicken meat': 'hähnchen', 'hähnchenfleisch': 'hähnchen',
    'chicken breast': 'hähnchenbrust', 'chicken breasts': 'hähnchenbrust', 'chicken breast fillet': 'hähnchenbrust', 'chicken breast fillets': 'hähnchenbrust', 'hähnchenbrustfilet': 'hähnchenbrust', 'hähnchenbrustfilets': 'hähnchenbrust',
    'chicken thigh': 'hähnchen-oberschenkel', 'chicken thighs': 'hähnchen-oberschenkel',
    'beef': 'rindfleisch', 'pork': 'schweinefleisch', 'lamb': 'lammfleisch',
    'garlic': 'knoblauch', 'onion': 'zwiebeln', 'onions': 'zwiebeln', 'zwiebel': 'zwiebeln',
    'tomato': 'tomaten', 'tomatoes': 'tomaten', 'tomate': 'tomaten',
    'potato': 'kartoffeln', 'potatoes': 'kartoffeln', 'kartoffel': 'kartoffeln',
    'carrot': 'karotten', 'carrots': 'karotten', 'karotte': 'karotten', 'möhre': 'karotten', 'möhren': 'karotten',
    'bell pepper': 'paprika', 'bell peppers': 'paprika',
    'mushroom': 'champignons', 'mushrooms': 'champignons', 'champignon': 'champignons',
    'milk': 'milch', 'cream': 'sahne', 'butter': 'butter', 'egg': 'eier', 'eggs': 'eier', 'ei': 'eier',
    'flour': 'mehl', 'sugar': 'zucker', 'salt': 'salz', 'water': 'wasser',
    'oil': 'öl', 'cooking oil': 'öl', 'vegetable oil': 'pflanzenöl', 'olive oil': 'olivenöl', 'sunflower oil': 'sonnenblumenöl', 'rapeseed oil': 'rapsöl', 'canola oil': 'rapsöl',
    'rice': 'reis', 'pasta': 'nudeln', 'noodles': 'nudeln', 'nudel': 'nudeln', 'spaghetti': 'nudeln',
    'parsley': 'petersilie', 'chives': 'schnittlauch', 'basil': 'basilikum', 'rosemary': 'rosmarin', 'thyme': 'thymian',
    'cinnamon': 'zimt', 'turmeric': 'kurkuma', 'ginger': 'ingwer', 'nutmeg': 'muskatnuss', 'black pepper': 'schwarzer pfeffer',
    'lemon': 'zitrone', 'lemons': 'zitrone', 'lime': 'limette', 'limes': 'limette',
    'vegetable broth': 'gemüsebrühe', 'vegetable stock': 'gemüsebrühe',
}

_COOKING_OILS = {
    'öl', 'speiseöl', 'pflanzenöl', 'olivenöl', 'rapsöl', 'sonnenblumenöl',
    'kokosöl', 'erdnussöl', 'sesamöl', 'avocadoöl', 'maisöl', 'mais keimöl',
    'maiskeimöl', 'distelöl', 'sojaöl', 'traubenkernöl', 'walnussöl',
    'leinöl', 'kürbiskernöl', 'hanföl', 'reiskeimöl', 'senföl', 'haselnussöl',
    'macadamiaöl', 'pistazienöl', 'mandelöl',
}


def matching_key(name):
    """Match explicit synonyms and common preparation notes, never arbitrary substrings."""
    text = ingredient_key(name)
    # Cumin is an alternative name, not a separate ingredient.
    text = re.sub(r'\s*\(\s*cumin\s*\)', '', text)
    text = re.sub(r'\s*\(\s*(gemahlen|gerieben|getrocknet|tiefgekühlt)\s*\)', '', text)
    parts = text.split(',', 1)
    if len(parts) == 2 and _PREPARATION.match(parts[1]):
        text = parts[0].strip()
    text = re.sub(r'^(?:gemahlener|gemahlenes|gemahlene|getrockneter|getrocknete|getrocknetes|ground|grated|chopped|diced|sliced|fresh|dried|frozen)\s+', '', text)
    text = re.sub(r'\s+(?:gemahlen|gerieben|getrocknet|tiefgekühlt)$', '', text)
    text = re.sub(r'\s+(?:und etwas mehr|nach geschmack|und mehr zum kochen der nudeln)\s*$', '', text)
    text = ' '.join(text.split()).strip()
    if re.match(r'^wasser\s+und\s+(?:etwas\s+)?mehr\b', text):
        return 'wasser'
    if re.fullmatch(r'(?:kaltes|heisses|warmes|kochendes|lauwarmes) wasser', text):
        return 'wasser'
    return _ALIASES.get(text, text)


def ingredient_group_key(name):
    """Group equivalent labels without merging different ingredient types."""
    key = matching_key(name)
    broth = r'(?:gemüsebrühe|gemüsebouillon)'
    if re.fullmatch(rf'(?:geh\.?\s*tl\s+|gestr\.?\s*tl\s+|würfel\s+)?(?:gewürzpaste\s+für\s+)?{broth}(?:\s*\([^)]*\))?(?:\s*,\s*selbst gemacht)?', key):
        return 'gemüsebrühe'
    if re.fullmatch(r'gemüsebouillon\s+paste', key):
        return 'gemüsebrühe'
    return key


def ingredient_aliases(name):
    key = ingredient_group_key(name)
    return sorted(alias for alias, target in _ALIASES.items() if target == key and alias != key)


def ingredient_search_text(name):
    return ' | '.join([ingredient_key(name), ingredient_group_key(name), *ingredient_aliases(name)])


def ingredient_display_name(name):
    key = ingredient_group_key(name)
    labels = {'gemüsebrühe':'Gemüsebrühe', 'kreuzkümmel':'Kreuzkümmel', 'muskatnuss':'Muskatnuss', 'schwarzer pfeffer':'Schwarzer Pfeffer', 'paprika edelsüss':'Paprika edelsüß', 'wasser':'Wasser', 'hähnchen':'Hähnchen', 'hähnchenbrust':'Hähnchenbrust', 'hähnchen-oberschenkel':'Hähnchen-Oberschenkel', 'rindfleisch':'Rindfleisch', 'schweinefleisch':'Schweinefleisch', 'lammfleisch':'Lammfleisch', 'knoblauch':'Knoblauch', 'zwiebeln':'Zwiebeln', 'tomaten':'Tomaten', 'kartoffeln':'Kartoffeln', 'karotten':'Karotten', 'champignons':'Champignons', 'öl':'Öl', 'olivenöl':'Olivenöl', 'rapsöl':'Rapsöl', 'sonnenblumenöl':'Sonnenblumenöl', 'pflanzenöl':'Pflanzenöl', 'nudeln':'Nudeln'}
    if key in labels:
        return labels[key]
    display = ' '.join(unicodedata.normalize('NFKC', name).split())
    if ingredient_key(display) == key:
        return display
    display = re.sub(r'\s*\(\s*(cumin|gemahlen|gerieben|getrocknet|tiefgekühlt)\s*\)', '', display, flags=re.IGNORECASE)
    parts = display.split(',', 1)
    if len(parts) == 2 and _PREPARATION.match(ingredient_key(parts[1])):
        display = parts[0].strip()
    display = re.sub(r'^(?:gemahlener|gemahlenes|gemahlene|getrockneter|getrocknete|getrocknetes)\s+', '', display, flags=re.IGNORECASE)
    display = re.sub(r'\s+(?:gemahlen|gerieben|getrocknet|tiefgekühlt)$', '', display, flags=re.IGNORECASE).strip()
    if ingredient_key(display) == key:
        return display[:1].upper() + display[1:]
    return key[:1].upper() + key[1:] if key else ''


def ingredient_available(name, pantry_names):
    key = ingredient_group_key(name)
    if not key:
        return False
    if key == 'wasser':
        return True
    if key in {'öl', 'speiseöl', 'pflanzenöl'}:
        return any(ingredient_group_key(item) in _COOKING_OILS for item in pantry_names)
    return any(key == ingredient_group_key(item) for item in pantry_names)


_QUANTITY = re.compile(r'^\s*(?:(?:\d+(?:[.,]\d+)?(?:\s*/\s*\d+)?|[½⅓⅔¼¾⅛⅜⅝⅞]+)(?:\s+|\s*(?=[a-zA-ZäöüÄÖÜ])))+')
_UNIT = re.compile(r'^(?:g|kg|mg|ml|cl|dl|l|el|tl|teelöffel|esslöffel|prisen?|prise[n]?|stück|stücke|packung(?:en)?|päckchen|dose[n]?|glas|gläser|bund|zweige?|blätter|blatt|zehen?|scheiben?|tassen?|becher|oz|lb|lbs|tsp|tbsp|cups?|cloves?)\b\.?\s*', re.IGNORECASE)
_EXTRA = re.compile(r'\s+(?:und etwas mehr|nach geschmack|zum garnieren|zum servieren)\s*$', re.IGNORECASE)


def ingredient_name(value):
    if isinstance(value, dict):
        name = value.get('name')
        return ' '.join(name.split()) if isinstance(name, str) else ''
    if not isinstance(value, str):
        return ''
    text = re.sub(r'^\s*[-•–—]\s*', '', value.strip())
    text = _QUANTITY.sub('', text)
    text = _UNIT.sub('', text).strip()
    text = re.split(r'\s*,\s*|\s*\(', text, maxsplit=1)[0].strip()
    text = _EXTRA.sub('', text).strip(' ,.;')
    return ' '.join(text.split())


# Warenbereiche für Zutaten ohne persönliche Vorratszuordnung.
_SHOPPING_CATEGORIES = (
    ('Gewürze', r'gewürz|gewuerz|pfeffer|salz|curry|kurkuma|kümmel|cumin|koriander|paprikapulver|zimt|muskat|chilipulver|chili.?flocken|oregano|thymian|rosmarin'),
    ('Obst', r'apfel|äpfel|birne|zitrone|limette|orange|banane|beere|mango|ananas|pfirsich|obst'),
    ('Gemüse', r'knoblauch|zwiebel|lauch|karotte|möhre|paprika|tomate|kartoffel|sellerie|brokkoli|blumenkohl|zucchini|gurke|spinat|chili|champignon|pilz|ingwer|salat|petersilie|basilikum|schnittlauch|gemüse|kraut'),
    ('Fisch', r'fisch|lachs|thunfisch|garnelen|shrimp|seelachs|kabeljau|forelle|meeresfrüchte'),
    ('Fleisch', r'hähnchen|hühn|chicken|rind|schwein|lamm|hackfleisch|fleisch|speck|wurst|schinken|pute'),
    ('Milchprodukte', r'milch|sahne|joghurt|quark|käse|parmesan|mozzarella|schmand|crème fraîche|creme fraiche|mascarpone'),
    ('Öle und Fette', r'öl|butter|ghee|margarine|schmalz'),
    ('Backzutaten', r'mehl|stärke|zucker|backpulver|hefe|vanille|kakao|schokolade|kuvertüre|puderzucker|süßungsmittel|honig'),
    ('Brot und Backwaren', r'brot|baguette|brötchen|toast|croissant|tortilla'),
    ('Soßen', r'soße|sauce|sosse|paste|pesto|senf|ketchup|mayonnaise|essig'),
    ('Vorräte und Konserven', r'brühe|bouillon|fond|reis|nudel|pasta|linsen|bohnen|kichererbsen|erbsen|mais|konserve|dose|tomatenmark|couscous|quinoa|haferflocken'),
    ('Getränke', r'wein|bier|saft|kaffee|tee|likör|rum'),
    ('Eier', r'^ei(?:er)?$'),
)

def shopping_category(name, pantry_categories=None):
    key = ingredient_group_key(name)
    if pantry_categories and key in pantry_categories:
        return pantry_categories[key]
    for category, pattern in _SHOPPING_CATEGORIES:
        if re.search(pattern, key, re.IGNORECASE):
            return category
    return 'Sonstiges'
