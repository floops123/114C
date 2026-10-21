# C411 Remote

> Ton seedbox dans la poche : les sorties des trackers, Transmission, ta liste
> de films à voir et ta vidéothèque, réunis dans une seule application.

C411 Remote est un client **Flutter** multiplateforme (Linux, Android…) qui
parle directement à ton serveur **Transmission**, aux trackers **C411**,
**tr4ker**, **Nostradamus**, **Draupnirr** et **AstraTorrent**, à **TMDB**
et au **FTP** de ta seedbox. Aucun serveur intermédiaire : tout se passe
entre l'application et tes services.

<p align="center">
  <img src="docs/images/fiche-titre.png" alt="Fiche d'un film : déjà sur le disque, sorties en France, disponibilité sur les trackers" width="860">
</p>

## Ce qu'elle sait faire

| | |
|---|---|
| 🎬 **Films & séries** | Les tops TMDB (rangées *Découvrir* tournées vers la France) et ta liste de souhaits ; sur chaque affiche, ▶ si tu l'as déjà, ⬇ s'il est sur un tracker. |
| 🌐 **Trackers** | Les sorties de tous les trackers, regroupées par film ou série et illustrées par TMDB ; choisis ta version, ou lis-la si elle est sur le disque. |
| 💾 **Ta vidéothèque** | Ta propre base de films et séries, construite à partir des fichiers de ta seedbox (FTP), reconnue par TMDB, saisons et épisodes compris ; filtre *Sur le disque* dans les deux vues. |
| ▶️ **Lecteur intégré** | Lecture directe du fichier d'origine, sans transcodage (mpv) : pistes audio, sous-titres, reprise là où tu t'étais arrêté. |
| ⬇️ **Transferts** | Tout Transmission : suivi en direct, tris, filtres, actions groupées, détail complet, statistiques, configuration du serveur. |
| 🆕 **Nouveautés** | Relève les trackers de ton choix toutes les *x* minutes, garde la liste des dernières sorties et te notifie de leur arrivée. |
| 🔁 **Cross-seed** | Repère tes torrents terminés présents sur d'autres trackers et les partage sans rien retélécharger. Relance aussi les sorties **sans seeder** et la liste palliative de C411. |
| 💰 **Rendement Zen** | Ce que rapporte chaque torrent partagé en Zen, et les sorties qu'il serait rentable d'ajouter, dans tes limites de disque et de ratio. |
| 🔔 **C411 et Salon** | L'onglet C411 : les notifications du site en direct et ton compte (ratio, crédit) ; le salon de discussion du site. |

## Démarrage rapide

```sh
# Linux (Debian / Ubuntu / Mint)
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsecret-1-dev libjsoncpp-dev libmpv-dev

flutter pub get
flutter run -d linux
```

Au premier lancement, l'application ouvre les **Réglages** : renseigne au
minimum l'adresse de Transmission et une clé de tracker. Tout le reste est
facultatif et se branche quand tu veux.

### Variante personnelle (réglages préenregistrés)

Pour une image familiale ou un poste personnel, copie
[`personal.json.example`](personal.json.example) en `personal.json`,
remplis-le, puis :

```sh
dart run tool/build_personal.dart personal.json --build apk
```

Les valeurs sont compilées dans le binaire au moment du build (le JSON
n'est pas embarqué dans l'APK). Détails : [Compilation personnalisée](docs/dev/build.md).

## C411 TV : la vidéothèque dans le navigateur

Le dossier [`web_player/`](web_player/README.md) contient un petit serveur
qui diffuse ta vidéothèque **à la manière d'un Netflix** : il lit la base de
l'application et les vidéos sur ton FTP (identifiants du JSON de réglages),
et convertit à la volée avec ffmpeg ce que le navigateur ne sait pas lire.

```sh
cd web_player && dart pub get && dart run bin/web_player.dart ../personal.json
```

## Documentation

La documentation complète est dans [`docs/`](docs/README.md).

**Guide d'utilisation**

1. [Installation](docs/guide/installation.md) — Linux, Android, prérequis
2. [Configuration](docs/guide/configuration.md) — Transmission, trackers, TMDB, FTP, Jellyfin
3. [Films & séries](docs/guide/films-et-series.md) — tops TMDB, souhaits, fiches, lire ou télécharger
4. [Trackers](docs/guide/trackers.md) — toutes les sorties regroupées par titre, versions
5. [Sur le disque et lecture](docs/guide/sur-le-disque.md) — ta vidéothèque et le lecteur intégré
6. [Transferts](docs/guide/transferts.md) — Transmission, statistiques, serveur
7. [Nouveautés](docs/guide/nouveautes.md) — veille des trackers, notifications
8. [Cross-seed et sans seeder](docs/guide/cross-seed.md) — partager plus, relancer les morts
9. [C411 et Salon](docs/guide/notifications.md) — C411 en direct
10. [Rendement Zen](docs/guide/zen.md) — portefeuille et opportunités
11. [Dépannage](docs/guide/depannage.md) — questions fréquentes

**Pour les développeurs**

- [Architecture](docs/dev/architecture.md) — organisation du code, état, flux de données
- [Notes sur les API](docs/dev/api.md) — C411, Torznab, AstraTorrent, TMDB, Jellyfin, Transmission, FTP
- [Interface et performances](docs/dev/interface.md) — thème, composants, choix pour rester fluide
- [Compilation personnalisée](docs/dev/build.md) — variante avec identifiants préenregistrés via JSON
- [Tests](docs/dev/tests.md) — ce qui est vérifié et comment

## Plateformes

| Plateforme | État |
|---|---|
| Linux | utilisée au quotidien |
| Android | APK compilé (API 24 → 36), mise en page téléphone vérifiée |
| iOS, Windows, macOS | projet généré, non testé |
| Web | non prise en charge (ni Transmission ni les trackers n'autorisent les requêtes d'un navigateur, CORS) |

## Vie privée

Les identifiants (Transmission, clés et passkeys des trackers, cookie de
session, FTP, TMDB, Jellyfin) sont rangés dans le **trousseau du système**
(libsecret, Keychain, Keystore). Ils ne quittent l'appareil que pour joindre
le service auquel ils appartiennent.

## Licences

Code de l'application (et de `packages/c411_core`, `web_player`) : licence
[WTFPL](LICENSE) — fais-en ce que tu veux. Police
[Inter](https://rsms.me/inter/) et polices code et rétro sous licence OFL
(`assets/fonts/`, `assets/fonts/licenses/`). Copie corrigée de `media_kit_video` sous
licence MIT ([`third_party/media_kit_video`](third_party/media_kit_video/C411-PATCH.md)).
Données de films et séries fournies par [TMDB](https://www.themoviedb.org/)
(l'application n'est ni approuvée ni certifiée par TMDB).
