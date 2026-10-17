import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import '../core/format.dart';
import 'bandwidth_groups_page.dart';
import 'theme.dart';
import 'widgets.dart';

// Réglages de session Transmission, d'après la spécification RPC et
// docs/Editing-Configuration-Files.md. Les clés sont celles du protocole RPC
// historique (kebab-case), toujours accepté par Transmission 4.x. Une option
// n'est affichée que si le serveur la renvoie dans `session-get` : la page
// s'adapte ainsi aux versions 3.x, 4.0 et 4.1.

sealed class _Opt {
  const _Opt(this.key, this.label, {this.help, this.dependsOn});
  final String key;
  final String label;
  final String? help;

  /// Option booléenne qui doit être active pour que celle-ci soit éditable.
  final String? dependsOn;
}

class _Bool extends _Opt {
  const _Bool(super.key, super.label, {super.help});
}

class _Int extends _Opt {
  const _Int(
    super.key,
    super.label, {
    this.suffix,
    super.help,
    super.dependsOn,
  });
  final String? suffix;
}

class _Decimal extends _Opt {
  const _Decimal(super.key, super.label, {super.dependsOn});
}

class _Text extends _Opt {
  const _Text(
    super.key,
    super.label, {
    this.multiline = false,
    super.help,
    super.dependsOn,
  });
  final bool multiline;
}

class _Encryption extends _Opt {
  const _Encryption(super.key, super.label);
}

class _Time extends _Opt {
  const _Time(super.key, super.label, {super.dependsOn});
}

class _Days extends _Opt {
  const _Days(super.key, super.label, {super.dependsOn});
}

class _Transports extends _Opt {
  const _Transports(super.key, super.label, {super.help});
}

