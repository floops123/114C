import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings.dart';
import 'downloads_page.dart';
import 'releases_page.dart';
import 'settings_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _destinations = [
    (Icons.new_releases_outlined, Icons.new_releases, 'Sorties'),
    (Icons.download_outlined, Icons.download, 'Téléchargements'),
    (Icons.settings_outlined, Icons.settings, 'Réglages'),
  ];
  static const _pages = [ReleasesPage(), DownloadsPage(), SettingsPage()];

  int _index = 0;
  bool _routed = false;

  @override
  Widget build(BuildContext context) {
    // Premier lancement : on ouvre directement les réglages.
    final settings = ref.watch(settingsProvider).value;
    if (!_routed && settings != null) {
      _routed = true;
      if (!settings.hasTracker && !settings.hasTransmission) _index = 2;
    }

    final body = IndexedStack(index: _index, children: _pages);
    void select(int i) => setState(() => _index = i);

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 720) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: select,
          destinations: [
            for (final (icon, selected, label) in _destinations)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selected),
                label: label,
              ),
          ],
        ),
      );
    });
  }
}
