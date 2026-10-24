'use strict';

// C411 Books : les livres, BD, mangas et magazines du serveur dans le
// navigateur. Bibliothèque : /api/library (livres, séries, état) ; lecture :
// EPUB par epub.js et PDF par pdf.js sur /media/<livre> (plages Range), BD
// page par page (/page/<livre>/<n>), le reste à télécharger.

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));
const icon = {
  read: '<svg viewBox="0 0 24 24"><path d="M4 4.5h6a2.5 2.5 0 0 1 2.5 2.5v13A2 2 0 0 0 10.5 18H4Zm16 0h-6A2.5 2.5 0 0 0 11.5 7v13a2 2 0 0 1 2-2H20Z"/></svg>',
  download: '<svg viewBox="0 0 24 24"><path d="M11 4h2v9.2l3.6-3.6 1.4 1.4-6 6-6-6 1.4-1.4 3.6 3.6V4Zm-6 14h14v2H5v-2Z"/></svg>',
  minus: '<svg viewBox="0 0 24 24"><path d="M5 11h14v2H5z"/></svg>',
  plus: '<svg viewBox="0 0 24 24"><path d="M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6z"/></svg>',
};

const kinds = {
  book: { label: 'Livres', one: 'Livre' },
  comic: { label: 'BD', one: 'BD' },
  manga: { label: 'Mangas', one: 'Manga' },
  magazine: { label: 'Magazines', one: 'Magazine' },
};

const state = {
  books: [], series: [], byId: new Map(), seriesById: new Map(), seriesOf: new Map(),
  status: {}, sort: 'added', badges: true,
};

// ---------------------------------------------------------------------------
// Préférences et positions de lecture (dans ce navigateur)

const store = {
  get(key, fallback) {
    try { const v = JSON.parse(localStorage.getItem('c411books.' + key)); return v ?? fallback; } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem('c411books.' + key, JSON.stringify(value)); } catch { /* stockage indisponible */ }
  },
};
const progress = {
  get: (id) => store.get('pos.' + id, null),
  set: (id, pos, pct) => store.set('pos.' + id, { pos, pct, at: Date.now() }),
  /** Commencés et pas finis, du plus récent au plus ancien. */
  reading() {
    const out = [];
    for (const b of state.books) {
      const p = progress.get(b.id);
      if (p && p.pct > 0.005 && p.pct < 0.98) out.push({ book: b, ...p });
    }
    return out.sort((a, b) => b.at - a.at).map((x) => x.book);
  },
};

// ---------------------------------------------------------------------------
// Bibliothèque

async function load() {
  const res = await fetch('api/library');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  state.books = data.books;
  state.series = data.series;
  state.status = data.status || {};
  state.byId = new Map(data.books.map((b) => [b.id, b]));
  state.seriesById = new Map(data.series.map((s) => [s.id, s]));
  state.seriesOf = new Map();
  for (const s of data.series) for (const id of s.books) state.seriesOf.set(id, s);
  const recent = data.books.filter(isRecent);
  state.badges = recent.length <= Math.max(10, data.books.length * 0.2);
  await Promise.all([loadVotes(), loadFavorites()]);
  showStatus(state.status);
}

const addedOf = (b) => (b.added ? Date.parse(b.added) : 0);
const isRecent = (b) => Date.now() - addedOf(b) < 7 * 864e5;
const fold = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const plural = (n, word, many = word + 's') => `${n} ${n > 1 ? many : word}`;
const months = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
const fmtSize = (b) => {
  const u = ['o', 'Ko', 'Mo', 'Go'];
  let i = 0;
  while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
  return `${b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1).replace('.', ',')} ${u[i]}`;
};
const volumeText = (v) => (v == null ? '' : `T${Number.isInteger(v) ? v : String(v).replace('.', ',')}`);

/** Date lisible : « 6 juin 2025 », « juin 2025 », « 2012 ». */
function dateText(d) {
  if (!d) return '';
  const [y, m, day] = d.split('-').map(Number);
  if (!m) return String(y);
  return `${day ? day + ' ' : ''}${months[m - 1]} ${y}`;
}

/** Sous-titre d'un livre selon son genre. */
function subtitle(b) {
  if (b.kind === 'magazine') return [b.issue ? `n° ${b.issue}` : '', dateText(b.date)].filter(Boolean).join(' · ');
  if (b.kind === 'book') return [b.authors.join(', '), b.year].filter(Boolean).join(' · ');
  return [volumeText(b.volume), b.authors[0], b.year].filter(Boolean).join(' · ');
}

/** Couverture : la vraie si elle existe, sinon une couverture sobre avec
 * le titre et l'auteur, de couleur stable pour un livre donné. */
function cover(b, { badge = '', count = 0 } = {}) {
  let h = 0;
  for (const ch of b.id) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const hue = h % 360;
  const bg = `background: linear-gradient(160deg, hsl(${hue} 42% 34%), hsl(${(hue + 40) % 360} 48% 18%))`;
  const p = progress.get(b.id);
  return `<div class="cover" style="${bg}"><div class="plain"><strong>${esc(b.title)}</strong><span>${esc(b.authors?.[0] || (b.kind === 'magazine' ? dateText(b.date) : ''))}</span></div>${
    b.cover ? `<img src="api/cover/${b.id}" alt="" loading="lazy" onerror="this.remove()">` : ''}${
    badge ? `<span class="badge">${esc(badge)}</span>` : ''}${
    count > 1 ? `<span class="badge count">${count}</span>` : ''}${
    p && p.pct > 0.005 ? `<span class="progress"><i style="width:${Math.round(p.pct * 100)}%"></i></span>` : ''}</div>`;
}

