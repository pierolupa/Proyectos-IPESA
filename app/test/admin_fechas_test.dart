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

Map<String, dynamic> _guia(String numero, DateTime creada) => {
  'numero_guia': numero,
  'estado': 'entregado',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén',
  'destino': 'Destino',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente $numero',
  'fecha_creacion': creada.toUtc().toIso8601String(),
  'fecha_actualizacion': creada.toUtc().toIso8601String(),
  'corregido_por_admin': false,
};

void main() {
  testWidgets('Guías muestra las de hoy; 7 días muestra la semana', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final ahora = DateTime.now();
    final client = MockClient(
      (r) async => r.url.path.endsWith('/sucursales')
          ? http.Response('[]', 200)
          : http.Response(
              jsonEncode([
                _guia('HOY-1', ahora),
                _guia('HACE-3', ahora.subtract(const Duration(days: 3))),
                _guia('HACE-20', ahora.subtract(const Duration(days: 20))),
              ]),
              200,
            ),
    );
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cargarGuias();
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todas · 1'), findsOneWidget);
    expect(find.text('HOY-1'), findsOneWidget);
    expect(find.text('HACE-3'), findsNothing);

    await tester.tap(find.text('7 días'));
    await tester.pumpAndSettle();
    expect(find.text('Todas · 2'), findsOneWidget);
    expect(find.text('HACE-3'), findsOneWidget);
    expect(find.text('HACE-20'), findsNothing);
  });
}
