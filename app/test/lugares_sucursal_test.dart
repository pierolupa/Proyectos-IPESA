import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/admin/admin_dashboard_screen.dart';
import 'package:ipesa_guias/screens/comercial/rastreo_detalle_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

final _salida = DateTime.now().copyWith(hour: 8, minute: 5);
final _cierre = DateTime.now().copyWith(hour: 10, minute: 40);

Map<String, dynamic> _guia(
  String numero,
  String estado, {
  String origen = 'Almacen Ate',
  String destino = 'Almacen Ate',
  bool cerrada = true,
}) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': origen,
  'destino': destino,
  'transportista': 'Victor Torres',
  'destinatario': 'Cliente $numero',
  'fecha_creacion': _salida.toUtc().toIso8601String(),
  'fecha_actualizacion': _cierre.toUtc().toIso8601String(),
  'fecha_cierre': cerrada ? _cierre.toUtc().toIso8601String() : '',
  'corregido_por_admin': false,
};

final _datos = [
  // Recogida y entregada en nuestra sucursal.
  _guia('T028-1', 'entregado', destino: 'ALMACEN ATE'),
  // Salió de una dirección cualquiera y se entregó al cliente.
  _guia(
    'T028-2',
    'entregado',
    origen: 'Av. Nicolás Ayllón 2241, Ate',
    destino: 'Jr. Lima 100',
  ),
  // Salió de la sucursal y sigue en ruta.
  _guia('T028-3', 'en_ruta', destino: 'Jr. Lima 100', cerrada: false),
  _guia('T028-4', 'rechazado', destino: 'Jr. Lima 100'),
];

Future<AppState> _estado() async {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/sucursales')) {
      return http.Response(
        jsonEncode([
          {
            'nombre': 'Almacen Ate',
            'lat': -12.05,
            'lng': -76.95,
            'radio_m': 200,
          },
        ]),
        200,
      );
    }
    return http.Response(jsonEncode(_datos), 200);
  });
  final appState = AppState(api: GuiasApi(client: client));
  await appState.cargarGuias();
  return appState;
}

Future<void> _tarjeta(WidgetTester tester, AppState appState, int i) =>
    tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          home: Scaffold(body: TarjetaGuiaAdmin(guia: appState.guias[i])),
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final hora = DateFormat('dd/MM/yyyy HH:mm').format(_cierre);

  testWidgets('La tarjeta dice dónde se recogió y entregó, con la hora', (
    tester,
  ) async {
    final appState = await _estado();
    final i = appState.guias.indexWhere((g) => g.numeroGuia == 'T028-1');
    await _tarjeta(tester, appState, i);

    expect(find.text('Recogida en Almacen Ate'), findsOneWidget);
    expect(find.text('Entregada en Almacen Ate · $hora'), findsOneWidget);
  });

  testWidgets('Fuera de nuestras sucursales solo va la fecha de entrega', (
    tester,
  ) async {
    final appState = await _estado();
    final i = appState.guias.indexWhere((g) => g.numeroGuia == 'T028-2');
    await _tarjeta(tester, appState, i);

    expect(find.textContaining('Recogida en'), findsNothing);
    expect(find.textContaining('Entregada en'), findsNothing);
    expect(find.text('Entregada $hora'), findsOneWidget);
  });

  testWidgets('En ruta muestra solo la sucursal de recojo; rechazada su hora', (
    tester,
  ) async {
    final appState = await _estado();
    await _tarjeta(
      tester,
      appState,
      appState.guias.indexWhere((g) => g.numeroGuia == 'T028-3'),
    );
    expect(find.text('Recogida en Almacen Ate'), findsOneWidget);
    expect(find.textContaining('Entregada'), findsNothing);

    await _tarjeta(
      tester,
      appState,
      appState.guias.indexWhere((g) => g.numeroGuia == 'T028-4'),
    );
    expect(find.text('Rechazada $hora'), findsOneWidget);
  });

  testWidgets('El rastreo muestra las sucursales de recojo y entrega', (
    tester,
  ) async {
    final appState = await _estado();
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(
          home: RastreoDetalleScreen(numeroGuia: 'T028-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recogida en'), findsOneWidget);
    expect(find.text('Entregada en'), findsOneWidget);
    expect(find.text('Almacen Ate'), findsNWidgets(2));
  });
}
