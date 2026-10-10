import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/admin/dashboard.dart';
import 'package:ipesa_guias/screens/admin/transportistas.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

final _ahora = DateTime.now();
final _hoy = DateTime(_ahora.year, _ahora.month, _ahora.day);
final _soloHoy = PeriodoResumen.fechas(_hoy, _hoy);

Map<String, dynamic> _envio(
  String numero, {
  String cliente = 'CALIZA S.A.C.',
  String transportista = 'Oscar Aspur',
  String origen = 'Almacen Ate',
  String agencia = 'SHALOM EMPRESARIAL S.A.C.',
  String comprobante = '',
  Object? monto,
  int dias = 0,
  String tipo = 'agencia',
  bool conComprobante = true,
}) {
  final fecha = _hoy
      .add(const Duration(hours: 10))
      .subtract(Duration(days: dias))
      .toUtc()
      .toIso8601String();
  return {
    'numero_guia': numero,
    'estado': 'finalizado',
    'tipo_entrega': tipo,
    'origen': origen,
    'destino': 'Agencia',
    'transportista': transportista,
    'destinatario': cliente,
    'fecha_creacion': fecha,
    'fecha_actualizacion': fecha,
    'fecha_cierre': fecha,
    'corregido_por_admin': false,
    if (conComprobante) ...{
      'agencia_razon_social': agencia,
      'agencia_comprobante': comprobante,
      'agencia_monto': monto,
    },
  };
}

List<Guia> _guias(List<Map<String, dynamic>> json) => [
  for (final j in json) Guia.fromJson(j),
];

final _datos = [
  // Un comprobante para dos guías de clientes distintos.
  _envio('T1', comprobante: 'B001-1', monto: 50),
  _envio('T2', cliente: 'UNIMAQ S.A.', comprobante: 'B001-1', monto: 50),
  _envio('T3', comprobante: 'B001-2', monto: 30),
  _envio(
    'T4',
    agencia: 'TRANSAMAZONICA CARGO',
    comprobante: 'F002-9',
    monto: 10,
    transportista: 'Jaime Bravo',
    origen: 'Av. Lima 123',
  ),
  // Marcada como agencia, sin comprobante leído.
  _envio('T5', conComprobante: false),
  // No es de agencia: cuenta solo en el total del periodo.
  _envio('T6', tipo: 'cliente_final', conComprobante: false),
  // Ayer: el periodo anterior.
  _envio('T7', comprobante: 'B001-0', monto: 40, dias: 1),
];

