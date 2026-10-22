import 'package:c411_remote/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OneLineRow : masque ce qui ne tient pas entier, dans l’ordre',
      (tester) async {
    Widget box(String label, double width, double height) =>
        SizedBox(width: width, height: height, child: Text(label));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 250,
          child: OneLineRow(children: [
            box('A', 100, 20),
            box('B', 100, 30),
            box('C', 100, 20),
            box('D', 20, 20), // Tiendrait, mais vient après C : masqué aussi.
          ]),
        ),
      ),
    ));
    expect(find.text('A').hitTestable(), findsOneWidget);
    expect(find.text('B').hitTestable(), findsOneWidget);
    expect(find.text('C').hitTestable(), findsNothing);
    expect(find.text('D').hitTestable(), findsNothing);
    expect(tester.getSize(find.byType(OneLineRow)).height, 30);
    // Centrés verticalement sur l'élément le plus haut.
    expect(tester.getTopLeft(find.text('A')).dy, 5);
  });
}
