import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/rol_usuario.dart';
import '../models/tipo_entrega.dart';

/// Estado en memoria de la app de demostración. Sustituye al backend +
/// Google Sheets descritos en ARCHITECTURE.md; toda la data es local y se
/// reinicia al recargar la app.
class AppState extends ChangeNotifier {
  AppState() : _guias = guiasIniciales();

  final List<Guia> _guias;
  RolUsuario? _rolActual;

  List<Guia> get guias => List.unmodifiable(_guias);
  RolUsuario? get rolActual => _rolActual;
  String get transportistaActual => transportistaActualDemo;

  void seleccionarRol(RolUsuario rol) {
    _rolActual = rol;
    notifyListeners();
  }

  void cerrarSesion() {
    _rolActual = null;
    notifyListeners();
  }

  List<Guia> guiasDelTransportista(String nombre) {
    return _guias.where((g) => g.transportista == nombre).toList()
      ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));
  }

  Guia? buscarPorNumero(String numeroGuia) {
    for (final g in _guias) {
      if (g.numeroGuia == numeroGuia) return g;
    }
    return null;
  }

  /// Simula el validador de duplicados: un número de guía ya activo
  /// (no finalizado ni entregado) no puede volver a asignarse como
  /// "en ruta".
  bool esDuplicado(String numeroGuia) {
    return _guias.any(
      (g) => g.numeroGuia == numeroGuia && !g.estado.esFinal,
    );
  }

  /// Asignación: crea una tarea "en ruta" a partir del número de guía
  /// extraído por OCR (o corregido manualmente antes de confirmar).
  Guia asignarNuevaGuia({
    required String numeroGuia,
    required String destino,
    required String destinatario,
  }) {
    final nueva = Guia(
      numeroGuia: numeroGuia,
      estado: EstadoGuia.enRuta,
      tipoEntrega: TipoEntrega.clienteFinal,
      origen: 'Almacén Callao',
      destino: destino,
      transportista: transportistaActual,
      destinatario: destinatario,
      fechaActualizacion: DateTime.now(),
    );
    _guias.insert(0, nueva);
    notifyListeners();
    return nueva;
  }

  void actualizarEstado(
    String numeroGuia,
    EstadoGuia nuevoEstado, {
    bool porAdmin = false,
  }) {
    final index = _guias.indexWhere((g) => g.numeroGuia == numeroGuia);
    if (index == -1) return;
    _guias[index] = _guias[index].copyWith(
      estado: nuevoEstado,
      fechaActualizacion: DateTime.now(),
      corregidoPorAdmin: porAdmin ? true : _guias[index].corregidoPorAdmin,
    );
    notifyListeners();
  }

  /// Corrección manual del número de guía por un administrador, para los
  /// casos en que el OCR no extrajo correctamente el dato (ver sección 5
  /// de ARCHITECTURE.md).
  void corregirNumeroGuia(String numeroAnterior, String numeroNuevo) {
    final index = _guias.indexWhere((g) => g.numeroGuia == numeroAnterior);
    if (index == -1) return;
    _guias[index] = _guias[index].copyWith(
      numeroGuia: numeroNuevo,
      corregidoPorAdmin: true,
      fechaActualizacion: DateTime.now(),
    );
    notifyListeners();
  }

  List<Guia> buscarPorUltimosCuatroDigitos(String ultimosCuatro) {
    return _guias
        .where((g) => g.ultimosCuatroDigitos == ultimosCuatro)
        .toList();
  }
}
