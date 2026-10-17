# C411 Remote

Client multiplateforme pour piloter un daemon **Transmission** distant et parcourir
les dernières sorties des trackers **C411** et **tr4ker**, avec envoi direct d'une
sortie vers Transmission en un clic.

L'application est 100 % cliente : elle parle directement à l'API RPC de
Transmission et aux API des trackers, sans serveur intermédiaire.

## Fonctionnalités

**Sorties (C411, tr4ker)**
- Un onglet par tracker configuré (le dernier choisi est mémorisé).
- Liste paginée au défilement des dernières sorties (affiche, badges résolution /
  source / langue / freeleech / exclu, taille, seeders, ancienneté).
- Recherche par nom, filtres catégorie et sous-catégorie, tri récents / seeders.
- Fiche détaillée : synopsis, casting, infos techniques.
- Bouton « Télécharger » : récupère le `.torrent` et l'ajoute à Transmission.
  Les sorties déjà présentes dans Transmission sont marquées d'une ✓.

**Transferts (Transmission)**
- Liste rafraîchie toutes les 2 s (`torrent-get` au format « table »,
  `recently-active`), vitesses globales, filtres (actifs, en cours, partage,
  terminés, en file, arrêtés, bloqués, erreurs), filtre par étiquette, 9 tris.
- Sélection multiple (appui long) et actions groupées ; tout démarrer / arrêter.
- Actions : démarrer, démarrer maintenant (hors file), arrêter, vérifier,
  réannoncer, déplacer dans la file, déplacer les fichiers
  (`torrent-set-location`), étiquettes, priorité, copier le magnet, supprimer
  (avec ou sans les données).
- Ajout par lien magnet ou URL, et envoi depuis un tracker, avec options :
  dossier, étiquettes, priorité, en pause.
- Détail en 5 onglets :
  - Infos : progression, carte des pièces, transfert, origine des pairs
    (tracker, DHT, PEX…), dates, créateur, hash ;
  - Fichiers : sélection, priorité par fichier, renommage (`torrent-rename-path`) ;
  - Pairs : client, progression, vitesses, chiffrement, µTP, entrant ;
  - Trackers : annonces et scrapes, paliers, édition de la liste (`trackerList`) ;
  - Options : priorité, limites de vitesse, groupe de bande passante, ratio et
    inactivité propres au torrent, nombre de pairs.

**Réglages**
- Adresse RPC, identifiants Transmission et clé API C411, stockés dans le
  trousseau du système (`flutter_secure_storage`).
- Test des connexions, automatiquement avant chaque enregistrement.
- Configuration complète du serveur Transmission (`session-set`), d'après
  `docs/Editing-Configuration-Files.md` : dossiers et fichiers incomplets,
  limites de vitesse, mode tortue et sa planification (heures, jours), files
  d'attente, ratio et inactivité, port, chiffrement, protocoles, DHT / PEX /
  LPD, blocklist, trackers par défaut, scripts, anti-force brute. Seules les
  options renvoyées par le serveur sont affichées (compatibilité 3.x → 4.1),
  recherche parmi les réglages, seules les modifications sont envoyées.
- Outils serveur : test du port, mise à jour de la blocklist, espace disque
  (libre / total), nombre de torrents, statistiques de session et cumulées,
  groupes de bande passante (`group-get` / `group-set`), arrêt du daemon
  (`session-close`).
- Thème clair, sombre ou suivant le système.

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
├── main.dart                  Chargement des préférences, ProviderScope
├── core/
│   ├── format.dart            Formatage (octets, vitesses, durées, dates) en français
│   ├── preferences.dart       Préférences d'interface (thème, grille/liste, tracker)
│   ├── release_name.dart      Titre, année, résolution… extraits d'un nom de release
│   └── settings.dart          Réglages + persistance dans le trousseau
├── api/
│   ├── tracker.dart           Modèle commun (Release…), interface TrackerApi, liste des trackers
│   ├── c411.dart              Client API JSON de C411
│   ├── torznab.dart           Client Torznab générique (tr4ker)
│   └── transmission.dart      Client RPC Transmission + modèle Torrent
├── state/                     Logique (Riverpod)
│   ├── releases.dart          Pagination/filtres des sorties, envoi vers Transmission
│   └── torrents.dart          Polling Transmission, détail d'un torrent
└── ui/                        Écrans
    ├── home_shell.dart        Navigation (barre en bas / rail latéral ≥ 720 px)
    ├── releases_page.dart, release_detail_page.dart
    ├── downloads_page.dart, torrent_detail_page.dart
    ├── settings_page.dart, server_settings_page.dart
    ├── send_button.dart       Bouton « Télécharger » (état d'envoi, options)
    ├── torrent_actions.dart   Menu et dialogues d'actions sur les torrents
    ├── bandwidth_groups_page.dart  Groupes de bande passante
    ├── theme.dart             Palette (AppColors) et thème clair / sombre
    └── widgets.dart           Composants partagés (Tag, Poster, Section…)
```

Stack : Flutter, `flutter_riverpod` (état), `dio` (HTTP),
`flutter_secure_storage` (secrets), `cached_network_image` (affiches),
`shared_preferences` (préférences d'interface), `google_fonts` (Inter).

### Style

Thème maison « appli média » construit sur les widgets Flutter mais sans
l'apparence Material : fond sombre profond (ou clair), cartes à bord fin sans
ombre, pas d'effet d'onde, police Inter, une seule couleur d'accent. Toutes les
couleurs sont définies dans `AppColors` (`lib/ui/theme.dart`) et accessibles via
`context.colors`.

Note : avec `google_fonts` 9, n'utiliser que `GoogleFonts.inter().fontFamily` ;
ses helpers `TextTheme` reposent sur le paquet `material_ui`, incompatible avec
le `TextTheme` de Flutter.

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

### Ajouter un tracker

Les trackers sont listés dans l'enum `Tracker` (`lib/api/tracker.dart`). Pour un
tracker Torznab, il suffit d'y ajouter une ligne (nom + URL de l'endpoint) et de
la brancher sur `TorznabApi` dans `Tracker.client`. La page Réglages et le
sélecteur de l'onglet Sorties s'adaptent automatiquement.

### tr4ker (Torznab)

- Endpoint : `https://tr4ker.net/api/` (`/api` redirige vers `/api/`).
  `/api/torznab` est déprécié ; `/api/torznab/all` inclut les torrents sans
  seeder (cross-seed), non utilisé ici.
- Authentification : en-tête `X-Api-Key: <clé>` (doc tr4ker) ; la clé est aussi
  passée en paramètre `apikey` (convention Torznab). Exigée même pour `t=caps`
  (sinon HTTP 401).
- Torznab ne donne ni affiche TMDB ni infos techniques : titre, année,
  résolution, source, codec et langues sont déduits du nom de la release
  (`ReleaseName`). Freeleech = `downloadvolumefactor` à 0. Pas de tri serveur.
- Les erreurs Torznab arrivent en HTTP 200 sous la forme
  `<error code="100" description="…"/>`.

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
- Le client utilise le protocole historique (clés kebab-case). Transmission
  4.1 introduit JSON-RPC 2.0 et le snake_case, mais accepte toujours l'ancien
  format ; la migration sera nécessaire avant Transmission 5.
- `test/fixtures/` contient des réponses réelles d'un `transmission-daemon`
  4.0.5 (session, statistiques, détail d'un torrent), utilisées par les tests
  d'interface.
- Champs inconnus d'une version (ex. `sequentialDownload`, 4.1) : ignorés par
  le serveur ; l'option correspondante n'est simplement pas affichée.
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
