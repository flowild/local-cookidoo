"""Build the smallest read-only week snapshot for the encrypted Telegram channel."""
import copy


def snapshot(week, queue, placements):
    days = copy.deepcopy(week['days'])
    for move in queue.get('items', []):
        if move.get('week') and move['week'] != days[0]['date']:
            continue
        source = next((day for day in days if day['date'] == move.get('source')), None)
        target = next((day for day in days if day['date'] == move.get('target')), None)
        if not source and move.get('source') != 'shelf':
            continue
        if not target and move.get('target') not in ('shelf', 'trash'):
            continue
        def matches(recipe):
            return recipe.get('calendar_id') == move.get('recipe_id') and bool(recipe.get('custom')) == bool(move.get('custom'))
        if target and any(matches(recipe) for recipe in target['recipes']):
            continue
        recipe = None
        if source:
            index = next((i for i, item in enumerate(source['recipes']) if matches(item)), None)
            if index is not None:
                recipe = source['recipes'].pop(index)
        else:
            recipe = move.get('recipe')
        if recipe and target:
            target['recipes'].append(recipe)
    def names(recipes):
        return [str(item.get('name') or 'Rezept') for item in recipes]
    return {'today': week['today'],
            'days': [{'date': day['date'], 'recipes': names(day['recipes']),
                      'placeholders': [p['placeholder'] for p in placements if p['target'] == day['date']]} for day in days],
            'shelf': names(week.get('shelf', [])),
            'shelf_placeholders': [p['placeholder'] for p in placements if p['target'] == 'shelf'],
            'queue_phase': queue.get('phase', 'idle'),
            'queue_error': bool(queue.get('error'))}
