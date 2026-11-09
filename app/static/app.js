'use strict';
const $ = selector => document.querySelector(selector);
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
const photo = (file, alt = '', eager = false) => file ? `<img data-recipe-image draggable="false" src="/api/images/${encodeURIComponent(file)}${eager ? '' : '?size=thumb'}" alt="${escapeHTML(alt)}" loading="${eager ? 'eager' : 'lazy'}" decoding="async">` : `<span class="image-placeholder" aria-label="Kein Rezeptbild verfügbar">${icon('bowl')}</span>`;
const state = {status:null, collections:[], recipes:[], total:0, offset:0, view:'uebersicht', collection:null, query:'', sort:'name', filters:{ingredient:'',minServings:'',maxMinutes:''}, request:0, candidateQuery:'', candidateOffset:0, candidateRequest:0, pantry:{categories:[],items:[]}, pantryFilter:'', pantryEdit:null};
let deferredInstall = null, toastTimer, searchTimer, candidateTimer, polling = false;
let suggestionTimer, suggestionRequest = 0, selectedIngredient = null, suggestionItems = [], suggestionIndex = -1;
let recipeIngredientOptions = [], recipeIngredientAliases = {}, recipeIngredientMatches = [], recipeIngredientIndex = -1;
let featuredLocalDay = null;
let weekOffset = 0;
let weekVisibleDay = 0;
try { const saved = localStorage.getItem('rezeptgarten-week-visible-day'); if (saved !== null && /^[0-6]$/.test(saved)) weekVisibleDay = Number(saved); } catch (_) {}
let displayedWeek = null, weekMoves = [], weekSaving = false;
let weekListRecipes = new Map(), weekOpenLists = new Set();
let weekQueueWriting = false, weekQueueError = '', weekQueueSignature = '', weekQueueRefreshPending = false, weekShoppingBusy = false;
let weekArchiveBusy = false, weekArchiveDone = Promise.resolve();
let weekBadgesBusy = false, weekBadgesTimer = null, weekBadgesDone = Promise.resolve(), noteBadgeVersion = {};
let inlineNote = null, recipeNoteRequest = 0;
let previewNoteCache = new Map(), previewNotePending = new Set(), previewNoteObserved = new Set();
let previewNoteObserver = null, previewNoteTimer = null, previewNoteBusy = false, previewNoteDone = Promise.resolve(), previewShelfBusy = false, previewInteractionBusy = false, previewAccount = null, previewAccountVersion = 0;
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
let serverReachable = false;
async function api(path, options = {}) {
  let response;
  const {timeoutMs, ...fetchOptions} = options;
  const controller = timeoutMs ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;
  try {
    response = await fetch(path, {credentials:'same-origin', ...fetchOptions, ...(controller ? {signal:controller.signal} : {}), headers:{'Content-Type':'application/json', ...fetchOptions.headers}});
  } catch (_) {
    serverReachable = false;
    $('#offline-banner').textContent = 'Keine Verbindung zu deinem Rezeptgarten-Server. Prüfe die Verbindung zum Heimnetz.';
    $('#offline-banner').hidden = false;
    const error = new Error('Dein Server ist gerade nicht erreichbar. Prüfe deine Verbindung zum Heimnetz.');
    error.serverUnreachable = true;
    throw error;
  } finally {
    if (timer) clearTimeout(timer);
  }
  serverReachable = true;
  if (navigator.onLine) $('#offline-banner').hidden = true;
  let payload;
  try { payload = await response.json(); } catch (_) { throw new Error('Die Serverantwort konnte nicht gelesen werden. Bitte versuche es erneut.'); }
  if (!response.ok) {
    throw new Error(typeof payload.detail === 'string' ? payload.detail : 'Bitte prüfe die Eingaben und versuche es erneut.');
  }
  return payload;
}
const post = (path, body = {}) => api(path, {method:'POST',body:JSON.stringify(body)});

function previewNote(id) {
  return `<span class="preview-note" data-preview-note="${escapeHTML(id)}" role="img" aria-label="Notiz vorhanden" title="Notiz vorhanden">${icon('note')}</span>`;
}
function previewWeekButton(id, name) {
  return `<button class="preview-week-add" type="button" data-preview-week-add="${escapeHTML(id)}" aria-label="${escapeHTML(name)} zur Ablage der aktuellen Woche hinzufügen" title="Zur Ablage der aktuellen Woche hinzufügen" ${previewShelfBusy ? 'disabled' : ''}>${icon('calendar')}<span aria-hidden="true">+</span></button>`;
}
function rememberPreviewNote(id, hasNote) {
  if (typeof hasNote !== 'boolean') return;
  previewNoteCache.set(id, {hasNote, time:Date.now()});
  document.querySelectorAll(`[data-preview-note="${CSS.escape(id)}"]`).forEach(node => node.classList.toggle('has-note', hasNote));
}
function updatePreviewAccount() {
  const account = JSON.stringify(state.status?.account || null);
  if (account === previewAccount) return;
  previewAccount = account; previewAccountVersion++;
  previewNoteCache.clear(); previewNotePending.clear();
  document.querySelectorAll('[data-preview-note]').forEach(node => node.classList.remove('has-note'));
  for (const node of previewNoteObserved) { previewNoteObserver?.unobserve(node); previewNoteObserver?.observe(node); }
}
function schedulePreviewNotes(delay = 200) {
  clearTimeout(previewNoteTimer);
  previewNoteTimer = setTimeout(loadPreviewNotes, delay);
}
async function loadPreviewNotes() {
  if (!previewNotePending.size || previewNoteBusy || !state.status?.connected) return;
  if (state.status.sync?.running || weekBadgesBusy || weekArchiveBusy || weekSaving || weekQueueWriting || weekShoppingBusy || previewShelfBusy || previewInteractionBusy || (state.view === 'meine-woche' && !displayedWeek) || document.querySelector('dialog:modal')) { schedulePreviewNotes(1200); return; }
  const ids = [...previewNotePending].slice(0, 4);
  ids.forEach(id => previewNotePending.delete(id));
  const accountVersion = previewAccountVersion;
  const versions = Object.fromEntries(ids.map(id => [id, noteBadgeVersion[id] || 0]));
  previewNoteBusy = true;
  let done; previewNoteDone = new Promise(resolve => { done = resolve; });
  try {
    const params = new URLSearchParams({notes_only:'true'});
    ids.forEach(id => params.append('recipe_id', id));
    const result = await api('/api/calendar/badges?' + params);
    if (accountVersion !== previewAccountVersion) return;
    for (const item of result.items) {
      if ((noteBadgeVersion[item.id] || 0) !== versions[item.id]) continue;
      if (typeof item.has_note === 'boolean') rememberPreviewNote(item.id, item.has_note);
      else previewNotePending.add(item.id);
    }
  } catch (_) {
    if (accountVersion === previewAccountVersion) ids.forEach(id => previewNotePending.add(id));
  } finally {
    previewNoteBusy = false; done();
    if (previewNotePending.size) schedulePreviewNotes(2000);
  }
}
function observeRecipePreviews() {
  for (const node of previewNoteObserved) {
    if (!node.isConnected) { previewNoteObserver?.unobserve(node); previewNoteObserved.delete(node); }
  }
  document.querySelectorAll('[data-preview-observe]').forEach(node => {
    const id = node.dataset.previewObserve, cached = previewNoteCache.get(id);
    if (cached && Date.now() - cached.time < 300000) node.querySelector('[data-preview-note]')?.classList.toggle('has-note', cached.hasNote);
    if (previewNoteObserved.has(node)) return;
    previewNoteObserved.add(node);
    if (previewNoteObserver) previewNoteObserver.observe(node);
    else { if (!cached || Date.now() - cached.time >= 300000) previewNotePending.add(id); schedulePreviewNotes(); }
  });
}
if ('IntersectionObserver' in window) {
  previewNoteObserver = new IntersectionObserver(entries => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      const id = entry.target.dataset.previewObserve, cached = previewNoteCache.get(id);
      if (!cached || Date.now() - cached.time >= 300000) previewNotePending.add(id);
    }
    if (previewNotePending.size) schedulePreviewNotes();
  }, {rootMargin:'200px'});
}
new MutationObserver(observeRecipePreviews).observe(document.body, {childList:true, subtree:true});
setInterval(() => {
  if (document.hidden || !state.status?.connected) return;
  for (const node of previewNoteObserved) {
    const rect = node.getBoundingClientRect(), cached = previewNoteCache.get(node.dataset.previewObserve);
    if (rect.bottom >= 0 && rect.top <= innerHeight && rect.right >= 0 && rect.left <= innerWidth && (!cached || Date.now() - cached.time >= 300000)) previewNotePending.add(node.dataset.previewObserve);
  }
  if (previewNotePending.size) schedulePreviewNotes();
}, 60000);

function setCartCount(count) {
  if (!Number.isInteger(count) || count < 0) return;
  $('#cart-shortcut-count').textContent = count > 99 ? '99+' : String(count);
  $('#cart-shortcut').setAttribute('aria-label', `Einkaufswagen öffnen, ${count} ${count === 1 ? 'Rezept' : 'Rezepte'}`);
}
async function refreshCartCount() {
  const status = await api('/api/status');
  setCartCount(status.cart_recipe_count);
}

