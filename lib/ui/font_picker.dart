import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/preferences.dart';
import 'app_fonts.dart';
import 'theme.dart';

/// Choix de la police de l'interface : une carte par police, écrite dans
/// cette police, à la taille qu'elle aura.
class FontPicker extends ConsumerWidget {
  const FontPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = AppFont.byName(ref.watch(uiPrefsProvider.select((p) => p.font)));
    return LayoutBuilder(builder: (context, box) {
      // Deux colonnes dès que la place le permet.
      final width = box.maxWidth >= 440 ? (box.maxWidth - 8) / 2 : box.maxWidth;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in AppFont.values)
          SizedBox(
            width: width,
            child: _FontCard(
              font: f,
              // L'aperçu est déjà agrandi ou réduit selon la police en cours.
              relativeScale: f.scale / current.scale,
              selected: f == current,
              onTap: () => ref.read(uiPrefsProvider.notifier).setFont(f.name),
            ),
          ),
      ]);
    });
  }
}

class _FontCard extends StatelessWidget {
  const _FontCard({
    required this.font,
    required this.relativeScale,
    required this.selected,
    required this.onTap,
  });

  final AppFont font;
  final double relativeScale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    TextStyle style(double size, {FontWeight? weight, Color? color}) => TextStyle(
          fontFamily: font.family,
          fontSize: size * relativeScale,
          fontWeight: weight,
          color: color,
          height: 1.25,
        );
    return Semantics(
      selected: selected,
      button: true,
      label: 'Police ${font.label}',
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.08) : c.surfaceAlt,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: selected ? c.accent : Colors.transparent, width: 1.4),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(font.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style(15, weight: FontWeight.w700, color: c.text)),
                  const SizedBox(height: 2),
                  Text('1080p · 4,2 Go · Été 2026',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style(12.5, color: c.muted)),
                  const SizedBox(height: 2),
                  Text(font.style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.muted)),
                ]),
              ),
              if (selected) Icon(Icons.check_circle_rounded, size: 20, color: c.accent),
            ]),
          ),
        ),
      ),
    );
  }
}
