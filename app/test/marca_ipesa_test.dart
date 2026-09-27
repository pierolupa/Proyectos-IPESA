import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ipesa_guias/widgets/carrusel_marcas.dart';
import 'package:ipesa_guias/widgets/splash_ipesa.dart';

double _desplazamiento(WidgetTester tester) => tester
    .widget<Transform>(
      find.descendant(
        of: find.byType(CarruselMarcas),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .getTranslation()
    .x;

void main() {
  testWidgets('La pantalla de inicio muestra el logo y "Cargando datos"', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashIpesa()));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.bySemanticsLabel('IPESA'), findsOneWidget);
    expect(find.text('CARGANDO DATOS'), findsOneWidget);
  });

  testWidgets('El carrusel avanza solo y muestra todas las marcas', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CarruselMarcas())),
      ),
    );
    final inicio = _desplazamiento(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(_desplazamiento(tester), lessThan(inicio));

    for (final (nombre, _) in marcasIpesa) {
      expect(find.bySemanticsLabel(nombre), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Con animaciones reducidas el carrusel queda quieto', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CarruselMarcas())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
    expect(find.bySemanticsLabel('John Deere'), findsOneWidget);
  });
}
