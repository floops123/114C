import 'package:c411_remote/api/quota.dart';
import 'package:c411_remote/api/tracker.dart';
import 'package:c411_remote/ui/quota_notice.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bandeau : visible pendant l’attente seulement', (tester) async {
    final quota = trackerQuotas[Tracker.c411]!;
    addTearDown(() => quota.waitingUntil.value = null);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(
          body: QuotaNotice(trackers: [Tracker.c411, Tracker.tr4ker])),
    ));
    expect(find.textContaining('Limite de requêtes'), findsNothing);

    quota.waitingUntil.value = DateTime.now().add(const Duration(seconds: 20));
    await tester.pump();
    expect(find.textContaining('C411 : reprise dans'), findsOneWidget);

    quota.waitingUntil.value = null;
    await tester.pump();
    expect(find.textContaining('Limite de requêtes'), findsNothing);
  });
}
