import 'package:flutter/material.dart';

/// Estados del ciclo de vida de una guía, según ARCHITECTURE.md.
enum EstadoGuia {
  enRuta,
  enProcesoTrasbordo,
  recepcionSucursal,
  entregado,
  finalizado,
}

extension EstadoGuiaX on EstadoGuia {
  String get etiqueta {
    switch (this) {
      case EstadoGuia.enRuta:
        return 'En ruta';
      case EstadoGuia.enProcesoTrasbordo:
        return 'En proceso de trasbordo';
      case EstadoGuia.recepcionSucursal:
        return 'Recepción en sucursal';
      case EstadoGuia.entregado:
        return 'Entregado';
      case EstadoGuia.finalizado:
        return 'Finalizado';
    }
  }

  Color get color {
    switch (this) {
      case EstadoGuia.enRuta:
        return Colors.blue;
      case EstadoGuia.enProcesoTrasbordo:
        return Colors.orange;
      case EstadoGuia.recepcionSucursal:
        return Colors.purple;
      case EstadoGuia.entregado:
        return Colors.green;
      case EstadoGuia.finalizado:
        return Colors.grey;
    }
  }

  GrupoEstado get grupo {
    switch (this) {
      case EstadoGuia.enRuta:
        return GrupoEstado.enRuta;
      case EstadoGuia.enProcesoTrasbordo:
      case EstadoGuia.recepcionSucursal:
        return GrupoEstado.trasbordo;
      case EstadoGuia.entregado:
      case EstadoGuia.finalizado:
        return GrupoEstado.entregado;
    }
  }

  bool get esFinal =>
      this == EstadoGuia.entregado || this == EstadoGuia.finalizado;

  /// Valor tal como lo espera/devuelve la API (backend/src/columns.js).
  String get valorApi {
    switch (this) {
      case EstadoGuia.enRuta:
        return 'en_ruta';
      case EstadoGuia.enProcesoTrasbordo:
        return 'en_proceso_trasbordo';
      case EstadoGuia.recepcionSucursal:
        return 'recepcion_sucursal';
      case EstadoGuia.entregado:
        return 'entregado';
      case EstadoGuia.finalizado:
        return 'finalizado';
    }
  }
}

/// Agrupación simplificada para el panel del administrador: los 5 estados
/// internos se mantienen, pero el admin solo filtra por estos 3.
enum GrupoEstado { enRuta, trasbordo, entregado }

extension GrupoEstadoX on GrupoEstado {
  String get etiqueta {
    switch (this) {
      case GrupoEstado.enRuta:
        return 'En ruta';
      case GrupoEstado.trasbordo:
        return 'Trasbordo';
      case GrupoEstado.entregado:
        return 'Entregado';
    }
  }
}

EstadoGuia estadoGuiaDesdeApi(String valor) {
  return EstadoGuia.values.firstWhere(
    (e) => e.valorApi == valor,
    orElse: () => throw FormatException('Estado desconocido: $valor'),
  );
}
