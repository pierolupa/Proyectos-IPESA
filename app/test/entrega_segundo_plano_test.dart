import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/screens/transportista/entrega_flow_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/services/ubicacion.dart';
import 'package:ipesa_guias/state/app_state.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _guia(String numero) => {
  'numero_guia': numero,
  'estado': 'en_ruta',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente $numero',
  'fecha_creacion': '2026-10-03T14:00:00.000Z',
  'fecha_actualizacion': '2026-10-03T14:00:00.000Z',
  'corregido_por_admin': false,
};

void main() {
  late Completer<http.Response> Function() respuestaEntrega;
  late int envios;
  late List<String> avisos;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Juan Pérez',
      'sesion_rol': 'transportista',
    });
    envios = 0;
    avisos = [];
    AppState.esperasReintento = const [Duration.zero, Duration.zero];
    Ubicacion.olvidarUltima();
    Ubicacion.permisoConcedido = () async => true;
    Ubicacion.leer = () async => Position(
      latitude: -12.05,
      longitude: -77.04,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    EntregaFlowScreen.tomarFoto = () async => null;
    EntregaFlowScreen.elegirFoto = () async => Uint8List.fromList(_png);
  });

  Future<AppState> abrir(WidgetTester tester) async {
    final client = MockClient((request) async {
      final ruta = request.url.path;
      if (ruta.endsWith('/sucursales')) return http.Response('[]', 200);
      if (ruta.endsWith('/ocr/numero-guia')) {
        return http.Response(jsonEncode({'numero_guia': 'T500'}), 200);
      }
      if (request.method == 'PATCH' && ruta.endsWith('/estado')) {
        envios++;
        return respuestaEntrega().future;
      }
      return http.Response(jsonEncode([_guia('T500'), _guia('T501')]), 200);
    });
    final appState = AppState(api: GuiasApi(client: client))
      ..avisar = avisos.add;
    await appState.restaurarSesion();
    await appState.cargarGuias();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EntregaFlowScreen(
                      guia: appState.buscarPorNumero('T500')!,
                      desdeDetalle: false,
                    ),
                  ),
                ),
                child: const Text('Entregar'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Entregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Galería'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(
        'La foto muestra la guía firmada o el comprobante de la agencia',
      ),
    );
    await tester.pumpAndSettle();
    return appState;
  }

  testWidgets('Al confirmar, la entrega queda al instante y se envía por '
      'detrás', (tester) async {
    final servidor = Completer<http.Response>();
    respuestaEntrega = () => servidor;
    final appState = await abrir(tester);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    // El servidor aún no respondió, pero la pantalla ya se cerró.
    expect(find.byType(EntregaFlowScreen), findsNothing);
    expect(find.text('Entrega registrada.'), findsOneWidget);
    expect(appState.buscarPorNumero('T500')!.estado, EstadoGuia.entregado);
    expect(appState.entregasEnviando, 1);

    // Un refresco con datos viejos no la devuelve a "En ruta".
    await appState.actualizarEnSegundoPlano();
    expect(appState.buscarPorNumero('T500')!.estado, EstadoGuia.entregado);

    servidor.complete(
      http.Response(jsonEncode({..._guia('T500'), 'estado': 'entregado'}), 200),
    );
    await tester.pumpAndSettle();
    expect(appState.entregasEnviando, 0);
    expect(envios, 1);
    expect(avisos, isEmpty);
  });

  testWidgets('Si es la señal o Drive, no la pierde: queda guardada en el '
      'celular y se envía después', (tester) async {
    respuestaEntrega = () =>
        Completer()..complete(http.Response('{"error":"caído"}', 503));
    final appState = await abrir(tester);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(find.byType(EntregaFlowScreen), findsNothing);

    // Reintentó, sigue entregada en el celular y avisa que se enviará sola.
    expect(envios, 3);
    expect(appState.entregasEnviando, 1);
    expect(appState.buscarPorNumero('T500')!.estado, EstadoGuia.entregado);
    expect(avisos.single, contains('se enviará sola'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('entregas_pendientes'), contains('T500'));

    // Vuelve la señal: en la siguiente actualización se envía.
    respuestaEntrega = () => Completer()
      ..complete(
        http.Response(
          jsonEncode({..._guia('T500'), 'estado': 'entregado'}),
          200,
        ),
      );
    await appState.actualizarEnSegundoPlano();
    await tester.pumpAndSettle();
    expect(appState.entregasEnviando, 0);
    expect(prefs.getString('entregas_pendientes'), isNull);
  });

  testWidgets('Si el servidor la rechaza, vuelve a "En ruta" con aviso', (
    tester,
  ) async {
    respuestaEntrega = () => Completer()
      ..complete(
        http.Response('{"error":"Falta la foto de la entrega."}', 400),
      );
    final appState = await abrir(tester);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(envios, 1);
    expect(appState.entregasEnviando, 0);
    expect(appState.buscarPorNumero('T500')!.estado, EstadoGuia.enRuta);
    expect(avisos.single, contains('No se pudo registrar la entrega de T500'));
  });

  test(
    'Al volver a abrir la app, envía las entregas que quedaron guardadas',
    () async {
      SharedPreferences.setMockInitialValues({
        'sesion_nombre': 'Juan Pérez',
        'sesion_rol': 'transportista',
        'entregas_pendientes': jsonEncode([
          {
            'usuario': 'Juan Pérez',
            'clave': 'T500|2026-10-03T14:00:00.000Z',
            'numero': 'T500',
            'cuerpo': {
              'estado': 'entregado',
              'foto': {'base64': 'AAAA'},
            },
          },
          {
            'usuario': 'Otro Chofer',
            'clave': 'T501|2026-10-03T14:00:00.000Z',
            'numero': 'T501',
            'cuerpo': {'estado': 'entregado'},
          },
        ]),
      });
      final enviados = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'PATCH') {
          enviados.add(request.url.path);
          return http.Response(
            jsonEncode({..._guia('T500'), 'estado': 'entregado'}),
            200,
          );
        }
        if (request.url.path.endsWith('/sucursales')) {
          return http.Response('[]', 200);
        }
        return http.Response(jsonEncode([_guia('T500'), _guia('T501')]), 200);
      });
      final appState = AppState(api: GuiasApi(client: client));
      await appState.restaurarSesion();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Solo la suya, y una vez enviada ya no queda pendiente.
      expect(enviados, [endsWith('/guias/T500/estado')]);
      expect(appState.entregasEnviando, 0);
      expect(appState.buscarPorNumero('T500')!.estado, EstadoGuia.entregado);
    },
  );
}