function bookCard(b) {
  const badge = state.badges && isRecent(b) ? 'NOUVEAU' : '';
  return `<a class="card" href="#b=${b.id}" title="${esc(b.title)}">${cover(b, { badge })}${voteBadge(b.id)}
    <div class="card-title">${esc(b.kind === 'book' || !b.series ? b.title : (b.kind === 'magazine' ? b.series : `${b.series} ${volumeText(b.volume)}`))}</div>
    <div class="card-sub">${esc(subtitle(b))}</div></a>`;
}

/** Carte d'une série : la couverture du dernier paru (magazine) ou du
 * premier tome (BD). */
function seriesCard(s) {
  const books = s.books.map((id) => state.byId.get(id)).filter(Boolean);
  const face = s.kind === 'magazine' ? books[books.length - 1] : books.find((b) => b.cover) || books[0];
  const recent = books.some(isRecent) && state.badges;
  return `<a class="card" href="#s=${s.id}" title="${esc(s.name)}">${cover(face, { badge: recent ? 'NOUVEAU' : '', count: books.length })}
    <div class="card-title">${esc(s.name)}</div>
    <div class="card-sub">${esc(s.kind === 'magazine' ? (dateText(face.date) || plural(books.length, 'numéro')) : plural(books.length, 'tome'))}</div></a>`;
}

/** Ce qu'on montre d'un genre : les séries (BD, mangas, magazines), puis
 * les livres sans série. */
function entriesOf(kind) {
  const books = state.books.filter((b) => b.kind === kind);
  if (kind === 'book') return books.map((b) => ({ book: b, added: addedOf(b), title: b.title, year: b.year, author: b.authors[0] }));
  const series = state.series.filter((s) => s.kind === kind);
  const inSeries = new Set(series.flatMap((s) => s.books));
  return [
    ...series.map((s) => {
      const list = s.books.map((id) => state.byId.get(id)).filter(Boolean);
      return {
        series: s, title: s.name, author: list[0]?.authors[0],
        added: Math.max(...list.map(addedOf)), year: Math.max(...list.map((b) => b.year || 0)),
        date: list.map((b) => b.date || '').sort().pop(),
      };
    }),
    ...books.filter((b) => !inSeries.has(b.id)).map((b) => ({ book: b, added: addedOf(b), title: b.title, year: b.year, author: b.authors[0], date: b.date })),
  ];
}
const entryCard = (e) => (e.series ? seriesCard(e.series) : bookCard(e.book));

function row(title, items, render, link) {
  if (!items.length) return '';
  return `<section class="row"><div class="row-head"><h2>${esc(title)}</h2>${link ? `<a href="${link}">Tout afficher</a>` : ''}</div>
    <div class="strip">${items.map(render).join('')}</div></section>`;
}

// ---------------------------------------------------------------------------
// Votes des membres : j'aime / je n'aime pas, anonymes (api/votes, voir
// c411_core/votes.dart). Le membre est celui de la connexion vache.cloud,
// transmis par le proxy ; sans connexion, on voit les totaux sans voter.

const thumbs = {
  up: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2 21h4V9H2v12Zm20-11a2 2 0 0 0-2-2h-6.3l.95-4.57.03-.32a1.5 1.5 0 0 0-.44-1.06L13.17 1 6.59 7.59A1.98 1.98 0 0 0 6 9v10a2 2 0 0 0 2 2h9c.83 0 1.54-.5 1.84-1.22l3.02-7.05c.09-.23.14-.47.14-.73v-2Z"/></svg>',
  down: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 3h-4v12h4V3ZM2 14a2 2 0 0 0 2 2h6.3l-.95 4.57-.03.32c0 .41.17.79.44 1.06L10.83 23l6.58-6.59c.37-.36.59-.86.59-1.41V5a2 2 0 0 0-2-2H7c-.83 0-1.54.5-1.84 1.22l-3.02 7.05c-.09.23-.14.47-.14.73v2Z"/></svg>',
};
const votes = { user: false, items: new Map() };

async function loadVotes() {
  try {
    const res = await fetch('api/votes');
    if (!res.ok) return;
    const data = await res.json();
    votes.user = Boolean(data.user);
    votes.items = new Map(Object.entries(data.items || {}));
  } catch { /* serveur sans votes : rien à afficher */ }
}

/** [pour, contre, mon vote] ; score = pour − contre. */
const tallyOf = (id) => votes.items.get(id) || [0, 0, 0];
const scoreOf = (id) => { const [up, down] = tallyOf(id); return up - down; };
/** Tri « préférés des membres » : score, puis nombre de « j'aime ». */
const byVotes = (a, b) => scoreOf(b) - scoreOf(a) || tallyOf(b)[0] - tallyOf(a)[0];
/** Éléments au score positif, du mieux voté au moins bien. */
const liked = (items, idOf = (x) => x.id) => items.filter((x) => scoreOf(idOf(x)) > 0)
  .sort((a, b) => byVotes(idOf(a), idOf(b)));

