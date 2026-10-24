'use strict';

// C411 Music : la musique du serveur dans le navigateur.
// Discothèque : /api/library (albums, artistes, état du parcours) ;
// lecture : /api/play/<piste> dit si le navigateur peut lire le fichier tel
// quel (/media, avance rapide native) ou s'il faut le convertir
// (/stream?t=…, l'avance rapide relance la conversion à la bonne position).

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));
const icon = {
  enqueue: '<svg viewBox="0 0 24 24"><path d="M3 6h12v2H3zm0 4h12v2H3zm0 4h8v2H3zm13 0v-3h2v3h3v2h-3v3h-2v-3h-3v-2h3Z"/></svg>',
  remove: '<svg viewBox="0 0 24 24"><path d="m18.3 7.1-1.4-1.4L12 10.6 7.1 5.7 5.7 7.1l4.9 4.9-4.9 4.9 1.4 1.4 4.9-4.9 4.9 4.9 1.4-1.4-4.9-4.9z"/></svg>',
  play: '<svg viewBox="0 0 24 24"><path d="M8 5.1v13.8a1 1 0 0 0 1.5.86l11-6.9a1 1 0 0 0 0-1.72l-11-6.9A1 1 0 0 0 8 5.1Z"/></svg>',
  pause: '<svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zm6 0h4v14h-4z"/></svg>',
  shuffle: '<svg viewBox="0 0 24 24"><path d="M10.6 9.2 5.4 4 4 5.4l5.2 5.2 1.4-1.4ZM14.5 4l2 2L4 18.6 5.4 20 18 7.5l2 2V4h-5.5Zm.3 9.4-1.4 1.4 3.1 3.1L14.5 20H20v-5.5l-2 2-3.2-3.1Z"/></svg>',
  repeat: '<svg viewBox="0 0 24 24"><path d="M7 7h10v3l4-4-4-4v3H5v6h2V7Zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4Z"/></svg>',
  repeatOne: '<svg viewBox="0 0 24 24"><path d="M7 7h10v3l4-4-4-4v3H5v6h2V7Zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4Zm-4-2V9h-1l-2 1v1h1.5v4H13Z"/></svg>',
  volume: '<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3Zm13.5 3A4.5 4.5 0 0 0 14 8v8a4.5 4.5 0 0 0 2.5-4ZM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6Z"/></svg>',
  album: '<svg viewBox="0 0 24 24"><path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16Zm0-12.5a4.5 4.5 0 1 0 0 9 4.5 4.5 0 0 0 0-9Zm0 6a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3Z"/></svg>',
  muted: '<svg viewBox="0 0 24 24"><path d="M16.5 12A4.5 4.5 0 0 0 14 8v2.2l2.45 2.45c.03-.2.05-.43.05-.65Zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51A8.8 8.8 0 0 0 21 12a9 9 0 0 0-7-8.8v2.1A7 7 0 0 1 19 12ZM4.27 3 3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25A7 7 0 0 1 14 18.7v2.1a9 9 0 0 0 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3ZM12 4 9.91 6.09 12 8.18V4Z"/></svg>',
};
const eq = '<span class="eq"><i></i><i></i><i></i></span>';

const state = {
  albums: [], audiobooks: [], artists: [], albumById: new Map(), artistById: new Map(), trackById: new Map(),
  status: {}, sort: 'added', genre: null, badges: true,
};

// ---------------------------------------------------------------------------
// Préférences et écoutes (dans ce navigateur)

const store = {
  get(key, fallback) {
    try { const v = JSON.parse(localStorage.getItem('c411music.' + key)); return v ?? fallback; } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem('c411music.' + key, JSON.stringify(value)); } catch { /* stockage indisponible */ }
  },
};

/** Albums écoutés récemment, du plus récent au plus ancien. */
function recentAlbums() {
  return store.get('recent', []).map((id) => state.albumById.get(id)).filter(Boolean);
}
function rememberAlbum(id) {
  store.set('recent', [id, ...store.get('recent', []).filter((x) => x !== id)].slice(0, 30));
}

/** Livres audio : où on en est de chacun (piste, position, date). */
const bookProgress = (id) => store.get('books', {})[id] || null;
function saveBookProgress() {
  const t = current();
  if (!t || t.album.kind !== 'audiobook') return;
  store.set('books', { ...store.get('books', {}), [t.album.id]: { track: t.id, time: position(), at: Date.now() } });
}
/** Livres audio commencés, du plus récent au plus ancien. */
const booksInProgress = () => state.audiobooks.filter((a) => bookProgress(a.id))
  .sort((a, b) => bookProgress(b.id).at - bookProgress(a.id).at);

// ---------------------------------------------------------------------------
// Discothèque

async function load() {
  const res = await fetch('api/library');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  // Musique d'un côté, livres audio de l'autre ; les sons sans rapport
  // (samples d'un logiciel, musiques d'un jeu : kind « other ») sont écartés.
  const kept = data.albums.filter((a) => a.kind !== 'other');
  state.albums = kept.filter((a) => a.kind !== 'audiobook');
  state.audiobooks = kept.filter((a) => a.kind === 'audiobook');
  state.artists = data.artists;
  state.status = data.status || {};
  state.albumById = new Map(kept.map((a) => [a.id, a]));
  state.artistById = new Map(data.artists.map((a) => [a.id, a]));
  state.trackById = new Map();
  for (const a of kept) for (const t of a.tracks) state.trackById.set(t.id, { ...t, album: a });
  // « NOUVEAU » : seulement si la nouveauté distingue quelque chose (pas
  // après un premier parcours, où tout paraît récent).
  const recent = state.albums.filter((a) => isRecent(a));
  state.badges = recent.length <= Math.max(8, state.albums.length * 0.2);
  await Promise.all([loadVotes(), loadFavorites()]);
  showStatus(state.status);
}

