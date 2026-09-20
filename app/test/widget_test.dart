import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ipesa_guias/app.dart';

void main() {
  testWidgets('Muestra la pantalla de selección de rol al iniciar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IpesaGuiasApp());

    expect(find.text('IPESA · Control de Guías'), findsOneWidget);
    expect(find.text('Transportista'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Equipo Comercial'), findsOneWidget);
  });

  testWidgets('El transportista puede ver su lista de tareas', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IpesaGuiasApp());

    await tester.tap(find.text('Transportista'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mis tareas'), findsOneWidget);
    expect(find.text('Nueva guía'), findsOneWidget);
  });

  testWidgets('El rastreo público valida los últimos 4 dígitos', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IpesaGuiasApp());

    await tester.tap(find.text('Equipo Comercial'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '4821');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('•••• 4821'), findsOneWidget);
  });
}
