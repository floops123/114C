import 'dart:collection';

import 'package:c411_remote/state/speed_history.dart';
import 'package:c411_remote/ui/charts.dart';
import 'package:c411_remote/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('courbe des vitesses : légende, résumé et info-bulle sans '
      'débordement des deux côtés', (tester) async {
    final now = DateTime.now();
    final samples = ListQueue<SpeedSample>.of([
      for (var s = 600; s >= 0; s -= 2)
        SpeedSample(now.subtract(Duration(seconds: s)), 5000000 + s * 1000,
            1500000),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.light]),
      home: Scaffold(
        body: SizedBox(
          width: 700,
          child: SpeedChart(
              samples: samples, window: const Duration(minutes: 15)),
        ),
      ),
    ));
    expect(find.text('Réception'), findsOneWidget);
    expect(find.textContaining('Moyenne'), findsOneWidget);

    final chart = tester.getRect(find.byType(CustomPaint).last);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    for (final dx in [0.6, 0.98]) {
      await mouse.moveTo(Offset(chart.left + chart.width * dx, chart.center.dy));
      await tester.pump();
      expect(find.text('réception'), findsOneWidget, reason: 'survol à $dx');
    }
    await mouse.removePointer();
  });

  testWidgets('barres : une ligne par élément, valeur au bout', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppColors.dark]),
      home: const Scaffold(
        body: BarList(color: Colors.orange, items: [
          BarItem('Premier', 100, '100 Go'),
          BarItem('Second', 25, '25 Go'),
          BarItem('Vide', 0, '0 Go'),
        ]),
      ),
    ));
    expect(find.text('100 Go'), findsOneWidget);
    expect(find.text('25 Go'), findsOneWidget);
    final first = tester.getSize(find.byType(Container).at(0)).width;
    expect(first, greaterThan(0));
  });
}