const _sections = <(String, IconData, List<_Opt>)>[
  (
    'Téléchargements',
    Icons.folder_outlined,
    [
      _Text('download-dir', 'Dossier de téléchargement'),
      _Bool(
        'incomplete-dir-enabled',
        'Dossier séparé pour les fichiers incomplets',
      ),
      _Text(
        'incomplete-dir',
        'Dossier des fichiers incomplets',
        dependsOn: 'incomplete-dir-enabled',
      ),
      _Bool(
        'rename-partial-files',
        'Suffixe .part sur les fichiers incomplets',
      ),
      _Bool('start-added-torrents', 'Démarrer les torrents ajoutés'),
      _Bool(
        'trash-original-torrent-files',
        'Supprimer le .torrent après ajout',
      ),
      _Bool(
        'sequential-download',
        'Téléchargement séquentiel par défaut',
        help: 'Utile pour lire un fichier pendant son téléchargement',
      ),
      _Int(
        'cache-size-mb',
        'Cache disque',
        suffix: 'Mo',
        help: 'Déprécié, sera retiré dans Transmission 5',
      ),
    ],
  ),
  (
    'Limites de vitesse',
    Icons.speed_outlined,
    [
      _Bool('speed-limit-down-enabled', 'Limiter la réception'),
      _Int(
        'speed-limit-down',
        'Réception max',
        suffix: 'ko/s',
        dependsOn: 'speed-limit-down-enabled',
      ),
      _Bool('speed-limit-up-enabled', 'Limiter l’envoi'),
      _Int(
        'speed-limit-up',
        'Envoi max',
        suffix: 'ko/s',
        dependsOn: 'speed-limit-up-enabled',
      ),
    ],
  ),
  (
    'Mode tortue',
    Icons.pets_outlined,
    [
      _Bool(
        'alt-speed-enabled',
        'Activer maintenant',
        help: 'Limites alternatives, par exemple pour la journée',
      ),
      _Int('alt-speed-down', 'Réception (tortue)', suffix: 'ko/s'),
      _Int('alt-speed-up', 'Envoi (tortue)', suffix: 'ko/s'),
      _Bool(
        'alt-speed-time-enabled',
        'Planifier',
        help: 'Active et désactive le mode tortue automatiquement',
      ),
      _Time(
        'alt-speed-time-begin',
        'Début',
        dependsOn: 'alt-speed-time-enabled',
      ),
      _Time('alt-speed-time-end', 'Fin', dependsOn: 'alt-speed-time-enabled'),
      _Days('alt-speed-time-day', 'Jours', dependsOn: 'alt-speed-time-enabled'),
    ],
  ),
  (
    'Files d’attente',
    Icons.queue_outlined,
    [
      _Bool('download-queue-enabled', 'Limiter les téléchargements simultanés'),
      _Int(
        'download-queue-size',
        'Téléchargements actifs max',
        dependsOn: 'download-queue-enabled',
      ),
      _Bool('seed-queue-enabled', 'Limiter les partages simultanés'),
      _Int(
        'seed-queue-size',
        'Partages actifs max',
        dependsOn: 'seed-queue-enabled',
      ),
      _Bool(
        'queue-stalled-enabled',
        'Ignorer les torrents bloqués',
        help: 'Un torrent inactif ne compte plus dans les files',
      ),
      _Int(
        'queue-stalled-minutes',
        'Bloqué après',
        suffix: 'min',
        dependsOn: 'queue-stalled-enabled',
      ),
    ],
  ),
  (
    'Partage',
    Icons.upload_outlined,
    [
      _Bool('seedRatioLimited', 'Arrêter le partage au ratio'),
      _Decimal('seedRatioLimit', 'Ratio', dependsOn: 'seedRatioLimited'),
      _Bool(
        'idle-seeding-limit-enabled',
        'Arrêter le partage après inactivité',
      ),
      _Int(
        'idle-seeding-limit',
        'Inactivité',
        suffix: 'min',
        dependsOn: 'idle-seeding-limit-enabled',
      ),
    ],
  ),
  (
    'Réseau',
    Icons.lan_outlined,
    [
      _Int('peer-port', 'Port d’écoute'),
      _Bool('peer-port-random-on-start', 'Port aléatoire au démarrage'),
      _Bool('port-forwarding-enabled', 'Redirection de port (UPnP / NAT-PMP)'),
      _Encryption('encryption', 'Chiffrement'),
      _Transports(
        'preferred-transports',
        'Protocoles',
        help: 'Ordre de préférence ; un protocole absent est désactivé',
      ),
      _Bool('utp-enabled', 'Autoriser µTP'),
      _Int('peer-limit-global', 'Pairs max (global)'),
      _Int('peer-limit-per-torrent', 'Pairs max par torrent'),
      _Int('reqq', 'Requêtes en attente par pair'),
    ],
  ),
  (
    'Découverte de pairs',
    Icons.travel_explore_outlined,
    [
      _Bool('dht-enabled', 'DHT', help: 'Torrents publics uniquement'),
      _Bool(
        'pex-enabled',
        'Échange de pairs (PEX)',
        help: 'Torrents publics uniquement',
      ),
      _Bool(
        'lpd-enabled',
        'Découverte locale (LPD)',
        help: 'Torrents publics uniquement',
      ),
    ],
  ),
  (
    'Blocklist',
    Icons.block_outlined,
    [
      _Bool('blocklist-enabled', 'Activer la blocklist'),
      _Text(
        'blocklist-url',
        'URL de la blocklist',
        dependsOn: 'blocklist-enabled',
      ),
    ],
  ),
  (
    'Trackers par défaut',
    Icons.campaign_outlined,
    [
      _Text(
        'default-trackers',
        'Annonces ajoutées aux torrents publics',
        multiline: true,
        help: 'Une URL par ligne, une ligne vide entre deux paliers',
      ),
    ],
  ),
  (
    'Scripts',
    Icons.terminal_outlined,
    [
      _Bool('script-torrent-added-enabled', 'Script à l’ajout'),
      _Text(
        'script-torrent-added-filename',
        'Chemin du script (ajout)',
        dependsOn: 'script-torrent-added-enabled',
      ),
      _Bool('script-torrent-done-enabled', 'Script en fin de téléchargement'),
      _Text(
        'script-torrent-done-filename',
        'Chemin du script (fin)',
        dependsOn: 'script-torrent-done-enabled',
      ),
      _Bool('script-torrent-done-seeding-enabled', 'Script en fin de partage'),
      _Text(
        'script-torrent-done-seeding-filename',
        'Chemin du script (partage)',
        dependsOn: 'script-torrent-done-seeding-enabled',
      ),
    ],
  ),
  (
    'Sécurité',
    Icons.shield_outlined,
    [
      _Bool('anti-brute-force-enabled', 'Protection anti-force brute du RPC'),
      _Int(
        'anti-brute-force-threshold',
        'Échecs d’authentification avant blocage',
        dependsOn: 'anti-brute-force-enabled',
      ),
    ],
  ),
];

