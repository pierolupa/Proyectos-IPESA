import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/estado_guia.dart';
import '../models/guia.dart';
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

  Future<Guia> asignarNuevaGuia({
    required String numeroGuia,
    required TipoEntrega tipoEntrega,
    required String origen,
    required String destino,
    required String transportista,
    required String destinatario,
    required double lat,
    required double lng,
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
