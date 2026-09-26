import 'estado_guia.dart';
import 'tipo_entrega.dart';

/// Modelo de una guía de despacho, equivalente a una fila de la hoja de
/// tareas descrita en ARCHITECTURE.md (sección 3).
class Guia {
  final String numeroGuia;
  final EstadoGuia estado;
  final TipoEntrega tipoEntrega;
  final String origen;
  final String destino;
  final String transportista;
  final String destinatario;
  final DateTime fechaActualizacion;
  final bool corregidoPorAdmin;
  final String numeroPedido;
  final String numeroEntrega;

  /// Ubicación del último evento registrado (asignación o entrega).
  final double? ultimaLat;
  final double? ultimaLng;

  /// Dónde y cuándo el transportista cerró la guía (entregado/finalizado).
  /// Null si sigue abierta o si la cerró un administrador a mano.
  final double? cierreLat;
  final double? cierreLng;
  final DateTime? fechaCierre;

  const Guia({
    required this.numeroGuia,
    required this.estado,
    required this.tipoEntrega,
    required this.origen,
    required this.destino,
    required this.transportista,
    required this.destinatario,
    required this.fechaActualizacion,
    this.corregidoPorAdmin = false,
    this.numeroPedido = '',
    this.numeroEntrega = '',
    this.ultimaLat,
    this.ultimaLng,
    this.cierreLat,
    this.cierreLng,
    this.fechaCierre,
  });

  bool get tieneUbicacionCierre => cierreLat != null && cierreLng != null;

  String get ultimosCuatroDigitos {
    final soloDigitos = numeroGuia.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.length <= 4) return soloDigitos;
    return soloDigitos.substring(soloDigitos.length - 4);
  }

  /// Parsea la respuesta JSON de la API (ver backend/src/app.js).
  factory Guia.fromJson(Map<String, dynamic> json) {
    return Guia(
      numeroGuia: json['numero_guia'] as String,
      estado: estadoGuiaDesdeApi(json['estado'] as String),
      tipoEntrega: tipoEntregaDesdeApi(json['tipo_entrega'] as String),
      origen: json['origen'] as String,
      destino: json['destino'] as String,
      transportista: json['transportista'] as String,
      destinatario: json['destinatario'] as String,
      fechaActualizacion: DateTime.parse(json['fecha_actualizacion'] as String),
      corregidoPorAdmin: json['corregido_por_admin'] == true,
      numeroPedido: json['numero_pedido'] as String? ?? '',
      numeroEntrega: json['numero_entrega'] as String? ?? '',
      ultimaLat: _coordenada(json['geo_lat']),
      ultimaLng: _coordenada(json['geo_lng']),
      cierreLat: _coordenada(json['cierre_lat']),
      cierreLng: _coordenada(json['cierre_lng']),
      fechaCierre: DateTime.tryParse(json['fecha_cierre'] as String? ?? ''),
    );
  }

  // Sheets devuelve los números como texto formateado, y según el idioma de
  // la hoja puede usar coma decimal ("-12,05").
  static double? _coordenada(Object? valor) {
    if (valor is num) return valor.toDouble();
    if (valor is! String || valor.trim().isEmpty) return null;
    return double.tryParse(valor.trim().replaceAll(',', '.'));
  }

  Guia copyWith({
    String? numeroGuia,
    EstadoGuia? estado,
    TipoEntrega? tipoEntrega,
    String? origen,
    String? destino,
    String? transportista,
    String? destinatario,
    DateTime? fechaActualizacion,
    bool? corregidoPorAdmin,
    String? numeroPedido,
    String? numeroEntrega,
  }) {
    return Guia(
      numeroGuia: numeroGuia ?? this.numeroGuia,
      estado: estado ?? this.estado,
      tipoEntrega: tipoEntrega ?? this.tipoEntrega,
      origen: origen ?? this.origen,
      destino: destino ?? this.destino,
      transportista: transportista ?? this.transportista,
      destinatario: destinatario ?? this.destinatario,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
      corregidoPorAdmin: corregidoPorAdmin ?? this.corregidoPorAdmin,
      numeroPedido: numeroPedido ?? this.numeroPedido,
      numeroEntrega: numeroEntrega ?? this.numeroEntrega,
      ultimaLat: ultimaLat,
      ultimaLng: ultimaLng,
      cierreLat: cierreLat,
      cierreLng: cierreLng,
      fechaCierre: fechaCierre,
    );
  }
}
