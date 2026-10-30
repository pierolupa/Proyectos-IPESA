import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/estado_guia.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

final _ahora = DateTime.now().toUtc();

Map<String, dynamic> _guia(
  String numero,
  String estado, {
  Duration hace = Duration.zero,
}) {
  final f = _ahora.subtract(hace).toIso8601String();
  return {
    'numero_guia': numero,
    'estado': estado,
    'tipo_entrega': 'cliente_final',
    'origen': 'Almacen Ate',
    'destino': 'Lima',
    'transportista': 'Oscar Aspur',
    'destinatario': 'Cliente $numero',
    'fecha_creacion': f,
    'fecha_actualizacion': f,
    'corregido_por_admin': false,
  };
}

void main() {
  late List<Uri> pedidos;
  late List<Map<String, dynamic>> respuesta;

  Future<AppState> abrir(String rol) async {
    SharedPreferences.setMockInitialValues({
      'sesion_nombre': 'Admin',
      'sesion_rol': rol,
    });
    pedidos = [];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/sucursales')) {
        return http.Response('[]', 200);
      }
      pedidos.add(request.url);
      return http.Response(jsonEncode(respuesta), 200);
    });
    final app = AppState(api: GuiasApi(client: client));
    await app.restaurarSesion();
    return app;
  }

  test(
    'El panel carga el último mes y las abiertas, no toda la hoja',
    () async {
      respuesta = [_guia('T1', 'en_ruta')];
      await abrir('administrador');
      final consulta = pedidos.single.queryParameters;
      expect(consulta.keys, ['vigentes']);
      final desde = DateTime.parse(consulta['vigentes']!).toLocal();
      final esperado = DateTime.now().subtract(
        const Duration(days: diasPanelPorDefecto - 1),
      );
      expect(desde.year, esperado.year);
      expect(desde.month, esperado.month);
      expect(desde.day, esperado.day);
      expect(desde.hour, 0);
    },
  );

  test('El transportista carga solo lo de hoy y sus abiertas', () async {
    respuesta = [];
    await abrir('transportista');
    final desde = DateTime.parse(pedidos.single.queryParameters['vigentes']!)
        .toLocal();
    final hoy = DateTime.now();
    expect(
      (desde.year, desde.month, desde.day),
      (hoy.year, hoy.month, hoy.day),
    );
  });

  test(
    'Cada refresco trae solo lo que cambió y lo junta con lo que hay',
    () async {
      respuesta = [
        _guia('A', 'en_ruta', hace: const Duration(hours: 3)),
        _guia('B', 'en_ruta', hace: const Duration(hours: 2)),
        _guia('C', 'entregado', hace: const Duration(days: 3)),
      ];
      final app = await abrir('administrador');
      expect(app.guias, hasLength(3));

      // El servidor responde solo las abiertas y lo que cambió: A se
      // entregó, B se borró (era abierta y ya no viene), D es nueva.
      respuesta = [
        _guia('A', 'entregado', hace: const Duration(hours: 3))
          ..['fecha_actualizacion'] = _ahora.toIso8601String(),
        _guia('D', 'en_ruta'),
      ];
      final cambios = await app.actualizarEnSegundoPlano();

      // Pidió desde lo último que tenía (menos un margen), no todo.
      final marca = DateTime.parse(pedidos.last.queryParameters['vigentes']!);
      expect(marca.isAfter(_ahora.subtract(const Duration(hours: 3))), isTrue);
      final porNumero = {for (final g in app.guias) g.numeroGuia: g};
      expect(porNumero.keys, unorderedEquals(['A', 'C', 'D']));
      expect(porNumero['A']!.estado.esFinal, isTrue);
      // C (cerrada, sin cambios) se queda aunque no vino.
      expect(porNumero['C'], isNotNull);
      expect(
        cambios.map((c) => c.guia.numeroGuia),
        unorderedEquals(['A', 'D']),
      );
    },
  );

  test('Elegir fechas antiguas las pide una sola vez y las suma', () async {
    respuesta = [_guia('A', 'en_ruta')];
    final app = await abrir('administrador');

    respuesta = [_guia('V', 'entregado', hace: const Duration(days: 60))];
    final hace90 = DateTime.now().subtract(const Duration(days: 90));
    await app.asegurarDesde(hace90);
    final consulta = pedidos.last.queryParameters;
    expect(consulta.keys, unorderedEquals(['desde', 'hasta']));
    expect(app.guias.map((g) => g.numeroGuia), unorderedEquals(['A', 'V']));

    // Ya cargadas: no vuelve a pedirlas.
    final antes = pedidos.length;
    await app.asegurarDesde(hace90.add(const Duration(days: 5)));
    expect(pedidos.length, antes);

    // La recarga completa incluye lo antiguo que se pidió.
    await app.cargarGuias();
    final desde = DateTime.parse(pedidos.last.queryParameters['vigentes']!);
    expect(desde.isBefore(hace90), isTrue);
  });

  test('El comercial sigue pidiendo su rango de fechas', () async {
    respuesta = [];
    await abrir('comercial');
    expect(
      pedidos.single.queryParameters.keys,
      unorderedEquals(['desde', 'hasta']),
    );
  });
}
