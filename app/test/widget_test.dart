import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ipesa_guias/app.dart';
import 'package:ipesa_guias/screens/tracking/public_tracking_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

http.Response _json(Object body, {int status = 200}) {
  return http.Response(jsonEncode(body), status);
}

void main() {
  testWidgets('Muestra la pantalla de selección de rol al iniciar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IpesaGuiasApp());

    expect(find.text('IPESA · Control de Guías'), findsOneWidget);
    expect(find.text('Transportista'), findsOneWidget);
    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('Equipo Comercial'), findsOneWidget);
  });

  testWidgets('El transportista ve sus tareas cargadas desde la API', (
    WidgetTester tester,
  ) async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/guias'));
      return _json([
        {
          'numero_guia': 'IPE-2026-000123',
          'estado': 'en_ruta',
          'tipo_entrega': 'cliente_final',
          'origen': 'Almacén Callao',
          'destino': 'Av. Siempre Viva 742',
          'transportista': transportistaActualDemo,
          'destinatario': 'María Torres',
          'fecha_actualizacion': '2026-01-01T00:00:00.000Z',
          'corregido_por_admin': false,
        },
      ]);
    });
    final appState = AppState(api: GuiasApi(client: client));

    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    await tester.tap(find.text('Transportista'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mis tareas'), findsOneWidget);
    expect(find.text('IPE-2026-000123'), findsOneWidget);
  });

  testWidgets('El transportista ve un error si la API falla', (
    WidgetTester tester,
  ) async {
    final client = MockClient((request) async => http.Response('boom', 500));
    final appState = AppState(api: GuiasApi(client: client));

    await tester.pumpWidget(IpesaGuiasApp(appState: appState));
    await tester.tap(find.text('Transportista'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No se pudo cargar'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('El rastreo público valida los últimos 4 dígitos', (
    WidgetTester tester,
  ) async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/guias/rastreo/4821'));
      return _json([
        {'ultimos_cuatro': '4821', 'estado': 'en_ruta', 'destino': 'San Miguel'},
      ]);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PublicTrackingScreen(api: GuiasApi(client: client)),
      ),
    );

    await tester.enterText(find.byType(TextField), '4821');
    await tester.tap(find.text('Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('•••• 4821'), findsOneWidget);
  });
}
