import 'dart:convert';
import 'dart:io';

import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/state/torrents.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:c411_remote/ui/torrent_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTransmission extends TransmissionClient {
  _FakeTransmission() : super(url: 'http://fake');

  final sets = <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> groupGet() async => [
        {'name': 'lent'},
      ];

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async =>
      (torrents: <Map<String, dynamic>>[], removed: <int>[]);

  @override
  Future<void> torrentSet(List<int> ids, Map<String, dynamic> args) async =>
      sets.add(args);
}

void main() {
  // Réponse réelle d'un transmission-daemon 4.0.5 (torrent Debian en pause).
  final json = jsonDecode(
          File('test/fixtures/torrent-detail-4.0.5.json').readAsStringSync())
      as Map<String, dynamic>;

  testWidgets('les 5 onglets du détail s’affichent et Options n’envoie que '
      'les changements', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = _FakeTransmission();
    final id = (json['id'] as num).toInt();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        transmissionProvider.overrideWithValue(fake),
        torrentDetailProvider.overrideWith((ref, _) => Stream.value(json)),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppColors.dark]),
        home: TorrentDetailPage(id: id, name: '…'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PIÈCES'), findsOneWidget);
    expect(find.textContaining('/ 3024 pièces'), findsOneWidget);
    expect(find.text('TRANSFERT'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Fichiers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fichiers sélectionnés'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Pairs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('203.0.113.7'), findsOneWidget);
    expect(find.text('µTP'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Trackers'));
    await tester.pumpAndSettle();
    expect(find.text('Modifier'), findsOneWidget);
    expect(find.textContaining('palier'), findsWidgets);

    await tester.tap(find.widgetWithText(Tab, 'Options'));
    await tester.pumpAndSettle();
    expect(find.text('Aucune modification'), findsOneWidget);
    await tester.tap(find.text('Haute'));
    await tester.pump();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Limiter la réception'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Réception max'), '500');
    await tester.pump();
    expect(find.text('3 modification(s)'), findsOneWidget);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(fake.sets, [
      {'bandwidthPriority': 1, 'downloadLimited': true, 'downloadLimit': 500},
    ]);
  });
}
