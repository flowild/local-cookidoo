"""Local shopping cart snapshots and explicit Cookidoo transfer."""
import dataclasses
import json
import logging

from .ingredients import ingredient_available, ingredient_group_key, ingredient_name

logger = logging.getLogger(__name__)


def recipe_snapshot(recipe, pantry_names):
    complete = recipe.get('ingredients_json') is not None
    try:
        ingredients = json.loads(recipe.get('ingredients_json') or '[]')
    except (TypeError, ValueError):
        ingredients = []
        complete = False
    if not isinstance(ingredients, list):
        ingredients = []
        complete = False
    items = []
    for item in ingredients if isinstance(ingredients, list) else []:
        name = ingredient_name(item)
        if isinstance(item, dict):
            description = str(item.get('description') or item.get('name') or '').strip()
            if name and name.casefold() not in description.casefold():
                description = (description + ' ' + name).strip()
        else:
            description = str(item).strip() if isinstance(item, str) else ''
        if name or description:
            items.append({'name': name, 'key': ingredient_group_key(name) if name else '', 'text': description, 'owned': ingredient_available(name, pantry_names) if name else False})
    return {'id': recipe['id'], 'name': recipe.get('name') or 'Rezept',
            'image_file': recipe.get('image_file'), 'servings': recipe.get('servings'),
            'total_seconds': recipe.get('total_seconds'), 'difficulty': recipe.get('difficulty'),
            'image_url': recipe.get('image_url'), 'ingredients': items, 'ingredients_complete': complete}


async def remote_recipe_snapshot(service, identifier, custom, pantry_names):
    recipe_id = ('creation:' if custom else '') + identifier
    local = service.database.recipe(recipe_id)
    if local and local.get('ingredients_json'):
        return recipe_snapshot(local, pantry_names)
    detail = await (service.client.get_custom_recipe(identifier) if custom else service.client.get_recipe_details(identifier))
    ingredients = [dataclasses.asdict(item) if dataclasses.is_dataclass(item) else item for item in detail.ingredients]
    image_url = getattr(detail, 'image', None) or getattr(detail, 'thumbnail', None)
    image_file = (local or {}).get('image_file') or service.calendar_image_reference(image_url)
    total_time = getattr(detail, 'total_time', None)
    total_seconds = max(0, int(total_time.total_seconds())) if hasattr(total_time, 'total_seconds') else max(0, int(total_time)) if isinstance(total_time, (int, float)) else None
    return recipe_snapshot({'id': recipe_id, 'name': detail.name, 'servings': str(detail.serving_size) if detail.serving_size else None,
                            'total_seconds': total_seconds, 'difficulty': str(getattr(detail, 'difficulty', '') or '') or None,
                            'image_file': image_file, 'image_url': str(image_url) if image_file and image_url else None,
                            'ingredients_json': json.dumps(ingredients, ensure_ascii=False)}, pantry_names)


