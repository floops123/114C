import 'package:c411_remote/ui/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Page verticale contenant une rangée horizontale de 20 cartes de 100 px.
Widget _page(ScrollController page, ScrollController? Function(ScrollController) row) =>
    MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: ListView(controller: page, children: [
          SizedBox(
            height: 100,
            child: HorizontalScroller(
              builder: (controller) {
                row(controller);
                return ListView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < 20; i++)
                      SizedBox(width: 100, child: Text('C$i')),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 3000),
        ]),
      ),
    );

void main() {
  testWidgets('molette : la rangée défile de côté, puis la page', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final page = ScrollController();
    late ScrollController row;
    await tester.pumpWidget(_page(page, (c) => row = c));

    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    final over = tester.getCenter(find.text('C1'));
    await tester.sendEventToBinding(mouse.hover(over));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 300)));
    await tester.pump();
    expect(row.offset, 300);
    expect(page.offset, 0, reason: 'la page ne bouge pas en même temps');

    // Au bout de la rangée (2000 − 400 px), la molette fait défiler la page.
    row.jumpTo(row.position.maxScrollExtent);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 200)));
    await tester.pump();
    expect(page.offset, 200);

    // Vers le haut : la rangée revient d'abord en arrière.
    page.jumpTo(0);
    await tester.pump();
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(row.offset, row.position.maxScrollExtent - 100);
  });

  testWidgets('souris : on fait glisser la rangée en cliquant', (tester) async {
    final page = ScrollController();
    late ScrollController row;
    await tester.pumpWidget(_page(page, (c) => row = c));
    await tester.drag(find.text('C1'), const Offset(-250, 0),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(row.offset, greaterThan(200));
  });

  testWidgets('souris : cliquer-glisser fait défiler une liste verticale, '
      'même en partant d’une carte cliquable', (tester) async {
    final page = ScrollController();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: ListView(controller: page, children: [
          for (var i = 0; i < 50; i++)
            InkWell(
              onTap: () => taps++,
              child: SizedBox(height: 80, child: Text('L$i')),
            ),
        ]),
      ),
    ));
    await tester.drag(find.text('L2'), const Offset(0, -300),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(page.offset, greaterThan(250));
    expect(taps, 0, reason: 'un glisser n’est pas un clic');

    await tester.tap(find.text('L5'), kind: PointerDeviceKind.mouse);
    expect(taps, 1, reason: 'le clic marche toujours');
  });

  testWidgets('fil du salon : glisser à la souris ne fait pas défiler',
      (tester) async {
    final page = ScrollController();
    await tester.pumpWidget(MaterialApp(
      scrollBehavior: const AppScrollBehavior(),
      home: Scaffold(
        body: MouseSelectsText(
          child: SelectionArea(
            child: ListView(controller: page, children: [
              for (var i = 0; i < 50; i++)
                SizedBox(height: 80, child: Text('M$i')),
            ]),
          ),
        ),
      ),
    ));
    await tester.drag(find.text('M2'), const Offset(0, -300),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(page.offset, 0);
    // Au doigt, on fait toujours défiler.
    await tester.drag(find.text('M2'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(page.offset, greaterThan(250));
  });
}
