import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ipesa_guias/widgets/invitacion_recordatorio.dart';

void main() {
  testWidgets('Ofrece activar el recordatorio de las 6 p. m.', (tester) async {
    var activar = 0, ahoraNo = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvitacionRecordatorio(
            onActivar: () => activar++,
            onAhoraNo: () => ahoraNo++,
          ),
        ),
      ),
    );
    expect(find.textContaining('6 p. m.'), findsOneWidget);
    await tester.tap(find.text('Activar'));
    await tester.tap(find.text('Ahora no'));
    expect((activar, ahoraNo), (1, 1));
  });
}
