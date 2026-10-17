import 'package:flutter/material.dart';

/// Estados del ciclo de vida de una guía, según ARCHITECTURE.md.
enum EstadoGuia {
  enRuta,
  enProcesoTrasbordo,
  recepcionSucursal,
  entregado,
  finalizado,

  /// El transportista no pudo o no quiso hacer la tarea (con motivo).
  rechazado,
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
      case EstadoGuia.rechazado:
        return 'Rechazada';
    }
  }

  Color get color {
    switch (this) {
      case EstadoGuia.enRuta:
        return const Color(0xFF2459A8);
      case EstadoGuia.enProcesoTrasbordo:
      case EstadoGuia.recepcionSucursal:
        return const Color(0xFF8A4F00);
      case EstadoGuia.entregado:
      case EstadoGuia.finalizado:
        return const Color(0xFF1D6B41);
      case EstadoGuia.rechazado:
        return const Color(0xFFB42318);
    }
  }

  Color get colorFondo {
    switch (this) {
      case EstadoGuia.enRuta:
        return const Color(0xFFE8EFFA);
      case EstadoGuia.enProcesoTrasbordo:
      case EstadoGuia.recepcionSucursal:
        return const Color(0xFFFBF0DD);
      case EstadoGuia.entregado:
      case EstadoGuia.finalizado:
        return const Color(0xFFE2F2E8);
      case EstadoGuia.rechazado:
        return const Color(0xFFFDECEA);
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
      case EstadoGuia.rechazado:
        return GrupoEstado.rechazado;
    }
  }

  /// Entregada (al cliente o en agencia). Una rechazada NO es final.
  bool get esFinal =>
      this == EstadoGuia.entregado || this == EstadoGuia.finalizado;

  /// Ya no está activa: entregada o rechazada.
  bool get esCerrada => esFinal || this == EstadoGuia.rechazado;

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
      case EstadoGuia.rechazado:
        return 'rechazado';
    }
  }
}

/// Agrupación simplificada para filtrar: los estados internos se mantienen,
/// pero el admin y el comercial solo filtran por estos.
enum GrupoEstado { enRuta, trasbordo, entregado, rechazado }

extension GrupoEstadoX on GrupoEstado {
  String get etiqueta {
    switch (this) {
      case GrupoEstado.enRuta:
        return 'En ruta';
      case GrupoEstado.trasbordo:
        return 'Trasbordo';
      case GrupoEstado.entregado:
        return 'Entregado';
      case GrupoEstado.rechazado:
        return 'Rechazada';
    }
  }
}

EstadoGuia estadoGuiaDesdeApi(String valor) {
  return EstadoGuia.values.firstWhere(
    (e) => e.valorApi == valor,
    orElse: () => throw FormatException('Estado desconocido: $valor'),
  );
}
