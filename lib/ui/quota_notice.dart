import 'dart:async';

import 'package:flutter/material.dart';

import '../api/quota.dart';
import '../api/tracker.dart';
import 'theme.dart';

/// Bandeau affiché tant qu'un des [trackers] fait patienter ses requêtes
/// (quota par minute atteint, ou tracker qui a demandé d'attendre), avec le
/// temps restant. Rien sinon.
class QuotaNotice extends StatefulWidget {
  const QuotaNotice({super.key, required this.trackers, this.padding});
  final Iterable<Tracker> trackers;
  final EdgeInsetsGeometry? padding;

  @override
  State<QuotaNotice> createState() => _QuotaNoticeState();
}

class _QuotaNoticeState extends State<QuotaNotice> {
  Timer? _tick;

  List<(Tracker, RequestQuota)> get _quotas => [
        for (final t in widget.trackers)
          for (final q in quotasOf(t)) (t, q),
      ];

  @override
  void initState() {
    super.initState();
    for (final (_, q) in _quotas) {
      q.waitingUntil.addListener(_changed);
    }
    _changed();
  }

  @override
  void didUpdateWidget(QuotaNotice old) {
    super.didUpdateWidget(old);
    for (final t in old.trackers) {
      for (final q in quotasOf(t)) {
        q.waitingUntil.removeListener(_changed);
      }
    }
    for (final (_, q) in _quotas) {
      q.waitingUntil.addListener(_changed);
    }
    _changed();
  }

  @override
  void dispose() {
    for (final (_, q) in _quotas) {
      q.waitingUntil.removeListener(_changed);
    }
    _tick?.cancel();
    super.dispose();
  }

  /// Compte à rebours rafraîchi chaque seconde, seulement pendant l'attente.
  void _changed() {
    final waiting = _quotas.any((e) => e.$2.waitingUntil.value != null);
    if (waiting && _tick == null) {
      _tick = Timer.periodic(
          const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    } else if (!waiting) {
      _tick?.cancel();
      _tick = null;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Le plus long délai par tracker (C411 a deux budgets).
    final longest = <Tracker, int>{};
    for (final (t, q) in _quotas) {
      if (q.waitingUntil.value case final until?) {
        final s = until.difference(now).inSeconds.clamp(1, 3600);
        if (s > (longest[t] ?? 0)) longest[t] = s;
      }
    }
    final waiting = [
      for (final MapEntry(:key, :value) in longest.entries) (key, value),
    ];
    if (waiting.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final text = [
      for (final (t, s) in waiting) '${t.label} : reprise dans $s s',
    ].join(' · ');
    return Padding(
      padding: widget.padding ?? EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded, size: 16, color: c.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Limite de requêtes par minute atteinte. $text',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ),
        ]),
      ),
    );
  }
}
