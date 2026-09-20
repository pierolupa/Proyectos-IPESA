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
}
