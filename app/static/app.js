'use strict';
const $ = selector => document.querySelector(selector);
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
const photo = (file, alt = '', eager = false) => file ? `<img data-recipe-image src="/api/images/${encodeURIComponent(file)}" alt="${escapeHTML(alt)}" loading="${eager ? 'eager' : 'lazy'}" decoding="async">` : `<span class="image-placeholder" aria-label="Kein Rezeptbild verfügbar">${icon('bowl')}</span>`;
const state = {status:null, collections:[], recipes:[], total:0, offset:0, view:'uebersicht', collection:null, query:'', sort:'name', filters:{ingredient:'',minServings:'',maxMinutes:''}, request:0, candidateQuery:'', candidateOffset:0, candidateRequest:0, pantry:{categories:[],items:[]}, pantryFilter:'', pantryEdit:null};
let deferredInstall = null, toastTimer, searchTimer, candidateTimer, polling = false;
let suggestionTimer, suggestionRequest = 0, selectedIngredient = null, suggestionItems = [], suggestionIndex = -1;
let recipeIngredientOptions = [], recipeIngredientAliases = {}, recipeIngredientMatches = [], recipeIngredientIndex = -1;
let featuredLocalDay = null;
let collapsedPantry = new Set();
let pantryDrag = null, pantryReordering = false;
try { const saved = JSON.parse(localStorage.getItem('rezeptgarten-pantry-collapsed') || '[]'); if (Array.isArray(saved)) collapsedPantry = new Set(saved.filter(Number.isInteger)); } catch (_) {}

