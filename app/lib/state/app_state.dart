import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/rol_usuario.dart';
import '../models/sucursal.dart';
import '../models/tipo_entrega.dart';
import '../services/guias_api.dart';

const _prefNombre = 'sesion_nombre';
const _prefRol = 'sesion_rol';

/// Estado de la app respaldado por la API real (ver ../services/guias_api.dart).
/// Mantiene una copia en memoria de las guías para que las pantallas no
/// tengan que repetir la llamada de red en cada rebuild.
class AppState extends ChangeNotifier {
  AppState({GuiasApi? api}) : _api = api ?? GuiasApi();

  final GuiasApi _api;

  List<Guia> _guias = [];
  List<Sucursal> _sucursales = [];
  bool cargando = false;
  String? error;
  RolUsuario? _rolActual;
  String? _nombreUsuario;

  List<Guia> get guias => List.unmodifiable(_guias);
  List<Sucursal> get sucursales => List.unmodifiable(_sucursales);
  RolUsuario? get rolActual => _rolActual;

  /// Nombre del transportista/administrador con sesión iniciada. Vacío
  /// para el rol Comercial, que no requiere login.
  String get transportistaActual => _nombreUsuario ?? '';

  /// Login simple contra la hoja "Usuarios" (ver backend/README.md — no
  /// es un mecanismo de autenticación real, ver la advertencia ahí).
  /// Deja que el ApiException se propague para que la pantalla de login
  /// muestre el mensaje de error.
  Future<void> iniciarSesion(String nombre, String pin) async {
    await _establecerSesion(await _api.login(nombre, pin));
  }

  /// Auto-registro; siempre crea la cuenta como transportista (ver
  /// backend/src/app.js).
  Future<void> registrarUsuario(String nombre, String pin) async {
    await _establecerSesion(await _api.registrar(nombre, pin));
  }

  Future<void> _establecerSesion(SesionUsuario sesion) async {
    _nombreUsuario = sesion.nombre;
    _rolActual = sesion.rol;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNombre, sesion.nombre);
    await prefs.setString(_prefRol, sesion.rol.name);
    await cargarGuias();
  }

  /// Restaura la sesión guardada (si hay una) al abrir la app — sin esto,
  /// recargar la página siempre volvía al login aunque ya se hubiera
  /// iniciado sesión antes, porque el estado solo vivía en memoria.
  /// No hace nada si no hay nada guardado (deja `rolActual` en null).
  Future<void> restaurarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final nombre = prefs.getString(_prefNombre);
    final rolTexto = prefs.getString(_prefRol);
    if (nombre == null || rolTexto == null) return;

    final rol = RolUsuario.values.asNameMap()[rolTexto];
    if (rol != RolUsuario.transportista && rol != RolUsuario.administrador) {
      return;
    }

    _nombreUsuario = nombre;
    _rolActual = rol;
    notifyListeners();
    await cargarGuias();
  }

  /// El rol Comercial no requiere login (ver ARCHITECTURE.md, sección 6).
  void entrarComoComercial() {
    _rolActual = RolUsuario.comercial;
    notifyListeners();
  }

  Future<void> cerrarSesion() async {
    _rolActual = null;
    _nombreUsuario = null;
    _guias = [];
    _sucursales = [];
    error = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefNombre);
    await prefs.remove(_prefRol);
  }

  Future<void> cargarGuias() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      _guias = await _api.listarGuias();
    } catch (e) {
      error = e.toString();
    }
    // Las sucursales son secundarias: si fallan no bloquean la lista.
    try {
      _sucursales = await _api.listarSucursales();
    } catch (_) {
      _sucursales = [];
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  Sucursal? sucursalPorNombre(String nombre) {
    final clave = nombre.trim().toLowerCase();
    for (final s in _sucursales) {
      if (s.nombre.toLowerCase() == clave) return s;
    }
    return null;
  }

  Future<void> guardarSucursal(Sucursal sucursal) async {
    await _api.guardarSucursal(sucursal);
    _sucursales = await _api.listarSucursales();
    notifyListeners();
  }

  Future<void> eliminarSucursal(String nombre) async {
    await _api.eliminarSucursal(nombre);
    _sucursales = await _api.listarSucursales();
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

  /// Validación local rápida (sin llamada de red) contra la última lista
  /// cargada. La validación definitiva la hace el backend al confirmar
  /// (responde 409 si hay conflicto).
  bool esDuplicado(String numeroGuia) {
    return _guias.any(
      (g) => g.numeroGuia == numeroGuia && !g.estado.esFinal,
    );
  }

  /// Lee los datos de la foto de una guía con IA (ver
  /// ../services/guias_api.dart). No toca `_guias`/no notifica — es solo
  /// para pre-llenar el formulario de asignación.
  Future<DatosGuiaLeida> leerGuiaConIA(Uint8List fotoBytes) =>
      _api.leerGuiaConIA(fotoBytes);

  Future<Guia> asignarNuevaGuia({
    required String numeroGuia,
    required TipoEntrega tipoEntrega,
    required String origen,
    required String destino,
    required String destinatario,
    required double lat,
    required double lng,
    String? numeroPedido,
    String? numeroEntrega,
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
      numeroPedido: numeroPedido,
      numeroEntrega: numeroEntrega,
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
