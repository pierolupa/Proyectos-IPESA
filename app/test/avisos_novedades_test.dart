import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/avisos_novedades.dart';

Guia _guia(String numero, String estado, {String motivo = ''}) =>
    Guia.fromJson({
      'numero_guia': numero,
      'estado': estado,
      'tipo_entrega': 'cliente_final',
      'origen': 'Almacén Callao',
      'destino': 'Av. Principal 123',
      'transportista': 'Oscar Aspur',
      'destinatario': 'Ferretería Lima',
      'fecha_actualizacion': DateTime.now().toUtc().toIso8601String(),
      'corregido_por_admin': false,
      'motivo_rechazo': motivo,
    });

void main() {
  late CentroNovedades centro;
  late List<String> abiertas;

  setUp(() {
    centro = CentroNovedades();
    abiertas = [];
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => CapaAvisos(
            centro: centro,
            onAbrirGuia: (g) => abiertas.add(g.numeroGuia),
            onVerTodas: () {},
            child: Scaffold(
              body: Center(
                child: BotonNovedades(
                  centro: centro,
                  onPressed: () => mostrarPanelNovedades(
                    context,
                    centro: centro,
                    onAbrirGuia: (g) => abiertas.add(g.numeroGuia),
                    avisosDelNavegador: true,
                    onActivarNavegador: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Cada novedad llega como un aviso claro que se va solo', (
    tester,
  ) async {
    await abrir(tester);
    centro.agregar([
      CambioGuia(_guia('T001-7', 'entregado'), '', anterior: EstadoGuia.enRuta),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Guía entregada'), findsOneWidget);
    expect(find.text('T001-7'), findsOneWidget);
    expect(find.text('Oscar Aspur · Ferretería Lima'), findsOneWidget);
    expect(find.byTooltip('1 novedad sin leer'), findsOneWidget);

    // Se va solo pasados unos segundos.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('Guía entregada'), findsNothing);
    // Pero queda en la campana.
    expect(find.byTooltip('1 novedad sin leer'), findsOneWidget);
  });

  testWidgets('Muchas a la vez se resumen y quedan en el historial', (
    tester,
  ) async {
    await abrir(tester);
    centro.agregar([
      CambioGuia(_guia('T1', 'en_ruta'), ''),
      CambioGuia(
        _guia('T2', 'rechazado', motivo: 'Cliente ausente'),
        '',
        anterior: EstadoGuia.enRuta,
      ),
      CambioGuia(_guia('T3', 'en_ruta'), ''),
      CambioGuia(_guia('T4', 'en_ruta'), ''),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Nueva guía registrada'), findsOneWidget);
    expect(find.text('Guía rechazada'), findsOneWidget);
    expect(find.text('Oscar Aspur · Cliente ausente'), findsOneWidget);
    expect(find.text('2 novedades más'), findsOneWidget);

    // Tocar un aviso abre la guía.
    await tester.tap(find.text('Guía rechazada'));
    await tester.pump();
    expect(abiertas, ['T2']);

    await tester.tap(find.byTooltip('4 novedades sin leer'));
    await tester.pumpAndSettle();
    expect(find.text('Novedades'), findsOneWidget);
    expect(find.text('4 nuevas'), findsOneWidget);
    expect(find.textContaining('T4 · '), findsOneWidget);
    // Al abrir el panel quedan leídas.
    expect(centro.noLeidas, 0);
  });
}
