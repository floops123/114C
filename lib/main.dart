import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/preferences.dart';
import 'ui/home_shell.dart';
import 'ui/smooth_wheel.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  // Défilement fluide à la molette (version PC).
  SmoothWheelBinding.ensureInitialized();
  // Images décodées gardées en mémoire : 50 Mo au lieu de 100 par défaut.
  // Les affiches sont décodées à leur taille d'affichage ; un écran en
  // montre une quarantaine, soit une vingtaine de Mo.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 50 << 20
    ..maximumSize = 400;
  // Le lecteur (libmpv, ~40 Mo) n'est chargé qu'à la première lecture :
  // voir PlayerPage.  // Licence de la police Inter, visible dans l'écran des licences.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        ['Inter'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final prefs = await loadSharedPrefs();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
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
