enum RolUsuario {
  transportista,
  administrador,
  comercial,

  /// Como el administrador, pero solo con las guías de sus transportistas
  /// (los que lo tienen de "Encargado" en la hoja Usuarios).
  subAdministrador,
}

extension RolUsuarioX on RolUsuario {
  String get etiqueta {
    switch (this) {
      case RolUsuario.transportista:
        return 'Transportista';
      case RolUsuario.administrador:
        return 'Administrador';
      case RolUsuario.comercial:
        return 'Equipo Comercial';
      case RolUsuario.subAdministrador:
        return 'Sub administrador';
    }
  }

  String get descripcion {
    switch (this) {
      case RolUsuario.transportista:
        return 'Captura guías, registra entregas y actualiza estados en ruta.';
      case RolUsuario.administrador:
        return 'Supervisa todas las tareas y corrige datos manualmente.';
      case RolUsuario.comercial:
        return 'Rastrea todas las guías con filtros de fecha, cliente, pedido y entrega.';
      case RolUsuario.subAdministrador:
        return 'Supervisa las tareas de sus transportistas y corrige sus datos.';
    }
  }
}

/// Convierte el `rol` que devuelve POST /auth/login (ver backend/README.md).
RolUsuario rolUsuarioDesdeApi(String valor) {
  switch (valor) {
    case 'transportista':
      return RolUsuario.transportista;
    case 'administrador':
      return RolUsuario.administrador;
    case 'comercial':
      return RolUsuario.comercial;
    case 'sub_administrador':
      return RolUsuario.subAdministrador;
    default:
      throw FormatException('Rol desconocido: $valor');
  }
}
