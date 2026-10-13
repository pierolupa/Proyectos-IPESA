import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/admin/regularizacion_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Regularización: dos pasos y el botón sólo cuando está todo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/transportistas')) {
        return http.Response(
          jsonEncode([
            {'nombre': 'Juan Pérez'},
          ]),
          200,
        );
      }
      return http.Response('[]', 200);
    });
    final appState = AppState(api: GuiasApi(client: client));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: RegularizacionScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transportista'), findsWidgets);
    expect(find.text('1 · Foto de la guía'), findsOneWidget);
    expect(find.text('2 · Foto de la entrega'), findsOneWidget);
    // Sin fotos ni datos, no se puede guardar.
    final boton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Regularizar entrega'),
    );
    expect(boton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
