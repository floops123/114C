import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/preferences.dart';
import 'ui/app_fonts.dart';
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
  // voir PlayerPage.
  // Licences des polices, visibles dans l'écran des licences.
  LicenseRegistry.addLicense(() async* {
    for (final f in AppFont.values) {
      yield LicenseEntryWithLineBreaks([f.label], await rootBundle.loadString(f.license));
    }
  });
  final prefs = await loadSharedPrefs();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const App(),
  ));
}

class App extends ConsumerWidget {
  const App({super.key});

  /// Thèmes clair et sombre par police, construits à la demande.
  static final _themes = <(AppFont, Brightness), ThemeData>{};

  static ThemeData _theme(AppFont font, Brightness brightness) =>
      _themes[(font, brightness)] ??= buildTheme(brightness, font: font.family);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(uiPrefsProvider.select((p) => p.themeMode));
    final font = AppFont.byName(ref.watch(uiPrefsProvider.select((p) => p.font)));
    return MaterialApp(
      title: 'C411 Remote',
      debugShowCheckedModeBanner: false,
      theme: _theme(font, Brightness.light),
      darkTheme: _theme(font, Brightness.dark),
      themeMode: themeMode,
      scrollBehavior: const AppScrollBehavior(),
      // Les polices n'ont pas la même taille apparente : on la corrige,
      // par-dessus le réglage du système.
      builder: font.scale == 1
          ? null
          : (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                    textScaler: TextScaler.linear(media.textScaler.scale(1) * font.scale)),
                child: child!,
              );
            },
      home: const HomeShell(),
    );
  }
}
