'use strict';

// C411 TV : la vidéothèque de C411 Remote dans le navigateur.
// Catalogue : /api/library ; lecture : /api/play/<fichier> dit s'il faut lire
// le fichier tel quel (/media, avance rapide native) ou converti à la volée
// (/stream?t=…, l'avance rapide relance la conversion à la bonne position).

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
}[c]));
const icon = {
  play: '<svg viewBox="0 0 24 24"><path d="M8 5.1v13.8a1 1 0 0 0 1.5.86l11-6.9a1 1 0 0 0 0-1.72l-11-6.9A1 1 0 0 0 8 5.1Z"/></svg>',
  pause: '<svg viewBox="0 0 24 24"><path d="M7 5h4v14H7zm6 0h4v14h-4z"/></svg>',
  info: '<svg viewBox="0 0 24 24"><path d="M11 10h2v7h-2zm0-3h2v2h-2zm1-5a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16Z"/></svg>',
  close: '<svg viewBox="0 0 24 24"><path d="m18.3 7.1-1.4-1.4L12 10.6 7.1 5.7 5.7 7.1l4.9 4.9-4.9 4.9 1.4 1.4 4.9-4.9 4.9 4.9 1.4-1.4-4.9-4.9z"/></svg>',
};

const state = { titles: [], byId: new Map(), fileOwner: new Map(), view: 'home', sort: 'added', query: '', all: false, art: false, badges: true, noArt: new Set() };

/** Titres reconnus par TMDB : les autres (fichiers épars, vidéos de jeux…)
 * ne sont montrés que sur demande, ou par la recherche. */
const known = (t) => t.tmdbId != null;

// ---------------------------------------------------------------------------
// Positions de lecture (dans ce navigateur)

const POS = 'c411tv.pos.';
const progress = {
  get(fileId) {
    try { return JSON.parse(localStorage.getItem(POS + fileId)) || null; } catch { return null; }
  },
  set(fileId, t, d) {
    try { localStorage.setItem(POS + fileId, JSON.stringify({ t, d, at: Date.now() })); } catch { /* stockage indisponible */ }
  },
  clear(fileId) {
    try { localStorage.removeItem(POS + fileId); } catch { /* idem */ }
  },
  /** Fichiers commencés et pas finis, du plus récent au plus ancien. */
  resumable() {
    const out = [];
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (!key.startsWith(POS)) continue;
        const p = JSON.parse(localStorage.getItem(key));
        if (p && p.d && p.t > 30 && p.t < p.d * 0.93) out.push({ fileId: key.slice(POS.length), ...p });
      }
    } catch { /* idem */ }
    return out.sort((a, b) => b.at - a.at);
  },
};

// ---------------------------------------------------------------------------
// Catalogue

async function load() {
  const res = await fetch('api/library');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  state.titles = data.titles;
  state.art = Boolean(data.art);
  // « NOUVEAU » : seulement si la nouveauté distingue quelque chose (pas
  // après une reconstruction de la base, où tout paraît récent).
  const recent = data.titles.filter((t) => t.tmdbId != null && Date.now() - (Date.parse(t.added) || 0) < 7 * 864e5);
  state.badges = recent.length <= Math.max(10, data.titles.filter((t) => t.tmdbId != null).length * 0.2);
  state.byId = new Map(data.titles.map((t) => [t.id, t]));
  state.fileOwner = new Map();
  for (const t of data.titles) for (const f of t.files) state.fileOwner.set(f.id, t);
}

