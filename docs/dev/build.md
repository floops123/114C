# Compilation personnalisée

[← Sommaire](../README.md)

C411 Remote peut être compilé dans une **variante personnelle** : au
premier lancement, les réglages passés à la compilation sont écrits dans
le trousseau du système (libsecret, Keychain, Keystore), comme si
l'utilisateur venait de les saisir. Les lancements suivants lisent depuis
le trousseau et les modifications faites dans *Réglages* priment toujours.

Deux mécanismes, qui peuvent être combinés (les variables individuelles
l'emportent sur le fichier) :

1. **Fichier JSON** : `--dart-define=C411_DEFAULTS_FILE=<chemin>`. Pratique
   quand on a beaucoup de réglages : tout est dans un fichier versionnable
   et facile à éditer.
2. **Variables individuelles** : `--dart-define=C411_<NOM>=<valeur>`. Utile
   pour surcharger une ou deux valeurs du fichier, ou pour ne pas en
   utiliser.

## Méthode rapide : le fichier JSON

Créer un fichier `personal.json` à la racine du projet (un modèle
[`personal.json.example`](../../personal.json.example) est commité) :

```json
{
  "rpcUrl": "http://seedbox.local:9091/transmission/rpc",
  "rpcUser": "admin",
  "rpcPassword": "secret",
  "sessionCookie": "connect_sid=xyz",
  "tmdbKey": "tmdb-key",
  "jellyfinUrl": "http://seedbox.local:8096",
  "jellyfinKey": "jf-key",
  "ftpHost": "app.seedbox.local",
  "ftpUser": "ftpuser",
  "ftpPassword": "ftppwd",
  "ftpTls": true,
  "mediaFolders": ["/torrents/completed", "/data/media"],
  "apiKeys": {
    "c411": "abc",
    "tr4ker": "def",
    "nostradamus": "ghi",
    "astratorrent": "passkey"
  }
}
```

Le format est exactement celui de `AppSettings.toJson()` (cf.
[`lib/core/settings.dart`](../../lib/core/settings.dart)). Les champs non
renseignés prennent les valeurs par défaut.

Puis compiler :

```sh
flutter build apk --dart-define=C411_DEFAULTS_FILE=personal.json
```

Deux modes de résolution du chemin :

- **Chemin en `assets/…`** : le fichier est lu depuis le bundle d'assets
  de Flutter. Ajouter `personal.json` à la section `flutter.assets` du
  [`pubspec.yaml`](../../pubspec.yaml) au préalable :
  ```yaml
  flutter:
    assets:
      - assets/personal.json
  ```
  Puis `--dart-define=C411_DEFAULTS_FILE=assets/personal.json`.
- **Autre chemin** (absolu ou relatif) : le fichier est lu sur disque à
  chaque démarrage. Pratique en développement, ou quand le fichier est
  posé manuellement sur l'appareil (Android : `/sdcard/…` avec les
  permissions idoines).

L'APK produit, installé sur un appareil vierge, ouvre les *Réglages*
préremplis. L'utilisateur peut encore modifier n'importe quel champ —
les valeurs sont écrites dans le trousseau et les défauts de build
cessent d'avoir effet.

## Méthode ponctuelle : variables individuelles

Pour une ou deux valeurs, ou quand on n'a pas envie de gérer un fichier :

```sh
flutter build apk \
  --dart-define=C411_RPC_URL=http://seedbox.local:9091/transmission/rpc \
  --dart-define=C411_RPC_USER=admin \
  --dart-define=C411_RPC_PASSWORD=**** \
  --dart-define=C411_C411_KEY=**** \
  --dart-define=C411_TR4KER_KEY=**** \
  --dart-define=C411_NOSTRADAMUS_KEY=**** \
  --dart-define=C411_ASTRATORRENT_KEY=**** \
  --dart-define=C411_SESSION_COOKIE=connect_sid=**** \
  --dart-define=C411_TMDB_KEY=**** \
  --dart-define=C411_JELLYFIN_URL=http://seedbox.local:8096 \
  --dart-define=C411_JELLYFIN_KEY=**** \
  --dart-define=C411_FTP_HOST=app.seedbox.local \
  --dart-define=C411_FTP_USER=**** \
  --dart-define=C411_FTP_PASSWORD=**** \
  --dart-define=C411_FTP_TLS=true \
  --dart-define=C411_MEDIA_FOLDERS=/torrents/completed,/data/media
```