/** Boutons j'aime / je n'aime pas ; recliquer retire son vote. */
function voteBar(id) {
  const [up, down, mine] = tallyOf(id);
  const off = votes.user ? '' : ' disabled';
  const hint = votes.user ? '' : ' — connecte-toi par vache.cloud pour voter';
  const button = (value, label, count) => `<button class="vote-btn${value < 0 ? ' down' : ''}${mine === value ? ' on' : ''}" data-vote="${value}"
    aria-pressed="${mine === value}" title="${label}${mine === value ? ' (cliquer pour retirer)' : ''}${hint}"${off}>${value > 0 ? thumbs.up : thumbs.down}<span>${count}</span></button>`;
  return `<div class="votes" data-votes="${esc(id)}">${button(1, 'J’aime', up)}${button(-1, 'Je n’aime pas', down)}<span class="votes-note">votes anonymes · 👍 ajoute à tes favoris</span></div>`;
}

/** Pastille du score sur une vignette (vide sans vote). */
function voteBadge(id) {
  const [up, down] = tallyOf(id);
  const s = up - down;
  const inner = up || down ? `${s < 0 ? thumbs.down : thumbs.up}${s > 0 ? '+' : ''}${s}` : '';
  return `<span class="vote-badge${s < 0 ? ' neg' : ''}${inner ? '' : ' empty'}" data-badge="${esc(id)}" title="${up} j’aime · ${down} je n’aime pas">${inner}</span>`;
}

document.addEventListener('click', async (e) => {
  const button = e.target.closest('[data-vote]');
  if (!button) return;
  // Avant les autres clics : le bouton peut être dans une carte ou un lien.
  e.preventDefault();
  e.stopPropagation();
  const id = button.closest('[data-votes]').dataset.votes;
  const wanted = Number(button.dataset.vote);
  const value = tallyOf(id)[2] === wanted ? 0 : wanted;
  try {
    const res = await fetch(`api/vote/${encodeURIComponent(id)}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ value }),
    });
    if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`);
    votes.items.set(id, await res.json());
    // Aimer, c'est mettre dans ses favoris (en tête) ; sinon, il en sort.
    favorites.ids = [...(value === 1 ? [id] : []), ...favorites.ids.filter((x) => x !== id)];
  } catch (err) {
    (typeof toast === 'function' ? toast : alert)(`Vote impossible : ${err.message}`);
    return;
  }
  for (const el of document.querySelectorAll(`[data-votes="${CSS.escape(id)}"]`)) el.outerHTML = voteBar(id);
  for (const el of document.querySelectorAll(`[data-badge="${CSS.escape(id)}"]`)) el.outerHTML = voteBadge(id);
  if (typeof onFavoritesChange === 'function') onFavoritesChange();
}, { capture: true });

/** Score d'une entrée de liste : le livre, ou la somme des tomes d'une série. */
const entryScore = (e) => (e.book ? scoreOf(e.book.id) : e.series.books.reduce((n, id) => n + scoreOf(id), 0));

// ---------------------------------------------------------------------------
// Favoris : ce que le membre a aimé (👍), du plus récent au plus ancien.
// Gardés sur le serveur (api/favorites), donc les mêmes sur tous ses
// appareils ; sans connexion vache.cloud, pas de favoris (lien masqué).

const favorites = { user: false, ids: [] };

async function loadFavorites() {
  try {
    const res = await fetch('api/favorites');
    if (!res.ok) return;
    const data = await res.json();
    favorites.user = Boolean(data.user);
    favorites.ids = data.items || [];
  } catch { /* serveur sans favoris */ }
  for (const el of document.querySelectorAll('[data-favorites-only]')) el.hidden = !favorites.user;
}

/** Favori ajouté ou retiré : la page « Favoris » suit. */
function onFavoritesChange() {
  if (decodeURIComponent(location.hash) === '#favoris') renderFavorites();
}

// ---------------------------------------------------------------------------
// Vues

const content = $('#content');
const statusLine = $('#status');

function setNav(view) {
  for (const a of document.querySelectorAll('.nav a')) a.classList.toggle('active', a.dataset.view === view);
}

function renderHome() {
  setNav('home');
  if (!state.books.length) {
    content.innerHTML = '';
    statusLine.textContent = 'Aucun livre pour l’instant. Les livres viennent du parcours de la vidéothèque '
      + 'de l’application (Films & séries › Actualiser) : torrents terminés et dossiers à parcourir.';
    return;
  }
  statusLine.textContent = '';
  const reading = progress.reading();
  const byAdded = [...state.books].sort((a, b) => addedOf(b) - addedOf(a));
  const featured = reading[0] || byAdded.find((b) => b.cover && b.description) || byAdded.find((b) => b.cover) || byAdded[0];
  const kindRow = (kind) => {
    const entries = entriesOf(kind).sort((a, b) => b.added - a.added).slice(0, 24);
    return row(kinds[kind].label, entries, entryCard, `#${kind}`);
  };
  content.innerHTML = bookHero(featured, reading[0] ? 'Reprendre la lecture' : 'À la une', { home: true }) +
    row('Continuer la lecture', reading.slice(0, 20), bookCard) +
    row('Mes favoris', favorites.ids.map((id) => state.byId.get(id)).filter(Boolean).slice(0, 24), bookCard, '#favoris') +
    row('Ajoutés récemment', byAdded.slice(0, 24), bookCard) +
    row('Préférés des membres', liked(state.books).slice(0, 24), bookCard) +
    ['book', 'comic', 'manga', 'magazine'].map(kindRow).join('');
}

