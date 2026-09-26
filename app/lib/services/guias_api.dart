import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/rol_usuario.dart';
import '../models/sucursal.dart';
import '../models/tipo_entrega.dart';

/// URL base del backend (ver ../../backend/README.md). Desplegado en
/// Vercel; toda la persistencia real vive en Google Sheets detrás de esta
/// API — la app nunca accede a Sheets directamente.
const apiBaseUrl = 'https://proyectos-ipesa-phi.vercel.app/api';

class ApiException implements Exception {
  ApiException(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Resultado de POST /auth/login. Login simple, sin token — ver la nota de
/// seguridad en backend/src/app.js y backend/README.md.
class SesionUsuario {
  const SesionUsuario({required this.nombre, required this.rol});

  final String nombre;
  final RolUsuario rol;

  factory SesionUsuario.fromJson(Map<String, dynamic> json) {
    return SesionUsuario(
      nombre: json['nombre'] as String,
      rol: rolUsuarioDesdeApi(json['rol'] as String),
    );
  }
}

/// Resultado del rastreo público: solo los campos no sensibles que expone
/// GET /guias/rastreo/:ultimosCuatro (ver backend/src/app.js).
class ResultadoRastreo {
  const ResultadoRastreo({
    required this.ultimosCuatro,
    required this.estado,
    required this.destino,
  });

  final String ultimosCuatro;
  final EstadoGuia estado;
  final String destino;

  factory ResultadoRastreo.fromJson(Map<String, dynamic> json) {
    return ResultadoRastreo(
      ultimosCuatro: json['ultimos_cuatro'] as String,
      estado: estadoGuiaDesdeApi(json['estado'] as String),
      destino: json['destino'] as String,
    );
  }
}

/// Resultado de POST /ocr/leer-guia: los 5 campos que la IA (Claude, con
/// visión) extrae de la foto. Cualquiera puede salir null si no se pudo
/// leer con confianza — todos quedan en campos editables en la pantalla.
class DatosGuiaLeida {
  const DatosGuiaLeida({
    this.numeroGuia,
    this.destinatario,
    this.destino,
    this.numeroPedido,
    this.numeroEntrega,
  });

  final String? numeroGuia;
  final String? destinatario;
  final String? destino;
  final String? numeroPedido;
  final String? numeroEntrega;

  factory DatosGuiaLeida.fromJson(Map<String, dynamic> json) {
    return DatosGuiaLeida(
      numeroGuia: json['numero_guia'] as String?,
      destinatario: json['destinatario'] as String?,
      destino: json['destino'] as String?,
      numeroPedido: json['numero_pedido'] as String?,
      numeroEntrega: json['numero_entrega'] as String?,
    );
  }
}

class GuiasApi {
  GuiasApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, dynamic> _decodeBody(http.Response res) {
    if (res.body.isEmpty) return const {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Never _lanzarError(http.Response res) {
    try {
      final body = _decodeBody(res);
      throw ApiException(body['error'] as String? ?? 'Error inesperado del servidor.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Error inesperado del servidor (${res.statusCode}).');
    }
  }

  Future<SesionUsuario> login(String nombre, String pin) async {
    final res = await _client.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nombre': nombre, 'pin': pin}),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return SesionUsuario.fromJson(_decodeBody(res));
  }

  /// Auto-registro. El backend siempre crea la cuenta como transportista
  /// (ver backend/src/app.js) — nunca se puede auto-otorgar administrador.
  Future<SesionUsuario> registrar(String nombre, String pin) async {
    final res = await _client.post(
      Uri.parse('$apiBaseUrl/auth/registro'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nombre': nombre, 'pin': pin}),
    );
    if (res.statusCode != 201) _lanzarError(res);
    return SesionUsuario.fromJson(_decodeBody(res));
  }

  Future<List<Sucursal>> listarSucursales() async {
    final res = await _client.get(Uri.parse('$apiBaseUrl/sucursales'));
    if (res.statusCode != 200) _lanzarError(res);
    final lista = jsonDecode(res.body) as List<dynamic>;
    return lista
        .map((e) => Sucursal.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> guardarSucursal(Sucursal sucursal) async {
    final res = await _client.put(
      Uri.parse(
        '$apiBaseUrl/sucursales/${Uri.encodeComponent(sucursal.nombre)}',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'lat': sucursal.lat,
        'lng': sucursal.lng,
        'radioM': sucursal.radioM,
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
  }

  Future<void> eliminarSucursal(String nombre) async {
    final res = await _client.delete(
      Uri.parse('$apiBaseUrl/sucursales/${Uri.encodeComponent(nombre)}'),
    );
    if (res.statusCode != 204) _lanzarError(res);
  }

  Future<List<Guia>> listarGuias({EstadoGuia? estado}) async {
    final uri = Uri.parse(apiBaseUrl).replace(
      path: '${Uri.parse(apiBaseUrl).path}/guias',
      queryParameters: estado != null ? {'estado': estado.valorApi} : null,
    );
    final res = await _client.get(uri);
    if (res.statusCode != 200) _lanzarError(res);
    final lista = jsonDecode(res.body) as List<dynamic>;
    return lista.map((e) => Guia.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Guia>> guiasDelTransportista(String nombre) async {
    final res = await _client.get(
      Uri.parse('$apiBaseUrl/guias/transportista/${Uri.encodeComponent(nombre)}'),
    );
    if (res.statusCode != 200) _lanzarError(res);
    final lista = jsonDecode(res.body) as List<dynamic>;
    return lista.map((e) => Guia.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ResultadoRastreo>> buscarPorUltimosCuatroDigitos(
    String ultimosCuatro,
  ) async {
    final res = await _client.get(
      Uri.parse('$apiBaseUrl/guias/rastreo/$ultimosCuatro'),
    );
    if (res.statusCode != 200) _lanzarError(res);
    final lista = jsonDecode(res.body) as List<dynamic>;
    return lista
        .map((e) => ResultadoRastreo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Manda la foto a la IA (backend → Claude con visión, ver
  /// backend/src/ocrAgente.js) para leer los datos de la guía. Reemplaza el
  /// OCR anterior en el navegador (Tesseract.js), que no leía de forma
  /// confiable un formulario denso con tablas.
  Future<DatosGuiaLeida> leerGuiaConIA(Uint8List fotoBytes) async {
    final res = await _client.post(
      Uri.parse('$apiBaseUrl/ocr/leer-guia'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'imagenBase64': base64Encode(fotoBytes),
        'mediaType': 'image/jpeg',
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return DatosGuiaLeida.fromJson(_decodeBody(res));
  }

  Future<Guia> asignarNuevaGuia({
    required String numeroGuia,
    required TipoEntrega tipoEntrega,
    required String origen,
    required String destino,
    required String transportista,
    required String destinatario,
    required double lat,
    required double lng,
    String? numeroPedido,
    String? numeroEntrega,
  }) async {
    final res = await _client.post(
      Uri.parse('$apiBaseUrl/guias'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'numeroGuia': numeroGuia,
        'tipoEntrega': tipoEntrega.valorApi,
        'origen': origen,
        'destino': destino,
        'transportista': transportista,
        'destinatario': destinatario,
        'geo': {'lat': lat, 'lng': lng},
        if (numeroPedido != null && numeroPedido.isNotEmpty)
          'numeroPedido': numeroPedido,
        if (numeroEntrega != null && numeroEntrega.isNotEmpty)
          'numeroEntrega': numeroEntrega,
      }),
    );
    if (res.statusCode != 201) _lanzarError(res);
    // La API de creación devuelve solo {numeroGuia, estado}; recargamos el
    // objeto completo para tener todos los campos consistentes.
    final guia = await buscarGuiaExacta(numeroGuia);
    if (guia == null) {
      throw ApiException('La guía se creó pero no se pudo recargar.');
    }
    return guia;
  }

  Future<Guia?> buscarGuiaExacta(String numeroGuia) async {
    final guias = await listarGuias();
    for (final g in guias) {
      if (g.numeroGuia == numeroGuia) return g;
    }
    return null;
  }

  Future<Guia> actualizarEstado(
    String numeroGuia,
    EstadoGuia nuevoEstado, {
    double? lat,
    double? lng,
    bool porAdmin = false,
  }) async {
    final res = await _client.patch(
      Uri.parse('$apiBaseUrl/guias/$numeroGuia/estado'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'estado': nuevoEstado.valorApi,
        'porAdmin': porAdmin,
        if (lat != null && lng != null) 'geo': {'lat': lat, 'lng': lng},
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  Future<Guia> corregirNumeroGuia(
    String numeroAnterior,
    String numeroNuevo,
  ) async {
    final res = await _client.patch(
      Uri.parse('$apiBaseUrl/guias/$numeroAnterior/numero'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'numeroNuevo': numeroNuevo}),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }
}
