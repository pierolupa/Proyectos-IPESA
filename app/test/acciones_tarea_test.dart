import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/screens/admin/admin_guia_edit_screen.dart';
import 'package:ipesa_guias/screens/transportista/guia_detail_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';
import 'package:ipesa_guias/widgets/avisos_novedades.dart';

const _creada = '2026-09-28T13:00:00.000Z';

Map<String, dynamic> _guia({
  String estado = 'en_ruta',
  String eliminacion = '',
  String motivo = '',
}) => {
  'numero_guia': 'T001-500',
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Lurín',
  'destino': 'Av. Principal 123',
  'transportista': 'Oscar Aspur',
  'destinatario': 'Ferretería Lima',
  'fecha_creacion': _creada,
  'fecha_actualizacion': _creada,
  'corregido_por_admin': false,
  'eliminacion': eliminacion,
  'motivo_eliminacion': motivo,
};

/// Servidor falso: guarda los pedidos y responde como el backend.
class _Servidor {
  _Servidor(this.guia);

  Map<String, dynamic>? guia;
  final pedidos = <http.Request>[];

  late final client = MockClient((r) async {
    pedidos.add(r);
    final ruta = r.url.path;
    if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
    if (r.method == 'GET') {
      return http.Response(jsonEncode([?guia]), 200);
    }
    final cuerpo = r.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    if (ruta.endsWith('/solicitud-eliminacion') && r.method == 'POST') {
      guia = {
        ...guia!,
        'eliminacion': 'pendiente',
        'motivo_eliminacion': cuerpo['motivo'],
      };
    } else if (ruta.endsWith('/solicitud-eliminacion/rechazo')) {
      guia = {...guia!, 'eliminacion': 'rechazada'};
    } else if (ruta.endsWith('/tipo')) {
      guia = {
        ...guia!,
        'tipo_entrega': cuerpo['tipoEntrega'],
        if (cuerpo['destino'] != null) 'destino': cuerpo['destino'],
      };
    } else if (r.method == 'DELETE' && ruta.endsWith('/T001-500')) {
      guia = null;
      return http.Response(jsonEncode({'eliminada': true}), 200);
    }
    return http.Response(jsonEncode(guia), 200);
  });
}

Future<AppState> _abrir(
  WidgetTester tester,
  _Servidor servidor,
  Widget pantalla, {
  String rol = 'transportista',
}) async {
  SharedPreferences.setMockInitialValues({
    'sesion_nombre': rol == 'transportista' ? 'Oscar Aspur' : 'Admin',
    'sesion_rol': rol,
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
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => pantalla)),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return appState;
}

void main() {
  testWidgets('El transportista pide eliminar una tarea en ruta', (
    tester,
  ) async {
    final servidor = _Servidor(_guia());
    await _abrir(
      tester,
      servidor,
      const GuiaDetailScreen(numeroGuia: 'T001-500'),
    );

    expect(find.text('Punto de partida'), findsOneWidget);
    expect(find.text('Almacén Lurín'), findsOneWidget);

    await tester.tap(find.text('Eliminar tarea'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'La registré dos veces');
    await tester.tap(find.text('Pedir eliminación'));
    await tester.pumpAndSettle();

    final pedido = servidor.pedidos.last;
    expect(pedido.url.path, endsWith('/guias/T001-500/solicitud-eliminacion'));
    expect(jsonDecode(pedido.body), {
      'motivo': 'La registré dos veces',
      'fechaCreacion': _creada,
    });
    // No se borró nada: espera al administrador.
    expect(find.text('Pediste eliminar esta tarea'), findsOneWidget);
    expect(find.text('Eliminar tarea'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Una tarea entregada no se puede eliminar ni cambiar de tipo', (
    tester,
  ) async {
    await _abrir(
      tester,
      _Servidor(_guia(estado: 'entregado')),
      const GuiaDetailScreen(numeroGuia: 'T001-500'),
    );
    expect(find.text('Eliminar tarea'), findsNothing);
    expect(find.text('Cambiar'), findsNothing);
  });

  testWidgets('El transportista ya no elige el tipo de entrega', (
    tester,
  ) async {
    await _abrir(
      tester,
      _Servidor(_guia()),
      const GuiaDetailScreen(numeroGuia: 'T001-500'),
    );
    // Se ve, pero lo pone la IA (agencia si ve su comprobante).
    expect(find.text('Tipo de entrega'), findsOneWidget);
    expect(find.text('Cambiar'), findsNothing);
  });

  testWidgets('El administrador aprueba y la tarea se borra', (tester) async {
    final servidor = _Servidor(
      _guia(eliminacion: 'pendiente', motivo: 'Duplicada'),
    );
    final appState = await _abrir(
      tester,
      servidor,
      const AdminGuiaEditScreen(numeroGuia: 'T001-500'),
      rol: 'administrador',
    );

    expect(find.text('Oscar Aspur pide eliminar esta tarea'), findsOneWidget);
    expect(find.text('Motivo: Duplicada'), findsOneWidget);

    await tester.tap(find.text('Aprobar y eliminar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    final pedido = servidor.pedidos.last;
    expect(pedido.method, 'DELETE');
    expect(pedido.url.path, endsWith('/guias/T001-500'));
    expect(pedido.url.queryParameters['fechaCreacion'], _creada);
    expect(appState.guias, isEmpty);
    expect(
      find.textContaining('eliminada de la base de datos'),
      findsOneWidget,
    );
  });

  testWidgets('El administrador puede mantener la tarea', (tester) async {
    final servidor = _Servidor(_guia(eliminacion: 'pendiente'));
    await _abrir(
      tester,
      servidor,
      const AdminGuiaEditScreen(numeroGuia: 'T001-500'),
      rol: 'administrador',
    );
    await tester.tap(find.text('Mantener tarea'));
    await tester.pumpAndSettle();
    expect(
      servidor.pedidos.last.url.path,
      endsWith('/solicitud-eliminacion/rechazo'),
    );
    expect(find.text('Oscar Aspur pide eliminar esta tarea'), findsNothing);
  });

  test('Al administrador le llega la novedad del pedido', () async {
    final servidor = _Servidor(_guia());
    final appState = AppState(api: GuiasApi(client: servidor.client));
    await appState.cargarGuias();
    servidor.guia = _guia(eliminacion: 'pendiente', motivo: 'Duplicada');

    final cambios = await appState.actualizarEnSegundoPlano();

    expect(cambios, hasLength(1));
    expect(cambios.single.pideEliminar, isTrue);
    expect(cambios.single.titulo, 'Pide eliminar una tarea');
    expect(cambios.single.detalle, 'Oscar Aspur · Duplicada');
  });
}
