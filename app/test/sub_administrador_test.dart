import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/rol_usuario.dart';
import 'package:ipesa_guias/screens/admin/admin_dashboard_screen.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

final _hoy10 = DateTime.now().copyWith(hour: 10, minute: 0, second: 0);

Map<String, dynamic> _guia(String numero, String transportista) => {
  'numero_guia': numero,
  'estado': 'en_ruta',
  'tipo_entrega': 'cliente_final',
  'origen': 'Almacén Callao',
  'destino': 'Av. Principal 123',
  'transportista': transportista,
  'destinatario': 'Cliente $numero',
  'fecha_creacion': _hoy10.toUtc().toIso8601String(),
  'fecha_actualizacion': _hoy10.toUtc().toIso8601String(),
  'corregido_por_admin': false,
};

/// Jairo Fabian (sub administrador) a cargo de Almacen Viru.
Future<AppState> _sesionDeJairo() async {
  SharedPreferences.setMockInitialValues({
    'sesion_nombre': 'Jairo Fabian',
    'sesion_rol': RolUsuario.subAdministrador.name,
  });
  final client = MockClient((request) async {
    final ruta = request.url.path;
    if (ruta.endsWith('/transportistas/equipo')) {
      return http.Response(
        jsonEncode([
          {'nombre': 'Almacen Viru'},
        ]),
        200,
      );
    }
    if (ruta.endsWith('/sucursales')) {
      return http.Response(
        jsonEncode([
          {'nombre': 'Trp Viru', 'lat': -8.4, 'lng': -78.7, 'radio_m': 200},
        ]),
        200,
      );
    }
    return http.Response(
      jsonEncode([
        _guia('T050-1', 'Almacen Viru'),
        _guia('T001-9', 'Oscar Aspur'),
      ]),
      200,
    );
  });
  final appState = AppState(api: GuiasApi(client: client));
  await appState.restaurarSesion();
  return appState;
}

void main() {
  test('el rol llega del servidor como sub_administrador', () {
    expect(
      rolUsuarioDesdeApi('sub_administrador'),
      RolUsuario.subAdministrador,
    );
  });

  test('ve solo las guías de sus transportistas; Rastrear, todas', () async {
    final appState = await _sesionDeJairo();
    expect(appState.esSubAdministrador, isTrue);
    expect([for (final g in appState.guias) g.numeroGuia], ['T050-1']);
    expect(appState.todasLasGuias, hasLength(2));
    // Una guía de otra zona se puede abrir desde Rastrear.
    expect(appState.buscarPorNumero('T001-9'), isNotNull);
  });

  testWidgets('Su menú no tiene archivo, regularización ni fotos, y las '
      'sucursales son solo para ver', (tester) async {
    final appState = await _sesionDeJairo();
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const MaterialApp(home: AdminDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // En Guías solo la de su transportista.
    expect(find.text('T050-1'), findsWidgets);
    expect(find.text('T001-9'), findsNothing);

    await tester.tap(find.byTooltip('Menú'));
    await tester.pumpAndSettle();
    expect(find.text('Sub administrador · Jairo Fabian'), findsOneWidget);
    for (final oculta in [
      'Archivo de guías',
      'Regularización',
      'Pasar fotos a Drive',
    ]) {
      expect(find.text(oculta), findsNothing);
    }

    await tester.tap(find.text('Sucursales'));
    await tester.pumpAndSettle();
    expect(find.text('Trp Viru'), findsOneWidget);
    expect(find.text('Nueva sucursal'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
