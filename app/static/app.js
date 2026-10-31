'use strict';
const $ = selector => document.querySelector(selector);
const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
const photo = (file, alt = '', eager = false) => file ? `<img data-recipe-image src="/api/images/${encodeURIComponent(file)}" alt="${escapeHTML(alt)}" loading="${eager ? 'eager' : 'lazy'}" decoding="async">` : `<span class="image-placeholder" aria-label="Kein Rezeptbild verfügbar">${icon('bowl')}</span>`;
const state = {status:null, collections:[], recipes:[], total:0, offset:0, view:'uebersicht', collection:null, query:'', sort:'name', authenticated:false, configured:true, request:0};
let setupCode = '', deferredInstall = null, toastTimer, searchTimer, polling = false;
if (location.hash.startsWith('#setup=')) {
  setupCode = new URLSearchParams(location.hash.slice(1)).get('setup') || '';
  history.replaceState(null, '', location.pathname);
}

function toast(message) {
  const node = $('#toast'); node.textContent = message; node.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { node.hidden = true; }, 6500);
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
    if (response.status === 401 && !path.startsWith('/api/auth/')) { state.authenticated = false; showAuth(); }
    throw new Error(typeof payload.detail === 'string' ? payload.detail : 'Bitte prüfe die Eingaben und versuche es erneut.');
  }
  return payload;
}
const post = (path, body = {}) => api(path, {method:'POST',body:JSON.stringify(body)});

