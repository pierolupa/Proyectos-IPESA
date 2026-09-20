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
  });

  String get ultimosCuatroDigitos {
    final soloDigitos = numeroGuia.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.length <= 4) return soloDigitos;
    return soloDigitos.substring(soloDigitos.length - 4);
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
    );
  }
}
