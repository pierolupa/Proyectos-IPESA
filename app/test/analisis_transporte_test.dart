import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/admin/dashboard.dart';
import 'package:ipesa_guias/screens/admin/transportistas.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

/// Una guía registrada a las 10:00 de [dia] y cerrada a las 11:30.
Map<String, dynamic> _guia(
  String numero,
  DateTime dia, {
  String transportista = 'Victor Torres',
  String estado = 'entregado',
  String tipo = 'cliente_final',
  String origen = 'Av. Lima 123',
}) {
  String hora(int h, int m) =>
      DateTime(dia.year, dia.month, dia.day, h, m).toUtc().toIso8601String();
  final cerrada = estado != 'en_ruta';
  return {
    'numero_guia': numero,
    'estado': estado,
    'tipo_entrega': tipo,
    'origen': origen,
    'destino': 'Cliente',
    'transportista': transportista,
    'destinatario': 'CLIENTE S.A.C.',
    'fecha_creacion': hora(10, 0),
    'fecha_actualizacion': hora(cerrada ? 11 : 10, cerrada ? 30 : 0),
    'fecha_cierre': cerrada ? hora(11, 30) : null,
    'corregido_por_admin': false,
  };
}

// Semana del lunes 7 al domingo 13 de septiembre de 2026.
final _lunes = DateTime(2026, 9, 7);
final _martes = DateTime(2026, 9, 8);
final _miercoles = DateTime(2026, 9, 9);
final _semana = PeriodoResumen.fechas(_lunes, DateTime(2026, 9, 13));
final _ahora = DateTime(2026, 9, 20, 12);

final _datos = [
  // Victor: 3 entregas en 3 días trabajados (lun, mar, mié).
  _guia('V1', _lunes),
  _guia('V2', _lunes),
  _guia('V3', _martes),
  _guia('V4', _martes, estado: 'rechazado'),
  _guia('V5', _miercoles, estado: 'en_ruta'),
  // Oscar: 3 entregas en 1 día; una por agencia desde Almacen Ate.
  _guia('O1', _lunes, transportista: 'Oscar Aspur'),
  _guia('O2', _lunes, transportista: 'Oscar Aspur'),
  _guia(
    'O3',
    _lunes,
    transportista: 'Oscar Aspur',
    tipo: 'agencia',
    origen: 'Almacen Ate',
  ),
  // La semana anterior: para comparar.
  _guia('P1', DateTime(2026, 8, 31)),
];

List<Guia> get _guias => [for (final j in _datos) Guia.fromJson(j)];

AnalisisTransporte _calcular({
  FiltrosTransporte filtros = const FiltrosTransporte(),
}) => AnalisisTransporte.calcular(
  _guias,
  _semana,
  ahora: _ahora,
  filtros: filtros,
  sucursales: const ['Almacen Ate'],
  conocidos: const ['Victor Torres', 'Oscar Aspur', 'Miguel Aguilar'],
);

