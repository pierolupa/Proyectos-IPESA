import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/models/filtros_rastreo.dart';
import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/models/rol_usuario.dart';
import 'package:ipesa_guias/screens/comercial/rastreo_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/escena_ruta.dart';

Map<String, dynamic> _guia(
  String numero,
  String estado,
  String cliente, {
  required DateTime salida,
  DateTime? cierre,
  String pedido = '',
  String entrega = '',
}) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': 'Juan Pérez',
  'destinatario': cliente,
  'fecha_creacion': salida.toUtc().toIso8601String(),
  'fecha_actualizacion': (cierre ?? salida).toUtc().toIso8601String(),
  'fecha_cierre': cierre?.toUtc().toIso8601String() ?? '',
  'numero_pedido': pedido,
  'numero_entrega': entrega,
  'corregido_por_admin': false,
};

final _datos = [
  _guia(
    'T028-130133',
    'entregado',
    'Genus SVC S.A.C.',
    salida: DateTime(2026, 9, 1, 9),
    cierre: DateTime(2026, 9, 3, 15),
    pedido: '0188169522',
    entrega: '0080209465',
  ),
  _guia(
    'T033-3455',
    'en_ruta',
    'Shougang Hierro Perú S.A.A.',
    salida: DateTime(2026, 9, 3, 8),
    pedido: '0188170001',
    entrega: '0080210000',
  ),
  _guia(
    'T041-2210',
    'en_proceso_trasbordo',
    'Ferretería Industrial Sur',
    salida: DateTime(2026, 9, 10, 11),
  ),
];

List<Guia> get _guias => [for (final j in _datos) Guia.fromJson(j)];

List<String> _numeros(List<Guia> guias) => [
  for (final g in guias) g.numeroGuia,
];

