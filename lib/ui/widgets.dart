import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
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
        // Opaque (sur une affiche) : fond de la couleur, texte blanc ; sans
        // couleur, voile sombre.
        color: solid
            ? (color ?? Colors.black).withValues(alpha: color == null ? 0.65 : 0.9)
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
          color: solid ? Colors.white : fg,
        ),
      ),
    );
  }
}

/// Affiche TMDB. Sans dimensions, elle remplit l'espace disponible.
/// Tailles proposées par TMDB pour les affiches.
const _tmdbWidths = [92, 154, 185, 342, 500, 780];
final _tmdbSize = RegExp(r'(image\.tmdb\.org/t/p/)(w\d+|original)/');

/// Remplace la taille d'une image TMDB par la plus petite couvrant [pixels] :
/// une vignette w185 pèse 4 à 5 fois moins qu'une w500 à télécharger et
/// à décoder.
String tmdbSized(String url, double pixels) {
  if (!_tmdbSize.hasMatch(url)) return url;
  final w = _tmdbWidths.firstWhere((w) => w >= pixels, orElse: () => 780);
  return url.replaceFirstMapped(_tmdbSize, (m) => '${m[1]}w$w/');
}

/// Affiche TMDB. Sans dimensions, elle remplit l'espace disponible.
/// Les coins arrondis sont dessinés avec l'image (pas de découpe séparée).
class Poster extends StatelessWidget {
  const Poster(this.url,
      {super.key,
      this.width,
      this.height,
      this.radius = 8,
      this.fallback,
      this.alignment = Alignment.center});
  final String? url;

  /// Partie gardée quand l'image est recadrée (haut pour une image de fond :
  /// les visages y sont).
  final Alignment alignment;
  final double? width;
  final double? height;
  final double radius;

  /// Affiché sans image, ou si elle ne se charge pas (ex. visuel du type de
  /// contenu, voir ContentArt).
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = BorderRadius.circular(radius);
    final placeholder = fallback ??
        DecoratedBox(
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: shape),
          child: Center(child: Icon(Icons.movie_outlined, color: c.muted)),
        );
    return SizedBox(
      width: width,
      height: height,
      child: url == null
          ? placeholder
          : LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : 160.0;
                final pixels = w * MediaQuery.devicePixelRatioOf(context);
                return CachedNetworkImage(
                  imageUrl: tmdbSized(url!, pixels),
                  // Décodage à la taille affichée : beaucoup moins de mémoire.
                  memCacheWidth: pixels.round(),
                  fadeInDuration: const Duration(milliseconds: 120),
                  imageBuilder: (_, image) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: shape,
                      image: DecorationImage(
                          image: image, fit: BoxFit.cover, alignment: alignment),
                    ),
                  ),
                  placeholder: (_, _) => placeholder,
                  errorWidget: (_, _, _) => placeholder,
                );
              },
            ),
    );
  }
}

/// En-tête de page : grand titre, sous-titre et actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });
  final String title;
  final Widget? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // Le sous-titre occupe toute la largeur sous la ligne titre + actions :
    // sur téléphone, il ne se tasse pas à côté des boutons.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              HeaderActions(children: actions),
            ],
          ),
          if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
        ],
      ),
    );
  }
}

/// Taille des icônes d'en-tête de page et de barre du haut (plus grandes que
/// celles des listes).
const headerIconSize = 26.0;

/// Actions d'en-tête de page : icônes et zone de clic agrandies (boutons
/// et menus).
class HeaderActions extends StatelessWidget {
  const HeaderActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = IconButtonTheme.of(context);
    return IconTheme.merge(
      data: const IconThemeData(size: headerIconSize),
      child: IconButtonTheme(
        data: IconButtonThemeData(
          style: (theme.style ?? const ButtonStyle()).copyWith(
            iconSize: const WidgetStatePropertyAll(headerIconSize),
            minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
            padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Grand bouton décoré : dégradé, pastille ou icône, titre et sous-titre.
/// Choisi : couleurs franches, liseré clair et coche ; sinon atténué (sans
/// perdre son décor). Pas d'animation ni de transparence.
class FeatureButton extends StatelessWidget {
  const FeatureButton({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.selected,
    required this.onTap,
  });
  final Widget leading;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = BorderRadius.circular(14);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: selected
              ? colors
              : [for (final x in colors) Color.lerp(x, c.surfaceAlt, 0.45)!],
        ),
        border: Border.all(
            color: selected ? c.text.withValues(alpha: 0.85) : Colors.transparent,
            width: 2),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconTheme.merge(
                data: IconThemeData(size: 28, color: c.onAccent),
                child: leading,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.onAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.onAccent.withValues(alpha: 0.8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_circle_rounded, size: 18, color: c.onAccent),
              ],
            ]),
          ),
        ),
      ),
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
    return Panel(
      radius: 14,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(letterSpacing: 0.8),
              ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(fontSize: 13, color: valueColor ?? c.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille de statistique (vitesse, compteur…).
class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: c.muted),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
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
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: c.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.danger, fontSize: 13),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

/// Défilement de l'application : en plus du doigt, du stylet et du pavé
/// tactile, on fait défiler les listes en cliquant et en faisant glisser la
/// souris (version PC).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices =>
      {...super.dragDevices, PointerDeviceKind.mouse};
}

