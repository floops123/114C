# C411 Remote

Client multiplateforme pour piloter un daemon **Transmission** distant et parcourir
les dernières sorties du tracker **C411**, avec envoi direct d'une sortie vers
Transmission en un clic.

L'application est 100 % cliente : elle parle directement à l'API RPC de
Transmission et à l'API de C411, sans serveur intermédiaire.

## Fonctionnalités

**Sorties (C411)**
- Liste paginée au défilement des dernières sorties (affiche, badges résolution /
  source / langue / freeleech / exclu, taille, seeders, ancienneté).
- Recherche par nom, filtres catégorie et sous-catégorie, tri récents / seeders.
- Fiche détaillée : synopsis, casting, infos techniques.
- Bouton « Télécharger » : récupère le `.torrent` et l'ajoute à Transmission.
  Les sorties déjà présentes dans Transmission sont marquées d'une ✓.

**Téléchargements (Transmission)**
- Liste rafraîchie toutes les 2 s, vitesses globales, filtres, tri, filtre par nom.
- Ajout par lien magnet ou URL.
- Détail : infos, fichiers (sélection), pairs, trackers ; démarrer / arrêter,
  vérifier, réannoncer, supprimer (avec ou sans les données).

**Réglages**
- Adresse RPC, identifiants Transmission et clé API C411, stockés dans le
  trousseau du système (`flutter_secure_storage`).
- Test des connexions, automatiquement avant chaque enregistrement.
- Configuration du serveur Transmission (`session-set`) : dossier, limites de
  vitesse, mode tortue, files d'attente, ratio, pairs.

## Plateformes

| Plateforme | État |
|---|---|
| Linux | testé |
| Android, iOS, Windows, macOS | projet généré, non testé |
| Web | **non supporté** : ni Transmission ni C411 n'envoient d'en-têtes CORS |

## Démarrer

Prérequis Linux (Debian / Ubuntu / Mint) :

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsecret-1-dev libjsoncpp-dev
```

Puis :

```sh
flutter pub get
flutter run -d linux        # développement (r = hot reload)
flutter build linux         # build release dans build/linux/x64/release/bundle
flutter test                # tests unitaires
flutter analyze             # analyse statique
```

Au premier lancement, l'application ouvre les Réglages : renseigner l'adresse RPC
(ex. `https://serveur:9091/transmission/rpc` ; sans chemin, `/transmission/rpc`
est ajouté) et la clé API C411.

## Architecture

```
lib/
├── main.dart                  Thème Material 3, ProviderScope
├── core/
│   ├── format.dart            Formatage (octets, vitesses, durées, dates) en français
│   └── settings.dart          Réglages + persistance dans le trousseau
├── api/
│   ├── c411.dart              Client API C411 (sorties, catégories, .torrent)
│   └── transmission.dart      Client RPC Transmission + modèle Torrent
├── state/                     Logique (Riverpod)
│   ├── releases.dart          Pagination/filtres des sorties, envoi vers Transmission
│   └── torrents.dart          Polling Transmission, détail d'un torrent
└── ui/                        Écrans
    ├── home_shell.dart        Navigation (barre en bas / rail latéral ≥ 720 px)
    ├── releases_page.dart, release_detail_page.dart
    ├── downloads_page.dart, torrent_detail_page.dart
    ├── settings_page.dart, server_settings_page.dart
    └── widgets.dart           Badges, affiches, états vides, bannières d'erreur
```

Stack : Flutter, `flutter_riverpod` (état), `dio` (HTTP),
`flutter_secure_storage` (secrets), `cached_network_image` (affiches).

### Choix pour rester léger

- **Listes virtualisées** (`ListView.builder` + `itemExtent` fixe) : seules les
  lignes visibles sont construites.
- **Affiches décodées à la taille affichée** (`memCacheWidth`) et mises en cache.
- **Transmission** : `torrent-get` ne demande que les champs affichés ; les
  rafraîchissements utilisent `ids: "recently-active"` (seuls les torrents
  modifiés reviennent, `removed` signale les suppressions). Une liste complète
  est rechargée toutes les 15 itérations et après chaque action. Les champs
  lourds (fichiers, pairs, trackers) ne sont chargés que sur l'écran de détail.

## Notes sur les API

### C411

Deux API coexistent, avec **deux modes d'authentification différents** :

| Usage | Endpoint | Auth |
|---|---|---|
| Liste des sorties (JSON riche : TMDB, tech…) | `GET /api/torrents` | `Authorization: Bearer <clé>` |
| Catégories | `GET /api/categories` | Bearer |
| Téléchargement du `.torrent` | `GET /api?t=get&id=<infoHash>&apikey=<clé>` | paramètre `apikey` (le Bearer y est refusé) |

Paramètres de `/api/torrents` constatés : `page`, `perPage`, `cat` (catégorie),
`subcat` (sous-catégorie), `name` (recherche), `sortBy=seeders` (sinon tri par
date). La réponse contient `data[]` et `meta` (`page`, `totalPages`, `total`,
compteurs par catégorie). `limit` est ignoré.

Limite : 120 requêtes / minute par clé (Torznab inclus).

Le `.torrent` est envoyé à Transmission en `metainfo` (base64) plutôt qu'en
magnet : sur un tracker privé, c'est le `.torrent` qui contient le passkey.

### Transmission RPC

- Protocole JSON `{method, arguments}` en POST sur `/transmission/rpc`.
- Protection CSRF : la première requête reçoit un `409` avec l'en-tête
  `X-Transmission-Session-Id`, que le client renvoie ensuite (rejeu automatique).
- Authentification Basic si un utilisateur est renseigné.
- Valeurs spéciales : `eta` et `uploadRatio` valent `-1` (indisponible) ou `-2`
  (infini).

## Sécurité

- Aucun secret dans le dépôt : clé API et identifiants sont saisis dans
  l'application et stockés dans le trousseau du système.
- L'onglet Trackers n'affiche que l'hôte, jamais l'URL d'annonce (qui contient
  le passkey).

## Pistes

- Build et test Android.
- Ajout d'un `.torrent` depuis un fichier local.
- Choix du dossier de destination à l'envoi.
- Tableau de bord du profil C411 (`/api/user/profile`, scope `profile:read`).
- Notifications de nouvelles sorties (filtres sauvegardés).
