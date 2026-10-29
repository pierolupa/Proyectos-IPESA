import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/despacho.dart';
import '../models/estado_guia.dart';
import '../models/guia.dart';
import '../models/rol_usuario.dart';
import '../models/sucursal.dart';
import '../models/tipo_entrega.dart';
import '../services/guias_api.dart';

const _prefNombre = 'sesion_nombre';

/// Novedad detectada al actualizar en segundo plano (para notificar al admin).
class CambioGuia {
  CambioGuia(
    this.guia,
    this.mensaje, {
    this.anterior,
    this.transbordoAntes,
    DateTime? momento,
  }) : momento = momento ?? DateTime.now();
  final Guia guia;
  final String mensaje;

  /// Estado que tenía antes; null si la guía es nueva.
  final EstadoGuia? anterior;
  final DateTime momento;

  /// Cómo estaba el transbordo antes ('' si no había).
  final String? transbordoAntes;

  bool get nueva => anterior == null;

  /// Se pidió, aceptó o rechazó un transbordo (el estado no cambió).
  bool get esTransbordo =>
      anterior != null &&
      anterior == guia.estado &&
      guia.transbordoEstado.isNotEmpty &&
      guia.transbordoEstado != (transbordoAntes ?? '');

  /// El transportista pide borrar la tarea (el estado no cambió).
  bool get pideEliminar =>
      anterior != null &&
      anterior == guia.estado &&
      !esTransbordo &&
      guia.eliminacionPendiente;
}

const _prefRol = 'sesion_rol';
const _prefToken = 'sesion_token';

// La última cuenta usada en este equipo: queda guardada aunque se cierre
// sesión, para no tener que escribir nombre y PIN cada vez.
const _prefCuentaNombre = 'cuenta_nombre';
const _prefCuentaPin = 'cuenta_pin';

/// Rastrear (y lo que se pide al servidor para el equipo comercial) busca
/// por defecto en los últimos días, hoy incluido.
const diasRastreoPorDefecto = 10;

/// Días que el administrador tiene cargados al abrir (más todas las guías
/// abiertas): alcanza para Hoy, 7 días y Este mes con su comparación. Las
/// fechas más antiguas se piden al elegirlas (ver [AppState.asegurarDesde]).
const diasPanelPorDefecto = 35;

/// Cada cuánto el refresco automático vuelve a traer todo lo cargado (y no
/// solo lo que cambió), por si alguien editó la hoja a mano.
const recargaCompletaCada = Duration(minutes: 10);

/// El mismo transportista puede volver a registrar una guía suya pasado
/// este tiempo desde su último registro de ella (igual que el backend).
const esperaRegistro = Duration(minutes: 20);

/// Distancia en metros entre dos puntos (haversine).
double distanciaMetros(double lat1, double lng1, double lat2, double lng2) {
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371000 * math.asin(math.sqrt(a));
}

DateTime _inicioDelDia(DateTime f) => DateTime(f.year, f.month, f.day);

/// Estado de la app respaldado por la API real (ver ../services/guias_api.dart).
/// Mantiene una copia en memoria de las guías para que las pantallas no
/// tengan que repetir la llamada de red en cada rebuild.
class AppState extends ChangeNotifier {
  AppState({GuiasApi? api}) : _api = api ?? GuiasApi() {
    _api.alVencerSesion = _renovarSesion;
  }

  final GuiasApi _api;

  /// Por qué se cerró la sesión sin que el usuario lo pidiera (la pantalla
  /// de ingreso lo muestra una vez y lo borra).
  String? avisoSesion;

  List<Guia> _guias = [];
  List<Sucursal> _sucursales = [];
  bool cargando = false;
  String? error;
  RolUsuario? _rolActual;
  String? _nombreUsuario;

  /// Solo para el equipo comercial: días de la fecha de tarea que se piden
  /// al servidor (así no se descarga toda la hoja). Por defecto, los
  /// últimos [diasRastreoPorDefecto] días.
  DateTime _desdeTareas = _inicioPorDefecto();
  DateTime _hastaTareas = _inicioDelDia(DateTime.now());
  Future<void>? _cargaEnCurso;
  (DateTime, DateTime)? _rangoCargado;

  (DateTime, DateTime) get rangoTareas => (_desdeTareas, _hastaTareas);

  bool get _pideRango => _rolActual == RolUsuario.comercial;

  /// Administrador y transportista: desde cuándo están cargadas las guías
  /// (más todas las abiertas). null = la ventana por defecto.
  DateTime? _desdeCargado;
  DateTime? _ultimaCompleta;

