import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/admin/admin_dashboard_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

// Hoy a media mañana, para que las guías entren en la línea de tiempo.
final _hoy10 = DateTime.now().copyWith(
  hour: 10,
  minute: 0,
  second: 0,
  millisecond: 0,
  microsecond: 0,
);

Map<String, dynamic> _guia(
  String numero,
  String estado,
  String transportista, {
  int minutos = 0,
}) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': transportista,
  'destinatario': 'Cliente $numero',
  'fecha_actualizacion': _hoy10
      .add(Duration(minutes: minutos))
      .toUtc()
      .toIso8601String(),
  'corregido_por_admin': false,
};

Future<void> _abrirPanel(WidgetTester tester) async {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/sucursales')) {
      return http.Response(
        jsonEncode([
          {
            'nombre': 'Sucursal Arequipa',
            'lat': -16.4,
            'lng': -71.53,
            'radio_m': 200,
          },
        ]),
        200,
      );
    }
    return http.Response(
      jsonEncode([
        _guia('T001-1', 'en_ruta', 'Juan Pérez'),
        _guia('T001-2', 'en_proceso_trasbordo', 'Juan Pérez', minutos: 180),
        _guia('T001-3', 'recepcion_sucursal', 'Ana Díaz', minutos: 60),
        _guia('T001-4', 'entregado', 'Ana Díaz', minutos: 120),
        _guia('T001-5', 'finalizado', 'Ana Díaz', minutos: 240),
      ]),
      200,
    );
  });
  // Pantalla alta, como un celular: con la franja de marcas abajo, en la
  // de 800×600 por defecto no entran todas las guías.
  tester.view.physicalSize = const Size(800, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final appState = AppState(api: GuiasApi(client: client));
  await appState.cargarGuias();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MaterialApp(home: AdminDashboardScreen()),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('El panel solo filtra por En ruta, Trasbordo y Entregado', (
    tester,
  ) async {
    await _abrirPanel(tester);

    expect(find.text('Todas · 5'), findsOneWidget);
    expect(find.text('En ruta · 1'), findsOneWidget);
    expect(find.text('Trasbordo · 2'), findsOneWidget);
    expect(find.text('Entregado · 2'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(4));

    await tester.tap(find.text('Trasbordo · 2'));
    await tester.pumpAndSettle();
    expect(find.text('T001-2'), findsOneWidget);
    expect(find.text('T001-3'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);
  });

  testWidgets('El buscador filtra por cliente o transportista', (
    tester,
  ) async {
    await _abrirPanel(tester);

    await tester.enterText(find.byType(TextField), 'ana');
    await tester.pumpAndSettle();
    expect(find.text('T001-3'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);
  });

  testWidgets('Recorrido muestra a cada transportista en la línea de tiempo', (
    tester,
  ) async {
    await _abrirPanel(tester);

    await tester.tap(find.text('Recorrido'));
    await tester.pumpAndSettle();

    expect(find.text('Recorrido de hoy'), findsOneWidget);
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(find.text('1 en ruta · 1 trasbordo'), findsOneWidget);
    expect(find.text('Ana Díaz'), findsOneWidget);
    expect(find.text('2 entregadas · 1 trasbordo'), findsOneWidget);
    for (final n in ['T001-1', 'T001-2', 'T001-3', 'T001-4', 'T001-5']) {
      expect(find.text(n), findsOneWidget);
    }
  });

  testWidgets('Sucursales lista los perímetros marcados', (tester) async {
    await _abrirPanel(tester);

    await tester.tap(find.text('Sucursales'));
    await tester.pumpAndSettle();

    expect(find.text('Sucursal Arequipa'), findsOneWidget);
    expect(find.text('Perímetro de 200 m'), findsOneWidget);
    expect(find.text('Nueva sucursal'), findsOneWidget);
  });
}
