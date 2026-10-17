import 'dart:convert';
import 'dart:io';

import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/ui/server_settings_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Réponses réelles d'un transmission-daemon 4.0.5 (test/fixtures).
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name-4.0.5.json').readAsStringSync())
        as Map<String, dynamic>;

class _FakeTransmission extends TransmissionClient {
  _FakeTransmission() : super(url: 'http://fake');

  final session = _fixture('session-get');
  final sets = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> sessionGet() async => session;

  @override
  Future<Map<String, dynamic>> sessionStats() async => _fixture('session-stats');

  @override
  Future<({int? free, int? total})> diskSpace(String path) async =>
      (free: 123456789012, total: 500107862016);

  @override
  Future<void> sessionSet(Map<String, dynamic> args) async {
    sets.add(args);
    session.addAll(args);
  }
}

void main() {
  testWidgets('affiche les réglages du serveur et n’envoie que les changements',
      (tester) async {
    tester.view.physicalSize = const Size(900, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = _FakeTransmission();
    await tester.pumpWidget(ProviderScope(
      overrides: [transmissionProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: const ServerSettingsPage(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('4.0.5'), findsWidgets);
    for (final title in [
      'Téléchargements', 'Limites de vitesse', 'Mode tortue', 'Files d’attente',
      'Partage', 'Réseau', 'Découverte de pairs', 'Blocklist',
      'Trackers par défaut', 'Scripts', 'Sécurité',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    // Absente en 4.0.5 : pas affichée.
    expect(find.textContaining('séquentiel'), findsNothing);

    // Aucune modification : pas de barre d'enregistrement.
    expect(find.text('Enregistrer'), findsNothing);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Limiter la réception'));
    await tester.pump();
    await tester.enterText(
        find.widgetWithText(TextField, 'Réception max'), '4200');
    await tester.pump();
    expect(find.text('2 modification(s) non enregistrée(s)'), findsOneWidget);

    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(fake.sets, [
      {'speed-limit-down-enabled': true, 'speed-limit-down': 4200},
    ]);
    expect(find.text('Enregistrer'), findsNothing);
  });
}
