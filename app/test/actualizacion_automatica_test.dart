import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/admin/admin_dashboard_screen.dart';
import 'package:ipesa_guias/screens/transportista/task_list_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

Map<String, dynamic> _guia(String numero, String estado) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente $numero',
  'fecha_actualizacion': '2026-09-01T15:30:00.000Z',
  'corregido_por_admin': false,
};

/// Cliente cuya lista de guías se puede cambiar entre llamadas, como si un
/// transportista hiciera algo desde otro celular.
class _Servidor {
  List<Map<String, dynamic>> guias;
  _Servidor(this.guias);

  MockClient get client => MockClient((request) async {
    if (request.url.path.endsWith('/sucursales')) {
      return http.Response('[]', 200);
    }
    return http.Response(jsonEncode(guias), 200);
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('El admin ve la entrega sin actualizar y recibe un aviso', (
    tester,
  ) async {
    final servidor = _Servidor([_guia('T001-1', 'en_ruta')]);
    final appState = AppState(api: GuiasApi(client: servidor.client));
    await appState.cargarGuias();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    expect(find.text('En ruta (1)'), findsOneWidget);

    servidor.guias = [
      _guia('T001-1', 'entregado'),
      _guia('T001-2', 'en_ruta'),
    ];
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();

    expect(find.text('Entregado (1)'), findsOneWidget);
    expect(find.textContaining('Juan Pérez entregó la guía T001-1.'), findsOneWidget);
    expect(find.textContaining('Juan Pérez registró la guía T001-2'), findsOneWidget);
  });

  testWidgets('Las tareas entregadas desaparecen de la lista del transportista', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    final servidor = _Servidor([
      _guia('T001-1', 'en_ruta'),
      _guia('T001-2', 'en_ruta'),
    ]);
    final appState = AppState(api: GuiasApi(client: servidor.client));
    await appState.restaurarSesion();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: TaskListScreen()),
      ),
    );
    expect(find.text('T001-1'), findsOneWidget);

    servidor.guias = [
      _guia('T001-1', 'entregado'),
      _guia('T001-2', 'en_ruta'),
    ];
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();

    expect(find.text('T001-1'), findsNothing);
    expect(find.text('T001-2'), findsOneWidget);
  });
}