function showAuth() {
  const setup = !state.configured;
  $('#auth-title').innerHTML = setup ? 'Ein guter Platz für<br>deine Lieblingsrezepte.' : 'Schön, dass<br>du wieder da bist.';
  $('#auth-description').textContent = setup ? 'Lege ein eigenes Passwort für deine lokale App fest. Du brauchst dafür den einmaligen Einrichtungscode.' : 'Öffne deine Sammlung mit deinem App-Passwort.';
  $('#setup-code-label').hidden = !setup;
  $('#setup-code').required = setup;
  $('#setup-code').value = setupCode;
  $('#app-password').minLength = setup ? 8 : 1;
  $('#app-password').autocomplete = setup ? 'new-password' : 'current-password';
  $('#auth-submit').innerHTML = `${setup ? 'Rezeptgarten einrichten' : 'Sammlung öffnen'}${icon('arrow')}`;
  if (!$('#auth-dialog').open) $('#auth-dialog').showModal();
}
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
  $('#connection-label').innerHTML = `<span class="status-dot"></span>${state.status.connected ? 'Mit Cookidoo verbunden' : 'Lokale Sammlung'}`;
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
  return `<a class="collection-card" href="#liste/${encodeURIComponent(collection.id)}"><div class="collection-mosaic ${images.length ? '' : 'no-images'}">${mosaic}</div><div class="collection-info"><div><h3>${escapeHTML(collection.name)}</h3><p>${collection.recipe_count} ${collection.recipe_count === 1 ? 'Rezept' : 'Rezepte'} · ${collection.kind === 'bookmarks' ? 'Merkliste' : collection.kind === 'managed' ? 'Kollektion' : 'Eigene Liste'}</p></div><span class="collection-arrow">${icon('arrow')}</span></div></a>`;
}
function recipeCard(recipe) {
  const time = duration(recipe.total_seconds);
  const difficulty = {easy:'Einfach',medium:'Mittel',advanced:'Anspruchsvoll',hard:'Anspruchsvoll'}[recipe.difficulty] || 'Cookidoo-Rezept';
  return `<button class="recipe-card" data-recipe="${escapeHTML(recipe.id)}" aria-label="${escapeHTML(recipe.name)} öffnen"><div class="recipe-photo">${photo(recipe.image_file, recipe.name)}${time ? `<span class="recipe-time">${icon('clock')}${time}</span>` : ''}</div><div class="recipe-info"><h3>${escapeHTML(recipe.name)}</h3><p>${escapeHTML(difficulty)}</p></div></button>`;
}
function navActive(view) {
  document.querySelectorAll('[data-nav]').forEach(node => {
    const active = node.dataset.nav === (view === 'collection' ? 'listen' : view);
    node.classList.toggle('active', active);
    if (active) node.setAttribute('aria-current', 'page'); else node.removeAttribute('aria-current');
  });
}
async function renderRoute() {
  if (!state.authenticated || !state.status) return;
  const request = ++state.request;
  const fragment = location.hash.slice(1);
  state.collection = null;
  state.view = fragment.startsWith('liste/') ? 'collection' : (['listen','rezepte','einstellungen'].includes(fragment) ? fragment : 'uebersicht');
  if (state.view === 'collection') {
    try { state.collection = decodeURIComponent(fragment.slice(6)); } catch (_) { state.collection = null; }
  }
  if (state.query && state.view !== 'collection') state.view = 'rezepte';
  navActive(state.view);
  const content = $('#content');
  if (state.view === 'einstellungen') { renderSettings(); return; }
  if (state.view === 'listen') {
    content.innerHTML = `<div class="page-title"><span class="eyebrow">ALLES HAT SEINEN PLATZ</span><h1>Deine Rezeptlisten</h1><p>Eigene Listen und gespeicherte Kollektionen aus deinem Cookidoo-Konto.</p></div>${state.collections.length ? `<div class="collection-grid">${state.collections.map(collectionCard).join('')}</div>` : emptyContent('Dein Rezeptregal wartet.', 'Verbinde dein Cookidoo-Konto, um deine gespeicherten Listen mit allen Rezepten hier zu sehen.', true)}`;
    return;
  }
  if (state.view === 'uebersicht') {
    const stats = state.status.stats;
    content.innerHTML = `<section class="hero"><div class="hero-copy"><span class="eyebrow">DEIN PERSÖNLICHES REZEPTREGAL</span><h1>Deine Sammlung.<br>Einfach griffbereit.</h1><p>Alle deine Lieblingsrezepte an einem Ort.<br>Weniger suchen. Mehr Freude am Kochen.</p></div><div class="hero-art" aria-hidden="true"><div class="plate">${icon('leaf')}</div><span class="hero-tag">${icon('check')}Bei dir zu Hause gespeichert</span></div></section><section class="stats" aria-label="Deine Sammlung in Zahlen"><div class="stat"><span class="stat-icon">${icon('layers')}</span><div><div class="stat-value">${stats.collections}</div><div class="stat-label">Rezeptlisten</div></div></div><div class="stat"><span class="stat-icon">${icon('book')}</span><div><div class="stat-value">${stats.recipes}</div><div class="stat-label">Gespeicherte Rezepte</div></div></div><div class="stat"><span class="stat-icon">${icon('sync')}</span><div><div class="stat-value date">${escapeHTML(formatDate(stats.last_sync, true))}</div><div class="stat-label">Letzte Synchronisierung</div></div></div></section><div class="section-heading"><div><h2>Deine Rezeptlisten</h2><p>Gut sortiert. Schnell wiedergefunden.</p></div>${state.collections.length ? `<a class="text-link" href="#listen">Alle Listen ansehen${icon('arrow')}</a>` : ''}</div>${state.collections.length ? `<div class="collection-grid">${state.collections.slice(0, 6).map(collectionCard).join('')}</div><div class="section-heading"><div><h2>Ein Blick in deine Sammlung</h2><p>Vielleicht ist dein nächstes Lieblingsgericht schon dabei.</p></div><a class="text-link" href="#rezepte">Alle Rezepte${icon('arrow')}</a></div><div id="overview-recipes" class="recipe-grid"></div>` : emptyContent(state.status.connected ? 'Alles verbunden. Jetzt wird gesammelt.' : 'Deine Lieblingsgerichte ziehen ein.', state.status.connected ? (!state.status.sync.running && state.status.last_result?.message ? state.status.last_result.message : 'Beim ersten Laden holt Rezeptgarten deine gespeicherten Listen, Rezeptdetails und Bilder. Das kann bei einer großen Sammlung etwas dauern.') : 'Verbinde dein Cookidoo-Konto. Deine gespeicherten Rezeptlisten und Bilder werden anschließend in deiner lokalen Datenbank abgelegt.', !state.status.sync.running)}`;
    if (state.collections.length) {
      const result = await api('/api/recipes?limit=8');
      if (request === state.request && $('#overview-recipes')) $('#overview-recipes').innerHTML = result.items.map(recipeCard).join('');
    }
    return;
  }
  const collection = state.collections.find(item => item.id === state.collection);
  const title = state.query ? `Rezepte für „${state.query}“` : (collection?.name || 'Alle deine Rezepte');
  const description = collection ? collection.description || 'Alle Rezepte aus dieser Cookidoo-Rezeptliste.' : 'Deine gespeicherten Rezepte. Einmal gesammelt, überall griffbereit.';
  content.innerHTML = `<div class="page-title">${state.collection ? `<a class="back-link" href="#listen">${icon('back')}Zurück zu deinen Listen</a>` : `<span class="eyebrow">GUTE IDEEN FÜR DEINE KÜCHE</span>`}<h1>${escapeHTML(title)}</h1><p>${escapeHTML(description)}</p></div><div class="results-toolbar"><span id="result-count">Rezepte werden geladen …</span><label class="sr-only" for="sort">Rezepte sortieren</label><select id="sort" class="sort-select"><option value="name" ${state.sort === 'name' ? 'selected' : ''}>Name · A bis Z</option><option value="time" ${state.sort === 'time' ? 'selected' : ''}>Kürzeste Gesamtzeit</option></select></div><div id="recipe-grid" class="recipe-grid"></div><div id="recipe-empty"></div><button id="load-more" class="button load-more" hidden>Weitere Rezepte laden${icon('arrow')}</button>`;
  state.offset = 0;
  await loadRecipes(false, request);
}
async function loadRecipes(append = false, request = state.request) {
  const params = new URLSearchParams({q:state.query,sort:state.sort,offset:append ? state.offset : 0,limit:48});
  if (state.collection) params.set('collection', state.collection);
  const result = await api('/api/recipes?' + params);
  if (request !== state.request || !$('#recipe-grid')) return;
  state.offset = result.offset + result.items.length; state.total = result.total;
  $('#result-count').textContent = `${result.total} ${result.total === 1 ? 'Rezept' : 'Rezepte'}${state.query ? ' gefunden' : ' in deiner Sammlung'}`;
  if (!append) $('#recipe-grid').innerHTML = '';
  $('#recipe-grid').insertAdjacentHTML('beforeend', result.items.map(recipeCard).join(''));
  $('#recipe-empty').innerHTML = result.total ? '' : emptyContent(state.query ? 'Noch kein Treffer.' : 'Hier ist noch Platz für gute Ideen.', state.query ? 'Versuche einen anderen Rezeptnamen oder einen kürzeren Suchbegriff.' : 'Diese Liste enthält noch keine gespeicherten Rezepte.', false, true);
  $('#load-more').hidden = state.offset >= result.total;
}
function renderSettings() {
  const status = state.status, account = status.account;
  $('#content').innerHTML = `<div class="page-title"><span class="eyebrow">ALLES NACH DEINEM GESCHMACK</span><h1>Dein Rezeptgarten</h1><p>Verbindung, Synchronisierung und deine App auf dem Startbildschirm.</p></div><div class="settings-grid"><section class="settings-card"><span class="dialog-symbol">${icon('link')}</span><h2>Dein Cookidoo-Konto</h2>${status.connected ? `<p class="account-email">${escapeHTML(account?.email)}</p><p>Verbunden mit Cookidoo ${escapeHTML(({de:'Deutschland',at:'Österreich',ch:'Schweiz'})[account?.region] || '')}.</p><button class="button" data-action="connect">Konto neu verbinden</button><button class="text-link danger-link" data-action="disconnect">Verbindung trennen</button><p class="settings-small">Deine lokale Sammlung bleibt beim Trennen erhalten.</p>` : `<p>Verbinde dein Konto, um persönliche Rezeptlisten und gespeicherte Cookidoo-Kollektionen zu laden.</p><button class="button button-primary" data-action="connect">${icon('link')}Cookidoo verbinden</button>`}</section><section class="settings-card"><span class="dialog-symbol">${icon('sync')}</span><h2>Automatisch aktuell</h2><p>Rezeptgarten prüft deine Listen im Hintergrund, auch wenn die App geschlossen ist.</p><label for="sync-hours">Synchronisierung<select id="sync-hours"><option value="0" ${status.sync_hours === 0 ? 'selected' : ''}>Nur manuell</option><option value="1" ${status.sync_hours === 1 ? 'selected' : ''}>Jede Stunde</option><option value="6" ${status.sync_hours === 6 ? 'selected' : ''}>Alle 6 Stunden</option><option value="24" ${status.sync_hours === 24 ? 'selected' : ''}>Einmal täglich</option></select></label><p class="settings-small">Letzter erfolgreicher Abgleich: ${escapeHTML(formatDate(status.stats.last_sync))}</p>${status.last_result?.phase === 'error' ? `<p class="form-error">${escapeHTML(status.last_result.message)}</p>` : ''}</section><section class="settings-card"><span class="dialog-symbol">${icon('download')}</span><h2>Auch auf deinem Handy</h2><p>Installiere Rezeptgarten über Chrome und öffne deine Sammlung direkt vom Startbildschirm.</p><button class="button" data-action="install">${icon('download')}App installieren</button><button class="text-link" data-action="install-help">Installationshilfe</button><p class="settings-small">Die Verbindung zum eigenen Server im Heimnetz bleibt erforderlich.</p></section><section class="settings-card"><span class="dialog-symbol">${icon('book')}</span><h2>Deine Daten bleiben bei dir</h2><p>${status.stats.recipes} Rezepte und ${status.stats.images} lokal gespeicherte Bilder. Vor jedem erfolgreichen Abgleich wird die Datenbank gesichert.</p><a class="button" href="/api/export" download>${icon('download')}Sammlung als JSON exportieren</a><button class="text-link" data-action="logout">Von dieser App abmelden</button><p class="settings-small">Rezeptgarten übernimmt aktuell Listen und Rezeptdetails aus Cookidoo. Zutaten werden in einer späteren Ansicht ergänzt.</p></section></div>`;
}
async function openRecipe(id) {
  const recipe = await api('/api/recipes/' + encodeURIComponent(id));
  const time = duration(recipe.total_seconds), active = duration(recipe.active_seconds);
  $('#recipe-content').innerHTML = `<div class="recipe-detail-photo">${photo(recipe.image_file, recipe.name, true)}</div><div class="recipe-detail-body"><span class="eyebrow">AUS DEINER SAMMLUNG</span><h2 id="recipe-title">${escapeHTML(recipe.name)}</h2><div class="recipe-meta">${time ? `<span class="meta-chip">${icon('clock')}${time} gesamt</span>` : ''}${active ? `<span class="meta-chip">${active} Arbeitszeit</span>` : ''}</div><div class="detail-lists"><p>GESPEICHERT IN</p>${recipe.collections.map(c => `<a data-close-recipe href="#liste/${encodeURIComponent(c.id)}">${escapeHTML(c.name)}</a>`).join('')}</div><a class="button button-primary button-full" href="${escapeHTML(recipe.source_url)}" target="_blank" rel="noopener noreferrer">In Cookidoo öffnen${icon('external')}</a></div>`;
  $('#recipe-dialog').showModal();
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
  const action = event.target.closest('[data-action]');
  try {
    if (event.target.closest('[data-close-recipe]')) $('#recipe-dialog').close();
    if (recipe) await openRecipe(recipe.dataset.recipe);
    if (event.target.closest('.install-trigger')) await install();
    if (action) {
      switch (action.dataset.action) {
        case 'connect': errorMessage($('#connect-error'), ''); $('#cookidoo-email').value = state.status?.account?.email || ''; $('#connect-dialog').showModal(); break;
        case 'sync': await startSync(); break;
        case 'install': await install(); break;
        case 'install-help': $('#install-dialog').showModal(); break;
        case 'disconnect': await post('/api/disconnect'); await loadLibrary(); toast('Verbindung getrennt. Deine lokale Sammlung bleibt erhalten.'); break;
        case 'logout': await post('/api/auth/logout'); state.authenticated = false; state.status = null; state.collections = []; $('#content').innerHTML = ''; $('#search').value = ''; state.query = ''; showAuth(); break;
      }
    }
    if (event.target.closest('#load-more')) { $('#load-more').disabled = true; try { await loadRecipes(true); } finally { if ($('#load-more')) $('#load-more').disabled = false; } }
  } catch (error) { toast(error.message); }
});
$('#auth-dialog').addEventListener('cancel', event => event.preventDefault());
document.querySelectorAll('dialog:not(#auth-dialog)').forEach(dialog => dialog.addEventListener('click', event => {
  if (event.target === dialog) { const rect = dialog.getBoundingClientRect(); if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close(); }
}));
$('#auth-form').addEventListener('submit', async event => {
  event.preventDefault(); const button = $('#auth-submit'); button.disabled = true; errorMessage($('#auth-error'), '');
  try {
    const payload = {password:$('#app-password').value};
    if (!state.configured) payload.code = $('#setup-code').value.trim();
    await post(state.configured ? '/api/auth/login' : '/api/auth/setup', payload);
    state.authenticated = true; state.configured = true; setupCode = ''; $('#setup-code').value = ''; $('#app-password').value = '';
    $('#auth-dialog').close(); await loadLibrary();
  } catch (error) { errorMessage($('#auth-error'), error.message); }
  finally { button.disabled = false; }
});
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
document.addEventListener('change', async event => {
  try {
    if (event.target.id === 'sort') { state.sort = event.target.value; await renderRoute(); }
    if (event.target.id === 'sync-hours') { await post('/api/settings', {sync_hours:Number(event.target.value)}); state.status.sync_hours = Number(event.target.value); toast('Synchronisierungseinstellung gespeichert.'); }
  } catch (error) { toast(error.message); }
});
window.addEventListener('hashchange', () => {
  state.query = ''; $('#search').value = '';
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
setInterval(async () => {
  if (!state.authenticated || !state.status || polling || !navigator.onLine) return;
  polling = true;
  try {
    const previous = state.status;
    state.status = await api('/api/status'); updateSync();
    if ((previous.sync.running && !state.status.sync.running) || previous.stats.last_sync !== state.status.stats.last_sync) {
      await loadLibrary(); if (previous.sync.running) toast(state.status.sync.message);
    }
  } catch (_) { /* Keep the last visible collection when the server is temporarily unreachable. */ }
  finally { polling = false; }
}, 2500);
async function initialize() {
  try {
    const auth = await api('/api/auth/status'); state.configured = auth.configured; state.authenticated = auth.authenticated;
    if (!auth.authenticated) showAuth(); else await loadLibrary();
  } catch (error) { $('#content').innerHTML = emptyContent('Dein Rezeptgarten ist gerade nicht erreichbar.', error.message); }
  if ('serviceWorker' in navigator && window.isSecureContext) navigator.serviceWorker.register('/sw.js').catch(() => {});
}
initialize();