/** Bandeau d'un livre ; [home] : à l'accueil, avec un lien vers la fiche. */
function bookHero(b, eyebrow, { home = false } = {}) {
  const s = state.seriesOf.get(b.id);
  const p = progress.get(b.id);
  const started = p && p.pct > 0.005 && p.pct < 0.98;
  const meta = [
    b.authors.length ? esc(b.authors.join(', ')) : '',
    s ? `<a href="#s=${s.id}">${esc(s.name)}</a>${b.volume != null && b.kind !== 'magazine' ? ' ' + volumeText(b.volume) : ''}` : '',
    b.kind === 'magazine' ? [b.issue ? `n° ${b.issue}` : '', dateText(b.date)].filter(Boolean).join(' · ') : (b.year || ''),
  ].filter(Boolean).join(' · ');
  const facts = [
    `<span class="fmt">${esc(b.format)}</span>`, fmtSize(b.size),
    b.pages ? plural(b.pages, 'page') : '', b.publisher ? esc(b.publisher) : '',
    b.language ? esc(b.language) : '',
  ].filter(Boolean).join(' · ');
  return `<section class="hero">${b.cover ? `<div class="hero-bg" style="background-image:url('api/cover/${b.id}')"></div>` : ''}
    ${cover(b)}
    <div class="hero-text"><div class="eyebrow">${esc(eyebrow)}</div><h1>${esc(b.title)}</h1><div class="meta">${meta}</div>
      ${b.subjects?.length ? `<div class="chips">${b.subjects.slice(0, 6).map((g) => `<span class="chip">${esc(g)}</span>`).join('')}</div>` : ''}
      ${b.description ? `<p class="summary">${esc(b.description)}</p>${b.description.length > 320 ? '<button class="more" data-more>Lire la suite</button>' : ''}` : ''}
      <div class="actions">
        ${b.reader ? `<a class="btn primary" href="#read=${b.id}">${icon.read}${started ? `Reprendre (${Math.round(p.pct * 100)} %)` : 'Lire'}</a>` : ''}
        <a class="btn${b.reader ? '' : ' primary'}" href="media/${b.id}?download=1">${icon.download}Télécharger</a>
        ${home ? `<a class="btn" href="#b=${b.id}">Voir la fiche</a>` : ''}
      </div>
      <div class="facts">${facts}${b.reader ? '' : ' · à lire dans une liseuse (Calibre…)'}</div></div></section>`;
}

const sorts = {
  added: ['Ajout récent', (a, b) => b.added - a.added],
  title: ['Titre', (a, b) => fold(a.title).localeCompare(fold(b.title), 'fr', { numeric: true })],
  author: ['Auteur', (a, b) => fold(a.author).localeCompare(fold(b.author)) || fold(a.title).localeCompare(fold(b.title))],
  year: ['Parution', (a, b) => (b.date || String(b.year || '')).localeCompare(a.date || String(a.year || ''))],
  votes: ['Préférés des membres', (a, b) => entryScore(b) - entryScore(a)],
};

function renderKind(kind) {
  setNav(kind);
  statusLine.textContent = '';
  const entries = entriesOf(kind).sort(sorts[state.sort][1]);
  const count = state.books.filter((b) => b.kind === kind).length;
  content.innerHTML = `<div class="page-head"><h1>${kinds[kind].label}</h1><span class="count">${
    kind === 'book' ? plural(count, 'livre') : `${plural(entries.length, 'série')} · ${plural(count, kind === 'magazine' ? 'numéro' : 'tome')}`}</span>
      <select id="sort" aria-label="Trier">${Object.entries(sorts).map(([k, [label]]) => `<option value="${k}"${k === state.sort ? ' selected' : ''}>${label}</option>`).join('')}</select></div>
    <div class="grid">${entries.map(entryCard).join('')}</div>`;
  if (!entries.length) statusLine.textContent = `Aucun élément dans « ${kinds[kind].label} ».`;
  $('#sort').addEventListener('change', (e) => { state.sort = e.target.value; store.set('sort', state.sort); renderKind(kind); });
}

function renderFavorites() {
  setNav('favoris');
  const list = favorites.ids.map((id) => state.byId.get(id)).filter(Boolean);
  statusLine.textContent = list.length ? '' : 'Aucun favori pour l’instant : ce que tu aimes (👍 sur la fiche d’un livre) arrive ici. '
    + 'Les favoris te suivent sur tous tes appareils.';
  content.innerHTML = `<div class="page-head"><h1>Mes favoris</h1><span class="count">${list.length}</span></div>
    <div class="grid">${list.map(bookCard).join('')}</div>`;
}

function renderSeries(id) {
  const s = state.seriesById.get(id);
  if (!s) return notFound();
  setNav(s.kind);
  statusLine.textContent = '';
  let books = s.books.map((x) => state.byId.get(x)).filter(Boolean);
  // Magazines : le plus récent d'abord.
  if (s.kind === 'magazine') books = [...books].reverse();
  const authors = [...new Set(books.flatMap((b) => b.authors))].slice(0, 4);
  content.innerHTML = `<div class="page-head"><h1>${esc(s.name)}</h1><span class="count">${kinds[s.kind].one} · ${
    plural(books.length, s.kind === 'magazine' ? 'numéro' : 'tome')}${authors.length ? ' · ' + esc(authors.join(', ')) : ''}</span></div>
    <div class="grid">${books.map(bookCard).join('')}</div>`;
}