async function loadLibrary() {
  const [status, collections] = await Promise.all([api('/api/status', {timeoutMs:2500}), api('/api/collections', {timeoutMs:2500})]);
  state.status = status; state.collections = collections.items;
  adoptWeekQueue(status.calendar_queue);
  $('#nav-list-count').textContent = status.stats.collections;
  $('#nav-recipe-count').textContent = status.stats.recipes;
  updateSync();
  await renderRoute();
}
function updateSync() {
  if (!state.status) return;
  updatePreviewAccount();
  if (state.status.connected && previewNotePending.size && !previewNoteBusy) schedulePreviewNotes();
  setCartCount(state.status.cart_recipe_count);
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
function difficultyLabel(value) {
  return {easy:'Einfach',medium:'Mittel',advanced:'Anspruchsvoll',hard:'Anspruchsvoll'}[String(value || '').toLowerCase()] || 'Cookidoo-Rezept';
}
function recipeCard(recipe) {
  const time = duration(recipe.total_seconds);
  const difficulty = difficultyLabel(recipe.difficulty);
  const outsideFilter = recipe.matches === false;
  const servings = Array.isArray(recipe.version_servings) ? recipe.version_servings : (recipe.servings ? [recipe.servings] : []);
  const servingsText = servings.join(' / ');
  const portionsLabel = servings.length === 1 && servings[0] === '1' ? 'Portion' : 'Portionen';
  return `<div class="preview-card"><button class="recipe-card${outsideFilter ? ' outside-filter' : ''}" data-recipe="${escapeHTML(recipe.id)}" aria-label="${escapeHTML(recipe.name)} öffnen${servings.length ? ` · ${escapeHTML(servingsText)} ${portionsLabel}` : ''}${outsideFilter ? ' · entspricht nicht dem Filter' : ''}"><div class="recipe-photo" data-preview-observe="${escapeHTML(recipe.id)}">${photo(recipe.image_file, recipe.name)}${previewNote(recipe.id)}${time ? `<span class="recipe-time">${icon('clock')}${time}</span>` : ''}${servings.length ? `<span class="recipe-portions${time ? ' with-time' : ''}">${icon('portion')}<span>${escapeHTML(servingsText)} ${portionsLabel}</span></span>` : ''}</div><div class="recipe-info"><h3>${escapeHTML(recipe.name)}</h3><p>${escapeHTML(difficulty)}</p></div></button>${previewWeekButton(recipe.id, recipe.name)}</div>`;
}
function berlinDay() {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone:'Europe/Berlin', year:'numeric', month:'2-digit', day:'2-digit'}).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}
function currentWeekMonday() {
  const date = new Date(berlinDay() + 'T12:00:00Z');
  date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7);
  return date.toISOString().slice(0, 10);
}
async function addPreviewToWeek(id) {
  if (weekQueueError) { toast(weekQueueError); return; }
  if (previewShelfBusy || weekQueueWriting || weekSaving || weekShoppingBusy) { toast('Bitte warte, bis die aktuelle Wochenänderung abgeschlossen ist.'); return; }
  if (!state.status?.connected) { toast('Bitte verbinde zuerst dein Cookidoo-Konto.'); return; }
  previewShelfBusy = true;
  document.querySelectorAll('[data-preview-week-add]').forEach(button => { button.disabled = true; });
  try {
    if (previewNoteBusy) await previewNoteDone;
    if (weekBadgesBusy) await weekBadgesDone;
    if (weekArchiveBusy) await weekArchiveDone;
    if (state.status?.sync?.running) { toast('Bitte warte, bis die Synchronisierung fertig ist.'); return; }
    const week = currentWeekMonday(), custom = id.startsWith('creation:');
    weekQueueWriting = true;
    const result = await post('/api/calendar/placement', {week, source:'preview', target:'shelf', recipe_id:custom ? id.slice(9) : id, custom, recipe:{}, move_id:globalThis.crypto?.randomUUID?.() || `${Date.now()}_${Math.random().toString(36).slice(2)}`});
    const {shelf_recipe: added, ...queue} = result;
    weekQueueWriting = false; adoptWeekQueue(queue);
    if (state.status) state.status.calendar_queue = queue;
    if (added && displayedWeek?.days[0].date === week && !displayedWeek.shelf.some(recipe => recipe.id === added.id)) {
      displayedWeek.shelf.push(added);
      if (state.view === 'meine-woche') showWeek();
    }
    toast('Zur Ablage der aktuellen Woche hinzugefügt.');
  } catch (error) { toast(error.message); }
  finally {
    weekQueueWriting = false; previewShelfBusy = false;
    document.querySelectorAll('[data-preview-week-add]').forEach(button => { button.disabled = false; });
    if (previewNotePending.size) schedulePreviewNotes();
  }
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
  container.innerHTML = `<section class="featured-recipe"><div class="featured-copy"><span class="eyebrow">DEIN REZEPT DES TAGES</span><h1>${escapeHTML(recipe.name)}</h1><div class="featured-meta">${time ? `<span>${icon('clock')}${escapeHTML(time)}</span>` : ''}${portions ? `<span>${icon('portion')}${portions}</span>` : ''}</div><div class="featured-actions"><button class="button button-primary" data-recipe="${escapeHTML(recipe.id)}">Rezept ansehen${icon('arrow')}</button><button class="button featured-shuffle" data-action="shuffle-featured" ${result.can_shuffle ? '' : 'disabled'}>${icon('shuffle')}Anderes Rezept</button></div></div><div class="featured-photo" data-preview-observe="${escapeHTML(recipe.id)}">${photo(recipe.image_file, recipe.name, true)}${previewNote(recipe.id)}${previewWeekButton(recipe.id, recipe.name)}</div></section>`;
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
function setTelegramMode(active) {
  $('#telegram-mode').hidden = !active;
}
function emptyCurrentWeek() {
  const today = berlinDay();
  const date = new Date(today + 'T12:00:00Z');
  date.setUTCDate(date.getUTCDate() - (date.getUTCDay() + 6) % 7);
  date.setUTCDate(date.getUTCDate() + weekOffset * 7);
  const days = Array.from({length:7}, (_, index) => {
    const day = new Date(date);
    day.setUTCDate(date.getUTCDate() + index);
    return {date:day.toISOString().slice(0, 10), recipes:[]};
  });
  return {today, days};
}
function weekRecipeBadges(recipe) {
  const time = duration(recipe.total_seconds);
  const servings = recipe.servings == null ? '' : String(recipe.servings).trim();
  return `${recipe.has_note ? `<span class="week-badge week-badge-note" role="img" aria-label="Notiz vorhanden" title="Notiz vorhanden">${icon('note')}</span>` : ''}${time ? `<span class="week-badge week-badge-time" aria-label="${escapeHTML(time)} Gesamtzeit" title="${escapeHTML(time)} Gesamtzeit">${icon('clock')}<span>${escapeHTML(time)}</span></span>` : ''}${servings ? `<span class="week-badge week-badge-servings" aria-label="${escapeHTML(servings)} ${servings === '1' ? 'Portion' : 'Portionen'}" title="${escapeHTML(servings)} ${servings === '1' ? 'Portion' : 'Portionen'}">${icon('portion')}<span>${escapeHTML(servings)}<span class="week-portion-label"> ${servings === '1' ? 'Portion' : 'Portionen'}</span></span></span>` : ''}`;
}
function weekPreviewAction(recipe, source) {
  const shelf = source === 'shelf';
  const label = shelf ? 'aus der Woche entfernen' : 'in die Wochenablage verschieben';
  return `<button class="preview-week-add week-preview-action" type="button" data-week-preview-action aria-label="${escapeHTML(recipe.name)} ${label}" title="${shelf ? 'Aus Woche entfernen' : 'In die Ablage verschieben'}" ${weekSaving || weekQueueWriting || weekQueueError || weekShoppingBusy || previewShelfBusy ? 'disabled' : ''}>${icon(shelf ? 'trash' : 'close')}</button>`;
}
const weekPlaceholderItems = [{id:'restaurant', name:'Im Restaurant essen', symbol:'🍴'}, {id:'fastfood', name:'Fastfood', symbol:'🍔'}, {id:'sushi', name:'Sushi', symbol:'🍣'}, {id:'pasta', name:'Pasta mit Pesto', symbol:'🍝'}, {id:'abendbrot', name:'Abendbrot', symbol:'🍞'}, {id:'resteessen', name:'Resteessen', symbol:'🍲'}];
const weekNativeDrag = () => matchMedia('(pointer:coarse)').matches ? 'false' : 'true';
let weekPlaceholderBusy = false;
function renderWeekPlaceholder(placement, source, week) {
  const item = weekPlaceholderItems.find(entry => entry.id === placement.placeholder);
  if (!item) return '';
  const shelf = source === 'shelf';
  const action = shelf ? 'aus der Woche entfernen' : 'in die Wochenablage verschieben';
  return `<li class="week-placeholder-card" draggable="${weekNativeDrag()}" data-placeholder-drag="${item.id}" data-placeholder-instance="${escapeHTML(placement.id)}" data-placeholder-source="${source}"><div class="week-placeholder-open"><span class="week-placeholder-card-icon placeholder-art-${item.id}" aria-hidden="true"><span></span></span><span class="week-recipe-info"><span class="week-recipe-name">${item.name}</span><span class="week-recipe-difficulty" aria-hidden="true">&nbsp;</span></span></div><button class="preview-week-add" type="button" data-week-placeholder-action="${item.id}" aria-label="${item.name} ${action}" title="${shelf ? 'Aus Woche entfernen' : 'In die Ablage verschieben'}">${icon(shelf ? 'trash' : 'close')}</button></li>`;
}
function weekDays(week, unavailable = false) {
  const format = new Intl.DateTimeFormat('de-DE', {weekday:'long', day:'numeric', month:'long', timeZone:'UTC'});
  const short = new Intl.DateTimeFormat('de-DE', {weekday:'short', day:'numeric', month:'short', timeZone:'UTC'});
  const narrow = new Intl.DateTimeFormat('de-DE', {weekday:'narrow', day:'numeric', month:'numeric', timeZone:'UTC'});
  const renderRecipe = (recipe, source) => `<li class="week-preview" data-week-recipe="${escapeHTML(recipe.calendar_id)}" data-week-custom="${recipe.custom ? '1' : '0'}" data-week-source="${source}"><button class="week-recipe" type="button" draggable="${weekNativeDrag()}" data-recipe="${escapeHTML(recipe.id)}"><span class="week-recipe-photo">${photo(recipe.image_file)}<span class="week-badge-layer">${weekRecipeBadges(recipe)}</span></span><span class="week-recipe-info"><span class="week-recipe-name">${escapeHTML(recipe.name)}</span><span class="week-recipe-difficulty">${escapeHTML(difficultyLabel(recipe.difficulty))}</span></span></button>${weekPreviewAction(recipe, source)}</li>`;
  return `<div class="week-scroll" tabindex="0" role="region" aria-label="Wochentage"><div class="week-grid">${week.days.map(day => { const date = new Date(day.date + 'T12:00:00Z'); const fullDate = escapeHTML(format.format(date)); return `<section class="week-day${day.date === week.today ? ' is-today' : ''}" data-week-day="${day.date}"${day.date === week.today ? ' aria-current="date"' : ''}><h2 aria-label="${fullDate}"><span class="week-date-full" aria-hidden="true">${fullDate}</span><span class="week-date-short" aria-hidden="true">${escapeHTML(short.format(date))}</span><span class="week-date-narrow" aria-hidden="true">${escapeHTML(narrow.format(date))}</span></h2>${day.recipes.length || week.placeholder_placements?.some(item => item.target === day.date) ? `<ul>${day.recipes.map(recipe => renderRecipe(recipe, day.date)).join('')}${(week.placeholder_placements || []).filter(item => item.target === day.date).map(item => renderWeekPlaceholder(item, day.date, week)).join('')}</ul>` : `<p>${unavailable ? 'Kalender nicht geladen' : 'Noch nichts geplant'}</p>`}</section>`; }).join('')}</div></div><section class="week-shelf" data-week-day="shelf"><h2>Ablage für diese Woche</h2>${week.shelf?.length || week.placeholders?.length ? `<ul>${(week.shelf || []).map(recipe => renderRecipe(recipe, 'shelf')).join('')}${(week.placeholder_placements || []).filter(item => item.target === 'shelf').map(item => renderWeekPlaceholder(item, 'shelf', week)).join('')}</ul>` : '<p>Rezepte hier ablegen, wenn der Tag noch offen ist.</p>'}</section>`;
}
function weekToolbar(message, error = false) {
  const disabled = weekQueueWriting || weekSaving || weekShoppingBusy ? 'disabled' : '';
  return `<div class="week-toolbar${error || weekQueueError ? ' week-error' : ''}">${message ? `<p>${escapeHTML(message)}</p>` : ''}<div class="week-controls"><button class="button week-arrow" type="button" data-action="previous-week" aria-label="Vorherige Woche" ${disabled}>${icon('back')}</button><button class="button week-arrow" type="button" data-action="next-week" aria-label="Nächste Woche" ${disabled}>${icon('arrow')}</button><button class="button" type="button" data-action="current-week" ${disabled}>Diese Woche</button>${error ? '<button class="button" type="button" data-action="retry-week">Erneut versuchen</button>' : `<button class="button button-primary" type="button" data-action="week-shopping" ${disabled || (weekQueueError ? 'disabled' : '')}>${icon('cart')}In den Einkaufswagen</button>`}${weekQueueError && weekMoves.length ? '<button class="button" type="button" data-action="discard-week-moves">Vorgemerkte Änderungen verwerfen</button>' : ''}</div></div>`;
}
function adoptWeekQueue(queue) {
  if (!queue || weekQueueWriting) return false;
  const signature = JSON.stringify(queue);
  if (signature === weekQueueSignature) return false;
  weekQueueSignature = signature;
  weekMoves = queue.items || [];
  weekSaving = queue.phase === 'processing';
  weekQueueError = queue.phase === 'error' ? (queue.error || 'Der Wochenabgleich konnte nicht bestätigt werden.') : '';
  return true;
}
function applyWeekMoves(week) {
  week.shelf ||= [];
  for (const move of weekMoves) {
    if (move.week && move.week !== week.days[0].date) continue;
    const from = week.days.find(day => day.date === move.source), to = week.days.find(day => day.date === move.target);
    if (!from && move.source !== 'shelf') continue;
    if (!to && !['shelf', 'trash'].includes(move.target)) continue;
    if (to?.recipes.some(item => item.calendar_id === move.recipe_id && item.custom === move.custom)) continue;
    const index = from?.recipes.findIndex(item => item.calendar_id === move.recipe_id && item.custom === move.custom) ?? -1;
    const recipe = from ? (index >= 0 ? from.recipes.splice(index, 1)[0] : null) : move.recipe;
    if (recipe && to && !to.recipes.some(item => item.calendar_id === move.recipe_id && item.custom === move.custom)) to.recipes.push(recipe);
  }
}
function restoreWeekPosition() {
  const scroll = $('.week-scroll');
  if (!scroll || !matchMedia('(max-width:700px)').matches) return;
  const day = scroll.querySelectorAll('.week-day')[weekVisibleDay];
  if (day) scroll.scrollLeft += day.getBoundingClientRect().left + day.offsetWidth / 2 - (scroll.getBoundingClientRect().left + scroll.clientWidth / 2);
}
document.addEventListener('scroll', event => {
  const scroll = event.target;
  if (!scroll.matches?.('.week-scroll') || !matchMedia('(max-width:700px)').matches) return;
  const center = scroll.getBoundingClientRect().left + scroll.clientWidth / 2;
  const days = [...scroll.querySelectorAll('.week-day')];
  if (!days.length) return;
  const index = days.reduce((best, day, i) => {
    const rect = day.getBoundingClientRect(), previous = days[best].getBoundingClientRect();
    return Math.abs(rect.left + rect.width / 2 - center) < Math.abs(previous.left + previous.width / 2 - center) ? i : best;
  }, 0);
  if (index === weekVisibleDay) return;
  weekVisibleDay = index;
  try { localStorage.setItem('rezeptgarten-week-visible-day', String(index)); } catch (_) {}
}, true);
function showWeek() {
  if (state.view !== 'meine-woche' || !$('#week-content') || !displayedWeek) return;
  clearWeekSwipeSelection();
  const scroll = $('.week-scroll')?.scrollLeft || 0;
  const message = weekQueueError || (weekShoppingBusy ? 'Rezepte werden zur Einkaufsliste hinzugefügt …' : weekSaving ? 'Änderungen werden mit Cookidoo abgeglichen …' : weekMoves.length ? 'Änderungen vorgemerkt · Abgleich fünf Minuten nach der letzten Änderung.' : '');
  $('#week-heading-toolbar').innerHTML = weekToolbar(message);
  $('#week-content').innerHTML = weekDays(displayedWeek);
  $('#week-content').insertAdjacentHTML('afterbegin', '<p class="week-swipe-hint">Kachel halten und wischen: Tag ↑ entfernen · ↓ Ablage. Ablage ↑ zum angezeigten Tag · ↓ entfernen. Tippen beendet die Auswahl.</p>');
  if (matchMedia('(max-width:700px)').matches) restoreWeekPosition();
  else $('.week-scroll').scrollLeft = scroll;
  updateWeekListButtons();
  updateWeekPlaceholderButtons();
}
function renderWeekPlaceholders() {
  const container = $('#week-placeholders');
  if (!container) return;
  container.innerHTML = `<details class="week-local-list"><summary><span>Platzhalter</span><span class="week-local-count">${weekPlaceholderItems.length} Einträge</span></summary><div class="week-local-content"><div class="candidate-list">${weekPlaceholderItems.map(item => `<div class="candidate-row" draggable="${weekNativeDrag()}" data-placeholder-drag="${item.id}" data-placeholder-source="library"><span class="candidate-photo placeholder-icon" aria-hidden="true">${item.symbol}</span><span class="candidate-name">${item.name}</span><button class="candidate-add" type="button" data-week-placeholder-add="${item.id}" aria-label="${item.name} zur Wochenablage hinzufügen" title="Zur Wochenablage hinzufügen" disabled>+</button></div>`).join('')}</div></div></details>`;
}
function updateWeekPlaceholderButtons() {
  document.querySelectorAll('[data-week-placeholder-add]').forEach(button => {
    button.disabled = !displayedWeek || weekPlaceholderBusy;
    button.title = 'Zur Wochenablage hinzufügen';
  });
}
async function setWeekPlaceholder(id, present, target = 'shelf', instanceId = null) {
  const week = displayedWeek;
  if (!week || weekPlaceholderBusy) return;
  weekPlaceholderBusy = true; updateWeekPlaceholderButtons();
  try {
    const create = !instanceId && present;
    if (create) instanceId = globalThis.crypto?.randomUUID?.() || `${Date.now()}_${Math.random().toString(36).slice(2)}`;
    const result = await api('/api/calendar/placeholders', {method:'PUT', body:JSON.stringify({week:week.days[0].date, placeholder:id, present, target, instance_id:instanceId, create})});
    week.placeholders = result.items;
    week.placeholder_placements = result.placements;
    if (displayedWeek === week) showWeek();
  } catch (error) { if (displayedWeek === week) showWeek(); toast(error.message); }
  finally { weekPlaceholderBusy = false; updateWeekPlaceholderButtons(); }
}
function renderWeekLists() {
  const container = $('#week-lists');
  if (!container) return;
  weekListRecipes = new Map();
  const lists = state.collections.filter(collection => collection.kind === 'local');
  container.innerHTML = lists.length ? `<h2>Meine lokalen Listen</h2>${lists.map(collection => `<details class="week-local-list" data-week-list="${escapeHTML(collection.id)}" ${weekOpenLists.has(collection.id) ? 'open' : ''}><summary><span>${escapeHTML(collection.name)}</span><span class="week-local-count">${collection.recipe_count} ${collection.recipe_count === 1 ? 'Rezept' : 'Rezepte'}</span></summary><div class="week-local-content"><div class="candidate-list" data-week-list-items></div><p class="week-local-empty" hidden>Diese Liste ist noch leer.</p><button class="button" type="button" data-week-list-more hidden>Weitere Rezepte anzeigen</button></div></details>`).join('')}` : '';
}
function updateWeekListButtons() {
  document.querySelectorAll('[data-week-add]').forEach(button => {
    const id = button.dataset.weekAdd;
    const inShelf = displayedWeek?.shelf?.some(recipe => recipe.id === id);
    button.disabled = !displayedWeek || !!inShelf || weekQueueWriting || weekSaving || !!weekQueueError || weekShoppingBusy;
    button.textContent = inShelf ? '✓' : '+';
    button.title = inShelf ? 'Bereits in der Ablage' : 'Zur Wochenablage hinzufügen';
  });
}
async function loadWeekList(details) {
  if (!details || details.dataset.loading === '1' || details.dataset.done === '1') return;
  details.dataset.loading = '1';
  const offset = Number(details.dataset.offset || 0);
  const more = details.querySelector('[data-week-list-more]');
  more.disabled = true;
  try {
    const params = new URLSearchParams({collection:details.dataset.weekList, offset, limit:100});
    const result = await api('/api/recipes?' + params);
    if (!details.isConnected) return;
    result.items.forEach(recipe => weekListRecipes.set(recipe.id, recipe));
    details.querySelector('[data-week-list-items]').insertAdjacentHTML('beforeend', result.items.map(recipe => `<div class="candidate-row"><button class="candidate-open" type="button" data-recipe="${escapeHTML(recipe.id)}"><span class="candidate-photo" data-preview-observe="${escapeHTML(recipe.id)}">${photo(recipe.image_file)}${previewNote(recipe.id)}</span><span class="candidate-name">${escapeHTML(recipe.name)}</span></button><button class="candidate-add" type="button" data-week-add="${escapeHTML(recipe.id)}" aria-label="${escapeHTML(recipe.name)} zur Wochenablage hinzufügen" title="Zur Wochenablage hinzufügen">+</button></div>`).join(''));
    details.dataset.offset = String(offset + result.items.length);
    details.dataset.done = details.dataset.offset >= result.total ? '1' : '0';
    details.querySelector('.week-local-empty').hidden = result.total > 0;
    more.hidden = details.dataset.done === '1';
    updateWeekListButtons();
  } finally { details.dataset.loading = '0'; more.disabled = false; }
}
async function addRecipeToWeekShelf(id) {
  if (!displayedWeek || weekQueueWriting || weekSaving || weekQueueError || weekShoppingBusy) return;
  const recipe = weekListRecipes.get(id);
  if (!recipe || displayedWeek.shelf.some(item => item.id === id)) return;
  const week = displayedWeek, custom = id.startsWith('creation:');
  const snapshot = {...recipe, calendar_id:custom ? id.slice(9) : id, custom};
  week.shelf.push(snapshot); weekQueueWriting = true; showWeek();
  try {
    const queue = await post('/api/calendar/placement', {week:week.days[0].date, source:'library', target:'shelf', recipe_id:snapshot.calendar_id, custom, recipe:snapshot, move_id:globalThis.crypto?.randomUUID?.() || `${Date.now()}_${Math.random().toString(36).slice(2)}`});
    weekQueueWriting = false; adoptWeekQueue(queue);
    if (state.status) state.status.calendar_queue = queue;
  } catch (error) {
    toast(`Die Änderung konnte nicht bestätigt werden. Bitte prüfe die Woche: ${error.message}`);
    weekQueueWriting = false;
    await renderRoute();
  } finally { weekQueueWriting = false; if (displayedWeek === week) showWeek(); }
}
function offerWeekUndo(move, recipe, index) {
  const container = $('#week-undo-notices');
  const notice = document.createElement('div'); notice.className = 'week-undo-notice';
  const text = document.createElement('span'); text.textContent = `„${recipe.name}“ entfernt`;
  const button = document.createElement('button'); button.type = 'button'; button.textContent = 'Rückgängig';
  const progress = document.createElement('span'); progress.className = 'week-undo-progress'; progress.setAttribute('aria-hidden', 'true');
  progress.innerHTML = '<svg viewBox="0 0 24 24"><circle class="week-undo-progress-track" cx="12" cy="12" r="9"></circle><circle class="week-undo-progress-ring" cx="12" cy="12" r="9"></circle></svg>';
  notice.append(text, button, progress); container.append(notice);
  const timer = setTimeout(() => notice.remove(), 5000);
  button.addEventListener('click', async () => {
    if (weekQueueWriting || weekSaving || weekShoppingBusy) { toast('Bitte warte, bis die aktuelle Wochenänderung abgeschlossen ist.'); return; }
    clearTimeout(timer); button.disabled = true; notice.classList.add('is-busy'); weekQueueWriting = true;
    try {
      const queue = await post('/api/calendar/undo-removal', {move_id:move.move_id});
      weekQueueWriting = false; adoptWeekQueue(queue);
      if (state.status) state.status.calendar_queue = queue;
      if (displayedWeek?.days[0].date === move.week) {
        const destination = move.source === 'shelf' ? displayedWeek.shelf : displayedWeek.days.find(day => day.date === move.source)?.recipes;
        if (destination && !destination.some(item => item.calendar_id === move.recipe_id && item.custom === move.custom)) destination.splice(Math.min(index, destination.length), 0, recipe);
        showWeek();
      }
      notice.remove();
    } catch (error) { notice.remove(); toast(error.message); }
    finally { weekQueueWriting = false; if (state.view === 'meine-woche') showWeek(); }
  });
}
async function queueWeekMove(source, target, identifier, custom) {
  if (weekSaving || weekQueueWriting || weekQueueError || weekShoppingBusy || !displayedWeek || source === target) return;
  const week = displayedWeek;
  const from = source === 'shelf' ? week.shelf : week.days.find(day => day.date === source)?.recipes;
  const to = target === 'shelf' ? week.shelf : target === 'trash' ? null : week.days.find(day => day.date === target)?.recipes;
  const index = from?.findIndex(item => item.calendar_id === identifier && item.custom === custom) ?? -1;
  if (!from || index < 0 || (target !== 'trash' && !to)) return;
  const destinationHasRecipe = !!to?.some(item => item.calendar_id === identifier && item.custom === custom);
  if (destinationHasRecipe && target !== 'shelf') { toast('Das Rezept ist dort bereits eingeplant.'); return; }
  const recipe = from.splice(index, 1)[0];
  const move = {week:week.days[0].date, source, target, recipe_id:identifier, custom, recipe, move_id:globalThis.crypto?.randomUUID?.() || `${Date.now()}_${Math.random().toString(36).slice(2)}`};
  if (to && !destinationHasRecipe) to.push(recipe);
  weekQueueWriting = true; showWeek();
  try {
    const queue = await post('/api/calendar/placement', move);
    weekQueueWriting = false; adoptWeekQueue(queue);
    if (state.status) state.status.calendar_queue = queue;
    if (target === 'trash' || (target === 'shelf' && queue.items?.some(item => item.move_id === move.move_id && item.target === 'trash'))) offerWeekUndo(move, recipe, index);
  } catch (error) {
    toast(`Die Änderung konnte nicht bestätigt werden. Bitte prüfe die Woche: ${error.message}`);
    weekQueueWriting = false;
    await renderRoute();
  } finally {
    weekQueueWriting = false;
    if (displayedWeek === week) showWeek();
  }
}
async function saveUnfiledWeek(week) {
  if (weekBadgesBusy || previewNoteBusy) { setTimeout(() => { if (displayedWeek === week) saveUnfiledWeek(week); }, 1000); return; }
  if (weekArchiveBusy || weekSaving || weekQueueWriting || weekShoppingBusy || (!week.needs_collection_setup && !week.days.some(day => day.recipes.some(recipe => recipe.unfiled)))) return;
  weekArchiveBusy = true;
  let resolveArchive;
  weekArchiveDone = new Promise(resolve => { resolveArchive = resolve; });
  try {
    const result = await post('/api/calendar/save-unfiled', {day:week.days[0].date});
    if (result.sync_started) { state.status = await api('/api/status'); updateSync(); }
    if (result.added) toast('Wochenrezepte ohne Liste werden in deiner Cookidoo-Liste gespeichert.');
  } catch (error) { toast(error.message); }
  finally {
    weekArchiveBusy = false;
    resolveArchive();
    if (displayedWeek && displayedWeek !== week && state.view === 'meine-woche') setTimeout(() => saveUnfiledWeek(displayedWeek), 300);
  }
}
async function addWeekShopping() {
  if (weekShoppingBusy || weekQueueError || !displayedWeek) return;
  const day = displayedWeek.days[0].date;
  weekShoppingBusy = true; showWeek();
  try {
    if (previewNoteBusy) await previewNoteDone;
    if (weekBadgesBusy) await weekBadgesDone;
    if (weekArchiveBusy) await weekArchiveDone;
    const result = await post('/api/calendar/shopping', {day});
    refreshCartCount().catch(() => {});
    if (result.status === 'empty') toast('In dieser Woche sind ab heute keine Rezepte eingeplant.');
    else if (!result.added) toast('Die Rezepte dieser Woche stehen bereits in deinem Einkaufswagen.');
    else toast(`${result.added} ${result.added === 1 ? 'Rezept wurde' : 'Rezepte wurden'} zum Einkaufswagen hinzugefügt.`);
  } catch (error) { toast(error.message); }
  finally { weekShoppingBusy = false; showWeek(); }
}
function updateWeekBadges(recipeId, values) {
  if (typeof values.has_note === 'boolean') rememberPreviewNote(recipeId, values.has_note);
  if (!displayedWeek) return;
  for (const recipe of [...displayedWeek.days.flatMap(day => day.recipes), ...(displayedWeek.shelf || [])]) {
    if (recipe.id === recipeId) Object.assign(recipe, values);
  }
  document.querySelectorAll('[data-week-recipe]').forEach(item => {
    const id = (item.dataset.weekCustom === '1' ? 'creation:' : '') + item.dataset.weekRecipe;
    if (id !== recipeId) return;
    const recipe = [...displayedWeek.days.flatMap(day => day.recipes), ...(displayedWeek.shelf || [])].find(entry => entry.id === id);
    const layer = item.querySelector('.week-badge-layer');
    if (recipe && layer) layer.innerHTML = weekRecipeBadges(recipe);
    const difficulty = item.querySelector('.week-recipe-difficulty');
    if (recipe && difficulty && values.difficulty != null) difficulty.textContent = difficultyLabel(recipe.difficulty);
  });
}
function scheduleWeekBadges(week, delay = 500) {
  clearTimeout(weekBadgesTimer);
  weekBadgesTimer = setTimeout(() => loadWeekBadges(week), delay);
}
async function loadWeekBadges(week) {
  if (state.view !== 'meine-woche' || displayedWeek !== week || week.badgesLoaded) return;
  const ids = [...new Set([...week.days.flatMap(day => day.recipes), ...(week.shelf || [])].map(recipe => recipe.id))];
  if (!ids.length) return;
  if (weekBadgesBusy || previewNoteBusy || previewShelfBusy || previewInteractionBusy || weekArchiveBusy || weekSaving || weekQueueWriting || weekShoppingBusy || state.status?.sync?.running || $('#recipe-dialog').open) { scheduleWeekBadges(week, 1000); return; }
  const versions = Object.fromEntries(ids.map(id => [id, noteBadgeVersion[id] || 0]));
  weekBadgesBusy = true;
  let resolveBadges;
  weekBadgesDone = new Promise(resolve => { resolveBadges = resolve; });
  try {
    let incomplete = false;
    for (let offset = 0; offset < ids.length; offset += 100) {
      const params = new URLSearchParams();
      ids.slice(offset, offset + 100).forEach(id => params.append('recipe_id', id));
      const result = await api(`/api/calendar/badges?${params}`);
      if (displayedWeek !== week) return;
      result.items.forEach(item => {
        if (item.has_note == null) incomplete = true;
        const values = {};
        if (item.total_seconds != null) values.total_seconds = item.total_seconds;
        if (item.servings != null) values.servings = item.servings;
        if (item.difficulty != null) values.difficulty = item.difficulty;
        if (item.has_note != null && (noteBadgeVersion[item.id] || 0) === versions[item.id]) values.has_note = item.has_note;
        updateWeekBadges(item.id, values);
      });
    }
    week.badgesLoaded = !incomplete;
    if (incomplete) scheduleWeekBadges(week, 30000);
  } catch (_) {
    if (displayedWeek === week) scheduleWeekBadges(week, 5000);
  } finally {
    weekBadgesBusy = false;
    resolveBadges();
    if (displayedWeek && displayedWeek !== week && state.view === 'meine-woche') scheduleWeekBadges(displayedWeek);
  }
}
async function renderRoute() {
  if (!state.status) {
    if (location.hash === '#einkaufswagen') { state.view = 'einkaufswagen'; navActive(state.view); await renderOfflineCart(++state.request); }
    else if (location.hash === '#meine-woche') { state.view = 'meine-woche'; navActive(state.view); await renderOfflineWeek(++state.request); }
    else if (location.hash === '#einstellungen') { state.view = 'einstellungen'; navActive(state.view); renderOfflineSettings(); }
    else $('#content').innerHTML = `<div class="empty-state"><h2>Dein Rezeptgarten ist gerade nicht erreichbar.</h2><p>Mit Internet kannst du deine Woche und den Einkaufswagen über Telegram öffnen.</p><a class="button button-primary" href="#meine-woche">Meine Woche öffnen</a> <a class="button" href="#einkaufswagen">Einkaufswagen öffnen</a></div>`;
    return;
  }
  const request = ++state.request;
  const fragment = location.hash.slice(1);
  state.collection = null;
  state.view = fragment.startsWith('liste/') ? 'collection' : (['listen','rezepte','vorrat','meine-woche','einkaufswagen','einstellungen'].includes(fragment) ? fragment : 'uebersicht');
  if (state.view === 'collection') {
    try { state.collection = decodeURIComponent(fragment.slice(6)); } catch (_) { state.collection = null; }
  }
  if (state.query && state.view !== 'collection') state.view = 'rezepte';
  navActive(state.view);
  if (serverReachable && state.view !== 'meine-woche' && state.view !== 'einkaufswagen') setTelegramMode(false);
  const content = $('#content');
  if (state.view === 'einstellungen') { renderSettings(); return; }
  if (state.view === 'einkaufswagen') { await renderCart(request); return; }
  if (state.view === 'meine-woche') {
    content.innerHTML = `<div class="week-heading"><div class="page-title"><span class="eyebrow">ZEIT FÜR GUTE IDEEN</span><h1>Meine Woche</h1></div><div id="week-heading-toolbar" aria-live="polite"></div></div><div id="week-content" aria-live="polite">Deine Woche wird geladen …</div><section id="week-placeholders" class="week-local-lists week-placeholder-list"></section><section id="week-lists" class="week-local-lists"></section>`;
    renderWeekPlaceholders();
    renderWeekLists();
    if ((weekSaving || weekQueueWriting || weekShoppingBusy) && displayedWeek) { showWeek(); return; }
    displayedWeek = null;
    try {
      if (weekBadgesBusy) await weekBadgesDone;
      if (previewNoteBusy) await previewNoteDone;
      if (request !== state.request) return;
      await api('/api/health', {timeoutMs:2500});
      const week = await api(`/api/calendar/week?day=${emptyCurrentWeek().days[0].date}`);
      if (request !== state.request) return;
      setTelegramMode(false);
      applyWeekMoves(week); displayedWeek = week; showWeek();
      setTimeout(() => { if (displayedWeek === week) saveUnfiledWeek(week); }, 300);
      scheduleWeekBadges(week);
    } catch (error) {
      if (error.serverUnreachable && request === state.request) { await renderOfflineWeek(request); return; }
      if (request === state.request) { $('#week-heading-toolbar').innerHTML = weekToolbar(error.message, true); $('#week-content').innerHTML = weekDays(emptyCurrentWeek(), true); restoreWeekPosition(); }
    }
    return;
  }
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
  content.innerHTML = `<div class="page-title">${state.collection ? `<a class="back-link" href="#listen">${icon('back')}Zurück zu deinen Listen</a>` : `<span class="eyebrow">GUTE IDEEN FÜR DEINE KÜCHE</span>`}<h1>${escapeHTML(title)}</h1><p>${escapeHTML(description)}</p>${collection?.kind === 'local' ? `<button class="button list-delete" type="button" data-delete-local-list="${escapeHTML(collection.id)}">${icon('trash')}Liste löschen</button>` : ''}</div>${filterPanel}<div class="results-toolbar"><span id="result-count">Rezepte werden geladen …</span><label class="sr-only" for="sort">Rezepte sortieren</label><select id="sort" class="sort-select"><option value="name" ${state.sort === 'name' ? 'selected' : ''}>Name · A bis Z</option><option value="time" ${state.sort === 'time' ? 'selected' : ''}>Kürzeste Gesamtzeit</option>${collection ? `<option value="servings" ${state.sort === 'servings' ? 'selected' : ''}>Wenigste Portionen</option><option value="ingredients" ${state.sort === 'ingredients' ? 'selected' : ''}>Wenigste Zutaten</option>` : ''}</select></div><div id="recipe-grid" class="recipe-grid"></div><div id="recipe-empty"></div><button id="load-more" class="button load-more" hidden>Weitere Rezepte laden${icon('arrow')}</button>`;
  if (collection?.kind === 'local') {
    content.insertAdjacentHTML('beforeend', `<section class="add-recipes"><div class="section-heading"><div><h2>Weitere Rezepte hinzufügen</h2><p>Diese Rezepte sind noch nicht in dieser Liste.</p></div></div><label class="candidate-search">Rezepte suchen<input id="candidate-search" type="search" maxlength="200" autocomplete="off" placeholder="Rezeptname eingeben" value="${escapeHTML(state.candidateQuery)}"></label><div id="candidate-list" class="candidate-list"></div><p id="candidate-empty" class="candidate-empty" hidden></p><button id="candidate-more" class="button load-more" hidden>Weitere Rezepte anzeigen${icon('arrow')}</button></section>`);
  }
  state.offset = 0;
  await Promise.all([loadRecipes(false, request), collection?.kind === 'local' ? loadCandidates(false, request) : Promise.resolve()]);
}
async function renderCart(request = state.request) {
  let cart;
  try { cart = await api('/api/cart', {timeoutMs:2500}); }
  catch (error) { if (error.serverUnreachable && request === state.request) return renderOfflineCart(request); throw error; }
  if (request !== state.request || state.view !== 'einkaufswagen') return;
  setTelegramMode(false);
  const recipes = cart.items.filter(item => item.kind === 'recipe');
  setCartCount(recipes.length);
  const extras = cart.items.filter(item => item.kind === 'additional');
  const groups = new Map();
  recipes.forEach(entry => entry.data.ingredients.forEach((ingredient, position) => {
    if (ingredient.is_water) return;
    const key = `${ingredient.owned ? '1' : '0'}:${ingredient.key || `${entry.id}:${position}`}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({entry, ingredient, position});
  }));
  const status = {pending:'Bereit', processing:'Wird übertragen', done:'Übertragen', existing:'Bereits in Cookidoo', uncertain:'Übertragung ungeklärt'};
  const rowStatus = entry => `<span class="cart-status ${entry.status === 'uncertain' ? 'cart-status-error' : ''}">${escapeHTML(status[entry.status] || entry.status)}</span>`;
  const resolve = entry => entry.status === 'uncertain' ? `<div class="cart-resolve"><p>Bitte prüfe den Eintrag in Cookidoo.</p><button type="button" class="button" data-cart-resolve="${entry.id}" data-status="done">Dort vorhanden</button><button type="button" class="button" data-cart-resolve="${entry.id}" data-status="pending">Dort nicht vorhanden</button></div>` : '';
  const recipeRows = recipes.map(entry => `<article class="cart-recipe" data-cart-recipe><button type="button" class="cart-recipe-link" data-recipe="${escapeHTML(entry.recipe_id)}"><span class="cart-preview-photo" data-preview-observe="${escapeHTML(entry.recipe_id)}">${photo(entry.data.image_file, entry.data.name)}${previewNote(entry.recipe_id)}<span class="week-badge-layer">${weekRecipeBadges({...entry.data, has_note:false})}</span></span><span><strong>${escapeHTML(entry.data.name)}</strong>${entry.data.difficulty ? `<small>${escapeHTML(difficultyLabel(entry.data.difficulty))}</small>` : ''}</span></button>${entry.data.ingredients_complete === false ? '<span class="cart-status-error">Zutaten fehlen · bitte nach Synchronisierung erneut hinzufügen</span>' : ''}${entry.status === 'pending' ? '' : rowStatus(entry)}<button type="button" class="cart-recipe-remove" data-cart-remove="${entry.id}" aria-label="${escapeHTML(entry.data.name)} aus dem Einkaufswagen entfernen" title="Aus dem Einkaufswagen entfernen">${icon('trash')}</button>${resolve(entry)}</article>`).join('');
  const ingredientRows = owned => {
    const byCategory = new Map();
    [...groups.values()].filter(items => !!items[0].ingredient.owned === owned).sort((a,b) => (a[0].ingredient.name || a[0].ingredient.text).localeCompare(b[0].ingredient.name || b[0].ingredient.text, 'de')).forEach(items => {
      const category = items[0].ingredient.category || 'Sonstiges';
      if (!byCategory.has(category)) byCategory.set(category, []);
      byCategory.get(category).push(items);
    });
    return [...byCategory].sort(([a],[b]) => a === 'Sonstiges' ? 1 : b === 'Sonstiges' ? -1 : a.localeCompare(b, 'de')).map(([category, categoryItems]) => `<section class="cart-category"><h3>${escapeHTML(category)}</h3><div class="cart-ingredients-list">${categoryItems.map(items => {
    const title = items[0].ingredient.name || items[0].ingredient.text;
    const quantities = items.map(({ingredient}) => ingredient.text.match(/^\s*(\d+(?:[.,]\d+)?)\s*(kg|g|ml|l|Stück)\b/i));
    const total = items.length > 1 && quantities.every(Boolean) && quantities.every(q => q[2].toLocaleLowerCase('de-DE') === quantities[0][2].toLocaleLowerCase('de-DE')) ? `${quantities.reduce((sum, q) => sum + Number(q[1].replace(',', '.')), 0).toLocaleString('de-DE')} ${quantities[0][2]}` : '';
    const heading = items.length > 1 ? `<div class="cart-ingredient-heading"><strong>${escapeHTML(title)}</strong>${total ? `<span class="cart-total">${escapeHTML(total)} insgesamt</span>` : ''}</div>` : '';
    return `<div class="cart-ingredient">${heading}${items.map(({entry,ingredient,position}) => `<label class="cart-ingredient-row"><input type="checkbox" data-cart-ingredient="${entry.id}" data-position="${position}" ${ingredient.owned ? 'checked' : ''} ${entry.status !== 'pending' || cart.transferring ? 'disabled' : ''}><span class="cart-ingredient-icon" aria-hidden="true">${pantryIcon(ingredient.name || ingredient.text, ingredient.category)}</span><span class="cart-ingredient-copy"><span class="cart-ingredient-text">${escapeHTML(ingredient.text)}</span><small>${escapeHTML(entry.data.name)}</small></span></label>`).join('')}</div>`;
    }).join('')}</div></section>`).join('');
  };
  const neededIngredients = ingredientRows(false), ownedIngredients = ingredientRows(true);
  const extraRows = extras.filter(entry => !entry.data.is_water).map(entry => `<div class="cart-extra"><label><input type="checkbox" data-cart-owned="${entry.id}" ${entry.data.owned ? 'checked' : ''} ${entry.status !== 'pending' || cart.transferring ? 'disabled' : ''}><span>${escapeHTML(entry.data.name)}</span></label>${rowStatus(entry)}<button type="button" class="icon-button" data-cart-remove="${entry.id}" aria-label="${escapeHTML(entry.data.name)} entfernen">${icon('trash')}</button>${resolve(entry)}</div>`).join('');
  $('#content').innerHTML = `<div class="page-title"><span class="eyebrow">GUT VORBEREITET</span><h1>Mein Einkaufswagen</h1><p>Hier sammelst du deine Einkäufe. Ein Häkchen bedeutet: bereits vorhanden.</p></div><div class="cart-toolbar"><button type="button" class="button button-primary" data-action="cart-transfer" ${!cart.items.some(item => item.status === 'pending') || cart.transferring ? 'disabled' : ''}>${icon('cart')}An Cookidoo übertragen</button><button type="button" class="button" data-action="cart-clear" ${!cart.items.length || cart.transferring ? 'disabled' : ''}>Einkaufswagen leeren</button></div><section class="cart-section"><h2>Rezepte</h2>${recipeRows ? `<div class="cart-recipe-grid">${recipeRows}</div>` : '<p>Noch keine Rezepte im Einkaufswagen.</p>'}</section><section class="cart-section"><h2>Zutaten</h2>${neededIngredients}${ownedIngredients ? `<h3 class="cart-owned-heading">Bereits vorhanden</h3>${ownedIngredients}` : ''}${!neededIngredients && !ownedIngredients ? '<p>Füge ein Rezept hinzu, um seine Zutaten zu sehen.</p>' : ''}</section><section class="cart-section"><h2>Weitere Artikel</h2>${extraRows}<form id="cart-item-form" class="cart-add"><label class="sr-only" for="cart-item-name">Artikel hinzufügen</label><input id="cart-item-name" name="name" maxlength="100" placeholder="Artikel hinzufügen" required><button class="button button-primary" type="submit">Hinzufügen</button></form></section>`;
}

function pantryIcon(name, category) {
  const value = name.toLocaleLowerCase('de-DE');
  if (/ingwer|ginger/.test(value)) return '<svg class="ingredient-ginger" viewBox="0 0 24 24" aria-hidden="true"><path d="M3.2 15.2c.7-2.1 2.5-3.3 4.7-3.5l-.8-2.4a2.2 2.2 0 0 1 4.2-1.4l.9 2.5 2.5-.6-.5-2a2 2 0 0 1 3.9-.9l.6 2.4c2 .3 3.2 1.7 2.8 3.5-.3 1.5-1.6 2.3-3.2 2.7l-.1 1.2c-.1 2-1.8 3.3-3.8 2.8l-2.7-.7c-1.7 1.3-4 1.5-5.8.6-1.7-.9-3.3-2.3-2.7-4.2Z" fill="#d6a568" stroke="#795833" stroke-width="1.2"/><path d="M7.8 12.1l1 2.1m3.4-3.4.7 2.1m5.1-2.8.2 1.8M7.6 16.6l1.4.4m5-1 1.3.4" fill="none" stroke="#a77a49" stroke-width="1" stroke-linecap="round"/></svg>';
  if (/öl|oil/.test(value)) return '<svg class="ingredient-oil" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 2h4v3.1c0 1.3.5 2.1 1.5 3.1l1.1 1.1c.6.6.9 1.4.9 2.2v8.1c0 1.3-1 2.4-2.3 2.4H8.8c-1.3 0-2.3-1.1-2.3-2.4v-8.1c0-.8.3-1.6.9-2.2l1.1-1.1C9.5 7.2 10 6.4 10 5.1Z" fill="#d2a742" stroke="#755d27" stroke-width="1.2"/><path d="M9.5 2h5v2.2h-5z" fill="#52714a" stroke="#3c5a37" stroke-width=".8"/><path d="M7.6 12h8.8v6.2H7.6z" fill="#f6efd3" stroke="none"/><path d="M12 12.9c-.8 1.1-1.7 2-1.7 2.8a1.7 1.7 0 0 0 3.4 0c0-.8-.9-1.7-1.7-2.8Z" fill="#84944d" stroke="none"/></svg>';
  if (/paprika|bell peppers?/.test(value) && !/paprikapulver|paprika edels|chili|cayenne|gemahlen/.test(value)) return '<svg class="ingredient-pepper" viewBox="0 0 24 24" aria-hidden="true"><path d="M11.7 6.1c-3.7-2.1-7.8.4-7.6 4.8.1 4.7 2.3 9.8 5.4 10 1.1.1 1.7-.4 2.5-.4s1.6.5 2.7.4c3-.2 5.1-5.3 5.3-10 .1-4.4-4-6.9-7.6-4.8Z" fill="#e85b4e" stroke="#aa3b32" stroke-width="1.1"/><path d="M11.9 6.6c-.9-2.1-.2-3.8 1.6-4.7l1 .9c-1.2.7-1.5 1.7-1.1 3.2" fill="#56864c" stroke="#3e693a" stroke-width="1"/><path d="M8 8.4c-1.1 2.8-.8 7.3.7 10M15.9 8.4c1.1 2.8.8 7.3-.7 10" fill="none" stroke="#f58e7e" stroke-width="1.1" stroke-linecap="round"/></svg>';
  if (/\bghee\b|butterschmalz/.test(value)) return '<svg class="ingredient-ghee" viewBox="0 0 24 24" aria-hidden="true"><path d="M6.5 7.2h11v12.2c0 1.4-1.1 2.4-2.4 2.4H8.9c-1.3 0-2.4-1-2.4-2.4Z" fill="#e7b74d" stroke="#886b2e" stroke-width="1.2"/><path d="M6 4h12v3H6z" fill="#876b45" stroke="#614d35" stroke-width="1"/><path d="M7.4 11h9.2v6H7.4z" fill="#fff3d1" stroke="none"/><path d="M12 11.9c-.8 1-1.6 1.8-1.6 2.6a1.6 1.6 0 0 0 3.2 0c0-.8-.8-1.6-1.6-2.6Z" fill="#d5a335" stroke="none"/></svg>';
  const icons = [
    [/chili|cayenne|paprikapulver|paprika edels/, '🌶️'],
    [/knoblauch/, '🧄'], [/zwiebel/, '🧅'], [/kartoffel/, '🥔'], [/tomate/, '🍅'],
    [/karotte|möhre/, '🥕'], [/gurke/, '🥒'], [/brokkoli/, '🥦'],
    [/pilz|champignon/, '🍄'], [/salat/, '🥬'], [/zitrone/, '🍋'], [/orange/, '🍊'],
    [/banane/, '🍌'], [/apfel|äpfel/, '🍎'], [/beere|beeren/, '🫐'],
    [/salz/, '🧂'], [/pfeffer/, '⚫'], [/zimt/, '🪵'],
    [/kreuzkümmel|kümmel|koriander/, '🌱'], [/oregano|thymian|basilikum|rosmarin|petersilie|schnittlauch|dill|kräuter/, '🌿'],
    [/curry|kurkuma|muskat/, '🥄'], [/zucker/, '🍬'], [/mehl/, '🌾'], [/stärke/, '🥣'],
    [/milch|sahne|joghurt/, '🥛'], [/käse/, '🧀'], [/butter/, '🧈'], [/ei(?:er)?\b/, '🥚'],
    [/hähnchen|huhn/, '🍗'], [/fleisch|rind|schwein/, '🥩'], [/fisch|lachs/, '🐟'],
    [/reis/, '🍚'], [/nudel|pasta/, '🍝'], [/baguette/, '🥖'], [/brot/, '🍞'], [/honig/, '🍯'], [/wasser/, '💧'],
  ];
  for (const [pattern, symbol] of icons) if (pattern.test(value)) return symbol;
  const fallback = {'Gewürze':'🌿','Gemüse':'🥕','Obst':'🍎','Fleisch':'🥩','Fisch':'🐟','Soßen':'🥫','Öle und Fette':'🫒','Milchprodukte':'🥛','Vorräte und Konserven':'🥫','Backzutaten':'🌾','Getränke':'🥤','Kräuter (tiefgekühlt)':'🌿'};
  return fallback[category] || '🥣';
}
function pantryCategoryCard(group, query) {
  const collapsed = collapsedPantry.has(group.id);
  const disabled = query || pantryReordering ? 'disabled' : '';
  const list = group.items.length ? `<ul class="pantry-items">${group.items.map(item => `<li><span class="pantry-item-icon" aria-hidden="true">${pantryIcon(item.name, group.name)}</span><div class="pantry-item-text"><strong>${escapeHTML(item.name)}</strong>${item.quantity ? `<span>${escapeHTML(item.quantity)}</span>` : ''}</div><button class="pantry-edit" data-pantry-edit="${item.id}" aria-label="${escapeHTML(item.name)} bearbeiten">Bearbeiten</button><button class="pantry-remove" data-pantry-remove="${item.id}" aria-label="${escapeHTML(item.name)} entfernen">${icon('close')}</button></li>`).join('')}</ul>` : '<p class="pantry-empty">Noch keine Zutaten eingetragen.</p>';
  return `<section class="pantry-card" data-pantry-category="${group.id}"><div class="pantry-card-heading"><button class="pantry-drag" type="button" data-pantry-drag="${group.id}" aria-label="${escapeHTML(group.name)} sortieren: ziehen oder Pfeiltasten verwenden" title="Zum Sortieren ziehen" ${disabled}>☰</button><h2><button class="pantry-toggle" type="button" data-pantry-toggle="${group.id}" aria-expanded="${!collapsed}" aria-controls="pantry-category-items-${group.id}"><span class="pantry-chevron" aria-hidden="true">${collapsed ? '▸' : '▾'}</span><span>${escapeHTML(group.name)}</span><span class="pantry-count">${group.items.length}</span></button></h2><div class="pantry-card-actions"><button class="pantry-add-small" data-pantry-add-category="${group.id}" aria-label="Zutat zu ${escapeHTML(group.name)} hinzufügen">+</button><button class="pantry-category-delete" type="button" data-pantry-delete-category="${group.id}" aria-label="Kategorie ${escapeHTML(group.name)} löschen" title="Kategorie löschen">${icon('trash')}</button></div></div><div id="pantry-category-items-${group.id}" ${collapsed ? 'hidden' : ''}>${list}</div></section>`;
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
  return `<div class="candidate-row${outsideFilter ? ' outside-filter' : ''}"><button class="candidate-open" type="button" data-recipe="${id}" aria-label="${name} öffnen${outsideFilter ? ' · entspricht nicht dem Filter' : ''}"><span class="candidate-photo" data-preview-observe="${id}">${photo(recipe.image_file)}${previewNote(recipe.id)}</span><span class="candidate-name">${name}</span></button>${previewWeekButton(recipe.id, recipe.name)}<button class="candidate-add" type="button" data-add-recipe="${id}" aria-label="${name} zur Liste hinzufügen${outsideFilter ? ' · entspricht nicht dem Filter' : ''}" title="Zur Liste hinzufügen">+</button></div>`;
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
const telegramClientKey = 'rezeptgarten-telegram-client-token';
const telegramPairKey = 'rezeptgarten-telegram-pair';
let telegramSnapshotBusy = false;
function telegramSettings(serverStatus) {
  let clientSet = false;
  try { clientSet = !!localStorage.getItem(telegramClientKey); } catch (_) {}
  const serverText = serverStatus === null ? 'Server nicht erreichbar; Status unbekannt.' : serverStatus ? 'Ein Token ist gespeichert.' : 'Noch kein Token gespeichert.';
  const card = (role, label, status, set, disabled) => `<section class="settings-card"><span class="dialog-symbol">${icon('link')}</span><h2>Telegram: ${label}</h2><p>${status}</p><form data-telegram-form="${role}" autocomplete="off"><label for="telegram-${role}">${set ? 'Token ersetzen' : 'Bot-Token'}</label><input id="telegram-${role}" type="password" required maxlength="221" autocomplete="off" spellcheck="false" ${disabled ? 'disabled' : ''}><button class="button button-primary" type="submit" ${disabled ? 'disabled' : ''}>Token speichern</button></form>${set && !disabled ? `<button class="text-link danger-link" type="button" data-telegram-delete="${role}">Token entfernen</button>` : ''}<p class="settings-small">${role === 'client' ? 'Das Token liegt unverschlüsselt in diesem Browser und gewährt Zugriff auf den Bot. Nur auf vertrauenswürdigen Geräten speichern.' : 'Das Token wird verschlüsselt auf dem Rezeptgarten-Server gespeichert.'} Ein gespeichertes Token bestätigt noch keine Verbindung zu Telegram.</p></section>`;
  let paired = false;
  try { paired = !!localStorage.getItem(telegramPairKey); } catch (_) {}
  return card('server', 'Server-Bot', serverText, serverStatus === true, serverStatus === null) + card('client', 'Client-Bot', clientSet ? 'Ein Token ist in diesem Browser gespeichert.' : 'Noch kein Token in diesem Browser gespeichert.', clientSet, false) + `<section class="settings-card"><span class="dialog-symbol">${icon('link')}</span><h2>Bot-Verbindung</h2><p>Aktiviere bei beiden Bots in BotFather die Bot-zu-Bot-Kommunikation. Verwende zwei eigene Bots ausschließlich für Rezeptgarten; ihre eingehenden Updates werden beim Test verarbeitet.</p><button class="button" type="button" data-telegram-pair ${!clientSet || serverStatus !== true ? 'disabled' : ''}>Bots verbinden</button><button class="button button-primary" type="button" data-telegram-test ${!clientSet || !paired ? 'disabled' : ''}>Verbindung testen</button><p class="settings-small">Verbinden benötigt das Heimnetz. Ein späterer Test benötigt Internet, aber kein Heimnetz. Die Bestätigung gilt nur für den Nachrichtentest.</p><p id="telegram-test-status" role="status" aria-live="polite"></p></section>`;
}
async function telegramClientCall(token, method, values = {}) {
  let response, data;
  try {
    response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {method:'POST', body:new URLSearchParams(values), cache:'no-store', referrerPolicy:'no-referrer'});
    data = await response.json();
  } catch (_) { throw new Error('Telegram ist nicht erreichbar. Prüfe deine Internetverbindung.'); }
  if (!response.ok || !data.ok) throw new Error('Telegram hat die Anfrage abgelehnt. Prüfe Token, Bot-zu-Bot-Freigabe und bestehende Webhooks.');
  return data.result;
}
function bytesToBase64(bytes) { return btoa(String.fromCharCode(...bytes)); }
function base64ToBytes(value) { return Uint8Array.from(atob(value), c => c.charCodeAt(0)); }
async function requestTelegramSnapshot(kind, day = '') {
  if (telegramSnapshotBusy) throw new Error('Ein Abruf läuft bereits. Bitte versuche es gleich erneut.');
  telegramSnapshotBusy = true;
  try {
    const token = localStorage.getItem(telegramClientKey), pair = JSON.parse(localStorage.getItem(telegramPairKey) || 'null');
    if (!token || !pair?.cart_key || !Number.isSafeInteger(pair.id) || !/^[A-Za-z0-9_]{5,32}$/.test(pair.username)) throw new Error('Bitte die Bots einmal im Heimnetz unter Einstellungen erneut verbinden.');
    if (!Number.isSafeInteger(pair.client_id) || token.split(':')[0] !== String(pair.client_id)) throw new Error('Bitte die Bots im Heimnetz erneut verbinden.');
    let offset = 0;
    const nonce = crypto.randomUUID().replaceAll('-', '');
    const compressed = typeof DecompressionStream === 'function';
    await telegramClientCall(token, 'sendMessage', {chat_id:'@' + pair.username, text:`rezeptgarten-${kind}${compressed ? 'z' : ''} ${nonce}${day ? ' ' + day : ''}`});
    const parts = new Map(), until = Date.now() + 90000;
    let total = null;
    while (Date.now() < until && (total === null || parts.size < total)) {
      const updates = await telegramClientCall(token, 'getUpdates', {offset:String(offset), timeout:'8', allowed_updates:'["message"]'});
      for (const update of updates) {
        if (Number.isSafeInteger(update.update_id)) offset = Math.max(offset, update.update_id + 1);
        const message = update.message;
        if (message?.from?.id !== pair.id || !message.from.is_bot || message.chat?.type !== 'private') continue;
        if (message.text === `rezeptgarten-${kind}-error ${nonce}`) throw new Error('Der Server konnte die Daten nicht laden. Prüfe die Verbindung und das gekoppelte Konto im Heimnetz.');
        const match = (message.text || '').match(new RegExp(`^rezeptgarten-${kind}-part ([a-f0-9]{32}) (\\d+)\\/(\\d+) ([A-Za-z0-9+/=]+)$`));
        if (!match || match[1] !== nonce) continue;
        const index = Number(match[2]), count = Number(match[3]);
        if (count < 1 || count > 18 || index < 1 || index > count || (total !== null && count !== total)) throw new Error('Die Antwort ist unvollständig oder ungültig.');
        total = count; parts.set(index, match[4]);
      }
    }
    if (total === null || parts.size !== total) throw new Error('Keine vollständige Antwort erhalten. Bitte erneut versuchen.');
    const encoded = Array.from({length:total}, (_, i) => parts.get(i + 1)).join('');
    const bytes = base64ToBytes(encoded), keyBytes = base64ToBytes(pair.cart_key);
    const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['decrypt']);
    let plain = await crypto.subtle.decrypt({name:'AES-GCM', iv:bytes.slice(0, 12), additionalData:new TextEncoder().encode(nonce)}, key, bytes.slice(12));
    if (compressed) plain = await new Response(new Blob([plain]).stream().pipeThrough(new DecompressionStream('deflate'))).arrayBuffer();
    return JSON.parse(new TextDecoder().decode(plain));
  } finally { telegramSnapshotBusy = false; }
}
async function renderOfflineCart(request) {
  setTelegramMode(true);
  const content = $('#content');
  content.innerHTML = `<div class="page-title"><h1>Mein Einkaufswagen</h1><p>Der Server ist nicht im Heimnetz erreichbar. Der Einkaufswagen wird verschlüsselt über Telegram geladen.</p></div><p id="telegram-cart-status" role="status">Einkaufswagen wird angefordert …</p><div id="telegram-cart-content"></div><button type="button" class="button" data-telegram-cart-refresh>Erneut laden</button>`;
  try {
    const cart = await requestTelegramSnapshot('cart');
    if (!Array.isArray(cart.items)) throw new Error('Ungültige Einkaufsdaten.');
    if (request !== state.request || state.view !== 'einkaufswagen') return;
    const recipes = cart.items.filter(i => i.kind === 'recipe'), extras = cart.items.filter(i => i.kind === 'additional');
    const rows = [];
    for (const recipe of recipes) for (const ingredient of recipe.ingredients || []) rows.push({...ingredient, recipe:recipe.name});
    rows.sort((a,b) => Number(a.owned) - Number(b.owned) || String(a.category).localeCompare(String(b.category), 'de'));
    const ingredients = rows.map(i => `<label class="cart-ingredient-row"><input type="checkbox" disabled ${i.owned ? 'checked' : ''}><span class="cart-ingredient-icon" aria-hidden="true">${pantryIcon(i.icon_name || i.text || '', i.category || '')}</span><span class="cart-ingredient-copy"><span class="cart-ingredient-text">${escapeHTML(i.text)}</span><small>${escapeHTML(i.recipe)} · ${escapeHTML(i.category)}</small></span></label>`).join('');
    const extraRows = extras.map(i => `<label class="cart-ingredient-row"><input type="checkbox" disabled ${i.owned ? 'checked' : ''}><span class="cart-ingredient-icon" aria-hidden="true">${pantryIcon(i.name || '', '')}</span><span>${escapeHTML(i.name)}</span></label>`).join('');
    $('#telegram-cart-content').innerHTML = `<section class="cart-section"><h2>Rezepte</h2>${recipes.length ? `<ul>${recipes.map(i => `<li>${escapeHTML(i.name)}</li>`).join('')}</ul>` : '<p>Keine Rezepte im Einkaufswagen.</p>'}</section><section class="cart-section"><h2>Zutaten</h2>${ingredients || '<p>Keine Zutaten vorhanden.</p>'}</section><section class="cart-section"><h2>Weitere Artikel</h2>${extraRows || '<p>Keine weiteren Artikel.</p>'}</section>`;
    $('#telegram-cart-status').textContent = 'Aktueller Stand über Telegram geladen. Unterwegs ist diese Ansicht zunächst nur lesbar.';
  } catch (error) {
    if (request === state.request && state.view === 'einkaufswagen' && $('#telegram-cart-status')) $('#telegram-cart-status').textContent = error.message || 'Der Einkaufswagen konnte nicht geladen werden.';
  }
}
document.addEventListener('click', event => {
  if (event.target.closest('[data-telegram-cart-refresh]') && !telegramSnapshotBusy) renderOfflineCart(++state.request);
});
async function renderOfflineWeek(request) {
  setTelegramMode(true);
  const monday = emptyCurrentWeek().days[0].date;
  $('#content').innerHTML = `<div class="page-title"><h1>Meine Woche</h1><p>Verschlüsselt über Telegram · nur ansehen</p></div><div class="week-controls"><button class="button" type="button" data-telegram-week="previous" disabled aria-label="Vorherige Woche">←</button><button class="button" type="button" data-telegram-week="next" disabled aria-label="Nächste Woche">→</button><button class="button" type="button" data-telegram-week="current" disabled>Diese Woche</button><button class="button" type="button" data-telegram-week="refresh" disabled>Erneut laden</button></div><p id="telegram-week-status" role="status">Woche wird geladen …</p><div id="telegram-week-content"></div>`;
  try {
    const week = await requestTelegramSnapshot('week', monday);
    if (request !== state.request || state.view !== 'meine-woche') return;
    const expected = emptyCurrentWeek().days;
    if (!Array.isArray(week.days) || week.days.length !== 7 || week.days.some((day, i) => day.date !== expected[i].date || !Array.isArray(day.recipes) || !Array.isArray(day.placeholders)) || !Array.isArray(week.shelf) || !Array.isArray(week.shelf_placeholders)) throw new Error('Die Wochenantwort ist ungültig.');
    const format = new Intl.DateTimeFormat('de-DE', {weekday:'long', day:'numeric', month:'long', timeZone:'UTC'});
    const placeholderName = id => weekPlaceholderItems.find(item => item.id === id)?.name || 'Platzhalter';
    const list = (recipes, placeholders) => {
      const names = [...recipes, ...placeholders.map(placeholderName)];
      return names.length ? `<ul>${names.map(name => `<li>${escapeHTML(name)}</li>`).join('')}</ul>` : '<p>Noch nichts geplant.</p>';
    };
    $('#telegram-week-content').innerHTML = `<div class="week-scroll" tabindex="0" role="region" aria-label="Wochentage"><div class="week-grid">${week.days.map(day => `<section class="week-day${day.date === week.today ? ' is-today' : ''}"><h2>${escapeHTML(format.format(new Date(day.date + 'T12:00:00Z')))}</h2>${list(day.recipes, day.placeholders)}</section>`).join('')}</div></div><section class="week-shelf"><h2>Ablage für diese Woche</h2>${list(week.shelf, week.shelf_placeholders)}</section>`;
    $('#telegram-week-status').textContent = week.queue_error || week.queue_phase === 'error' ? 'Wochenabgleich ungeklärt. Bitte im Heimnetz prüfen.' : week.queue_phase !== 'idle' ? 'Vorgemerkte Änderungen sind berücksichtigt; der Abgleich läuft oder steht noch aus.' : 'Aktueller Stand geladen. Diese Ansicht ist nur lesbar.';
  } catch (error) {
    if (request === state.request && state.view === 'meine-woche' && $('#telegram-week-status')) $('#telegram-week-status').textContent = error.message || 'Die Woche konnte nicht geladen werden.';
  } finally {
    if (request === state.request && state.view === 'meine-woche') document.querySelectorAll('[data-telegram-week]').forEach(button => { button.disabled = false; });
  }
}
document.addEventListener('click', event => {
  const button = event.target.closest('[data-telegram-week]');
  if (!button || telegramSnapshotBusy) return;
  if (button.dataset.telegramWeek === 'previous') weekOffset--;
  else if (button.dataset.telegramWeek === 'next') weekOffset++;
  else if (button.dataset.telegramWeek === 'current') weekOffset = 0;
  renderOfflineWeek(++state.request);
});
document.addEventListener('click', async event => {
  const button = event.target.closest('[data-telegram-pair], [data-telegram-test]');
  if (!button) return;
  button.disabled = true;
  const status = $('#telegram-test-status');
  try {
    if (telegramSnapshotBusy) throw new Error('Ein Abruf läuft bereits. Bitte versuche es gleich erneut.');
    const token = localStorage.getItem(telegramClientKey);
    if (!token) throw new Error('Bitte zuerst das Client-Bot-Token speichern.');
    if (button.hasAttribute('data-telegram-pair')) {
      status.textContent = 'Bots werden geprüft …';
      const client = await telegramClientCall(token, 'getMe');
      if (!client.is_bot || !Number.isSafeInteger(client.id)) throw new Error('Das Client-Token gehört nicht zu einem gültigen Bot.');
      const cart_key = bytesToBase64(crypto.getRandomValues(new Uint8Array(32)));
      const pair = await post('/api/telegram-pair', {client_id:client.id, cart_key});
      localStorage.setItem(telegramPairKey, JSON.stringify({...pair, client_id:client.id, cart_key}));
      state.status ? renderSettings() : renderOfflineSettings();
      $('#telegram-test-status').textContent = 'Bots verbunden. Starte den Verbindungstest.';
    } else {
      const pair = JSON.parse(localStorage.getItem(telegramPairKey) || 'null');
      if (!pair || !Number.isSafeInteger(pair.id) || !/^[A-Za-z0-9_]{5,32}$/.test(pair.username)) throw new Error('Bitte die Bots zuerst im Heimnetz verbinden.');
      const client = await telegramClientCall(token, 'getMe');
      if (client.id !== pair.client_id || !client.is_bot) throw new Error('Das Client-Token hat sich geändert. Bitte die Bots erneut verbinden.');
      status.textContent = 'Testnachricht wird gesendet …';
      const pending = await telegramClientCall(token, 'getUpdates', {limit:'100', timeout:'0', allowed_updates:'["message"]'});
      let offset = pending.reduce((n, update) => Math.max(n, Number.isSafeInteger(update.update_id) ? update.update_id + 1 : 0), 0);
      const nonce = crypto.randomUUID().replaceAll('-', '');
      await telegramClientCall(token, 'sendMessage', {chat_id:'@' + pair.username, text:'rezeptgarten-ping ' + nonce});
      status.textContent = 'Testnachricht gesendet; warte auf Bestätigung …';
      const until = Date.now() + 35000;
      while (Date.now() < until) {
        const updates = await telegramClientCall(token, 'getUpdates', {offset:String(offset), timeout:'8', allowed_updates:'["message"]'});
        let confirmed = false;
        for (const update of updates) {
          if (Number.isSafeInteger(update.update_id)) offset = Math.max(offset, update.update_id + 1);
          const message = update.message;
          if (message?.from?.id === pair.id && message.from.is_bot && message.chat?.type === 'private' && message.text === 'rezeptgarten-pong ' + nonce) confirmed = true;
        }
        if (confirmed) { status.textContent = 'Bestätigt: Beide Bots haben miteinander kommuniziert.'; return; }
      }
      throw new Error('Keine Bestätigung erhalten. Prüfe den Host-Dienst und die Bot-zu-Bot-Freigabe.');
    }
  } catch (error) { status.textContent = error.message || 'Der Verbindungstest ist fehlgeschlagen.'; }
  finally { button.disabled = false; }
});
function renderOfflineSettings() {
  $('#content').innerHTML = `<div class="page-title"><h1>Einstellungen</h1><p>Der Rezeptgarten-Server ist nicht erreichbar.</p></div><div class="settings-grid">${telegramSettings(null)}</div>`;
}
function renderSettings() {
  const status = state.status, account = status.account;
  $('#content').innerHTML = `<div class="page-title"><span class="eyebrow">ALLES NACH DEINEM GESCHMACK</span><h1>Dein Rezeptgarten</h1><p>Verbindung, Synchronisierung und deine App auf dem Startbildschirm.</p></div><div class="settings-grid"><section class="settings-card"><span class="dialog-symbol">${icon('leaf')}</span><h2>Darstellung</h2><p>Wähle eine angenehme Darstellung für dieses Gerät.</p><label class="theme-toggle" for="dark-mode"><span>Dunkelmodus</span><input id="dark-mode" type="checkbox" role="switch" ${document.documentElement.dataset.theme === 'dark' ? 'checked' : ''}></label><div class="accent-control"><label for="accent-color">Akzentfarbe</label><div class="accent-picker-row"><input id="accent-color" type="color" value="${escapeHTML(window.RezeptgartenAccent?.current() || '#234d3c')}" aria-describedby="accent-description"><span id="accent-value">${escapeHTML(window.RezeptgartenAccent?.current() || '#234d3c')}</span><button class="button" type="button" data-action="accent-reset">Standardfarbe</button></div><p id="accent-description" class="settings-small">Die Farbe gilt für diesen Browser.</p></div><p class="settings-small">Die Auswahl wird in diesem Browser gespeichert.</p></section><section class="settings-card"><span class="dialog-symbol">${icon('link')}</span><h2>Dein Cookidoo-Konto</h2>${status.connected ? `<p class="account-email">${escapeHTML(account?.email)}</p><p>Verbunden mit Cookidoo ${escapeHTML(({de:'Deutschland',at:'Österreich',ch:'Schweiz'})[account?.region] || '')}.</p><button class="button" data-action="connect">Konto neu verbinden</button><button class="text-link danger-link" data-action="disconnect">Verbindung trennen</button><p class="settings-small">Deine lokale Sammlung bleibt beim Trennen erhalten.</p>` : `<p>Verbinde dein Konto, um persönliche Rezeptlisten und gespeicherte Cookidoo-Kollektionen zu laden.</p><button class="button button-primary" data-action="connect">${icon('link')}Cookidoo verbinden</button>`}</section><section class="settings-card"><span class="dialog-symbol">${icon('sync')}</span><h2>Automatisch aktuell</h2><p>Rezeptgarten prüft deine Listen im Hintergrund, auch wenn die App geschlossen ist.</p><label for="sync-hours">Synchronisierung<select id="sync-hours"><option value="0" ${status.sync_hours === 0 ? 'selected' : ''}>Nur manuell</option><option value="1" ${status.sync_hours === 1 ? 'selected' : ''}>Jede Stunde</option><option value="6" ${status.sync_hours === 6 ? 'selected' : ''}>Alle 6 Stunden</option><option value="24" ${status.sync_hours === 24 ? 'selected' : ''}>Einmal täglich</option></select></label><p class="settings-small">Letzter erfolgreicher Abgleich: ${escapeHTML(formatDate(status.stats.last_sync))}</p>${status.last_result?.phase === 'error' ? `<p class="form-error">${escapeHTML(status.last_result.message)}</p>` : ''}</section><section class="settings-card"><span class="dialog-symbol">${icon('download')}</span><h2>Auch auf deinem Handy</h2><p>Installiere Rezeptgarten über Chrome und öffne deine Sammlung direkt vom Startbildschirm.</p><button class="button" data-action="install">${icon('download')}App installieren</button><button class="text-link" data-action="install-help">Installationshilfe</button><p class="settings-small">Die Verbindung zum eigenen Server im Heimnetz bleibt erforderlich.</p></section><section class="settings-card"><span class="dialog-symbol">${icon('book')}</span><h2>Deine Daten bleiben bei dir</h2><p>${status.stats.recipes} Rezepte und ${status.stats.images} lokal gespeicherte Bilder. Vor jedem erfolgreichen Abgleich wird die Datenbank gesichert.</p><a class="button" href="/api/export" download>${icon('download')}Sammlung als JSON exportieren</a><p class="settings-small">Rezeptgarten übernimmt aktuell Listen und Rezeptdetails aus Cookidoo. Zutaten werden in einer späteren Ansicht ergänzt.</p></section></div>`;
  $('.settings-grid').insertAdjacentHTML('beforeend', `<section class="settings-card"><span class="dialog-symbol">${icon('link')}</span><h2>Google API</h2><p>${status.google_api_key_set ? 'Ein API-Schlüssel ist gespeichert.' : 'Noch kein API-Schlüssel gespeichert.'}</p><form id="google-key-form" autocomplete="off"><label for="google-api-key">${status.google_api_key_set ? 'API-Schlüssel ersetzen' : 'API-Schlüssel'}</label><input id="google-api-key" type="password" required maxlength="512" autocomplete="off" spellcheck="false"><button class="button button-primary" type="submit">Schlüssel speichern</button></form>${status.google_api_key_set ? '<button class="text-link danger-link" type="button" data-action="google-key-delete">Schlüssel entfernen</button>' : ''}<p class="settings-small">Nach dem Speichern wird der Schlüssel nicht mehr angezeigt.</p></section>`);
  $('.settings-grid').insertAdjacentHTML('beforeend', telegramSettings(serverReachable ? !!status.telegram_server_bot_set : null));
}
function recipeDetails(recipe) {
  const parse = value => { try { const result = JSON.parse(value || '[]'); return Array.isArray(result) ? result : []; } catch (_) { return []; } };
  const ingredients = parse(recipe.ingredients_json).map((item, position) => {
    if (recipe.hidden_ingredient_positions?.includes(position)) return null;
    if (typeof item === 'string') return {text:item, available:recipe.ingredient_availability?.[position]};
    if (!item || typeof item !== 'object') return null;
    const description = typeof item.description === 'string' ? item.description.trim() : '';
    const name = typeof item.name === 'string' ? item.name.trim() : '';
    const preparation = typeof item.preparation === 'string' ? item.preparation.trim() : '';
    const text = description && name && !description.toLocaleLowerCase('de-DE').includes(name.toLocaleLowerCase('de-DE')) ? `${description} ${name}` : description || name;
    return {name, text:text + (preparation && !text.includes(preparation) ? (preparation.startsWith(',') ? '' : ', ') + preparation : ''), available:recipe.ingredient_availability?.[position]};
  }).filter(item => item?.text);
  const groups = parse(recipe.instructions_json);
  const sections = groups.some(item => Array.isArray(item?.steps))
    ? groups.map(group => ({title: group.title || '', steps: (group.steps || []).filter(item => typeof item === 'string' && item)}))
    : [{title: '', steps: groups.map(item => typeof item === 'string' ? item : item?.text).filter(item => typeof item === 'string' && item)}];
  const steps = sections.filter(group => group.steps.length);
  return `${ingredients.length ? `<details class="creation-detail recipe-accordion" id="recipe-ingredients" open><summary>Zutaten<span aria-hidden="true">⌄</span></summary><ul class="ingredient-list">${ingredients.map(item => { const status = item.available === true ? 'available' : item.available === false ? 'missing' : 'unknown'; const label = item.available === true ? 'Im Vorrat' : item.available === false ? 'Nicht im Vorrat' : 'Nicht zugeordnet'; return `<li><span class="ingredient-dot ${status}" role="img" aria-label="${label}" title="${label}"></span><span class="recipe-ingredient-icon" aria-hidden="true">${pantryIcon(item.name || item.text, '')}</span><span>${escapeHTML(item.text)}</span></li>`; }).join('')}</ul></details>` : ''}${steps.length ? `<details class="creation-detail recipe-accordion" id="recipe-preparation"><summary>Zubereitung<span aria-hidden="true">⌄</span></summary>${steps.map(group => `${group.title ? `<h4>${escapeHTML(group.title)}</h4>` : ''}<ol>${group.steps.map(item => `<li>${escapeHTML(item)}</li>`).join('')}</ol>`).join('')}</details>` : ''}`;
}
function renderRecipeTips(tips, custom = false) {
  if (custom && Array.isArray(tips)) {
    const marker = tips.findIndex(item => typeof item === 'string' && /^Notiz:[ \t]?/.test(item));
    if (marker >= 0) tips = tips.slice(0, marker);
  }
  const values = Array.isArray(tips) ? tips.filter(item => typeof item === 'string' && item.trim()) : [];
  return values.length ? `<details class="creation-detail recipe-accordion" id="recipe-tips"><summary>Tipps<span aria-hidden="true">⌄</span></summary><ul class="recipe-tips-list">${values.map(value => `<li>${escapeHTML(value)}</li>`).join('')}</ul></details>` : '';
}
async function loadRecipeTips(recipe, note) {
  const container = $('#recipe-tips-container');
  if (!container) return;
  if (recipe.tips_json != null) {
    try { container.innerHTML = renderRecipeTips(JSON.parse(recipe.tips_json), recipe.id.startsWith('creation:')); } catch (_) { container.innerHTML = ''; }
    return;
  }
  container.innerHTML = '<p class="recipe-tips-status">Tipps werden geladen …</p>';
  try {
    const result = await api(`/api/recipes/${encodeURIComponent(recipe.id)}/tips`);
    if (inlineNote !== note || !$('#recipe-dialog').open) return;
    recipe.tips_json = JSON.stringify(result.tips);
    $('#recipe-tips-container').innerHTML = renderRecipeTips(result.tips, recipe.id.startsWith('creation:'));
  } catch (_) {
    if (inlineNote !== note || !$('#recipe-dialog').open) return;
    $('#recipe-tips-container').innerHTML = '<p class="recipe-tips-status">Tipps konnten nicht geladen werden. <button type="button" class="text-link" data-retry-tips>Erneut versuchen</button></p>';
  }
}
function setInlineNoteStatus(note, message, error = false) {
  if (inlineNote !== note || !$('#recipe-dialog').open) return;
  const status = $('#recipe-note-status');
  if (status) { status.textContent = message; status.hidden = !message; status.classList.toggle('is-error', error); }
}
function resizeInlineNote(field) {
  field.style.height = 'auto';
  field.style.height = `${field.scrollHeight}px`;
}
async function loadRecipeNote(note) {
  const request = ++recipeNoteRequest;
  note.loading = true;
  setInlineNoteStatus(note, 'Notiz wird geladen …');
  try {
    const result = await api(`/api/notes/${encodeURIComponent(note.id)}`);
    if (request !== recipeNoteRequest || inlineNote !== note) return;
    note.original = result.text; note.draft = result.text; note.loaded = true;
    noteBadgeVersion[note.id] = (noteBadgeVersion[note.id] || 0) + 1;
    updateWeekBadges(note.id, {has_note:!!result.text.trim()});
    const field = $('#recipe-note-text');
    if (field) { field.value = result.text; field.readOnly = false; resizeInlineNote(field); }
    setInlineNoteStatus(note, '');
  } catch (error) {
    if (request === recipeNoteRequest) setInlineNoteStatus(note, `${error.message} Zum erneuten Laden ins Feld klicken.`, true);
  } finally { note.loading = false; }
}
async function saveInlineNote(note) {
  if (!note?.loaded) return true;
  note.requested = true;
  if (note.saving) return note.saving;
  note.saving = (async () => {
    while (note.requested) {
      note.requested = false;
      if (note.draft === note.original) break;
      const text = note.draft;
      setInlineNoteStatus(note, 'Notiz wird mit Cookidoo abgeglichen …');
      try {
        const result = await api(`/api/notes/${encodeURIComponent(note.id)}`, {method:'PUT', body:JSON.stringify({text, expected:note.original})});
        note.original = result.text;
        noteBadgeVersion[note.id] = (noteBadgeVersion[note.id] || 0) + 1;
        updateWeekBadges(note.id, {has_note:!!result.text.trim()});
        setInlineNoteStatus(note, note.draft === note.original ? 'In Cookidoo gespeichert.' : 'Weitere Änderung noch nicht gespeichert.');
      } catch (error) {
        note.requested = false;
        setInlineNoteStatus(note, `${error.message} Dein Text bleibt im Feld erhalten.`, true);
        return false;
      }
    }
    return true;
  })();
  try { return await note.saving; } finally { note.saving = null; }
}
async function ensureInlineNoteSaved() {
  const note = inlineNote;
  if (!note?.loaded || (!note.saving && note.draft === note.original)) return true;
  const saved = await saveInlineNote(note);
  return saved && note.draft === note.original;
}
async function openRecipe(id, fromWeek = false) {
  previewInteractionBusy = true;
  try {
  if (previewNoteBusy) await previewNoteDone;
  if ($('#recipe-dialog').open && !await ensureInlineNoteSaved()) {
    if ($('#recipe-version') && inlineNote) $('#recipe-version').value = inlineNote.id;
    return;
  }
  if (weekBadgesBusy) await weekBadgesDone;
  const recipe = await api('/api/recipes/' + encodeURIComponent(id) + (fromWeek ? '?calendar=true' : ''));
  const time = duration(recipe.total_seconds), active = duration(recipe.active_seconds);
  const local = state.collections.filter(c => c.kind === 'local');
  const difficulty = {easy:'Einfach',medium:'Mittel',advanced:'Anspruchsvoll',hard:'Anspruchsvoll'}[recipe.difficulty?.toLowerCase()];
  const versions = recipe.versions || [];
  const selector = versions.length > 1 ? `<label class="version-select">Rezeptversion<select id="recipe-version">${versions.map((version, index) => `<option value="${escapeHTML(version.id)}" ${version.id === recipe.id ? 'selected' : ''}>${version.origin_recipe_id ? `Meine Kreation${versions.filter(v => v.origin_recipe_id).length > 1 ? ` ${index}` : ''}` : 'Cookidoo-Original'}${version.servings ? ` · ${escapeHTML(version.servings)} Portionen` : ''}</option>`).join('')}</select></label>` : '';
  $('#recipe-content').innerHTML = `<div class="recipe-detail-photo">${photo(recipe.image_file, recipe.name, true)}</div><div class="recipe-detail-body"><div class="recipe-collection-pills">${recipe.collections.map(c => `<a data-close-recipe href="#liste/${encodeURIComponent(c.id)}">${escapeHTML(c.name)}</a>`).join('')}</div><h2 id="recipe-title">${escapeHTML(recipe.name)}</h2>${selector}<div class="recipe-meta">${time ? `<span class="meta-chip">${icon('clock')}${time} gesamt</span>` : ''}${active ? `<span class="meta-chip">${active} Arbeitszeit</span>` : ''}${recipe.servings ? `<span class="meta-chip">${escapeHTML(recipe.servings)} Portionen</span>` : ''}${difficulty ? `<span class="meta-chip">${difficulty}</span>` : ''}</div><div class="recipe-note-preview" id="recipe-note-preview" data-recipe-id="${escapeHTML(recipe.id)}"><label class="recipe-note-heading" for="recipe-note-text"><strong>Meine Notiz</strong>${icon('edit')}</label><textarea id="recipe-note-text" class="recipe-note-text" rows="1" maxlength="5000" placeholder="Notiz hinzufügen" aria-describedby="recipe-note-status" enterkeyhint="done" readonly></textarea></div><p id="recipe-note-status" class="recipe-note-status" role="status" hidden></p>${recipeDetails(recipe)}<div id="recipe-tips-container"></div>${recipe.is_local === false ? '<p class="calendar-detail-hint">Dieses Rezept ist in deiner Cookidoo-Woche eingeplant.</p>' : `<section class="local-memberships"><h3>Zu lokalen Listen hinzufügen</h3>${local.length ? local.map(c => `<label class="membership-option"><input type="checkbox" data-local-list="${escapeHTML(c.id)}" data-local-recipe="${escapeHTML(recipe.id)}" ${recipe.collections.some(item => item.id === c.id) ? 'checked' : ''}><span>${escapeHTML(c.name)}</span></label>`).join('') : '<p>Erstelle zuerst eine lokale Rezeptliste unter „Listen“.</p>'}</section>`}<button type="button" class="button button-primary button-full" data-action="plan-today" data-action-calendar="${recipe.is_local === false}" data-action-recipe="${escapeHTML(recipe.id)}"><span class="recipe-action-label">${icon('cook')}Heute kochen</span></button><button type="button" class="button button-primary button-full" data-action="add-shopping" data-action-calendar="${recipe.is_local === false}" data-action-recipe="${escapeHTML(recipe.id)}"><span class="recipe-action-label">${icon('cart')}Zum Einkaufswagen hinzufügen</span></button><a class="button button-primary button-full" href="${escapeHTML(recipe.source_url)}" target="_blank" rel="noopener noreferrer"><span class="recipe-action-label">${icon('external')}In Cookidoo öffnen</span></a></div>`;
  if (!$('#recipe-dialog').open) $('#recipe-dialog').showModal();
  inlineNote = {id:recipe.id, original:'', draft:'', loaded:false, loading:false, saving:null, requested:false};
  const currentNote = inlineNote;
  loadRecipeNote(currentNote).then(() => loadRecipeTips(recipe, currentNote));
  } finally { previewInteractionBusy = false; }
}
async function startSync() {
  if (!state.status?.connected) { $('#connect-dialog').showModal(); return; }
  if (weekQueueWriting) { toast('Bitte schließe zuerst die Änderung an der Woche ab.'); return; }
  const result = await post('/api/sync');
  state.status = await api('/api/status'); updateSync();
  if (result.started && !state.status.sync.running) { await loadLibrary(); toast(state.status.sync.message); }
}
async function install() {
  if (deferredInstall) {
    await deferredInstall.prompt(); await deferredInstall.userChoice; deferredInstall = null;
    document.querySelectorAll('.install-trigger').forEach(node => { node.hidden = true; });
  } else $('#install-dialog').showModal();
}
document.addEventListener('input', event => {
  if (event.target.id !== 'recipe-note-text' || !inlineNote?.loaded) return;
  inlineNote.draft = event.target.value;
  resizeInlineNote(event.target);
  setInlineNoteStatus(inlineNote, '');
});
document.addEventListener('focusin', event => {
  if (event.target.id === 'recipe-note-text' && inlineNote && !inlineNote.loaded && !inlineNote.loading) loadRecipeNote(inlineNote);
});
document.addEventListener('focusout', event => {
  if (event.target.id === 'recipe-note-text' && inlineNote?.loaded) saveInlineNote(inlineNote);
});
document.addEventListener('keydown', event => {
  if (event.target.id === 'recipe-note-text' && event.key === 'Enter' && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    event.target.blur();
  }
});
async function closeRecipeSafely() {
  if (document.activeElement?.id === 'recipe-note-text') document.activeElement.blur();
  if (!await ensureInlineNoteSaved()) return false;
  $('#recipe-dialog').close();
  if (weekQueueRefreshPending && state.view === 'meine-woche') {
    weekQueueRefreshPending = false;
    renderRoute().catch(error => toast(error.message));
  }
  return true;
}
$('#recipe-dialog').addEventListener('cancel', event => { event.preventDefault(); closeRecipeSafely(); });
let weekMouseDrag = null;
document.addEventListener('dragstart', event => {
  const placeholder = event.target.closest('[data-placeholder-drag]');
  if (placeholder) {
    if (!displayedWeek || weekPlaceholderBusy || event.target.closest('[data-week-placeholder-action], [data-week-placeholder-add]')) { event.preventDefault(); return; }
    weekMouseDrag = {placeholder:true, source:placeholder.dataset.placeholderSource, id:placeholder.dataset.placeholderDrag, instance:placeholder.dataset.placeholderInstance || null};
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', placeholder.querySelector('.candidate-name,.week-recipe-name')?.textContent || 'Platzhalter');
    placeholder.classList.add('week-dragging');
    return;
  }
  const card = event.target.closest('.week-recipe[draggable]');
  if (!card) return;
  const item = card.closest('[data-week-recipe]');
  if (!item || weekSaving || weekQueueWriting || weekQueueError || weekShoppingBusy || previewShelfBusy || !displayedWeek) { event.preventDefault(); return; }
  weekMouseDrag = {source:item.dataset.weekSource, id:item.dataset.weekRecipe, custom:item.dataset.weekCustom === '1'};
  event.dataTransfer.effectAllowed = 'move';
  event.dataTransfer.setData('text/plain', item.querySelector('.week-recipe-name')?.textContent || 'Rezept');
  item.classList.add('week-dragging');
});
document.addEventListener('dragover', event => {
  if (!weekMouseDrag) return;
  const target = event.target.closest('[data-week-day]');
  document.querySelectorAll('.week-drop-target').forEach(node => { if (node !== target) node.classList.remove('week-drop-target'); });
  if (!target || target.dataset.weekDay === weekMouseDrag.source) return;
  event.preventDefault(); event.dataTransfer.dropEffect = 'move'; target.classList.add('week-drop-target');
});
function clearWeekMouseDrag() {
  document.querySelectorAll('.week-dragging,.week-drop-target').forEach(node => node.classList.remove('week-dragging', 'week-drop-target'));
  weekMouseDrag = null;
}
document.addEventListener('drop', event => {
  if (!weekMouseDrag) return;
  const target = event.target.closest('[data-week-day]');
  const drag = weekMouseDrag;
  if (target) event.preventDefault();
  clearWeekMouseDrag();
  if (target && target.dataset.weekDay !== drag.source) {
    if (drag.placeholder) setWeekPlaceholder(drag.id, true, target.dataset.weekDay, drag.instance);
    else queueWeekMove(drag.source, target.dataset.weekDay, drag.id, drag.custom);
  }
});
document.addEventListener('dragend', clearWeekMouseDrag);
// A long press starts touch dragging without blocking ordinary scrolling or taps.
let weekTouchDrag = null, weekTouchSuppressClick = false, weekSwipeSelection = null;
function clearWeekSwipeSelection() {
  weekSwipeSelection?.source.classList.remove('week-touch-ready');
  weekSwipeSelection = null;
  document.documentElement.classList.remove('week-swipe-selected');
}
function selectWeekSwipe(touch) {
  clearWeekSwipeSelection();
  weekSwipeSelection = {source:touch.source, drag:touch.drag, week:touch.week};
  touch.source.classList.add('week-touch-ready');
  document.documentElement.classList.add('week-swipe-selected');
}
window.addEventListener('hashchange', clearWeekSwipeSelection);
document.addEventListener('contextmenu', event => {
  if (matchMedia('(pointer:coarse)').matches && event.target.closest('[data-recipe], [data-week-recipe], [data-placeholder-drag], [data-recipe-image]')) event.preventDefault();
});
function updateWeekTouchTarget() {
  const touch = weekTouchDrag;
  if (!touch?.active) return;
  const target = document.elementFromPoint(touch.x, touch.y)?.closest('[data-week-day]');
  touch.target = target && target.dataset.weekDay !== touch.drag.source ? target : null;
  document.querySelectorAll('.week-drop-target').forEach(node => { if (node !== touch.target) node.classList.remove('week-drop-target'); });
  touch.target?.classList.add('week-drop-target');
}
function finishWeekTouchDrag(commit = false) {
  const touch = weekTouchDrag;
  if (!touch) return;
  clearTimeout(touch.timer); clearInterval(touch.scrollTimer);
  $('.week-scroll')?.classList.remove('week-touch-scrolling');
  document.querySelectorAll('.week-dragging,.week-drop-target').forEach(node => node.classList.remove('week-dragging', 'week-drop-target'));
  touch.source.style.removeProperty('transform');
  if (touch.nativeDragElement) touch.nativeDragElement.draggable = touch.nativeDragWasEnabled;
  touch.source.querySelector('.week-swipe-feedback')?.remove();
  if (!weekSwipeSelection) touch.source.classList.remove('week-touch-ready');
  weekTouchDrag = null;
  if (!touch.active && !touch.swiping && !touch.ready) return;
  weekTouchSuppressClick = true;
  setTimeout(() => { weekTouchSuppressClick = false; }, 700);
  if (touch.swiping) {
    const distance = touch.y - touch.startY;
    if (commit && Math.abs(distance) >= 90 && touch.week === displayedWeek && touch.source.isConnected) {
      const target = touch.drag.source === 'shelf' ? (distance < 0 ? displayedWeek.days[weekVisibleDay]?.date : 'trash') : (distance < 0 ? 'trash' : 'shelf');
      if (target) {
        clearWeekSwipeSelection();
        if (touch.drag.placeholder) setWeekPlaceholder(touch.drag.id, target !== 'trash', target === 'trash' ? 'shelf' : target, touch.drag.instance);
        else queueWeekMove(touch.drag.source, target, touch.drag.id, touch.drag.custom);
      }
    }
    return;
  }
  if (commit && touch.target) {
    clearWeekSwipeSelection();
    if (touch.drag.placeholder) setWeekPlaceholder(touch.drag.id, true, touch.target.dataset.weekDay, touch.drag.instance);
    else queueWeekMove(touch.drag.source, touch.target.dataset.weekDay, touch.drag.id, touch.drag.custom);
  } else if (touch.active || (commit && touch.fromSelection)) clearWeekSwipeSelection();
}
document.addEventListener('touchstart', event => {
  if (weekTouchDrag || event.touches.length !== 1) return;
  if (weekSwipeSelection && (!weekSwipeSelection.source.isConnected || weekSwipeSelection.week !== displayedWeek)) clearWeekSwipeSelection();
  if (weekSwipeSelection) {
    const point = event.touches[0], selected = weekSwipeSelection;
    weekTouchDrag = {...selected, id:point.identifier, x:point.clientX, y:point.clientY, startX:point.clientX, startY:point.clientY, active:false, swiping:false, ready:true, fromSelection:true};
    return;
  }
  if (event.target.closest('[data-week-placeholder-action], [data-week-placeholder-add], [data-week-preview-action]')) return;
  const placeholder = event.target.closest('[data-placeholder-drag]');
  const item = event.target.closest('.week-recipe[draggable]')?.closest('[data-week-recipe]');
  let drag, source;
  if (placeholder && displayedWeek && !weekPlaceholderBusy) {
    source = placeholder;
    drag = {placeholder:true, source:placeholder.dataset.placeholderSource, id:placeholder.dataset.placeholderDrag, instance:placeholder.dataset.placeholderInstance || null};
  } else if (item && displayedWeek && !weekSaving && !weekQueueWriting && !weekQueueError && !weekShoppingBusy && !previewShelfBusy) {
    source = item;
    drag = {source:item.dataset.weekSource, id:item.dataset.weekRecipe, custom:item.dataset.weekCustom === '1'};
  } else return;
  const point = event.touches[0];
  const nativeDragElement = placeholder || item?.querySelector('.week-recipe');
  const nativeDragWasEnabled = !!nativeDragElement?.draggable;
  if (nativeDragElement) nativeDragElement.draggable = false;
  const touch = weekTouchDrag = {drag, source, nativeDragElement, nativeDragWasEnabled, week:displayedWeek, id:point.identifier, x:point.clientX, y:point.clientY, startX:point.clientX, startY:point.clientY, active:false, swiping:false, ready:false};
  touch.timer = setTimeout(() => {
    if (weekTouchDrag !== touch || !source.isConnected) return;
    touch.ready = true;
    if (!drag.placeholder || drag.instance) selectWeekSwipe(touch);
    else source.classList.add('week-touch-ready');
  }, 500);
}, {passive:true});
function startWeekTouchDrag(touch) {
    touch.active = true; touch.source.classList.remove('week-touch-ready'); touch.source.classList.add('week-dragging');
    $('.week-scroll')?.classList.add('week-touch-scrolling');
    updateWeekTouchTarget();
    touch.scrollTimer = setInterval(() => {
      const edge = 65, speed = 16;
      if (touch.y < edge) window.scrollBy(0, -speed);
      else if (touch.y > innerHeight - edge) window.scrollBy(0, speed);
      const scroll = document.querySelector('.week-scroll');
      if (scroll) {
        const rect = scroll.getBoundingClientRect();
        if (touch.y >= rect.top && touch.y <= rect.bottom) {
          if (touch.x < rect.left + edge) scroll.scrollLeft -= speed;
          else if (touch.x > rect.right - edge) scroll.scrollLeft += speed;
        }
      }
      updateWeekTouchTarget();
    }, 40);
}
document.addEventListener('touchmove', event => {
  const touch = weekTouchDrag;
  const point = touch && Array.from(event.changedTouches).find(item => item.identifier === touch.id);
  if (!point) return;
  touch.x = point.clientX; touch.y = point.clientY;
  if (!touch.active) {
    const dx = touch.x - touch.startX, dy = touch.y - touch.startY;
    if (!touch.swiping && Math.hypot(dx, dy) > 10) {
      if (!touch.ready || !event.cancelable) { finishWeekTouchDrag(); return; }
      event.preventDefault();
      if ((!touch.drag.placeholder || touch.drag.instance) && Math.abs(dy) > Math.abs(dx) * 1.3) {
        touch.swiping = true; clearTimeout(touch.timer);
        const feedback = document.createElement('span'); feedback.className = 'week-swipe-feedback'; feedback.setAttribute('aria-hidden', 'true'); touch.source.append(feedback);
      } else { startWeekTouchDrag(touch); updateWeekTouchTarget(); return; }
    }
    if (touch.ready && event.cancelable) event.preventDefault();
    if (touch.swiping) {
      event.preventDefault();
      touch.source.style.transform = `translateY(${Math.max(-45, Math.min(45, dy * .35))}px)`;
      const feedback = touch.source.querySelector('.week-swipe-feedback');
      if (feedback) feedback.textContent = touch.drag.source === 'shelf' ? (dy < 0 ? 'Zum angezeigten Tag' : 'Entfernen') : (dy < 0 ? 'Entfernen' : 'In die Ablage');
    }
    return;
  }
  event.preventDefault(); updateWeekTouchTarget();
}, {passive:false});
document.addEventListener('touchend', event => {
  if (weekTouchDrag && Array.from(event.changedTouches).some(item => item.identifier === weekTouchDrag.id)) finishWeekTouchDrag(true);
});
document.addEventListener('touchcancel', () => finishWeekTouchDrag());
document.addEventListener('click', event => {
  if (weekTouchSuppressClick) { event.preventDefault(); event.stopImmediatePropagation(); weekTouchSuppressClick = false; }
}, true);
document.addEventListener('toggle', event => {
  if (!event.target.matches?.('[data-week-list]') || !event.target.isConnected) return;
  if (event.target.open) { weekOpenLists.add(event.target.dataset.weekList); loadWeekList(event.target).catch(error => toast(error.message)); }
  else weekOpenLists.delete(event.target.dataset.weekList);
}, true);
window.addEventListener('beforeunload', event => { if (weekQueueWriting || weekShoppingBusy || (inlineNote?.loaded && (inlineNote.saving || inlineNote.draft !== inlineNote.original))) { event.preventDefault(); event.returnValue = ''; } });
document.addEventListener('click', async event => {
  const placeholderAdd = event.target.closest('[data-week-placeholder-add]');
  const placeholderAction = event.target.closest('[data-week-placeholder-action]');
  if (placeholderAdd) { await setWeekPlaceholder(placeholderAdd.dataset.weekPlaceholderAdd, true); return; }
  if (placeholderAction) {
    const card = placeholderAction.closest('[data-placeholder-instance]');
    if (card) await setWeekPlaceholder(placeholderAction.dataset.weekPlaceholderAction, card.dataset.placeholderSource !== 'shelf', 'shelf', card.dataset.placeholderInstance);
    return;
  }
  const retryTips = event.target.closest('[data-retry-tips]');
  if (retryTips && inlineNote) { await loadRecipeTips({id:inlineNote.id, tips_json:null}, inlineNote); return; }
  const close = event.target.closest('.close-dialog');
  if (close) { const dialog = close.closest('dialog'); if (dialog.id === 'recipe-dialog') await closeRecipeSafely(); else dialog.close(); return; }
  const previewWeek = event.target.closest('[data-preview-week-add]');
  if (previewWeek) { await addPreviewToWeek(previewWeek.dataset.previewWeekAdd); return; }
  const weekAction = event.target.closest('[data-week-preview-action]');
  if (weekAction) {
    const item = weekAction.closest('[data-week-recipe]');
    if (item && !previewShelfBusy) await queueWeekMove(item.dataset.weekSource, item.dataset.weekSource === 'shelf' ? 'trash' : 'shelf', item.dataset.weekRecipe, item.dataset.weekCustom === '1');
    return;
  }
  const recipe = event.target.closest('[data-recipe]');
  const addRecipe = event.target.closest('[data-add-recipe]');
  const weekAdd = event.target.closest('[data-week-add]');
  const weekListMore = event.target.closest('[data-week-list-more]');
  const deleteLocalList = event.target.closest('[data-delete-local-list]');
  const deletePantryCategory = event.target.closest('[data-pantry-delete-category]');
  const pantryAdd = event.target.closest('[data-pantry-add-category]');
  const pantryEdit = event.target.closest('[data-pantry-edit]');
  const pantryRemove = event.target.closest('[data-pantry-remove]');
  const pantryToggle = event.target.closest('[data-pantry-toggle]');
  const action = event.target.closest('[data-action]');
  try {
    if (deleteLocalList) {
      const list = state.collections.find(item => item.id === deleteLocalList.dataset.deleteLocalList && item.kind === 'local');
      if (list && confirm(`Lokale Liste „${list.name}“ löschen? Die Zuordnungen zu dieser Liste werden entfernt. Rezepte, die nur hier gespeichert sind, erscheinen danach nicht mehr in der Sammlung.`)) {
        deleteLocalList.disabled = true;
        try { await api(`/api/local-collections/${encodeURIComponent(list.id)}`, {method:'DELETE'}); location.hash = '#listen'; await loadLibrary(); toast('Lokale Liste gelöscht.'); }
        finally { deleteLocalList.disabled = false; }
      }
      return;
    }
    if (deletePantryCategory) {
      const category = state.pantry.categories.find(item => item.id === Number(deletePantryCategory.dataset.pantryDeleteCategory));
      if (category && confirm(`Vorratskategorie „${category.name}“ löschen? Alle darin enthaltenen Vorratseinträge werden ebenfalls gelöscht.`)) {
        deletePantryCategory.disabled = true;
        try { await api(`/api/pantry/categories/${category.id}`, {method:'DELETE'}); collapsedPantry.delete(category.id); await refreshPantry(); toast('Vorratskategorie gelöscht.'); }
        finally { deletePantryCategory.disabled = false; }
      }
      return;
    }
    if (weekAdd) await addRecipeToWeekShelf(weekAdd.dataset.weekAdd);
    if (weekListMore) await loadWeekList(weekListMore.closest('[data-week-list]'));
    if (event.target.closest('#recipe-note-preview') && event.target.id !== 'recipe-note-text') $('#recipe-note-text')?.focus();
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
    const closeRecipeLink = event.target.closest('[data-close-recipe]');
    if (closeRecipeLink) {
      event.preventDefault();
      if (await closeRecipeSafely()) location.hash = closeRecipeLink.getAttribute('href');
      return;
    }
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
    if (recipe) await openRecipe(recipe.dataset.recipe, !!recipe.closest('[data-week-recipe], [data-cart-recipe]'));
    const cartRemove = event.target.closest('[data-cart-remove]');
    if (cartRemove) {
      cartRemove.disabled = true;
      try { await api(`/api/cart/${encodeURIComponent(cartRemove.dataset.cartRemove)}`, {method:'DELETE'}); await renderCart(); }
      finally { cartRemove.disabled = false; }
    }
    const cartResolve = event.target.closest('[data-cart-resolve]');
    if (cartResolve && confirm('Hast du diesen Eintrag in Cookidoo geprüft?')) {
      cartResolve.disabled = true;
      try { await post(`/api/cart/${encodeURIComponent(cartResolve.dataset.cartResolve)}/resolve`, {status:cartResolve.dataset.status}); await renderCart(); }
      finally { cartResolve.disabled = false; }
    }
    if (event.target.closest('.install-trigger')) await install();
    if (action) {
      switch (action.dataset.action) {
        case 'plan-today':
        case 'add-shopping': {
          if (!await ensureInlineNoteSaved()) break;
          action.disabled = true;
          try {
            const planning = action.dataset.action === 'plan-today';
            const result = await post(`/api/recipes/${encodeURIComponent(action.dataset.actionRecipe)}/${planning ? 'plan-today' : 'shopping'}${action.dataset.actionCalendar === 'true' ? '?calendar=true' : ''}`);
            if (!planning) refreshCartCount().catch(() => {});
            toast(planning ? (result.verified ? 'Für heute im Cookidoo-Kalender eingeplant.' : 'Cookidoo hat die Anfrage angenommen, aber der Kalendereintrag konnte nicht bestätigt werden. Bitte prüfe den Kalender, bevor du es erneut versuchst.') : result.added ? 'Zum Einkaufswagen hinzugefügt.' : 'Dieses Rezept steht bereits im Einkaufswagen.');
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
        case 'previous-week': weekOffset--; await renderRoute(); $('[data-action="previous-week"]')?.focus(); break;
        case 'next-week': weekOffset++; await renderRoute(); $('[data-action="next-week"]')?.focus(); break;
        case 'current-week': weekOffset = 0; await renderRoute(); $('[data-action="current-week"]')?.focus(); break;
        case 'week-shopping': await addWeekShopping(); $('[data-action="week-shopping"]')?.focus(); break;
        case 'cart-transfer': {
          action.disabled = true;
          try { const result = await post('/api/cart/transfer'); await renderCart(); toast(result.message || 'Einkaufswagen an Cookidoo übertragen.'); }
          finally { action.disabled = false; }
          break;
        }
        case 'cart-clear':
          if (confirm('Den gesamten lokalen Einkaufswagen leeren?')) { await api('/api/cart', {method:'DELETE'}); await renderCart(); toast('Einkaufswagen geleert.'); }
          break;
        case 'retry-week': await renderRoute(); break;
        case 'discard-week-moves': {
          if (!confirm('Die vorgemerkten Änderungen werden verworfen. Bereits in Cookidoo übernommene Änderungen bleiben dort bestehen. Fortfahren?')) break;
          const queue = await api('/api/calendar/queue', {method:'DELETE'});
          adoptWeekQueue(queue); if (state.status) state.status.calendar_queue = queue;
          await renderRoute();
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
document.addEventListener('click', async event => {
  const remove = event.target.closest('[data-telegram-delete]');
  if (!remove) return;
  remove.disabled = true;
  try {
    if (remove.dataset.telegramDelete === 'server') { await api('/api/telegram-server-bot', {method:'DELETE'}); state.status.telegram_server_bot_set = false; }
    else { localStorage.removeItem(telegramClientKey); localStorage.removeItem(telegramPairKey); }
    state.status ? renderSettings() : renderOfflineSettings(); toast('Bot-Token entfernt.');
  } catch (error) { toast(error.message || 'Token konnte nicht entfernt werden.'); }
  finally { remove.disabled = false; }
});
document.addEventListener('submit', async event => {
  if (event.target.matches('[data-telegram-form]')) {
    event.preventDefault();
    const role = event.target.dataset.telegramForm, input = event.target.querySelector('input'), button = event.target.querySelector('button');
    const token = input.value.trim(); input.value = '';
    if (!/^[0-9]{1,20}:[A-Za-z0-9_-]{20,200}$/.test(token)) { toast('Bitte gib ein gültiges Bot-Token ein.'); return; }
    button.disabled = true;
    try {
      if (role === 'server') { await post('/api/telegram-server-bot', {token}); state.status.telegram_server_bot_set = true; }
      else { localStorage.setItem(telegramClientKey, token); localStorage.removeItem(telegramPairKey); }
      state.status ? renderSettings() : renderOfflineSettings(); toast('Bot-Token gespeichert.');
    } catch (error) { toast(error.message || 'Token konnte nicht gespeichert werden.'); }
    finally { button.disabled = false; }
    return;
  }
  if (event.target.id === 'cart-item-form') {
    event.preventDefault();
    const form = event.target, input = $('#cart-item-name'), button = form.querySelector('button');
    button.disabled = true;
    try { await post('/api/cart/items', {name:input.value}); await renderCart(); $('#cart-item-name')?.focus(); }
    catch (error) { toast(error.message); }
    finally { button.disabled = false; }
    return;
  }
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
    if (event.target.matches('[data-cart-ingredient], [data-cart-owned]')) {
      const checkbox = event.target;
      const path = checkbox.dataset.cartIngredient ? `/api/cart/${encodeURIComponent(checkbox.dataset.cartIngredient)}/ingredients/${checkbox.dataset.position}` : `/api/cart/${encodeURIComponent(checkbox.dataset.cartOwned)}/owned`;
      checkbox.disabled = true;
      try {
        await api(path, {method:'PUT', body:JSON.stringify({owned:checkbox.checked})});
        if (checkbox.dataset.cartIngredient && state.view === 'einkaufswagen') {
          const entry = checkbox.dataset.cartIngredient, position = checkbox.dataset.position;
          await renderCart();
          document.querySelector(`[data-cart-ingredient="${CSS.escape(entry)}"][data-position="${CSS.escape(position)}"]`)?.focus({preventScroll:true});
        }
      }
      catch (error) { checkbox.checked = !checkbox.checked; throw error; }
      finally { checkbox.disabled = false; }
      return;
    }
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
window.addEventListener('online', () => { if (!state.status) loadLibrary().catch(() => {}); });
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && navigator.onLine && state.view === 'uebersicht' && featuredLocalDay !== berlinDay()) loadFeatured().catch(error => toast(error.message));
});
setInterval(async () => {
  if (!state.status || polling || !navigator.onLine) return;
  polling = true;
  try {
    const previous = state.status;
    state.status = await api('/api/status'); updateSync();
    const queueChanged = adoptWeekQueue(state.status.calendar_queue);
    if (queueChanged && state.view === 'meine-woche') {
      if ($('#recipe-dialog').open) weekQueueRefreshPending = true;
      else if (weekSaving && displayedWeek) showWeek();
      else await renderRoute();
    }
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
  } catch (error) { await renderRoute(); }
  if ('serviceWorker' in navigator && window.isSecureContext) navigator.serviceWorker.register('/sw.js').catch(() => {});
}
initialize();
