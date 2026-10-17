import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/transmission.dart';
import 'theme.dart';
import 'widgets.dart';

/// Groupes de bande passante (`group-get` / `group-set`, Transmission ≥ 4) :
/// des limites de vitesse partagées par tous les torrents d'un groupe.
/// On affecte un torrent à un groupe depuis l'onglet Options de son détail.
class BandwidthGroupsPage extends ConsumerStatefulWidget {
  const BandwidthGroupsPage({super.key});

  @override
  ConsumerState<BandwidthGroupsPage> createState() =>
      _BandwidthGroupsPageState();
}

class _BandwidthGroupsPageState extends ConsumerState<BandwidthGroupsPage> {
  List<Map<String, dynamic>>? _groups;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.read(transmissionProvider);
    if (client == null) return;
    try {
      final groups = await client.groupGet();
      if (mounted) {
        setState(() {
          _groups = groups;
          _error = null;
        });
      }
    } on TransmissionException catch (e) {
      if (mounted) {
        setState(() => _error =
            '${e.message}\n\nLes groupes nécessitent Transmission 4 ou plus.');
      }
    }
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau groupe'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nom du groupe'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Créer')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _save({
      'name': name.trim(),
      'honorsSessionLimits': true,
      'speed-limit-down-enabled': false,
      'speed-limit-down': 0,
      'speed-limit-up-enabled': false,
      'speed-limit-up': 0,
    });
  }

  Future<void> _save(Map<String, dynamic> group) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(transmissionProvider)!.groupSet(group);
      messenger.showSnackBar(
          SnackBar(content: Text('Groupe « ${group['name']} » enregistré')));
      await _load();
    } on TransmissionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groupes de bande passante'),
        actions: [
          IconButton(
            tooltip: 'Nouveau groupe',
            icon: const Icon(Icons.add_rounded),
            onPressed: groups == null ? null : _create,
          ),
        ],
      ),
      body: _error != null
          ? EmptyState(Icons.speed_rounded, _error!)
          : groups == null
              ? const Center(child: CircularProgressIndicator())
              : groups.isEmpty
                  ? EmptyState(
                      Icons.speed_rounded,
                      'Aucun groupe.\nUn groupe partage ses limites de vitesse '
                      'entre tous ses torrents.',
                      action: FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Créer un groupe'),
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final g in groups) ...[
                              _GroupCard(
                                  key: ValueKey(g['name']),
                                  group: g,
                                  onSave: _save),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              'Pour placer un torrent dans un groupe : détail du '
                              'torrent → onglet Options.',
                              style: TextStyle(
                                  color: context.colors.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}

class _GroupCard extends StatefulWidget {
  const _GroupCard({super.key, required this.group, required this.onSave});
  final Map<String, dynamic> group;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late final Map<String, dynamic> _values = {...widget.group};
  late final _down =
      TextEditingController(text: '${widget.group['speed-limit-down'] ?? 0}');
  late final _up =
      TextEditingController(text: '${widget.group['speed-limit-up'] ?? 0}');

  @override
  void dispose() {
    _down.dispose();
    _up.dispose();
    super.dispose();
  }

  Widget _limit(String key, String label, TextEditingController controller) {
    final enabled = _values['$key-enabled'] == true;
    return Row(children: [
      Expanded(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(label),
          value: enabled,
          onChanged: (v) => setState(() => _values['$key-enabled'] = v),
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 130,
        child: TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'ko/s'),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Section(title: '${widget.group['name']}', children: [
      _limit('speed-limit-down', 'Limiter la réception', _down),
      _limit('speed-limit-up', 'Limiter l’envoi', _up),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Respecter aussi les limites globales'),
        value: _values['honorsSessionLimits'] == true,
        onChanged: (v) => setState(() => _values['honorsSessionLimits'] = v),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => widget.onSave({
            ..._values,
            'speed-limit-down':
                int.tryParse(_down.text.trim()) ?? _values['speed-limit-down'],
            'speed-limit-up':
                int.tryParse(_up.text.trim()) ?? _values['speed-limit-up'],
          }),
          child: const Text('Enregistrer'),
        ),
      ),
    ]);
  }
}
