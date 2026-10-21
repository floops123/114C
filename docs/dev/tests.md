# Tests

[← Sommaire](../README.md)

## Lancer

```sh
flutter test              # tous les tests unitaires et d'interface
flutter test test/ftp_test.dart   # un seul fichier
flutter analyze           # analyse statique (doit rester sans remarque)
```

Les tests ne touchent à aucun service réel : trackers, TMDB, Jellyfin et
Transmission sont remplacés par des faux, et le FTP par un petit serveur
local. Ils tournent hors ligne en une trentaine de secondes.

## Ce qui est vérifié

**Trackers et sorties**

| Fichier | Contenu |
|---|---|
| `catalog_test.dart` | regroupement par titre (français et original), disponibilité (un tracker suffit, mémorisée), pages fusionnées, vue Trackers et ses filtres |
| `parsing_test.dart` | noms de release, dates RFC 822, tri local, tailles d'affiches |
| `release_profile_test.dart` | profils de qualité C411 sur des sorties réelles |
| `content_art_test.dart` | type de contenu d'une sortie, pictos des catégories |
| `row_layout_test.dart` | lignes sans débordement (390 / 1 705 px, police × 1 et × 1,3) |
| `mouse_scroll_test.dart`, `smooth_wheel_test.dart` | glisser à la souris, molette adoucie |

**Transmission**

| Fichier | Contenu |
|---|---|
| `add_files_test.dart` | envoi de `.torrent` : ajoutés, doublons, invalides, refusés |
| `server_settings_test.dart`, `torrent_detail_test.dart` | écrans sur des réponses réelles d'un daemon 4.0.5 |
| `charts_test.dart` | graphiques (survol, info-bulle sans débordement) |
| `reorder_test.dart` | liste réordonnée à chaque rafraîchissement sans erreur |

**Cross-seed et sans seeder**

| Fichier | Contenu |
|---|---|
| `cross_seed_test.dart` | bencode, tracker d'origine, analyse dans les deux sens, mémoire, ajout |
| `revive_test.dart` | sorties mortes retrouvées, téléchargées, puis ajoutées depuis le tracker d'origine |
| `palliative_test.dart` | liste palliative C411, recherche multi-tracker, téléchargement puis cross-seed |

**Films & séries, vidéothèque et lecture**

| Fichier | Contenu |
|---|---|
| `settings_test.dart` | `SettingsNotifier` : trousseau vide → défaut ; défauts au build → appliqués ; trousseau non vide → priorité aux valeurs stockées |
| `build_defaults_test.dart` | `BuildDefaults` : `hasAny`, `allVariables`, round-trip JSON |
| `build_personal_test.dart` | outil `tool/build_personal.dart` : JSON → `--dart-define` (champs scalaires, `mediaFolders` CSV, `apiKeys` par tracker, valeurs vides ignorées, erreurs de lecture) |
| `draupnirr_test.dart` | parsing défensif de `DraupnirrAccount` / `Mission` / `Badge` (alias multiples, champs manquants, progress décimal ou pourcentage) |
| `bulk_import_test.dart` | `BulkCriteria.accepts` : trackers et catégories multi-sélection, min/max taille/seeders/leechers, combinaison des bornes ; `parseBytes` Go/Mo/To |
| `release_watch_test.dart` | veille : premier relevé sans alerte, nouveautés en tête et notifiées, trackers choisis, échec d'un tracker, vu / vidé, relevé à l'ouverture puis selon l'intervalle, sérialisation ; page Nouveautés |
| `bulk_import_small_test.dart` | petits torrents : tri par taille demandé au tracker, arrêt à la taille max, dichotomie vers la taille min, enchaînement des pages sans tri serveur, déjà dans Transmission, stopper puis reprendre, catégorie transmise ; écran (raccourci de taille, en-tête, envoi) |
| `bulk_import_categories_test.dart` | catégories des sorties (Torznab via le `caps` servi en local, C411, AstraTorrent) et filtre ; catégories rechargées quand les trackers changent ; erreurs cumulées par tracker puis effacées |
| `wishlist_test.dart` | TMDB, liste, Découvrir, fiche, recherche par tracker, tris et intertitres |
| `media_name_test.dart` | film ou épisode d'après le chemin, extraits et bonus ignorés |
| `ftp_test.dart` | client FTP **et FTPS** : liste, taille, lecture à une position, repli sur `LIST`, identifiants refusés |
| `media_relay_test.dart` | relais HTTP : plages `Range`, 206 / 416, contenu exact via FTPS |
| `media_library_test.dart` | parcours complet (Transmission + dossiers), correspondance des chemins, TMDB, rattachement aux fiches et aux sorties, cartes de la vidéothèque et épisodes |
| `media_library_finished_test.dart` | fin de téléchargement : les fichiers du torrent rejoignent la base sans repasser par le FTP ; pas de parcours automatique au lancement ; aucun FTP quand Transmission suffit, parcours quand des dossiers sont configurés |
| `player_tracks_test.dart` | choix de la piste audio et des sous-titres, appliqué même quand les commandes se masquent |
| `jellyfin_test.dart` | bibliothèque, versions, épisodes, bibliothèque mixte (dossiers nommés comme la release, une sortie par saison) |

**C411 en direct**

| Fichier | Contenu |
|---|---|
| `socket_test.dart`, `chat_send_test.dart` | client Socket.IO contre un faux serveur : ping, événements, refus, envoi avec accusé, réessai |
| `notifications_test.dart`, `chat_test.dart`, `chat_format_test.dart` | trames et réponses réelles anonymisées, salon, mise en forme, cache |

**Ensemble**

| Fichier | Contenu |
|---|---|
| `smoke_test.dart` | l'application complète : tous les onglets, info-bulles, rafraîchissements, à plusieurs largeurs |

## Outils de test

- **`test/fake_ftp.dart`** : serveur FTP en mémoire (`EPSV`, `MLSD` / `LIST`,
  `SIZE`, `REST`, `RETR`), avec TLS explicite facultatif grâce à un
  certificat autosigné **réservé aux tests** (`test/fixtures/ftp_test_*.pem`).
- **`test/fixtures/`** : réponses réelles (Transmission 4.0.5, C411,
  AstraTorrent), anonymisées.
- **Stores en mémoire** : `MemoryWishlistStore`, `MemoryPlaybackStore`,
  `MemoryMediaLibraryStore`… à passer en `overrideWithValue`.
- **Faux clients** : sous-classes de `TmdbApi`, `TransmissionClient`,
  `JellyfinClient` (avec un `HttpClientAdapter` factice) ou implémentations
  de `TrackerApi`.

## Performances

`integration_test/scroll_perf_test.dart` (avec `test_driver/perf_driver.dart`)
mesure la fluidité du défilement des transferts (424 torrents rafraîchis
toutes les 2 s) et des sorties, en mode profil :

```sh
flutter drive --profile -d linux --driver=test_driver/perf_driver.dart \
  --target=integration_test/scroll_perf_test.dart
```

## Captures d'écran

Les images de `docs/images/` sont produites par un test temporaire : il charge
les polices (Inter et MaterialIcons) avec `FontLoader`, affiche un écran avec
des données fictives, puis enregistre le rendu d'un `RepaintBoundary` en PNG.