AnalisisAgencias _calcular(
  List<Map<String, dynamic>> json, {
  FiltrosAgencias filtros = const FiltrosAgencias(),
}) => AnalisisAgencias.calcular(
  _guias(json),
  _soloHoy,
  ahora: _ahora,
  filtros: filtros,
  sucursales: const ['Almacen Ate'],
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Cuenta cada comprobante una vez aunque cubra varias guías', () {
    final a = _calcular(_datos);
    expect(a.guiasDelPeriodo, 6);
    expect(a.guias, hasLength(5));
    expect(a.comprobantes, hasLength(3));
    expect(a.guiasConComprobante, 4);
    expect(a.gasto, 90);
    expect(a.porComprobante, 30);
    expect(a.porGuia, 22.5);
    expect(a.guiasPorComprobante, closeTo(1.33, 0.01));
    expect(a.gastoAnterior, 40);

    final shalom = a.agencias.first;
    expect(shalom.nombre, 'SHALOM EMPRESARIAL S.A.C.');
    expect(
      (shalom.guias.length, shalom.comprobantes.length, shalom.costo),
      (3, 2, 80),
    );
    // El comprobante de 50 se reparte entre CALIZA y UNIMAQ.
    final caliza = a.clientes.firstWhere((f) => f.nombre == 'CALIZA S.A.C.');
    expect(caliza.costo, 65); // 25 (mitad de B001-1) + 30 + 10
    expect(a.clientes.firstWhere((f) => f.nombre == 'UNIMAQ S.A.').costo, 25);
    // Sucursal de salida: solo las marcadas.
    expect(a.salidas.map((f) => f.nombre), ['Almacen Ate', fueraDeSucursal]);
    expect(a.sinComprobante.map((g) => g.numeroGuia), ['T5']);
  });

  test('Los filtros recortan y reparten el monto del comprobante', () {
    final porCliente = _calcular(
      _datos,
      filtros: const FiltrosAgencias(clientes: {'UNIMAQ S.A.'}),
    );
    expect(porCliente.guias.map((g) => g.numeroGuia), ['T2']);
    expect(porCliente.comprobantes.single.guias, hasLength(1));
    expect(porCliente.comprobantes.single.todas, hasLength(2));
    expect(porCliente.gasto, 25);

    final porAgencia = _calcular(
      _datos,
      filtros: const FiltrosAgencias(agencias: {'TRANSAMAZONICA CARGO'}),
    );
    expect(porAgencia.gasto, 10);
    expect(porAgencia.sinComprobante, isEmpty);
    expect(porAgencia.opcionesAgencia, [
      'SHALOM EMPRESARIAL S.A.C.',
      'TRANSAMAZONICA CARGO',
    ]);
  });

  test('Avisa montos vacíos, raros o distintos en un mismo comprobante', () {
    final a = _calcular([
      _envio('A1', comprobante: 'B1', monto: 20),
      _envio('A2', comprobante: 'B2', monto: 22),
      _envio('A3', comprobante: 'B3', monto: 25),
      _envio('A4', comprobante: 'B4', monto: 90),
      _envio('A5', comprobante: 'B5', monto: 0),
      _envio('A6', comprobante: 'B6', monto: 15),
      _envio('A7', comprobante: 'B6', monto: 18),
    ]);
    expect(a.sinMonto.map((c) => c.numero), ['B5']);
    expect(a.montoInusual.map((c) => c.numero), ['B4']);
    expect(a.montosDistintos.map((c) => c.numero), ['B6']);
    expect(a.porRevisar, 3);
  });

  test('Exporta un comprobante por fila, legible en Excel', () {
    final bytes = hojaComprobantes(_calcular(_datos));
    expect(bytes.take(2), [0xFF, 0xFE]);
    final texto = String.fromCharCodes(
      bytes.buffer.asUint16List(bytes.offsetInBytes + 2),
    );
    final filas = texto.split('\r\n');
    expect(filas, hasLength(4));
    expect(filas.first.split('\t').take(5), [
      'Fecha',
      'Agencia',
      'RUC',
      'N° comprobante',
      'Monto (S/)',
    ]);
    final b1 = filas.firstWhere((f) => f.contains('B001-1')).split('\t');
    expect(b1[4], '50.00');
    expect(b1[5], '2');
    expect(b1[6], 'T1, T2');
    expect(b1[9], 'Almacen Ate');
  });

  testWidgets('Desde Dashboard se abre el análisis y se filtra por agencia', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/sucursales')) {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response(jsonEncode(_datos), 200);
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cargarGuias();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: Scaffold(body: PestanaDashboard())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Análisis de agencias'));
    await tester.pumpAndSettle();
    expect(find.text('Gasto en agencias'), findsOneWidget);
    expect(find.text('Comprobantes'), findsWidgets);
    expect(find.text('Por revisar'), findsWidgets);
    expect(find.text('Sin comprobante leído'), findsOneWidget);
    expect(find.text('Exportar a Excel'), findsOneWidget);
    for (final rapido in ['Hoy', '7 días', 'Este mes']) {
      expect(find.text(rapido), findsOneWidget);
    }

    // Tocar una agencia del ranking filtra todo por ella.
    await tester.tap(find.text('TRANSAMAZONICA CARGO').first);
    await tester.pumpAndSettle();
    expect(find.text('Agencia: '), findsOneWidget);
    expect(find.text('Limpiar'), findsOneWidget);
    expect(find.text('S/ 10.00'), findsWidgets);
    expect(find.text('Sin comprobante leído'), findsNothing);

    await tester.tap(find.text('Limpiar'));
    await tester.pumpAndSettle();
    expect(find.text('Limpiar'), findsNothing);

    // Y se vuelve al resumen general.
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('Gasto en agencias'), findsNothing);
    expect(find.text('Guías del periodo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('General y Análisis muestran lo mismo y comparten el periodo', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/sucursales')) {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response(jsonEncode(_datos), 200);
    });
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cargarGuias();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: Scaffold(body: PestanaDashboard())),
      ),
    );
    await tester.pumpAndSettle();

    // Hoy: SHALOM suma S/ 80 (el comprobante de ayer no entra).
    expect(find.text('3 guías · 2 comprobantes'), findsOneWidget);
    expect(find.text('S/ 80.00'), findsOneWidget);

    await tester.tap(find.text('Ver análisis de agencias'));
    await tester.pumpAndSettle();
    expect(find.text('Gasto en agencias'), findsOneWidget);
    expect(find.text('S/ 80.00'), findsWidgets);

    // Cambiar a 7 días en el análisis también cambia el resumen General.
    await tester.tap(find.text('7 días'));
    await tester.pumpAndSettle();
    expect(find.text('S/ 120.00'), findsWidgets);
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    expect(find.text('4 guías · 3 comprobantes'), findsOneWidget);
    expect(find.text('S/ 120.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