const addedOf = (a) => (a.added ? Date.parse(a.added) : 0);
const isRecent = (a) => Date.now() - addedOf(a) < 7 * 864e5;
const fmtTime = (s) => {
  if (!Number.isFinite(s) || s < 0) return '0:00';
  s = Math.floor(s);
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = String(s % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${sec}` : `${m}:${sec}`;
};
const albumDuration = (a) => a.tracks.reduce((n, t) => n + (t.duration || 0), 0);
const fold = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const plural = (n, word) => `${n} ${word}${n > 1 ? 's' : ''}`;
const typeLabel = { Album: 'Album', EP: 'EP', Single: 'Single', Broadcast: 'Émission', Other: 'Autre' };

/** Pochette : celle de la Cover Art Archive, sinon un dégradé et des
 * initiales, de couleur stable pour un album donné. [coverId] : l'album
 * dont prendre la pochette (pour un artiste). */
function cover(album, { badge = false, coverId = album.id } = {}) {
  let h = 0;
  for (const ch of album.id) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const hue = h % 360;
  const initials = (album.title || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const bg = `background: linear-gradient(135deg, hsl(${hue} 55% 38%), hsl(${(hue + 50) % 360} 60% 22%))`;
  return `<div class="cover" style="${bg}"><span class="initials">${esc(initials)}</span>${
    album.cover ? `<img src="api/cover/${coverId}" alt="" loading="lazy" onerror="this.remove()">` : ''}${
    badge && state.badges && isRecent(album) ? '<span class="badge">NOUVEAU</span>' : ''}</div>`;
}

function albumCard(a) {
  const sub = [a.artist, a.year].filter(Boolean).join(' · ');
  return `<a class="card" href="#album=${a.id}">${cover(a, { badge: true })}${voteBadge(a.id)}
    <button class="play-on" data-play-album="${a.id}" title="Écouter" aria-label="Écouter ${esc(a.title)}">${icon.play}</button>
    <div class="card-title" title="${esc(a.title)}">${esc(a.title)}</div><div class="card-sub">${esc(sub)}</div></a>`;
}

function artistCard(artist) {
  const albums = artist.albums.map((id) => state.albumById.get(id)).filter(Boolean);
  const pic = albums.find((a) => a.cover) || albums[0];
  return `<a class="card artist" href="#artist=${artist.id}">${cover({ id: artist.id, title: artist.name, cover: Boolean(pic?.cover) }, { coverId: pic?.id })}
    <div class="card-title">${esc(artist.name)}</div><div class="card-sub">${plural(albums.length, 'album')}</div></a>`;
}

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

/** Votes compacts (file d'attente) : icônes seules, totaux en infobulle. */
function voteMini(id, what = 'cet album') {
  const [up, down, mine] = tallyOf(id);
  const off = votes.user ? '' : ' disabled';
  const button = (value, label, count) => `<button class="vote-btn mini${value < 0 ? ' down' : ''}${mine === value ? ' on' : ''}" data-vote="${value}"
    aria-pressed="${mine === value}" title="${label} ${what} (${count})${mine === value ? ' — cliquer pour retirer' : ''}"${off}>${value > 0 ? thumbs.up : thumbs.down}</button>`;
  return `<span class="q-votes" data-votes="${esc(id)}" data-mini="${esc(what)}">${button(1, 'J’aime', up)}${button(-1, 'Je n’aime pas', down)}</span>`;
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
  for (const el of document.querySelectorAll(`[data-votes="${CSS.escape(id)}"]`)) {
    el.outerHTML = el.dataset.mini ? voteMini(id, el.dataset.mini) : voteBar(id);
  }
  for (const el of document.querySelectorAll(`[data-badge="${CSS.escape(id)}"]`)) el.outerHTML = voteBadge(id);
  if (typeof onFavoritesChange === 'function') onFavoritesChange();
}, { capture: true });

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

/** Les titres favoris (pas les albums), dans l'ordre des favoris. */
const favoriteTrackIds = () => favorites.ids.filter((id) => state.trackById.has(id) && !state.albumById.has(id));

/** Favori ajouté ou retiré : la page « Favoris » suit. */
function onFavoritesChange() {
  if (decodeURIComponent(location.hash) === '#favoris') {
    const y = window.scrollY;
    renderFavorites();
    window.scrollTo({ top: y });
  }
}

/** Ligne d'un titre hors de son album (recherche, favoris). */
const trackRow = (t) => `<div class="track" data-track="${t.id}" data-album="${t.album.id}">
      <span class="num"><span class="n">${t.number ?? '·'}</span>${eq}</span>
      <span><div class="t-title">${esc(t.title)}</div><div class="t-artist">${esc(t.album.artist)} · ${esc(t.album.title)}</div></span>
      <span class="fmt">${esc(t.format)}</span><span class="t-fav">${t.album.kind === 'audiobook' ? '' : `<button class="icon-btn t-enqueue" data-enqueue="${t.id}" title="Ajouter à la file d’attente" aria-label="Ajouter à la file d’attente">${icon.enqueue}</button>${voteMini(t.id, 'ce titre')}`}</span><span class="dur">${t.duration ? fmtTime(t.duration) : ''}</span></div>`;

// ---------------------------------------------------------------------------
// Vues

const content = $('#content');
const statusLine = $('#status');

function setNav(view) {
  for (const a of document.querySelectorAll('.nav a')) a.classList.toggle('active', a.dataset.view === view);
}

function genresOf(albums) {
  const count = new Map();
  for (const a of albums) for (const g of a.genres || []) count.set(g, (count.get(g) || 0) + 1);
  return [...count.entries()].sort((a, b) => b[1] - a[1]).map(([g]) => g);
}

function renderHome() {
  setNav('home');
  const albums = state.albums;
  if (!albums.length) {
    content.innerHTML = '';
    statusLine.textContent = 'Aucun album pour l’instant. La musique vient du parcours de la vidéothèque '
      + 'de l’application (Films & séries › Actualiser) : torrents terminés et dossiers à parcourir.';
    return;
  }
  statusLine.textContent = '';
  const byAdded = [...albums].sort((a, b) => addedOf(b) - addedOf(a));
  const featured = byAdded.find((a) => a.cover) || byAdded[0];
  const recent = recentAlbums().filter((a) => a.kind !== 'audiobook');
  const favs = favorites.ids.map((id) => state.albumById.get(id)).filter(Boolean);
  const genres = genresOf(albums).slice(0, 5);
  const artists = [...state.artists].sort((a, b) => b.albums.length - a.albums.length).slice(0, 24);
  content.innerHTML = hero(featured, 'À la une') +
    row('Écoutés récemment', recent.slice(0, 20), albumCard) +
    row('Mes favoris', favs.slice(0, 24), albumCard, '#favoris') +
    row('Ajoutés récemment', byAdded.slice(0, 24), albumCard, '#albums') +
    row('Préférés des membres', liked(albums).slice(0, 24), albumCard, '#albums') +
    genres.map((g) => row(g[0].toUpperCase() + g.slice(1), albums.filter((a) => a.genres?.includes(g)).slice(0, 24), albumCard, `#albums&genre=${encodeURIComponent(g)}`)).join('') +
    row('Artistes', artists, artistCard, '#artists');
}

function hero(a, eyebrow) {
  const artist = state.artists.find((x) => x.albums.includes(a.id));
  const meta = [
    artist ? `<a href="#artist=${artist.id}">${esc(a.artist)}</a>` : esc(a.artist),
    a.year, plural(a.tracks.length, 'titre'),
    albumDuration(a) ? fmtTime(albumDuration(a)) : '',
  ].filter(Boolean).join(' · ');
  return `<section class="hero">${a.cover ? `<div class="hero-bg" style="background-image:url('api/cover/${a.id}')"></div>` : ''}
    ${cover(a)}
    <div class="hero-text"><div class="eyebrow">${esc(eyebrow)}</div><h1>${esc(a.title)}</h1><div class="meta">${meta}</div>
      ${a.genres?.length ? `<div class="chips">${a.genres.map((g) => `<span class="chip">${esc(g)}</span>`).join('')}</div>` : ''}
      <div class="actions">${a.kind === 'audiobook' ? bookActions(a) : `
        <button class="btn primary" data-play-album="${a.id}">${icon.play}Écouter</button>
        <button class="btn" data-shuffle-album="${a.id}">${icon.shuffle}Aléatoire</button>
        <button class="btn" data-enqueue-album="${a.id}" title="Ajouter tout l’album à la fin de la file d’attente">${icon.enqueue}File d’attente</button>
        ${eyebrow === 'À la une' ? `<a class="btn" href="#album=${a.id}">Voir l'album</a>` : ''}`}
      </div></div></section>`;
}

/** Livre audio : reprendre là où on s'était arrêté, ou commencer. */
function bookActions(a) {
  const p = bookProgress(a.id);
  const i = p ? a.tracks.findIndex((t) => t.id === p.track) : -1;
  if (i < 0) return `<button class="btn primary" data-play-book="${a.id}">${icon.play}Écouter</button>`;
  return `<button class="btn primary" data-play-book="${a.id}">${icon.play}Reprendre · piste ${i + 1}/${a.tracks.length}, ${fmtTime(p.time)}</button>
    <button class="btn" data-play-album="${a.id}">Depuis le début</button>`;
}

function renderFavorites() {
  setNav('favoris');
  const items = favorites.ids.map((id) => state.albumById.get(id) || state.trackById.get(id)).filter(Boolean);
  const albums = items.filter((x) => x.tracks && x.kind !== 'audiobook');
  const books = items.filter((x) => x.tracks && x.kind === 'audiobook');
  const tracks = items.filter((x) => !x.tracks);
  statusLine.textContent = items.length ? '' : 'Aucun favori pour l’instant : ce que tu aimes arrive ici. 👍 sur un album, un livre audio '
    + 'ou un titre précis (sur sa ligne, dans la file d’attente ou dans le lecteur). Les favoris te suivent sur tous tes appareils.';
  content.innerHTML = `<div class="page-head"><h1>Mes favoris</h1><span class="count">${items.length}</span>${tracks.length
      ? `<div class="actions" style="margin:0 0 0 auto"><button class="btn primary" data-play-favs>${icon.play}Écouter les titres</button>
        <button class="btn" data-shuffle-favs>${icon.shuffle}Aléatoire</button></div>` : ''}</div>
    ${row('Albums', albums, albumCard)}
    ${tracks.length ? `<section class="row"><div class="row-head"><h2>Titres</h2></div></section><div class="tracks">${tracks.map(trackRow).join('')}</div>` : ''}
    ${row('Livres audio', books, albumCard)}`;
  markCurrent();
}

function renderAudiobooks() {
  setNav('audiobooks');
  const list = [...state.audiobooks].sort((a, b) => addedOf(b) - addedOf(a));
  statusLine.textContent = list.length ? '' : 'Aucun livre audio. Ils viennent des dossiers « Livres » (catégorie Livres dans Transmission) '
    + 'ou sont reconnus à leur nom (.m4b, « Chapitre … », référence Audible).';
  content.innerHTML = `<div class="page-head"><h1>Livres audio</h1><span class="count">${list.length}</span></div>
    ${row('Continuer l’écoute', booksInProgress(), albumCard)}
    <div class="grid">${list.map(albumCard).join('')}</div>`;
}

const sorts = {
  added: ['Ajout récent', (a, b) => addedOf(b) - addedOf(a)],
  title: ['Titre', (a, b) => fold(a.title).localeCompare(fold(b.title))],
  artist: ['Artiste', (a, b) => fold(a.artist).localeCompare(fold(b.artist)) || (a.year || 0) - (b.year || 0)],
  year: ['Année', (a, b) => (b.year || 0) - (a.year || 0)],
  votes: ['Préférés des membres', (a, b) => byVotes(a.id, b.id)],
};

function renderAlbums(genre) {
  setNav('albums');
  statusLine.textContent = '';
  state.genre = genre || null;
  const list = state.albums.filter((a) => !state.genre || a.genres?.includes(state.genre)).sort(sorts[state.sort][1]);
  const genres = genresOf(state.albums).slice(0, 14);
  content.innerHTML = `<div class="page-head"><h1>Albums</h1><span class="count">${list.length}</span>
      <select id="sort" aria-label="Trier">${Object.entries(sorts).map(([k, [label]]) => `<option value="${k}"${k === state.sort ? ' selected' : ''}>${label}</option>`).join('')}</select></div>
    ${genres.length ? `<div class="chips" style="padding:0 var(--gutter) 16px">${genres.map((g) => `<button class="chip${g === state.genre ? ' active' : ''}" data-genre="${esc(g)}">${esc(g)}</button>`).join('')}</div>` : ''}
    <div class="grid">${list.map(albumCard).join('')}</div>`;
  $('#sort').addEventListener('change', (e) => { state.sort = e.target.value; store.set('sort', state.sort); renderAlbums(state.genre); });
}

function renderArtists() {
  setNav('artists');
  statusLine.textContent = '';
  const list = [...state.artists].sort((a, b) => fold(a.name).localeCompare(fold(b.name)));
  content.innerHTML = `<div class="page-head"><h1>Artistes</h1><span class="count">${list.length}</span></div>
    <div class="grid">${list.map(artistCard).join('')}</div>`;
}

function renderAlbum(id) {
  const a = state.albumById.get(id);
  if (!a) return notFound();
  const book = a.kind === 'audiobook';
  setNav(book ? 'audiobooks' : '');
  statusLine.textContent = '';
  const discs = [...new Set(a.tracks.map((t) => t.disc))];
  const eyebrow = book ? 'Livre audio' : [typeLabel[a.type] || 'Album', a.label, a.country].filter(Boolean).join(' · ');
  content.innerHTML = hero(a, eyebrow).replace('class="hero"', 'class="hero album-head"')
      .replace('</div></div></section>', `</div>${voteBar(a.id)}</div></section>`) +
    `<div class="tracks">${discs.map((d) => `${discs.length > 1 ? `<div class="disc">Disque ${d}</div>` : ''}${
      a.tracks.filter((t) => t.disc === d).map((t) => `<div class="track" data-track="${t.id}" data-album="${a.id}">
        <span class="num"><span class="n">${t.number ?? '·'}</span>${eq}</span>
        <span><div class="t-title">${esc(t.title)}</div>${t.artist ? `<div class="t-artist">${esc(t.artist)}</div>` : ''}</span>
        <span class="fmt">${esc(t.format)}</span>
        <span class="t-fav">${book ? '' : `<button class="icon-btn t-enqueue" data-enqueue="${t.id}" title="Ajouter à la file d’attente" aria-label="Ajouter à la file d’attente">${icon.enqueue}</button>${voteMini(t.id, 'ce titre')}`}</span>
        <span class="dur">${t.duration ? fmtTime(t.duration) : ''}</span></div>`).join('')}`).join('')}</div>
    <p class="notes">${book ? 'Livre audio : les pistes sont lues dans l’ordre des fichiers, et la position est gardée dans ce navigateur. '
      : a.source === 'discogs'
      ? `Fiche <a href="${esc(a.link)}" target="_blank" rel="noopener">Discogs</a> (album inconnu de MusicBrainz). `
      : a.mbid
        ? `Fiche <a href="https://musicbrainz.org/release/${a.mbid}" target="_blank" rel="noopener">MusicBrainz</a>${a.cover ? `, pochette ${a.coverFrom === 'discogs' ? 'Discogs' : 'Cover Art Archive'}` : ''}. `
        : 'Album non reconnu en ligne : titres et ordre d’après les noms de fichiers. '}
      ${book ? '' : `<button class="link-btn" data-identify="${a.id}">Chercher à nouveau en ligne</button>`}</p>`;
  markCurrent();
}

function renderArtist(id) {
  const artist = state.artistById.get(id);
  if (!artist) return notFound();
  setNav('');
  statusLine.textContent = '';
  const albums = artist.albums.map((x) => state.albumById.get(x)).filter(Boolean).sort((a, b) => (b.year || 0) - (a.year || 0));
  const tracks = albums.reduce((n, a) => n + a.tracks.length, 0);
  content.innerHTML = `<div class="page-head"><h1>${esc(artist.name)}</h1><span class="count">${plural(albums.length, 'album')} · ${plural(tracks, 'titre')}</span>
      <div class="actions" style="margin:0 0 0 auto"><button class="btn primary" data-play-artist="${artist.id}">${icon.play}Écouter</button>
      <button class="btn" data-shuffle-artist="${artist.id}">${icon.shuffle}Aléatoire</button></div></div>
    <div class="grid">${albums.map(albumCard).join('')}</div>
    ${artist.mbid ? `<p class="notes">Fiche <a href="https://musicbrainz.org/artist/${artist.mbid}" target="_blank" rel="noopener">MusicBrainz</a>.</p>` : ''}`;
}

function renderSearch(query) {
  setNav('');
  const q = fold(query.trim());
  const albums = state.albums.filter((a) => fold(`${a.title} ${a.artist}`).includes(q));
  const books = state.audiobooks.filter((a) => fold(`${a.title} ${a.artist}`).includes(q));
  const artists = state.artists.filter((a) => fold(a.name).includes(q));
  // Titres : la musique seulement (pas les « Chapitre 3 » des livres audio).
  const tracks = [...state.trackById.values()].filter((t) => t.album.kind !== 'audiobook' && fold(t.title).includes(q)).slice(0, 50);
  statusLine.textContent = albums.length + books.length + artists.length + tracks.length ? '' : `Rien pour « ${query} ».`;
  content.innerHTML = (artists.length ? `<div class="page-head"><h1>Artistes</h1></div><div class="grid">${artists.slice(0, 12).map(artistCard).join('')}</div>` : '') +
    (albums.length ? `<div class="page-head"><h1>Albums</h1></div><div class="grid">${albums.map(albumCard).join('')}</div>` : '') +
    (books.length ? `<div class="page-head"><h1>Livres audio</h1></div><div class="grid">${books.map(albumCard).join('')}</div>` : '') +
    (tracks.length ? `<div class="page-head"><h1>Titres</h1></div><div class="tracks">${tracks.map(trackRow).join('')}</div>` : '');
  markCurrent();
}

function notFound() {
  content.innerHTML = '';
  statusLine.textContent = 'Introuvable : la discothèque a peut-être changé.';
}

/** Routes : #albums, #albums&genre=…, #artists, #audiobooks, #favoris, #album=<id>, #artist=<id>. */
function route() {
  const hash = decodeURIComponent(location.hash.slice(1));
  const query = $('#search').value.trim();
  if (query && !hash) return renderSearch(query);
  const params = new URLSearchParams(hash.replace(/^[^&=]+(?=&|$)/, (v) => `view=${v}`));
  if (params.has('album')) renderAlbum(params.get('album'));
  else if (params.has('artist')) renderArtist(params.get('artist'));
  else if (params.get('view') === 'albums') renderAlbums(params.get('genre'));
  else if (params.get('view') === 'artists') renderArtists();
  else if (params.get('view') === 'audiobooks') renderAudiobooks();
  else if (params.get('view') === 'favoris') renderFavorites();
  else renderHome();
  window.scrollTo({ top: 0 });
}

// ---------------------------------------------------------------------------
// Lecture

const audio = $('#audio');
const player = {
  queue: [], index: -1, shuffle: false, repeat: 'off',
  mode: 'direct', offset: 0, duration: 0, info: null, seeking: false,
};

function current() { return state.trackById.get(player.queue[player.index]); }

// Safari et Firefox ne laissent démarrer le son que pendant le clic : après
// l'attente de api/play, audio.play() serait refusé et la file resterait en
// pause. Un son vide joué tout de suite, pendant le clic, débloque l'élément
// <audio> pour la suite.
const SILENCE = 'data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA=';
function unlockAudio() {
  if (!audio.paused) return;
  audio.src = SILENCE;
  audio.play().catch(() => { /* déjà débloqué, ou refusé : rien à faire */ });
}
const silent = () => audio.src === SILENCE;

/** Joue [ids] à partir de [start] ; aléatoire si demandé. Appelée pendant
 * un clic. */
function playList(ids, start = 0, shuffle = player.shuffle) {
  if (!ids.length) return;
  unlockAudio();
  let queue = [...ids];
  if (shuffle) {
    const first = queue.splice(start, 1)[0];
    for (let i = queue.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [queue[i], queue[j]] = [queue[j], queue[i]]; }
    queue = [first, ...queue];
    start = 0;
  }
  player.queue = queue;
  player.shuffle = shuffle;
  playAt(start);
}

/** Livre audio : à la piste et à la position où on s'était arrêté. */
function playBook(id) {
  const ids = albumTrackIds(id);
  if (!ids.length) return;
  const p = bookProgress(id);
  const start = p ? Math.max(0, ids.indexOf(p.track)) : 0;
  unlockAudio();
  player.queue = ids;
  player.shuffle = false;
  playAt(start, { time: p && ids[start] === p.track ? p.time : 0 });
}

const albumTrackIds = (id) => state.albumById.get(id)?.tracks.map((t) => t.id) || [];
function artistTrackIds(id) {
  const artist = state.artistById.get(id);
  return artist ? artist.albums.flatMap(albumTrackIds) : [];
}

// ---------------------------------------------------------------------------
// Random : une playlist tirée au hasard dans la discothèque (ou le genre affiché)

const RANDOM_SIZE = 30;
const MAX_PER_ALBUM = 2, MAX_PER_ARTIST = 3;

/** Titres joués récemment (pour ne pas les resservir tout de suite). */
function rememberTrack(id) {
  store.set('played', [id, ...store.get('played', []).filter((x) => x !== id)].slice(0, 300));
}

/** Tirage pondéré, sans remise : moins de chances pour ce qui a été écouté
 * récemment, un peu plus pour les albums ajoutés depuis moins d'un mois et
 * pour les albums et titres que les membres aiment (moins pour ceux qu'ils
 * n'aiment pas) ;
 * pas d'intros ni d'interludes (< 1 min) ni de morceaux de plus de 15 min ;
 * deux titres par album et trois par artiste au plus (limites relâchées
 * par paliers si la discothèque est trop petite) ; jamais deux fois le même
 * artiste d'affilée quand c'est possible. */
function randomPlaylist(genre) {
  const recent = new Set(store.get('recent', []).slice(0, 10));
  const played = new Set(store.get('played', []));
  const artistOf = (t) => fold(t.artist || t.album.artist || '?');
  const pool = [];
  for (const a of state.albums) {
    if (a.type === 'Broadcast' || (genre && !a.genres?.includes(genre))) continue;
    for (const t of a.tracks) {
      if (t.duration && (t.duration < 60 || t.duration > 900)) continue;
      let w = 1;
      if (played.has(t.id)) w *= 0.1;
      if (recent.has(a.id)) w *= 0.3;
      if (Date.now() - addedOf(a) < 30 * 864e5) w *= 1.5;
      const score = scoreOf(a.id) + scoreOf(t.id); // votes des membres : album et titre
      if (score > 0) w *= Math.min(2, 1 + score * 0.25);
      else if (score < 0) w *= 0.5;
      // Efraimidis-Spirakis : trier sur u^(1/w) = tirage pondéré sans remise.
      pool.push({ t: { ...t, album: a }, key: Math.random() ** (1 / w) });
    }
  }
  pool.sort((x, y) => y.key - x.key);
  const picked = [], perAlbum = new Map(), perArtist = new Map();
  for (const factor of [1, 2, Infinity]) {
    for (const { t } of pool) {
      if (picked.length >= RANDOM_SIZE) break;
      if (picked.includes(t)) continue;
      const ar = artistOf(t);
      if ((perAlbum.get(t.album.id) || 0) >= MAX_PER_ALBUM * factor || (perArtist.get(ar) || 0) >= MAX_PER_ARTIST * factor) continue;
      picked.push(t);
      perAlbum.set(t.album.id, (perAlbum.get(t.album.id) || 0) + 1);
      perArtist.set(ar, (perArtist.get(ar) || 0) + 1);
    }
  }
  // Ordre : à chaque pas, le premier titre restant (ordre du tirage) d'un
  // autre artiste que le précédent ; mais l'artiste qui a plus de la moitié
  // des titres restants passe d'abord, sinon il finirait en grappe.
  const ordered = [];
  while (picked.length) {
    const prevArtist = ordered.length ? artistOf(ordered[ordered.length - 1]) : null;
    const left = new Map();
    for (const t of picked) left.set(artistOf(t), (left.get(artistOf(t)) || 0) + 1);
    const [top, count] = [...left].sort((x, y) => y[1] - x[1])[0];
    const urgent = top !== prevArtist && count * 2 > picked.length;
    const i = Math.max(0, picked.findIndex((t) => (urgent ? artistOf(t) === top : artistOf(t) !== prevArtist)));
    ordered.push(picked.splice(i, 1)[0]);
  }
  return ordered;
}

function playRandom() {
  const genre = new URLSearchParams(decodeURIComponent(location.hash.slice(1))).get('genre');
  const tracks = randomPlaylist(genre);
  if (!tracks.length) return toast(genre ? `Rien à tirer au hasard dans « ${genre} ».` : 'La discothèque est vide.');
  playList(tracks.map((t) => t.id), 0, false);
  const total = tracks.reduce((n, t) => n + (t.duration || 0), 0);
  toast(`Random${genre ? ` · ${genre}` : ''} : ${plural(tracks.length, 'titre')}${total ? ` · ${fmtTime(total)}` : ''}`);
  const button = $('#random');
  button.classList.remove('rolling');
  void button.offsetWidth; // relance l'animation
  button.classList.add('rolling');
}

$('#random').addEventListener('click', playRandom);

async function playAt(index, { time = 0, autoplay = true } = {}) {
  if (index < 0 || index >= player.queue.length) return;
  player.index = index;
  const t = current();
  if (!t) return;
  rememberAlbum(t.album.id);
  rememberTrack(t.id);
  showNow(t);
  saveSession();
  $('#spinner').hidden = false;
  let info;
  try {
    const res = await fetch(`api/play/${t.id}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    info = await res.json();
  } catch (e) {
    toast(`Lecture impossible : ${e.message}`);
    $('#spinner').hidden = true;
    return;
  }
  if (player.queue[player.index] !== t.id) return; // Une autre piste a été demandée entre-temps.
  player.info = info;
  player.duration = info.duration || t.duration || 0;
  const direct = info.type && audio.canPlayType(info.type) !== '';
  if (direct || !info.streamUrl) loadSource(info.directUrl, 'direct', time, autoplay);
  else loadSource(info.streamUrl, 'stream', time, autoplay);
}

function loadSource(url, mode, time, autoplay) {
  player.mode = mode;
  player.offset = mode === 'stream' ? time : 0;
  audio.src = mode === 'stream' ? `${url}?t=${time.toFixed(1)}` : url;
  if (mode === 'direct' && time > 0) audio.addEventListener('loadedmetadata', () => { audio.currentTime = time; }, { once: true });
  if (autoplay) audio.play().catch(() => { /* lecture bloquée sans geste : le bouton reste là */ });
  updateButtons();
}

/** Position dans la piste, conversion comprise. */
const position = () => player.offset + (audio.currentTime || 0);
const duration = () => (player.mode === 'direct' && Number.isFinite(audio.duration) ? audio.duration : player.duration);

function seekTo(seconds) {
  const d = duration();
  if (d) seconds = Math.max(0, Math.min(seconds, d - 0.5));
  if (player.mode === 'stream') loadSource(player.info.streamUrl, 'stream', seconds, !audio.paused);
  else audio.currentTime = seconds;
}

function next(auto = false) {
  if (auto && player.repeat === 'one') return seekTo(0) || audio.play();
  if (player.index + 1 < player.queue.length) return playAt(player.index + 1);
  if (player.repeat === 'all' && player.queue.length) return playAt(0);
  if (auto) { audio.pause(); updateButtons(); }
}
function prev() {
  if (position() > 4 || player.index === 0) return seekTo(0);
  playAt(player.index - 1);
}
function toggle() {
  if (!current()) return;
  if (!audio.src || silent()) {
    unlockAudio();
    return playAt(player.index, { time: store.get('time', 0) });
  }
  if (audio.paused) audio.play(); else audio.pause();
}

audio.addEventListener('ended', () => { if (!silent()) next(true); });
audio.addEventListener('play', updateButtons);
audio.addEventListener('pause', updateButtons);
audio.addEventListener('waiting', () => { $('#spinner').hidden = false; });
audio.addEventListener('playing', () => { if (!silent()) $('#spinner').hidden = true; });
audio.addEventListener('canplay', () => { if (!silent()) $('#spinner').hidden = true; });
audio.addEventListener('error', () => {
  if (silent()) return;
  $('#spinner').hidden = true;
  // Lecture directe refusée (ALAC dans un .m4a, codec inattendu) : on
  // convertit, à la même position.
  if (player.mode === 'direct' && player.info?.streamUrl) {
    loadSource(player.info.streamUrl, 'stream', position(), true);
    return;
  }
  toast('Ce fichier ne peut pas être lu dans ce navigateur.');
});
let saved = 0;
audio.addEventListener('timeupdate', () => {
  if (silent()) return;
  if (!player.seeking) {
    const d = duration();
    const seek = $('#seek');
    seek.value = d ? Math.round((position() / d) * 1000) : 0;
    seek.style.setProperty('--pos', `${seek.value / 10}%`);
  }
  $('#elapsed').textContent = fmtTime(position());
  $('#total').textContent = fmtTime(duration());
  if (Date.now() - saved > 5000) { saved = Date.now(); store.set('time', position()); saveBookProgress(); }
  if ('mediaSession' in navigator && duration() && navigator.mediaSession.setPositionState) {
    try { navigator.mediaSession.setPositionState({ duration: duration(), position: Math.min(position(), duration()), playbackRate: 1 }); } catch { /* valeurs refusées */ }
  }
});

function showNow(t) {
  $('#player').hidden = false;
  $('#now-title').textContent = t.title;
  $('#now-title').onclick = () => goToTrack(t.id);
  $('#now-fav').innerHTML = t.album.kind === 'audiobook' ? voteMini(t.album.id, 'ce livre') : voteMini(t.id, 'ce titre');
  const artist = $('#now-artist');
  artist.textContent = [t.artist || t.album.artist, t.album.title].join(' · ');
  const owner = state.artists.find((x) => x.albums.includes(t.album.id));
  artist.href = owner ? `#artist=${owner.id}` : `#album=${t.album.id}`;
  $('#now-cover').innerHTML = cover(t.album);
  $('#now-cover').onclick = () => { location.hash = `album=${t.album.id}`; };
  document.title = `${t.title} · ${t.album.artist} — C411 Music`;
  markCurrent();
  renderQueue();
  if ('mediaSession' in navigator) {
    navigator.mediaSession.metadata = new MediaMetadata({
      title: t.title, artist: t.artist || t.album.artist, album: t.album.title,
      artwork: t.album.cover ? [{ src: new URL(`api/cover/${t.album.id}`, location.href).href, sizes: '500x500' }] : [],
    });
  }
}

function markCurrent() {
  const id = player.queue[player.index];
  for (const el of document.querySelectorAll('.track')) el.classList.toggle('current', el.dataset.track === id);
}

function updateButtons() {
  const playing = !audio.paused;
  $('#play').innerHTML = playing ? icon.pause : icon.play;
  document.body.classList.toggle('playing', playing);
  $('#shuffle').classList.toggle('on', player.shuffle);
  $('#repeat').classList.toggle('on', player.repeat !== 'off');
  $('#repeat').innerHTML = player.repeat === 'one' ? icon.repeatOne : icon.repeat;
  $('#repeat').title = { off: 'Répéter : non (R)', all: 'Répéter : tout (R)', one: 'Répéter : ce titre (R)' }[player.repeat];
  $('#mute').innerHTML = audio.muted || audio.volume === 0 ? icon.muted : icon.volume;
  if ('mediaSession' in navigator) navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
}

function renderQueue() {
  const list = $('#queue-list');
  if ($('#queue').hidden) return;
  list.innerHTML = player.queue.map((id, i) => {
    const t = state.trackById.get(id);
    if (!t) return '';
    const cls = i === player.index ? 'current' : i < player.index ? 'past' : '';
    const book = t.album.kind === 'audiobook';
    return `<li class="${cls}" data-queue="${i}">${cover(t.album)}<span><div class="q-title">${esc(t.title)}</div><div class="q-sub">${esc([t.artist || t.album.artist, t.album.title].filter(Boolean).join(' · '))}</div></span>
      <span class="q-actions">${book ? voteMini(t.album.id, 'ce livre') : voteMini(t.id, 'ce titre')}<button class="icon-btn q-remove" data-unqueue="${i}" title="Retirer de la file d’attente" aria-label="Retirer de la file d’attente">${icon.remove}</button><button class="icon-btn q-go" data-goto="${t.id}" title="Voir le titre dans ${book ? 'le livre' : 'l’album'}" aria-label="Voir le titre dans ${book ? 'le livre' : 'l’album'}">${icon.album}</button></span>
      <span class="dur">${t.duration ? fmtTime(t.duration) : ''}</span></li>`;
  }).join('');
  list.querySelector('.current')?.scrollIntoView({ block: 'nearest' });
}

function saveSession() {
  store.set('queue', player.queue);
  store.set('index', player.index);
  store.set('shuffle', player.shuffle);
  store.set('repeat', player.repeat);
}

// Commandes du lecteur
$('#play').addEventListener('click', toggle);
$('#next').addEventListener('click', () => next());
$('#prev').addEventListener('click', prev);
$('#shuffle').addEventListener('click', () => {
  const t = player.queue[player.index];
  if (!player.shuffle && player.queue.length > 1) {
    // Le reste de la file est mélangé, la piste en cours reste en tête.
    const rest = player.queue.filter((_, i) => i !== player.index);
    for (let i = rest.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [rest[i], rest[j]] = [rest[j], rest[i]]; }
    player.queue = [t, ...rest];
    player.index = 0;
  }
  player.shuffle = !player.shuffle;
  saveSession();
  updateButtons();
  renderQueue();
});
$('#repeat').addEventListener('click', () => {
  player.repeat = { off: 'all', all: 'one', one: 'off' }[player.repeat];
  saveSession();
  updateButtons();
});
const seek = $('#seek');
seek.addEventListener('input', () => {
  player.seeking = true;
  seek.style.setProperty('--pos', `${seek.value / 10}%`);
  $('#elapsed').textContent = fmtTime((seek.value / 1000) * duration());
});
seek.addEventListener('change', () => {
  player.seeking = false;
  seekTo((seek.value / 1000) * duration());
});
const volume = $('#volume');
function setVolume(v) {
  audio.volume = v;
  audio.muted = v === 0;
  volume.value = Math.round(v * 100);
  volume.style.setProperty('--pos', `${volume.value}%`);
  store.set('volume', v);
  updateButtons();
}
volume.addEventListener('input', () => setVolume(volume.value / 100));
$('#mute').addEventListener('click', () => { audio.muted = !audio.muted; updateButtons(); });
$('#queue-btn').addEventListener('click', () => { $('#queue').hidden = !$('#queue').hidden; renderQueue(); });
$('#queue-close').addEventListener('click', () => { $('#queue').hidden = true; });
$('#queue-list').addEventListener('click', (e) => {
  const out = e.target.closest('[data-unqueue]');
  if (out) return unqueue(Number(out.dataset.unqueue));
  const go = e.target.closest('[data-goto]');
  if (go) return goToTrack(go.dataset.goto);
  const li = e.target.closest('[data-queue]');
  if (li) playAt(Number(li.dataset.queue));
});
$('#queue-current').addEventListener('click', () => { if (current()) goToTrack(current().id); });

/** Ajoute des pistes à la fin de la file ; si rien n'est en cours, les joue. */
function enqueue(ids, label) {
  if (!ids.length) return;
  if (!current()) {
    playList(ids, 0, false);
    return toast(`${label} : lecture lancée`);
  }
  player.queue.push(...ids);
  saveSession();
  renderQueue();
  toast(`${label} : ajouté à la file d’attente (${plural(player.queue.length - player.index - 1, 'titre')} après celui en cours)`);
}

/** Retire la ligne [i] de la file ; si c'est la piste en cours, passe à la suivante. */
function unqueue(i) {
  if (i < 0 || i >= player.queue.length) return;
  const playing = i === player.index;
  player.queue.splice(i, 1);
  if (i < player.index) player.index--;
  if (playing) {
    if (player.index < player.queue.length) {
      playAt(player.index, { autoplay: !audio.paused });
    } else {
      audio.pause();
      player.index = player.queue.length - 1;
      if (current()) showNow(current()); else $('#player').hidden = true;
    }
  }
  saveSession();
  renderQueue();
}

// Avant les autres clics : le bouton est dans une ligne qui lance la lecture.
document.addEventListener('click', (e) => {
  const one = e.target.closest('[data-enqueue]');
  const all = e.target.closest('[data-enqueue-album]');
  if (!one && !all) return;
  e.preventDefault();
  e.stopPropagation();
  if (one) {
    const t = state.trackById.get(one.dataset.enqueue);
    if (t) enqueue([t.id], `« ${t.title} »`);
  } else {
    const a = state.albumById.get(all.dataset.enqueueAlbum);
    if (a) enqueue(albumTrackIds(a.id), `« ${a.title} » (${plural(a.tracks.length, 'titre')})`);
  }
}, { capture: true });

/** Ouvre l'album (ou le livre audio) d'une piste et la montre. */
function goToTrack(id) {
  const t = state.trackById.get(id);
  if (!t) return;
  $('#search').value = '';
  const hash = `#album=${t.album.id}`;
  if (location.hash !== hash) location.hash = hash; else route();
  // Sur petit écran, la file cache la page.
  if (window.matchMedia('(max-width: 760px)').matches) $('#queue').hidden = true;
  setTimeout(() => {
    const row = document.querySelector(`.track[data-track="${CSS.escape(id)}"]`);
    if (!row) return;
    row.scrollIntoView({ block: 'center', behavior: 'smooth' });
    row.classList.remove('flash');
    void row.offsetWidth;
    row.classList.add('flash');
  }, 60);
}

if ('mediaSession' in navigator) {
  const handlers = {
    play: () => audio.play(), pause: () => audio.pause(),
    previoustrack: prev, nexttrack: () => next(),
    seekto: (d) => seekTo(d.seekTime),
    seekbackward: () => seekTo(position() - 10), seekforward: () => seekTo(position() + 10),
  };
  for (const [action, fn] of Object.entries(handlers)) {
    try { navigator.mediaSession.setActionHandler(action, fn); } catch { /* action non prise en charge */ }
  }
}

// Clics dans les vues : lecture d'un album, d'un artiste, d'une piste.
document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-play-favs],[data-shuffle-favs],[data-play-book],[data-play-album],[data-shuffle-album],[data-play-artist],[data-shuffle-artist],[data-track],[data-genre],[data-identify]');
  if (!el) return;
  const d = el.dataset;
  if (d.playFavs !== undefined || d.shuffleFavs !== undefined) return playList(favoriteTrackIds(), 0, d.shuffleFavs !== undefined);
  if (d.playBook || d.playAlbum || d.shuffleAlbum || d.playArtist || d.shuffleArtist) e.preventDefault();
  if (d.playBook) playBook(d.playBook);
  else if (d.playAlbum) playList(albumTrackIds(d.playAlbum), 0, false);
  else if (d.shuffleAlbum) playList(albumTrackIds(d.shuffleAlbum), 0, true);
  else if (d.playArtist) playList(artistTrackIds(d.playArtist), 0, false);
  else if (d.shuffleArtist) playList(artistTrackIds(d.shuffleArtist), 0, true);
  else if (d.genre) location.hash = d.genre === state.genre ? 'albums' : `albums&genre=${encodeURIComponent(d.genre)}`;
  else if (d.identify) identify(d.identify);
  else if (d.track) {
    if (d.track === player.queue[player.index] && audio.src) return toggle();
    const ids = decodeURIComponent(location.hash) === '#favoris' ? favoriteTrackIds()
      : $('#search').value.trim() && !location.hash ? [d.track] : albumTrackIds(d.album);
    playList(ids, Math.max(0, ids.indexOf(d.track)), false);
  }
});