  /// Se están trayendo guías de fechas más antiguas.
  bool cargandoHistorial = false;

  /// El transportista solo necesita las suyas abiertas y lo de hoy; el
  /// administrador, el último mes y algo más.
  DateTime _ventanaPorDefecto() {
    final hoy = _inicioDelDia(DateTime.now());
    return _rolActual == RolUsuario.transportista
        ? hoy
        : hoy.subtract(const Duration(days: diasPanelPorDefecto - 1));
  }

  Future<List<Guia>> _pedirGuias() {
    if (!_pideRango) {
      return _api.listarGuias(vigentes: _desdeCargado ?? _ventanaPorDefecto());
    }
    return _api.listarGuias(
      desde: _desdeTareas,
      hasta: _hastaTareas.add(const Duration(days: 1)),
    );
  }

  /// El administrador eligió fechas desde [desde]: si son anteriores a lo
  /// cargado, se piden esas guías (solo una vez) y se suman a la lista.
  Future<void> asegurarDesde(DateTime desde) async {
    if (_pideRango || _rolActual == null) return;
    final inicio = _inicioDelDia(desde);
    final cargado = _desdeCargado ?? _ventanaPorDefecto();
    if (!inicio.isBefore(cargado)) return;
    if (_cargaEnCurso case final carga?) await carga;
    cargandoHistorial = true;
    notifyListeners();
    try {
      final antiguas = await _api.listarGuias(desde: inicio, hasta: cargado);
      _guias = _conEntregasEnviando(_unir(_guias, antiguas));
      _desdeCargado = inicio;
    } catch (_) {
      // Sin conexión: se queda con lo que hay; se puede volver a elegir.
    } finally {
      cargandoHistorial = false;
      notifyListeners();
    }
  }

  /// [actuales] con [nuevas] encima (la versión nueva de cada guía).
  static List<Guia> _unir(List<Guia> actuales, Iterable<Guia> nuevas) {
    final porClave = {for (final g in actuales) g.clave: g};
    for (final g in nuevas) {
      porClave[g.clave] = g;
    }
    return porClave.values.toList();
  }

  /// Desde cuándo pedir lo que cambió: lo último modificado que se tiene
  /// (hora del servidor), con un margen por las escrituras simultáneas.
  DateTime _marcaDeCambios() {
    var ultima = _desdeCargado ?? _ventanaPorDefecto();
    for (final g in _guias) {
      if (g.fechaActualizacion.isAfter(ultima)) ultima = g.fechaActualizacion;
      if (g.fechaCreacion.isAfter(ultima)) ultima = g.fechaCreacion;
    }
    return ultima.subtract(const Duration(minutes: 2));
  }

  /// El comercial busca en otro rango de fechas: se piden al servidor solo
  /// esas guías (si no son las que ya están cargadas). Para los demás
  /// roles no hace nada: ya tienen todas.
  Future<void> asegurarRangoTareas(DateTime desde, DateTime hasta) async {
    _desdeTareas = _inicioDelDia(desde);
    _hastaTareas = _inicioDelDia(hasta);
    if (!_pideRango) return;
    if (_cargaEnCurso case final carga?) await carga;
    if (_rangoCargado == (_desdeTareas, _hastaTareas) && error == null) return;
    await cargarGuias();
  }

  /// Guías de la hoja "Despachos Ate" que no están en la base (ver
  /// [asegurarDespachos]). Solo las usa Rastrear.
  List<Despacho> _despachos = [];
  (DateTime, DateTime)? _rangoDespachos;
  DateTime? _despachosLeidos;
  List<Despacho> get despachos => List.unmodifiable(_despachos);

  /// Trae los despachos de esos días (de [desde] a [hasta], ambos
  /// incluidos), si no son los que ya tiene o pasaron unos minutos. Si la
  /// hoja no se puede leer no falla: Rastrear sigue con las guías de la app.
  Future<void> asegurarDespachos(DateTime desde, DateTime hasta) async {
    final rango = (_inicioDelDia(desde), _inicioDelDia(hasta));
    final leidos = _despachosLeidos;
    if (_rangoDespachos == rango &&
        leidos != null &&
        DateTime.now().difference(leidos) < const Duration(minutes: 2)) {
      return;
    }
    try {
      _despachos = await _api.listarDespachos(
        desde: rango.$1,
        hasta: rango.$2.add(const Duration(days: 1)),
      );
      _rangoDespachos = rango;
      _despachosLeidos = DateTime.now();
    } catch (e) {
      debugPrint('Despachos Ate no disponible: $e');
      _despachos = [];
      _rangoDespachos = null;
    }
    notifyListeners();
  }

