import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import '../state/speed_history.dart';
import '../state/notifications.dart';
import 'downloads_page.dart';
import 'notifications_page.dart';
import 'releases_page.dart';
import 'settings_page.dart';
import 'theme.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _destinations = [
    (Icons.local_movies_outlined, Icons.local_movies, 'Sorties'),
    (Icons.downloading_outlined, Icons.downloading, 'Transferts'),
    (Icons.notifications_outlined, Icons.notifications, 'Notifications'),
    (Icons.tune_outlined, Icons.tune, 'Réglages'),
  ];
  static const _pages = [
    ReleasesPage(),
    DownloadsPage(),
    NotificationsPage(),
    SettingsPage(),
  ];
  static const _notificationsTab = 2, _settingsTab = 3;

  int _index = 0;
  bool _routed = false;

  /// En quittant l'onglet Notifications, celles affichées deviennent lues.
  void select(int i) {
    if (_index == _notificationsTab && i != _notificationsTab) {
      ref.read(notificationsProvider.notifier).markAllRead();
    }
    setState(() => _index = i);
  }

  /// Icône de navigation, avec le nombre de non-lues sur les notifications.
  static Widget _icon(IconData icon, int index, int unread) =>
      index == _notificationsTab && unread > 0
          ? Badge.count(count: unread, child: Icon(icon))
          : Icon(icon);

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
    ref.listen(notificationsProvider, (previous, next) {
      final before = previous?.items.length ?? 0;
      if (next.items.length <= before || _index == _notificationsTab) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(next.items.first.title),
          action: SnackBarAction(
              label: 'Voir', onPressed: () => select(_notificationsTab)),
        ));
    });
    final unread = ref.watch(notificationsProvider.select((s) => s.unread));

    // L'historique des vitesses s'enregistre dès l'ouverture de l'application,
    // sans reconstruire cet écran à chaque mesure.
    ref.listen(speedHistoryProvider, (_, _) {});

    final c = context.colors;
    final body = IndexedStack(index: _index, children: _pages);

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 720) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
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
                    color: c.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('411',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
              ),
              destinations: [
                for (final (i, (icon, selected, label)) in _destinations.indexed)
                  NavigationRailDestination(
                    icon: _icon(icon, i, unread),
                    selectedIcon: _icon(selected, i, unread),
                    label: Text(label),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: c.border),
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
              for (final (i, (icon, selected, label)) in _destinations.indexed)
                NavigationDestination(
                  icon: _icon(icon, i, unread),
                  selectedIcon: _icon(selected, i, unread),
                  label: label,
                ),
            ],
          ),
        ),
      );
    });
  }
}