async def transfer(service):
    if service.cart_transferring or service.lock.locked() or service.state['running']:
        raise ValueError('Bitte warte, bis die aktuelle Übertragung oder Synchronisierung fertig ist.')
    service.cart_transferring = True
    try:
        async with service.lock:
            if not service.client or not service.database.get('account'):
                raise ValueError('Bitte verbinde zuerst dein Cookidoo-Konto.')
            owner = service.cart_owner()
            entries = service.database.cart(owner)
            if any(row['status'] in ('processing', 'uncertain') for row in entries):
                raise ValueError('Eine frühere Übertragung ist ungeklärt. Bitte prüfe sie in Cookidoo und bestätige den Status im Einkaufswagen.')
            existing = {str(item.id).removeprefix('creation:') for item in await service.client.get_shopping_list_recipes()}
            if any(row['kind'] == 'recipe' and row['status'] == 'pending' and row['recipe_id'].removeprefix('creation:') not in existing and not row['data'].get('ingredients_complete', True) for row in entries):
                raise ValueError('Für ein Rezept fehlen die Zutaten. Bitte synchronisiere die Sammlung und füge das Rezept erneut hinzu.')
            for row in entries:
                if row['kind'] != 'recipe' or row['status'] != 'pending' or row['recipe_id'].removeprefix('creation:') in existing:
                    continue
                selections = {}
                for item in row['data']['ingredients']:
                    key = ingredient_group_key(item['name']) if item['name'] else ''
                    if key:
                        selections.setdefault(key, set()).add(bool(item['owned']))
                if any(len(values) > 1 for values in selections.values()):
                    raise ValueError('Gleiche Zutaten in einem Rezept sind unterschiedlich abgehakt. Bitte gleiche ihre Markierungen an.')
            for row in entries:
                if row['status'] != 'pending':
                    continue
                if row['kind'] == 'recipe':
                    source = row['recipe_id'].removeprefix('creation:')
                    if source in existing:
                        service.database.cart_update(owner, row['id'], status='existing', expected='pending')
                        continue
                if not service.database.cart_update(owner, row['id'], status='processing', expected='pending', expected_data=row['data']):
                    return {'status': 'partial', 'message': 'Der Einkaufswagen wurde während der Übertragung verändert. Bitte prüfe die übrigen Einträge.'}
                try:
                    if row['kind'] == 'recipe':
                        custom = row['recipe_id'].startswith('creation:')
                        method = service.client.add_ingredient_items_for_custom_recipes if custom else service.client.add_ingredient_items_for_recipes
                        remote_items = await method([source])
                        confirmed = {str(item.id).removeprefix('creation:') for item in await service.client.get_shopping_list_recipes()}
                        if source not in confirmed:
                            raise ValueError('Recipe addition not confirmed')
                        existing.add(source)
                        wanted = {}
                        for item in row['data']['ingredients']:
                            key = ingredient_group_key(item['name']) if item['name'] else ''
                            if key:
                                wanted.setdefault(key, set()).add(bool(item['owned']))
                        if any(len(values) > 1 for values in wanted.values()):
                            raise ValueError('Conflicting ingredient selections')
                        remote_by_key = {}
                        for item in remote_items:
                            name = getattr(item, 'name', None) or ingredient_name(getattr(item, 'description', '') or '')
                            key = ingredient_group_key(name) if name else ''
                            if key:
                                remote_by_key.setdefault(key, []).append(item)
                        owned_keys = {key for key, values in wanted.items() if True in values}
                        if not owned_keys.issubset(remote_by_key):
                            raise ValueError('Ingredient selection cannot be matched')
                        changes = []
                        for key in owned_keys:
                            for item in remote_by_key[key]:
                                if not item.is_owned:
                                    item.is_owned = True
                                    changes.append(item)
                        if changes:
                            marked = await service.client.edit_ingredient_items_ownership(changes)
                            if not {str(item.id) for item in changes}.issubset({str(item.id) for item in marked if item.is_owned}):
                                raise ValueError('Ingredient ownership not confirmed')
                    else:
                        added = await service.client.add_additional_items([row['data']['name']])
                        if len(added) != 1 or not getattr(added[0], 'id', None):
                            raise ValueError('Additional item not confirmed')
                        if row['data'].get('owned'):
                            added[0].is_owned = True
                            marked = await service.client.edit_additional_items_ownership(added)
                            if not any(str(item.id) == str(added[0].id) and item.is_owned for item in marked):
                                raise ValueError('Additional item ownership not confirmed')
                    service.database.cart_update(owner, row['id'], status='done', expected='processing')
                except Exception as error:
                    logger.warning('Shopping cart transfer unconfirmed: %s', type(error).__name__)
                    service.database.cart_update(owner, row['id'], status='uncertain', expected='processing')
                    return {'status': 'partial', 'message': 'Die Übertragung konnte nicht vollständig bestätigt werden. Bitte prüfe Cookidoo und bestätige den Eintrag im Einkaufswagen.'}
            return {'status': 'ok'}
    finally:
        service.cart_transferring = False
