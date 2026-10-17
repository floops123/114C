import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../state/speed_history.dart';
import 'theme.dart';

// Graphiques dessinés à la main (CustomPainter) : aucune dépendance, rendu
// léger. Conventions : traits de 2 px, quadrillage en filet discret, textes en
// couleurs de texte (jamais en couleur de série), une seule échelle par axe.

const _tabular = [FontFeature.tabularFigures()];

/// Échelle « propre » : 0, pas, 2 pas… avec un pas en 1 / 2 / 2,5 / 5 × 10^n,
/// calculé dans l'unité d'affichage (Ko, Mo… en base 1024, comme
/// [formatBytes]) pour que les graduations tombent sur des nombres ronds.
({double max, double step}) _niceScale(double maxValue, {int ticks = 4}) {
  if (maxValue <= 0) return (max: 1024, step: 256);
  var unit = 1.0;
  while (maxValue / unit >= 1024) {
    unit *= 1024;
  }
  final nice = _niceDecimal(maxValue / unit, ticks);
  return (max: nice.max * unit, step: nice.step * unit);
}

({double max, double step}) _niceDecimal(double maxValue, int ticks) {
  final raw = maxValue / ticks;
  final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final step = [1.0, 2.0, 2.5, 5.0, 10.0]
          .map((m) => m * magnitude)
          .firstWhere((s) => s >= raw, orElse: () => 10 * magnitude);
  return (max: (maxValue / step).ceil() * step, step: step);
}

/// Clé de légende : un court trait de la couleur de la série.
class LineKey extends StatelessWidget {
  const LineKey(this.color, {super.key});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 14,
        height: 3,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2)),
      );
}

/// Vitesses de réception et d'envoi dans le temps, sur [window].
class SpeedChart extends StatefulWidget {
  const SpeedChart({
    super.key,
    required this.samples,
    required this.window,
    this.height = 180,
  });

  final Iterable<SpeedSample> samples;
  final Duration window;
  final double height;

  @override
  State<SpeedChart> createState() => _SpeedChartState();
}

class _SpeedChartState extends State<SpeedChart> {
  /// Position du pointeur dans la zone de tracé (null = pas de survol).
  double? _pointerX;

  static const _left = 64.0, _bottom = 20.0, _top = 8.0, _right = 8.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = DateTime.now();
    final start = now.subtract(widget.window);
    final samples =
        widget.samples.where((s) => !s.time.isBefore(start)).toList();
    final last = samples.isEmpty ? null : samples.last;

    Widget legend(Color color, String label, int? value) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          LineKey(color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
          if (value != null) ...[
            const SizedBox(width: 6),
            Text(formatSpeed(value),
                style: TextStyle(
                    color: c.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: _tabular)),
          ],
        ]);

    final peakDown = samples.fold(0, (m, s) => math.max(m, s.down));
    final peakUp = samples.fold(0, (m, s) => math.max(m, s.up));
    int avg(int Function(SpeedSample) f) => samples.isEmpty
        ? 0
        : samples.fold(0, (sum, s) => sum + f(s)) ~/ samples.length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 6, children: [
        legend(c.download, 'Réception', last?.down),
        legend(c.upload, 'Envoi', last?.up),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, constraints) {
          final plotWidth = constraints.maxWidth - _left - _right;
          final scale = _niceScale(math.max(peakDown, peakUp).toDouble());
          double xOf(DateTime t) =>
              _left +
              plotWidth *
                  (t.difference(start).inMilliseconds /
                      widget.window.inMilliseconds);

          // Échantillon le plus proche du pointeur.
          SpeedSample? hovered;
          if (_pointerX != null && samples.isNotEmpty) {
            hovered = samples.reduce((a, b) =>
                (xOf(a.time) - _pointerX!).abs() <=
                        (xOf(b.time) - _pointerX!).abs()
                    ? a
                    : b);
          }

          void track(Offset p) => setState(() => _pointerX =
              p.dx.clamp(_left, constraints.maxWidth - _right));
          void clear() => setState(() => _pointerX = null);

          return MouseRegion(
            onHover: (e) => track(e.localPosition),
            onExit: (_) => clear(),
            child: GestureDetector(
              onTapDown: (d) => track(d.localPosition),
              onHorizontalDragUpdate: (d) => track(d.localPosition),
              onHorizontalDragEnd: (_) => clear(),
              onTapUp: (_) {},
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SpeedPainter(
                      samples: samples,
                      start: start,
                      window: widget.window,
                      scale: scale,
                      hovered: hovered,
                      colors: c,
                      insets: const EdgeInsets.fromLTRB(
                          _left, _top, _right, _bottom),
                    ),
                  ),
                ),
                if (samples.isEmpty)
                  Center(
                    child: Text('Pas encore de mesure',
                        style: TextStyle(color: c.muted, fontSize: 12)),
                  ),
                if (hovered != null)
                  _tooltip(context, hovered, xOf(hovered.time),
                      constraints.maxWidth),
              ]),
            ),
          );
        }),
      ),
      const SizedBox(height: 8),
      // Résumé chiffré : les valeurs restent lisibles sans survol.
      Text(
        'Moyenne ↓ ${formatSpeed(avg((s) => s.down))} · ↑ ${formatSpeed(avg((s) => s.up))}'
        '   ·   Pic ↓ ${formatSpeed(peakDown)} · ↑ ${formatSpeed(peakUp)}',
        style: TextStyle(color: c.muted, fontSize: 12, fontFeatures: _tabular),
      ),
    ]);
  }

  Widget _tooltip(
      BuildContext context, SpeedSample s, double x, double width) {
    final c = context.colors;
    // Largeur libre (suit le contenu) : ancrée à droite du réticule, ou à sa
    // gauche dans la moitié droite du graphique.
    final onRight = x < width / 2;
    final ago = DateTime.now().difference(s.time).inSeconds;

    Widget row(Color color, String label, int value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            LineKey(color),
            const SizedBox(width: 8),
            Text(formatSpeed(value),
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    fontFeatures: _tabular)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
          ]),
        );

    return Positioned(
      left: onRight ? x + 12 : null,
      right: onRight ? null : width - x + 12,
      top: 0,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ago < 5 ? 'maintenant' : 'il y a ${formatDuration(ago)}',
                style: TextStyle(color: c.muted, fontSize: 11)),
            row(c.download, 'réception', s.down),
            row(c.upload, 'envoi', s.up),
          ]),
        ),
      ),
    );
  }
}

