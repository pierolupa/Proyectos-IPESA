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

  testWidgets('El comercial busca por cliente y abre el detalle', (
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

    expect(find.text('Resultados'), findsOneWidget);
    expect(find.text('Cliente: shougang'), findsOneWidget);
    expect(find.text('1 guía'), findsOneWidget);
    expect(find.text('T033-3455'), findsOneWidget);
    expect(find.text('T028-130133'), findsNothing);

    await tester.tap(find.text('T033-3455'));
    await tester.pumpAndSettle();

    expect(find.text('Guía T033-3455'), findsOneWidget);
    expect(find.text('0188170001'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
  });

  testWidgets('Ver todas lista todo y los chips filtran por estado', (
    tester,
  ) async {
    await _abrirRastreo(tester);

    await tester.ensureVisible(find.text('Ver todas las guías'));
    await tester.tap(find.text('Ver todas las guías'));
    await tester.pumpAndSettle();

    expect(find.text('Todas las guías'), findsOneWidget);
    expect(find.text('3 guías'), findsOneWidget);
    await tester.tap(find.text('Entregado · 1'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 3 guías'), findsOneWidget);
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
