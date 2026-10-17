import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/format.dart';
import 'widgets.dart';

/// Réglages de session Transmission (`session-get` / `session-set`).
class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  Map<String, dynamic>? _session;
  int? _freeSpace;
  String? _error;
  bool _saving = false;
  final _bools = <String, bool>{};
  final _fields = <String, TextEditingController>{};

  static const _textKeys = ['download-dir'];
  static const _intKeys = [
    'speed-limit-down', 'speed-limit-up', 'alt-speed-down', 'alt-speed-up',
    'peer-limit-global', 'peer-limit-per-torrent', 'download-queue-size',
    'seed-queue-size', 'idle-seeding-limit',
  ];
  static const _doubleKeys = ['seedRatioLimit'];
  static const _boolKeys = [
    'start-added-torrents', 'speed-limit-down-enabled',
    'speed-limit-up-enabled', 'alt-speed-enabled', 'download-queue-enabled',
    'seed-queue-enabled', 'seedRatioLimited', 'idle-seeding-limit-enabled',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.read(transmissionProvider);
    if (client == null) return;
    try {
      final s = await client.sessionGet();
      int? free;
      final dir = s['download-dir'] as String?;
      if (dir != null) free = await client.freeSpace(dir).catchError((_) => null);
      if (!mounted) return;
      setState(() {
        _session = s;
        _freeSpace = free;
        _error = null;
        for (final k in _boolKeys) {
          if (s[k] is bool) _bools[k] = s[k] as bool;
        }
        for (final k in [..._textKeys, ..._intKeys, ..._doubleKeys]) {
          if (s[k] != null) {
            (_fields[k] ??= TextEditingController()).text = '${s[k]}';
          }
        }
      });
    } on TransmissionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final client = ref.read(transmissionProvider);
    if (client == null) return;
    final args = <String, dynamic>{..._bools};
    for (final k in _textKeys) {
      if (_fields[k] != null) args[k] = _fields[k]!.text.trim();
    }
    for (final k in _intKeys) {
      final v = int.tryParse(_fields[k]?.text.trim() ?? '');
      if (v != null) args[k] = v;
    }
    for (final k in _doubleKeys) {
      final v = double.tryParse(
          (_fields[k]?.text.trim() ?? '').replaceAll(',', '.'));
      if (v != null) args[k] = v;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await client.sessionSet(args);
      messenger.showSnackBar(
          const SnackBar(content: Text('Configuration du serveur enregistrée')));
      await _load();
    } on TransmissionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _switch(String key, String label, {String? subtitle}) {
    if (!_bools.containsKey(key)) return const SizedBox.shrink();
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: _bools[key]!,
      onChanged: (v) => setState(() => _bools[key] = v),
    );
  }

  Widget _field(String key, String label, {String? suffix, bool number = true}) {
    final c = _fields[key];
    if (c == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Serveur Transmission'),
        actions: [
          IconButton(
            tooltip: 'Enregistrer',
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            onPressed: s == null || _saving ? null : _save,
          ),
        ],
      ),
      body: _error != null
          ? EmptyState(Icons.error_outline, _error!,
              action: OutlinedButton(
                  onPressed: _load, child: const Text('Réessayer')))
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('Transmission ${s['version']} · RPC ${s['rpc-version']}'
                            '${_freeSpace != null ? ' · ${formatBytes(_freeSpace!)} libres' : ''}'),
                        _section('Téléchargements'),
                        _field('download-dir', 'Dossier de téléchargement',
                            number: false),
                        _switch('start-added-torrents',
                            'Démarrer les torrents ajoutés'),
                        _section('Limites de vitesse'),
                        _switch('speed-limit-down-enabled', 'Limiter la réception'),
                        _field('speed-limit-down', 'Réception max', suffix: 'Ko/s'),
                        _switch('speed-limit-up-enabled', 'Limiter l’envoi'),
                        _field('speed-limit-up', 'Envoi max', suffix: 'Ko/s'),
                        _switch('alt-speed-enabled', 'Mode tortue',
                            subtitle: 'Limites alternatives ci-dessous'),
                        _field('alt-speed-down', 'Réception (tortue)', suffix: 'Ko/s'),
                        _field('alt-speed-up', 'Envoi (tortue)', suffix: 'Ko/s'),
                        _section('Files d’attente'),
                        _switch('download-queue-enabled',
                            'Limiter les téléchargements simultanés'),
                        _field('download-queue-size', 'Téléchargements actifs max'),
                        _switch('seed-queue-enabled', 'Limiter les partages simultanés'),
                        _field('seed-queue-size', 'Partages actifs max'),
                        _section('Partage'),
                        _switch('seedRatioLimited',
                            'Arrêter le partage au ratio'),
                        _field('seedRatioLimit', 'Ratio'),
                        _switch('idle-seeding-limit-enabled',
                            'Arrêter le partage après inactivité'),
                        _field('idle-seeding-limit', 'Inactivité', suffix: 'min'),
                        _section('Connexions'),
                        _field('peer-limit-global', 'Pairs max (global)'),
                        _field('peer-limit-per-torrent', 'Pairs max par torrent'),
                      ],
                    ),
                  ),
                ),
    );
  }
}
