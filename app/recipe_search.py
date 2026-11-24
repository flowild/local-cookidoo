"""Parse the Web search field into shared recipe search criteria."""
import re
from dataclasses import dataclass

from .ingredients import ingredient_key, ingredient_name, ingredient_search_text

DIFFICULTIES = {
    'einfach': 'easy', 'leicht': 'easy', 'easy': 'easy',
    'mittel': 'medium', 'medium': 'medium',
    'anspruchsvoll': 'hard', 'schwierig': 'hard', 'schwer': 'hard',
    'advanced': 'hard', 'hard': 'hard',
}
TIME = re.compile(r'(?:bis\s+|max(?:imal)?\.?\s*|<=\s*)?(\d+)\s*(?:min(?:uten)?\.?|minute)')
PORTIONS = re.compile(r'(\d+)\s*portion(?:en)?')


@dataclass(frozen=True)
class RecipeSearch:
    text: str = ''
    ingredients: tuple[str, ...] = ()
    minutes: int | None = None
    portions: int | None = None
    difficulty: str | None = None
    title_only: bool = False

    @property
    def filtered(self):
        return bool(self.ingredients or self.minutes or self.portions or self.difficulty or self.title_only)

    def matches(self, detail, ingredients):
        if self.title_only and self.text.casefold() not in detail["name"].casefold():
            return False
        if self.minutes and not (0 < (detail['total_seconds'] or 0) <= self.minutes * 60):
            return False
        if self.portions and str(detail.get('servings') or '').strip() != str(self.portions):
            return False
        if self.difficulty and DIFFICULTIES.get(str(detail.get('difficulty') or '').lower()) != self.difficulty:
            return False
        names = [ingredient_name(item) for item in ingredients]
        index = [(ingredient_key(name), ingredient_search_text(name)) for name in names if name]
        return all(any(needle in name or needle in aliases for name, aliases in index)
                   for term in self.ingredients if (needle := ingredient_key(term)))


def parse_recipe_search(query):
    terms = []
    for part in query.split(','):
        part = part.strip()
        if not part:
            continue
        if part.casefold().startswith(('titel:', 'zutat:')):
            terms.append(part)
            continue
        pattern = r'(?:bis\s+|max(?:imal)?\.?\s*|<=\s*)?\d+\s*(?:min(?:uten)?\.?|minute|portion(?:en)?)|\S+'
        terms.extend(re.findall(pattern, part, flags=re.IGNORECASE))
    text = ''
    title_only = False
    ingredients = []
    minutes = portions = difficulty = None
    for term in terms:
        folded = term.casefold()
        if match := TIME.fullmatch(folded):
            value = int(match[1])
            if not 1 <= value <= 10080:
                raise ValueError('Die Gesamtzeit muss zwischen 1 und 10080 Minuten liegen.')
            minutes = min(minutes or value, value)
        elif match := PORTIONS.fullmatch(folded):
            value = int(match[1])
            if not 1 <= value <= 1000:
                raise ValueError('Die Portionszahl muss zwischen 1 und 1000 liegen.')
            if portions is not None and portions != value:
                raise ValueError('Bitte gib nur eine Portionszahl an.')
            portions = value
        elif folded in DIFFICULTIES:
            value = DIFFICULTIES[folded]
            if difficulty is not None and difficulty != value:
                raise ValueError('Bitte gib nur einen Schwierigkeitsgrad an.')
            difficulty = value
        elif folded.startswith('titel:'):
            title = term.partition(':')[2].strip()
            if text or not title:
                raise ValueError('Bitte gib nach „Titel:“ einen Suchbegriff an.')
            text = title
            title_only = True
        elif folded.startswith('zutat:'):
            ingredient = term.partition(':')[2].strip()
            if not ingredient:
                raise ValueError('Bitte gib nach „Zutat:“ eine Zutat an.')
            ingredients.append(ingredient)
        elif len(terms) == 1:
            text = term
        else:
            ingredients.append(term)
    if len(ingredients) > 20 or any(len(term) > 100 for term in ingredients):
        raise ValueError('Bitte gib höchstens 20 Zutaten mit je maximal 100 Zeichen an.')
    return RecipeSearch(text, tuple(ingredients), minutes, portions, difficulty, title_only)
