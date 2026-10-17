import 'package:c411_remote/ui/smooth_wheel.dart';
import 'package:c411_remote/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PointerScrollEvent _wheel(double dy, {Offset at = Offset.zero}) =>
    PointerScrollEvent(
        kind: PointerDeviceKind.mouse, position: at, scrollDelta: Offset(0, dy));

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  test('un cran est étalé dans le temps, en ralentissant', () {
    final sent = <double>[];
    final s = WheelSmoother(dispatch: (e) => sent.add(e.scrollDelta.dy));
    s.add(_wheel(100));
    // Images toutes les 16 ms à partir de t = 1000 ms.
    var frame = 1000;
    while (s.tick(_ms(frame))) {
      frame += 16;
    }
    expect(sent.fold<double>(0, (a, b) => a + b), closeTo(100, 1e-9));
    expect(sent.length, greaterThan(8), reason: 'plusieurs images, pas un saut');
    expect(sent.first, greaterThan(sent.last), reason: 'décélération');
    expect(s.active, isFalse);
  });

  test('deux crans rapprochés s’additionnent', () {
    var total = 0.0;
    final s = WheelSmoother(dispatch: (e) => total += e.scrollDelta.dy);
    s.add(_wheel(100));
    s.tick(_ms(0));
    s.tick(_ms(50)); // une partie du premier cran est partie
    s.add(_wheel(100));
    var frame = 66;
    while (s.tick(_ms(frame))) {
      frame += 16;
    }
    expect(total, closeTo(200, 1e-9));
  });

  testWidgets('les petits pas font défiler la page et les rangées',
      (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final page = ScrollController();
    late ScrollController row;
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: ListView(controller: page, children: [
          SizedBox(
            height: 100,
            child: HorizontalScroller(builder: (c) {
              row = c;
              return ListView(
                controller: c,
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 20; i++)
                    SizedBox(width: 100, child: Text('C$i')),
                ],
              );
            }),
          ),
          for (var i = 0; i < 40; i++) SizedBox(height: 80, child: Text('L$i')),
        ]),
      ),
    ));

    final s = WheelSmoother(dispatch: tester.binding.handlePointerEvent);
    Future<void> roll(double dy, Offset at) async {
      s.add(_wheel(dy, at: at));
      var frame = 0;
      while (s.tick(_ms(frame))) {
        frame += 16;
      }
      await tester.pump();
    }

    // Sur la liste : la page défile de toute la distance.
    await roll(240, tester.getCenter(find.text('L3')));
    expect(page.offset, closeTo(240, 1e-6));

    // Sur la rangée horizontale : elle défile de côté, pas la page.
    page.jumpTo(0);
    await tester.pump();
    await roll(150, tester.getCenter(find.text('C1')));
    expect(row.offset, closeTo(150, 1e-6));
    expect(page.offset, 0);
  });
}