class _SpeedPainter extends CustomPainter {
  _SpeedPainter({
    required this.samples,
    required this.start,
    required this.window,
    required this.scale,
    required this.hovered,
    required this.colors,
    required this.insets,
  });

  final List<SpeedSample> samples;
  final DateTime start;
  final Duration window;
  final ({double max, double step}) scale;
  final SpeedSample? hovered;
  final AppColors colors;
  final EdgeInsets insets;

  /// Au-delà, deux mesures ne sont pas reliées (application fermée, réseau…).
  static const _gap = Duration(seconds: 10);

  @override
  void paint(Canvas canvas, Size size) {
    final plot = insets.deflateRect(Offset.zero & size);
    double x(DateTime t) =>
        plot.left +
        plot.width * (t.difference(start).inMilliseconds / window.inMilliseconds);
    double y(num v) => plot.bottom - plot.height * (v / scale.max);

    // Quadrillage horizontal + graduations de l'axe Y.
    final grid = Paint()
      ..color = colors.border
      ..strokeWidth = 1;
    for (var v = 0.0; v <= scale.max + 0.5; v += scale.step) {
      final gy = y(v).roundToDouble() + 0.5;
      canvas.drawLine(Offset(plot.left, gy), Offset(plot.right, gy), grid);
      _text(canvas, formatSpeed(v), Offset(plot.left - 8, gy),
          align: Alignment.centerRight);
    }

    // Axe X : début de la fenêtre, milieu, maintenant.
    final minutes = window.inMinutes;
    for (final (frac, label) in [
      (0.0, '-$minutes min'),
      (0.5, '-${minutes ~/ 2} min'),
      (1.0, 'maintenant'),
    ]) {
      _text(canvas, label,
          Offset(plot.left + plot.width * frac, plot.bottom + 4),
          align: frac == 0
              ? Alignment.topLeft
              : frac == 1
                  ? Alignment.topRight
                  : Alignment.topCenter);
    }

    if (samples.isEmpty) return;

    canvas.save();
    canvas.clipRect(plot.inflate(6));
    for (final (color, value) in [
      (colors.download, (SpeedSample s) => s.down),
      (colors.upload, (SpeedSample s) => s.up),
    ]) {
      final path = Path();
      SpeedSample? previous;
      for (final s in samples) {
        final p = Offset(x(s.time), y(value(s)));
        if (previous == null || s.time.difference(previous.time) > _gap) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
        previous = s;
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);

      // Point final (ou point survolé), cerclé de la couleur du fond.
      final marker = hovered ?? samples.last;
      final m = Offset(x(marker.time), y(value(marker)));
      canvas.drawCircle(m, 6, Paint()..color = colors.surface);
      canvas.drawCircle(m, 4, Paint()..color = color);
    }
    canvas.restore();

    if (hovered != null) {
      final hx = x(hovered!.time).roundToDouble() + 0.5;
      canvas.drawLine(Offset(hx, plot.top), Offset(hx, plot.bottom),
          Paint()
            ..color = colors.muted.withValues(alpha: 0.6)
            ..strokeWidth = 1);
    }
  }

  void _text(Canvas canvas, String text, Offset anchor,
      {required Alignment align}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: colors.muted, fontSize: 10.5, fontFeatures: _tabular)),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = anchor.dx - tp.width * (align.x + 1) / 2;
    final dy = anchor.dy - tp.height * (align.y + 1) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_SpeedPainter old) =>
      old.samples.length != samples.length ||
      (samples.isNotEmpty && old.samples.last != samples.last) ||
      old.hovered != hovered ||
      old.window != window ||
      old.colors != colors;
}

class BarItem {
  const BarItem(this.label, this.value, this.display, {this.onTap});
  final String label;
  final double value;
  final String display;
  final VoidCallback? onTap;
}

/// Barres horizontales d'une seule série, valeur au bout de la barre.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.items, required this.color});
  final List<BarItem> items;
  final Color color;

  static const _valueWidth = 84.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = items.fold(0.0, (m, i) => math.max(m, i.value));
    return Column(children: [
      for (final item in items)
        Tooltip(
          message: '${item.label}\n${item.display}',
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: item.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.text)),
                  const SizedBox(height: 4),
                  LayoutBuilder(builder: (context, constraints) {
                    final available = constraints.maxWidth - _valueWidth;
                    final width = max == 0
                        ? 0.0
                        : math.max(2.0, available * item.value / max);
                    return Row(children: [
                      Container(
                        width: width,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          // Extrémité arrondie, base carrée.
                          borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(item.display,
                          style: TextStyle(
                              fontSize: 12,
                              color: c.muted,
                              fontFeatures: _tabular)),
                    ]);
                  }),
                ],
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Jauge de progression : la piste est une teinte claire de la même couleur.
class Meter extends StatelessWidget {
  const Meter({super.key, required this.value, required this.color});
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: 4,
          color: color,
          backgroundColor: color.withValues(alpha: 0.18),
        ),
      );
}
