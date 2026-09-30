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

  /// Cuándo se asignó (salió del almacén). Si la hoja no la tiene, se usa
  /// la fecha de actualización.
  final DateTime fechaCreacion;
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

  /// Dónde quedó la foto de la entrega en el almacenamiento privado (vacío
  /// si no hay). La app no la abre directo: usa `urlFotoEntrega`, que pasa
  /// por el backend.
  final String fotoEntregaUrl;

  /// Por qué el transportista rechazó la tarea (vacío si no la rechazó).
  final String motivoRechazo;

  /// El transportista pidió borrar la tarea: 'pendiente' mientras el
  /// administrador decide, 'rechazada' si no lo aprobó; vacío si no.
  final String eliminacion;
  final String motivoEliminacion;

  /// Transbordo a otro transportista: 'pendiente' mientras [transbordoA]
  /// decide, 'rechazado' si no la aceptó (sigue con quien la envió),
  /// 'aceptado' si la tomó ([transbordoDe] es quien se la pasó); vacío si no.
  final String transbordoEstado;
  final String transbordoA;
  final String transbordoDe;

  const Guia({
    required this.numeroGuia,
    required this.estado,
    required this.tipoEntrega,
    required this.origen,
    required this.destino,
    required this.transportista,
    required this.destinatario,
    required this.fechaActualizacion,
    DateTime? fechaCreacion,
    this.corregidoPorAdmin = false,
    this.numeroPedido = '',
    this.numeroEntrega = '',
    this.ultimaLat,
    this.ultimaLng,
    this.cierreLat,
    this.cierreLng,
    this.fechaCierre,
    this.fotoEntregaUrl = '',
    this.motivoRechazo = '',
    this.eliminacion = '',
    this.motivoEliminacion = '',
    this.transbordoEstado = '',
    this.transbordoA = '',
    this.transbordoDe = '',
  }) : fechaCreacion = fechaCreacion ?? fechaActualizacion;

  bool get tieneFotoEntrega => fotoEntregaUrl.isNotEmpty;

  bool get eliminacionPendiente => eliminacion == 'pendiente';
  bool get eliminacionRechazada => eliminacion == 'rechazada';

  bool get transbordoPendiente => transbordoEstado == 'pendiente';
  bool get transbordoRechazado => transbordoEstado == 'rechazado';
  bool get transbordoAceptado => transbordoEstado == 'aceptado';

  /// El transbordo en una línea, para el administrador y el rastreo (vacío
  /// si no hubo).
  String get resumenTransbordo {
    if (transbordoPendiente) {
      return 'Transbordo a $transbordoA · esperando que acepte';
    }
    if (transbordoRechazado) return '$transbordoA no aceptó el transbordo';
    if (transbordoAceptado && transbordoDe.isNotEmpty) {
      return 'Transbordo: $transbordoDe → $transportista';
    }
    return '';
  }

  /// Otro transportista le quiere pasar esta tarea a [nombre].
  bool esTransbordoPara(String nombre) =>
      transbordoPendiente &&
      transbordoA.trim().toLowerCase() == nombre.trim().toLowerCase();

  /// Solo una tarea en ruta se puede borrar (o cambiar de tipo).
  bool get esEditablePorTransportista => estado == EstadoGuia.enRuta;

  /// Identifica este registro aunque el mismo número de guía se haya
  /// registrado más de una vez (otro viaje, con 2 horas de diferencia).
  String get clave => '$numeroGuia|${fechaCreacion.toUtc().toIso8601String()}';

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
      fechaCreacion: DateTime.tryParse(json['fecha_creacion'] as String? ?? ''),
      corregidoPorAdmin: json['corregido_por_admin'] == true,
      numeroPedido: json['numero_pedido'] as String? ?? '',
      numeroEntrega: json['numero_entrega'] as String? ?? '',
      ultimaLat: _coordenada(json['geo_lat']),
      ultimaLng: _coordenada(json['geo_lng']),
      cierreLat: _coordenada(json['cierre_lat']),
      cierreLng: _coordenada(json['cierre_lng']),
      fechaCierre: DateTime.tryParse(json['fecha_cierre'] as String? ?? ''),
      fotoEntregaUrl: json['foto_entrega_url'] as String? ?? '',
      motivoRechazo: json['motivo_rechazo'] as String? ?? '',
      eliminacion: (json['eliminacion'] as String? ?? '').trim(),
      motivoEliminacion: json['motivo_eliminacion'] as String? ?? '',
      transbordoEstado: (json['transbordo_estado'] as String? ?? '').trim(),
      transbordoA: (json['transbordo_a'] as String? ?? '').trim(),
      transbordoDe: (json['transbordo_de'] as String? ?? '').trim(),
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
      fechaCreacion: fechaCreacion,
      corregidoPorAdmin: corregidoPorAdmin ?? this.corregidoPorAdmin,
      numeroPedido: numeroPedido ?? this.numeroPedido,
      numeroEntrega: numeroEntrega ?? this.numeroEntrega,
      ultimaLat: ultimaLat,
      ultimaLng: ultimaLng,
      cierreLat: cierreLat,
      cierreLng: cierreLng,
      fechaCierre: fechaCierre,
      fotoEntregaUrl: fotoEntregaUrl,
      motivoRechazo: motivoRechazo,
      eliminacion: eliminacion,
      motivoEliminacion: motivoEliminacion,
      transbordoEstado: transbordoEstado,
      transbordoA: transbordoA,
      transbordoDe: transbordoDe,
    );
  }
}