function renderBook(id) {
  const b = state.byId.get(id);
  if (!b) return notFound();
  setNav(b.kind);
  statusLine.textContent = '';
  const s = state.seriesOf.get(b.id);
  let more = '';
  if (s) {
    const others = s.books.filter((x) => x !== b.id).map((x) => state.byId.get(x)).filter(Boolean);
    more = row(`${s.kind === 'magazine' ? 'Autres numéros' : 'Dans la même série'} : ${s.name}`, s.kind === 'magazine' ? others.reverse() : others, bookCard, `#s=${s.id}`);
  }
  const sourceName = { google: 'Google Books', hardcover: 'Hardcover', bnf: 'BnF',
    wikidata: /wikipedia\.org/.test(b.link || '') ? 'Wikipédia' : 'Wikidata' }[b.source] || 'Open Library';
  const link = b.link ? `Fiche <a href="${esc(b.link)}" target="_blank" rel="noopener">${sourceName}</a>. ` : '';
  content.innerHTML = bookHero(b, kinds[b.kind].one).replace('<div class="facts">', `${voteBar(b.id)}<div class="facts">`) + more +
    `<p class="facts" style="padding: 0 var(--gutter)">${link}${b.kind === 'book' ? '<button class="link-btn" data-identify="' + b.id + '">Chercher à nouveau en ligne</button>' : ''}</p>`;
}

function renderSearch(query) {
  setNav('');
  const q = fold(query.trim());
  const books = state.books.filter((b) => fold(`${b.title} ${b.authors.join(' ')} ${b.series || ''}`).includes(q));
  const series = state.series.filter((s) => fold(s.name).includes(q));
  statusLine.textContent = books.length + series.length ? '' : `Rien pour « ${query} ».`;
  content.innerHTML = (series.length ? `<div class="page-head"><h1>Séries</h1></div><div class="grid">${series.slice(0, 24).map(seriesCard).join('')}</div>` : '') +
    (books.length ? `<div class="page-head"><h1>Livres</h1><span class="count">${books.length}</span></div><div class="grid">${books.slice(0, 120).map(bookCard).join('')}</div>` : '');
}

function notFound() {
  content.innerHTML = '';
  statusLine.textContent = 'Introuvable : la bibliothèque a peut-être changé.';
}

/** Routes : #book, #comic, #manga, #magazine, #b=<livre>, #s=<série>,
 * #read=<livre> (liseuse, par-dessus la fiche). */
function route() {
  const hash = decodeURIComponent(location.hash.slice(1));
  const query = $('#search').value.trim();
  const params = new URLSearchParams(hash.includes('=') ? hash : '');
  if (params.has('read')) {
    const b = state.byId.get(params.get('read'));
    if (b && !content.innerHTML) renderBook(b.id);
    if (b) openReader(b);
    return;
  }
  closeReader();
  if (query && !hash) return renderSearch(query);
  if (params.has('b')) renderBook(params.get('b'));
  else if (params.has('s')) renderSeries(params.get('s'));
  else if (hash === 'favoris') renderFavorites();
  else if (kinds[hash]) renderKind(hash);
  else renderHome();
  window.scrollTo({ top: 0 });
}

// ---------------------------------------------------------------------------
// Liseuse

const reader = {
  el: $('#reader'), stage: $('#reader-stage'), tools: $('#reader-tools'), seek: $('#reader-seek'),
  book: null, impl: null,
};

function loadScript(src) {
  return new Promise((resolve, reject) => {
    if (document.querySelector(`script[src="${src}"]`)) return resolve();
    const s = document.createElement('script');
    s.src = src;
    s.onload = resolve;
    s.onerror = () => reject(new Error(`${src} introuvable`));
    document.head.appendChild(s);
  });
}

function readerBusy(on) { $('#reader-spinner').hidden = !on; }
function readerError(text) {
  readerBusy(false);
  const el = $('#reader-error');
  el.textContent = text;
  el.hidden = !text;
}
function setPosition(text, ratio) {
  $('#reader-pos').textContent = text;
  if (!reader.seeking) {
    reader.seek.value = Math.round(ratio * 1000);
    reader.seek.style.setProperty('--pos', `${ratio * 100}%`);
  }
}

async function openReader(b) {
  if (reader.book?.id === b.id && !reader.el.hidden) return;
  closeReader();
  reader.book = b;
  reader.el.hidden = false;
  reader.el.classList.remove('light');
  document.body.classList.add('locked');
  $('#reader-title').textContent = b.title;
  $('#reader-sub').textContent = subtitle(b);
  reader.stage.innerHTML = '';
  reader.stage.className = 'reader-stage';
  reader.tools.innerHTML = '';
  readerError('');
  readerBusy(true);
  const impl = { epub: epubReader, pdf: pdfReader, comic: comicReader }[b.reader];
  if (!impl) return readerError('Ce format se lit dans une liseuse : télécharge-le.');
  try {
    reader.impl = await impl(b);
  } catch (e) {
    readerError(`Lecture impossible : ${e.message || e}`);
  }
}

function closeReader() {
  if (reader.el.hidden) return;
  reader.stage.onclick = null;
  try { reader.impl?.close?.(); } catch { /* déjà fermé */ }
  reader.impl = null;
  reader.book = null;
  reader.el.hidden = true;
  reader.stage.innerHTML = '';
  document.body.classList.remove('locked');
}

/** Ferme la liseuse : retour à la fiche du livre. */
function leaveReader() {
  const id = reader.book?.id;
  if (id && location.hash.startsWith('#read=')) location.replace(`#b=${id}`);
  else closeReader();
}

