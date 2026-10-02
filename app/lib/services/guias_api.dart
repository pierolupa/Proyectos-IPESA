import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// URL (del backend) para ver la foto de la entrega. Las fotos son
/// privadas: siempre pasan por la API. `v` cambia si la foto se reemplaza,
/// para que el navegador no muestre la anterior desde su caché.
String urlFotoEntrega(Guia guia) =>
    '$apiBaseUrl/guias/${Uri.encodeComponent(guia.numeroGuia)}/foto'
    '?v=${guia.fotoEntregaUrl.hashCode.toUnsigned(32)}';

/// Tipo MIME de la foto según sus primeros bytes (la cámara da JPEG, pero
/// una imagen elegida de la galería puede ser PNG o WebP).
String tipoImagen(Uint8List bytes) {
  if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return 'image/png';
  }
  if (bytes.length > 11 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return 'image/jpeg';
}

Map<String, String> _fotoJson(Uint8List foto) => {
  'base64': base64Encode(foto),
  'mediaType': tipoImagen(foto),
};

class ApiException implements Exception {
  ApiException(this.mensaje, {this.codigo});
  final String mensaje;

  /// Código HTTP de la respuesta, si vino del servidor.
  final int? codigo;

  /// La IA está ocupada (límite por minuto): conviene esperar y reintentar.
  bool get esLimiteTemporal => codigo == 429;

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

/// El comprobante de una agencia de transporte (boleta, factura o vale de
/// encomienda) pegado en la guía, leído por la IA de la foto.
class ComprobanteAgencia {
  const ComprobanteAgencia({this.razonSocial = '', this.ruc = '', this.monto});

  final String razonSocial;
  final String ruc;
  final double? monto;

  /// De la respuesta de la IA (agencia_*); null si no había comprobante.
  static ComprobanteAgencia? desdeIA(Map<String, dynamic> json) {
    final razon = '${json['agencia_razon_social'] ?? ''}'.trim();
    final ruc = '${json['agencia_ruc'] ?? ''}'.trim();
    final valor = json['agencia_monto'];
    final monto = valor is num
        ? valor.toDouble()
        : double.tryParse('${valor ?? ''}'.trim());
    if (razon.isEmpty && ruc.isEmpty && monto == null) return null;
    return ComprobanteAgencia(razonSocial: razon, ruc: ruc, monto: monto);
  }

  Map<String, dynamic> toJson() => {
    'razonSocial': razonSocial,
    'ruc': ruc,
    'monto': monto,
  };

  /// En una línea, ej. "PALOMINO S.A.C. · RUC 20515659324 · S/ 70.00".
  String get resumen => [
    if (razonSocial.isNotEmpty) razonSocial,
    if (ruc.isNotEmpty) 'RUC $ruc',
    if (monto case final m?) 'S/ ${m.toStringAsFixed(2)}',
  ].join(' · ');
}

/// Lo que la IA lee de una foto de entrega: el número de guía y, si viene
/// pegado, el comprobante de la agencia.
typedef LecturaEntrega = ({String? numero, ComprobanteAgencia? comprobante});

/// Resultado de POST /ocr/leer-guia: los campos que la IA (Gemini, con
/// visión) extrae de la foto. Cualquiera puede salir null si no se pudo
/// leer con confianza — todos quedan en campos editables en la pantalla.
class DatosGuiaLeida {
  const DatosGuiaLeida({
    this.numeroGuia,
    this.destinatario,
    this.destino,
    this.origen,
    this.numeroPedido,
    this.numeroEntrega,
    this.comprobante,
  });

  /// El comprobante de agencia pegado en la guía (null si no hay).
  final ComprobanteAgencia? comprobante;

  final String? numeroGuia;
  final String? destinatario;
  final String? destino;

  /// El "Punto de partida" de la hoja.
  final String? origen;
  final String? numeroPedido;
  final String? numeroEntrega;