class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key});

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _stats;
  ({int? free, int? total})? _disk;
  String? _error;
  bool _saving = false;
  String _filter = '';
  String? _portStatus;
  String? _blocklistStatus;

  /// Valeurs éditées des options non textuelles.
  final _values = <String, dynamic>{};
  final _controllers = <String, TextEditingController>{};

  TransmissionClient? get _client => ref.read(transmissionProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    try {
      final session = await client.sessionGet();
      final stats = await client.sessionStats().catchError(
        (_) => <String, dynamic>{},
      );
      final dir = session['download-dir'] as String?;
      ({int? free, int? total})? disk;
      if (dir != null) {
        try {
          disk = await client.diskSpace(dir);
        } on TransmissionException {
          // Dossier inaccessible : on n'affiche simplement pas l'espace disque.
        }
      }
      if (!mounted) return;
      setState(() {
        _session = session;
        _stats = stats;
        _disk = disk;
        _error = null;
        _values.clear();
        for (final (_, _, opts) in _sections) {
          for (final o in opts) {
            if (!session.containsKey(o.key)) continue;
            final v = session[o.key];
            if (o is _Int || o is _Decimal || o is _Text) {
              final c = _controllers.putIfAbsent(o.key, () {
                final c = TextEditingController();
                c.addListener(() => setState(() {}));
                return c;
              });
              c.text = o is _Decimal
                  ? '${(v as num).toDouble()}'.replaceAll('.', ',')
                  : '${v ?? ''}';
            } else {
              _values[o.key] = v is List ? List.of(v) : v;
            }
          }
        }
      });
    } on TransmissionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Valeur courante d'une option ; lève FormatException si un champ est invalide.
  dynamic _current(_Opt o) => switch (o) {
    _Int() =>
      int.tryParse(_controllers[o.key]!.text.trim()) ??
          (throw FormatException(o.label)),
    _Decimal() =>
      double.tryParse(_controllers[o.key]!.text.trim().replaceAll(',', '.')) ??
          (throw FormatException(o.label)),
    _Text() => _controllers[o.key]!.text.trim(),
    _ => _values[o.key],
  };

  bool _changed(_Opt o) {
    try {
      final now = _current(o);
      final before = _session![o.key];
      if (now is List && before is List) return !listEquals(now, before);
      if (now is double && before is num) return now != before.toDouble();
      return now != before;
    } on FormatException {
      return true;
    }
  }

  Iterable<_Opt> get _available => _sections
      .expand((s) => s.$3)
      .where((o) => _session?.containsKey(o.key) ?? false);

  Future<void> _save() async {
    final client = _client;
    if (client == null) return;
    final args = <String, dynamic>{};
    final invalid = <String>[];
    for (final o in _available.where(_changed)) {
      try {
        args[o.key] = _current(o);
      } on FormatException catch (e) {
        invalid.add(e.message);
      }
    }
    final messenger = ScaffoldMessenger.of(context);
    if (invalid.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('Valeur invalide : ${invalid.join(', ')}')),
      );
      return;
    }
    if (args.isEmpty) return;
    setState(() => _saving = true);
    try {
      await client.sessionSet(args);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${args.length} réglage(s) enregistré(s) sur le serveur',
          ),
        ),
      );
      await _load();
    } on TransmissionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testPort() async {
    setState(() => _portStatus = 'Test en cours…');
    try {
      final open = await _client!.portTest();
      setState(() => _portStatus = open ? '✓ Port ouvert' : '✗ Port fermé');
    } on TransmissionException catch (e) {
      setState(() => _portStatus = '✗ ${e.message}');
    }
  }

  Future<void> _updateBlocklist() async {
    setState(() => _blocklistStatus = 'Mise à jour…');
    try {
      final size = await _client!.blocklistUpdate();
      setState(() => _blocklistStatus = '✓ ${size ?? 0} règles');
    } on TransmissionException catch (e) {
      setState(() => _blocklistStatus = '✗ ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final c = context.colors;
    final dirty = s == null ? 0 : _available.where(_changed).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Serveur Transmission')),
      bottomNavigationBar: dirty == 0
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$dirty modification(s) non enregistrée(s)',
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _load,
                      child: const Text('Annuler'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.onAccent))
                          : const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
            ),
      body: _error != null
          ? EmptyState(
              Icons.error_outline,
              _error!,
              action: OutlinedButton(
                onPressed: _load,
                child: const Text('Réessayer'),
              ),
            )
          : s == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    _overview(s),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) =>
                          setState(() => _filter = v.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        hintText: 'Rechercher un réglage',
                      ),
                    ),
                    for (final (title, icon, opts) in _sections)
                      ..._section(title, icon, opts),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.speed_rounded),
                        title: const Text('Groupes de bande passante'),
                        subtitle: const Text(
                          'Limites de vitesse partagées entre plusieurs torrents',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BandwidthGroupsPage(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _dangerZone(),
                    const SizedBox(height: 16),
                    Text(
                      'Les réglages du serveur RPC (adresse d’écoute, '
                      'whitelist, identifiants…), les sockets et les journaux '
                      'ne sont modifiables que dans settings.json sur le serveur.',
                      style: TextStyle(color: c.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _diskUsage(int free, int? total) {
    final c = context.colors;
    if (total == null || total == 0) {
      return InfoRow('Espace libre', formatBytes(free));
    }
    final used = 1 - free / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatBytes(free)} libres sur ${formatBytes(total)}',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: used,
              minHeight: 6,
              color: used > 0.9 ? c.danger : (used > 0.75 ? c.warning : c.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerZone() {
    final c = context.colors;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.danger.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        leading: Icon(Icons.power_settings_new_rounded, color: c.danger),
        title: Text('Arrêter le daemon', style: TextStyle(color: c.danger)),
        subtitle: const Text(
          'Transmission s’arrête sur le serveur ; il faudra le relancer '
          'depuis le serveur lui-même',
        ),
        onTap: _shutdown,
      ),
    );
  }

  Future<void> _shutdown() async {
    final c = context.colors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arrêter Transmission ?'),
        content: const Text(
          'Les téléchargements et partages s’arrêteront. L’application ne '
          'pourra plus joindre le serveur tant que le daemon n’aura pas été '
          'relancé sur la machine.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arrêter le daemon'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _client!.sessionClose();
      messenger.showSnackBar(
        const SnackBar(content: Text('Transmission est en cours d’arrêt')),
      );
      if (mounted) Navigator.of(context).pop();
    } on TransmissionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _overview(Map<String, dynamic> s) {
    final c = context.colors;
    final current = (_stats?['current-stats'] as Map?)?.cast<String, dynamic>();
    final total = (_stats?['cumulative-stats'] as Map?)
        ?.cast<String, dynamic>();
    int n(Map<String, dynamic>? m, String k) => (m?[k] as num?)?.toInt() ?? 0;
    String ratio(Map<String, dynamic>? m) {
      final down = n(m, 'downloadedBytes');
      return down == 0 ? '—' : formatRatio(n(m, 'uploadedBytes') / down);
    }

    Widget status(String? text) => text == null
        ? const SizedBox.shrink()
        : Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: text.startsWith('✓')
                  ? c.success
                  : text.startsWith('✗')
                  ? c.danger
                  : c.muted,
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Section(
          title: 'Serveur',
          children: [
            InfoRow('Version', '${s['version'] ?? '?'}'),
            InfoRow(
              'Version RPC',
              '${s['rpc-version-semver'] ?? s['rpc-version'] ?? '?'}',
            ),
            if (s['config-dir'] != null)
              InfoRow('Configuration', '${s['config-dir']}'),
            if (_disk?.free != null) _diskUsage(_disk!.free!, _disk!.total),
            if (_stats?['torrentCount'] != null)
              InfoRow(
                'Torrents',
                '${_stats!['torrentCount']} · '
                    '${_stats!['activeTorrentCount']} actifs · '
                    '${_stats!['pausedTorrentCount']} en pause',
              ),
            if (s['blocklist-size'] != null)
              InfoRow('Règles bloquées', '${s['blocklist-size']} règles'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _testPort,
                  icon: const Icon(Icons.router_outlined, size: 18),
                  label: const Text('Tester le port'),
                ),
                status(_portStatus),
              ],
            ),
            if (s.containsKey('blocklist-url')) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _updateBlocklist,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('Mettre à jour la blocklist'),
                  ),
                  status(_blocklistStatus),
                ],
              ),
            ],
          ],
        ),
        if (current != null || total != null) ...[
          const SizedBox(height: 12),
          Section(
            title: 'Statistiques',
            children: [
              Table(
                columnWidths: const {0: FlexColumnWidth(1.4)},
                children: [
                  for (final (label, a, b) in [
                    ('', 'Session', 'Total'),
                    (
                      'Envoyé',
                      formatBytes(n(current, 'uploadedBytes')),
                      formatBytes(n(total, 'uploadedBytes')),
                    ),
                    (
                      'Reçu',
                      formatBytes(n(current, 'downloadedBytes')),
                      formatBytes(n(total, 'downloadedBytes')),
                    ),
                    ('Ratio', ratio(current), ratio(total)),
                    (
                      'Fichiers ajoutés',
                      '${n(current, 'filesAdded')}',
                      '${n(total, 'filesAdded')}',
                    ),
                    (
                      'Durée active',
                      formatDuration(n(current, 'secondsActive')),
                      formatDuration(n(total, 'secondsActive')),
                    ),
                    ('Démarrages', '—', '${n(total, 'sessionCount')}'),
                  ])
                    TableRow(
                      children: [
                        for (final (i, text) in [label, a, b].indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              text,
                              style: TextStyle(
                                fontSize: 13,
                                color: i == 0 || label.isEmpty
                                    ? c.muted
                                    : c.text,
                                fontWeight: label.isEmpty
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _section(String title, IconData icon, List<_Opt> opts) {
    final visible = opts
        .where((o) => _session!.containsKey(o.key))
        .where(
          (o) =>
              _filter.isEmpty ||
              o.label.toLowerCase().contains(_filter) ||
              title.toLowerCase().contains(_filter) ||
              (o.help?.toLowerCase().contains(_filter) ?? false),
        )
        .toList();
    if (visible.isEmpty) return const [];
    final c = context.colors;
    return [
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: c.accent),
                  const SizedBox(width: 8),
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 6),
              for (final o in visible) _option(o),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _option(_Opt o) {
    final c = context.colors;
    final enabled = o.dependsOn == null || _values[o.dependsOn] != false;
    final changed = _changed(o);
    Widget field(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Opacity(opacity: enabled ? 1 : 0.5, child: child),
    );
    final label = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: o.label),
          if (changed)
            TextSpan(
              text: '  •',
              style: TextStyle(color: c.warning),
            ),
        ],
      ),
    );
    final help = o.help == null
        ? null
        : Text(o.help!, style: TextStyle(color: c.muted, fontSize: 12));

    switch (o) {
      case _Bool():
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: label,
          subtitle: help,
          value: _values[o.key] == true,
          onChanged: enabled ? (v) => setState(() => _values[o.key] = v) : null,
        );
      case _Int() || _Decimal() || _Text():
        final multiline = o is _Text && o.multiline;
        return field(
          TextField(
            controller: _controllers[o.key],
            enabled: enabled,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 8 : 1,
            keyboardType: switch (o) {
              _Int() => TextInputType.number,
              _Decimal() => const TextInputType.numberWithOptions(
                decimal: true,
              ),
              _ => multiline ? TextInputType.multiline : TextInputType.text,
            },
            decoration: InputDecoration(
              label: label,
              helperText: o.help,
              suffixText: o is _Int ? o.suffix : null,
            ),
          ),
        );
      case _Encryption():
        final current = _values[o.key] as String?;
        // 4.0 dit « tolerated », 4.1 dit « allowed » pour la même option.
        final tolerant = current == 'allowed' ? 'allowed' : 'tolerated';
        return field(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(
                    value: 'required',
                    label: Text('Obligatoire'),
                  ),
                  const ButtonSegment(
                    value: 'preferred',
                    label: Text('Préféré'),
                  ),
                  ButtonSegment(value: tolerant, label: const Text('Toléré')),
                ],
                selected: {?current},
                onSelectionChanged: (v) =>
                    setState(() => _values[o.key] = v.first),
              ),
            ],
          ),
        );
      case _Transports():
        const choices = {
          'utp,tcp': 'µTP puis TCP',
          'tcp,utp': 'TCP puis µTP',
          'tcp': 'TCP uniquement',
          'utp': 'µTP uniquement',
        };
        final current = (_values[o.key] as List?)?.join(',');
        return field(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label,
              ?help,
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final MapEntry(:key, :value) in choices.entries)
                    ButtonSegment(value: key, label: Text(value)),
                ],
                selected: {if (choices.containsKey(current)) current!},
                emptySelectionAllowed: true,
                onSelectionChanged: (v) {
                  if (v.isEmpty) return;
                  setState(() => _values[o.key] = v.first.split(','));
                },
              ),
            ],
          ),
        );
      case _Time():
        final minutes = (_values[o.key] as num?)?.toInt() ?? 0;
        final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          enabled: enabled,
          title: label,
          trailing: OutlinedButton(
            onPressed: !enabled
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(alwaysUse24HourFormat: true),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setState(
                        () => _values[o.key] = picked.hour * 60 + picked.minute,
                      );
                    }
                  },
            child: Text(
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            ),
          ),
        );
      case _Days():
        // Masque de bits Transmission : dimanche = 1, lundi = 2 … samedi = 64.
        const days = [
          ('L', 2),
          ('M', 4),
          ('M', 8),
          ('J', 16),
          ('V', 32),
          ('S', 64),
          ('D', 1),
        ];
        final mask = (_values[o.key] as num?)?.toInt() ?? 127;
        return field(
          Row(
            children: [
              Expanded(child: label),
              for (final (letter, bit) in days)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text(letter),
                    selected: mask & bit != 0,
                    onSelected: !enabled
                        ? null
                        : (_) => setState(() => _values[o.key] = mask ^ bit),
                  ),
                ),
            ],
          ),
        );
    }
  }
}
