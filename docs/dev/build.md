# Compilation personnalisée

[← Sommaire](../README.md)

C411 Remote peut être compilé dans une **variante personnelle** : au
premier lancement, les réglages passés à la compilation sont écrits dans
le trousseau du système (libsecret, Keychain, Keystore), comme si
l'utilisateur venait de les saisir. Les lancements suivants lisent depuis
le trousseau et les modifications dans *Réglages* priment toujours.

## Méthode recommandée : le fichier JSON

Tu mets tes identifiants dans un JSON local
([`personal.json.example`](../../personal.json.example) est commité comme
modèle), et l'outil
[`tool/build_personal.dart`](../../tool/build_personal.dart) le convertit
en `--dart-define` *au moment du build*. Les valeurs sont alors
**compilées dans le binaire** : le JSON lui-même ne va pas dans l'APK.

```sh
# Copier le modèle, éditer, sauvegarder
cp personal.json.example personal.json
$EDITOR personal.json

# Compiler en une commande : l'outil génère les --dart-define et lance
# `flutter build apk`.
dart run tool/build_personal.dart personal.json --build apk
```

Pour juste voir les flags générés (par exemple pour les passer
manuellement à un autre `flutter build`) :

```sh
dart run tool/build_personal.dart personal.json
# Affiche :
#   --dart-define=C411_RPC_URL=http://...
#   --dart-define=C411_RPC_USER=admin
#   ...
```

`personal.json` est listé dans `.gitignore` pour ne pas committer tes
secrets par accident. Le modèle `personal.json.example`, lui, est commité.

### Format JSON

Exactement celui de [`AppSettings.toJson()`](../../lib/core/settings.dart).
Les champs non renseignés prennent les valeurs par défaut.

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
  "ftpPort": 21,
  "ftpUser": "ftpuser",
  "ftpPassword": "ftppwd",
  "ftpTls": true,
  "filesProtocol": "ftp",
  "webdavUrl": "",
  "webdavUser": "",
  "webdavPassword": "",
  "localRoot": "",
  "mediaFolders": ["/torrents/completed", "/data/media"],
  "apiKeys": {
    "c411": "abc",
    "tr4ker": "def",
    "nostradamus": "ghi",
    "draupnirr": "jkl",
    "astra": "passkey"
  }
}
```

`filesProtocol` vaut `ftp` (par défaut), `webdav` (fichiers lus sur le
partage `webdavUrl`) ou `local` (dossier `localRoot` de la machine) (voir
[Configuration](../guide/configuration.md#serveur-de-fichiers-ftp)), et les
serveurs web (C411 TV, Musique, Livres) font de même.

### Cibles supportées par `--build`

Tout ce que `flutter build` accepte : `apk`, `appbundle`, `linux`, `web`,
`ios`, `macos`, `windows`, etc.

```sh
dart run tool/build_personal.dart personal.json --build linux
dart run tool/build_personal.dart personal.json --build appbundle
```

## Méthode ponctuelle : variables individuelles

Pour une ou deux valeurs à modifier sans toucher au fichier, ou pour
intégrer le build dans un script shell existant :

```sh
flutter build apk \
  --dart-define=C411_RPC_URL=http://seedbox:9091/transmission/rpc \
  --dart-define=C411_RPC_USER=admin \
  --dart-define=C411_C411_KEY=**** \
  ...
```

Voir le tableau des variables dans
[`lib/build_defaults.dart`](../../lib/build_defaults.dart) (`allVariables`).

## Méthode manuelle

Tu peux aussi concaténer toi-même la sortie de l'outil à une commande
`flutter build` :

```sh
FLAGS=$(dart run tool/build_personal.dart personal.json)
flutter build apk $FLAGS
```

Pratique pour intégrer le build dans un script plus large, ou pour
ajouter des flags supplémentaires (release, split-per-abi, etc.).

## Sécurité

Les valeurs sont **compilées dans le binaire** : le JSON source ne va
pas dans l'APK, mais toute personne qui décompile l'APK peut lire les
constantes. La règle :

- **Distribution publique** : ne mets pas les secrets en `--dart-define`,
  laisse l'utilisateur les saisir dans *Réglages* (stockage dans le
  trousseau).
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
3. ajouter le champ dans [`personal.json.example`](../../personal.json.example),
4. ajouter le mapping dans `tool/build_personal.dart.personalJsonToFlags`,
5. ajouter un test dans `test/build_defaults_test.dart` ou
   `test/build_personal_test.dart`.

Sans l'étape 1, le champ reste vide sur la variante compilée.
Sans l'étape 4, le JSON peut contenir le champ mais il ne sera pas
transmis à `flutter build`.
## Compilation automatique (GitHub Actions)

Le fichier `.github/workflows/build.yml` compile l'application à chaque
poussée sur `master`, à chaque tag `v…`, à chaque pull request, ou à la
demande (*Actions › Build › Run workflow*). Ses tâches :

1. **Analyse et tests** : `flutter analyze`, `flutter test`, puis les tests
   des serveurs web (`web_player`, `web_music`, `web_books`).
2. Ensuite, en parallèle :
   - **APK Android** : `flutter build apk --release`, signé avec la clé de
     débogage comme en local ;
   - **Linux** : `flutter build linux`, avec GTK, libmpv, libsecret et
     jsoncpp installés ;
   - **Windows** : `flutter build windows`, en ajoutant le composant ATL de
     Visual Studio s'il manque (exigé par `flutter_secure_storage`).

Les binaires sont attachés à l'exécution pendant 14 jours (*Artifacts*) :
- l'APK ;
- `c411_remote-linux-x64.tar.gz`, le dossier `bundle` à décompresser ;
- `c411_remote-windows-x64.zip`, le dossier `Release`.

Flutter est figé à la version utilisée en local (`FLUTTER_VERSION`, en tête
du fichier). Ces binaires ne contiennent aucun réglage préenregistré : la
variante personnelle (`tool/build_personal.dart`) se compile en local, pour
ne pas mettre d'identifiants dans les secrets du dépôt.
