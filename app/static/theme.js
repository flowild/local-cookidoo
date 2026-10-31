'use strict';
(() => {
  const root = document.documentElement;
  const key = 'rezeptgarten-accent';
  const fallback = '#234d3c';
  let selected = null;
  const cookieKey = 'rezeptgarten_accent';
  function cookieValue() {
    try { return document.cookie.split('; ').find(part => part.startsWith(cookieKey + '='))?.slice(cookieKey.length + 1) || null; }
    catch (_) { return null; }
  }
  function saveCookie(value) {
    try {
      document.cookie = `${cookieKey}=${value || ''}; Path=/; Max-Age=${value ? 31536000 : 0}; SameSite=Strict${location.protocol === 'https:' ? '; Secure' : ''}`;
      return cookieValue() === value;
    } catch (_) { return false; }
  }
  try { if (localStorage.getItem('rezeptgarten-theme') === 'dark') root.dataset.theme = 'dark'; } catch (_) {}
  let stored = cookieValue();
  if (!stored) { try { stored = localStorage.getItem(key); } catch (_) {} }
  if (/^#[0-9a-f]{6}$/i.test(stored || '')) selected = stored.toLowerCase();

  const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
  const hex = values => '#' + values.map(value => Math.round(value).toString(16).padStart(2, '0')).join('');
  const mix = (a, b, fraction) => a.map((value, i) => value * (1 - fraction) + b[i] * fraction);
  const luminance = values => values.map(value => {
    const c = value / 255;
    return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4;
  }).reduce((sum, value, i) => sum + value * [.2126, .7152, .0722][i], 0);
  const contrast = (a, b) => {
    const values = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (values[0] + .05) / (values[1] + .05);
  };
  const inkOn = background => contrast([0, 0, 0], background) >= contrast([255, 255, 255], background) ? '#000000' : '#ffffff';
  function apply() {
    if (!selected) {
      delete root.dataset.accent;
      for (const property of ['--accent-fill','--accent-on','--accent-hover','--accent-hover-on','--accent-text','--accent-soft']) root.style.removeProperty(property);
      return;
    }
    const dark = root.dataset.theme === 'dark';
    const fill = rgb(selected), surface = dark ? [36, 74, 76] : [233, 238, 223];
    const target = dark ? [255, 255, 255] : [0, 0, 0];
    let text = fill;
    for (let i = 0; i <= 100 && contrast(text, surface) < 4.5; i++) text = mix(fill, target, i / 100);
    const hover = mix(fill, dark ? [255, 255, 255] : [0, 0, 0], .12);
    const soft = mix(dark ? [27, 56, 58] : [255, 255, 255], fill, .14);
    root.dataset.accent = 'custom';
    root.style.setProperty('--accent-fill', selected);
    root.style.setProperty('--accent-on', inkOn(fill));
    root.style.setProperty('--accent-hover', hex(hover));
    root.style.setProperty('--accent-hover-on', inkOn(hover));
    root.style.setProperty('--accent-text', hex(text));
    root.style.setProperty('--accent-soft', hex(soft));
  }
  window.RezeptgartenAccent = {
    current: () => selected || (root.dataset.theme === 'dark' ? '#8fc9c5' : fallback),
    apply,
    set(value) {
      if (!/^#[0-9a-f]{6}$/i.test(value)) return false;
      selected = value.toLowerCase(); apply();
      try { localStorage.setItem(key, selected); saveCookie(null); return true; } catch (_) { return saveCookie(selected); }
    },
    reset() {
      selected = null; apply();
      try { localStorage.removeItem(key); return saveCookie(null); } catch (_) { return saveCookie('default'); }
    },
  };
  apply();
})();
