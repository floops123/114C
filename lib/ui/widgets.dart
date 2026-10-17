import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Petite étiquette plate (résolution, langue, freeleech…).
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color, this.solid = false});
  final String label;
  final Color? color;

  /// Fond opaque : lisible par-dessus une affiche.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: solid
            ? Colors.black.withValues(alpha: 0.65)
            : (color ?? c.muted).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.3,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: solid ? (color ?? Colors.white) : fg,
        ),
      ),
    );
  }
}

/// Affiche TMDB. Sans dimensions, elle remplit l'espace disponible.
class Poster extends StatelessWidget {
  const Poster(this.url, {super.key, this.width, this.height, this.radius = 8});
  final String? url;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: LayoutBuilder(builder: (context, constraints) {
          final placeholder = ColoredBox(
            color: c.surfaceAlt,
            child: Center(child: Icon(Icons.movie_outlined, color: c.muted)),
          );
          if (url == null) return placeholder;
          final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 160;
          return CachedNetworkImage(
            imageUrl: url!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            // Décodage à la taille affichée : beaucoup moins de mémoire.
            memCacheWidth: (w * MediaQuery.devicePixelRatioOf(context)).round(),
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
        }),
      ),
    );
  }
}

/// En-tête de page : grand titre, sous-titre et actions.
class PageHeader extends StatelessWidget {
  const PageHeader(
      {super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final Widget? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
            ],
          ),
        ),
        ...actions,
      ]),
    );
  }
}

/// Bloc de contenu à bord fin, avec titre optionnel.
class Section extends StatelessWidget {
  const Section({super.key, this.title, required this.children, this.padding});
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(title!.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(letterSpacing: 0.8)),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Ligne « libellé : valeur » pour les écrans de détail.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: Text(label, style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        Expanded(
          child: SelectableText(value,
              style: TextStyle(fontSize: 13, color: valueColor ?? c.text)),
        ),
      ]),
    );
  }
}

/// Pastille de statistique (vitesse, compteur…).
class StatPill extends StatelessWidget {
  const StatPill({super.key, required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.text,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.message, {super.key, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration:
                BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
            child: Icon(icon, size: 28, color: c.muted),
          ),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.danger.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 18, color: c.danger),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message, style: TextStyle(color: c.danger, fontSize: 13))),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ]),
    );
  }
}

/// Rangée horizontale de pastilles sélectionnables.
class ChipRow<T> extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> items;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Center(
          child: ChoiceChip(
            label: Text(label(items[i])),
            selected: items[i] == selected,
            onSelected: (_) => onSelected(items[i]),
          ),
        ),
      ),
    );
  }
}