const yearOf = (t) => t.year ? String(t.year) : '';
const addedOf = (t) => t.added ? Date.parse(t.added) : 0;
const isNew = (t) => state.badges && Date.now() - addedOf(t) < 7 * 864e5;
const seasons = (t) => [...new Set(t.files.map((f) => f.season ?? 0))].sort((a, b) => a - b);
const fmtSize = (b) => {
  const u = ['o', 'Ko', 'Mo', 'Go', 'To'];
  let i = 0;
  while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
  return `${b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1).replace('.', ',')} ${u[i]}`;
};
const fmtTime = (s) => {
  s = Math.max(0, Math.floor(s || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}` : `${m}:${String(sec).padStart(2, '0')}`;
};
const episodeLabel = (f) => f.episode != null
  ? `S${String(f.season ?? 1).padStart(2, '0')}E${String(f.episode).padStart(2, '0')}` : '';
const artUrl = (t) => state.art && t.tmdbId && !state.noArt.has(t.id) ? `api/art/${t.type}/${t.tmdbId}` : null;
/** Affiche en plus grand (TMDB : w500 → w780) pour les grandes surfaces. */
const bigPoster = (url) => url ? url.replace('/w500/', '/w780/') : url;

// ---------------------------------------------------------------------------
// Rendu

function card(t, extra = {}) {
  const p = extra.progress;
  const sub = [t.type === 'tv' ? `${seasons(t).length} saison${seasons(t).length > 1 ? 's' : ''}` : yearOf(t),
    t.rating ? `★ ${t.rating.toFixed(1)}` : ''].filter(Boolean).join(' · ');
  return `<button class="card" data-title="${esc(t.id)}"${extra.file ? ` data-file="${esc(extra.file)}"` : ''}>
    <div class="art">
      ${t.poster ? `<img loading="lazy" src="${esc(t.poster)}" alt="">` : `<div class="fallback">${esc(t.title)}</div>`}
      ${isNew(t) && !p ? '<span class="tag new">NOUVEAU</span>' : ''}
      ${p ? `<div class="progress"><span style="width:${Math.min(100, (p.t / p.d) * 100).toFixed(1)}%"></span></div>` : ''}
    </div>
    <div class="label">${esc(t.title)}</div>
    <div class="sub">${esc(extra.sub ?? sub)}</div>
  </button>`;
}

function row(title, items, count) {
  if (!items.length) return '';
  return `<section class="row">
    <h2>${esc(title)}${count ? `<small>${count}</small>` : ''}</h2>
    <button class="arrow left" aria-label="Précédent">‹</button>
    <div class="track">${items.join('')}</div>
    <button class="arrow right" aria-label="Suivant">›</button>
  </section>`;
}

function renderHero(t) {
  const hero = $('#hero');
  if (!t) { hero.hidden = true; return; }
  hero.hidden = false;
  const art = artUrl(t);
  const poster = bigPoster(t.poster);
  hero.classList.toggle('poster-only', !art);
  hero.style.backgroundImage = art ? `url("${art}")` : '';
  hero.innerHTML = `${!art && poster ? `<div class="blur" style="background-image:url('${esc(poster)}')"></div>
    <img class="hero-poster" src="${esc(poster)}" alt="">` : ''}
  <div class="hero-body">
    <h1>${esc(t.title)}</h1>
    <div class="meta">
      ${t.year ? `<span>${t.year}</span>` : ''}
      ${t.rating ? `<span class="rating">★ ${t.rating.toFixed(1)}</span>` : ''}
      <span class="badge">${t.type === 'tv' ? 'SÉRIE' : 'FILM'}</span>
    </div>
    ${t.overview ? `<p>${esc(t.overview)}</p>` : '<p></p>'}
    <div class="actions">
      <button class="btn btn-play" data-play-title="${esc(t.id)}">${icon.play} Lecture</button>
      <button class="btn btn-info" data-title="${esc(t.id)}">${icon.info} Plus d'infos</button>
    </div>
  </div>`;
  // Pas d'image de fond pour ce titre : affiche floutée et nette.
  if (art) {
    const img = new Image();
    img.onerror = () => { state.noArt.add(t.id); renderHero(t); };
    if (!state.noArt.has(t.id)) img.src = art; else img.onerror();
  }
}

function renderHome() {
  const all = state.titles.filter(known);
  const recent = [...all].sort((a, b) => addedOf(b) - addedOf(a));
  const movies = recent.filter((t) => t.type === 'movie');
  const series = recent.filter((t) => t.type === 'tv');
  const rated = all.filter((t) => t.rating && t.poster).sort((a, b) => b.rating - a.rating);

  const resume = [];
  const seen = new Set();
  for (const p of progress.resumable()) {
    const t = state.fileOwner.get(p.fileId);
    if (!t || seen.has(t.id)) continue;
    seen.add(t.id);
    const f = t.files.find((x) => x.id === p.fileId);
    resume.push(card(t, { file: p.fileId, progress: p, sub: `${episodeLabel(f)} · reste ${fmtTime(p.d - p.t)}`.replace(/^ · /, '') }));
  }

  const pool = recent.filter((t) => t.poster && t.overview).slice(0, 12);
  renderHero(pool[Math.floor(Math.random() * pool.length)] || recent[0]);
  $('#content').innerHTML = [
    row('Reprendre', resume),
    row('Ajoutés récemment', recent.slice(0, 30).map((t) => card(t))),
    row('Films', movies.slice(0, 40).map((t) => card(t)), movies.length),
    row('Séries', series.slice(0, 40).map((t) => card(t)), series.length),
    row('Les mieux notés', rated.slice(0, 30).map((t) => card(t))),
  ].join('');
}

function renderGrid() {
  $('#hero').hidden = true;
  const q = state.query.trim().toLowerCase();
  const inView = state.titles.filter((t) => state.view === 'search' || t.type === state.view);
  const hidden = state.view === 'search' ? 0 : inView.filter((t) => !known(t)).length;
  let list = inView.filter((t) => (state.view === 'search' || state.all || known(t))
    && (!q || t.title.toLowerCase().includes(q) || t.files.some((f) => f.name.toLowerCase().includes(q))));
  const sorts = { added: (a, b) => addedOf(b) - addedOf(a), title: (a, b) => a.title.localeCompare(b.title, 'fr'), rating: (a, b) => (b.rating || 0) - (a.rating || 0) };
  list = list.sort(sorts[state.sort]);
  const heading = state.view === 'search' ? `Résultats pour « ${state.query.trim()} »` : state.view === 'tv' ? 'Séries' : 'Films';
  $('#content').innerHTML = `<div class="grid-head">
      <h1>${esc(heading)}</h1><span class="count">${list.length}</span>
      <div class="sorts">
        ${hidden ? `<button class="chip${state.all ? ' on' : ''}" data-all>Tout afficher (+${hidden} sans fiche)</button>` : ''}
        ${[['added', 'Récents'], ['title', 'A → Z'], ['rating', 'Mieux notés']].map(([k, l]) =>
          `<button class="chip${state.sort === k ? ' on' : ''}" data-sort="${k}">${l}</button>`).join('')}
      </div>
    </div>
    <div class="grid">${list.map((t) => card(t)).join('') || '<p class="status">Rien ne correspond.</p>'}</div>`;
}

// Liens directs : #films, #series, #t=<titre>.
const VIEW_HASH = { home: '', movie: '#films', tv: '#series' };
function syncHash(titleId) {
  const hash = titleId ? `#t=${titleId}` : (VIEW_HASH[state.view] ?? '');
  if (location.hash !== hash) history.replaceState(null, '', hash || location.pathname);
}
function fromHash() {
  const h = location.hash;
  if (h.startsWith('#t=')) {
    const t = state.byId.get(h.slice(3));
    if (t) { state.view = t.type; render(); openDetail(t); return; }
  }
  state.view = h === '#films' ? 'movie' : h === '#series' ? 'tv' : 'home';
  render();
}

function render() {
  syncHash();
  for (const a of document.querySelectorAll('.nav a')) a.classList.toggle('active', a.dataset.view === state.view);
  if (state.view === 'home') renderHome(); else renderGrid();
  $('#status').hidden = state.titles.length > 0;
  if (!state.titles.length) $('#status').textContent = 'La vidéothèque est vide : lance un parcours dans l’application.';
}

// ---------------------------------------------------------------------------
// Fiche

function openDetail(t, season) {
  const sheet = $('#detail .sheet');
  const art = artUrl(t);
  const isSeries = t.type === 'tv';
  const all = seasons(t);
  season ??= (() => {
    const last = progress.resumable().find((p) => state.fileOwner.get(p.fileId) === t);
    return last ? t.files.find((f) => f.id === last.fileId).season ?? all[0] : all[0];
  })();
  const files = isSeries ? t.files.filter((f) => (f.season ?? 0) === season) : t.files;

  const item = (f, i) => {
    const p = progress.get(f.id);
    const name = isSeries
      ? (f.episode != null ? `Épisode ${f.episode}` : f.name)
      : (t.files.length > 1 ? `Version ${i + 1}` : t.title);
    const details = [isSeries ? episodeLabel(f) : '', f.resolution, f.source, f.codec, fmtSize(f.size)].filter(Boolean).join(' · ');
    return `<div class="item" data-play="${esc(f.id)}" tabindex="0">
      <div class="num">${isSeries && f.episode != null ? f.episode : i + 1}</div>
      <div>
        <div class="name">${esc(name)}</div>
        <div class="details">${esc(details)}</div>
        <div class="details">${esc(f.name)}</div>
        ${p && p.d ? `<div class="progress"><span style="width:${Math.min(100, (p.t / p.d) * 100).toFixed(1)}%"></span></div>` : ''}
      </div>
      <div class="play-dot">${icon.play}</div>
    </div>`;
  };

  sheet.innerHTML = `
    <button class="close" data-close aria-label="Fermer">${icon.close}</button>
    <div class="sheet-head${art ? '' : ' poster-only'}" style="${art ? `background-image:url('${esc(art)}')` : ''}">
      ${!art && t.poster ? `<div class="blur" style="background-image:url('${esc(bigPoster(t.poster))}')"></div>` : ''}
      <div class="head-body">
        <h2 id="detail-title">${esc(t.title)}</h2>
        <div class="actions"><button class="btn btn-play" data-play-title="${esc(t.id)}">${icon.play} ${resumeLabel(t)}</button></div>
      </div>
    </div>
    <div class="sheet-body">
      <div>
        <div class="meta" style="margin-bottom:12px">
          ${t.year ? `<span>${t.year}</span>` : ''}
          ${t.rating ? `<span class="rating">★ ${t.rating.toFixed(1)}</span>` : ''}
          <span class="badge">${isSeries ? 'SÉRIE' : 'FILM'}</span>
          <span>${isSeries ? `${t.files.length} épisode${t.files.length > 1 ? 's' : ''}` : fmtSize(t.files[0].size)}</span>
        </div>
        <p class="overview">${esc(t.overview || 'Pas de résumé.')}</p>
      </div>
      <aside>${t.poster ? `<img src="${esc(t.poster)}" alt="">` : ''}</aside>
      <div class="items">
        <div class="section-title">
          <h3>${isSeries ? 'Épisodes' : t.files.length > 1 ? 'Versions' : 'Fichier'}</h3>
          ${isSeries && all.length > 1 ? `<select id="season">${all.map((s) =>
            `<option value="${s}"${s === season ? ' selected' : ''}>${s ? `Saison ${s}` : 'Autres'}</option>`).join('')}</select>` : ''}
        </div>
        ${files.map(item).join('')}
      </div>
    </div>`;
  const select = $('#season', sheet);
  if (select) select.onchange = () => openDetail(t, Number(select.value));
  $('#detail').hidden = false;
  document.body.classList.add('locked');
  $('#detail').dataset.title = t.id;
  syncHash(t.id);
}

function closeDetail() {
  $('#detail').hidden = true;
  document.body.classList.remove('locked');
  syncHash();
}

/** Le fichier à lancer pour un titre : celui en cours, sinon le premier. */
function nextFileOf(t) {
  const started = progress.resumable().find((p) => state.fileOwner.get(p.fileId) === t);
  return started ? started.fileId : t.files[0].id;
}
const resumeLabel = (t) => progress.resumable().some((p) => state.fileOwner.get(p.fileId) === t) ? 'Reprendre' : 'Lecture';

// ---------------------------------------------------------------------------
// Lecteur

/**
 * Comment lire un fichier, d'après ce que CE navigateur sait décoder :
 * - direct : le fichier tel quel (MKV compris), si la vidéo et la piste audio
 *   voulue se lisent, et que cette piste est celle que le navigateur jouera ;
 * - stream + copy : ffmpeg copie la vidéo (le navigateur la décode) et ne
 *   convertit que l'audio — quasiment sans calcul ;
 * - stream : vidéo réencodée en H.264 (le navigateur ne la décode pas).
 */
function choose(info, audioIndex) {
  const probe = document.createElement('video');
  const can = (mime) => Boolean(mime) && probe.canPlayType(mime) !== '';
  const video = can(info.videoMime);
  const track = (info.audio || []).find((a) => a.index === audioIndex);
  const audio = !track || can(track.mime);
  const sameTrack = !track || track.index === info.browserAudio;
  const container = /mp4|mov|matroska|webm/.test(info.container || '');
  if (container && video && audio && sameTrack) return { mode: 'direct', copy: false };
  return { mode: 'stream', copy: video };
}

const player = {
  el: $('#player'), video: $('#video'),
  file: null, title: null, info: null,
  mode: 'direct', copy: false, offset: 0, duration: 0, audio: null, stallTimer: 0,
  idleTimer: 0, saveTimer: 0, dragging: false,

  async open(fileId) {
    const t = state.fileOwner.get(fileId);
    const f = t?.files.find((x) => x.id === fileId);
    if (!f) return;
    closeDetail();
    this.file = f; this.title = t;
    this.el.hidden = false;
    document.body.classList.add('locked');
    $('#player-title').textContent = t.title;
    $('#player-sub').textContent = [episodeLabel(f), f.resolution].filter(Boolean).join(' · ');
    $('#player-error').hidden = true;
    $('#player-spinner').hidden = false;
    this.video.removeAttribute('src');
    this.video.load();

    let info;
    try {
      const res = await fetch(`api/play/${encodeURIComponent(fileId)}`);
      info = await res.json();
      if (!res.ok || info.error) throw new Error(info.error || `HTTP ${res.status}`);
    } catch (e) {
      return this.fail(`Impossible de préparer la lecture : ${e.message}`);
    }
    if (this.file !== f) return; // Autre fichier entre-temps.
    this.info = info;
    this.duration = info.duration || 0;
    this.audio = info.preferredAudio ?? null;
    ({ mode: this.mode, copy: this.copy } = info.videoMime === undefined
      ? { mode: info.mode, copy: false } // Serveur sans ffprobe : son avis.
      : choose(info, this.audio));

    const audio = $('#audio');
    const tracks = info.audio || [];
    audio.hidden = tracks.length < 2;
    audio.innerHTML = tracks.map((a) => `<option value="${a.index}"${a.index === this.audio ? ' selected' : ''}>${esc(
      [a.language ? a.language.toUpperCase() : `Piste ${a.index}`, a.title, a.codec?.toUpperCase(), a.channels > 2 ? `${a.channels} canaux` : ''].filter(Boolean).join(' · '))}</option>`).join('');

    const next = this.nextEpisode();
    $('#next-episode').hidden = !next;

    const saved = progress.get(f.id);
    const start = saved && saved.t > 30 && (!saved.d || saved.t < saved.d * 0.95) ? saved.t : 0;
    this.load(start);
    this.poke();
  },

  /** Charge la vidéo à partir de [at] secondes. */
  load(at) {
    const v = this.video;
    $('#player-spinner').hidden = false;
    clearTimeout(this.stallTimer);
    if (this.mode === 'stream') {
      this.offset = at;
      const params = new URLSearchParams({ t: at.toFixed(1) });
      if (this.audio != null) params.set('audio', this.audio);
      if (this.copy) params.set('copy', '1');
      v.src = `${this.info.streamUrl || this.info.url}?${params}`;
    } else {
      this.offset = 0;
      const url = this.info.directUrl || this.info.url;
      if (!v.src.endsWith(url)) v.src = url;
      v.addEventListener('loadedmetadata', () => {
        // Conteneur lu mais image non décodée : on passe par ffmpeg.
        if (this.mode === 'direct' && v.videoWidth === 0) return this.fallback(at);
        v.currentTime = at;
      }, { once: true });
      // Rien au bout de 20 s : le navigateur cale sur ce fichier.
      this.stallTimer = setTimeout(() => {
        if (this.file && this.mode === 'direct' && v.readyState < 2) this.fallback(at);
      }, 20000);
    }
    v.play().catch(() => { /* lecture auto refusée : le bouton reste */ });
  },

  /** La lecture directe a échoué : conversion à la volée, même position. */
  fallback(at) {
    if (this.mode !== 'direct' || !this.info.streamUrl) return false;
    this.mode = 'stream';
    this.copy = false;
    this.load(at ?? this.now());
    return true;
  },

  now() { return this.offset + (this.video.currentTime || 0); },
  total() { return this.duration || (Number.isFinite(this.video.duration) ? this.video.duration : 0); },

  seek(at) {
    at = Math.max(0, Math.min(at, this.total() || at));
    if (this.mode === 'stream') this.load(at);
    else this.video.currentTime = at;
  },

  nextEpisode() {
    const t = this.title, f = this.file;
    if (!t || t.type !== 'tv') return null;
    const i = t.files.indexOf(f);
    return i >= 0 && i < t.files.length - 1 ? t.files[i + 1] : null;
  },

  save() {
    if (!this.file) return;
    const t = this.now(), d = this.total();
    if (!d) return;
    if (t > d * 0.95) progress.clear(this.file.id); else if (t > 5) progress.set(this.file.id, t, d);
  },

  close() {
    clearTimeout(this.stallTimer);
    this.save();
    this.video.pause();
    this.video.removeAttribute('src');
    this.video.load(); // Coupe la connexion : le serveur arrête ffmpeg.
    this.el.hidden = true;
    this.file = null;
    document.body.classList.remove('locked');
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    render();
  },

  fail(message) {
    $('#player-spinner').hidden = true;
    const err = $('#player-error');
    err.textContent = message;
    err.hidden = false;
  },

  update() {
    const t = this.now(), d = this.total();
    $('#time').textContent = `${fmtTime(t)} / ${fmtTime(d)}`;
    if (!this.dragging && d) {
      const seek = $('#seek');
      seek.value = String(Math.round((t / d) * 1000));
      seek.style.setProperty('--p', `${(t / d) * 100}%`);
    }
    $('#play').innerHTML = this.video.paused ? icon.play : icon.pause;
  },

  /** Commandes visibles, puis masquées après 3 s sans mouvement. */
  poke() {
    this.el.classList.remove('idle');
    clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => { if (!this.video.paused) this.el.classList.add('idle'); }, 3000);
  },
};