Future<void> _abrirRastreo(WidgetTester tester) async {
  final client = MockClient(
    (request) async => request.url.path.endsWith('/sucursales')
        ? http.Response('[]', 200)
        : http.Response(jsonEncode(_datos), 200),
  );
  final appState = AppState(api: GuiasApi(client: client));
  await appState.cargarGuias();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MaterialApp(home: RastreoScreen()),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FiltrosRastreo', () {
    test('sin filtros devuelve todas, de la más reciente a la más antigua', () {
      expect(_numeros(const FiltrosRastreo().aplicar(_guias)), [
        'T041-2210',
        'T033-3455',
        'T028-130133',
      ]);
    });

    test('filtra por número de guía, cliente, entrega y pedido', () {
      expect(
        _numeros(const FiltrosRastreo(numeroGuia: '3455').aplicar(_guias)),
        ['T033-3455'],
      );
      expect(_numeros(const FiltrosRastreo(cliente: 'genus').aplicar(_guias)), [
        'T028-130133',
      ]);
      expect(
        _numeros(
          const FiltrosRastreo(numeroEntrega: '0080210000').aplicar(_guias),
        ),
        ['T033-3455'],
      );
      expect(
        _numeros(const FiltrosRastreo(numeroPedido: '8169522').aplicar(_guias)),
        ['T028-130133'],
      );
    });

    test('filtra por rango de fecha de salida (días completos)', () {
      final filtros = FiltrosRastreo(
        desde: DateTime(2026, 9, 1),
        hasta: DateTime(2026, 9, 3),
      );
      expect(_numeros(filtros.aplicar(_guias)), ['T033-3455', 'T028-130133']);
    });

    test('por fecha de entrega solo cuenta guías ya entregadas', () {
      final filtros = FiltrosRastreo(
        campoFecha: CampoFecha.entrega,
        desde: DateTime(2026, 9, 3),
        hasta: DateTime(2026, 9, 3),
      );
      expect(_numeros(filtros.aplicar(_guias)), ['T028-130133']);
    });

    test('filtra por estado agrupado', () {
      expect(
        _numeros(
          const FiltrosRastreo(grupo: GrupoEstado.trasbordo).aplicar(_guias),
        ),
        ['T041-2210'],
      );
    });
  });

  test('el login reconoce el rol comercial', () {
    expect(rolUsuarioDesdeApi('comercial'), RolUsuario.comercial);
  });

  testWidgets('Una sola coincidencia abre la guía de frente, con su sello', (
    tester,
  ) async {
    await _abrirRastreo(tester);

    expect(find.text('Rastrea tus guías'), findsOneWidget);
    expect(find.byType(EscenaRuta), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Cliente'),
      'shougang',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Buscar'));
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    // Sin lista de resultados: directo a la guía.
    expect(find.text('Resultados'), findsNothing);
    expect(find.text('Tu guía'), findsOneWidget);
    expect(find.text('GUÍA DE REMISIÓN'), findsOneWidget);
    expect(find.text('T033-3455'), findsOneWidget);
    expect(find.text('0188170001'), findsOneWidget);
    expect(find.text('EN RUTA'), findsOneWidget);
    // El camión sigue abajo.
    expect(find.byType(EscenaRuta), findsOneWidget);
    // En ruta no hay foto que ver todavía.
    expect(find.text('Ver foto'), findsNothing);
    expect(find.text('Ubicación'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Nueva búsqueda'));
    await tester.pumpAndSettle();
    expect(find.text('Rastrea tus guías'), findsOneWidget);
  });

  testWidgets('Una guía entregada lleva el sello ENTREGADO y su foto', (
    tester,
  ) async {
    await _abrirRastreo(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'N° de guía'),
      '130133',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Buscar'));
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('ENTREGADO'), findsOneWidget);
    expect(find.text('Ver foto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Si nada coincide lo avisa sin salir de la búsqueda', (
    tester,
  ) async {
    await _abrirRastreo(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'N° de guía'),
      'ZZZ-999',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Buscar'));
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No encontramos ninguna guía con esos datos.'),
      findsOneWidget,
    );
    expect(find.text('Tu guía'), findsNothing);
  });

  testWidgets('Sin datos no busca; los chips filtran por estado', (
    tester,
  ) async {
    await _abrirRastreo(tester);

    expect(find.text('Ver todas las guías'), findsNothing);
    expect(find.text('Fechas'), findsNothing);
    await tester.ensureVisible(find.text('Buscar'));
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe al menos un dato para buscar.'), findsOneWidget);
    expect(find.text('Resultados'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'N° pedido'), '0188');
    await tester.pump();
    await tester.ensureVisible(find.text('Buscar'));
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('2 guías'), findsOneWidget);
    await tester.tap(find.text('Entregado · 1'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 guías'), findsOneWidget);
    expect(find.text('T028-130133'), findsOneWidget);
    expect(find.text('T033-3455'), findsNothing);
  });

  testWidgets('El teclado no le quita el foco al campo de búsqueda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _abrirRastreo(tester);

    await tester.tap(find.widgetWithText(TextField, 'N° de guía'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final campo = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextField, 'N° de guía'),
        matching: find.byType(EditableText),
      ),
    );
    expect(campo.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('En pantalla ancha muestra la tabla con todas las columnas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _abrirRastreo(tester);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.widgetWithText(TextField, 'N° de guía'), 'T');
    await tester.pump();
    await tester.ensureVisible(find.text('Buscar'));
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    for (final columna in [
      'N° de guía',
      'Cliente',
      'Pedido',
      'Entrega',
      'Salida',
      'Entregada',
      'Estado',
    ]) {
      expect(find.text(columna), findsWidgets);
    }
    expect(find.text('0188169522'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // La fuente de los tests es más grande que la real (en el navegador entra
  // hasta en 360×640); por eso se prueba con celulares medianos.
  for (final tamano in const [Size(390, 780), Size(412, 820)]) {
    testWidgets('En un celular de $tamano todo entra sin deslizar', (
      tester,
    ) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _abrirRastreo(tester);

      final vertical = tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .where((s) => s.position.axis == Axis.vertical);
      for (final s in vertical) {
        expect(s.position.maxScrollExtent, 0);
      }
      expect(find.byType(EscenaRuta), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('La vista del comercial entra en un celular sin desbordes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _abrirRastreo(tester);
    expect(tester.takeException(), isNull);
  });
}
