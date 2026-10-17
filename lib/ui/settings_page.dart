import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/c411.dart';
import '../api/transmission.dart';
import '../core/settings.dart';
import 'server_settings_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _apiKey = TextEditingController();
  bool _initialized = false;
  bool _showSecrets = false;
  bool _testing = false;
  String? _rpcStatus;
  String? _trackerStatus;

  @override
  void dispose() {
    for (final c in [_url, _user, _password, _apiKey]) {
      c.dispose();
    }
    super.dispose();
  }

  AppSettings get _form => AppSettings(
        rpcUrl: _url.text.trim(),
        rpcUser: _user.text.trim(),
        rpcPassword: _password.text,
        apiKey: _apiKey.text.trim(),
      );

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
          url: s.rpcUrl, user: s.rpcUser, password: s.rpcPassword);
      final session = await client.sessionGet();
      _setStatus(() => _rpcStatus = '✓ Transmission ${session['version']}');
      return true;
    } on TransmissionException catch (e) {
      _setStatus(() => _rpcStatus = '✗ ${e.message}');
      return false;
    }
  }

  Future<bool> _testTracker() async {
    final s = _form;
    if (!s.hasTracker) {
      _setStatus(() => _trackerStatus = '✗ Clé API manquante');
      return false;
    }
    _setStatus(() => _trackerStatus = 'Connexion…');
    try {
      final page = await C411Api(s.apiKey).releases(perPage: 1);
      _setStatus(() => _trackerStatus = '✓ ${page.total} torrents disponibles');
      return true;
    } on C411Exception catch (e) {
      _setStatus(() => _trackerStatus = '✗ ${e.message}');
      return false;
    }
  }

  /// Teste en parallèle les connexions renseignées.
  Future<bool> _testAll() async {
    final s = _form;
    setState(() => _testing = true);
    final results = await Future.wait([
      if (s.hasTransmission) _testTransmission(),
      if (s.hasTracker) _testTracker(),
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
          content: Text([
            if (_rpcStatus?.startsWith('✗') ?? false) 'Transmission : $_rpcStatus',
            if (_trackerStatus?.startsWith('✗') ?? false) 'C411 : $_trackerStatus',
            '',
            'Enregistrer quand même ?',
          ].join('\n')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Enregistrer quand même')),
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
      _apiKey.text = saved.apiKey;
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: settings.isLoading && saved == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (settings.hasError)
                    Text('Lecture du trousseau impossible : ${settings.error}',
                        style: TextStyle(color: theme.colorScheme.error)),
                  Text('Serveur Transmission', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Adresse RPC',
                      hintText: 'https://serveur:9091/transmission/rpc',
                      helperText:
                          'Sans chemin, /transmission/rpc est ajouté automatiquement',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _user,
                        decoration: const InputDecoration(
                            labelText: 'Utilisateur',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _password,
                        obscureText: !_showSecrets,
                        decoration: const InputDecoration(
                            labelText: 'Mot de passe',
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    OutlinedButton(
                        onPressed: _testTransmission,
                        child: const Text('Tester')),
                    const SizedBox(width: 12),
                    if (_rpcStatus != null) Expanded(child: Text(_rpcStatus!)),
                  ]),
                  const SizedBox(height: 24),
                  Text('Tracker C411', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKey,
                    obscureText: !_showSecrets,
                    decoration: const InputDecoration(
                      labelText: 'Clé API',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    OutlinedButton(
                        onPressed: _testTracker, child: const Text('Tester')),
                    const SizedBox(width: 12),
                    if (_trackerStatus != null)
                      Expanded(child: Text(_trackerStatus!)),
                  ]),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Afficher les secrets'),
                    value: _showSecrets,
                    onChanged: (v) => setState(() => _showSecrets = v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _testAll,
                      icon: _testing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.network_check),
                      label: const Text('Tester les connexions'),
                    ),
                    FilledButton.icon(
                      onPressed: _testing ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Tester et enregistrer'),
                    ),
                  ]),
                  const Divider(height: 32),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tune),
                    title: const Text('Configuration du serveur Transmission'),
                    subtitle: const Text(
                        'Dossier, limites de vitesse, file d’attente, ratio…'),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: ref.watch(transmissionProvider) != null,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ServerSettingsPage())),
                  ),
                ]),
              ),
            ),
    );
  }
}