function toast(message) {
  const node = $('#toast');
  const modal = document.querySelector('dialog:modal');
  const target = modal || document.body;
  if (node.parentElement !== target) target.append(node);
  node.textContent = message;
  node.hidden = false;
  if (typeof node.showPopover === 'function') {
    node.setAttribute('popover', 'manual');
    if (!node.matches(':popover-open')) node.showPopover();
  }
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    if (typeof node.hidePopover === 'function' && node.matches(':popover-open')) node.hidePopover();
    node.hidden = true;
  }, 6500);
}
function errorMessage(node, message) { node.textContent = message || ''; node.hidden = !message; }
function formatDate(value, brief = false) {
  if (!value) return 'Noch nicht synchronisiert';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Noch nicht synchronisiert';
  return new Intl.DateTimeFormat('de-DE', brief ? {day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit',timeZone:'Europe/Berlin'} : {dateStyle:'medium',timeStyle:'short',timeZone:'Europe/Berlin'}).format(date);
}
function duration(seconds) {
  if (!seconds) return '';
  const minutes = Math.ceil(seconds / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)} Std.${minutes % 60 ? ` ${minutes % 60} Min.` : ''}` : `${minutes} Min.`;
}
async function api(path, options = {}) {
  let response;
  try {
    response = await fetch(path, {credentials:'same-origin', ...options, headers:{'Content-Type':'application/json', ...options.headers}});
  } catch (_) {
    $('#offline-banner').textContent = 'Keine Verbindung zu deinem Rezeptgarten-Server. Prüfe die Verbindung zum Heimnetz.';
    $('#offline-banner').hidden = false;
    throw new Error('Dein Server ist gerade nicht erreichbar. Prüfe deine Verbindung zum Heimnetz.');
  }
  if (navigator.onLine) $('#offline-banner').hidden = true;
  let payload;
  try { payload = await response.json(); } catch (_) { throw new Error('Die Serverantwort konnte nicht gelesen werden. Bitte versuche es erneut.'); }
  if (!response.ok) {
    throw new Error(typeof payload.detail === 'string' ? payload.detail : 'Bitte prüfe die Eingaben und versuche es erneut.');
  }
  return payload;
}
const post = (path, body = {}) => api(path, {method:'POST',body:JSON.stringify(body)});

async function loadLibrary() {
  const [status, collections] = await Promise.all([api('/api/status'), api('/api/collections')]);
  state.status = status; state.collections = collections.items;
  $('#nav-list-count').textContent = status.stats.collections;
  $('#nav-recipe-count').textContent = status.stats.recipes;
  updateSync();
  await renderRoute();
}
function updateSync() {
  if (!state.status) return;
  const sync = state.status.sync;
  const button = $('#sync-button');
  button.disabled = sync.running;
  button.querySelector('svg').classList.toggle('spinning', sync.running);
  button.querySelector('span').textContent = sync.running ? 'Lädt …' : 'Synchronisieren';
  $('#connection-label').innerHTML = `<span><span class="status-dot"></span>${state.status.connected ? 'Mit Cookidoo verbunden' : 'Lokale Sammlung'}</span><span class="last-sync">${state.status.stats.last_sync ? `Letzter Abgleich: ${escapeHTML(formatDate(state.status.stats.last_sync))}` : 'Noch nicht synchronisiert'}</span>`;
  $('#sync-progress').hidden = !sync.running;
  $('#sync-message').textContent = sync.message;
  $('#sync-counter').textContent = sync.total ? `${sync.done} von ${sync.total} Rezepten · bitte lass den Server weiterlaufen` : 'Deine bisherige Sammlung bleibt währenddessen verfügbar.';
  $('#sync-meter').max = sync.total || 1;
  if (sync.total) $('#sync-meter').value = sync.done; else $('#sync-meter').removeAttribute('value');
}
function emptyContent(title, description, action = false, compact = false) {
  return `<section class="empty-state ${compact ? 'compact' : ''}"><span class="empty-icon">${icon(action ? 'layers' : 'search')}</span><h2>${escapeHTML(title)}</h2><p>${escapeHTML(description)}</p>${action ? `<button class="button button-primary" data-action="${state.status?.connected ? 'sync' : 'connect'}">${icon(state.status?.connected ? 'sync' : 'link')}${state.status?.connected ? 'Rezeptlisten laden' : 'Cookidoo verbinden'}${icon('arrow')}</button>` : ''}</section>`;
}
function collectionCard(collection) {
  const images = collection.images || [];
  let mosaic = images.map(file => photo(file)).join('');
  if (images.length === 2) mosaic += `<span class="image-placeholder">${icon('leaf')}</span>`;
  if (!images.length) mosaic = `<span class="image-placeholder">${icon('layers')}</span>`;
  return `<a class="collection-card" href="#liste/${encodeURIComponent(collection.id)}"><div class="collection-mosaic ${images.length ? '' : 'no-images'}">${mosaic}</div><div class="collection-info"><div><h3>${escapeHTML(collection.name)}</h3><p>${collection.recipe_count} ${collection.recipe_count === 1 ? 'Rezept' : 'Rezepte'} · ${collection.kind === 'local' ? 'Lokale Liste' : collection.kind === 'bookmarks' ? 'Merkliste' : collection.kind === 'creations' ? 'Eigene Kreationen' : collection.kind === 'managed' ? 'Kollektion' : 'Cookidoo-Liste'}</p></div><span class="collection-arrow">${icon('arrow')}</span></div></a>`;
}
function collectionSections() {
  const local = state.collections.filter(c => c.kind === 'local');
  const cookidoo = state.collections.filter(c => c.kind !== 'local');
  return `<section><div class="section-heading"><div><h2>Meine lokalen Listen</h2><p>Nur in deinem Rezeptgarten gespeichert.</p></div><button class="button button-primary" data-action="new-list">Neue Liste</button></div>${local.length ? `<div class="collection-grid">${local.map(collectionCard).join('')}</div>` : '<div class="empty-state compact"><p>Hier ist Platz für deine eigenen Rezeptlisten.</p></div>'}</section><section><div class="section-heading"><div><h2>Aus Cookidoo</h2><p>Synchronisierte Merkliste, Kreationen und weitere Sammlungen.</p></div></div>${cookidoo.length ? `<div class="collection-grid">${cookidoo.map(collectionCard).join('')}</div>` : '<div class="empty-state compact"><p>Noch keine Cookidoo-Sammlungen vorhanden.</p></div>'}</section>`;
}
function recipeCard(recipe) {
  const time = duration(recipe.total_seconds);
  const difficulty = {easy:'Einfach',medium:'Mittel',advanced:'Anspruchsvoll',hard:'Anspruchsvoll'}[recipe.difficulty] || 'Cookidoo-Rezept';
  const outsideFilter = recipe.matches === false;
  const servings = Array.isArray(recipe.version_servings) ? recipe.version_servings : (recipe.servings ? [recipe.servings] : []);
  const servingsText = servings.join(' / ');
  const portionsLabel = servings.length === 1 && servings[0] === '1' ? 'Portion' : 'Portionen';
  return `<button class="recipe-card${outsideFilter ? ' outside-filter' : ''}" data-recipe="${escapeHTML(recipe.id)}" aria-label="${escapeHTML(recipe.name)} öffnen${servings.length ? ` · ${escapeHTML(servingsText)} ${portionsLabel}` : ''}${outsideFilter ? ' · entspricht nicht dem Filter' : ''}"><div class="recipe-photo">${photo(recipe.image_file, recipe.name)}${time ? `<span class="recipe-time">${icon('clock')}${time}</span>` : ''}${servings.length ? `<span class="recipe-portions${time ? ' with-time' : ''}">${icon('portion')}<span>${escapeHTML(servingsText)} ${portionsLabel}</span></span>` : ''}</div><div class="recipe-info"><h3>${escapeHTML(recipe.name)}</h3><p>${escapeHTML(difficulty)}</p></div></button>`;
}
function berlinDay() {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone:'Europe/Berlin', year:'numeric', month:'2-digit', day:'2-digit'}).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
function renderFeatured(result) {
  const container = $('#featured-recipe');
  if (!container || state.view !== 'uebersicht') return;
  featuredLocalDay = result.date;
  const recipe = result.recipe;
  if (!recipe) {
    container.innerHTML = `<section class="featured-recipe featured-empty"><div class="featured-copy"><span class="eyebrow">DEIN REZEPT DES TAGES</span><h1>Hier wartet deine nächste Kochidee.</h1><p>Wenn Rezepte in deiner Sammlung sind, findest du hier jeden Tag einen Vorschlag.</p></div></section>`;
    return;
  }
  const time = duration(recipe.total_seconds);
  const portions = recipe.servings ? `${escapeHTML(recipe.servings)} ${String(recipe.servings) === '1' ? 'Portion' : 'Portionen'}` : '';
  container.innerHTML = `<section class="featured-recipe"><div class="featured-copy"><span class="eyebrow">DEIN REZEPT DES TAGES</span><h1>${escapeHTML(recipe.name)}</h1><div class="featured-meta">${time ? `<span>${icon('clock')}${escapeHTML(time)}</span>` : ''}${portions ? `<span>${icon('portion')}${portions}</span>` : ''}</div><div class="featured-actions"><button class="button button-primary" data-recipe="${escapeHTML(recipe.id)}">Rezept ansehen${icon('arrow')}</button><button class="button featured-shuffle" data-action="shuffle-featured" ${result.can_shuffle ? '' : 'disabled'}>${icon('shuffle')}Anderes Rezept</button></div></div><div class="featured-photo">${photo(recipe.image_file, recipe.name, true)}</div></section>`;
}
async function loadFeatured(request = state.request) {
  const result = await api('/api/featured-recipe');
  if (request === state.request && state.view === 'uebersicht') renderFeatured(result);
}
function navActive(view) {
  document.querySelectorAll('[data-nav]').forEach(node => {
    const active = node.dataset.nav === (view === 'collection' ? 'listen' : view);
    node.classList.toggle('active', active);
    if (active) node.setAttribute('aria-current', 'page'); else node.removeAttribute('aria-current');
  });
}
async function renderRoute() {
  if (!state.status) return;
  const request = ++state.request;
  const fragment = location.hash.slice(1);
  state.collection = null;
  state.view = fragment.startsWith('liste/') ? 'collection' : (['listen','rezepte','vorrat','einstellungen'].includes(fragment) ? fragment : 'uebersicht');
  if (state.view === 'collection') {
    try { state.collection = decodeURIComponent(fragment.slice(6)); } catch (_) { state.collection = null; }
  }
  if (state.query && state.view !== 'collection') state.view = 'rezepte';
  navActive(state.view);
  const content = $('#content');
  if (state.view === 'einstellungen') { renderSettings(); return; }
  if (state.view === 'vorrat') {
    const result = await api('/api/pantry');
    if (request !== state.request) return;
    state.pantry = result; renderPantry(); return;
  }
  if (state.view === 'listen') {
    content.innerHTML = `<div class="page-title"><span class="eyebrow">ALLES HAT SEINEN PLATZ</span><h1>Deine Rezeptlisten</h1><p>Deine lokalen Listen und deine Sammlungen aus Cookidoo.</p></div>${collectionSections()}`;
    return;
  }
  if (state.view === 'uebersicht') {
    const stats = state.status.stats;
    content.innerHTML = `<div id="featured-recipe" aria-live="polite"></div><section class="stats" aria-label="Deine Sammlung in Zahlen"><div class="stat"><span class="stat-icon">${icon('layers')}</span><div><div class="stat-value">${stats.collections}</div><div class="stat-label">Rezeptlisten</div></div></div><div class="stat"><span class="stat-icon">${icon('book')}</span><div><div class="stat-value">${stats.recipes}</div><div class="stat-label">Gespeicherte Rezepte</div></div></div><div class="stat"><span class="stat-icon">${icon('sync')}</span><div><div class="stat-value date">${escapeHTML(formatDate(stats.last_sync, true))}</div><div class="stat-label">Letzte Synchronisierung</div></div></div></section><div class="section-heading"><div><h2>Deine Rezeptlisten</h2><p>Gut sortiert. Schnell wiedergefunden.</p></div>${state.collections.length ? `<a class="text-link" href="#listen">Alle Listen ansehen${icon('arrow')}</a>` : ''}</div>${state.collections.length ? `${collectionSections()}<div class="section-heading"><div><h2>Ein Blick in deine Sammlung</h2><p>Vielleicht ist dein nächstes Lieblingsgericht schon dabei.</p></div><a class="text-link" href="#rezepte">Alle Rezepte${icon('arrow')}</a></div><div id="overview-recipes" class="recipe-grid"></div>` : emptyContent(state.status.connected ? 'Alles verbunden. Jetzt wird gesammelt.' : 'Deine Lieblingsgerichte ziehen ein.', state.status.connected ? (!state.status.sync.running && state.status.last_result?.message ? state.status.last_result.message : 'Beim ersten Laden holt Rezeptgarten deine gespeicherten Listen, Rezeptdetails und Bilder. Das kann bei einer großen Sammlung etwas dauern.') : 'Verbinde dein Cookidoo-Konto. Deine gespeicherten Rezeptlisten und Bilder werden anschließend in deiner lokalen Datenbank abgelegt.', !state.status.sync.running)}`;
    await loadFeatured(request);
    if (state.collections.length) {
      const result = await api('/api/recipes?limit=8');
      if (request === state.request && $('#overview-recipes')) $('#overview-recipes').innerHTML = result.items.map(recipeCard).join('');
    }
    return;
  }
  const collection = state.collections.find(item => item.id === state.collection);
  const filterOptions = collection ? await api(`/api/collections/${encodeURIComponent(collection.id)}/filter-options`) : null;
  if (request !== state.request) return;
  recipeIngredientOptions = filterOptions?.ingredients || [];
  recipeIngredientAliases = filterOptions?.ingredient_aliases || {};
  const title = state.query ? `Rezepte für „${state.query}“` : (collection?.name || 'Alle deine Rezepte');
  const description = collection ? collection.description || (collection.kind === 'local' ? 'Deine lokal gespeicherte Rezeptliste.' : 'Alle Rezepte aus dieser Cookidoo-Rezeptliste.') : 'Deine gespeicherten Rezepte. Einmal gesammelt, überall griffbereit.';
  const filterPanel = collection ? `<form id="recipe-filters" class="recipe-filters"><div class="recipe-ingredient-combobox"><label for="recipe-ingredient-filter">Zutaten (alle enthalten)</label><input id="recipe-ingredient-filter" name="ingredient" type="text" maxlength="2000" autocomplete="off" placeholder="Zutaten auswählen oder eingeben" value="${escapeHTML(state.filters.ingredient)}" role="combobox" aria-autocomplete="list" aria-controls="recipe-ingredient-options" aria-expanded="false"><div id="recipe-ingredient-options" class="ingredient-suggestions" role="listbox" aria-label="Zutaten in dieser Liste" hidden></div></div><label>Mindestens Portionen<select name="min_servings"><option value="">Beliebig</option>${filterOptions.servings.map(n => `<option value="${n}" ${String(n) === state.filters.minServings ? 'selected' : ''}>${n} Portionen</option>`).join('')}</select></label><div class="filter-actions"><button class="button button-primary" type="submit">Filtern</button><button class="button" type="button" data-action="reset-filters">Zurücksetzen</button></div><fieldset class="time-filter"><legend>Gesamtzeit höchstens</legend><div class="time-options">${[['','Beliebig'],['20','20 Min.'],['30','30 Min.'],['40','40 Min.'],['60','60 Min.']].map(([value, label]) => `<label class="time-choice"><input type="radio" name="max_minutes" value="${value}" ${state.filters.maxMinutes === value ? 'checked' : ''}><span>${label}</span></label>`).join('')}</div></fieldset></form>` : '';
  content.innerHTML = `<div class="page-title">${state.collection ? `<a class="back-link" href="#listen">${icon('back')}Zurück zu deinen Listen</a>` : `<span class="eyebrow">GUTE IDEEN FÜR DEINE KÜCHE</span>`}<h1>${escapeHTML(title)}</h1><p>${escapeHTML(description)}</p></div>${filterPanel}<div class="results-toolbar"><span id="result-count">Rezepte werden geladen …</span><label class="sr-only" for="sort">Rezepte sortieren</label><select id="sort" class="sort-select"><option value="name" ${state.sort === 'name' ? 'selected' : ''}>Name · A bis Z</option><option value="time" ${state.sort === 'time' ? 'selected' : ''}>Kürzeste Gesamtzeit</option>${collection ? `<option value="servings" ${state.sort === 'servings' ? 'selected' : ''}>Wenigste Portionen</option><option value="ingredients" ${state.sort === 'ingredients' ? 'selected' : ''}>Wenigste Zutaten</option>` : ''}</select></div><div id="recipe-grid" class="recipe-grid"></div><div id="recipe-empty"></div><button id="load-more" class="button load-more" hidden>Weitere Rezepte laden${icon('arrow')}</button>`;
  if (collection?.kind === 'local') {
    content.insertAdjacentHTML('beforeend', `<section class="add-recipes"><div class="section-heading"><div><h2>Weitere Rezepte hinzufügen</h2><p>Diese Rezepte sind noch nicht in dieser Liste.</p></div></div><label class="candidate-search">Rezepte suchen<input id="candidate-search" type="search" maxlength="200" autocomplete="off" placeholder="Rezeptname eingeben" value="${escapeHTML(state.candidateQuery)}"></label><div id="candidate-list" class="candidate-list"></div><p id="candidate-empty" class="candidate-empty" hidden></p><button id="candidate-more" class="button load-more" hidden>Weitere Rezepte anzeigen${icon('arrow')}</button></section>`);
  }
  state.offset = 0;
  await Promise.all([loadRecipes(false, request), collection?.kind === 'local' ? loadCandidates(false, request) : Promise.resolve()]);
}
function pantryIcon(name, category) {
  const value = name.toLocaleLowerCase('de-DE');
  const icons = [
    [/chili|cayenne|paprikapulver|paprika edels/, '🌶️'],
    [/knoblauch/, '🧄'], [/zwiebel/, '🧅'], [/kartoffel/, '🥔'], [/tomate/, '🍅'],
    [/karotte|möhre/, '🥕'], [/gurke/, '🥒'], [/paprika/, '🫑'], [/brokkoli/, '🥦'],
    [/pilz|champignon/, '🍄'], [/salat/, '🥬'], [/zitrone/, '🍋'], [/orange/, '🍊'],
    [/banane/, '🍌'], [/apfel|äpfel/, '🍎'], [/beere|beeren/, '🫐'],
    [/salz/, '🧂'], [/pfeffer/, '⚫'], [/zimt/, '🪵'], [/ingwer/, '🫚'],
    [/kreuzkümmel|kümmel|koriander/, '🌱'], [/oregano|thymian|basilikum|rosmarin|petersilie|schnittlauch|dill|kräuter/, '🌿'],
    [/curry|kurkuma|muskat/, '🥄'], [/zucker/, '🍬'], [/mehl/, '🌾'], [/stärke/, '🥣'],
    [/milch|sahne|joghurt/, '🥛'], [/käse/, '🧀'], [/butter/, '🧈'], [/ei(?:er)?\b/, '🥚'],
    [/öl/, '🫒'], [/hähnchen|huhn/, '🍗'], [/fleisch|rind|schwein/, '🥩'], [/fisch|lachs/, '🐟'],
    [/reis/, '🍚'], [/nudel|pasta/, '🍝'], [/brot/, '🍞'], [/honig/, '🍯'], [/wasser/, '💧'],
  ];
  for (const [pattern, symbol] of icons) if (pattern.test(value)) return symbol;
  const fallback = {'Gewürze':'🌿','Gemüse':'🥕','Obst':'🍎','Fleisch':'🥩','Fisch':'🐟','Soßen':'🥫','Öle und Fette':'🫒','Milchprodukte':'🥛','Vorräte und Konserven':'🥫','Backzutaten':'🌾','Getränke':'🥤','Kräuter (tiefgekühlt)':'🌿'};
  return fallback[category] || '🥣';
}
function pantryCategoryCard(group, query) {
  const collapsed = collapsedPantry.has(group.id);
  const disabled = query || pantryReordering ? 'disabled' : '';
  const list = group.items.length ? `<ul class="pantry-items">${group.items.map(item => `<li><span class="pantry-item-icon" aria-hidden="true">${pantryIcon(item.name, group.name)}</span><div class="pantry-item-text"><strong>${escapeHTML(item.name)}</strong>${item.quantity ? `<span>${escapeHTML(item.quantity)}</span>` : ''}</div><button class="pantry-edit" data-pantry-edit="${item.id}" aria-label="${escapeHTML(item.name)} bearbeiten">Bearbeiten</button><button class="pantry-remove" data-pantry-remove="${item.id}" aria-label="${escapeHTML(item.name)} entfernen">${icon('close')}</button></li>`).join('')}</ul>` : '<p class="pantry-empty">Noch keine Zutaten eingetragen.</p>';
  return `<section class="pantry-card" data-pantry-category="${group.id}"><div class="pantry-card-heading"><button class="pantry-drag" type="button" data-pantry-drag="${group.id}" aria-label="${escapeHTML(group.name)} sortieren: ziehen oder Pfeiltasten verwenden" title="Zum Sortieren ziehen" ${disabled}>☰</button><h2><button class="pantry-toggle" type="button" data-pantry-toggle="${group.id}" aria-expanded="${!collapsed}" aria-controls="pantry-category-items-${group.id}"><span class="pantry-chevron" aria-hidden="true">${collapsed ? '▸' : '▾'}</span><span>${escapeHTML(group.name)}</span><span class="pantry-count">${group.items.length}</span></button></h2><div class="pantry-card-actions"><button class="pantry-add-small" data-pantry-add-category="${group.id}" aria-label="Zutat zu ${escapeHTML(group.name)} hinzufügen">+</button></div></div><div id="pantry-category-items-${group.id}" ${collapsed ? 'hidden' : ''}>${list}</div></section>`;
}
function renderPantry() {
  if (state.view !== 'vorrat') return;
  const query = state.pantryFilter.toLocaleLowerCase('de-DE');
  const groups = state.pantry.categories.map(category => ({...category, items:state.pantry.items.filter(item => item.category_id === category.id && item.name.toLocaleLowerCase('de-DE').includes(query))}));
  $('#content').innerHTML = `<div class="page-title"><span class="eyebrow">DEINE KÜCHE, DEIN ÜBERBLICK</span><h1>Mein Vorrat</h1><p>Halte fest, welche Zutaten du zu Hause hast. Deine Angaben bleiben lokal gespeichert.</p></div><div class="pantry-toolbar"><button class="button button-primary" data-action="pantry-add">Zutat hinzufügen</button><button class="button" data-action="pantry-category">Neue Kategorie</button><button class="button" data-action="pantry-collapse-all">Alle einklappen</button><button class="button" data-action="pantry-expand-all">Alle ausklappen</button></div><label class="pantry-search">Vorrat durchsuchen<input id="pantry-search" type="search" maxlength="100" placeholder="Zutat suchen" value="${escapeHTML(state.pantryFilter)}"></label>${query ? '<p class="pantry-reorder-hint">Zum Sortieren die Suche leeren.</p>' : '<p class="pantry-reorder-hint">Kategorien am Griff ziehen und sortieren.</p>'}<div class="pantry-grid">${groups.filter(group => !query || group.items.length).map(group => pantryCategoryCard(group, query)).join('')}</div>${query && !groups.some(group => group.items.length) ? '<p class="pantry-no-results">Keine passenden Zutaten gefunden.</p>' : ''}`;
}
function setAllPantryCollapsed(collapsed) {
  collapsedPantry = collapsed ? new Set(state.pantry.categories.map(category => category.id)) : new Set();
  try { localStorage.setItem('rezeptgarten-pantry-collapsed', JSON.stringify([...collapsedPantry])); } catch (_) {}
  renderPantry();
}
function showPantryDialog(item = null, categoryId = null) {
  state.pantryEdit = item?.id ?? null;
  $('#pantry-dialog-title').textContent = item ? 'Zutat bearbeiten' : 'Zutat hinzufügen';
  $('#pantry-name').value = item?.name || '';
  selectedIngredient = item?.ingredient_id ?? null;
  closeSuggestions();
  $('#pantry-quantity').value = item?.quantity || '';
  $('#pantry-category').innerHTML = state.pantry.categories.map(c => `<option value="${c.id}">${escapeHTML(c.name)}</option>`).join('');
  if (item || categoryId) $('#pantry-category').value = String(item?.category_id || categoryId);
  errorMessage($('#pantry-error'), ''); $('#pantry-dialog').showModal(); $('#pantry-name').focus();
}
function closeSuggestions() {
  clearTimeout(suggestionTimer); suggestionRequest++;
  suggestionItems = []; suggestionIndex = -1;
  $('#ingredient-suggestions').hidden = true;
  $('#pantry-name').setAttribute('aria-expanded', 'false');
  $('#pantry-name').removeAttribute('aria-activedescendant');
}
function selectSuggestion(index) {
  const item = suggestionItems[index];
  if (!item) return;
  $('#pantry-name').value = item.name; selectedIngredient = item.id;
  closeSuggestions(); $('#pantry-name').focus();
}
function updateSuggestionSelection() {
  document.querySelectorAll('#ingredient-suggestions [role="option"]').forEach((node, index) => node.setAttribute('aria-selected', String(index === suggestionIndex)));
  if (suggestionIndex >= 0) $('#pantry-name').setAttribute('aria-activedescendant', `ingredient-option-${suggestionIndex}`);
  else $('#pantry-name').removeAttribute('aria-activedescendant');
}
$('#pantry-name').addEventListener('input', event => {
  selectedIngredient = null;
  closeSuggestions();
  const query = event.target.value.trim();
  if (!query) return;
  const request = suggestionRequest;
  suggestionTimer = setTimeout(async () => {
    try {
      const response = await api('/api/ingredients/suggestions?' + new URLSearchParams({q:query}));
      if (request !== suggestionRequest || !$('#pantry-dialog').open) return;
      suggestionItems = response.items;
      const list = $('#ingredient-suggestions');
      list.innerHTML = suggestionItems.map((item, index) => `<button type="button" role="option" aria-selected="false" id="ingredient-option-${index}" data-ingredient-option="${index}">${escapeHTML(item.name)}</button>`).join('');
      list.hidden = !suggestionItems.length;
      $('#pantry-name').setAttribute('aria-expanded', String(!!suggestionItems.length));
    } catch (error) { if (request === suggestionRequest) toast(error.message); }
  }, 180);
});
$('#pantry-name').addEventListener('keydown', event => {
  if (!suggestionItems.length) return;
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    suggestionIndex = event.key === 'ArrowDown' ? Math.min(suggestionIndex + 1, suggestionItems.length - 1) : Math.max(suggestionIndex - 1, 0);
    updateSuggestionSelection();
  } else if (event.key === 'Enter' && suggestionIndex >= 0) {
    event.preventDefault(); selectSuggestion(suggestionIndex);
  } else if (event.key === 'Escape') { event.preventDefault(); closeSuggestions(); }
});
$('#ingredient-suggestions').addEventListener('mousedown', event => event.preventDefault());
$('#ingredient-suggestions').addEventListener('click', event => {
  const option = event.target.closest('[data-ingredient-option]');
  if (option) selectSuggestion(Number(option.dataset.ingredientOption));
});
$('#pantry-dialog').addEventListener('close', closeSuggestions);
async function refreshPantry() {
  state.pantry = await api('/api/pantry');
  renderPantry();
}
async function movePantryCategory(sourceId, targetId) {
  if (pantryReordering || state.pantryFilter.trim()) return;
  const ordered = state.pantry.categories.map(category => category.id);
  const source = ordered.indexOf(sourceId), target = ordered.indexOf(targetId);
  if (source < 0 || target < 0 || source === target) return;
  ordered.splice(source, 1); ordered.splice(target, 0, sourceId);
  pantryReordering = true;
  try {
    await api('/api/pantry/categories/order', {method:'PUT', body:JSON.stringify({category_ids:ordered})});
    await refreshPantry(); toast('Kategorien neu sortiert.');
  } catch (error) {
    await refreshPantry().catch(() => {});
    throw error;
  } finally { pantryReordering = false; if (state.view === 'vorrat') renderPantry(); }
}
document.addEventListener('pointerdown', event => {
  const handle = event.target.closest('[data-pantry-drag]');
  if (!handle || handle.disabled || event.button !== 0 || pantryReordering) return;
  pantryDrag = {pointer:event.pointerId, source:Number(handle.dataset.pantryDrag), target:null, x:event.clientX, y:event.clientY, moved:false, handle};
  handle.setPointerCapture(event.pointerId);
});
document.addEventListener('pointermove', event => {
  if (!pantryDrag || pantryDrag.pointer !== event.pointerId) return;
  if (Math.hypot(event.clientX - pantryDrag.x, event.clientY - pantryDrag.y) < 6 && !pantryDrag.moved) return;
  pantryDrag.moved = true;
  const source = document.querySelector(`[data-pantry-category="${pantryDrag.source}"]`);
  source?.classList.add('pantry-dragging');
  const target = document.elementFromPoint(event.clientX, event.clientY)?.closest('[data-pantry-category]');
  document.querySelectorAll('.pantry-drop-target').forEach(node => node.classList.remove('pantry-drop-target'));
  pantryDrag.target = target ? Number(target.dataset.pantryCategory) : null;
  if (target && pantryDrag.target !== pantryDrag.source) target.classList.add('pantry-drop-target');
});
function finishPantryDrag(event, cancelled = false) {
  if (!pantryDrag || pantryDrag.pointer !== event.pointerId) return;
  const {source, target, moved} = pantryDrag;
  pantryDrag = null;
  document.querySelectorAll('.pantry-dragging,.pantry-drop-target').forEach(node => node.classList.remove('pantry-dragging', 'pantry-drop-target'));
  if (!cancelled && moved && target !== null) movePantryCategory(source, target).catch(error => toast(error.message));
}
document.addEventListener('pointerup', event => finishPantryDrag(event));
document.addEventListener('pointercancel', event => finishPantryDrag(event, true));
document.addEventListener('keydown', event => {
  const handle = event.target.closest('[data-pantry-drag]');
  if (!handle || handle.disabled || !['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(event.key)) return;
  event.preventDefault();
  const id = Number(handle.dataset.pantryDrag);
  const index = state.pantry.categories.findIndex(category => category.id === id);
  const direction = ['ArrowUp', 'ArrowLeft'].includes(event.key) ? -1 : 1;
  const target = state.pantry.categories[index + direction];
  if (target) movePantryCategory(id, target.id).then(() => $(`[data-pantry-drag="${id}"]`)?.focus()).catch(error => toast(error.message));
});
function recipeIngredientParts(value) {
  const parts = []; let text = '', quoted = false;
  for (let i = 0; i < value.length; i++) {
    const c = value[i];
    if (c === '"') {
      if (quoted && value[i + 1] === '"') { text += '"'; i++; }
      else quoted = !quoted;
    } else if (c === ',' && !quoted) { parts.push(text.trim()); text = ''; }
    else text += c;
  }
  parts.push(text.trim());
  return parts;
}
function parseRecipeIngredientTerms(value) { return recipeIngredientParts(value).filter(Boolean); }
function formatRecipeIngredient(value) { return /[,"]/.test(value) ? `"${value.replace(/"/g, '""')}"` : value; }
function showRecipeIngredientOptions() {
  const input = $('#recipe-ingredient-filter'), list = $('#recipe-ingredient-options');
  if (!input || !list) return;
  const parts = recipeIngredientParts(input.value);
  const fragment = parts[parts.length - 1].toLocaleLowerCase('de-DE');
  const previous = new Set(parts.slice(0, -1).filter(Boolean).map(v => v.toLocaleLowerCase('de-DE')));
  recipeIngredientMatches = recipeIngredientOptions.filter(name => (name.toLocaleLowerCase('de-DE').includes(fragment) || (recipeIngredientAliases[name] || []).some(alias => alias.toLocaleLowerCase('de-DE').includes(fragment))) && !previous.has(name.toLocaleLowerCase('de-DE')));
  recipeIngredientIndex = -1;
  list.innerHTML = recipeIngredientMatches.map((name, index) => `<button type="button" role="option" id="recipe-ingredient-option-${index}" data-recipe-ingredient-option="${index}" aria-selected="false">${escapeHTML(name)}</button>`).join('');
  list.hidden = recipeIngredientMatches.length === 0;
  input.setAttribute('aria-expanded', String(!list.hidden));
  input.removeAttribute('aria-activedescendant');
}
function chooseRecipeIngredient(index) {
  const name = recipeIngredientMatches[index], input = $('#recipe-ingredient-filter');
  if (!name || !input) return;
  const parts = recipeIngredientParts(input.value); parts.pop();
  parts.push(name);
  input.value = parts.filter(Boolean).map(formatRecipeIngredient).join(', ') + ', ';
  input.focus(); showRecipeIngredientOptions();
}
async function loadRecipes(append = false, request = state.request) {
  const params = new URLSearchParams({q:state.query,sort:state.sort,offset:append ? state.offset : 0,limit:48});
  if (state.collection) { params.set('collection', state.collection); params.set('show_all', 'true'); }
  if (state.collection) applyRecipeFilters(params);
  const result = await api('/api/recipes?' + params);
  if (request !== state.request || !$('#recipe-grid')) return;
  state.offset = result.offset + result.items.length; state.total = result.total;
  const filtered = state.query || (state.collection && (state.filters.ingredient || state.filters.minServings || state.filters.maxMinutes));
  $('#result-count').textContent = state.collection && filtered ? `${result.match_total} von ${result.total} Rezepten passen zum Filter` : `${result.total} ${result.total === 1 ? 'Rezept' : 'Rezepte'}${state.query ? ' gefunden' : ' in deiner Sammlung'}`;
  if (!append) $('#recipe-grid').innerHTML = '';
  $('#recipe-grid').insertAdjacentHTML('beforeend', result.items.map(recipeCard).join(''));
  $('#recipe-empty').innerHTML = result.total ? '' : emptyContent(filtered ? 'Noch kein Treffer.' : 'Hier ist noch Platz für gute Ideen.', filtered ? 'Passe die Suche oder die Filter an und versuche es erneut.' : 'Diese Liste enthält noch keine gespeicherten Rezepte.', false, true);
  $('#load-more').hidden = state.offset >= result.total;
}
function applyRecipeFilters(params) {
  if (state.filters.ingredient) for (const ingredient of parseRecipeIngredientTerms(state.filters.ingredient)) params.append('ingredient', ingredient);
  if (state.filters.minServings) params.set('min_servings', state.filters.minServings);
  if (state.filters.maxMinutes) params.set('max_minutes', state.filters.maxMinutes);
}
function candidateCard(recipe) {
  const outsideFilter = recipe.matches === false;
  const name = escapeHTML(recipe.name), id = escapeHTML(recipe.id);
  return `<div class="candidate-row${outsideFilter ? ' outside-filter' : ''}"><button class="candidate-open" type="button" data-recipe="${id}" aria-label="${name} öffnen${outsideFilter ? ' · entspricht nicht dem Filter' : ''}"><span class="candidate-photo">${photo(recipe.image_file)}</span><span class="candidate-name">${name}</span></button><button class="candidate-add" type="button" data-add-recipe="${id}" aria-label="${name} zur Liste hinzufügen${outsideFilter ? ' · entspricht nicht dem Filter' : ''}" title="Zur Liste hinzufügen">+</button></div>`;
}
async function loadCandidates(append = false, request = state.request) {
  const candidateRequest = ++state.candidateRequest;
  const params = new URLSearchParams({exclude_collection:state.collection, q:state.query, candidate_q:state.candidateQuery, show_all:'true', offset:append ? state.candidateOffset : 0, limit:48});
  applyRecipeFilters(params);
  const result = await api('/api/recipes?' + params);
  if (request !== state.request || candidateRequest !== state.candidateRequest || !$('#candidate-list')) return;
  state.candidateOffset = result.offset + result.items.length;
  if (!append) $('#candidate-list').innerHTML = '';
  $('#candidate-list').insertAdjacentHTML('beforeend', result.items.map(candidateCard).join(''));
  $('#candidate-empty').hidden = result.total > 0;
  $('#candidate-empty').textContent = state.candidateQuery ? 'Keine passenden Rezepte gefunden.' : 'Alle Rezepte sind bereits in dieser Liste.';
  $('#candidate-more').hidden = state.candidateOffset >= result.total;
}
function renderSettings() {
  const status = state.status, account = status.account;
  $('#content').innerHTML = `<div class="page-title"><span class="eyebrow">ALLES NACH DEINEM GESCHMACK</span><h1>Dein Rezeptgarten</h1><p>Verbindung, Synchronisierung und deine App auf dem Startbildschirm.</p></div><div class="settings-grid"><section class="settings-card"><span class="dialog-symbol">${icon('leaf')}</span><h2>Darstellung</h2><p>Wähle eine angenehme Darstellung für dieses Gerät.</p><label class="theme-toggle" for="dark-mode"><span>Dunkelmodus</span><input id="dark-mode" type="checkbox" role="switch" ${document.documentElement.dataset.theme === 'dark' ? 'checked' : ''}></label><div class="accent-control"><label for="accent-color">Akzentfarbe</label><div class="accent-picker-row"><input id="accent-color" type="color" value="${escapeHTML(window.RezeptgartenAccent?.current() || '#234d3c')}" aria-describedby="accent-description"><span id="accent-value">${escapeHTML(window.RezeptgartenAccent?.current() || '#234d3c')}</span><button class="button" type="button" data-action="accent-reset">Standardfarbe</button></div><p id="accent-description" class="settings-small">Die Farbe gilt für diesen Browser.</p></div><p class="settings-small">Die Auswahl wird in diesem Browser gespeichert.</p></section><section class="settings-card"><span class="dialog-symbol">${icon('link')}</span><h2>Dein Cookidoo-Konto</h2>${status.connected ? `<p class="account-email">${escapeHTML(account?.email)}</p><p>Verbunden mit Cookidoo ${escapeHTML(({de:'Deutschland',at:'Österreich',ch:'Schweiz'})[account?.region] || '')}.</p><button class="button" data-action="connect">Konto neu verbinden</button><button class="text-link danger-link" data-action="disconnect">Verbindung trennen</button><p class="settings-small">Deine lokale Sammlung bleibt beim Trennen erhalten.</p>` : `<p>Verbinde dein Konto, um persönliche Rezeptlisten und gespeicherte Cookidoo-Kollektionen zu laden.</p><button class="button button-primary" data-action="connect">${icon('link')}Cookidoo verbinden</button>`}</section><section class="settings-card"><span class="dialog-symbol">${icon('sync')}</span><h2>Automatisch aktuell</h2><p>Rezeptgarten prüft deine Listen im Hintergrund, auch wenn die App geschlossen ist.</p><label for="sync-hours">Synchronisierung<select id="sync-hours"><option value="0" ${status.sync_hours === 0 ? 'selected' : ''}>Nur manuell</option><option value="1" ${status.sync_hours === 1 ? 'selected' : ''}>Jede Stunde</option><option value="6" ${status.sync_hours === 6 ? 'selected' : ''}>Alle 6 Stunden</option><option value="24" ${status.sync_hours === 24 ? 'selected' : ''}>Einmal täglich</option></select></label><p class="settings-small">Letzter erfolgreicher Abgleich: ${escapeHTML(formatDate(status.stats.last_sync))}</p>${status.last_result?.phase === 'error' ? `<p class="form-error">${escapeHTML(status.last_result.message)}</p>` : ''}</section><section class="settings-card"><span class="dialog-symbol">${icon('download')}</span><h2>Auch auf deinem Handy</h2><p>Installiere Rezeptgarten über Chrome und öffne deine Sammlung direkt vom Startbildschirm.</p><button class="button" data-action="install">${icon('download')}App installieren</button><button class="text-link" data-action="install-help">Installationshilfe</button><p class="settings-small">Die Verbindung zum eigenen Server im Heimnetz bleibt erforderlich.</p></section><section class="settings-card"><span class="dialog-symbol">${icon('book')}</span><h2>Deine Daten bleiben bei dir</h2><p>${status.stats.recipes} Rezepte und ${status.stats.images} lokal gespeicherte Bilder. Vor jedem erfolgreichen Abgleich wird die Datenbank gesichert.</p><a class="button" href="/api/export" download>${icon('download')}Sammlung als JSON exportieren</a><p class="settings-small">Rezeptgarten übernimmt aktuell Listen und Rezeptdetails aus Cookidoo. Zutaten werden in einer späteren Ansicht ergänzt.</p></section></div>`;
  $('.settings-grid').insertAdjacentHTML('beforeend', `<section class="settings-card"><span class="dialog-symbol">${icon('link')}</span><h2>Google API</h2><p>${status.google_api_key_set ? 'Ein API-Schlüssel ist gespeichert.' : 'Noch kein API-Schlüssel gespeichert.'}</p><form id="google-key-form" autocomplete="off"><label for="google-api-key">${status.google_api_key_set ? 'API-Schlüssel ersetzen' : 'API-Schlüssel'}</label><input id="google-api-key" type="password" required maxlength="512" autocomplete="off" spellcheck="false"><button class="button button-primary" type="submit">Schlüssel speichern</button></form>${status.google_api_key_set ? '<button class="text-link danger-link" type="button" data-action="google-key-delete">Schlüssel entfernen</button>' : ''}<p class="settings-small">Nach dem Speichern wird der Schlüssel nicht mehr angezeigt.</p></section>`);
}
function recipeDetails(recipe) {
  const parse = value => { try { const result = JSON.parse(value || '[]'); return Array.isArray(result) ? result : []; } catch (_) { return []; } };
  const ingredients = parse(recipe.ingredients_json).map((item, position) => {
    if (typeof item === 'string') return {text:item, available:recipe.ingredient_availability?.[position]};
    if (!item || typeof item !== 'object') return null;
    const description = typeof item.description === 'string' ? item.description.trim() : '';
    const name = typeof item.name === 'string' ? item.name.trim() : '';
    const preparation = typeof item.preparation === 'string' ? item.preparation.trim() : '';
    const text = description && name && !description.toLocaleLowerCase('de-DE').includes(name.toLocaleLowerCase('de-DE')) ? `${description} ${name}` : description || name;
    return {text:text + (preparation && !text.includes(preparation) ? (preparation.startsWith(',') ? '' : ', ') + preparation : ''), available:recipe.ingredient_availability?.[position]};
  }).filter(item => item?.text);
  const groups = parse(recipe.instructions_json);
  const sections = groups.some(item => Array.isArray(item?.steps))
    ? groups.map(group => ({title: group.title || '', steps: (group.steps || []).filter(item => typeof item === 'string' && item)}))
    : [{title: '', steps: groups.map(item => typeof item === 'string' ? item : item?.text).filter(item => typeof item === 'string' && item)}];
  const steps = sections.filter(group => group.steps.length);
  return `${ingredients.length ? `<section class="creation-detail"><h3>Zutaten</h3><p class="ingredient-legend">Grün: im Vorrat · Rot: nicht im Vorrat · Grau: nicht zugeordnet · Wasser ist immer vorhanden · Mengen werden noch nicht geprüft</p><ul class="ingredient-list">${ingredients.map(item => { const status = item.available === true ? 'available' : item.available === false ? 'missing' : 'unknown'; const label = item.available === true ? 'Im Vorrat' : item.available === false ? 'Nicht im Vorrat' : 'Nicht zugeordnet'; return `<li><span class="ingredient-dot ${status}" role="img" aria-label="${label}" title="${label}"></span><span>${escapeHTML(item.text)}</span></li>`; }).join('')}</ul></section>` : ''}${steps.length ? `<section class="creation-detail"><h3>Zubereitung</h3>${steps.map(group => `${group.title ? `<h4>${escapeHTML(group.title)}</h4>` : ''}<ol>${group.steps.map(item => `<li>${escapeHTML(item)}</li>`).join('')}</ol>`).join('')}</section>` : ''}`;
}
async function openRecipe(id) {
  const recipe = await api('/api/recipes/' + encodeURIComponent(id));
  const time = duration(recipe.total_seconds), active = duration(recipe.active_seconds);
  const local = state.collections.filter(c => c.kind === 'local');
  const difficulty = {easy:'Einfach',medium:'Mittel',advanced:'Anspruchsvoll',hard:'Anspruchsvoll'}[recipe.difficulty?.toLowerCase()];
  const versions = recipe.versions || [];
  const selector = versions.length > 1 ? `<label class="version-select">Rezeptversion<select id="recipe-version">${versions.map((version, index) => `<option value="${escapeHTML(version.id)}" ${version.id === recipe.id ? 'selected' : ''}>${version.origin_recipe_id ? `Meine Kreation${versions.filter(v => v.origin_recipe_id).length > 1 ? ` ${index}` : ''}` : 'Cookidoo-Original'}${version.servings ? ` · ${escapeHTML(version.servings)} Portionen` : ''}</option>`).join('')}</select></label>` : '';
  $('#recipe-content').innerHTML = `<div class="recipe-detail-photo">${photo(recipe.image_file, recipe.name, true)}</div><div class="recipe-detail-body"><span class="eyebrow">AUS DEINER SAMMLUNG</span><h2 id="recipe-title">${escapeHTML(recipe.name)}</h2>${selector}<div class="recipe-meta">${time ? `<span class="meta-chip">${icon('clock')}${time} gesamt</span>` : ''}${active ? `<span class="meta-chip">${active} Arbeitszeit</span>` : ''}${recipe.servings ? `<span class="meta-chip">${escapeHTML(recipe.servings)} Portionen</span>` : ''}${difficulty ? `<span class="meta-chip">${difficulty}</span>` : ''}</div>${recipeDetails(recipe)}<div class="detail-lists"><p>GESPEICHERT IN</p>${recipe.collections.map(c => `<a data-close-recipe href="#liste/${encodeURIComponent(c.id)}">${escapeHTML(c.name)}</a>`).join('')}</div><section class="local-memberships"><h3>Zu lokalen Listen hinzufügen</h3>${local.length ? local.map(c => `<label class="membership-option"><input type="checkbox" data-local-list="${escapeHTML(c.id)}" data-local-recipe="${escapeHTML(recipe.id)}" ${recipe.collections.some(item => item.id === c.id) ? 'checked' : ''}><span>${escapeHTML(c.name)}</span></label>`).join('') : '<p>Erstelle zuerst eine lokale Rezeptliste unter „Listen“.</p>'}</section><button type="button" class="button button-primary button-full" data-action="plan-today" data-action-recipe="${escapeHTML(recipe.id)}">Heute kochen</button><button type="button" class="button button-primary button-full" data-action="add-shopping" data-action-recipe="${escapeHTML(recipe.id)}">Zur Einkaufsliste hinzufügen</button><a class="button button-primary button-full" href="${escapeHTML(recipe.source_url)}" target="_blank" rel="noopener noreferrer">In Cookidoo öffnen${icon('external')}</a></div>`;
  if (!$('#recipe-dialog').open) $('#recipe-dialog').showModal();
}
async function startSync() {
  if (!state.status?.connected) { $('#connect-dialog').showModal(); return; }
  await post('/api/sync');
  state.status = await api('/api/status'); updateSync();
}
async function install() {
  if (deferredInstall) {
    await deferredInstall.prompt(); await deferredInstall.userChoice; deferredInstall = null;
    document.querySelectorAll('.install-trigger').forEach(node => { node.hidden = true; });
  } else $('#install-dialog').showModal();
}
document.addEventListener('click', async event => {
  const close = event.target.closest('.close-dialog');
  if (close) { close.closest('dialog').close(); return; }
  const recipe = event.target.closest('[data-recipe]');
  const addRecipe = event.target.closest('[data-add-recipe]');
  const pantryAdd = event.target.closest('[data-pantry-add-category]');
  const pantryEdit = event.target.closest('[data-pantry-edit]');
  const pantryRemove = event.target.closest('[data-pantry-remove]');
  const pantryToggle = event.target.closest('[data-pantry-toggle]');
  const action = event.target.closest('[data-action]');
  try {
    if (pantryToggle) {
      const id = Number(pantryToggle.dataset.pantryToggle);
      if (collapsedPantry.has(id)) collapsedPantry.delete(id); else collapsedPantry.add(id);
      try { localStorage.setItem('rezeptgarten-pantry-collapsed', JSON.stringify([...collapsedPantry])); } catch (_) {}
      renderPantry();
      $(`[data-pantry-toggle="${id}"]`)?.focus();
    }
    if (pantryAdd) showPantryDialog(null, Number(pantryAdd.dataset.pantryAddCategory));
    if (pantryEdit) { const item = state.pantry.items.find(i => i.id === Number(pantryEdit.dataset.pantryEdit)); if (item) showPantryDialog(item); }
    if (pantryRemove) {
      const item = state.pantry.items.find(i => i.id === Number(pantryRemove.dataset.pantryRemove));
      if (item && confirm(`„${item.name}“ aus deinem Vorrat entfernen?`)) {
        pantryRemove.disabled = true;
        try { await api(`/api/pantry/items/${item.id}`, {method:'DELETE'}); await refreshPantry(); toast('Zutat entfernt.'); }
        finally { pantryRemove.disabled = false; }
      }
    }
    if (event.target.closest('[data-close-recipe]')) $('#recipe-dialog').close();
    if (addRecipe) {
      addRecipe.disabled = true;
      try {
        const collection = state.collection;
        await api(`/api/local-collections/${encodeURIComponent(collection)}/recipes/${encodeURIComponent(addRecipe.dataset.addRecipe)}`, {method:'PUT', body:JSON.stringify({present:true})});
        if (state.collection === collection) {
          const result = await api('/api/collections'); state.collections = result.items;
          await Promise.all([loadRecipes(false), loadCandidates(false)]);
          toast('Rezept zur Liste hinzugefügt.');
        }
      } finally { addRecipe.disabled = false; }
    }
    if (recipe) await openRecipe(recipe.dataset.recipe);
    if (event.target.closest('.install-trigger')) await install();
    if (action) {
      switch (action.dataset.action) {
        case 'plan-today':
        case 'add-shopping': {
          action.disabled = true;
          try {
            const planning = action.dataset.action === 'plan-today';
            const result = await post(`/api/recipes/${encodeURIComponent(action.dataset.actionRecipe)}/${planning ? 'plan-today' : 'shopping'}`);
            toast(planning ? (result.verified ? 'Für heute im Cookidoo-Kalender eingeplant.' : 'Cookidoo hat die Anfrage angenommen, aber der Kalendereintrag konnte nicht bestätigt werden. Bitte prüfe den Kalender, bevor du es erneut versuchst.') : result.partial ? 'Rezept hinzugefügt, aber vorhandene Zutaten konnten nicht markiert werden. Bitte prüfe die Cookidoo-Einkaufsliste.' : 'Zur Cookidoo-Einkaufsliste hinzugefügt. Vorhandene Zutaten sind markiert.');
          } finally { action.disabled = false; }
          break;
        }
        case 'accent-reset':
          if (!window.RezeptgartenAccent) toast('Das Farbmodul konnte nicht geladen werden. Bitte lade die Seite neu.');
          else if (!window.RezeptgartenAccent.reset()) toast('Die Farbe kann in diesem Browser nicht dauerhaft gespeichert werden.');
          $('#accent-color').value = window.RezeptgartenAccent?.current() || '#234d3c';
          $('#accent-value').textContent = $('#accent-color').value;
          break;
        case 'pantry-collapse-all': setAllPantryCollapsed(true); $('[data-action="pantry-collapse-all"]')?.focus(); break;
        case 'pantry-expand-all': setAllPantryCollapsed(false); $('[data-action="pantry-expand-all"]')?.focus(); break;
        case 'shuffle-featured': {
          action.disabled = true;
          try { const result = await post('/api/featured-recipe/shuffle'); if (state.view === 'uebersicht') renderFeatured(result); }
          finally { action.disabled = false; }
          break;
        }
        case 'reset-filters': state.filters = {ingredient:'',minServings:'',maxMinutes:''}; await renderRoute(); break;
        case 'pantry-add': showPantryDialog(); break;
        case 'pantry-category': $('#pantry-category-form').reset(); errorMessage($('#pantry-category-error'), ''); $('#pantry-category-dialog').showModal(); $('#pantry-category-name').focus(); break;
        case 'new-list': $('#new-list-form').reset(); errorMessage($('#new-list-error'), ''); $('#new-list-dialog').showModal(); $('#new-list-name').focus(); break;
        case 'connect': errorMessage($('#connect-error'), ''); $('#cookidoo-email').value = state.status?.account?.email || ''; $('#connect-dialog').showModal(); break;
        case 'sync': await startSync(); break;
        case 'install': await install(); break;
        case 'install-help': $('#install-dialog').showModal(); break;
        case 'disconnect': await post('/api/disconnect'); await loadLibrary(); toast('Verbindung getrennt. Deine lokale Sammlung bleibt erhalten.'); break;
        case 'google-key-delete': {
          action.disabled = true;
          try { await api('/api/google-api-key', {method:'DELETE'}); state.status.google_api_key_set = false; if (state.view === 'einstellungen') renderSettings(); toast('Google API-Schlüssel entfernt.'); }
          finally { action.disabled = false; }
          break;
        }
      }
    }
    if (event.target.closest('#load-more')) { $('#load-more').disabled = true; try { await loadRecipes(true); } finally { if ($('#load-more')) $('#load-more').disabled = false; } }
    if (event.target.closest('#candidate-more')) { const button = $('#candidate-more'); button.disabled = true; try { await loadCandidates(true); } finally { button.disabled = false; } }
  } catch (error) { toast(error.message); }
});
$('#new-list-form').addEventListener('submit', async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector('button[type="submit"]');
  button.disabled = true; errorMessage($('#new-list-error'), '');
  try {
    await post('/api/local-collections', {name: $('#new-list-name').value});
    $('#new-list-dialog').close();
    await loadLibrary();
    toast('Deine lokale Liste wurde erstellt.');
  } catch (error) { errorMessage($('#new-list-error'), error.message); }
  finally { button.disabled = false; }
});
$('#pantry-form').addEventListener('submit', async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector('button[type="submit"]'); button.disabled = true; errorMessage($('#pantry-error'), '');
  try {
    const data = {name:$('#pantry-name').value, category_id:Number($('#pantry-category').value), quantity:$('#pantry-quantity').value, ingredient_id:selectedIngredient};
    if (state.pantryEdit !== null) await api(`/api/pantry/items/${state.pantryEdit}`, {method:'PUT',body:JSON.stringify(data)});
    else await post('/api/pantry/items', data);
    $('#pantry-dialog').close(); await refreshPantry(); toast('Vorrat gespeichert.');
  } catch (error) { errorMessage($('#pantry-error'), error.message); }
  finally { button.disabled = false; }
});
$('#pantry-category-form').addEventListener('submit', async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector('button[type="submit"]'); button.disabled = true; errorMessage($('#pantry-category-error'), '');
  try { await post('/api/pantry/categories', {name:$('#pantry-category-name').value}); $('#pantry-category-dialog').close(); await refreshPantry(); toast('Kategorie erstellt.'); }
  catch (error) { errorMessage($('#pantry-category-error'), error.message); }
  finally { button.disabled = false; }
});
document.querySelectorAll('dialog').forEach(dialog => dialog.addEventListener('click', event => {
  if (event.target === dialog) { const rect = dialog.getBoundingClientRect(); if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close(); }
}));
$('#connect-form').addEventListener('submit', async event => {
  event.preventDefault(); const button = $('#connect-submit'); button.disabled = true; errorMessage($('#connect-error'), '');
  button.textContent = 'Cookidoo wird verbunden …';
  try {
    await post('/api/connect', {email:$('#cookidoo-email').value.trim(),password:$('#cookidoo-password').value,region:$('#cookidoo-region').value});
    $('#connect-dialog').close(); await loadLibrary(); toast('Verbunden. Deine Rezeptlisten und Bilder werden jetzt geladen.');
  } catch (error) { errorMessage($('#connect-error'), error.message); }
  finally { $('#cookidoo-password').value = ''; button.disabled = false; button.innerHTML = `Verbinden & Listen laden${icon('arrow')}`; }
});
$('#sync-button').addEventListener('click', () => startSync().catch(error => toast(error.message)));
$('#search').addEventListener('input', event => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => { state.query = event.target.value.trim(); renderRoute().catch(error => toast(error.message)); }, 260);
});
document.addEventListener('input', event => {
  if (event.target.id === 'accent-color') {
    if (!window.RezeptgartenAccent) toast('Das Farbmodul konnte nicht geladen werden. Bitte lade die Seite neu.');
    else if (!window.RezeptgartenAccent.set(event.target.value)) toast('Die Farbe kann in diesem Browser nicht dauerhaft gespeichert werden.');
    $('#accent-value').textContent = event.target.value;
    return;
  }
  if (event.target.id === 'recipe-ingredient-filter') { showRecipeIngredientOptions(); return; }
  if (event.target.id === 'pantry-search') {
    const input = event.target, position = input.selectionStart;
    state.pantryFilter = input.value; renderPantry(); $('#pantry-search').focus(); $('#pantry-search').setSelectionRange(position, position);
    return;
  }
  if (event.target.id !== 'candidate-search') return;
  state.candidateQuery = event.target.value.trim();
  ++state.candidateRequest;
  clearTimeout(candidateTimer);
  candidateTimer = setTimeout(() => loadCandidates(false).catch(error => toast(error.message)), 260);
});
document.addEventListener('focusin', event => {
  if (event.target.id === 'recipe-ingredient-filter') showRecipeIngredientOptions();
});
document.addEventListener('focusout', event => {
  if (event.target.id !== 'recipe-ingredient-filter') return;
  setTimeout(() => { const list = $('#recipe-ingredient-options'), input = $('#recipe-ingredient-filter'); if (list && input && !list.contains(document.activeElement) && document.activeElement !== input) { list.hidden = true; input.setAttribute('aria-expanded', 'false'); input.removeAttribute('aria-activedescendant'); } }, 150);
});
document.addEventListener('mousedown', event => { if (event.target.closest('#recipe-ingredient-options')) event.preventDefault(); });
document.addEventListener('click', event => {
  const option = event.target.closest('[data-recipe-ingredient-option]');
  if (option) chooseRecipeIngredient(Number(option.dataset.recipeIngredientOption));
});
document.addEventListener('keydown', event => {
  if (event.target.id !== 'recipe-ingredient-filter' || !recipeIngredientMatches.length || $('#recipe-ingredient-options')?.hidden) return;
  if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
    event.preventDefault();
    recipeIngredientIndex = event.key === 'ArrowDown' ? Math.min(recipeIngredientIndex + 1, recipeIngredientMatches.length - 1) : Math.max(recipeIngredientIndex - 1, 0);
    document.querySelectorAll('#recipe-ingredient-options [role="option"]').forEach((node, index) => node.setAttribute('aria-selected', String(index === recipeIngredientIndex)));
    event.target.setAttribute('aria-activedescendant', `recipe-ingredient-option-${recipeIngredientIndex}`);
    $(`#recipe-ingredient-option-${recipeIngredientIndex}`)?.scrollIntoView({block:'nearest'});
  } else if (event.key === 'Enter' && recipeIngredientIndex >= 0) { event.preventDefault(); chooseRecipeIngredient(recipeIngredientIndex); }
  else if (event.key === 'Escape') { event.preventDefault(); $('#recipe-ingredient-options').hidden = true; event.target.setAttribute('aria-expanded', 'false'); }
});
document.addEventListener('submit', async event => {
  if (event.target.id === 'google-key-form') {
    event.preventDefault();
    const input = $('#google-api-key'), button = event.target.querySelector('button[type="submit"]');
    const key = input.value;
    input.value = ''; button.disabled = true;
    try { await post('/api/google-api-key', {key}); state.status.google_api_key_set = true; if (state.view === 'einstellungen') renderSettings(); toast('Google API-Schlüssel gespeichert.'); }
    catch (error) { toast(error.message); }
    finally { input.value = ''; button.disabled = false; }
    return;
  }
  if (event.target.id !== 'recipe-filters') return;
  event.preventDefault();
  const form = new FormData(event.target);
  state.filters = {ingredient:String(form.get('ingredient') || '').trim(), minServings:String(form.get('min_servings') || ''), maxMinutes:String(form.get('max_minutes') || '')};
  renderRoute().catch(error => toast(error.message));
});
document.addEventListener('change', async event => {
  try {
    if (event.target.id === 'recipe-version') await openRecipe(event.target.value);
    if (event.target.matches('[data-local-list]')) {
      const checkbox = event.target;
      checkbox.disabled = true;
      try {
        await api(`/api/local-collections/${encodeURIComponent(checkbox.dataset.localList)}/recipes/${encodeURIComponent(checkbox.dataset.localRecipe)}`, {method:'PUT', body:JSON.stringify({present:checkbox.checked})});
        const [status, collections] = await Promise.all([api('/api/status'), api('/api/collections')]);
        state.status = status; state.collections = collections.items;
        $('#nav-list-count').textContent = status.stats.collections;
        $('#nav-recipe-count').textContent = status.stats.recipes;
        await renderRoute();
        toast(checkbox.checked ? 'Rezept zur Liste hinzugefügt.' : 'Rezept aus der Liste entfernt.');
      } catch (error) { checkbox.checked = !checkbox.checked; throw error; }
      finally { checkbox.disabled = false; }
    }
    if (event.target.id === 'dark-mode') {
      const dark = event.target.checked;
      document.documentElement.dataset.theme = dark ? 'dark' : 'light';
      window.RezeptgartenAccent?.apply();
      if ($('#accent-color')) { $('#accent-color').value = window.RezeptgartenAccent?.current() || '#234d3c'; $('#accent-value').textContent = $('#accent-color').value; }
      try { localStorage.setItem('rezeptgarten-theme', dark ? 'dark' : 'light'); } catch (_) { toast('Die Darstellung kann in diesem Browser nicht dauerhaft gespeichert werden.'); }
    }
    if (event.target.id === 'sort') { state.sort = event.target.value; await renderRoute(); }
    if (event.target.id === 'sync-hours') { await post('/api/settings', {sync_hours:Number(event.target.value)}); state.status.sync_hours = Number(event.target.value); toast('Synchronisierungseinstellung gespeichert.'); }
  } catch (error) { toast(error.message); }
});
window.addEventListener('hashchange', () => {
  state.query = ''; state.candidateQuery = ''; state.pantryFilter = ''; state.filters = {ingredient:'',minServings:'',maxMinutes:''}; state.sort = 'name'; clearTimeout(candidateTimer); $('#search').value = '';
  renderRoute().catch(error => toast(error.message));
  window.scrollTo({top:0,behavior:'instant'});
});
document.addEventListener('error', event => {
  if (event.target.matches?.('img[data-recipe-image]')) { const placeholder = document.createElement('span'); placeholder.className = 'image-placeholder'; placeholder.innerHTML = icon('bowl'); placeholder.setAttribute('aria-label', 'Rezeptbild nicht verfügbar'); event.target.replaceWith(placeholder); }
}, true);
window.addEventListener('beforeinstallprompt', event => { event.preventDefault(); deferredInstall = event; document.querySelectorAll('.install-trigger').forEach(node => { node.hidden = false; }); });
window.addEventListener('appinstalled', () => { deferredInstall = null; toast('Rezeptgarten wurde installiert. Viel Freude mit deiner Sammlung!'); });
function offlineStatus() { $('#offline-banner').hidden = navigator.onLine; }
window.addEventListener('online', offlineStatus); window.addEventListener('offline', offlineStatus); offlineStatus();
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && navigator.onLine && state.view === 'uebersicht' && featuredLocalDay !== berlinDay()) loadFeatured().catch(error => toast(error.message));
});
setInterval(async () => {
  if (!state.status || polling || !navigator.onLine) return;
  polling = true;
  try {
    const previous = state.status;
    state.status = await api('/api/status'); updateSync();
    if (state.view === 'uebersicht' && featuredLocalDay !== berlinDay()) await loadFeatured(state.request);
    if ((previous.sync.running && !state.status.sync.running) || previous.stats.last_sync !== state.status.stats.last_sync) {
      await loadLibrary(); if (previous.sync.running) toast(state.status.sync.message);
    }
  } catch (_) { /* Keep the last visible collection when the server is temporarily unreachable. */ }
  finally { polling = false; }
}, 2500);
async function initialize() {
  try {
    await loadLibrary();
  } catch (error) { $('#content').innerHTML = emptyContent('Dein Rezeptgarten ist gerade nicht erreichbar.', error.message); }
  if ('serviceWorker' in navigator && window.isSecureContext) navigator.serviceWorker.register('/sw.js').catch(() => {});
}
initialize();