function bindPlayer() {
  const v = player.video;
  v.addEventListener('timeupdate', () => player.update());
  v.addEventListener('play', () => player.update());
  v.addEventListener('pause', () => { player.update(); player.poke(); });
  v.addEventListener('waiting', () => { $('#player-spinner').hidden = false; });
  v.addEventListener('playing', () => { $('#player-spinner').hidden = true; });
  v.addEventListener('canplay', () => { $('#player-spinner').hidden = true; });
  v.addEventListener('error', () => {
    if (!player.file || !v.getAttribute('src')) return;
    if (player.mode === 'direct' && player.fallback(player.now())) return;
    // Vidéo copiée mais finalement pas décodée : réencodage complet.
    if (player.mode === 'stream' && player.copy) {
      player.copy = false;
      return player.load(player.now());
    }
    player.fail('Lecture impossible, même convertie (ffmpeg).');
  });
  v.addEventListener('ended', () => {
    // En conversion, « ended » peut venir d'une coupure : on ne passe à la
    // suite qu'en fin de fichier.
    if (player.total() && player.now() < player.total() - 20) return;
    progress.clear(player.file.id);
    const next = player.nextEpisode();
    if (next) player.open(next.id); else player.close();
  });
  setInterval(() => { if (player.file && !v.paused) player.save(); }, 5000);

  $('#play').onclick = () => (v.paused ? v.play() : v.pause());
  $('#back10').onclick = () => player.seek(player.now() - 10);
  $('#fwd10').onclick = () => player.seek(player.now() + 10);
  $('#player-back').onclick = () => player.close();
  $('#next-episode').onclick = () => { const n = player.nextEpisode(); if (n) { player.save(); player.open(n.id); } };
  $('#fullscreen').onclick = () => (document.fullscreenElement
    ? document.exitFullscreen() : player.el.requestFullscreen()).catch(() => {});
  $('#audio').onchange = (e) => {
    // Une autre piste : en lecture directe, le navigateur ne sait jouer que
    // celle par défaut ; on choisit à nouveau (souvent : vidéo copiée).
    const at = player.now();
    player.audio = Number(e.target.value);
    ({ mode: player.mode, copy: player.copy } = choose(player.info, player.audio));
    player.load(at);
  };
  v.onclick = () => (v.paused ? v.play() : v.pause());
  v.ondblclick = () => $('#fullscreen').click();

  const seek = $('#seek');
  seek.oninput = () => {
    player.dragging = true;
    const d = player.total();
    seek.style.setProperty('--p', `${seek.value / 10}%`);
    $('#time').textContent = `${fmtTime((seek.value / 1000) * d)} / ${fmtTime(d)}`;
  };
  seek.onchange = () => { player.dragging = false; player.seek((seek.value / 1000) * player.total()); };

  player.el.addEventListener('mousemove', () => player.poke());
  player.el.addEventListener('touchstart', () => player.poke(), { passive: true });
  document.addEventListener('keydown', (e) => {
    if (player.el.hidden) {
      if (e.key === 'Escape' && !$('#detail').hidden) closeDetail();
      return;
    }
    if (e.target.tagName === 'SELECT') return;
    const keys = {
      ' ': () => (v.paused ? v.play() : v.pause()), k: () => (v.paused ? v.play() : v.pause()),
      ArrowLeft: () => player.seek(player.now() - 10), ArrowRight: () => player.seek(player.now() + 10),
      f: () => $('#fullscreen').click(), Escape: () => { if (!document.fullscreenElement) player.close(); },
    };
    if (keys[e.key]) { e.preventDefault(); keys[e.key](); player.poke(); }
  });
}

