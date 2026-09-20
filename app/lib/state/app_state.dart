import 'package:flutter/foundation.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/rol_usuario.dart';
import '../models/tipo_entrega.dart';
import '../services/guias_api.dart';

/// Nombre del transportista "logueado". No hay autenticación real todavía
/// (ver ARCHITECTURE.md, sección 8 — decisión pendiente), así que se usa
/// un valor fijo para esta demo.
const transportistaActualDemo = 'Juan Pérez';

/// Estado de la app respaldado por la API real (ver ../services/guias_api.dart).
/// Mantiene una copia en memoria de las guías para que las pantallas no
/// tengan que repetir la llamada de red en cada rebuild.
class AppState extends ChangeNotifier {
  AppState({GuiasApi? api}) : _api = api ?? GuiasApi();

  final GuiasApi _api;

  List<Guia> _guias = [];
  bool cargando = false;
  String? error;
  RolUsuario? _rolActual;

  List<Guia> get guias => List.unmodifiable(_guias);
  RolUsuario? get rolActual => _rolActual;
  String get transportistaActual => transportistaActualDemo;

  void seleccionarRol(RolUsuario rol) {
    _rolActual = rol;
    notifyListeners();
    if (rol == RolUsuario.transportista || rol == RolUsuario.administrador) {
      cargarGuias();
    }
  }

  void cerrarSesion() {
    _rolActual = null;
    notifyListeners();
  }

  Future<void> cargarGuias() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      _guias = await _api.listarGuias();
    } catch (e) {
      error = e.toString();
    } finally {
      cargando = false;
      notifyListeners();
    }
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

  /// Validación local rápida (sin llamada de red) contra la última lista
  /// cargada. La validación definitiva la hace el backend al confirmar
  /// (responde 409 si hay conflicto).
  bool esDuplicado(String numeroGuia) {
    return _guias.any(
      (g) => g.numeroGuia == numeroGuia && !g.estado.esFinal,
    );
  }

  Future<Guia> asignarNuevaGuia({
    required String numeroGuia,
    required TipoEntrega tipoEntrega,
    required String origen,
    required String destino,
    required String destinatario,
    required double lat,
    required double lng,
  }) async {
    final nueva = await _api.asignarNuevaGuia(
      numeroGuia: numeroGuia,
      tipoEntrega: tipoEntrega,
      origen: origen,
      destino: destino,
      transportista: transportistaActual,
      destinatario: destinatario,
      lat: lat,
      lng: lng,
    );
    _guias.insert(0, nueva);
    notifyListeners();
    return nueva;
  }

  Future<void> actualizarEstado(
    String numeroGuia,
    EstadoGuia nuevoEstado, {
    double? lat,
    double? lng,
    bool porAdmin = false,
  }) async {
    final actualizada = await _api.actualizarEstado(
      numeroGuia,
      nuevoEstado,
      lat: lat,
      lng: lng,
      porAdmin: porAdmin,
    );
    final index = _guias.indexWhere((g) => g.numeroGuia == numeroGuia);
    if (index != -1) {
      _guias[index] = actualizada;
    }
    notifyListeners();
  }

  Future<void> corregirNumeroGuia(
    String numeroAnterior,
    String numeroNuevo,
  ) async {
    final actualizada = await _api.corregirNumeroGuia(
      numeroAnterior,
      numeroNuevo,
    );
    final index = _guias.indexWhere((g) => g.numeroGuia == numeroAnterior);
    if (index != -1) {
      _guias[index] = actualizada;
    }
    notifyListeners();
  }
}
