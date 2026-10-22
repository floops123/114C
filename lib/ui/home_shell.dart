import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../state/draupnirr.dart';
import '../state/speed_history.dart';
import '../state/notifications.dart';
import '../state/release_watch.dart';
import '../state/revive.dart';
import 'chat_page.dart';
import 'downloads_page.dart';
import 'draupnirr_page.dart';
import 'notifications_page.dart';
import 'settings_page.dart';
import 'trackers_page.dart';
import 'theme.dart';
import 'wishlist_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  /// Bascule sur l'onglet Salon si on est dans la navigation principale ;
  /// renvoie false sinon (l'appelant ouvre alors la page du salon).
  static bool showChat(BuildContext context) {
    final shell = context.findAncestorStateOfType<_HomeShellState>();
    if (shell == null) return false;
    shell.select(shell._chatTab);
    return true;
  }

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // Onglets fixes, dans l'ordre. L'onglet Draupnirr s'insère entre
  // Transferts et Notifications quand la clé API est saisie.
  static const _baseDestinations = <(IconData, IconData, String)>[
    (Icons.movie_outlined, Icons.movie, 'Films & séries'),
    (Icons.hub_outlined, Icons.hub, 'Trackers'),
    (Icons.downloading_outlined, Icons.downloading, 'Transferts'),
    // Notifications, compte et compteurs du site C411.
    (Icons.notifications_outlined, Icons.notifications, _c411Label),
    (Icons.forum_outlined, Icons.forum, 'Salon'),
    (Icons.tune_outlined, Icons.tune, 'Réglages'),
  ];
  static const _basePages = <Widget>[
    WishlistPage(),
    TrackersPage(),
    DownloadsPage(),
    NotificationsPage(),
    ChatPage(),
    SettingsPage(),
  ];

  static const _draupnirrLabel = 'Draupnirr';
  static const _c411Label = 'C411';

  int _index = 0;
  bool _routed = false;

  /// Onglets déjà ouverts, par nom (les index bougent avec Draupnirr). Un
  /// onglet n'est construit qu'à sa première visite, puis gardé : au
  /// lancement, seul l'onglet affiché charge ses données et ses images.
  final _visited = <String>{};

  /// Construit la liste des onglets : Draupnirr est inséré entre Transferts
  /// (index 2) et Notifications si la clé API est saisie.
  List<(IconData, IconData, String)> _destinations() {
    final hasDraupnirr = ref.watch(draupnirrApiProvider) != null;
    return [
      ..._baseDestinations.take(3),
      if (hasDraupnirr) (Icons.shield_outlined, Icons.shield, _draupnirrLabel),
      ..._baseDestinations.skip(3),
    ];
  }

  List<Widget> _pages() {
    final hasDraupnirr = ref.watch(draupnirrApiProvider) != null;
    return [
      ..._basePages.take(3),
      if (hasDraupnirr) const DraupnirrPage(),
      ..._basePages.skip(3),
    ];
  }

  /// Index d'un onglet par nom, ou -1 si absent.
  int _indexOf(List<(IconData, IconData, String)> d, String label) =>
      d.indexWhere((e) => e.$3 == label);

  /// Index calculés à chaque build (les destinations peuvent changer si
  /// l'utilisateur saisit/retire sa clé Draupnirr).
  int get _notificationsTab => _indexOf(_destinations(), _c411Label);
  int get _chatTab => _indexOf(_destinations(), 'Salon');
  int get _settingsTab => _indexOf(_destinations(), 'Réglages');

  /// En quittant l'onglet Notifications, celles affichées deviennent lues.
  void select(int i) {
    if (_index == _notificationsTab && i != _notificationsTab) {
      ref.read(notificationsProvider.notifier).markAllRead();
    }
    setState(() => _index = i);
  }

  /// Icône de navigation, avec le nombre de non-lues : notifications, et
  /// messages de salon signalés par le site.
  Widget _icon(IconData icon, int index, (int, int) unread) {
    final notif = _notificationsTab;
    final chat = _chatTab;
    final n = switch (index) {
      var i when i == notif => unread.$1,
      var i when i == chat => unread.$2,
      _ => 0,
    };
    return n > 0 ? Badge.count(count: n, child: Icon(icon)) : Icon(icon);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations();
    final pages = _pages();

    // Si l'onglet courant n'existe plus (Draupnirr retiré des Réglages),
    // on retombe sur « Films & séries ».
    if (_index >= pages.length) _index = 0;

    // Premier lancement : on ouvre directement les réglages.
    final settings = ref.watch(settingsProvider).value;
    if (!_routed && settings != null) {
      _routed = true;
      if (!settings.hasTracker && !settings.hasTransmission &&
          _settingsTab >= 0) {
        _index = _settingsTab;
      }
    }

    // Nouvelle notification hors de l'onglet : bandeau avec raccourci.
    ref.listen(notificationsProvider.select((s) => s.arrivals), (_, _) {
      final text = ref.read(notificationsProvider).arrival;
      if (text == null || _index == _notificationsTab) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(text),
          action: SnackBarAction(
              label: 'Voir', onPressed: () => select(_notificationsTab)),
          // Avec une action, le bandeau reste affiché : on peut aussi le fermer.
          showCloseIcon: true,
        ));
    });
    final unread = ref.watch(notificationsProvider.select((s) => (
          s.unread,
          s.counters?.counts['channelMessages'] ?? 0,
        )));

    // L'historique des vitesses s'enregistre dès l'ouverture de l'application,
    // sans reconstruire cet écran à chaque mesure.
    ref.listen(speedHistoryProvider, (_, _) {});
    // Passage en cross-seed C411 des téléchargements tr4ker terminés.
    ref.listen(reviveProvider, (_, _) {});
    // Veille des nouveautés : relevés périodiques dès l'ouverture.
    ref.listen(releaseWatchProvider, (_, _) {});
    // Si on ouvre l'onglet Draupnirr, son notifier charge les données
    // automatiquement (déclenché par `draupnirrProvider`).
    ref.listen(draupnirrProvider, (_, _) {});

    final c = context.colors;
    _visited.add(destinations[_index].$3);
    // Onglets masqués : gardés en mémoire une fois visités, mais leurs
    // animations à l'arrêt ; jamais visités : pas construits du tout. Leurs
    // info-bulles sont retirées : animation gelée, une info-bulle ouverte
    // restait affichée par-dessus l'onglet suivant.
    final body = IndexedStack(index: _index, children: [
      for (final (i, page) in pages.indexed)
        TickerMode(
          enabled: i == _index,
          child: TooltipVisibility(
            visible: i == _index,
            child: _visited.contains(destinations[i].$3)
                ? page
                : const SizedBox.shrink(),
          ),
        ),
    ]);

    return LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth >= 720) {
            return Scaffold(
              body: Row(children: [
                // Barre de navigation flottante.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                  child: Panel(
                    radius: 22,
                    child: NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: select,
                      labelType: NavigationRailLabelType.all,
                      minWidth: 84,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [c.accent, c.download],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('411',
                              style: TextStyle(
                                  color: c.onAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                        ),
                      ),
                      destinations: [
                        for (var i = 0; i < destinations.length; i++)
                          NavigationRailDestination(
                            icon: _icon(destinations[i].$1, i, unread),
                            selectedIcon: _icon(destinations[i].$2, i, unread),
                            label: Text(destinations[i].$3),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: body),
              ]),
            );
          }
          // Barre du bas : libellés courts quand ils débordent.
          final labels = [
            for (final d in destinations)
              switch (d.$3) {
                'Films & séries' => 'Films',
                _ => d.$3,
              },
          ];
          return Scaffold(
            body: SafeArea(bottom: false, child: body),
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border))),
              child: _FittedLabels(
                labels: labels,
                width: constraints.maxWidth,
                child: NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: select,
                  destinations: [
                    for (var i = 0; i < destinations.length; i++)
                      NavigationDestination(
                        icon: _icon(destinations[i].$1, i, unread),
                        selectedIcon: _icon(destinations[i].$2, i, unread),
                        label: labels[i],
                      ),
                  ],
                ),
              ),
            ),
          );
        });
  }
}

/// Réduit la taille des libellés de la barre du bas pour que le plus long
/// tienne sur une ligne : sept onglets sur un téléphone de 360 à 400 px
/// coupaient « Transferts » en deux.
class _FittedLabels extends StatelessWidget {
  const _FittedLabels({required this.labels, required this.width, required this.child});
  final List<String> labels;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    final style = theme.labelTextStyle;
    if (style == null || labels.isEmpty) return child;
    final selected = style.resolve({WidgetState.selected}) ?? const TextStyle();
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final l in labels) {
      final painter = TextPainter(
        text: TextSpan(text: l, style: DefaultTextStyle.of(context).style.merge(selected)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    // Marge de 4 px de part et d'autre du libellé.
    final room = width / labels.length - 8;
    if (widest <= room) return child;
    final factor = room / widest;
    return NavigationBarTheme(
      data: theme.copyWith(
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final s = style.resolve(states) ?? const TextStyle();
          return s.copyWith(fontSize: (s.fontSize ?? 12) * factor);
        }),
      ),
      child: child,
    );
  }
}
