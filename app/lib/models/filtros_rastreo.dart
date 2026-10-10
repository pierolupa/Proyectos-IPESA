import 'estado_guia.dart';
import 'guia.dart';

/// Sobre qué fecha se aplica el rango del rastreo.
enum CampoFecha {
  salida('Fecha de salida'),
  entrega('Fecha de entrega');

  const CampoFecha(this.etiqueta);
  final String etiqueta;
}

/// Filtros de la vista "Rastreo de guías" del equipo comercial. Los textos
/// se buscan sin importar mayúsculas ni espacios; las fechas son días
/// completos (desde el inicio de `desde` hasta el final de `hasta`).
class FiltrosRastreo {
  const FiltrosRastreo({
    this.numeroGuia = '',
    this.cliente = '',
    this.numeroEntrega = '',
    this.numeroPedido = '',
    this.grupo,
    this.campoFecha = CampoFecha.salida,
    this.desde,
    this.hasta,
  });

  final String numeroGuia;
  final String cliente;
  final String numeroEntrega;
  final String numeroPedido;
  final GrupoEstado? grupo;
  final CampoFecha campoFecha;
  final DateTime? desde;
  final DateTime? hasta;

  bool get tieneRango => desde != null && hasta != null;

  /// Los mismos filtros con otro estado (null = todos).
  FiltrosRastreo conGrupo(GrupoEstado? nuevo) => FiltrosRastreo(
    numeroGuia: numeroGuia,
    cliente: cliente,
    numeroEntrega: numeroEntrega,
    numeroPedido: numeroPedido,
    grupo: nuevo,
    campoFecha: campoFecha,
    desde: desde,
    hasta: hasta,
  );

  static String _normalizar(String texto) =>
      texto.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static bool _contiene(String valor, String buscado) =>
      buscado.trim().isEmpty ||
      _normalizar(valor).contains(_normalizar(buscado));

  /// La fecha de la guía que se compara con el rango (en hora local), o
  /// null si no tiene (p. ej. "fecha de entrega" de una guía aún en ruta).
  DateTime? fechaDe(Guia guia) {
    switch (campoFecha) {
      case CampoFecha.salida:
        return guia.fechaCreacion.toLocal();
      case CampoFecha.entrega:
        if (guia.fechaCierre != null) return guia.fechaCierre!.toLocal();
        return guia.estado.esFinal ? guia.fechaActualizacion.toLocal() : null;
    }
  }

  bool acepta(Guia guia) {
    if (!_contiene(guia.numeroGuia, numeroGuia)) return false;
    if (!_contiene(guia.destinatario, cliente)) return false;
    if (!_contiene(guia.numeroEntrega, numeroEntrega)) return false;
    if (!_contiene(guia.numeroPedido, numeroPedido)) return false;
    if (grupo != null && guia.estado.grupo != grupo) return false;
    if (tieneRango) {
      final fecha = fechaDe(guia);
      if (fecha == null) return false;
      final inicio = DateTime(desde!.year, desde!.month, desde!.day);
      final fin = DateTime(hasta!.year, hasta!.month, hasta!.day + 1);
      if (fecha.isBefore(inicio) || !fecha.isBefore(fin)) return false;
    }
    return true;
  }

  /// Guías que pasan los filtros, de la más reciente a la más antigua.
  List<Guia> aplicar(Iterable<Guia> guias) {
    final lista = guias.where(acepta).toList();
    lista.sort((a, b) {
      final fa = fechaDe(a) ?? a.fechaActualizacion;
      final fb = fechaDe(b) ?? b.fechaActualizacion;
      return fb.compareTo(fa);
    });
    return lista;
  }
}
