import 'package:c411_remote/api/transmission.dart';
import 'package:c411_remote/core/preferences.dart';
import 'package:c411_remote/ui/downloads_page.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Prefs extends UiPrefsNotifier {
  _Prefs(this.initial);
  final UiPrefs initial;
  @override
  UiPrefs build() => initial;
}

/// Transmission qui compte les relevés.
class _Client extends TransmissionClient {
  _Client() : super(url: 'http://x');
  int reads = 0;

  @override
  Future<TorrentGetResult> torrentGet(List<String> fields, {Object? ids}) async {
    reads++;
    return (
      torrents: [
        for (var i = 0; i < 6; i++)
          {'id': i, 'name': 'Torrent.$i', 'hashString': 'h$i', 'status': 6, 'percentDone': 1.0,
           'sizeWhenDone': 1000, 'addedDate': i},
      ],
      removed: <int>[],
    );
  }
}

void main() {
  Future<_Client> pump(WidgetTester tester, UiPrefs prefs) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _Client();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        uiPrefsProvider.overrideWith(() => _Prefs(prefs)),
        transmissionProvider.overrideWithValue(client),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const DownloadsPage()),
    ));
    await tester.pump();
    await tester.pump();
    return client;
  }

  testWidgets('Transferts : nombre de torrents affichés limité', (tester) async {
    await pump(tester, const UiPrefs(transferLimit: 4));
    expect(find.textContaining('Torrent.'), findsNWidgets(4));
    expect(find.text('4 affichés sur 6'), findsOneWidget);

    await tester.tap(find.text('Tout afficher'));
    await tester.pump();
    expect(find.textContaining('Torrent.'), findsNWidgets(6));
    expect(find.textContaining('affichés sur'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // Arrête les relevés.
  });

  testWidgets('Transferts : actualisation automatique désactivable', (tester) async {
    final client = await pump(tester, const UiPrefs(autoRefresh: false));
    final first = client.reads;
    await tester.pump(const Duration(seconds: 7));
    expect(client.reads, first, reason: 'pas de relevé périodique');

    await tester.tap(find.byTooltip('Actualiser'));
    await tester.pump();
    expect(client.reads, first + 1);

    await tester.tap(find.text('Actualisation auto'));
    await tester.pump(const Duration(seconds: 3));
    expect(client.reads, greaterThan(first + 1));
    expect(find.byTooltip('Actualiser'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
