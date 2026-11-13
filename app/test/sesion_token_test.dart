import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ipesa_guias/models/rol_usuario.dart';
import 'package:ipesa_guias/services/guias_api.dart';
import 'package:ipesa_guias/state/app_state.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

/// Servidor simulado: el login da "token-nuevo" (o responde
/// `estadoLogin`), y GET /guias solo acepta ese token.
class _Servidor {
  _Servidor({this.estadoLogin = 200});

  static const _token = 'token-nuevo';
  final int estadoLogin;
  int logins = 0;
  final cabeceras = <String?>[];

  MockClient get cliente => MockClient((request) async {
    if (request.url.path.endsWith('/auth/login')) {
      logins++;
      if (estadoLogin != 200) {
        return _json({'error': 'No'}, status: estadoLogin);
      }
      return _json({
        'nombre': 'Juan Pérez',
        'rol': 'transportista',
        'token': _token,
      });
    }
    if (request.url.path.endsWith('/guias')) {
      final cabecera = request.headers['Authorization'];
      cabeceras.add(cabecera);
      if (cabecera != 'Bearer $_token') {
        return _json({'error': 'Tu sesión venció.'}, status: 401);
      }
      return _json(<Object>[]);
    }
    if (request.url.path.endsWith('/sucursales')) return _json(<Object>[]);
    return http.Response('No mockeado: ${request.url}', 404);
  });
}

/// Una sesión guardada en el equipo, como la que deja una versión anterior.
Map<String, Object> _sesionGuardada({String? token}) => {
  'sesion_nombre': 'Juan Pérez',
  'sesion_rol': 'transportista',
  'cuenta_nombre': 'Juan Pérez',
  'cuenta_pin': '1234',
  'sesion_token': ?token,
};

void main() {
  test('al ingresar, cada pedido lleva el token de la sesión', () async {
    SharedPreferences.setMockInitialValues({});
    final servidor = _Servidor();
    final appState = AppState(api: GuiasApi(client: servidor.cliente));

    await appState.iniciarSesion('Juan Pérez', '1234');

    expect(servidor.cabeceras, ['Bearer token-nuevo']);
    expect(appState.error, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sesion_token'), 'token-nuevo');
  });

  test('una sesión vencida se renueva sola con la cuenta guardada', () async {
    SharedPreferences.setMockInitialValues(_sesionGuardada(token: 'viejo'));
    final servidor = _Servidor();
    final appState = AppState(api: GuiasApi(client: servidor.cliente));

    await appState.restaurarSesion();

    expect(servidor.logins, 1);
    // Primero con el token vencido, luego el mismo pedido con el nuevo.
    expect(servidor.cabeceras, ['Bearer viejo', 'Bearer token-nuevo']);
    expect(appState.rolActual, RolUsuario.transportista);
    expect(appState.error, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sesion_token'), 'token-nuevo');
  });

  test('una sesión de antes de los tokens también se renueva sola', () async {
    SharedPreferences.setMockInitialValues(_sesionGuardada());
    final servidor = _Servidor();
    final appState = AppState(api: GuiasApi(client: servidor.cliente));

    await appState.restaurarSesion();

    expect(servidor.cabeceras, [null, 'Bearer token-nuevo']);
    expect(appState.rolActual, RolUsuario.transportista);
    expect(appState.error, isNull);
  });

  test('si el PIN guardado ya no sirve, cierra la sesión y avisa', () async {
    SharedPreferences.setMockInitialValues(_sesionGuardada(token: 'viejo'));
    final servidor = _Servidor(estadoLogin: 401);
    final appState = AppState(api: GuiasApi(client: servidor.cliente));

    await appState.restaurarSesion();

    expect(appState.rolActual, isNull);
    expect(appState.avisoSesion, contains('venció'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sesion_token'), isNull);
  });

  test('un fallo del servidor al renovar no cierra la sesión', () async {
    SharedPreferences.setMockInitialValues(_sesionGuardada(token: 'viejo'));
    final servidor = _Servidor(estadoLogin: 500);
    final appState = AppState(api: GuiasApi(client: servidor.cliente));

    await appState.restaurarSesion();

    expect(appState.rolActual, RolUsuario.transportista);
    expect(appState.avisoSesion, isNull);
  });
}
