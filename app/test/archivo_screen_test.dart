import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/admin/archivo_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

void main() {
  test('ofrece el mes en curso como tope y los 11 anteriores', () {
    final cortes = cortesDisponibles('2026-02-01');
    expect(cortes.first, '2026-02-01');
    expect(cortes[1], '2026-01-01');
    expect(cortes[2], '2025-12-01');
    expect(cortes, hasLength(12));
    expect(etiquetaCorte('2026-10-01'), 'Hasta septiembre de 2026');
    expect(etiquetaCorte('2026-01-01'), 'Hasta diciembre de 2025');
  });

  testWidgets('simula, y archiva solo después de confirmar con el PIN', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Piero',
      'sesion_rol': 'administrador',
    });
    final pedidos = <http.Request>[];
    var archivado = false;
    final client = MockClient((request) async {
      final ruta = request.url.path;
      if (ruta.endsWith('/archivo')) {
        pedidos.add(request);
        if (request.method == 'POST') {
          archivado = true;
          return http.Response(
            jsonEncode({
              'hasta': '2026-10-01',
              'ejecutar': true,
              'total': 80,
              'porPestana': {'Guías 2026': 80},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'hasta': request.url.queryParameters['hasta'] ?? '2026-10-01',
            'maximo': '2026-10-01',
            'ejecutar': false,
            'total': archivado ? 0 : 80,
            'porPestana': archivado ? {} : {'Guías 2026': 80},
          }),
          200,
        );
      }
      if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
      return http.Response('[]', 200);
    });
    final app = AppState(api: GuiasApi(client: client));
    await app.restaurarSesion();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: const MaterialApp(home: ArchivoScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Se moverían 80 guías cerradas'), findsOneWidget);
    expect(find.text('Hasta septiembre de 2026'), findsOneWidget);
    expect(pedidos.single.method, 'GET');

    // Cancelar el PIN no archiva nada.
    await tester.tap(find.text('Archivar 80 guías'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(pedidos.where((p) => p.method == 'POST'), isEmpty);

    await tester.tap(find.text('Archivar 80 guías'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Archivar'));
    await tester.pumpAndSettle();

    final post = pedidos.firstWhere((p) => p.method == 'POST');
    expect(jsonDecode(post.body), {
      'nombre': 'Piero',
      'pin': '1234',
      'hasta': '2026-10-01',
    });
    expect(find.textContaining('Listo: 80 guías'), findsOneWidget);
    expect(find.text('Nada para archivar'), findsOneWidget);
  });
}