$('#reader-close').addEventListener('click', leaveReader);
$('#reader-prev').addEventListener('click', () => reader.impl?.prev());
$('#reader-next').addEventListener('click', () => reader.impl?.next());
reader.seek.addEventListener('input', () => {
  reader.seeking = true;
  reader.seek.style.setProperty('--pos', `${reader.seek.value / 10}%`);
  reader.impl?.preview?.(reader.seek.value / 1000);
});
reader.seek.addEventListener('change', () => {
  reader.seeking = false;
  reader.impl?.seek(reader.seek.value / 1000);
});

function toolButton(label, title, onClick, { on = false, html = false } = {}) {
  const b = document.createElement('button');
  b.className = html ? 'icon-btn' : 'text-btn';
  if (on) b.classList.add('on');
  b.title = title;
  b.innerHTML = html ? label : esc(label);
  b.addEventListener('click', () => { onClick(b); });
  reader.tools.appendChild(b);
  return b;
}

/** Préférences de lecture par genre (sens, page double, ajustement). */
const readPrefs = (b) => store.get('read.' + b.kind, {
  fit: 'height', double: b.kind === 'magazine' || b.kind === 'comic', rtl: Boolean(b.rtl),
});
const saveReadPrefs = (b, p) => store.set('read.' + b.kind, p);

/** Pages d'images (BD) ou de PDF : simple ou double page (la couverture
 * seule), ajustée à la hauteur ou à la largeur, de droite à gauche au
 * besoin. [draw] place les pages données dans la double page. */
function pagedReader(b, count, draw, { start = 0, rtlOption = true } = {}) {
  const prefs = readPrefs(b);
  let page = Math.min(start, count - 1);
  const spreadOf = (p) => (prefs.double && p > 0 && p + 1 < count ? [p, p + 1] : [p]);
  // En double page, les paires commencent après la couverture (1-2, 3-4…).
  const align = (p) => (prefs.double && p > 0 && p % 2 === 0 ? p - 1 : p);
  const step = () => spreadOf(page).length;

  async function show() {
    page = Math.max(0, Math.min(align(page), count - 1));
    reader.stage.className = `reader-stage fit-${prefs.fit}`;
    const pages = spreadOf(page);
    await draw(pages, prefs);
    const last = pages[pages.length - 1];
    setPosition(`${pages.map((p) => p + 1).join('-')} / ${count}`, count > 1 ? page / (count - 1) : 1);
    progress.set(b.id, page, (last + 1) / count);
    reader.stage.scrollTop = 0;
  }
  const api = {
    next() { if (page + step() < count) { page += step(); show(); } },
    prev() { if (page > 0) { page = Math.max(0, page - (prefs.double && page > 1 ? 2 : 1)); show(); } },
    seek(r) { page = Math.round(r * (count - 1)); show(); },
    preview(r) { $('#reader-pos').textContent = `${Math.round(r * (count - 1)) + 1} / ${count}`; },
    left() { prefs.rtl ? api.next() : api.prev(); },
    right() { prefs.rtl ? api.prev() : api.next(); },
    show,
  };
  toolButton('Double page', 'Une ou deux pages (D)', (btn) => { prefs.double = !prefs.double; btn.classList.toggle('on', prefs.double); saveReadPrefs(b, prefs); show(); }, { on: prefs.double }).dataset.key = 'd';
  toolButton(prefs.fit === 'height' ? 'Hauteur' : 'Largeur', 'Ajuster à la hauteur ou à la largeur (F)', (btn) => {
    prefs.fit = prefs.fit === 'height' ? 'width' : 'height';
    btn.textContent = prefs.fit === 'height' ? 'Hauteur' : 'Largeur';
    saveReadPrefs(b, prefs); show();
  }).dataset.key = 'f';
  if (rtlOption) {
    toolButton('Droite → gauche', 'Sens de lecture des mangas (R)', (btn) => { prefs.rtl = !prefs.rtl; btn.classList.toggle('on', prefs.rtl); saveReadPrefs(b, prefs); show(); }, { on: prefs.rtl }).dataset.key = 'r';
  }
  // Zones de clic : un tiers à gauche, un tiers à droite.
  reader.stage.onclick = (e) => {
    const x = e.clientX / reader.stage.clientWidth;
    if (x < 0.33) api.left(); else if (x > 0.67) api.right();
  };
  api.prefs = prefs;
  return api;
}

async function comicReader(b) {
  const res = await fetch(`api/pages/${b.id}`);
  const data = await res.json();
  if (!res.ok || data.error) throw new Error(data.error || `HTTP ${res.status}`);
  const count = data.count;
  if (!count) throw new Error('aucune page');
  const saved = progress.get(b.id);
  const url = (p) => `page/${b.id}/${p}`;
  const api = pagedReader(b, count, async (pages, prefs) => {
    readerBusy(true);
    const spread = document.createElement('div');
    spread.className = `spread${pages.length > 1 ? ' double' : ''}${prefs.rtl ? ' rtl' : ''}`;
    await Promise.all(pages.map((p) => new Promise((resolve) => {
      const img = new Image();
      img.alt = `Page ${p + 1}`;
      img.onload = img.onerror = resolve;
      img.src = url(p);
      spread.appendChild(img);
    })));
    reader.stage.querySelector('.spread')?.remove();
    reader.stage.appendChild(spread);
    readerBusy(false);
    // Les pages suivantes, d'avance.
    for (let p = pages[pages.length - 1] + 1; p < Math.min(count, pages[0] + 6); p++) new Image().src = url(p);
  }, { start: saved?.pos ?? 0 });
  await api.show();
  return api;
}

