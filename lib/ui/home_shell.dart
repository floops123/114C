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
    (Icons.notifications_outlined, Icons.notifications, 'Notifications'),
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

  int _index = 0;
  bool _routed = false;

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
  int get _notificationsTab => _indexOf(_destinations(), 'Notifications');
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
    // Onglets masqués : gardés en mémoire, mais leurs animations à l'arrêt.
    final body = IndexedStack(index: _index, children: [
      for (final (i, page) in pages.indexed)
        TickerMode(enabled: i == _index, child: page),
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
          return Scaffold(
            body: SafeArea(bottom: false, child: body),
            bottomNavigationBar: DecoratedBox(
              decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border))),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: select,
                destinations: [
                  for (var i = 0; i < destinations.length; i++)
                    NavigationDestination(
                      icon: _icon(destinations[i].$1, i, unread),
                      selectedIcon: _icon(destinations[i].$2, i, unread),
                      // Barre du bas : libellés courts quand ils débordent.
                      label: switch (destinations[i].$3) {
                        'Notifications' => 'Notifs',
                        'Films & séries' => 'Films',
                        _ => destinations[i].$3,
                      },
                    ),
                ],
              ),
            ),
          );
        });
  }
}
