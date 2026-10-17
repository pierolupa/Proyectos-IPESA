enum TipoEntrega { clienteFinal, agencia, entreSucursales }

/// Tipos que se pueden elegir al registrar o cambiar una guía. "Entre
/// sucursales" ya no se ofrece (la sucursal se detecta sola por GPS); solo
/// se conserva para mostrar y terminar las guías antiguas de ese tipo.
const tiposEntregaElegibles = [TipoEntrega.clienteFinal, TipoEntrega.agencia];

extension TipoEntregaX on TipoEntrega {
  String get etiqueta {
    switch (this) {
      case TipoEntrega.clienteFinal:
        return 'Cliente final';
      case TipoEntrega.agencia:
        return 'Agencia';
      case TipoEntrega.entreSucursales:
        return 'Entre sucursales';
    }
  }

  /// Valor tal como lo espera/devuelve la API (backend/src/columns.js).
  String get valorApi {
    switch (this) {
      case TipoEntrega.clienteFinal:
        return 'cliente_final';
      case TipoEntrega.agencia:
        return 'agencia';
      case TipoEntrega.entreSucursales:
        return 'entre_sucursales';
    }
  }
}

TipoEntrega tipoEntregaDesdeApi(String valor) {
  return TipoEntrega.values.firstWhere(
    (e) => e.valorApi == valor,
    orElse: () => throw FormatException('Tipo de entrega desconocido: $valor'),
  );
}