async function pdfReader(b) {
  await loadScript('vendor/pdf.min.js');
  const lib = window.pdfjsLib;
  lib.GlobalWorkerOptions.workerSrc = 'vendor/pdf.worker.min.js';
  // Par plages de 1 Mo : un magazine de 80 Mo s'ouvre sans tout télécharger.
  const task = lib.getDocument({ url: `media/${b.id}`, rangeChunkSize: 1 << 20, disableAutoFetch: true, disableStream: true });
  const doc = await task.promise;
  const saved = progress.get(b.id);
  let rendering = [];
  const api = pagedReader(b, doc.numPages, async (pages, prefs) => {
    readerBusy(true);
    for (const r of rendering) r.cancel();
    rendering = [];
    const spread = document.createElement('div');
    spread.className = `spread${pages.length > 1 ? ' double' : ''}${prefs.rtl ? ' rtl' : ''}`;
    const width = reader.stage.clientWidth / pages.length, height = reader.stage.clientHeight;
    const ratio = window.devicePixelRatio || 1;
    // Toiles créées dans l'ordre des pages, dessinées ensuite.
    const canvases = pages.map(() => spread.appendChild(document.createElement('canvas')));
    await Promise.all(pages.map(async (n, i) => {
      const page = await doc.getPage(n + 1);
      const base = page.getViewport({ scale: 1 });
      const scale = prefs.fit === 'height'
        ? Math.min(height / base.height, width / base.width)
        : Math.min(1100 / pages.length, width) / base.width;
      const viewport = page.getViewport({ scale: scale * ratio });
      const canvas = canvases[i];
      canvas.width = Math.floor(viewport.width);
      canvas.height = Math.floor(viewport.height);
      canvas.style.width = `${Math.floor(viewport.width / ratio)}px`;
      canvas.style.height = `${Math.floor(viewport.height / ratio)}px`;
      const task = page.render({ canvasContext: canvas.getContext('2d'), viewport });
      rendering.push(task);
      try { await task.promise; } catch { /* rendu annulé (page suivante) */ }
    }));
    reader.stage.querySelector('.spread')?.remove();
    reader.stage.appendChild(spread);
    readerBusy(false);
  }, { start: saved?.pos ?? 0, rtlOption: false });
  await api.show();
  let resize;
  const onResize = () => { clearTimeout(resize); resize = setTimeout(() => api.show(), 200); };
  window.addEventListener('resize', onResize);
  api.close = () => { window.removeEventListener('resize', onResize); doc.destroy(); };
  return api;
}

async function epubReader(b) {
  await loadScript('vendor/jszip.min.js');
  await loadScript('vendor/epub.min.js');
  const prefs = store.get('read.epub', { theme: 'dark', size: 100 });
  const host = document.createElement('div');
  host.className = 'epub-host';
  reader.stage.appendChild(host);
  const book = window.ePub(`media/${b.id}`, { openAs: 'epub' });
  const rendition = book.renderTo(host, { width: '100%', height: '100%', flow: 'paginated', spread: 'auto', allowScriptedContent: false });
  const themes = {
    dark: { body: { background: '#050b0e !important', color: '#e3ece9 !important' }, a: { color: '#f06595 !important' } },
    sepia: { body: { background: '#f3e9d6 !important', color: '#3a2f22 !important' } },
    light: { body: { background: '#f7f5f0 !important', color: '#1b1b1b !important' } },
  };
  for (const [name, css] of Object.entries(themes)) rendition.themes.register(name, css);
  const applyTheme = () => {
    rendition.themes.select(prefs.theme);
    reader.el.classList.toggle('light', prefs.theme !== 'dark');
    reader.stage.style.background = themes[prefs.theme].body.background.replace(' !important', '');
    rendition.themes.fontSize(`${prefs.size}%`);
    store.set('read.epub', prefs);
  };
  applyTheme();
  const saved = progress.get(b.id);
  let located = false;
  rendition.on('relocated', (loc) => {
    located = true;
    readerBusy(false);
    const pct = book.locations.length() ? book.locations.percentageFromCfi(loc.start.cfi) : (saved?.pct ?? 0);
    const page = loc.start.displayed;
    setPosition(book.locations.length() ? `${Math.round(pct * 100)} %` : `${page.page} / ${page.total}`, pct);
    progress.set(b.id, loc.start.cfi, Math.max(pct, 0.006));
  });
  const keys = (e) => {
    if (e.key === 'ArrowRight' || e.key === ' ' || e.key === 'PageDown') rendition.next();
    else if (e.key === 'ArrowLeft' || e.key === 'PageUp') rendition.prev();
    else if (e.key === 'Escape') leaveReader();
  };
  rendition.on('keyup', keys);
  await rendition.display(saved?.pos || undefined);
  if (!located) readerBusy(false);

  toolButton(icon.minus, 'Texte plus petit', () => { prefs.size = Math.max(70, prefs.size - 10); applyTheme(); }, { html: true });
  toolButton(icon.plus, 'Texte plus grand', () => { prefs.size = Math.min(200, prefs.size + 10); applyTheme(); }, { html: true });
  const themeBtn = toolButton({ dark: 'Sombre', sepia: 'Sépia', light: 'Clair' }[prefs.theme], 'Thème', () => {
    prefs.theme = { dark: 'sepia', sepia: 'light', light: 'dark' }[prefs.theme];
    themeBtn.textContent = { dark: 'Sombre', sepia: 'Sépia', light: 'Clair' }[prefs.theme];
    applyTheme();
  });
  book.loaded.navigation.then((nav) => {
    const flat = [];
    const walk = (items, depth) => { for (const i of items) { flat.push([i.href, ' '.repeat(depth * 2) + i.label.trim()]); walk(i.subitems || [], depth + 1); } };
    walk(nav.toc, 0);
    if (!flat.length) return;
    const select = document.createElement('select');
    select.title = 'Table des matières';
    select.innerHTML = `<option value="">Chapitres</option>${flat.map(([href, label]) => `<option value="${esc(href)}">${esc(label)}</option>`).join('')}`;
    select.addEventListener('change', () => { if (select.value) rendition.display(select.value); select.value = ''; });
    reader.tools.prepend(select);
  });
  // Positions en pourcentage : calculées une fois le livre chargé.
  book.ready.then(() => book.locations.generate(1200)).then(() => {
    const loc = rendition.currentLocation();
    if (loc?.start) rendition.emit('relocated', loc);
  }).catch(() => { /* pourcentage indisponible */ });
  return {
    next: () => rendition.next(),
    prev: () => rendition.prev(),
    left: () => rendition.prev(),
    right: () => rendition.next(),
    seek(r) { if (book.locations.length()) rendition.display(book.locations.cfiFromPercentage(r)); },
    preview(r) { $('#reader-pos').textContent = `${Math.round(r * 100)} %`; },
    close() { book.destroy(); },
  };
}