document.addEventListener('keydown', (e) => {
  if (e.target.matches('input[type="search"], select') || e.ctrlKey || e.metaKey || e.altKey) return;
  const k = e.key;
  if (k === ' ' && !e.target.matches('button, a')) { e.preventDefault(); toggle(); }
  else if (k === 'ArrowRight' && e.shiftKey || k === 'n' || k === 'N') next();
  else if (k === 'ArrowLeft' && e.shiftKey || k === 'p' || k === 'P') prev();
  else if (k === 'ArrowRight' && !e.target.matches('input[type="range"]')) seekTo(position() + 10);
  else if (k === 'ArrowLeft' && !e.target.matches('input[type="range"]')) seekTo(position() - 10);
  else if (k === 'm' || k === 'M') $('#mute').click();
  else if (k === 's' || k === 'S') $('#shuffle').click();
  else if (k === 'r' || k === 'R') $('#repeat').click();
  else if (k === 'q' || k === 'Q') $('#queue-btn').click();
  else if (k === 'Escape') $('#queue').hidden = true;
});

// ---------------------------------------------------------------------------
// MusicBrainz et base de l'application

/** Texte d'état : identification en cours, dernier parcours de l'application. */
function statusText(s) {
  return [
    s.step || (s.identifying ? 'Recherche en ligne…' : `${s.identified ?? 0} albums sur ${s.albums ?? 0} reconnus${s.discogs ? ` (dont ${s.fromDiscogs ?? 0} par Discogs)` : ' par MusicBrainz'}.`),
    s.discogsProblem ? `Discogs : ${s.discogsProblem}.` : '',
    s.scannedAt ? `Dernier parcours de l’application : ${new Date(s.scannedAt).toLocaleString('fr-FR')}.` : 'Pas encore de parcours dans l’application.',
    s.error || '',
  ].filter(Boolean).join('\n');
}

