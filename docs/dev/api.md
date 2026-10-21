# Notes sur les API

[← Sommaire](../README.md)

Ce qu'on a appris de chaque service, souvent à force d'essais : endpoints,
formats, pièges. À lire avant de toucher à un client de `lib/api/`.

- [C411 (HTTP)](#c411--api-http)
- [C411 (WebSocket et discussion)](#c411--websocket-et-discussion)
- [Torznab : tr4ker, Nostradamus, Draupnirr](#torznab--tr4ker-nostradamus-draupnirr)
- [Draupnirr (compte, missions)](#draupnirr--compte-missions)
- [AstraTorrent](#astratorrent)
- [Transmission](#transmission)
- [TMDB](#tmdb)
- [Jellyfin](#jellyfin)
- [FTP / FTPS (Appbox)](#ftp--ftps-appbox)
- [Quotas des trackers](#quotas-des-trackers)

---

## C411 : API HTTP

Deux API coexistent, avec **deux modes d'authentification** :

| Usage | Endpoint | Authentification |
|---|---|---|
| Sorties (JSON riche : fiche, technique) | `GET /api/torrents` | `Authorization: Bearer <clé>` |
| Catégories | `GET /api/categories` | Bearer |
| Sorties « palliatives » (sans seeder depuis un certain temps) | `GET /api/torrents?palliative=only&palliativeAge=recent` | cookie de session |
| `.torrent` | `GET /api?t=get&id=<infohash>&apikey=<clé>` | paramètre `apikey` (le Bearer y est refusé) |
| `.torrent` (import en masse, si un cookie est renseigné) | `GET /api/torrents/<infohash>/download` | cookie de session |

Paramètres de `/api/torrents` : `page`, `perPage`, `cat`, `subcat`, `name`
(recherche), `sortBy` (`createdAt`, `seeders`, `leechers`, `completions`,
`size`, `name`, `comments`), `sortOrder` (`asc` / `desc`). `limit` est
ignoré. Réponse : `data[]` et `meta` (`page`, `totalPages`, `total`, compteurs
par catégorie).

Pour la liste palliative, le Bearer ne suffit pas : `c411SiteApiProvider`
envoie `Cookie: …` + `Origin: https://c411.org` (même authentification que
le WebSocket des notifications et que `C411ChatApi`). Paramètres :
`palliative=only` (obligatoire), `palliativeAge=recent` (ou autre valeur
unknown, non documentée), `sortBy=bounty` / `sortOrder=desc` imposés. La
réponse renvoie les mêmes champs que `/api/torrents`, plus
`palliativeSince`, `bountyZen`, `palliativeCountdown` par sortie, et
`meta.palliativeCount` / `palliativeMatches` / `palliativeFallback`.

- `name` cherche une **sous-chaîne du nom de la release** : noms à points,
  sans accents. On cherche donc `Dune.Part.Two`, pas « Dune : Deuxième
  partie ».
- Chaque sortie a une fiche `media` (`kind` : `movie`, `tv`, `music`,
  `game`… ; `title`, `originalTitle`, `year`) et un bloc `tech`
  (`resolution`, `source`, `videoCodec`, `hdrFormat`, `audioCodec`,
  `audioChannels`, `languages`). Les sorties **sans fiche** sont écartées de la
  recherche des souhaits.
- Quota : **120 requêtes / minute** par clé, Torznab compris.

## C411 : WebSocket et discussion

- `wss://c411.org/ws/?EIO=4&transport=websocket` : Socket.IO, transport
  WebSocket uniquement (le polling répond « Transport unknown »).
- En-tête `Origin: https://c411.org` **obligatoire** (sinon fermeture 1006).
- Authentification **par cookie de session uniquement** : la clé API est
  refusée sous toutes ses formes. Sans cookie : `44{"message":"Authentication
  required","data":{"code":"no_cookies"}}` ; cookie inconnu :
  `no_session_cookie`.
- Échanges : `0{…pingInterval…}` → `40` → `40{sid}` (accepté) ou `44{…}`
  (refusé) ; `2` → `3` (ping / pong) ; `42["événement", données]`.

Événements observés :

| Événement | Contenu |
|---|---|
| `unread:update` | compteurs `privateMessages`, `channelMessages`, `pendingRequests`, `staffMessages`, `total` |
| `stats:update` | `uploaded`, `downloaded`, `upload_credit`, `user_id` |
| `channel:message` | message de salon (parfois en double : dédoublonné par `id`) |
| `channel:typing`, `channel:viewers` | « … écrit », personnes en ligne |
| `channel:reaction` | `messageId` et liste complète des réactions (`userIds`, `usernames`, émoticônes `:nom:`) |

- **Salons** : le client émet `42["channel:join",{"channelId":N}]` (et
  `channel:leave`) ; le serveur ne diffuse un salon qu'à ceux qui l'ont
  rejoint. À refaire après chaque reconnexion.
- **Envoi** avec accusé de réception :
  `42<n>["channel:send",{"channelId":1,"content":"…","tempId":"temp-<ms>-<9 car.>"}]`
  → `43<n>[{"success":true,"messageId":…,"tempId":…,"status":"sent"}]`. Le
  message revient aussi en `channel:message` avec le même `tempId`.
- Le contenu est encodé en HTML (`c&#x27;est`) ; `{{pseudo}}` est une mention.
- `GET /api/notifications?offset=N&perPage=M` → `data[]` (`id`, `type`,
  `title`, `message`, `link`, `isRead`, `createdAt`) et `meta` (`hasMore`,
  `unreadCount`).
- `GET /api/messages/channels` (salons) et
  `GET /api/messages/channels/{id}?limit=N` (historique, `pinnedMessage`),
  même cookie. Avatars et images `/uploads/…` sont publics.

## Torznab : tr4ker, Nostradamus, Draupnirr

Client générique `TorznabApi` ([spécification](https://torznab.github.io/spec-1.3-draft/)).

| | tr4ker | Nostradamus | Draupnirr |
|---|---|---|---|
| Endpoint | `https://tr4ker.net/api/` | `https://nostradamus.foo/api` | `https://draupnirr.xyz/torznab/api` |
| Clé | en-tête `X-Api-Key` **et** paramètre `apikey` | paramètre `apikey` | en-tête `X-Api-Key` **et** paramètre `apikey` |
| Limite | 120/min clé | 120/min clé | 120/min clé (300/min IP) |

- tr4ker : `/api` redirige vers `/api/` ; `/api/torznab` est déprécié ; la
  clé est exigée même pour `t=caps` (sinon 401).
- Draupnirr expose aussi un catalogue JSON (`/api/torrents`, avec
  `q`/`category`/limite/décalage) et un endpoint compte (`/api/me`,
  missions, badges, boutique). L'application n'utilise que la passerelle
  Torznab, suffisante pour la recherche et le téléchargement. Les
  téléchargements passent par `/torznab/download/{id}` (le `.torrent` est
  personnalisé avec la clé de l'utilisateur). Deux refus côté serveur :
  ratio sous le plancher (`403 ratio too low`) ou release en quarantaine
  Ratatosk (`403 awaiting media verification`) — l'un comme l'autre
  remontent en `Clé API refusée` par notre wrapper.
- Torznab ne donne ni affiche ni technique : titre, année, résolution, source,
  codec, langues sont lus dans le nom (`ReleaseName`). Freeleech =
  `downloadvolumefactor` à 0.
- **Pas de tri serveur** : les tris s'appliquent aux résultats chargés.
- Les erreurs arrivent en HTTP 200 : `<error code="100" description="…"/>`.
- Dates RFC 822 (`Sat, 17 Oct 2026 01:55:38 +0000`).

## Draupnirr : compte, missions

En plus de Torznab (ci-dessus), Draupnirr expose une API JSON pour le
compte utilisateur. Authentification par clé API en paramètre `apikey`
**et** en-tête `X-Api-Key` (le client envoie les deux par sécurité).
Limite : 120 requêtes / minute par clé (300 / minute par IP).

| Endpoint | Réponse | Champs utiles |
|---|---|---|
| `GET /api/me` | objet | `name`, `class` (niveau), `ratio` (null tant qu'il n'y a pas assez de données), `uploaded`, `downloaded`, `credits` (ce que tu as), `buffer` / `bonus_upload` (ce que tu peux gagner via les freeleech), `seedtime_seconds`, `seedtime_cumulative_seconds`, `uploads_count`, `hnr_count`, `invites`, `freeleech_global`, `source_tag`, `site_url`, `badges` |
| `GET /api/me/missions` | tableau | `code`, `period` (`daily`/`weekly`/`monthly`), `title`, `goal_type`, `goal_value`, `reward_credits`, `progress` (compte d'unités accomplies), `completed` |
| `GET /api/me/badges` | tableau | `slug`, `name`, `description`, `earned`, `awarded_at` |
| `GET /api/shop` | (non utilisé) | articles de la boutique |

Sur les missions, `progress` est un **compte d'unités accomplies**, pas
une fraction : la barre de progression vaut `progress / goal_value` clampée
à `1`. Les valeurs « seedtime » sont en secondes : on les convertit en
heures côté client (division par 3600).

L'onglet « Draupnirr » (icône bouclier) **n'apparaît dans la barre
principale que si une clé API est saisie** dans *Réglages → Trackers →
Draupnirr*. Il charge le compte et les missions automatiquement à
l'ouverture, plus un bouton « Actualiser » manuel (et pull-to-refresh).

Modèles dans `lib/api/draupnirr.dart`. Parsing défensif : si un champ
est absent ou typé différemment, le modèle l'ignore sans crasher (les
missions restent un tableau `[{...}]`, jamais `{data:[...]}` chez
Draupnirr).

## AstraTorrent

| Endpoint | Rôle | Auth |
|---|---|---|
| `/api/torrents.php` | sorties en JSON : `q`, `category` (slug : `films`, `series`, `anime`, `music`, `books`, `games`, `apps`, `xxx`), `sort` (`seeders`, `size` ; date par défaut), `limit` ≤ 1000 | publique |
| `/api/cross_seed.php?action=bulk_scan&passkey=…` | scanner de cross-seed : torrents terminés envoyés par lots de 150 (nom, taille, infohash) | passkey |
| `/api/download.php?id=…&passkey=…` | le `.torrent` | passkey |

- Pas de pagination : `limit` seulement. Les tris non faits par le site (et
  tous les tris croissants) portent sur les 1 000 dernières sorties, chargées
  une fois puis découpées en pages.
- Les dates sont à l'**heure de Paris** sans fuseau (`2026-10-17 15:17:38`).
- Pas de sous-catégories (le site en a des dizaines, mal normalisées).

## Transmission

- JSON `{method, arguments}` en POST sur `/transmission/rpc`.
- **CSRF** : la première requête reçoit un `409` avec
  `X-Transmission-Session-Id`, à renvoyer ensuite (rejeu automatique).
- Authentification Basic si un utilisateur est renseigné.
- `torrent-get` au format **`table`** (Transmission ≥ 3) : noms de champs
  envoyés une fois, réponse bien plus compacte. Rafraîchissements en
  `ids: "recently-active"` (seuls les torrents modifiés, `removed` pour les
  suppressions) ; liste complète toutes les 15 itérations et après chaque
  action.
- Protocole historique (clés kebab-case). Transmission 4.1 introduit
  JSON-RPC 2.0 et le snake_case mais accepte l'ancien format ; migration à
  prévoir avant Transmission 5.
- Valeurs spéciales : `eta` et `uploadRatio` à `-1` (indisponible) ou `-2`
  (infini). Les champs inconnus d'une version sont ignorés par le serveur.
- `test/fixtures/` contient des réponses réelles d'un daemon 4.0.5.

## TMDB

- API v3, langue `fr-FR`. Clé v3 en paramètre `api_key`, ou jeton v4 (`eyJ…`)
  en `Authorization: Bearer`.
- Dates françaises : `/movie/{id}/release_dates`, pays `FR` ; type 3 (à
  défaut 2, sortie limitée) : salles, 4 : VOD, 5 : physique. La plus ancienne
  date de chaque type est retenue.
- Fiche complète en une requête : `append_to_response=credits,videos,
  recommendations,release_dates` (ou `content_ratings` pour une série),
  `include_video_language=fr,en`.
- Rangées françaises : `/discover/movie` avec `region=FR` et
  `with_release_type` (`2|3` salles, `4|5` VOD et physique), plus
  `with_original_language=fr` pour les films français ; `/discover/tv` avec
  `with_origin_country=FR` pour les séries.
- Base : `/search/movie?year=` ou `/search/tv?first_air_date_year=`, avec puis
  sans l'année ; épisodes : `/tv/{id}/season/{n}`.
- Images : `https://image.tmdb.org/t/p/w500/…`, demandées à la taille
  affichée (`w154`, `w185`, `w342`).

## Jellyfin

- En-têtes `X-Emby-Token` et `Authorization: MediaBrowser Token="…"`.
- Une **clé d'API** n'a pas d'utilisateur : sans `userId`, `/Items` peut
  revenir vide. On prend le premier administrateur actif de `/Users`.
- Épisodes : `/Items?ParentId=…&Recursive=true&IncludeItemTypes=Episode&IsMissing=false`,
  sinon `/Shows/{id}/Episodes`, sinon sans le filtre (épisodes virtuels
  écartés).
- **Bibliothèque mixte** (films et séries mélangés) : pas de type `Series`
  ni `Episode`. La série est un `Folder`, souvent **nommé comme la release**
  (`MobLand.2025.S01.MULTI…-ZAKARI`), et les épisodes sont des `Movie` ou
  `Video` tous nommés comme la série : saison, numéro et titre sont lus dans
  le chemin du fichier. Une sortie par saison = plusieurs dossiers, réunis.
- Flux sans transcodage : `/Videos/{id}/stream?static=true&mediaSourceId=…`.

## FTP / FTPS (Appbox)

- Appbox : application **Pure-FTPd**, hôte `ftp.<identifiant>.appbox.co`,
  port 21, **TLS explicite**. SFTP n'est pas proposé par défaut.
- Séquence : accueil `220` → `AUTH TLS` (`234`) → poignée de main TLS →
  `USER` / `PASS` → `PBSZ 0` → `PROT P` (données chiffrées) → `TYPE I` →
  `OPTS UTF8 ON`.
- Mode **passif** : `EPSV` (`229 (|||port|)`), sinon `PASV` ; l'adresse
  annoncée par `PASV` est ignorée (souvent interne), on garde l'hôte.
- Listes : `MLSD` (faits `type`, `size`), sinon `LIST -a` façon Unix.
- Lecture à partir d'une position : `REST <octet>` puis `RETR`.
- Les certificats ne sont pas vérifiés (souvent autosignés sur les
  seedboxes).
- Limite connue : la reprise de session TLS sur la connexion de données n'est
  pas faite ; un serveur qui l'exige refusera les transferts.

## Quotas des trackers

| Tracker | Limite annoncée | Budget de l'application |
|---|---|---|
| C411 | 120 / min par clé | 80 / min, `.torrent` espacés de 3 s (sauf par le cookie) |
| tr4ker, Nostradamus | 120 / min par clé | 108 / min, `.torrent` espacés de 2 s |
| Draupnirr | 120 / min par clé (300 / min par IP) | 108 / min, `.torrent` espacés de 2 s |
| AstraTorrent | non publiée | 54 / min (60 supposées), `.torrent` espacés de 2 s |

C411 a renvoyé des 429 pendant un envoi en masse alors que l'application
restait sous 108 / min : son budget est abaissé à 80 et ses téléchargements
plus espacés (`requestBudget`, `downloadSpacing` dans l'enum `Tracker`).

Toute requête HTTP vers un tracker passe par `trackerRequest`
(`lib/api/quota.dart`) : clé API, cookie de session (palliatif, salon) ou
téléchargement de `.torrent`, toutes fonctions confondues (import en masse,
veille, disponibilité, cross-seed…). Un `RequestQuota` par tracker compte
les départs sur une **fenêtre glissante d'une minute** et fait patienter la
requête de trop au lieu de la laisser se faire refuser ; les rafales restent
permises sous la limite. Le budget garde 10 % de marge (horloge du serveur,
autre appareil avec la même clé), davantage pour C411.

Les **téléchargements de `.torrent`** (`trackerGet(…, download: true)`,
quel que soit l'appelant : envoi en masse, bouton ⬇, revive, palliatif,
cross-seed) sont en plus espacés d'un écart minimal depuis le précédent.
Exception : l'import en masse prend les `.torrent` C411 par le site avec le
cookie de session (`C411SiteApi.downloadTorrent`) quand il est renseigné ;
cette voie n'est pas espacée (seule celle par clé API se faisait refuser),
mais reste comptée dans le quota de C411. Cet
espacement ne déclenche pas le bandeau d'attente ; le bouton d'envoi en
masse affiche la progression (« Envoi 3 / 20… »).

Sur un **HTTP 429**, le quota du tracker est suspendu le temps donné par
`Retry-After` (secondes ou date HTTP ; 60 s à défaut) et la requête est
refaite une fois. Un second refus remonte en erreur.

Les attentes sont visibles : `QuotaNotice` affiche « reprise dans N s » sur
les pages Trackers, Import en masse et Nouveautés. Les espacements propres à
certaines tâches de fond (disponibilité : `trackerLimitersProvider`,
cross-seed : `crossSeedDelayProvider`) restent en place : ils leur évitent
de consommer tout le budget au détriment de ce qu'on fait à l'écran.

La limite d'un tracker se règle dans l'enum `Tracker`
(`requestsPerMinute`, et au besoin `requestBudget`, `downloadSpacing`).