document.addEventListener('keydown', (e) => {
  if (reader.el.hidden) return;
  if (e.target.matches('input, select') && e.key !== 'Escape') return;
  const impl = reader.impl;
  switch (e.key) {
    case 'Escape': leaveReader(); break;
    case 'ArrowRight': e.preventDefault(); impl?.right?.(); break;
    case 'ArrowLeft': e.preventDefault(); impl?.left?.(); break;
    case ' ': case 'PageDown': e.preventDefault(); impl?.next(); break;
    case 'PageUp': e.preventDefault(); impl?.prev(); break;
    default: {
      const btn = reader.tools.querySelector(`[data-key="${e.key.toLowerCase()}"]`);
      if (btn) btn.click();
    }
  }
});

// ---------------------------------------------------------------------------
// État de la bibliothèque

function statusText(s) {
  return [
    s.step || `${s.books ?? 0} livres, dont ${s.online ?? 0} avec une fiche ${[s.google && 'Google Books', s.hardcover && 'Hardcover', 'Open Library', 'BnF', 'Wikidata'].filter(Boolean).join(', ')}.`,
    s.hardcover ? `Hardcover : ${s.hardcoverUsed ?? 0} requêtes sur ${s.hardcoverBudget ?? 4500} aujourd’hui${s.hardcoverProblem ? ` — ${s.hardcoverProblem}` : ''}.` : '',
    s.scannedAt ? `Dernier parcours de l’application : ${new Date(s.scannedAt).toLocaleString('fr-FR')}.` : 'Pas encore de parcours dans l’application.',
    s.error || '',
  ].filter(Boolean).join('\n');
}

let polling = null;
function showStatus(s) {
  const busy = Boolean(s.working);
  const button = $('#state');
  button.classList.toggle('busy', busy);
  $('#state-label').textContent = busy ? (s.step || '').split(' : ')[0] : '';
  button.title = statusText(s);
  clearInterval(polling);
  polling = setInterval(poll, busy ? 4000 : 30000);
}

async function poll() {
  try {
    const s = await (await fetch('api/status')).json();
    const was = state.status;
    state.status = s;
    showStatus(s);
    if (s.books !== was.books || s.scannedAt !== was.scannedAt || s.online !== was.online || (was.working && !s.working)) {
      await refresh();
    }
  } catch { /* serveur arrêté : on réessaie */ }
}

async function refresh() {
  if (!reader.el.hidden) return load(); // Pas de rendu sous la liseuse.
  const y = window.scrollY;
  await load();
  route();
  window.scrollTo({ top: y });
}

$('#state').addEventListener('click', () => toast(statusText(state.status)));

let toastTimer;
function toast(text) {
  const el = $('#toast');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 4000);
}

document.addEventListener('click', async (e) => {
  const more = e.target.closest('[data-more]');
  if (more) {
    more.previousElementSibling.classList.add('open');
    more.remove();
    return;
  }
  const identify = e.target.closest('[data-identify]');
  if (identify) {
    await fetch(`api/identify/${identify.dataset.identify}`, { method: 'POST' });
    toast('Recherche en ligne…');
    state.status = { ...state.status, working: true };
    showStatus(state.status);
  }
});

// ---------------------------------------------------------------------------
// Démarrage

let searchTimer;
$('#search').addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    if (location.hash) history.replaceState(null, '', location.pathname);
    if ($('#search').value.trim()) renderSearch($('#search').value); else route();
  }, 150);
});
window.addEventListener('hashchange', () => { if (location.hash) $('#search').value = ''; route(); });
window.addEventListener('scroll', () => $('#topbar').classList.toggle('solid', window.scrollY > 10), { passive: true });

(async () => {
  state.sort = store.get('sort', 'added');
  try {
    await load();
  } catch (e) {
    statusLine.textContent = `Bibliothèque illisible : ${e.message}`;
    return;
  }
  route();
})();
