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
  testWidgets('La pantalla de carga muestra el logo de frente', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashIpesa()));
    await tester.pump();

    // Sin animación de entrada: el logo está completo desde el primer cuadro.
    expect(
      find.ancestor(
        of: find.bySemanticsLabel('IPESA'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );

    expect(find.bySemanticsLabel('IPESA'), findsOneWidget);
    expect(find.text('TRACKING DISTRIBUCIÓN'), findsOneWidget);
    // Logo y nombre fijos; solo la barra de progreso avanza.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    double avance() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    final alInicio = avance();
    await tester.pump(const Duration(seconds: 2));
    expect(avance(), greaterThan(alInicio));
    expect(avance(), lessThan(1));
    // Termina de moverse sola (no traba a pumpAndSettle).
    await tester.pumpAndSettle();
    expect(avance(), lessThan(1));
  });

  testWidgets('El carrusel avanza solo y muestra todas las marcas', (
    tester,
  ) async {
    CarruselMarcas.animar = true;
    addTearDown(() => CarruselMarcas.animar = false);
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
