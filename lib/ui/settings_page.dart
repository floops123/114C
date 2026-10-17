import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/astra.dart';
import '../api/c411_socket.dart';
import '../api/tmdb.dart';
import '../api/tracker.dart';
import '../api/transmission.dart';
import '../core/settings.dart';
import '../core/preferences.dart';
import 'server_settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _apiKeys = {for (final t in Tracker.values) t: TextEditingController()};
  bool _initialized = false;
  bool _showSecrets = false;
  bool _testing = false;
  String? _rpcStatus;
  final _trackerStatus = <Tracker, String>{};
  final _cookie = TextEditingController();
  String? _cookieStatus;
  final _tmdb = TextEditingController();
  String? _tmdbStatus;

  @override
  void dispose() {
    for (final c in [_url, _user, _password, _cookie, _tmdb, ..._apiKeys.values]) {
      c.dispose();
    }
    super.dispose();
  }

  AppSettings get _form => AppSettings(
    rpcUrl: _url.text.trim(),
    rpcUser: _user.text.trim(),
    rpcPassword: _password.text,
    apiKeys: {
      for (final MapEntry(:key, :value) in _apiKeys.entries)
        if (value.text.trim().isNotEmpty) key.name: value.text.trim(),
    },
    sessionCookie: normalizeCookie(_cookie.text),
    tmdbKey: _tmdb.text.trim(),
  );

  Future<void> _testTmdb() async {
    final key = _tmdb.text.trim();
    if (key.isEmpty) {
      _setStatus(() => _tmdbStatus = '✗ Clé manquante');
      return;
    }
    _setStatus(() => _tmdbStatus = 'Connexion…');
    try {
      await TmdbApi(key).check();
      _setStatus(() => _tmdbStatus = '✓ Clé acceptée');
    } on TmdbException catch (e) {
      _setStatus(() => _tmdbStatus = '✗ ${e.message}');
    }
  }

  /// Teste le cookie sur le WebSocket : connexion acceptée ou refusée.
  Future<void> _testCookie() async {
    final cookie = normalizeCookie(_cookie.text);
    if (cookie.isEmpty) {
      _setStatus(() => _cookieStatus = '✗ Cookie manquant');
      return;
    }
    _setStatus(() => _cookieStatus = 'Connexion…');
    final result = Completer<String>();
    final socket = C411Socket(
      cookie,
      onStatus: (s) {
        if (s == SocketStatus.connected && !result.isCompleted) {
          result.complete('✓ Session acceptée');
        }
      },
      onError: (e) {
        if (!result.isCompleted) result.complete('✗ $e');
      },
    );
    await socket.connect();
    final text = await result.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => '✗ Pas de réponse du serveur',
    );
    await socket.close();
    _setStatus(() => _cookieStatus = text);
  }

  void _setStatus(void Function() update) {
    if (mounted) setState(update);
  }

  Future<bool> _testTransmission() async {
    final s = _form;
    if (!s.hasTransmission) {
      _setStatus(() => _rpcStatus = '✗ Adresse RPC manquante');
      return false;
    }
    _setStatus(() => _rpcStatus = 'Connexion…');
    try {
      final client = TransmissionClient(
        url: s.rpcUrl,
        user: s.rpcUser,
        password: s.rpcPassword,
      );
      final session = await client.sessionGet();
      _setStatus(() => _rpcStatus = '✓ Transmission ${session['version']}');
      return true;
    } on TransmissionException catch (e) {
      _setStatus(() => _rpcStatus = '✗ ${e.message}');
      return false;
    }
  }

  Future<bool> _testTracker(Tracker tracker) async {
    final key = _apiKeys[tracker]!.text.trim();
    if (key.isEmpty) {
      _setStatus(() => _trackerStatus[tracker] = '✗ Clé API manquante');
      return false;
    }
    _setStatus(() => _trackerStatus[tracker] = 'Connexion…');
    try {
      // Le flux RSS répond même sans passkey : on la vérifie par le scanner.
      if (tracker.client(key) case final AstraApi astra) {
        final user = await astra.username();
        _setStatus(() => _trackerStatus[tracker] =
            user == null ? '✗ Passkey refusée' : '✓ Connecté : $user');
        return user != null;
      }
      final page = await tracker.client(key).releases(perPage: 1);
      _setStatus(
        () => _trackerStatus[tracker] = page.total > 0
            ? '✓ ${page.total} torrents disponibles'
            : '✓ Connexion réussie',
      );
      return true;
    } on TrackerException catch (e) {
      _setStatus(() => _trackerStatus[tracker] = '✗ ${e.message}');
      return false;
    }
  }

  /// Teste en parallèle les connexions renseignées.
  Future<bool> _testAll() async {
    final s = _form;
    setState(() => _testing = true);
    final results = await Future.wait([
      if (s.hasTransmission) _testTransmission(),
      for (final t in Tracker.values)
        if (s.apiKeys.containsKey(t.name)) _testTracker(t),
    ]);
    _setStatus(() => _testing = false);
    return results.every((ok) => ok);
  }

  /// On teste avant d'enregistrer ; en cas d'échec on demande confirmation
  /// (le serveur peut être temporairement éteint).
  Future<void> _save() async {
    final ok = await _testAll();
    if (!mounted) return;
    if (!ok) {
      final force = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Échec de la connexion'),
          content: Text(
            [
              if (_rpcStatus?.startsWith('✗') ?? false)
                'Transmission : $_rpcStatus',
              for (final MapEntry(:key, :value) in _trackerStatus.entries)
                if (value.startsWith('✗')) '${key.label} : $value',
              '',
              'Enregistrer quand même ?',
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer quand même'),
            ),
          ],
        ),
      );
      if (force != true || !mounted) return;
    }
    await ref.read(settingsProvider.notifier).save(_form);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Réglages enregistrés')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final saved = settings.value;
    if (saved != null && !_initialized) {
      _initialized = true;
      _url.text = saved.rpcUrl;
      _user.text = saved.rpcUser;
      _password.text = saved.rpcPassword;
      for (final MapEntry(:key, :value) in _apiKeys.entries) {
        value.text = saved.apiKeys[key.name] ?? '';
      }
      _cookie.text = saved.sessionCookie;
      _tmdb.text = saved.tmdbKey;
    }
    final c = context.colors;
    final themeMode = ref.watch(uiPrefsProvider.select((p) => p.themeMode));
    final narrow = MediaQuery.sizeOf(context).width < 600;

    Widget status(String? text) {
      if (text == null) return const SizedBox.shrink();
      final color = text.startsWith('✓')
          ? c.success
          : text.startsWith('✗')
          ? c.danger
          : c.muted;
      return Expanded(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Scaffold(
      body: settings.isLoading && saved == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const PageHeader(title: 'Réglages'),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (settings.hasError)
                            ErrorBanner(
                              'Lecture du trousseau impossible : ${settings.error}',
                            ),
                          Section(
                            title: 'Apparence',
                            children: [
                              SegmentedButton<ThemeMode>(
                                showSelectedIcon: false,
                                segments: [
                                  ButtonSegment(
                                    value: ThemeMode.system,
                                    icon: narrow
                                        ? null
                                        : const Icon(
                                            Icons.brightness_auto_outlined,
                                            size: 18,
                                          ),
                                    label: const Text('Système'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.light,
                                    icon: narrow
                                        ? null
                                        : const Icon(
                                            Icons.light_mode_outlined,
                                            size: 18,
                                          ),
                                    label: const Text('Clair'),
                                  ),
                                  ButtonSegment(
                                    value: ThemeMode.dark,
                                    icon: narrow
                                        ? null
                                        : const Icon(
                                            Icons.dark_mode_outlined,
                                            size: 18,
                                          ),
                                    label: const Text('Sombre'),
                                  ),
                                ],
                                selected: {themeMode},
                                onSelectionChanged: (s) => ref
                                    .read(uiPrefsProvider.notifier)
                                    .setThemeMode(s.first),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Section(
                            title: 'Serveur Transmission',
                            children: [
                              TextField(
                                controller: _url,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(
                                  labelText: 'Adresse RPC',
                                  hintText:
                                      'https://serveur:9091/transmission/rpc',
                                  helperText: 'Sans chemin, /transmission/rpc est ajouté automatiquement',
                                  helperMaxLines: 2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _user,
                                      decoration: const InputDecoration(
                                        labelText: 'Utilisateur',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _password,
                                      obscureText: !_showSecrets,
                                      decoration: const InputDecoration(
                                        labelText: 'Mot de passe',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: _testTransmission,
                                    child: const Text('Tester'),
                                  ),
                                  const SizedBox(width: 12),
                                  status(_rpcStatus),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.dns_outlined),
                                title: const Text('Configuration du serveur'),
                                subtitle: const Text(
                                  'Dossier, vitesses, files d’attente, ratio…',
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                enabled:
                                    ref.watch(transmissionProvider) != null,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ServerSettingsPage(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final t in Tracker.values) ...[
                            Section(
                              title: 'Tracker ${t.label}',
                              children: [
                                TextField(
                                  controller: _apiKeys[t],
                                  obscureText: !_showSecrets,
                                  decoration: InputDecoration(
                                    labelText: t.keyLabel,
                                    helperText: 'Laisser vide pour désactiver',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => _testTracker(t),
                                      child: const Text('Tester'),
                                    ),
                                    const SizedBox(width: 12),
                                    status(_trackerStatus[t]),
                                  ],
                                ),
                                if (t == Tracker.c411) ...[
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _cookie,
                                    obscureText: !_showSecrets,
                                    decoration: const InputDecoration(
                                      labelText:
                                          'Cookies de session (notifications)',
                                      helperMaxLines: 4,
                                      helperText:
                                          'Navigateur connecté à c411.org → outils de '
                                          'développement (F12) → Réseau → une requête '
                                          'vers c411.org → en-têtes de requête → copier '
                                          'la valeur de « Cookie ». À recoller quand la '
                                          'session expire.',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      OutlinedButton(
                                        onPressed: _testCookie,
                                        child: const Text('Tester'),
                                      ),
                                      const SizedBox(width: 12),
                                      status(_cookieStatus),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          Section(
                            title: 'TMDB (liste de souhaits)',
                            children: [
                              TextField(
                                controller: _tmdb,
                                obscureText: !_showSecrets,
                                decoration: const InputDecoration(
                                  labelText: 'Clé d’API ou jeton de lecture',
                                  helperMaxLines: 3,
                                  helperText:
                                      'Compte gratuit sur themoviedb.org → '
                                      'Paramètres → API. Laisser vide pour '
                                      'désactiver la recherche.',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  OutlinedButton(
                                    onPressed: _testTmdb,
                                    child: const Text('Tester'),
                                  ),
                                  const SizedBox(width: 12),
                                  status(_tmdbStatus),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            title: const Text('Afficher les secrets'),
                            value: _showSecrets,
                            onChanged: (v) => setState(() => _showSecrets = v),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _testing ? null : _testAll,
                                icon: _testing
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.network_check_rounded,
                                        size: 18,
                                      ),
                                label: const Text('Tester les connexions'),
                              ),
                              FilledButton.icon(
                                onPressed: _testing ? null : _save,
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Tester et enregistrer'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