void main() {
  test('Promedio diario por transportista y del equipo', () {
    final a = _calcular();
    expect(a.total, 8);
    expect(a.entregadas, 6);
    expect(a.rechazadas, 1);
    expect(a.enRuta, 1);
    expect(a.atrasadas, 1);
    expect(a.diasDelRango, 7);
    // Hubo actividad lunes, martes y miércoles: 6 / 3.
    expect(a.diasConActividad, hasLength(3));
    expect(a.promedioDiario, 2);
    // 3 días de Victor + 1 de Oscar: 6 / 4.
    expect(a.promedioPorTransportista, 1.5);
    expect(a.eficiencia, 0.75);
    // Todas las guías de prueba son del mismo cliente.
    expect(a.clientesAtendidos, 1);
    expect(a.entregadasAnterior, 1);

    final victor = a.filas.firstWhere((f) => f.nombre == 'Victor Torres');
    expect(victor.total, 5);
    expect(victor.entregadas, 3);
    expect(victor.dias, hasLength(3));
    expect(victor.promedioDiario, 1);
    final oscar = a.filas.firstWhere((f) => f.nombre == 'Oscar Aspur');
    expect(oscar.promedioDiario, 3);
  });

  test('Muestra a todos, también a los que no tuvieron guías', () {
    final a = _calcular();
    expect(a.filas.map((f) => f.nombre), [
      'Oscar Aspur',
      'Victor Torres',
      'Miguel Aguilar',
    ]);
    expect(a.activos, 2);
    final miguel = a.filas.last;
    expect(miguel.total, 0);
    expect(miguel.promedioDiario, isNull);
  });

  test('Ordena por promedio, eficiencia o nombre', () {
    final a = _calcular()..ordenar(OrdenTransporte.promedio);
    expect(a.filas.first.nombre, 'Oscar Aspur');
    a.ordenar(OrdenTransporte.eficiencia);
    expect(a.filas.first.nombre, 'Oscar Aspur');
    a.ordenar(OrdenTransporte.nombre);
    expect(a.filas.map((f) => f.nombre).first, 'Miguel Aguilar');
  });

  test('Promedio por día de la semana', () {
    final a = _calcular();
    expect(a.promedioDiaSemana(0), 5); // 5 entregas el único lunes
    expect(a.promedioDiaSemana(1), 1);
    expect(a.promedioDiaSemana(2), 0); // el miércoles nada se entregó
  });

  test('Filtra por transportista, tipo y sucursal', () {
    final soloVictor = _calcular(
      filtros: const FiltrosTransporte(transportistas: {'victor torres'}),
    );
    expect(soloVictor.filas.map((f) => f.nombre), ['Victor Torres']);
    expect(soloVictor.entregadas, 3);

    final agencia = _calcular(
      filtros: const FiltrosTransporte(tipos: {'Agencia'}),
    );
    expect(agencia.entregadas, 1);
    expect(agencia.opcionesTipo, ['Agencia', 'Cliente final']);

    final ate = _calcular(
      filtros: const FiltrosTransporte(sucursales: {'Almacen Ate'}),
    );
    expect(ate.guias.map((g) => g.numeroGuia), ['O3']);
    expect(ate.opcionesSucursal, ['Almacen Ate', 'Fuera de sucursal']);
  });

  test('El promedio por día se redondea siempre hacia arriba', () {
    // 3 entregas en 2 días = 1,5 → 2 (no hay medias guías).
    final a = AnalisisTransporte.calcular(
      [
        for (final j in [
          _guia('L1', _lunes, transportista: 'Lucho Paz'),
          _guia('L2', _lunes, transportista: 'Lucho Paz'),
          _guia('L3', _martes, transportista: 'Lucho Paz'),
        ])
          Guia.fromJson(j),
      ],
      _semana,
      ahora: _ahora,
    );
    expect(a.filas.single.promedioDiario, 1.5);
    final bytes = hojaTransporte(a);
    final texto = String.fromCharCodes(
      bytes.buffer.asUint16List(bytes.offsetInBytes + 2),
    );
    final fila = texto.split('\r\n')[1].split('\t');
    expect(fila[7], '2');
  });

  test('Exporta una fila por transportista, legible en Excel', () {
    final bytes = hojaTransporte(_calcular());
    expect(bytes.take(2), [0xFF, 0xFE]);
    final texto = String.fromCharCodes(
      bytes.buffer.asUint16List(bytes.offsetInBytes + 2),
    );
    final filas = texto.split('\r\n');
    expect(filas, hasLength(4));
    final victor = filas.firstWhere((f) => f.startsWith('Victor')).split('\t');
    expect(victor.sublist(0, 8), [
      'Victor Torres',
      '5',
      '3',
      '1',
      '1',
      '60',
      '3',
      '1',
    ]);
  });

  for (final (pantalla, ancho) in [
    ('computadora', 1400.0),
    ('celular', 400.0),
  ]) {
    testWidgets('Desde Dashboard se abre el análisis por transporte '
        '($pantalla)', (tester) async {
      final hoy = DateTime.now();
      final client = MockClient((request) async {
        final ruta = request.url.path;
        if (ruta.endsWith('/sucursales')) {
          return http.Response(jsonEncode([]), 200);
        }
        if (ruta.endsWith('/transportistas')) {
          return http.Response(
            jsonEncode([
              {'nombre': 'Victor Torres'},
              {'nombre': 'Miguel Aguilar'},
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode([_guia('H1', hoy), _guia('H2', hoy)]),
          200,
        );
      });
      tester.view.physicalSize = Size(ancho, 1600);
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

      // En celular los segmentos se desplazan de lado para llegar a ella.
      await tester.ensureVisible(find.text('Análisis por transporte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Análisis por transporte'));
      await tester.pumpAndSettle();
      expect(find.text('Todos los transportistas'), findsOneWidget);
      expect(find.text('Promedio diario'), findsOneWidget);
      expect(find.text('Exportar a Excel'), findsOneWidget);
      expect(find.text('Victor Torres'), findsOneWidget);
      // Sin guías hoy, pero se lista igual.
      expect(find.text('Miguel Aguilar'), findsOneWidget);
      // Más abajo, el promedio por día de la semana.
      await tester.scrollUntilVisible(
        find.text('Por día de la semana'),
        300,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('Por día de la semana'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
