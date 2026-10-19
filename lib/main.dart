import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'build_defaults.dart';
import 'core/preferences.dart';
import 'ui/home_shell.dart';
import 'ui/smooth_wheel.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  // Défilement fluide à la molette (version PC).
  SmoothWheelBinding.ensureInitialized();
  // Lecteur vidéo intégré (libmpv).
  MediaKit.ensureInitialized();
  // Licence de la police Inter, visible dans l'écran des licences.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['Inter'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  // Réglages préenregistrés au build (--dart-define=C411_DEFAULTS_FILE=… ou
  // variables C411_* individuelles). Lu avant que `SettingsNotifier` ne se
  // construise pour la première fois, donc avant tout premier lancement.
  final defaults = await BuildDefaults.load();
  final prefs = await loadSharedPrefs();
  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      buildDefaultsProvider.overrideWithValue(defaults),
    ],
    child: const App(),
  ));
}

class App extends ConsumerWidget {
  const App({super.key});

  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(uiPrefsProvider.select((p) => p.themeMode));
    return MaterialApp(
      title: 'C411 Remote',
      debugShowCheckedModeBanner: false,
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      scrollBehavior: const AppScrollBehavior(),
      home: const HomeShell(),
    );
  }
}
