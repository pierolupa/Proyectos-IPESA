import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/screens/transportista/guia_detail_screen.dart';
import 'package:ipesa_guias/screens/transportista/rechazo_sheet.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

Map<String, dynamic> _guia({String estado = 'en_ruta', String motivo = ''}) => {
  'numero_guia': 'T033-3455',
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Villa El Salvador',
  'transportista': 'Juan Perez',
  'destinatario': 'SHOUGANG HIERRO PERU S.A.A.',
  'fecha_actualizacion': '2026-09-27T15:00:00.000Z',
  'corregido_por_admin': false,
  'motivo_rechazo': motivo,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Sin GPS en los tests: se rechaza sin ubicación.
    HojaRechazo.leerUbicacion = () async => null;
  });

  Future<(AppState, List<http.Request>)> abrirDetalle(
    WidgetTester tester,
  ) async {
    final pedidos = <http.Request>[];
    final client = MockClient((request) async {
      pedidos.add(request);
      if (request.url.path.endsWith('/rechazo')) {
        final cuerpo = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(
            _guia(estado: 'rechazado', motivo: cuerpo['motivo'] as String),
          ),
          200,
        );
      }
      if (request.url.path.endsWith('/sucursales')) {
        return http.Response('[]', 200);
      }
      return http.Response(jsonEncode([_guia()]), 200);
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cargarGuias();
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const GuiaDetailScreen(numeroGuia: 'T033-3455'),
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return (appState, pedidos);
  }

  testWidgets('El transportista rechaza una tarea con un motivo', (
    tester,
  ) async {
    final (appState, pedidos) = await abrirDetalle(tester);

    await tester.tap(find.text('Rechazar tarea'));
    await tester.pumpAndSettle();
    expect(find.text('¿Por qué la rechazas?'), findsOneWidget);

    // Sin motivo no deja.
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar tarea'));
    await tester.pumpAndSettle();
    expect(find.text('Elige un motivo.'), findsOneWidget);

    await tester.tap(find.text('Cliente ausente'));
    await tester.enterText(find.byType(TextField), 'Nadie abrió en 20 min');
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar tarea'));
    await tester.pumpAndSettle();

    final rechazo = pedidos.last;
    expect(rechazo.url.path, endsWith('/guias/T033-3455/rechazo'));
    expect(
      (jsonDecode(rechazo.body) as Map)['motivo'],
      'Cliente ausente: Nadie abrió en 20 min',
    );
    expect(appState.buscarPorNumero('T033-3455')!.estado, EstadoGuia.rechazado);
    // Volvió a la pantalla anterior y avisa que se rechazó.
    expect(find.text('abrir'), findsOneWidget);
    expect(find.textContaining('rechazada'), findsOneWidget);
  });

  testWidgets('"Otro" obliga a escribir el motivo', (tester) async {
    final (_, pedidos) = await abrirDetalle(tester);
    await tester.tap(find.text('Rechazar tarea'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Otro'));
    await tester.tap(find.widgetWithText(FilledButton, 'Rechazar tarea'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Escribe qué pasó'), findsOneWidget);
    expect(pedidos.where((p) => p.url.path.endsWith('/rechazo')), isEmpty);
  });

  test('una rechazada no es entregada pero sí está cerrada', () {
    expect(EstadoGuia.rechazado.esFinal, isFalse);
    expect(EstadoGuia.rechazado.esCerrada, isTrue);
    expect(EstadoGuia.rechazado.grupo, GrupoEstado.rechazado);
    expect(estadoGuiaDesdeApi('rechazado'), EstadoGuia.rechazado);
  });

  test('el admin recibe el aviso con el motivo', () async {
    var rechazada = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/sucursales')) {
        return http.Response('[]', 200);
      }
      return http.Response(
        jsonEncode([
          rechazada
              ? _guia(estado: 'rechazado', motivo: 'Dirección incorrecta')
              : _guia(),
        ]),
        200,
      );
    });
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cargarGuias();
    rechazada = true;
    final cambios = await appState.actualizarEnSegundoPlano();
    expect(
      cambios.single.mensaje,
      'Juan Perez rechazó la guía T033-3455: Dirección incorrecta',
    );
  });
}
