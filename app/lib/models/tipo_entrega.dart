enum TipoEntrega { clienteFinal, agencia, entreSucursales }

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