  factory DatosGuiaLeida.fromJson(Map<String, dynamic> json) {
    return DatosGuiaLeida(
      numeroGuia: json['numero_guia'] as String?,
      destinatario: json['destinatario'] as String?,
      destino: json['destino'] as String?,
      origen: json['origen'] as String?,
      numeroPedido: json['numero_pedido'] as String?,
      numeroEntrega: json['numero_entrega'] as String?,
      comprobante: ComprobanteAgencia.desdeIA(json),
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
      throw ApiException(
        body['error'] as String? ?? 'Error inesperado del servidor.',
        codigo: res.statusCode,
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Error inesperado del servidor (${res.statusCode}).',
        codigo: res.statusCode,
      );
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

  /// [desde]/[hasta]: solo las tareas creadas en ese lapso (desde
  /// incluido, hasta excluido).
  /// Las guías de una lista. Una fila de la hoja con datos incompletos o
  /// raros (sin estado, un tipo desconocido...) se salta: nunca impide ver
  /// las demás.
  static List<Guia> _guiasValidas(List<dynamic> lista) {
    final guias = <Guia>[];
    for (final e in lista) {
      try {
        guias.add(Guia.fromJson(e as Map<String, dynamic>));
      } catch (err) {
        debugPrint('Guía omitida por datos incompletos: $err · $e');
      }
    }
    return guias;
  }

  Future<List<Guia>> listarGuias({
    EstadoGuia? estado,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final consulta = {
      if (estado != null) 'estado': estado.valorApi,
      if (desde != null) 'desde': desde.toUtc().toIso8601String(),
      if (hasta != null) 'hasta': hasta.toUtc().toIso8601String(),
    };
    final uri = Uri.parse(apiBaseUrl).replace(
      path: '${Uri.parse(apiBaseUrl).path}/guias',
      queryParameters: consulta.isEmpty ? null : consulta,
    );
    final res = await _client.get(uri);
    if (res.statusCode != 200) _lanzarError(res);
    final lista = jsonDecode(res.body) as List<dynamic>;
    return _guiasValidas(lista);
  }

  Future<List<Guia>> guiasDelTransportista(String nombre) async {
    final res = await _client.get(
      Uri.parse(
        '$apiBaseUrl/guias/transportista/${Uri.encodeComponent(nombre)}',
      ),
    );
    if (res.statusCode != 200) _lanzarError(res);
    final lista = jsonDecode(res.body) as List<dynamic>;
    return _guiasValidas(lista);
  }

  /// Manda la foto a la IA (backend → Claude con visión, ver
  /// backend/src/ocrAgente.js) para leer los datos de la guía. Reemplaza el
  /// OCR anterior en el navegador (Tesseract.js), que no leía de forma
  /// confiable un formulario denso con tablas.
  /// Los bytes de la foto de la entrega (para verla, descargarla,
  /// copiarla o compartirla sin bajarla dos veces).
  Future<Uint8List> fotoEntrega(Guia guia) async {
    final res = await _client.get(Uri.parse(urlFotoEntrega(guia)));
    if (res.statusCode != 200) _lanzarError(res);
    return res.bodyBytes;
  }

  Future<DatosGuiaLeida> leerGuiaConIA(Uint8List fotoBytes) async {
    final res = await _client.post(
      Uri.parse('$apiBaseUrl/ocr/leer-guia'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'imagenBase64': base64Encode(fotoBytes),
        'mediaType': tipoImagen(fotoBytes),
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return DatosGuiaLeida.fromJson(_decodeBody(res));
  }

  /// Entrega inteligente: lee el número de guía de una foto de entrega (y
  /// el comprobante de agencia, si viene pegado). La IA lo compara con
  /// [candidatos] (sus guías en ruta) y, si es una de ellas, devuelve ese
  /// número tal cual.
  Future<LecturaEntrega> leerNumeroGuia(
    Uint8List fotoBytes, {
    List<String> candidatos = const [],
  }) async {
    final res = await _client.post(
      Uri.parse('$apiBaseUrl/ocr/numero-guia'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'imagenBase64': base64Encode(fotoBytes),
        'mediaType': tipoImagen(fotoBytes),
        'candidatos': candidatos,
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    final json = _decodeBody(res);
    final numero = json['numero_guia'];
    return (
      numero: numero is String && numero.trim().isNotEmpty
          ? numero.trim()
          : null,
      comprobante: ComprobanteAgencia.desdeIA(json),
    );
  }

  /// Carga masiva: registra hasta [maxGuiasPorCarga] guías con un solo
  /// pedido. Devuelve, en el mismo orden, la guía creada o el error de
  /// cada una (las demás se registran igual). Con [despachoCorte] todas
  /// quedan unidas en un Despacho Corte, cuyo código va en
  /// [ResultadoCarga.despachoCorte].
  Future<ResultadoCarga> asignarLote(
    List<GuiaNueva> guias, {
    bool despachoCorte = false,
    String? codigoCorte,
  }) async {
    final res = await _client.post(
      Uri.parse(
        despachoCorte
            ? '$apiBaseUrl/despachos-corte'
            : '$apiBaseUrl/guias/lote',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'guias': [for (final g in guias) g.toJson()],
        if (despachoCorte && codigoCorte != null) 'despachoCorte': codigoCorte,
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    final cuerpo = _decodeBody(res);
    final resultados = cuerpo['resultados'] as List<dynamic>;
    return ResultadoCarga(
      despachoCorte: cuerpo['despacho_corte'] as String?,
      resultados: [
        for (final r in resultados.cast<Map<String, dynamic>>())
          r['guia'] is Map<String, dynamic>
              ? ResultadoRegistro.guia(
                  Guia.fromJson(r['guia'] as Map<String, dynamic>),
                )
              : ResultadoRegistro.error(
                  r['error'] as String? ?? 'No se pudo registrar.',
                ),
      ],
    );
  }

  /// Llegada de un Despacho Corte: todas sus guías en camino quedan
  /// entregadas a la vez (sin foto). Devuelve las guías actualizadas.
  Future<List<Guia>> llegadaDespachoCorte(
    String codigo, {
    required double lat,
    required double lng,
    required String transportista,
  }) async {
    final res = await _client.post(
      Uri.parse(
        '$apiBaseUrl/despachos-corte/${Uri.encodeComponent(codigo)}/llegada',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'geo': {'lat': lat, 'lng': lng},
        'transportista': transportista,
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return [
      for (final g
          in (_decodeBody(res)['guias'] as List<dynamic>)
              .cast<Map<String, dynamic>>())
        Guia.fromJson(g),
    ];
  }

  /// Saca una guía de su Despacho Corte: sigue como tarea normal.
  Future<Guia> quitarDeDespachoCorte(Guia guia) async {
    final res = await _client.post(
      Uri.parse(
        '$apiBaseUrl/despachos-corte/'
        '${Uri.encodeComponent(guia.despachoCorte)}/quitar',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'numeroGuia': guia.numeroGuia,
        'fechaCreacion': _fechaCreacion(guia),
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
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
    // El backend devuelve la guía completa; si es uno antiguo que solo
    // manda {numeroGuia, estado}, se recarga la lista para obtenerla.
    final cuerpo = jsonDecode(res.body);
    if (cuerpo is Map<String, dynamic> && cuerpo['numero_guia'] is String) {
      return Guia.fromJson(cuerpo);
    }
    final guia = await buscarGuiaExacta(numeroGuia);
    if (guia == null) {
      throw ApiException('La guía se creó pero no se pudo recargar.');
    }
    return guia;
  }

  /// El registro más reciente con ese número.
  Future<Guia?> buscarGuiaExacta(String numeroGuia) async {
    Guia? encontrada;
    for (final g in await listarGuias()) {
      if (g.numeroGuia == numeroGuia &&
          (encontrada == null ||
              !g.fechaCreacion.isBefore(encontrada.fechaCreacion))) {
        encontrada = g;
      }
    }
    return encontrada;
  }

  /// Devuelve la guía actualizada y, si la foto no se pudo guardar, el
  /// aviso del backend (el estado cambia igual).
  Future<(Guia, String?)> actualizarEstado(
    String numeroGuia,
    EstadoGuia nuevoEstado, {
    double? lat,
    double? lng,
    bool porAdmin = false,
    Uint8List? foto,
    DateTime? fechaCreacion,
    LecturaComprobante? comprobante,
  }) async {
    final res = await _client.patch(
      Uri.parse('$apiBaseUrl/guias/$numeroGuia/estado'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'estado': nuevoEstado.valorApi,
        'porAdmin': porAdmin,
        if (fechaCreacion != null)
          'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
        if (lat != null && lng != null) 'geo': {'lat': lat, 'lng': lng},
        if (foto != null) 'foto': _fotoJson(foto),
        // Ya leído por la app (aunque no haya): el backend no lo vuelve a
        // pedir a la IA. Si no viene, lo lee él de la foto.
        if (comprobante != null) 'comprobante': comprobante.$1?.toJson(),
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    final json = _decodeBody(res);
    return (Guia.fromJson(json), json['aviso_foto'] as String?);
  }

  /// Si el backend tiene conectado el almacenamiento de fotos.
  Future<bool> almacenamientoFotosConfigurado() async {
    final res = await _client.get(Uri.parse('$apiBaseUrl/fotos/estado'));
    if (res.statusCode != 200) _lanzarError(res);
    return _decodeBody(res)['configurado'] == true;
  }

  /// El transportista rechaza una tarea abierta con un motivo. El GPS va si
  /// se pudo leer (no es obligatorio para rechazar).
  Future<Guia> rechazarGuia(
    String numeroGuia,
    String motivo, {
    double? lat,
    double? lng,
    DateTime? fechaCreacion,
  }) async {
    final res = await _client.post(
      Uri.parse('$apiBaseUrl/guias/${Uri.encodeComponent(numeroGuia)}/rechazo'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'motivo': motivo,
        if (fechaCreacion != null)
          'fechaCreacion': fechaCreacion.toUtc().toIso8601String(),
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

  /// Identifica el registro exacto aunque el número se repita.
  static String _fechaCreacion(Guia g) =>
      g.fechaCreacion.toUtc().toIso8601String();

  String _rutaGuia(Guia g, [String sufijo = '']) =>
      '$apiBaseUrl/guias/${Uri.encodeComponent(g.numeroGuia)}$sufijo';

  /// Cambia el tipo de entrega (el transportista, solo en ruta). Para
  /// "entre sucursales" [destino] es el nombre de la sucursal.
  Future<Guia> cambiarTipoEntrega(
    Guia guia,
    TipoEntrega tipo, {
    String? destino,
    bool porAdmin = false,
  }) async {
    final res = await _client.patch(
      Uri.parse(_rutaGuia(guia, '/tipo')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tipoEntrega': tipo.valorApi,
        'destino': ?destino,
        'porAdmin': porAdmin,
        'fechaCreacion': _fechaCreacion(guia),
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  /// El transportista pide borrar la tarea; decide el administrador.
  Future<Guia> pedirEliminacion(Guia guia, String motivo) async {
    final res = await _client.post(
      Uri.parse(_rutaGuia(guia, '/solicitud-eliminacion')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'motivo': motivo,
        'fechaCreacion': _fechaCreacion(guia),
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  /// El transportista retira su pedido de eliminación.
  Future<Guia> retirarPedidoEliminacion(Guia guia) async {
    final res = await _client.delete(
      Uri.parse(_rutaGuia(guia, '/solicitud-eliminacion'))
          .replace(queryParameters: {'fechaCreacion': _fechaCreacion(guia)}),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  /// El administrador no aprueba borrar la tarea.
  Future<Guia> rechazarEliminacion(Guia guia) async {
    final res = await _client.post(
      Uri.parse(_rutaGuia(guia, '/solicitud-eliminacion/rechazo')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fechaCreacion': _fechaCreacion(guia)}),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  /// Los transportistas activos (para elegir a quién pasar una tarea).
  Future<List<String>> listarTransportistas() async {
    final res = await _client.get(Uri.parse('$apiBaseUrl/transportistas'));
    if (res.statusCode != 200) _lanzarError(res);
    final lista = jsonDecode(res.body) as List<dynamic>;
    return [
      for (final e in lista) (e as Map<String, dynamic>)['nombre'] as String,
    ];
  }

  /// [de] pasa la tarea a [a]; queda pendiente hasta que [a] responda.
  Future<Guia> pedirTransbordo(
    Guia guia, {
    required String de,
    required String a,
  }) async {
    final res = await _client.post(
      Uri.parse(_rutaGuia(guia, '/transbordo')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'de': de,
        'a': a,
        'fechaCreacion': _fechaCreacion(guia),
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  /// Quien envió el transbordo lo cancela.
  Future<Guia> cancelarTransbordo(Guia guia) async {
    final res = await _client.delete(
      Uri.parse(_rutaGuia(guia, '/transbordo'))
          .replace(queryParameters: {'fechaCreacion': _fechaCreacion(guia)}),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  /// [quien] acepta o rechaza el transbordo que le enviaron.
  Future<Guia> responderTransbordo(
    Guia guia, {
    required String quien,
    required bool acepta,
  }) async {
    final res = await _client.post(
      Uri.parse(_rutaGuia(guia, '/transbordo/respuesta')),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'quien': quien,
        'acepta': acepta,
        'fechaCreacion': _fechaCreacion(guia),
      }),
    );
    if (res.statusCode != 200) _lanzarError(res);
    return Guia.fromJson(_decodeBody(res));
  }

  /// Borra la tarea de la hoja (administrador; solo en ruta).
  Future<void> eliminarGuia(Guia guia) async {
    final res = await _client.delete(
      Uri.parse(_rutaGuia(guia))
          .replace(queryParameters: {'fechaCreacion': _fechaCreacion(guia)}),
    );
    if (res.statusCode != 200) _lanzarError(res);
  }

  /// Quita la foto de la entrega (administrador). Devuelve la guía y, si el
  /// archivo no se pudo borrar, el aviso.
  Future<(Guia, String?)> eliminarFotoEntrega(Guia guia) async {
    final res = await _client.delete(
      Uri.parse(_rutaGuia(guia, '/foto'))
          .replace(queryParameters: {'fechaCreacion': _fechaCreacion(guia)}),
    );
    if (res.statusCode != 200) _lanzarError(res);
    final json = _decodeBody(res);
    return (Guia.fromJson(json), json['aviso_foto'] as String?);
  }
}

/// Guías que se pueden registrar de una vez (lo mismo valida el backend).
const maxGuiasPorCarga = 30;

/// Una guía por registrar en una carga masiva (POST /guias/lote).
class GuiaNueva {
  const GuiaNueva({
    required this.numeroGuia,
    required this.tipoEntrega,
    required this.origen,
    required this.destino,
    required this.transportista,
    required this.destinatario,
    required this.lat,
    required this.lng,
    this.numeroPedido = '',
    this.numeroEntrega = '',
    this.comprobante,
  });

  final String numeroGuia;
  final TipoEntrega tipoEntrega;
  final String origen;
  final String destino;
  final String transportista;
  final String destinatario;
  final double lat;
  final double lng;
  final String numeroPedido;
  final String numeroEntrega;

  /// El comprobante de agencia leído de la foto (null si no hay).
  final ComprobanteAgencia? comprobante;

  Map<String, dynamic> toJson() => {
    'numeroGuia': numeroGuia,
    'tipoEntrega': tipoEntrega.valorApi,
    'origen': origen,
    'destino': destino,
    'transportista': transportista,
    'destinatario': destinatario,
    'geo': {'lat': lat, 'lng': lng},
    if (numeroPedido.isNotEmpty) 'numeroPedido': numeroPedido,
    if (numeroEntrega.isNotEmpty) 'numeroEntrega': numeroEntrega,
    if (comprobante case final c?) 'comprobante': c.toJson(),
  };
}

/// El comprobante que la app ya leyó de una foto de entrega: `(null,)` si
/// la IA no encontró ninguno. Se manda para que el backend no lo vuelva a
/// leer.
typedef LecturaComprobante = (ComprobanteAgencia?,);

/// Resultado de una carga masiva: el de cada guía, en orden, y el código
/// del Despacho Corte si fue uno (null si ninguna se registró).
class ResultadoCarga {
  const ResultadoCarga({required this.resultados, this.despachoCorte});

  final List<ResultadoRegistro> resultados;
  final String? despachoCorte;
}

/// Lo que pasó con una guía de la carga masiva: creada o con su error.
class ResultadoRegistro {
  const ResultadoRegistro.guia(Guia this.guia) : error = null;
  const ResultadoRegistro.error(String this.error) : guia = null;

  final Guia? guia;
  final String? error;
}
