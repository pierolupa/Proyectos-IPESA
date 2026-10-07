import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
