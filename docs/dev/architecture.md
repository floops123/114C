# Architecture

[← Sommaire](../README.md)

## Vue d'ensemble

L'application est découpée en quatre couches, chacune ne dépendant que de
celles du dessous :

```
ui/      Écrans et composants (widgets Flutter)
  │
state/   Logique et état (Riverpod) : ce que l'interface affiche et ses actions
  │
api/     Clients des services : trackers, Transmission, TMDB, Jellyfin, FTP
  │
core/    Outils purs : analyse des noms, format, réglages, préférences
```

Stack : **Flutter**, `flutter_riverpod` 3 (état), `dio` (HTTP),
`flutter_secure_storage` (secrets), `shared_preferences` (préférences et
caches), `cached_network_image` (affiches), `media_kit` (lecteur, mpv),
`xml` (Torznab), `file_selector`, `url_launcher`. Police Inter intégrée.

## Les dossiers

```
packages/c411_core/            Dart pur partagé avec web_player, web_music et
                               web_books : client FTP, relais HTTP, lecture
                               des noms de release, de musique et de livres
                               (lib/api/ftp.dart… ne font que ré-exporter)
web_player/                    C411 TV : la vidéothèque dans un navigateur
                               (voir web_player/README.md)
web_music/                     C411 Music : la musique dans un navigateur,
                               fiches MusicBrainz (voir web_music/README.md)
web_books/                     C411 Books : livres, BD, mangas, magazines
                               dans un navigateur (voir web_books/README.md)
tool/
└── build_personal.dart        convertit un JSON de réglages en --dart-define
                               pour produire une variante avec identifiants
                               préenregistrés (voir docs/dev/build.md)
lib/
├── main.dart                  préférences, liaison du défilement adouci, ProviderScope
├── build_defaults.dart        réglages injectés au build via --dart-define
                               (générés par tool/build_personal.dart)
├── core/
│   ├── settings.dart          réglages (identifiants) dans le trousseau
│   ├── preferences.dart       préférences d'interface + liste des clés stockées
│   ├── release_name.dart      titre, année, qualité… lus dans un nom de release
│   ├── release_profile.dart   profils de qualité C411, traits techniques
│   ├── media_name.dart        film ou épisode d'après un chemin de fichier
│   ├── titles.dart            comparaison de titres (accents, ponctuation)
│   ├── bencode.dart           lecture des .torrent
│   ├── format.dart            octets, vitesses, durées, dates en français
│   └── zen.dart               règles Zen (Swarm Keeper) : note, poids, bonus, budget
├── api/
│   ├── tracker.dart           enum Tracker, modèle Release, interface TrackerApi
│   ├── quota.dart             quota de requêtes par minute de chaque tracker, 429
│   ├── c411.dart              API JSON de C411
│   ├── torznab.dart           Torznab générique (tr4ker, Nostradamus, Draupnirr)
│   ├── draupnirr.dart          API JSON Draupnirr : /api/me, missions, badges
│   ├── astra.dart             AstraTorrent (torrents.php, cross_seed.php)
│   ├── c411_socket.dart       Socket.IO minimal (WebSocket des notifications)
│   ├── c411_chat.dart         salons et messages
│   ├── transmission.dart      RPC Transmission, modèle Torrent
│   ├── tmdb.dart              TMDB : recherche, rangées, fiches, saisons
│   ├── jellyfin.dart          Jellyfin : bibliothèque, épisodes, flux
│   ├── ftp.dart               client FTP / FTPS (TLS explicite, passif)
│   └── media_relay.dart       relais HTTP local vers le FTP, pour mpv
├── state/
│   ├── releases.dart          envoi d'une sortie vers Transmission
│   ├── catalog.dart           tops des trackers regroupés, fiches TMDB, disponibilité
│   ├── torrents.dart          interrogation de Transmission, détail, statistiques
│   ├── speed_history.dart     historique des vitesses
│   ├── cross_seed.dart        analyse et ajout des cross-seeds, sens choisis
│   ├── revive.dart            relance des sorties sans seeder
│   ├── palliative.dart        liste palliative C411, copie sur les autres trackers
│   ├── wishlist.dart          souhaits, recherche et tri sur les trackers
│   ├── media_library.dart     notre base (parcours FTP, TMDB, stockage, ajout des torrents terminés absents)
│   ├── playback.dart          positions de reprise
│   ├── notifications.dart     WebSocket, notifications, compteurs
│   ├── draupnirr.dart          compte Draupnirr, missions, badges
│   ├── bulk_import.dart        import en masse : critères, page par tracker, envoi
│   ├── release_watch.dart      veille : relevés périodiques, nouveautés, notifications système
│   ├── c411_overview.dart      compte, niveau, Zen, réanimations, classement (cookie)
│   ├── zen_portfolio.dart      ce que rapporte chaque torrent C411 de Transmission
│   └── zen_opportunities.dart  sorties C411 rentables à ajouter, sélection, envoi
└── ui/
    ├── home_shell.dart        navigation : barre en bas, rail latéral ≥ 720 px
    ├── wishlist_page.dart     Films & séries : Découvrir, Ma liste, affiches, rangées
    ├── title_detail_page.dart fiche d'un titre : infos, dates, déjà chez toi, trackers
    ├── wish_search_page.dart  recherche d'un titre, un onglet par tracker
    ├── trackers_page.dart     Trackers : sorties regroupées par titre, versions
    ├── releases_page.dart     une sortie en carte, tuile ou ligne ; grille commune
    ├── disk_page.dart         vidéothèque : cartes, épisodes de la base, lecture
    ├── series_page.dart       épisodes Jellyfin
    ├── player_page.dart       lecteur, choix de version
    ├── on_disk.dart           « déjà chez toi » pour une sortie (base, Jellyfin)
    ├── downloads_page.dart    Transferts
    ├── torrent_detail_page.dart, torrent_actions.dart, stats_page.dart
    ├── cross_seed_page.dart, revive_page.dart
    ├── notifications_page.dart, chat_page.dart, rich_text.dart
    ├── draupnirr_page.dart       onglet compte Draupnirr (compte + missions)
    ├── bulk_import_page.dart    import en masse : filtres, sélection, envoi
    ├── release_watch_page.dart  Nouveautés : sorties repérées, réglages de la veille
    ├── settings_page.dart, server_settings_page.dart, bandwidth_groups_page.dart
    ├── theme.dart             palette AppColors, thèmes clair et sombre
    ├── widgets.dart           composants partagés
    ├── content_art.dart       images par type de contenu, pictos de catégories
    └── smooth_wheel.dart      défilement à la molette adouci
```

