import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

Map<String, dynamic> _guia(String numero, String estado) => {
  'numero_guia': numero,
  'estado': estado,
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': 'Juan Pérez',
  'destinatario': 'Cliente $numero',
  'fecha_actualizacion': '2026-09-29T15:00:00.000Z',
  'corregido_por_admin': false,
};

void main() {
  test('Una guía con el estado vacío no impide cargar las demás', () async {
    final client = MockClient(
      (r) async => r.url.path.endsWith('/sucursales')
          ? http.Response('[]', 200)
          : http.Response(
              jsonEncode([
                _guia('T1', 'en_ruta'),
                _guia('T2', ''),
                _guia('T3', 'entregado'),
              ]),
              200,
            ),
    );
    final appState = AppState(api: GuiasApi(client: client));
    await appState.cargarGuias();

    expect(appState.error, isNull);
    expect(appState.guias.map((g) => g.numeroGuia), ['T1', 'T3']);
  });
}
