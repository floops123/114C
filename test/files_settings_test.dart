import 'dart:io';

import 'package:c411_remote/core/settings.dart';
import 'package:c411_remote/ui/settings_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_webdav.dart';

class _Saved extends SettingsNotifier {
  _Saved(this.initial);
  final AppSettings initial;
  @override
  Future<AppSettings> build() async => initial;
}

void main() {
  testWidgets('Réglages : protocole WebDAV, champs et test de connexion', (tester) async {
    // Les tests de widgets remplacent HttpClient par une maquette (400) :
    // ici, le vrai, vers le serveur WebDAV local.
    HttpOverrides.global = null;
    tester.view.physicalSize = const Size(900, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = (await tester.runAsync(() => FakeWebDav.start({'/torrents/a.mkv': [1]})))!;
    addTearDown(server.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _Saved(AppSettings(
            filesProtocol: 'webdav', webdavUrl: server.url, webdavUser: 'moi',
            webdavPassword: 'secret', ftpHost: 'ftp.example', ftpUser: 'f'))),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const SettingsPage()),
    ));
    await tester.pumpAndSettle();

    final url = find.widgetWithText(TextField, 'Adresse du partage');
    expect(url, findsOneWidget);
    expect(tester.widget<TextField>(url).controller!.text, server.url);
    expect(find.widgetWithText(TextField, 'Hôte'), findsNothing, reason: 'champs FTP masqués');

    // « Tester » de la section : le premier sous le champ d'adresse.
    final below = tester.getTopLeft(url).dy;
    final testers = find.widgetWithText(OutlinedButton, 'Tester').evaluate().toList()
      ..sort((a, b) => tester.getTopLeft(find.byWidget(a.widget)).dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy));
    final button = testers.firstWhere((e) => tester.getTopLeft(find.byWidget(e.widget)).dy > below);
    await tester.tap(find.byWidget(button.widget));
    for (var i = 0; i < 20 && find.textContaining('✓ Connecté').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('✓ Connecté · dossiers à la racine : torrents'), findsOneWidget);

    await tester.tap(find.text('FTP'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Hôte'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Adresse du partage'), findsNothing);
  });
}