## L'état avec Riverpod

Chaque service a un fournisseur qui dépend des réglages, et se recrée quand
ils changent :

```
settingsProvider ──► transmissionProvider ──► torrentsProvider
                 ├─► trackersProvider ──────► releasesProvider, wishSearchProvider
                 ├─► tmdbProvider ──────────► tmdbFeedProvider, tmdbDetailsProvider
                 ├─► jellyfinProvider ──────► jellyfinLibraryProvider
                 └─► mediaRelayProvider        mediaLibraryProvider ◄── store
```

Conventions :

- **Stockage interchangeable** : chaque donnée persistante passe par une
  interface `…Store` avec une version `Prefs…` (shared_preferences) et une
  version `Memory…` (tests). Le fournisseur se rabat sur la mémoire si les
  préférences ne sont pas initialisées, ce qui garde les tests simples.
- **Clés déclarées** : toute clé de shared_preferences doit figurer dans la
  liste `allowList` de `core/preferences.dart`.
- **Après un `await`**, un notifier vérifie `ref.mounted` avant de toucher à
  son état ; un widget lit son notifier **avant** l'attente.
- **Écrans masqués en pause** : les onglets sont dans un `IndexedStack` avec
  `TickerMode` ; Riverpod 3 met en pause ce qui n'est pas visible.
