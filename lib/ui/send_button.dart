import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tracker.dart';
import '../state/releases.dart';
import '../state/torrents.dart';
import '../api/transmission.dart';
import 'theme.dart';
import 'torrent_actions.dart';

/// Bouton « envoyer à Transmission », avec état d'envoi et coche si le torrent
/// est déjà présent dans le client.
class SendButton extends ConsumerStatefulWidget {
  const SendButton({super.key, required this.release, this.large = false});
  final Release release;

  /// Grand bouton avec libellé (fiche détail) ou pastille ronde (listes).
  final bool large;

  @override
  ConsumerState<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends ConsumerState<SendButton> {
  bool _sending = false;

  Future<void> _send([AddOptions options = const AddOptions()]) async {
    setState(() => _sending = true);
    await sendToTransmission(context, ref, widget.release, options: options);
    if (mounted) setState(() => _sending = false);
  }

  /// Ajout avec choix du dossier, des étiquettes, de la priorité…
  Future<void> _sendWithOptions() async {
    final options = await askAddOptions(context, ref,
        title: 'Télécharger ${widget.release.title ?? widget.release.name}');
    if (options != null && mounted) await _send(options);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final inClient = ref.watch(torrentsProvider
        .select((s) => s.hashes.contains(widget.release.infoHash)));
    // Sans infoHash (certains flux Torznab), on ne peut pas savoir s'il est présent.
    final onPressed = inClient || _sending ? null : () => _send();
    final icon = _sending
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Icon(inClient ? Icons.check_rounded : Icons.download_rounded,
            size: 18, color: Colors.white);

    if (widget.large) {
      final main = FilledButton.icon(
        onPressed: onPressed,
        style: inClient
            ? FilledButton.styleFrom(
                disabledBackgroundColor: c.success.withValues(alpha: 0.15),
                disabledForegroundColor: c.success)
            : null,
        icon: inClient
            ? Icon(Icons.check_rounded, size: 18, color: c.success)
            : icon,
        label: Text(inClient
            ? 'Dans Transmission'
            : _sending
                ? 'Envoi…'
                : 'Télécharger'),
      );
      if (inClient) return main;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        main,
        OutlinedButton.icon(
          onPressed: _sending ? null : _sendWithOptions,
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Options…'),
        ),
      ]);
    }

    return Tooltip(
      message: inClient
          ? 'Déjà dans Transmission'
          : 'Télécharger (appui long : options)',
      child: Material(
        color: inClient ? c.success : c.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          onLongPress: inClient || _sending ? null : _sendWithOptions,
          child: SizedBox.square(dimension: 34, child: Center(child: icon)),
        ),
      ),
    );
  }
}
