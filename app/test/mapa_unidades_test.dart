import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/admin/admin_dashboard_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

final _hoy = DateTime.now().copyWith(hour: 9, minute: 0);

Guia _guia(String numero, String transportista, int minutos, double lat) =>
    Guia.fromJson({
      'numero_guia': numero,
      'estado': 'en_ruta',
      'tipo_entrega': 'cliente_final',
      'origen': 'Almacén Callao',
      'destino': 'Lima',
      'transportista': transportista,
      'destinatario': 'Cliente $numero',
      'fecha_actualizacion': _hoy
          .add(Duration(minutes: minutos))
          .toUtc()
          .toIso8601String(),
      'corregido_por_admin': false,
      'geo_lat': lat,
      'geo_lng': -77.04,
    });

Future<void> _mapa(
  WidgetTester tester,
  List<Guia> guias, {
  bool recorrido = false,
}) async {
  final client = MockClient((_) async => http.Response(jsonEncode([]), 200));
  final appState = AppState(api: GuiasApi(client: client));
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        home: Scaffold(
          body: MapaGuias(guias: guias, recorrido: recorrido),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final guias = [
    _guia('T1', 'Oscar Aspur', 0, -12.00),
    _guia('T2', 'Oscar Aspur', 90, -12.10),
    _guia('T3', 'Jaime Bravo', 30, -12.05),
  ];

  testWidgets('Cada transportista aparece una vez, con su nombre', (
    tester,
  ) async {
    await _mapa(tester, guias);
    expect(find.text('Oscar Aspur'), findsOneWidget);
    expect(find.text('Jaime Bravo'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_rounded), findsNWidgets(2));
    expect(find.text('Unidad (última posición)'), findsOneWidget);
    // Con la fecha y hora de su última posición (T2 para Oscar).
    expect(
      find.text(
        DateFormat('dd/MM/yyyy HH:mm')
            .format(_hoy.add(const Duration(minutes: 90))),
      ),
      findsOneWidget,
    );
  });

  testWidgets('La unidad está en el punto de su último movimiento', (
    tester,
  ) async {
    await _mapa(tester, guias);
    // De sus dos guías, la unidad de Oscar va en la de T2 (la más reciente).
    final mensajes = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((t) => t.message ?? '')
        .where((m) => m.startsWith('Oscar Aspur'));
    expect(mensajes.single, contains('T2'));
  });

  testWidgets('En el recorrido de un transportista no se repite su nombre', (
    tester,
  ) async {
    await _mapa(tester, guias.take(2).toList(), recorrido: true);
    expect(find.text('Oscar Aspur'), findsNothing);
  });

  Guia entregada({required double geoLat, String origen = 'Almacén Callao'}) =>
      Guia.fromJson({
        'numero_guia': 'T9',
        'estado': 'entregado',
        'tipo_entrega': 'cliente_final',
        'origen': origen,
        'destino': 'Lima',
        'transportista': 'Oscar Aspur',
        'destinatario': 'Cliente T9',
        'fecha_creacion': _hoy.toUtc().toIso8601String(),
        'fecha_actualizacion': _hoy
            .add(const Duration(hours: 2))
            .toUtc()
            .toIso8601String(),
        'fecha_cierre': _hoy
            .add(const Duration(hours: 2))
            .toUtc()
            .toIso8601String(),
        'corregido_por_admin': false,
        'geo_lat': geoLat,
        'geo_lng': -77.04,
        'cierre_lat': -12.20,
        'cierre_lng': -77.04,
      });

  testWidgets(
    'Una guía entregada muestra dónde se recogió y dónde se entregó',
    (tester) async {
      await _mapa(tester, [entregada(geoLat: -12.00)], recorrido: true);
      final mensajes = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '')
          .toList();
      expect(mensajes.where((m) => m.contains('recogida')), hasLength(1));
      expect(find.text('Recogida'), findsOneWidget);
      // El recorrido va del punto de recojo al de entrega.
      final linea = tester
          .widget<PolylineLayer>(find.byType(PolylineLayer))
          .polylines
          .single;
      expect(linea.points.first.latitude, -12.00);
      expect(linea.points.last.latitude, -12.20);
    },
  );

  testWidgets('Sin punto de recojo distinto ni sucursal, no se inventa uno', (
    tester,
  ) async {
    // Entregada antes del cambio: geo_* quedó igual al punto de entrega.
    await _mapa(tester, [entregada(geoLat: -12.20)], recorrido: true);
    expect(find.text('Recogida'), findsNothing);
    expect(find.byType(PolylineLayer), findsNothing);
  });
}