/// Zone où glisser à la souris sélectionne du texte au lieu de faire défiler
/// (la molette fait toujours défiler).
class MouseSelectsText extends StatelessWidget {
  const MouseSelectsText({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return ScrollConfiguration(
      behavior: behavior.copyWith(dragDevices: {
        for (final d in behavior.dragDevices)
          if (d != PointerDeviceKind.mouse) d,
      }),
      child: child,
    );
  }
}

/// Liste horizontale utilisable à la molette (version PC) : la molette
/// verticale la fait défiler de côté, puis rend la main à la page une fois au
/// bout.
class HorizontalScroller extends StatefulWidget {
  const HorizontalScroller({super.key, required this.builder});

  /// Construit la liste horizontale avec le contrôleur à lui donner.
  final Widget Function(ScrollController controller) builder;

  @override
  State<HorizontalScroller> createState() => _HorizontalScrollerState();
}

class _HorizontalScrollerState extends State<HorizontalScroller> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta;
    // Pavé tactile ou molette horizontale : la liste s'en charge déjà.
    if (delta.dy == 0 || delta.dx != 0) return;
    final p = _controller.position;
    final atEnd = delta.dy > 0 ? p.pixels >= p.maxScrollExtent : p.pixels <= p.minScrollExtent;
    if (atEnd) return; // La page défile.
    GestureBinding.instance.pointerSignalResolver.register(
        event, (_) => p.pointerScroll(delta.dy));
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: _onSignal,
        child: widget.builder(_controller),
      );
}

/// Rangée horizontale de pastilles sélectionnables.
class ChipRow<T> extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.icon,
  });
  final List<T> items;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  /// Picto devant le libellé (catégories…), ou null.
  final IconData? Function(T)? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 38,
      child: HorizontalScroller(
        builder: (controller) => ListView.separated(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final on = items[i] == selected;
            final glyph = icon?.call(items[i]);
            return Center(
              child: ChoiceChip(
                avatar: glyph == null
                    ? null
                    : Icon(glyph, size: 16, color: on ? c.onAccent : c.muted),
                label: Text(label(items[i])),
                selected: on,
                onSelected: (_) => onSelected(items[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _SortDirection { ascending, descending }

/// Bouton de tri : affiche le critère et le sens courants. Choisir à nouveau
/// le critère actif inverse le sens ; un nouveau critère prend son sens
/// naturel ([ascendingByDefault]).
class SortMenu<T extends Object> extends StatelessWidget {
  const SortMenu({
    super.key,
    required this.options,
    required this.selected,
    required this.ascending,
    required this.label,
    required this.ascendingByDefault,
    required this.onChanged,
    this.note,
    this.icon,
  });

  final List<T> options;
  final T selected;
  final bool ascending;
  final String Function(T) label;
  final bool Function(T) ascendingByDefault;
  final void Function(T sort, bool ascending) onChanged;

  /// Précision affichée en tête du menu (ex. tri local).
  final String? note;

  /// Icône de chaque critère (menu et bouton), ou null.
  final IconData Function(T)? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget entry(IconData? glyph, String text) => Row(children: [
          if (glyph != null) ...[
            Icon(glyph, size: 18, color: c.muted),
            const SizedBox(width: 12),
          ],
          Flexible(child: Text(text)),
        ]);
    final current = icon?.call(selected) ?? Icons.sort_rounded;
    return PopupMenuButton<Object>(
      tooltip: 'Trier',
      onSelected: (v) {
        if (v is _SortDirection) {
          onChanged(selected, v == _SortDirection.ascending);
        } else if (v == selected) {
          onChanged(selected, !ascending);
        } else {
          onChanged(v as T, ascendingByDefault(v));
        }
      },
      itemBuilder: (_) => [
        if (note != null)
          PopupMenuItem(
            enabled: false,
            child: Text(note!, style: TextStyle(color: c.muted, fontSize: 12)),
          ),
        for (final o in options)
          CheckedPopupMenuItem(
            value: o,
            checked: o == selected,
            child: entry(icon?.call(o), label(o)),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: _SortDirection.ascending,
          checked: ascending,
          child: entry(Icons.arrow_upward_rounded, 'Croissant'),
        ),
        CheckedPopupMenuItem(
          value: _SortDirection.descending,
          checked: !ascending,
          child: entry(Icons.arrow_downward_rounded, 'Décroissant'),
        ),
      ],
      // Écran étroit : icône et sens seulement (critère en info-bulle).
      child: MediaQuery.sizeOf(context).width < 600
          ? Tooltip(
              message: 'Tri : ${label(selected)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(current, size: headerIconSize, color: c.muted),
                    Icon(
                      ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                      color: c.accent,
                    ),
                  ],
                ),
              ),
            )
          : Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(current, size: 18, color: c.muted),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(
                      label(selected),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    ascending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 14,
                    color: c.accent,
                  ),
                ],
              ),
            ),
    );
  }
}

/// Pastille ronde d'action sur une affiche (Lire, Télécharger…), opaque.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.size = 30,
  });
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: size * 0.62, color: Colors.white),
            ),
          ),
        ),
      );
}
