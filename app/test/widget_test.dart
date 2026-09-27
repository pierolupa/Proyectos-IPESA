import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/app.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

http.Response _json(Object body, {int status = 200}) {
  return http.Response(jsonEncode(body), status);
}

/// Cliente simulado que responde POST /auth/login y GET /guias, para
/// probar el flujo completo de login sin red real.
MockClient _clienteConSesion({
  required String nombre,
  required String rol,
  List<Map<String, dynamic>> guias = const [],
}) {
  return MockClient((request) async {
    if (request.method == 'POST' && request.url.path.endsWith('/auth/login')) {
      return _json({'nombre': nombre, 'rol': rol});
    }
    if (request.method == 'GET' && request.url.path.endsWith('/guias')) {
      return _json(guias);
    }
    return http.Response('No mockeado: ${request.method} ${request.url}', 404);
  });
}

void main() {
  // AppState ahora guarda la sesión en SharedPreferences (ver
  // restaurarSesion/_establecerSesion) — sin este mock, getInstance()
  // fallaría en los tests por no tener un canal de plataforma real. Se
  // resetea antes de cada test para que ninguno herede la sesión guardada
  // por el anterior.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Muestra el login como pantalla de inicio', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IpesaGuiasApp());
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Ingresar'), findsOneWidget);
    expect(find.text('Crear una cuenta'), findsOneWidget);
    expect(find.text('¿Eres cliente? Rastrea tu envío'), findsNothing);
  });

  testWidgets('El transportista inicia sesión y ve sus tareas', (
    WidgetTester tester,
  ) async {
    final client = _clienteConSesion(
      nombre: 'Juan Pérez',
      rol: 'transportista',
      guias: [
        {
          'numero_guia': 'IPE-2026-000123',
          'estado': 'en_ruta',
          'tipo_entrega': 'cliente_final',
          'origen': 'Almacén Callao',
          'destino': 'Av. Siempre Viva 742',
          'transportista': 'Juan Pérez',
          'destinatario': 'María Torres',
          'fecha_actualizacion': '2026-01-01T00:00:00.000Z',
          'corregido_por_admin': false,
        },
      ],
    );
    final appState = AppState(api: GuiasApi(client: client));

    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Juan Pérez');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pendientes · 1'), findsOneWidget);
    expect(find.text('IPE-2026-000123'), findsOneWidget);
  });

  testWidgets('El login rechaza credenciales inválidas', (
    WidgetTester tester,
  ) async {
    final client = MockClient(
      (request) async => _json({'error': 'Nombre o PIN incorrecto.'}, status: 401),
    );
    final appState = AppState(api: GuiasApi(client: client));

    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Nadie');
    await tester.enterText(find.byType(TextField).at(1), '0000');
    await tester.tap(find.widgetWithText(FilledButton, 'Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Nombre o PIN incorrecto.'), findsOneWidget);
  });

  testWidgets('Crear cuenta registra al usuario como transportista', (
    WidgetTester tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path.endsWith('/auth/registro')) {
        return _json({
          'nombre': 'Chofer Nuevo',
          'rol': 'transportista',
        }, status: 201);
      }
      if (request.method == 'GET' && request.url.path.endsWith('/guias')) {
        return _json([]);
      }
      return http.Response('No mockeado: ${request.method} ${request.url}', 404);
    });
    final appState = AppState(api: GuiasApi(client: client));

    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Crear cuenta'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Chofer Nuevo');
    await tester.enterText(find.byType(TextField).at(1), '9999');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear cuenta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pendientes'), findsOneWidget);
  });
}