- **`select`** partout où un widget ne dépend que d'une partie d'un état
  (par exemple la pastille « sur le disque » d'une tuile).

## Flux : envoyer une sortie

```
Bouton ⬇ ─► TrackerApi.downloadTorrent(release) ─► .torrent (avec la passkey)
        ─► TransmissionClient.addTorrentWithHash(metainfo) ─► torrent-add
        ─► torrentsProvider se rafraîchit ─► la sortie passe « SUR LE DISQUE »
```

Le `.torrent` est envoyé en `metainfo` (base64) plutôt qu'en magnet : sur un
tracker privé, c'est lui qui porte la passkey.

L'import en masse (`lib/ui/bulk_import_page.dart`) suit le même chemin,
sortie par sortie, après filtrage côté client. Les bornes (taille, seeders,
leechers) ne sont pas transmises aux trackers — aucun indexer ne les
supporte de manière homogène. Un seul tracker à la fois, car chacun a ses
identifiants de catégories : chaque catégorie cochée est transmise au
tracker (une recherche paginée par catégorie, résultats réunis). L'ordre
l'est aussi (taille croissante quand le tracker trie lui-même : arrêt à la
taille max, dichotomie vers la taille min).
Les bornes rognent les résultats avant l'envoi. Voir [Import en masse](../guide/import-en-masse.md).

## Flux : notre base

```
MediaLibraryNotifier.scan()
 ├─ FtpClient.connect()                         (FTPS : AUTH TLS, PBSZ, PROT P)
 ├─ scanFolders(dossiers des Réglages)          MLSD, sinon LIST
 ├─ Transmission : torrent-get files            torrents terminés
 │   └─ detectPathMap()                         chemin serveur → chemin FTP (SIZE)
 ├─ MediaGuess.parse(chemin)                    film / épisode, titre, année
 ├─ TmdbApi.identify(titre, type, année)        une fois par titre
 └─ MediaLibraryStore.save()                    sur l'appareil
```

Un torrent qui termine ne déclenche pas ce parcours : le listener sur
`torrentsProvider` dans `MediaLibraryNotifier.build()` remarque le passage à
100 % et appelle `appendFinished(id, hash)`, qui relit juste ce torrent
(`torrent-get` avec ses `files`), traduit les chemins avec la correspondance
déjà connue (`pathFrom` / `pathTo`) et n'ajoute que les fichiers absents. Pas
de FTP, pas de `MLSD` : une requête, et l'identification TMDB des seuls titres
nouveaux.

Le parcours complet, lui, ne touche le FTP que s'il lui sert vraiment :

| Situation | Connexion FTP |
|---|---|
| Transmission seul, correspondance des chemins connue | **aucune** — une requête `torrent-get` |
| Transmission, correspondance à établir (jamais parcouru) | oui, pour `detectPathMap` (quelques `SIZE`) |
| Des *Dossiers à parcourir* configurés | oui, pour le parcours (`scanFolders`) |

Autrement dit, les torrents sont la source principale : Transmission connaît
déjà tous les fichiers vidéo et leur chemin en une requête, alors qu'un
parcours de dossiers fait un `list()` par répertoire. La promenade ne sert
qu'à ce que Transmission ne connaît pas (les fichiers posés à la main dans
les dossiers choisis).

Le parcours complet reste manuel (bouton *Actualiser*) et automatique
uniquement quand les réglages FTP ou les dossiers changent.

La lecture passe ensuite par le relais :

```
PlayerPage ─► MediaRelay.urlFor(chemin) ─► http://127.0.0.1:<port>/<n>/<nom>
mpv ─► GET + Range ─► relais ─► FTP : SIZE, REST <début>, RETR ─► octets
```

Une connexion FTP par requête HTTP : simple et robuste, au prix d'une seconde
environ à chaque saut dans la vidéo.

## Ajouter un tracker

1. Une ligne dans l'enum `Tracker` (`api/tracker.dart`) : nom, URL, fragment
   d'URL d'annonce (pour reconnaître ses torrents), nom de l'identifiant,
   requêtes permises par minute (120 par défaut).
2. Le brancher dans `Tracker.client` : `TorznabApi` s'il parle Torznab,
   sinon une nouvelle classe qui implémente `TrackerApi`.

Les Réglages, la vue Trackers, la disponibilité des titres, la recherche
des souhaits et le cross-seed
s'adaptent tout seuls.

## Dépendance corrigée

`third_party/media_kit_video` est une copie de `media_kit_video` 2.0.1 avec un
correctif Linux (rendu matériel sous Impeller), branchée par
`dependency_overrides`. Explications dans
[C411-PATCH.md](../../third_party/media_kit_video/C411-PATCH.md). À retirer
quand une version officielle corrigera le problème.
