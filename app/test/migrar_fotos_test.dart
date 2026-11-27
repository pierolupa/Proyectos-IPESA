import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/migrar_fotos.dart';

Future<List<http.Request>> _abrir(
  WidgetTester tester,
  List<Map<String, dynamic>> tandas,
) async {
  final pedidos = <http.Request>[];
  var i = 0;
  final client = MockClient((r) async {
    pedidos.add(r);
    final tanda = tandas[i < tandas.length ? i : tandas.length - 1];
    i++;
    return http.Response(jsonEncode(tanda), 200);
  });
  final appState = AppState(api: GuiasApi(client: client));
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => mostrarMigrarFotos(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return pedidos;
}

void main() {
  testWidgets('Pasa las fotos por tandas hasta que no quedan', (tester) async {
    final pedidos = await _abrir(tester, [
      {'movidas': 8, 'pendientes': 4, 'errores': []},
      {'movidas': 4, 'pendientes': 0, 'errores': []},
    ]);
    expect(pedidos, hasLength(2));
    expect(pedidos.first.method, 'POST');
    expect(pedidos.first.url.path, endsWith('/fotos/migrar'));
    expect(find.text('Listo: todas las fotos están en Drive.'), findsOneWidget);
    expect(find.text('12 fotos pasadas a Drive'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Pasar fotos a Drive'), findsNothing);
  });

  testWidgets('Si Vercel tiene bloqueado Blob, se detiene y deja reintentar', (
    tester,
  ) async {
    final pedidos = await _abrir(tester, [
      {
        'movidas': 0,
        'pendientes': 5,
        'errores': [
          {'numero_guia': 'T1', 'error': 'Your store is blocked'},
        ],
      },
    ]);
    expect(pedidos, hasLength(1));
    expect(
      find.textContaining('No se pudieron leer las fotos de Vercel Blob'),
      findsOneWidget,
    );
    expect(find.text('T1: Your store is blocked'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