  /// Sub administrador: los transportistas a su cargo (en minúsculas).
  Set<String> _equipo = {};

  bool get esSubAdministrador => _rolActual == RolUsuario.subAdministrador;

  /// Lo que se le muestra: al sub administrador, solo las guías de sus
  /// transportistas.
  bool _esDeSuZona(Guia g) =>
      !esSubAdministrador ||
      _equipo.contains(g.transportista.trim().toLowerCase());

  List<Guia> get guias => List.unmodifiable(
    esSubAdministrador ? _guias.where(_esDeSuZona) : _guias,
  );

  /// Todas las cargadas, también las que no son de su zona: Rastrear busca
  /// cualquier guía.
  List<Guia> get todasLasGuias => List.unmodifiable(_guias);
  List<Sucursal> get sucursales => List.unmodifiable(_sucursales);
  RolUsuario? get rolActual => _rolActual;

  /// Nombre del usuario con sesión iniciada (vacío si no hay sesión).
  String get transportistaActual => _nombreUsuario ?? '';

  /// Login simple contra la hoja "Usuarios" (ver backend/README.md — no
  /// es un mecanismo de autenticación real, ver la advertencia ahí).
  /// Deja que el ApiException se propague para que la pantalla de login
  /// muestre el mensaje de error.
  Future<void> iniciarSesion(String nombre, String pin) async {
    final sesion = await _api.login(nombre, pin);
    await _recordarCuenta(sesion.nombre, pin);
    await _establecerSesion(sesion);
  }

