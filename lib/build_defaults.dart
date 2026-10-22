import 'core/settings.dart';

/// Réglages injectés au build via `--dart-define`. Permettent de produire
/// une variante de l'application avec tous les identifiants préenregistrés :
/// au premier lancement (trousseau vide), ils sont écrits dans le trousseau
/// du système. Les lancements suivants lisent depuis le trousseau et les
/// modifications dans *Réglages* priment toujours.
///
/// Les valeurs sont **compilées dans le binaire**, donc lisibles par
/// quiconque décompile l'APK. Pour une distribution largement partagée,
/// garder les secrets dans le trousseau du système (Réglage normal). Pour
/// une image *personnelle* ou familiale, c'est l'usage prévu.
///
/// Pour ranger les réglages dans un fichier JSON plutôt qu'en ligne de
/// commande, voir [`tool/build_personal.dart`](../tool/build_personal.dart) :
/// il convertit un JSON en `--dart-define` (et peut lancer `flutter build`
/// à la place de l'utilisateur).
class BuildDefaults {
  const BuildDefaults();

  bool get hasAny =>
      _has(_rpcUrl) ||
      _has(_rpcUser) ||
      _has(_rpcPassword) ||
      _has(_sessionCookie) ||
      _has(_tmdbKey) ||
      _has(_jellyfinUrl) ||
      _has(_jellyfinKey) ||
      _has(_ftpHost) ||
      _has(_ftpPort) ||
      _has(_ftpUser) ||
      _has(_ftpPassword) ||
      _has(_ftpTls) ||
      _has(_filesProtocol) ||
      _has(_webdavUrl) ||
      _has(_webdavUser) ||
      _has(_webdavPassword) ||
      _has(_localRoot) ||
      _has(_mediaFolders) ||
      _has(_c411Key) ||
      _has(_tr4kerKey) ||
      _has(_nostradamusKey) ||
      _has(_astratorrentKey);

  AppSettings toAppSettings() {
    final foldersCsv = _str(_mediaFolders);
    final folders = foldersCsv == null
        ? const <String>[]
        : (foldersCsv.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)
            .toList());
    final apiKeys = <String, String>{};
    if (_str(_c411Key) case final v?) apiKeys['c411'] = v;
    if (_str(_tr4kerKey) case final v?) apiKeys['tr4ker'] = v;
    if (_str(_nostradamusKey) case final v?) apiKeys['nostradamus'] = v;
    if (_str(_astratorrentKey) case final v?) apiKeys['astratorrent'] = v;
    return AppSettings(
      rpcUrl: _str(_rpcUrl) ?? '',
      rpcUser: _str(_rpcUser) ?? '',
      rpcPassword: _str(_rpcPassword) ?? '',
      apiKeys: apiKeys,
      sessionCookie: _str(_sessionCookie) ?? '',
      tmdbKey: _str(_tmdbKey) ?? '',
      jellyfinUrl: _str(_jellyfinUrl) ?? '',
      jellyfinKey: _str(_jellyfinKey) ?? '',
      ftpHost: _str(_ftpHost) ?? '',
      ftpPort: int.tryParse(_str(_ftpPort) ?? '') ?? 21,
      ftpUser: _str(_ftpUser) ?? '',
      ftpPassword: _str(_ftpPassword) ?? '',
      ftpTls: _bool(_ftpTls) ?? true,
      filesProtocol: _str(_filesProtocol) ?? 'ftp',
      webdavUrl: _str(_webdavUrl) ?? '',
      webdavUser: _str(_webdavUser) ?? '',
      webdavPassword: _str(_webdavPassword) ?? '',
      localRoot: _str(_localRoot) ?? '',
      mediaFolders: folders,
    );
  }

  /// Liste des variables reconnues. Sert au test et à la doc.
  static const List<String> allVariables = [
    'C411_RPC_URL',
    'C411_RPC_USER',
    'C411_RPC_PASSWORD',
    'C411_SESSION_COOKIE',
    'C411_TMDB_KEY',
    'C411_JELLYFIN_URL',
    'C411_JELLYFIN_KEY',
    'C411_FTP_HOST',
    'C411_FTP_PORT',
    'C411_FTP_USER',
    'C411_FTP_PASSWORD',
    'C411_FTP_TLS',
    'C411_FILES_PROTOCOL',
    'C411_WEBDAV_URL',
    'C411_WEBDAV_USER',
    'C411_WEBDAV_PASSWORD',
    'C411_LOCAL_ROOT',
    'C411_MEDIA_FOLDERS',
    'C411_C411_KEY',
    'C411_TR4KER_KEY',
    'C411_NOSTRADAMUS_KEY',
    'C411_ASTRATORRENT_KEY',
  ];
}

// Chaque variable est lue par `String.fromEnvironment` (const) puis stockée
// dans une constante top-level. `String.fromEnvironment` exige un littéral
// en argument, d'où la multiplication des constantes.

const String _rpcUrl = String.fromEnvironment('C411_RPC_URL');
const String _rpcUser = String.fromEnvironment('C411_RPC_USER');
const String _rpcPassword = String.fromEnvironment('C411_RPC_PASSWORD');
const String _sessionCookie = String.fromEnvironment('C411_SESSION_COOKIE');
const String _tmdbKey = String.fromEnvironment('C411_TMDB_KEY');
const String _jellyfinUrl = String.fromEnvironment('C411_JELLYFIN_URL');
const String _jellyfinKey = String.fromEnvironment('C411_JELLYFIN_KEY');
const String _ftpHost = String.fromEnvironment('C411_FTP_HOST');
const String _ftpPort = String.fromEnvironment('C411_FTP_PORT');
const String _ftpUser = String.fromEnvironment('C411_FTP_USER');
const String _ftpPassword = String.fromEnvironment('C411_FTP_PASSWORD');
const String _ftpTls = String.fromEnvironment('C411_FTP_TLS');
const String _filesProtocol = String.fromEnvironment('C411_FILES_PROTOCOL');
const String _webdavUrl = String.fromEnvironment('C411_WEBDAV_URL');
const String _webdavUser = String.fromEnvironment('C411_WEBDAV_USER');
const String _webdavPassword = String.fromEnvironment('C411_WEBDAV_PASSWORD');
const String _localRoot = String.fromEnvironment('C411_LOCAL_ROOT');
const String _mediaFolders = String.fromEnvironment('C411_MEDIA_FOLDERS');
const String _c411Key = String.fromEnvironment('C411_C411_KEY');
const String _tr4kerKey = String.fromEnvironment('C411_TR4KER_KEY');
const String _nostradamusKey = String.fromEnvironment('C411_NOSTRADAMUS_KEY');
const String _astratorrentKey = String.fromEnvironment('C411_ASTRATORRENT_KEY');

String? _str(String v) => v.isEmpty ? null : v;

bool? _bool(String v) {
  if (v.isEmpty) return null;
  final low = v.toLowerCase();
  return low == 'true' || low == '1' || low == 'yes';
}

bool _has(String v) => v.isNotEmpty;