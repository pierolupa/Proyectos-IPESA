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

Map<String, dynamic> _guia(String numero, String estado, String transportista) =>
    {
      'numero_guia': numero,
      'estado': estado,
      'tipo_entrega': 'cliente_final',
      'origen': 'Almacén Callao',
      'destino': 'Av. Principal 123',
      'transportista': transportista,
      'destinatario': 'Cliente $numero',
      'fecha_actualizacion': '2026-09-01T15:30:00.000Z',
      'corregido_por_admin': false,
    };

Future<void> _abrirPanel(WidgetTester tester) async {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/sucursales')) {
      return http.Response(
        jsonEncode([
          {'nombre': 'Sucursal Arequipa', 'lat': -16.4, 'lng': -71.53, 'radio_m': 200},
        ]),
        200,
      );
    }
    return http.Response(
      jsonEncode([
        _guia('T001-1', 'en_ruta', 'Juan Pérez'),
        _guia('T001-2', 'en_proceso_trasbordo', 'Juan Pérez'),
        _guia('T001-3', 'recepcion_sucursal', 'Ana Díaz'),
        _guia('T001-4', 'entregado', 'Ana Díaz'),
        _guia('T001-5', 'finalizado', 'Ana Díaz'),
      ]),
      200,
    );
  });
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

    expect(find.text('Todas (5)'), findsOneWidget);
    expect(find.text('En ruta (1)'), findsOneWidget);
    expect(find.text('Trasbordo (2)'), findsOneWidget);
    expect(find.text('Entregado (2)'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(4));

    await tester.tap(find.text('Trasbordo (2)'));
    await tester.pumpAndSettle();
    expect(find.text('T001-2'), findsOneWidget);
    expect(find.text('T001-3'), findsOneWidget);
    expect(find.text('T001-1'), findsNothing);
  });

  testWidgets('Tareas agrupa las guías por transportista', (tester) async {
    await _abrirPanel(tester);

    await tester.tap(find.text('Tareas'));
    await tester.pumpAndSettle();

    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(
      find.text('2 tareas · 1 en ruta · 1 trasbordo · 0 entregado'),
      findsOneWidget,
    );
    expect(find.text('Ana Díaz'), findsOneWidget);
    expect(
      find.text('3 tareas · 0 en ruta · 1 trasbordo · 2 entregado'),
      findsOneWidget,
    );
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
