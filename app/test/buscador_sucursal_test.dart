import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:ipesa_guias/screens/admin/sucursal_edit_screen.dart';
import 'package:ipesa_guias/services/buscador_lugares.dart';
import 'package:ipesa_guias/state/app_state.dart';

void main() {
  testWidgets('Buscar una tienda centra el perímetro y llena el nombre', (
    tester,
  ) async {
    Uri? consultada;
    final buscador = BuscadorLugares(
      client: MockClient((request) async {
        consultada = request.url;
        return http.Response(
          jsonEncode([
            {
              'name': 'Plaza Vea Arequipa',
              'display_name': 'Plaza Vea Arequipa, Av. Ejército, Arequipa, Perú',
              'lat': '-16.3920',
              'lon': '-71.5470',
            },
          ]),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(home: SucursalEditScreen(buscador: buscador)),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar tienda o dirección'),
      'Plaza Vea Arequipa',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(consultada!.host, 'nominatim.openstreetmap.org');
    expect(consultada!.queryParameters['q'], 'Plaza Vea Arequipa');
    expect(consultada!.queryParameters['countrycodes'], 'pe');

    await tester.tap(find.text('Plaza Vea Arequipa').last);
    await tester.pumpAndSettle();

    final nombre = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Nombre de la sucursal'),
    );
    expect(nombre.controller!.text, 'Plaza Vea Arequipa');
    expect(
      find.text('Toca el mapa para mover el centro del perímetro.'),
      findsOneWidget,
    );
  });
}
