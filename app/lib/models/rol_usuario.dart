enum RolUsuario { transportista, administrador, comercial }

extension RolUsuarioX on RolUsuario {
  String get etiqueta {
    switch (this) {
      case RolUsuario.transportista:
        return 'Transportista';
      case RolUsuario.administrador:
        return 'Administrador';
      case RolUsuario.comercial:
        return 'Equipo Comercial';
    }
  }

  String get descripcion {
    switch (this) {
      case RolUsuario.transportista:
        return 'Captura guías, registra entregas y actualiza estados en ruta.';
      case RolUsuario.administrador:
        return 'Supervisa todas las tareas y corrige datos manualmente.';
      case RolUsuario.comercial:
        return 'Rastrea envíos con los últimos 4 dígitos de la guía.';
    }
  }
}
