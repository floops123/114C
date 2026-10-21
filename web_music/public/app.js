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
  play: '<svg viewBox="0 0 24 24"><path d="M8 5.1v13.8a1 1 0 0 0 1.5.86l11-6.9a1 1 0 0 0 0-1.72l-11-6.9A1 1 0 0 0 8 5.1Z"/></svg>',
  pause: '<svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zm6 0h4v14h-4z"/></svg>',
  shuffle: '<svg viewBox="0 0 24 24"><path d="M10.6 9.2 5.4 4 4 5.4l5.2 5.2 1.4-1.4ZM14.5 4l2 2L4 18.6 5.4 20 18 7.5l2 2V4h-5.5Zm.3 9.4-1.4 1.4 3.1 3.1L14.5 20H20v-5.5l-2 2-3.2-3.1Z"/></svg>',
  repeat: '<svg viewBox="0 0 24 24"><path d="M7 7h10v3l4-4-4-4v3H5v6h2V7Zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4Z"/></svg>',
  repeatOne: '<svg viewBox="0 0 24 24"><path d="M7 7h10v3l4-4-4-4v3H5v6h2V7Zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4Zm-4-2V9h-1l-2 1v1h1.5v4H13Z"/></svg>',
  volume: '<svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3Zm13.5 3A4.5 4.5 0 0 0 14 8v8a4.5 4.5 0 0 0 2.5-4ZM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6Z"/></svg>',
  muted: '<svg viewBox="0 0 24 24"><path d="M16.5 12A4.5 4.5 0 0 0 14 8v2.2l2.45 2.45c.03-.2.05-.43.05-.65Zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51A8.8 8.8 0 0 0 21 12a9 9 0 0 0-7-8.8v2.1A7 7 0 0 1 19 12ZM4.27 3 3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25A7 7 0 0 1 14 18.7v2.1a9 9 0 0 0 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3ZM12 4 9.91 6.09 12 8.18V4Z"/></svg>',
};
const eq = '<span class="eq"><i></i><i></i><i></i></span>';

