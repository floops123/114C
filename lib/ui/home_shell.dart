import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../state/speed_history.dart';
import '../state/notifications.dart';
import '../state/revive.dart';
import 'chat_page.dart';
import 'downloads_page.dart';
import 'notifications_page.dart';
import 'releases_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'wishlist_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  /// Bascule sur l'onglet Salon si on est dans la navigation principale ;
  /// renvoie false sinon (l'appelant ouvre alors la page du salon).
  static bool showChat(BuildContext context) {
    final shell = context.findAncestorStateOfType<_HomeShellState>();
    shell?.select(_HomeShellState._chatTab);
    return shell != null;
  }

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _destinations = [
    (Icons.local_movies_outlined, Icons.local_movies, 'Sorties'),
    (Icons.bookmarks_outlined, Icons.bookmarks, 'Souhaits'),
    (Icons.downloading_outlined, Icons.downloading, 'Transferts'),
    (Icons.notifications_outlined, Icons.notifications, 'Notifications'),
    (Icons.forum_outlined, Icons.forum, 'Salon'),
    (Icons.tune_outlined, Icons.tune, 'Réglages'),
  ];
  static const _pages = [
    ReleasesPage(),
    WishlistPage(),
    DownloadsPage(),
    NotificationsPage(),
    ChatPage(),
    SettingsPage(),
  ];
  static const _notificationsTab = 3, _chatTab = 4, _settingsTab = 5;

  int _index = 0;
  bool _routed = false;

  /// En quittant l'onglet Notifications, celles affichées deviennent lues.
  void select(int i) {
    if (_index == _notificationsTab && i != _notificationsTab) {
      ref.read(notificationsProvider.notifier).markAllRead();
    }
    setState(() => _index = i);
  }

  /// Icône de navigation, avec le nombre de non-lues : notifications, et
  /// messages de salon signalés par le site.
  static Widget _icon(IconData icon, int index, (int, int) unread) {
    final n = switch (index) {
      _notificationsTab => unread.$1,
      _chatTab => unread.$2,
      _ => 0,
    };
    return n > 0 ? Badge.count(count: n, child: Icon(icon)) : Icon(icon);
  }

  @override
  Widget build(BuildContext context) {
    // Premier lancement : on ouvre directement les réglages.
    final settings = ref.watch(settingsProvider).value;
    if (!_routed && settings != null) {
      _routed = true;
      if (!settings.hasTracker && !settings.hasTransmission) {
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

    final c = context.colors;
    // Onglets masqués : gardés en mémoire, mais leurs animations à l'arrêt.
    final body = IndexedStack(index: _index, children: [
      for (final (i, page) in _pages.indexed)
        TickerMode(enabled: i == _index, child: page),
    ]);

    final destinations = [
      for (final (i, (icon, selected, label)) in _destinations.indexed)
        (i, icon, selected, label),
    ];

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
                        for (final (i, icon, selected, label) in destinations)
                          NavigationRailDestination(
                            icon: _icon(icon, i, unread),
                            selectedIcon: _icon(selected, i, unread),
                            label: Text(label),
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
                  for (final (i, icon, selected, label) in destinations)
                    NavigationDestination(
                      icon: _icon(icon, i, unread),
                      selectedIcon: _icon(selected, i, unread),
                      // Barre du bas : libellés courts (6 onglets sur un
                      // téléphone), « Notifications » ne tient pas.
                      label: label == 'Notifications' ? 'Notifs' : label,
                    ),
                ],
              ),
            ),
          );
        });
  }
}
