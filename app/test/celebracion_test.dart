import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/widgets/celebracion_jornada.dart';

void main() {
  testWidgets('La felicitación sale una sola vez por día', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final navegador = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navegador, home: const Scaffold()),
    );

    Future<void> intentar(DateTime dia) async {
      CelebracionJornada.mostrarSiCorresponde(
        navegador.currentState!,
        nombre: 'Oscar Aspur',
        entregadasHoy: 8,
        ahora: dia,
      );
      await tester.pumpAndSettle();
    }

    await intentar(DateTime(2026, 9, 29, 16));
    expect(find.text('¡Excelente trabajo, Oscar!'), findsOneWidget);
    expect(find.text('8 guías entregadas hoy'), findsOneWidget);
    await tester.tap(find.text('¡Sigo así!'));
    await tester.pumpAndSettle();

    // El mismo día ya no vuelve a salir.
    await intentar(DateTime(2026, 9, 29, 18));
    expect(find.text('JORNADA IMPECABLE'), findsNothing);

    // Al día siguiente, sí.
    await intentar(DateTime(2026, 9, 30, 17));
    expect(find.text('JORNADA IMPECABLE'), findsOneWidget);
  });
}