Les variables reconnues sont :

| Variable                       | Champ `AppSettings`    | Exemple |
|--------------------------------|------------------------|---------|
| `C411_RPC_URL`                 | `rpcUrl`               | `http://seedbox:9091/transmission/rpc` |
| `C411_RPC_USER`                | `rpcUser`              | `admin` |
| `C411_RPC_PASSWORD`            | `rpcPassword`          | `secret` |
| `C411_SESSION_COOKIE`          | `sessionCookie`        | `connect_sid=abc; session=def` |
| `C411_TMDB_KEY`                | `tmdbKey`              | clé API TMDB ou jeton de lecture |
| `C411_JELLYFIN_URL`            | `jellyfinUrl`          | `http://seedbox:8096` |
| `C411_JELLYFIN_KEY`            | `jellyfinKey`          | clé API Jellyfin |
| `C411_FTP_HOST`                | `ftpHost`              | `app.seedbox.local` |
| `C411_FTP_PORT`                | `ftpPort`              | `21` |
| `C411_FTP_USER`                | `ftpUser`              | utilisateur FTP |
| `C411_FTP_PASSWORD`            | `ftpPassword`          | mot de passe FTP |
| `C411_FTP_TLS`                 | `ftpTls`               | `true` / `false` |
| `C411_MEDIA_FOLDERS`           | `mediaFolders`         | `/films,/series` (CSV) |
| `C411_<TRACKER>_KEY`           | `apiKeys[<tracker>]`   | clé API ou passkey |

`<TRACKER>` est l'un de : `C411`, `TR4KER`, `NOSTRADAMUS`,
`ASTRATORRENT`. La clé est stockée dans `apiKeys` sous le nom en
camelCase du tracker (`c411`, `tr4ker`, …) — l'alignement exact est
maintenu par `BuildDefaults.toAppSettings` dans
[`lib/build_defaults.dart`](../../lib/build_defaults.dart) et doit
rester synchronisé avec l'enum `Tracker` de
[`lib/api/tracker.dart`](../../lib/api/tracker.dart).

## Combinaison

Si le même nom est défini à la fois dans le fichier et en
`--dart-define`, c'est la variable individuelle qui l'emporte. Pratique
pour corriger une seule valeur à la compilation sans éditer le JSON :

```sh
flutter build apk \
  --dart-define=C411_DEFAULTS_FILE=personal.json \
  --dart-define=C411_RPC_PASSWORD=otherpassword
```

## Sécurité

Les deux mécanismes placent les valeurs dans le binaire (l'asset est
intégré à l'APK, les `--dart-define` sont compilées). Toute personne qui
décompile l'APK peut les lire. La règle simple :

- **Distribution publique** : ne mets pas les secrets en `--dart-define` ni
  dans un asset, laisse l'utilisateur les saisir dans *Réglages* (et
  donc les stocker dans le trousseau).
- **Installation familiale / poste personnel** : c'est l'usage prévu. Le
  binaire n'est pas partagé.

Si l'utilisateur veut repartir d'un trousseau vierge (pour annuler les
défauts de build), il peut effacer les clés dans *Réglages → Avancé* ou
réinitialiser le trousseau du système d'exploitation ; au prochain
lancement, les défauts seront réappliqués.

## Mise à jour

Quand un nouveau champ est ajouté à `AppSettings` :

1. ajouter le mapping dans `BuildDefaults.toAppSettings`,
2. ajouter l'entrée dans `BuildDefaults.allVariables`,
3. ajouter la ligne dans le tableau ci-dessus,
4. ajouter le champ dans [`personal.json.example`](../../personal.json.example),
5. ajouter un test dans `test/build_defaults_test.dart` ou
   `test/settings_test.dart`.

Sans l'étape 1, le champ reste vide sur la variante compilée.