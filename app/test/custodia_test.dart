import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/transportista/guia_detail_screen.dart';
import 'package:ipesa_guias/screens/transportista/task_list_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/estado_badge.dart';

const _creada = '2026-10-19T13:00:00.000Z';
const _custodia = '2026-10-19T23:30:00.000Z';

Map<String, dynamic> _guia({
  String estado = 'en_ruta',
  String custodia = '',
  String tipo = 'cliente_final',
}) => {
  'numero_guia': 'T001-700',
  'estado': estado,
  'tipo_entrega': tipo,
  'origen': 'Almacén Lurín',
  'destino': 'Av. Principal 123',
  'transportista': 'Oscar Aspur',
  'destinatario': 'Ferretería Lima',
  'fecha_creacion': _creada,
  'fecha_actualizacion': _creada,
  'corregido_por_admin': false,
  'custodia_desde': custodia,
};

/// Servidor falso: guarda los pedidos y responde como el backend.
class _Servidor {
  _Servidor(this.guia);

  Map<String, dynamic> guia;
  final pedidos = <http.Request>[];

  late final client = MockClient((r) async {
    pedidos.add(r);
    final ruta = r.url.path;
    if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
    if (r.method == 'GET') return http.Response(jsonEncode([guia]), 200);
    if (ruta.endsWith('/custodia')) {
      guia = {...guia, 'custodia_desde': r.method == 'POST' ? _custodia : ''};
    }
    return http.Response(jsonEncode(guia), 200);
  });
}

Future<void> _abrir(
  WidgetTester tester,
  _Servidor servidor, {
  Widget pantalla = const GuiaDetailScreen(numeroGuia: 'T001-700'),
}) async {
  SharedPreferences.setMockInitialValues({
    'sesion_nombre': 'Oscar Aspur',
    'sesion_rol': 'transportista',
  });
  final appState = AppState(api: GuiasApi(client: servidor.client));
  await appState.restaurarSesion();
  await appState.cargarGuias();
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: appState,
      child: MaterialApp(home: pantalla),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Lee la custodia y solo cuenta mientras sigue en ruta', () {
    final enRuta = Guia.fromJson(_guia(custodia: _custodia));
    expect(enRuta.custodiaDesde, DateTime.parse(_custodia));
    expect(enRuta.enCustodia, isTrue);
    expect(Guia.fromJson(_guia()).enCustodia, isFalse);
    // Ya entregada, la custodia queda solo como historia.
    final entregada = Guia.fromJson(
      _guia(estado: 'entregado', custodia: _custodia),
    );
    expect(entregada.enCustodia, isFalse);
  });

  testWidgets('El badge dice "En custodia"', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EstadoBadge(estado: EstadoGuia.enRuta, custodia: true),
        ),
      ),
    );
    expect(find.text('En custodia'), findsOneWidget);
  });

  testWidgets('El transportista la deja en custodia y luego la quita', (
    tester,
  ) async {
    final servidor = _Servidor(_guia());
    await _abrir(tester, servidor);

    await tester.tap(find.text('Dejar en custodia'));
    await tester.pumpAndSettle();
    // Confirma en el diálogo.
    await tester.tap(find.widgetWithText(FilledButton, 'Dejar en custodia'));
    await tester.pumpAndSettle();

    final pedido = servidor.pedidos.last;
    expect(pedido.method, 'POST');
    expect(pedido.url.path, endsWith('/guias/T001-700/custodia'));
    expect(jsonDecode(pedido.body), {'fechaCreacion': _creada});
    // Sigue en ruta: se entrega con el flujo de siempre.
    expect(find.text('Quitar custodia'), findsOneWidget);
    expect(find.text('Registrar entrega'), findsOneWidget);
    expect(find.text('En custodia'), findsWidgets);

    await tester.tap(find.text('Quitar custodia'));
    await tester.pumpAndSettle();
    expect(servidor.pedidos.last.method, 'DELETE');
    expect(servidor.pedidos.last.url.queryParameters['fechaCreacion'], _creada);
    expect(find.text('Dejar en custodia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Un traslado entre sucursales no ofrece custodia', (
    tester,
  ) async {
    await _abrir(tester, _Servidor(_guia(tipo: 'entre_sucursales')));
    expect(find.text('Dejar en custodia'), findsNothing);
  });

  testWidgets('Desde el menú ⋯ de la tarjeta se deja en custodia', (
    tester,
  ) async {
    final servidor = _Servidor(_guia());
    await _abrir(tester, servidor, pantalla: const TaskListScreen());

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Rechazar tarea'), findsOneWidget);
    await tester.tap(find.text('Dejar en custodia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Dejar en custodia'));
    await tester.pumpAndSettle();

    expect(servidor.pedidos.last.method, 'POST');
    expect(servidor.pedidos.last.url.path, endsWith('/custodia'));
    expect(find.text('En custodia'), findsOneWidget);

    // Ya en custodia, el menú ofrece quitarla.
    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Quitar custodia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
