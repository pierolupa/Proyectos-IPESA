import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/models/guia.dart';
import 'package:ipesa_guias/screens/transportista/task_list_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/avisos_novedades.dart';

final _hoy = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _guia({
  String transportista = 'Diego Pillaca',
  String transbordoEstado = '',
  String transbordoA = '',
  String transbordoDe = '',
}) => {
  'numero_guia': 'T035-7954',
  'estado': 'en_ruta',
  'tipo_entrega': 'cliente_final',
  'origen': 'Trp Callao',
  'destino': 'Av. Confraternidad Internacional, Huaraz',
  'transportista': transportista,
  'destinatario': 'MULTISERVICIOS E IMPORTACIONES',
  'fecha_creacion': _hoy,
  'fecha_actualizacion': _hoy,
  'corregido_por_admin': false,
  'transbordo_estado': transbordoEstado,
  'transbordo_a': transbordoA,
  'transbordo_de': transbordoDe,
};

/// Abre "Mis tareas" como [yo]; [servidor] responde las rutas que importan.
Future<List<http.Request>> _abrir(
  WidgetTester tester, {
  required String yo,
  required List<Map<String, dynamic>> guias,
  required Map<String, dynamic> Function(http.Request) respuesta,
}) async {
  SharedPreferences.setMockInitialValues({
    'sesion_nombre': yo,
    'sesion_rol': 'transportista',
  });
  final pedidos = <http.Request>[];
  final client = MockClient((r) async {
    pedidos.add(r);
    final ruta = r.url.path;
    if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
    if (ruta.endsWith('/transportistas')) {
      return http.Response(
        jsonEncode([
          {'nombre': 'Diego Pillaca'},
          {'nombre': 'Juan Pérez'},
        ]),
        200,
      );
    }
    if (ruta.contains('/transbordo')) {
      return http.Response(jsonEncode(respuesta(r)), 200);
    }
    return http.Response(jsonEncode(guias), 200);
  });
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
  return pedidos;
}

void main() {
  testWidgets('Quien envía elige a otro transportista y queda esperando', (
    tester,
  ) async {
    final pedidos = await _abrir(
      tester,
      yo: 'Diego Pillaca',
      guias: [_guia()],
      respuesta: (_) =>
          _guia(transbordoEstado: 'pendiente', transbordoA: 'Juan Pérez'),
    );

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transbordo'));
    await tester.pumpAndSettle();

    // La lista no lo incluye a él mismo.
    expect(find.text('Juan Pérez'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Diego Pillaca'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Juan Pérez'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar a Juan Pérez'));
    await tester.pumpAndSettle();

    final envio = pedidos.lastWhere((r) => r.url.path.endsWith('/transbordo'));
    expect(jsonDecode(envio.body), containsPair('a', 'Juan Pérez'));
    expect(jsonDecode(envio.body), containsPair('de', 'Diego Pillaca'));
    // Sigue en su lista, marcada.
    expect(find.text('T035-7954'), findsOneWidget);
    expect(
      find.text('Esperando que Juan Pérez acepte el transbordo'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    expect(find.text('Cancelar transbordo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quien recibe ve el anuncio y al aceptar la tarea pasa a ser '
      'suya', (tester) async {
    final pedidos = await _abrir(
      tester,
      yo: 'Juan Pérez',
      guias: [_guia(transbordoEstado: 'pendiente', transbordoA: 'Juan Pérez')],
      respuesta: (_) => _guia(
        transportista: 'Juan Pérez',
        transbordoEstado: 'aceptado',
        transbordoDe: 'Diego Pillaca',
      ),
    );

    // El anuncio al entrar.
    expect(find.text('Diego Pillaca te pasa una tarea'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar').last);
    await tester.pumpAndSettle();

    final respuesta = pedidos.lastWhere(
      (r) => r.url.path.endsWith('/transbordo/respuesta'),
    );
    expect(jsonDecode(respuesta.body), containsPair('acepta', true));
    expect(jsonDecode(respuesta.body), containsPair('quien', 'Juan Pérez'));
    expect(find.text('Pendientes · 1'), findsOneWidget);
    expect(find.text('Te la pasó Diego Pillaca'), findsOneWidget);
    expect(find.text('Te pasaron 1 tarea'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quien recibe puede rechazarla desde la tarjeta', (tester) async {
    await _abrir(
      tester,
      yo: 'Juan Pérez',
      guias: [_guia(transbordoEstado: 'pendiente', transbordoA: 'Juan Pérez')],
      respuesta: (_) =>
          _guia(transbordoEstado: 'rechazado', transbordoA: 'Juan Pérez'),
    );
    await tester.tap(find.text('Ver después'));
    await tester.pumpAndSettle();

    expect(find.text('Te pasaron 1 tarea'), findsOneWidget);
    expect(find.text('Diego Pillaca te pasa esta tarea'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Rechazar'));
    await tester.pumpAndSettle();

    expect(find.text('Te pasaron 1 tarea'), findsNothing);
    expect(find.text('T035-7954'), findsNothing);
  });

  test('El administrador recibe la novedad de cada paso del transbordo', () {
    Guia g(
      String estado, {
      String a = '',
      String de = '',
      String t = 'Diego',
    }) => Guia.fromJson(
      _guia(
        transportista: t,
        transbordoEstado: estado,
        transbordoA: a,
        transbordoDe: de,
      ),
    );
    final pedido = CambioGuia(
      g('pendiente', a: 'Juan'),
      '',
      anterior: EstadoGuia.enRuta,
      transbordoAntes: '',
    );
    expect(pedido.esTransbordo, isTrue);
    expect(pedido.titulo, 'Transbordo solicitado');
    expect(pedido.detalle, 'Diego → Juan');

    final aceptado = CambioGuia(
      g('aceptado', de: 'Diego', t: 'Juan'),
      '',
      anterior: EstadoGuia.enRuta,
      transbordoAntes: 'pendiente',
    );
    expect(aceptado.titulo, 'Transbordo aceptado');
    expect(aceptado.detalle, 'Diego → Juan');

    final rechazado = CambioGuia(
      g('rechazado', a: 'Juan'),
      '',
      anterior: EstadoGuia.enRuta,
      transbordoAntes: 'pendiente',
    );
    expect(rechazado.titulo, 'Transbordo rechazado');
    expect(rechazado.pideEliminar, isFalse);
  });
}