  /// La última cuenta con la que se entró en este equipo (nombre y PIN),
  /// para dejarla escrita en el login; null si no hay ninguna.
  Future<(String, String)?> cuentaGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nombre = prefs.getString(_prefCuentaNombre);
      final pin = prefs.getString(_prefCuentaPin);
      if (nombre == null || pin == null) return null;
      return (nombre, pin);
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordarCuenta(String nombre, String pin) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefCuentaNombre, nombre);
      await prefs.setString(_prefCuentaPin, pin);
    } catch (_) {
      // Sin almacenamiento solo se pierde el recuerdo.
    }
  }

  static DateTime _inicioPorDefecto() =>
      _inicioDelDia(DateTime.now())
          .subtract(const Duration(days: diasRastreoPorDefecto - 1));

  void _rangoPorDefecto() {
    _desdeTareas = _inicioPorDefecto();
    _hastaTareas = _inicioDelDia(DateTime.now());
    _rangoCargado = null;
    _desdeCargado = null;
    _ultimaCompleta = null;
  }

  Future<void> _establecerSesion(SesionUsuario sesion) async {
    _nombreUsuario = sesion.nombre;
    _rolActual = sesion.rol;
    _api.token = sesion.token;
    avisoSesion = null;
    _rangoPorDefecto();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefNombre, sesion.nombre);
    await prefs.setString(_prefRol, sesion.rol.name);
    await _guardarToken(sesion.token);
    await cargarGuias();
  }

  Future<void> _guardarToken(String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (token == null) {
        await prefs.remove(_prefToken);
      } else {
        await prefs.setString(_prefToken, token);
      }
    } catch (_) {
      // Sin almacenamiento, al recargar se renueva con la cuenta guardada.
    }
  }

  Future<String?>? _renovando;

  /// El servidor dijo que la sesión venció (401): entra de nuevo con la
  /// cuenta guardada en este equipo, sin que el usuario lo note. Si el PIN
  /// ya no sirve (lo cambiaron o el usuario fue dado de baja), cierra la
  /// sesión. Varios pedidos vencidos a la vez esperan una sola renovación.
  Future<String?> _renovarSesion() =>
      _renovando ??= _renovar().whenComplete(() => _renovando = null);

  Future<String?> _renovar() async {
    final nombre = _nombreUsuario;
    if (nombre == null) return null;
    final cuenta = await cuentaGuardada();
    final esLaMisma =
        cuenta != null &&
        cuenta.$1.trim().toLowerCase() == nombre.trim().toLowerCase();
    if (esLaMisma) {
      try {
        final sesion = await _api.login(cuenta.$1, cuenta.$2);
        if (sesion.token != null) {
          _api.token = sesion.token;
          await _guardarToken(sesion.token);
          return sesion.token;
        }
      } on ApiException catch (e) {
        // Un fallo del servidor no cierra la sesión: se reintenta en el
        // próximo pedido. Solo un PIN rechazado o bloqueado la cierra.
        if (e.codigo != 401 && e.codigo != 429) return null;
      } catch (_) {
        // Sin conexión: igual, se reintenta después.
        return null;
      }
    }
    avisoSesion = 'Tu sesión venció. Ingresa de nuevo.';
    await cerrarSesion();
    return null;
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
    if (rol == null) return;

    _nombreUsuario = nombre;
    _rolActual = rol;
    // Una sesión guardada antes de que hubiera tokens no trae ninguno: el
    // primer pedido recibe 401 y se renueva solo (ver _renovarSesion).
    _api.token = prefs.getString(_prefToken);
    _rangoPorDefecto();
    notifyListeners();
    await cargarGuias();
  }

  Future<void> cerrarSesion() async {
    _rolActual = null;
    _nombreUsuario = null;
    _api.token = null;
    _guias = [];
    _sucursales = [];
    _equipo = {};
    error = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefNombre);
    await prefs.remove(_prefRol);
    await prefs.remove(_prefToken);
  }

  Future<void> cargarGuias() {
    final carga = _cargar();
    _cargaEnCurso = carga;
    return carga.whenComplete(() {
      if (identical(_cargaEnCurso, carga)) _cargaEnCurso = null;
    });
  }

  Future<void> _cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    if (esSubAdministrador) {
      try {
        _equipo = {
          for (final n in await _api.listarEquipo()) n.trim().toLowerCase(),
        };
      } catch (_) {
        // Sin conexión: sigue con el equipo que tenía.
      }
    }
    try {
      final rango = (_desdeTareas, _hastaTareas);
      _desdeCargado ??= _pideRango ? null : _ventanaPorDefecto();
      _guias = _conEntregasEnviando(await _pedirGuias());
      _rangoCargado = _pideRango ? rango : null;
      _ultimaCompleta = DateTime.now();
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

  /// Recarga las guías sin mostrar carga ni borrar la lista si falla (para
  /// el refresco automático) y devuelve lo que cambió desde la última vez.
  ///
  /// Administrador y transportista: cada vez solo se piden las guías
  /// abiertas (las del día, que se siguen) y las que cambiaron desde la
  /// última vez; cada [recargaCompletaCada], todo lo cargado.
  Future<List<CambioGuia>> actualizarEnSegundoPlano() async {
    if (cargando || cargandoHistorial) return const [];
    final soloCambios =
        !_pideRango &&
        _ultimaCompleta != null &&
        DateTime.now().difference(_ultimaCompleta!) < recargaCompletaCada;
    final List<Guia> recibidas;
    try {
      recibidas = soloCambios
          ? await _api.listarGuias(vigentes: _marcaDeCambios())
          : await _pedirGuias();
    } catch (_) {
      return const [];
    }
    if (!soloCambios) _ultimaCompleta = DateTime.now();
    final List<Guia> nuevas;
    if (soloCambios) {
      // Las abiertas vienen siempre: una abierta que ya no viene se borró.
      final llegaron = {for (final g in recibidas) g.clave};
      nuevas = _conEntregasEnviando(
        _unir([
          for (final g in _guias)
            if (g.estado.esCerrada || llegaron.contains(g.clave)) g,
        ], recibidas),
      );
    } else {
      nuevas = _conEntregasEnviando(recibidas);
    }
    // Las que se avisan: las que llegaron (las demás no cambiaron).
    final avisables = soloCambios ? {for (final g in recibidas) g.clave} : null;
    final anteriores = {for (final g in _guias) g.clave: g};
    final cambios = <CambioGuia>[
      for (final g in nuevas)
        if ((avisables == null || avisables.contains(g.clave)) &&
            _esDeSuZona(g))
          if (_describirCambio(anteriores[g.clave], g) case final mensaje?)
            CambioGuia(
              g,
              mensaje,
              anterior: anteriores[g.clave]?.estado,
              transbordoAntes: anteriores[g.clave]?.transbordoEstado,
            ),
    ];
    _guias = nuevas;
    error = null;
    notifyListeners();
    return cambios;
  }

  static String? _describirCambio(Guia? antes, Guia ahora) {
    final quien = ahora.transportista;
    final n = ahora.numeroGuia;
    if (antes == null) {
      return '$quien registró la guía $n (${ahora.tipoEntrega.etiqueta}).';
    }
    if (antes.estado == ahora.estado) {
      if (ahora.transbordoEstado != antes.transbordoEstado) {
        if (ahora.transbordoPendiente) {
          return '$quien quiere pasar la guía $n a ${ahora.transbordoA}.';
        }
        if (ahora.transbordoAceptado) {
          return '$quien aceptó la guía $n que le pasó ${ahora.transbordoDe}.';
        }
        if (ahora.transbordoRechazado) {
          return '${ahora.transbordoA} no aceptó la guía $n que le pasaba '
              '$quien.';
        }
      }
      if (ahora.eliminacionPendiente && !antes.eliminacionPendiente) {
        return '$quien pide eliminar la guía $n: ${ahora.motivoEliminacion}';
      }
      return null;
    }
    switch (ahora.estado) {
      case EstadoGuia.enRuta:
        return 'La guía $n volvió a "En ruta".';
      case EstadoGuia.enProcesoTrasbordo:
        return '$quien inició el traslado de $n a ${ahora.destino}.';
      case EstadoGuia.recepcionSucursal:
        return '$quien llegó con $n a ${ahora.destino}.';
      case EstadoGuia.entregado:
        return '$quien entregó la guía $n.';
      case EstadoGuia.finalizado:
        return '$quien entregó la guía $n en agencia.';
      case EstadoGuia.rechazado:
        return ahora.motivoRechazo.isEmpty
            ? '$quien rechazó la guía $n.'
            : '$quien rechazó la guía $n: ${ahora.motivoRechazo}';
    }
  }

  /// La sucursal cuyo perímetro contiene el punto (la más cercana si hay
  /// varias); null si no está dentro de ninguna. Lo mismo decide el backend.
  Sucursal? sucursalEnPunto(double lat, double lng) {
    Sucursal? mejor;
    var menor = double.infinity;
    for (final s in _sucursales) {
      final d = distanciaMetros(lat, lng, s.lat, s.lng);
      if (d <= s.radioM && d < menor) {
        mejor = s;
        menor = d;
      }
    }
    return mejor;
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

  Future<PlanArchivo> simularArchivo({String? hasta}) =>
      _api.simularArchivo(hasta: hasta);

  /// Archiva con el PIN del administrador en sesión y recarga la lista (lo
  /// archivado se sigue viendo: el backend lo trae del archivo).
  Future<PlanArchivo> archivar({
    required String pin,
    required String hasta,
  }) async {
    final res = await _api.archivar(
      nombre: _nombreUsuario ?? '',
      pin: pin,
      hasta: hasta,
    );
    await cargarGuias();
    return res;
  }

  List<Guia> guiasDelTransportista(String nombre) {
    return _guias.where((g) => g.transportista == nombre).toList()
      ..sort((a, b) => b.fechaActualizacion.compareTo(a.fechaActualizacion));
  }

  /// Tareas que otro transportista le quiere pasar a [nombre] (esperan que
  /// acepte o rechace).
  List<Guia> transbordosPara(String nombre) => [
    for (final g in _guias)
      if (g.transportista != nombre && g.esTransbordoPara(nombre)) g,
  ];

  /// Transportistas activos a quienes se puede pasar una tarea.
  Future<List<String>> listarTransportistas() => _api.listarTransportistas();

  Future<Guia> pedirTransbordo(Guia guia, String a) async {
    final nueva = await _api.pedirTransbordo(
      guia,
      de: guia.transportista,
      a: a,
    );
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> cancelarTransbordo(Guia guia) async {
    final nueva = await _api.cancelarTransbordo(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  /// El transportista actual acepta o rechaza el transbordo que le pasaron.
  /// Si lo rechaza, la tarea sale de su vista (vuelve a quien la envió).
  Future<Guia> responderTransbordo(Guia guia, {required bool acepta}) async {
    final nueva = await _api.responderTransbordo(
      guia,
      quien: transportistaActual,
      acepta: acepta,
    );
    _reemplazar(guia, nueva);
    return nueva;
  }

  /// Posición del registro más reciente con ese número (-1 si no hay).
  int _indiceDe(String numeroGuia) {
    var indice = -1;
    for (var i = 0; i < _guias.length; i++) {
      final g = _guias[i];
      if (g.numeroGuia != numeroGuia) continue;
      if (indice == -1 ||
          !g.fechaCreacion.isBefore(_guias[indice].fechaCreacion)) {
        indice = i;
      }
    }
    return indice;
  }

  /// El registro más reciente con ese número de guía.
  /// La tarea con ese número; si se indica [fechaCreacion], exactamente esa
  /// (una guía rechazada y vuelta a registrar son dos tareas distintas).
  Guia? buscarPorNumero(String numeroGuia, {DateTime? fechaCreacion}) {
    final i = _indiceDeRegistro(numeroGuia, fechaCreacion);
    return i == -1 ? null : _guias[i];
  }

  /// Si el usuario actual registró ese número hace menos de
  /// [esperaRegistro], desde cuándo podrá registrarlo otra vez; si no,
  /// null. Lo que registró otro transportista y un registro rechazado no
  /// bloquean. Validación local rápida contra la última lista cargada; la
  /// definitiva la hace el backend al confirmar (409).
  DateTime? registroBloqueadoHasta(String numeroGuia, {DateTime? ahora}) {
    final yo = transportistaActual.trim().toLowerCase();
    Guia? ultima;
    for (final g in _guias) {
      if (g.numeroGuia != numeroGuia ||
          g.estado == EstadoGuia.rechazado ||
          g.transportista.trim().toLowerCase() != yo) {
        continue;
      }
      if (ultima == null || g.fechaCreacion.isAfter(ultima.fechaCreacion)) {
        ultima = g;
      }
    }
    if (ultima == null) return null;
    final libre = ultima.fechaCreacion.toLocal().add(esperaRegistro);
    return (ahora ?? DateTime.now()).isBefore(libre) ? libre : null;
  }

  /// El registro exacto (por fecha de creación) o, sin ella, el más
  /// reciente con ese número.
  int _indiceDeRegistro(String numeroGuia, DateTime? fechaCreacion) {
    if (fechaCreacion != null) {
      final i = _guias.indexWhere(
        (g) =>
            g.numeroGuia == numeroGuia &&
            g.fechaCreacion.isAtSameMomentAs(fechaCreacion),
      );
      if (i != -1) return i;
    }
    return _indiceDe(numeroGuia);
  }

  bool esDuplicado(String numeroGuia) =>
      registroBloqueadoHasta(numeroGuia) != null;

  /// Lee los datos de la foto de una guía con IA (ver
  /// ../services/guias_api.dart). No toca `_guias`/no notifica — es solo
  /// para pre-llenar el formulario de asignación.
  Future<DatosGuiaLeida> leerGuiaConIA(Uint8List fotoBytes) =>
      _api.leerGuiaConIA(fotoBytes);

  /// Regularización (solo administrador). Ver GuiasApi.regularizarGuia.
  Future<(Guia, String?)> regularizarGuia({
    required String transportista,
    required String numeroGuia,
    required String origen,
    required String destino,
    required String destinatario,
    required Uint8List foto,
    String numeroPedido = '',
    String numeroEntrega = '',
  }) => _api.regularizarGuia(
    transportista: transportista,
    numeroGuia: numeroGuia,
    origen: origen,
    destino: destino,
    destinatario: destinatario,
    foto: foto,
    numeroPedido: numeroPedido,
    numeroEntrega: numeroEntrega,
  );

  Future<LecturaEntrega> leerNumeroGuia(
    Uint8List fotoBytes, {
    List<String> candidatos = const [],
  }) => _api.leerNumeroGuia(fotoBytes, candidatos: candidatos);

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

  /// Carga masiva: registra todas con un solo pedido al backend y agrega a
  /// la lista las que se crearon. Con [despachoCorte] quedan unidas en un
  /// Despacho Corte. Devuelve el resultado de cada una, en el mismo orden.
  Future<ResultadoCarga> asignarLote(
    List<GuiaNueva> guias, {
    bool despachoCorte = false,
    String? codigoCorte,
  }) async {
    final carga = await _api.asignarLote(
      guias,
      despachoCorte: despachoCorte,
      codigoCorte: codigoCorte,
    );
    final creadas = [
      for (final r in carga.resultados)
        if (r.guia != null) r.guia!,
    ];
    if (creadas.isNotEmpty) {
      _guias.insertAll(0, creadas.reversed);
      notifyListeners();
    }
    return carga;
  }

  /// Llegada de un Despacho Corte: todas sus guías en camino quedan
  /// entregadas a la vez. Devuelve cuántas.
  Future<int> llegadaDespachoCorte(
    String codigo, {
    required double lat,
    required double lng,
  }) async {
    final actualizadas = await _api.llegadaDespachoCorte(
      codigo,
      lat: lat,
      lng: lng,
      transportista: transportistaActual,
    );
    for (final nueva in actualizadas) {
      final i = _guias.indexWhere((g) => g.clave == nueva.clave);
      if (i != -1) _guias[i] = nueva;
    }
    notifyListeners();
    return actualizadas.length;
  }

  Future<void> quitarDeDespachoCorte(Guia guia) async {
    _reemplazar(guia, await _api.quitarDeDespachoCorte(guia));
  }

  /// Devuelve el aviso si la foto no se pudo guardar (null si todo bien).
  Future<String?> actualizarEstado(
    String numeroGuia,
    EstadoGuia nuevoEstado, {
    double? lat,
    double? lng,
    bool porAdmin = false,
    Uint8List? foto,
    DateTime? fechaCreacion,
    LecturaComprobante? comprobante,
    DocClienteEntrega? docCliente,
  }) async {
    final (actualizada, avisoFoto) = await _api.actualizarEstado(
      numeroGuia,
      nuevoEstado,
      lat: lat,
      lng: lng,
      porAdmin: porAdmin,
      foto: foto,
      fechaCreacion: fechaCreacion,
      comprobante: comprobante,
      docCliente: docCliente,
    );
    final index = _indiceDeRegistro(numeroGuia, fechaCreacion);
    if (index != -1) {
      _guias[index] = actualizada;
    }
    notifyListeners();
    return avisoFoto;
  }

  /// Entregas ya confirmadas que aún se están enviando al servidor (clave de
  /// la guía → cómo quedó en el celular). Mientras tanto, lo que llegue del
  /// servidor no las devuelve a "En ruta".
  final Map<String, Guia> _entregasEnviando = {};

  /// Entregas que aún se están enviando.
  int get entregasEnviando => _entregasEnviando.length;

  /// Muestra un aviso en la pantalla que esté abierta (lo conecta la app).
  void Function(String mensaje)? avisar;

  /// Esperas entre reintentos cuando falla la señal.
  @visibleForTesting
  static List<Duration> esperasReintento = const [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
  ];

  /// Registra la entrega al instante en el celular y la envía al servidor
  /// por detrás (con reintentos), para que el transportista no espere a que
  /// se guarde la foto. Si no se puede enviar, la tarea vuelve a "En ruta"
  /// y se avisa.
  void entregarEnSegundoPlano(
    Guia guia,
    EstadoGuia nuevoEstado, {
    required double lat,
    required double lng,
    Uint8List? foto,
    LecturaComprobante? comprobante,
    DocClienteEntrega? docCliente,
  }) {
    final comp = comprobante?.$1;
    final local = guia.copyWith(
      estado: nuevoEstado,
      tipoEntrega: comp != null ? TipoEntrega.agencia : null,
      fechaActualizacion: DateTime.now().toUtc(),
    );
    _entregasEnviando[guia.clave] = local;
    final i = _guias.indexWhere((g) => g.clave == guia.clave);
    if (i != -1) _guias[i] = local;
    notifyListeners();
    _enviarEntrega(guia, local, lat, lng, foto, comprobante, docCliente);
  }

  Future<void> _enviarEntrega(
    Guia original,
    Guia local,
    double lat,
    double lng,
    Uint8List? foto,
    LecturaComprobante? comprobante,
    DocClienteEntrega? docCliente,
  ) async {
    Object? error;
    for (var intento = 0; ; intento++) {
      try {
        final (actualizada, avisoFoto) = await _api.actualizarEstado(
          original.numeroGuia,
          local.estado,
          lat: lat,
          lng: lng,
          foto: foto,
          fechaCreacion: original.fechaCreacion,
          comprobante: comprobante,
          docCliente: docCliente,
        );
        _entregasEnviando.remove(original.clave);
        final i = _guias.indexWhere((g) => g.clave == original.clave);
        if (i != -1) _guias[i] = actualizada;
        notifyListeners();
        if (avisoFoto != null) avisar?.call(avisoFoto);
        return;
      } on ApiException catch (e) {
        error = e.mensaje;
        // El servidor la rechazó (no es la señal): no sirve reintentar.
        final codigo = e.codigo;
        if (codigo != null && codigo >= 400 && codigo < 500) break;
      } catch (e) {
        error = e;
      }
      if (intento >= esperasReintento.length) break;
      await Future<void>.delayed(esperasReintento[intento]);
    }
    _entregasEnviando.remove(original.clave);
    final i = _guias.indexWhere((g) => g.clave == original.clave);
    if (i != -1 && identical(_guias[i], local)) _guias[i] = original;
    notifyListeners();
    avisar?.call(
      'No se pudo registrar la entrega de ${original.numeroGuia} '
      '($error). Vuelve a entregarla.',
    );
  }

  /// Lo que llegó del servidor, sin deshacer las entregas que aún se envían.
  List<Guia> _conEntregasEnviando(List<Guia> guias) => _entregasEnviando.isEmpty
      ? guias
      : [for (final g in guias) _entregasEnviando[g.clave] ?? g];

  /// Fotos ya pedidas, por URL (la URL cambia si la foto cambia). Así la
  /// que se adelantó al buscar en Rastrear se abre al instante.
  final _fotos = <String, Future<Uint8List>>{};

  Future<Uint8List> fotoEntrega(Guia guia) {
    final url = urlFotoEntrega(guia);
    final enCache = _fotos.remove(url);
    if (enCache != null) return _fotos[url] = enCache;
    if (_fotos.length >= 20) _fotos.remove(_fotos.keys.first);
    final foto = _api.fotoEntrega(guia);
    // Si falla no se guarda: "Reintentar" la vuelve a pedir.
    foto.catchError((Object _) {
      _fotos.remove(url);
      return Uint8List(0);
    });
    return _fotos[url] = foto;
  }

  Future<Uint8List> fotoDocCliente(Guia guia) => _api.fotoDocCliente(guia);

  /// Una tanda del paso de fotos viejas de Vercel Blob a Drive.
  Future<ResultadoMigracion> migrarFotos() => _api.migrarFotos();

  /// null mientras no se sabe (o si no se pudo consultar).
  Future<bool?> almacenamientoFotosConfigurado() async {
    try {
      return await _api.almacenamientoFotosConfigurado();
    } catch (_) {
      return null;
    }
  }

  Future<void> rechazarGuia(
    String numeroGuia,
    String motivo, {
    double? lat,
    double? lng,
    DateTime? fechaCreacion,
  }) async {
    final actualizada = await _api.rechazarGuia(
      numeroGuia,
      motivo,
      lat: lat,
      lng: lng,
      fechaCreacion: fechaCreacion,
    );
    final index = _indiceDeRegistro(numeroGuia, fechaCreacion);
    if (index != -1) _guias[index] = actualizada;
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
    final index = _indiceDe(numeroAnterior);
    if (index != -1) {
      _guias[index] = actualizada;
    }
    notifyListeners();
  }

  /// Reemplaza en la lista el registro exacto de [guia] (mismo número y
  /// fecha de creación) por [nueva]; null lo quita.
  void _reemplazar(Guia guia, Guia? nueva) {
    final i = _guias.indexWhere((g) => g.clave == guia.clave);
    if (i == -1) return;
    if (nueva == null) {
      _guias.removeAt(i);
    } else {
      _guias[i] = nueva;
    }
    notifyListeners();
  }

  Future<Guia> cambiarTipoEntrega(
    Guia guia,
    TipoEntrega tipo, {
    String? destino,
    bool porAdmin = false,
  }) async {
    final nueva = await _api.cambiarTipoEntrega(
      guia,
      tipo,
      destino: destino,
      porAdmin: porAdmin,
    );
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> pedirEliminacion(Guia guia, String motivo) async {
    final nueva = await _api.pedirEliminacion(guia, motivo);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> ponerEnCustodia(Guia guia) async {
    final nueva = await _api.ponerEnCustodia(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> quitarCustodia(Guia guia) async {
    final nueva = await _api.quitarCustodia(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> retirarPedidoEliminacion(Guia guia) async {
    final nueva = await _api.retirarPedidoEliminacion(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<Guia> rechazarEliminacion(Guia guia) async {
    final nueva = await _api.rechazarEliminacion(guia);
    _reemplazar(guia, nueva);
    return nueva;
  }

  Future<void> eliminarGuia(Guia guia) async {
    await _api.eliminarGuia(guia);
    _reemplazar(guia, null);
  }

  Future<String?> eliminarFotoEntrega(Guia guia) async {
    final (nueva, aviso) = await _api.eliminarFotoEntrega(guia);
    _reemplazar(guia, nueva);
    return aviso;
  }

  /// La versión actual (en la lista) de un registro, o null si ya no está.
  Guia? guiaActual(Guia guia) {
    for (final g in _guias) {
      if (g.clave == guia.clave) return g;
    }
    return null;
  }
}