const state = {
  albums: [], artists: [], albumById: new Map(), artistById: new Map(), trackById: new Map(),
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

// ---------------------------------------------------------------------------
// Discothèque

async function load() {
  const res = await fetch('api/library');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  state.albums = data.albums;
  state.artists = data.artists;
  state.status = data.status || {};
  state.albumById = new Map(data.albums.map((a) => [a.id, a]));
  state.artistById = new Map(data.artists.map((a) => [a.id, a]));
  state.trackById = new Map();
  for (const a of data.albums) for (const t of a.tracks) state.trackById.set(t.id, { ...t, album: a });
  // « NOUVEAU » : seulement si la nouveauté distingue quelque chose (pas
  // après un premier parcours, où tout paraît récent).
  const recent = data.albums.filter((a) => isRecent(a));
  state.badges = recent.length <= Math.max(8, data.albums.length * 0.2);
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
  return `<a class="card" href="#album=${a.id}">${cover(a, { badge: true })}
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
  const recent = recentAlbums();
  const genres = genresOf(albums).slice(0, 5);
  const artists = [...state.artists].sort((a, b) => b.albums.length - a.albums.length).slice(0, 24);
  content.innerHTML = hero(featured, 'À la une') +
    row('Écoutés récemment', recent.slice(0, 20), albumCard) +
    row('Ajoutés récemment', byAdded.slice(0, 24), albumCard, '#albums') +
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
      <div class="actions">
        <button class="btn primary" data-play-album="${a.id}">${icon.play}Écouter</button>
        <button class="btn" data-shuffle-album="${a.id}">${icon.shuffle}Aléatoire</button>
        ${eyebrow === 'À la une' ? `<a class="btn" href="#album=${a.id}">Voir l'album</a>` : ''}
      </div></div></section>`;
}

const sorts = {
  added: ['Ajout récent', (a, b) => addedOf(b) - addedOf(a)],
  title: ['Titre', (a, b) => fold(a.title).localeCompare(fold(b.title))],
  artist: ['Artiste', (a, b) => fold(a.artist).localeCompare(fold(b.artist)) || (a.year || 0) - (b.year || 0)],
  year: ['Année', (a, b) => (b.year || 0) - (a.year || 0)],
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
  setNav('');
  statusLine.textContent = '';
  const discs = [...new Set(a.tracks.map((t) => t.disc))];
  const eyebrow = [typeLabel[a.type] || 'Album', a.label, a.country].filter(Boolean).join(' · ');
  content.innerHTML = hero(a, eyebrow).replace('class="hero"', 'class="hero album-head"') +
    `<div class="tracks">${discs.map((d) => `${discs.length > 1 ? `<div class="disc">Disque ${d}</div>` : ''}${
      a.tracks.filter((t) => t.disc === d).map((t) => `<div class="track" data-track="${t.id}" data-album="${a.id}">
        <span class="num"><span class="n">${t.number ?? '·'}</span>${eq}</span>
        <span><div class="t-title">${esc(t.title)}</div>${t.artist ? `<div class="t-artist">${esc(t.artist)}</div>` : ''}</span>
        <span class="fmt">${esc(t.format)}</span>
        <span class="dur">${t.duration ? fmtTime(t.duration) : ''}</span></div>`).join('')}`).join('')}</div>
    <p class="notes">${a.mbid
      ? `Fiche <a href="https://musicbrainz.org/release/${a.mbid}" target="_blank" rel="noopener">MusicBrainz</a>, pochette Cover Art Archive. `
      : 'Album non reconnu par MusicBrainz : titres et ordre d’après les noms de fichiers. '}
      <button class="link-btn" data-identify="${a.id}">Chercher à nouveau sur MusicBrainz</button></p>`;
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
  const artists = state.artists.filter((a) => fold(a.name).includes(q));
  const tracks = [...state.trackById.values()].filter((t) => fold(t.title).includes(q)).slice(0, 50);
  statusLine.textContent = albums.length + artists.length + tracks.length ? '' : `Rien pour « ${query} ».`;
  content.innerHTML = (artists.length ? `<div class="page-head"><h1>Artistes</h1></div><div class="grid">${artists.slice(0, 12).map(artistCard).join('')}</div>` : '') +
    (albums.length ? `<div class="page-head"><h1>Albums</h1></div><div class="grid">${albums.map(albumCard).join('')}</div>` : '') +
    (tracks.length ? `<div class="page-head"><h1>Titres</h1></div><div class="tracks">${tracks.map((t) => `<div class="track" data-track="${t.id}" data-album="${t.album.id}">
      <span class="num"><span class="n">${t.number ?? '·'}</span>${eq}</span>
      <span><div class="t-title">${esc(t.title)}</div><div class="t-artist">${esc(t.album.artist)} · ${esc(t.album.title)}</div></span>
      <span class="fmt">${esc(t.format)}</span><span class="dur">${t.duration ? fmtTime(t.duration) : ''}</span></div>`).join('')}</div>` : '');
  markCurrent();
}

function notFound() {
  content.innerHTML = '';
  statusLine.textContent = 'Introuvable : la discothèque a peut-être changé.';
}

/** Routes : #albums, #albums&genre=…, #artists, #album=<id>, #artist=<id>. */
function route() {
  const hash = decodeURIComponent(location.hash.slice(1));
  const query = $('#search').value.trim();
  if (query && !hash) return renderSearch(query);
  const params = new URLSearchParams(hash.replace(/^[^&=]+(?=&|$)/, (v) => `view=${v}`));
  if (params.has('album')) renderAlbum(params.get('album'));
  else if (params.has('artist')) renderArtist(params.get('artist'));
  else if (params.get('view') === 'albums') renderAlbums(params.get('genre'));
  else if (params.get('view') === 'artists') renderArtists();
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

/** Joue [ids] à partir de [start] ; aléatoire si demandé. */
function playList(ids, start = 0, shuffle = player.shuffle) {
  if (!ids.length) return;
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

const albumTrackIds = (id) => state.albumById.get(id)?.tracks.map((t) => t.id) || [];
function artistTrackIds(id) {
  const artist = state.artistById.get(id);
  return artist ? artist.albums.flatMap(albumTrackIds) : [];
}

async function playAt(index, { time = 0, autoplay = true } = {}) {
  if (index < 0 || index >= player.queue.length) return;
  player.index = index;
  const t = current();
  if (!t) return;
  rememberAlbum(t.album.id);
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
  if (!audio.src) return playAt(player.index, { time: store.get('time', 0) });
  if (audio.paused) audio.play(); else audio.pause();
}

audio.addEventListener('ended', () => next(true));
audio.addEventListener('play', updateButtons);
audio.addEventListener('pause', updateButtons);
audio.addEventListener('waiting', () => { $('#spinner').hidden = false; });
audio.addEventListener('playing', () => { $('#spinner').hidden = true; });
audio.addEventListener('canplay', () => { $('#spinner').hidden = true; });
audio.addEventListener('error', () => {
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
  if (!player.seeking) {
    const d = duration();
    const seek = $('#seek');
    seek.value = d ? Math.round((position() / d) * 1000) : 0;
    seek.style.setProperty('--pos', `${seek.value / 10}%`);
  }
  $('#elapsed').textContent = fmtTime(position());
  $('#total').textContent = fmtTime(duration());
  if (Date.now() - saved > 5000) { saved = Date.now(); store.set('time', position()); }
  if ('mediaSession' in navigator && duration() && navigator.mediaSession.setPositionState) {
    try { navigator.mediaSession.setPositionState({ duration: duration(), position: Math.min(position(), duration()), playbackRate: 1 }); } catch { /* valeurs refusées */ }
  }
});

function showNow(t) {
  $('#player').hidden = false;
  $('#now-title').textContent = t.title;
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
    return `<li class="${cls}" data-queue="${i}">${cover(t.album)}<span><div class="q-title">${esc(t.title)}</div><div class="q-sub">${esc(t.artist || t.album.artist)}</div></span><span class="dur">${t.duration ? fmtTime(t.duration) : ''}</span></li>`;
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
  const li = e.target.closest('[data-queue]');
  if (li) playAt(Number(li.dataset.queue));
});

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
  const el = e.target.closest('[data-play-album],[data-shuffle-album],[data-play-artist],[data-shuffle-artist],[data-track],[data-genre],[data-identify]');
  if (!el) return;
  const d = el.dataset;
  if (d.playAlbum || d.shuffleAlbum || d.playArtist || d.shuffleArtist) e.preventDefault();
  if (d.playAlbum) playList(albumTrackIds(d.playAlbum), 0, false);
  else if (d.shuffleAlbum) playList(albumTrackIds(d.shuffleAlbum), 0, true);
  else if (d.playArtist) playList(artistTrackIds(d.playArtist), 0, false);
  else if (d.shuffleArtist) playList(artistTrackIds(d.shuffleArtist), 0, true);
  else if (d.genre) location.hash = d.genre === state.genre ? 'albums' : `albums&genre=${encodeURIComponent(d.genre)}`;
  else if (d.identify) identify(d.identify);
  else if (d.track) {
    if (d.track === player.queue[player.index] && audio.src) return toggle();
    const ids = $('#search').value.trim() && !location.hash ? [d.track] : albumTrackIds(d.album);
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
    s.step || (s.identifying ? 'Recherche sur MusicBrainz…' : `${s.identified ?? 0} albums sur ${s.albums ?? 0} reconnus par MusicBrainz.`),
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
  toast('Recherche sur MusicBrainz…');
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
