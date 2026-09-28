import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/transportista/entrega_flow_screen.dart';
import 'package:ipesa_guias/screens/transportista/task_list_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

final _hoy = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _guia(
  String numero,
  String cliente, {
  String estado = 'en_ruta',
  String destino = 'Av. Principal 123',
}) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Lurín',
  'destino': destino,
  'transportista': 'Oscar Aspur',
  'destinatario': cliente,
  'fecha_creacion': _hoy,
  'fecha_actualizacion': _hoy,
  'corregido_por_admin': false,
};

Future<void> _abrir(
  WidgetTester tester,
  List<Map<String, dynamic>> guias,
) async {
  SharedPreferences.setMockInitialValues({
    'sesion_nombre': 'Oscar Aspur',
    'sesion_rol': 'transportista',
  });
  final client = MockClient(
    (r) async => r.url.path.endsWith('/sucursales')
        ? http.Response('[]', 200)
        : http.Response(jsonEncode(guias), 200),
  );
  final appState = AppState(api: GuiasApi(client: client));
  await appState.restaurarSesion();
  await appState.cargarGuias();
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: const MaterialApp(home: TaskListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('El buscador filtra por guía, cliente o destino', (tester) async {
    await _abrir(tester, [
      _guia('T001-94912', 'TRANSPORTES SIN FRONTERAS'),
      _guia('T001-94855', 'CORPORACION LOGISTICA SINCHE', destino: 'Ate'),
    ]);

    expect(find.text('Oscar Aspur'), findsOneWidget);
    expect(find.text('Pendientes · 2'), findsOneWidget);
    expect(find.text('T001-94912'), findsOneWidget);
    expect(find.text('T001-94855'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'sinche');
    await tester.pumpAndSettle();
    expect(find.text('T001-94912'), findsNothing);
    expect(find.text('T001-94855'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '94912');
    await tester.pumpAndSettle();
    expect(find.text('T001-94912'), findsOneWidget);
    expect(find.text('T001-94855'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nada');
    await tester.pumpAndSettle();
    expect(find.textContaining('Ninguna guía coincide'), findsOneWidget);

    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pumpAndSettle();
    expect(find.text('T001-94855'), findsOneWidget);
  });

  testWidgets('Sin pendientes aparece "Ruta completada"', (tester) async {
    await _abrir(tester, [
      _guia('T1', 'Cliente A', estado: 'entregado'),
      _guia('T2', 'Cliente B', estado: 'entregado'),
    ]);
    expect(find.text('RUTA COMPLETADA'), findsOneWidget);
    expect(find.text('No tienes más tareas pendientes'), findsOneWidget);
    expect(find.textContaining('Entregaste 2 guías hoy'), findsOneWidget);
    // "Nueva guía" queda en la tarjeta (sin el botón flotante repetido).
    expect(find.text('Nueva guía'), findsOneWidget);
    // No hay nada que buscar.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('Entregar y el menú de opciones están en la tarjeta', (
    tester,
  ) async {
    await _abrir(tester, [_guia('T1', 'Cliente A')]);

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar tipo de entrega'), findsOneWidget);
    expect(find.text('Rechazar tarea'), findsOneWidget);
    expect(find.text('Eliminar tarea'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entregar'));
    await tester.pumpAndSettle();
    final entrega = tester.widget<EntregaFlowScreen>(
      find.byType(EntregaFlowScreen),
    );
    // Desde la lista, al entregar solo se cierra esa pantalla.
    expect(entrega.desdeDetalle, isFalse);
  });
}