let polling = null;
function showStatus(s) {
  const busy = Boolean(s.identifying);
  const button = $('#scan');
  button.classList.toggle('busy', busy);
  $('#scan-label').textContent = busy ? `MusicBrainz ${s.identified}/${s.albums}` : '';
  button.title = statusText(s);
  // Vérifié aussi au repos : la base de l'application change quand elle parcourt.
  clearInterval(polling);
  polling = setInterval(poll, busy ? 4000 : 30000);
}

let lastIdentified = -1;
async function poll() {
  try {
    const s = await (await fetch('api/status')).json();
    const was = state.status;
    state.status = s;
    showStatus(s);
    // Discothèque relue quand des albums arrivent, au fil de
    // l'identification, et quand elle finit.
    const changed = s.albums !== was.albums || s.scannedAt !== was.scannedAt
      || (s.identified !== lastIdentified && (s.identified % 10 === 0 || !s.identifying));
    if (changed) {
      lastIdentified = s.identified;
      await refresh();
    }
  } catch { /* serveur arrêté : on réessaie */ }
}

async function refresh() {
  const y = window.scrollY;
  await load();
  route();
  window.scrollTo({ top: y });
  if (current()) markCurrent();
}

$('#scan').addEventListener('click', () => toast(statusText(state.status)));

async function identify(id) {
  await fetch(`api/identify/${id}`, { method: 'POST' });
  state.status = { ...state.status, identifying: true };
  showStatus(state.status);
  toast('Recherche en ligne…');
}

let toastTimer;
function toast(text) {
  const el = $('#toast');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3500);
}

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
  setVolume(store.get('volume', 1));
  try {
    await load();
  } catch (e) {
    statusLine.textContent = `Discothèque illisible : ${e.message}`;
    return;
  }
  // Reprise de la dernière écoute, en pause.
  player.queue = store.get('queue', []).filter((id) => state.trackById.has(id));
  player.index = Math.min(store.get('index', 0), player.queue.length - 1);
  player.shuffle = store.get('shuffle', false);
  player.repeat = store.get('repeat', 'off');
  if (current()) {
    showNow(current());
    $('#elapsed').textContent = fmtTime(store.get('time', 0));
  }
  updateButtons();
  route();
})();