// ---------------------------------------------------------------------------
// Navigation

function bind() {
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-view],[data-title],[data-play],[data-play-title],[data-close],[data-sort],[data-all],.arrow');
    if (!el) return;
    if (el.matches('.arrow')) {
      const track = el.parentElement.querySelector('.track');
      track.scrollBy({ left: (el.classList.contains('left') ? -1 : 1) * track.clientWidth * 0.85, behavior: 'smooth' });
    } else if (el.dataset.view) {
      e.preventDefault();
      state.view = el.dataset.view; state.query = ''; $('#search').value = '';
      render(); window.scrollTo(0, 0);
    } else if (el.dataset.close !== undefined) {
      closeDetail();
    } else if (el.dataset.play) {
      player.open(el.dataset.play);
    } else if (el.dataset.playTitle) {
      const t = state.byId.get(el.dataset.playTitle);
      if (t) player.open(nextFileOf(t));
    } else if (el.dataset.all !== undefined) {
      state.all = !state.all; renderGrid();
    } else if (el.dataset.sort) {
      state.sort = el.dataset.sort; renderGrid();
    } else if (el.dataset.file) {
      player.open(el.dataset.file); // Carte « Reprendre ».
    } else if (el.dataset.title) {
      const t = state.byId.get(el.dataset.title);
      if (t) openDetail(t);
    }
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && e.target.matches('.item[data-play]')) player.open(e.target.dataset.play);
  });
  let timer = 0;
  $('#search').addEventListener('input', (e) => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      state.query = e.target.value;
      state.view = state.query.trim() ? 'search' : 'home';
      render();
    }, 150);
  });
  const bar = $('#topbar');
  window.addEventListener('scroll', () => bar.classList.toggle('solid', window.scrollY > 40), { passive: true });
}

(async function main() {
  bind();
  bindPlayer();
  try {
    await load();
  } catch (e) {
    $('#status').textContent = `Vidéothèque indisponible : ${e.message}`;
    return;
  }
  fromHash();
  window.addEventListener('hashchange', fromHash);
})();
