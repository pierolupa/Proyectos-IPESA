const express = require('express');
const cors = require('cors');
const {
  ESTADOS,
  ESTADOS_FINALES,
  ESTADOS_CERRADOS,
  ELIMINACION,
  TIPOS_ENTREGA,
  ROLES,
  TRANSBORDO,
} = require('./columns');
const repo = require('./sheetsRepository');
const {
  leerGuiaConIA,
  leerNumeroGuia,
  leerComprobante,
  comprobanteDe,
  hayComprobante,
} = require('./ocrAgente');
const fotos = require('./fotos');

const app = express();
app.use(cors({ origin: true }));
// Límite alto: el body incluye la foto en base64 (/ocr/leer-guia, y la foto
// de la entrega al cliente que se guarda). Vercel corta en 4,5 MB.
app.use(express.json({ limit: '8mb' }));

const ESTADOS_VALIDOS = new Set(Object.values(ESTADOS));
// "Entre sucursales" ya no se ofrece: la sucursal se detecta sola por GPS
// (origen al registrar, destino al entregar). Las guías antiguas de ese tipo
// se siguen leyendo y se pueden terminar, pero no se crean nuevas.
const TIPOS_VALIDOS = new Set(
  Object.values(TIPOS_ENTREGA).filter((t) => t !== TIPOS_ENTREGA.ENTRE_SUCURSALES),
);
const AVISO_SIN_TRASLADOS =
  'Ya no se registran traslados entre sucursales: elige cliente final o agencia.';
function tipoInvalido(tipoEntrega) {
  return tipoEntrega === TIPOS_ENTREGA.ENTRE_SUCURSALES
    ? AVISO_SIN_TRASLADOS
    : `tipoEntrega inválido: ${tipoEntrega}`;
}
const ROLES_VALIDOS = new Set(Object.values(ROLES));

// Perú está en UTC-5 todo el año (sin horario de verano).
const DESFASE_PERU_MS = 5 * 60 * 60 * 1000;
const DIA_MS = 24 * 60 * 60 * 1000;

/** El día (calendario de Perú) de un instante, como número para comparar. */
function diaPeru(ms) {
  return Math.floor((ms - DESFASE_PERU_MS) / DIA_MS);
}

/** "14:35" en hora de Perú (el servidor corre en UTC). */
function horaPeru(ms) {
  return new Date(ms).toLocaleTimeString('es-PE', {
    timeZone: 'America/Lima',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

/**
 * NOTA DE SEGURIDAD: el login de /auth/login es deliberadamente simple
 * (nombre + PIN comparados en texto plano contra la hoja "Usuarios") y
 * NO reemplaza un mecanismo de autenticación real — no hay tokens, no hay
 * expiración de sesión, no hay hashing del PIN. Sirve solo para que el
 * equipo pruebe internamente la app. El resto de la API tampoco valida
 * quién llama cada endpoint (ver ARCHITECTURE.md, sección 8 — decisión
 * pendiente): antes de un despliegue real con transportistas de verdad
 * hay que migrar a un proveedor de autenticación de verdad (Firebase Auth,
 * por ejemplo) y exigir/verificar un token en cada endpoint sensible.
 */

function distanciaMetros(lat1, lng1, lat2, lng2) {
  const rad = (g) => (g * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(a));
}

/** La sucursal cuyo perímetro contiene el punto (la más cercana si hay varias). */
function sucursalEnPunto(sucursales, lat, lng) {
  let mejor = null;
  let menor = Infinity;
  for (const s of sucursales || []) {
    if (typeof s.lat !== 'number' || typeof s.lng !== 'number' || !s.radio_m) continue;
    const d = distanciaMetros(lat, lng, s.lat, s.lng);
    if (d <= s.radio_m && d < menor) {
      mejor = s;
      menor = d;
    }
  }
  return mejor;
}

function buscarSucursal(sucursales, nombre) {
  const clave = String(nombre).trim().toLowerCase();
  return sucursales.find((s) => s.nombre.toLowerCase() === clave) || null;
}

/**
 * El registro de una guía. Si viene `fechaCreacion` (la app la manda) se
 * busca ese registro exacto; si no, el más reciente con ese número.
 */
async function buscarRegistro(numeroGuia, fechaCreacion) {
  if (fechaCreacion) {
    const guias = await repo.listarGuias({ fresco: true });
    const exacta = guias.find(
      (g) =>
        g.numero_guia === numeroGuia &&
        Date.parse(g.fecha_creacion) === Date.parse(fechaCreacion),
    );
    if (exacta) return exacta;
  }
  return repo.buscarPorNumero(numeroGuia, { fresco: true });
}

function motivoValido(motivo) {
  const limpio = String(motivo ?? '').trim();
  if (limpio.length < 3) return { error: 'Indica el motivo.' };
  if (limpio.length > 300) return { error: 'El motivo es muy largo (máx. 300 caracteres).' };
  return { motivo: limpio };
}

/** Quita un transbordo pendiente o rechazado; el aceptado queda como historia. */
function limpiarTransbordoAbierto(guia) {
  if (guia.transbordo_estado && guia.transbordo_estado !== TRANSBORDO.ACEPTADO) {
    guia.transbordo_estado = '';
    guia.transbordo_a = '';
  }
}

const mismoNombre = (a, b) =>
  String(a ?? '').trim().toLowerCase() === String(b ?? '').trim().toLowerCase();

/** Transportistas activos de la hoja "Usuarios" (solo el nombre, nunca el PIN). */
async function transportistasActivos() {
  const usuarios = await repo.listarUsuarios();
  return usuarios
    .filter((u) => u.activo && u.rol === ROLES.TRANSPORTISTA && u.nombre.trim())
    .map((u) => u.nombre.trim())
    .sort((a, b) => a.localeCompare(b, 'es'));
}

function sinCamposInternos(guia) {
  const { _row, _fila, ...resto } = guia;
  return resto;
}

/**
 * Guarda la foto si vino en el body. Nunca lanza: si falla, devuelve el
 * aviso para la app y la guía se registra igual (ver fotos.js).
 */
async function intentarGuardarFoto(numeroGuia, foto) {
  if (!fotos.esFotoValida(foto)) return { url: null, aviso: null };
  try {
    return { url: await fotos.guardarFoto(numeroGuia, foto), aviso: null };
  } catch (err) {
    console.error(err);
    return { url: null, aviso: `La foto no se pudo guardar: ${err.message}` };
  }
}

app.get('/health', (_req, res) => res.json({ ok: true }));

/**
 * Responde un fallo de la IA con el mensaje real (a diferencia del resto de
 * rutas, que usan el manejador genérico) porque este proyecto de Vercel no
 * tiene acceso a runtime logs (403) — sin esto, un fallo de la IA es
 * indiagnosticable desde afuera. No es información sensible: es un error de
 * la librería de Gemini, no un dato de la guía ni la API key.
 */
function responderFalloIA(res, err) {
  console.error(err);
  // Límite por minuto de la IA (varios transportistas leyendo fotos a la
  // vez): 429 para que la app espere y vuelva a intentar esa foto.
  if (err.status === 429 || /RESOURCE_EXHAUSTED|\b429\b/.test(String(err.message))) {
    return res.status(429).json({
      error: 'La IA está ocupada en este momento; se reintentará en unos segundos.',
    });
  }
  res.status(500).json({ error: `Fallo al leer la guía con IA: ${err.message}` });
}

// Lee la foto de una guía con IA (Gemini, con visión) y devuelve los datos
// extraídos, incluido el comprobante de agencia si viene pegado. Ver
// ocrAgente.js; requiere GEMINI_API_KEY (ver README.md).
app.post('/ocr/leer-guia', async (req, res) => {
  try {
    const { imagenBase64, mediaType } = req.body || {};
    if (!imagenBase64) {
      return res.status(400).json({ error: 'Falta imagenBase64.' });
    }
    const datos = await leerGuiaConIA(imagenBase64, mediaType || 'image/jpeg');
    res.json(datos);
  } catch (err) {
    responderFalloIA(res, err);
  }
});

// Entrega inteligente: solo el número de guía de una foto de entrega, que
// la IA compara con las guías en ruta del transportista (candidatos).
const MAX_CANDIDATOS = 300;
app.post('/ocr/numero-guia', async (req, res) => {
  try {
    const { imagenBase64, mediaType, candidatos } = req.body || {};
    if (!imagenBase64) {
      return res.status(400).json({ error: 'Falta imagenBase64.' });
    }
    const lista = Array.isArray(candidatos)
      ? [...new Set(candidatos.filter((c) => typeof c === 'string' && c.trim()).map((c) => c.trim()))]
          .slice(0, MAX_CANDIDATOS)
      : [];
    const datos = await leerNumeroGuia(imagenBase64, mediaType || 'image/jpeg', lista);
    res.json(datos);
  } catch (err) {
    responderFalloIA(res, err);
  }
});

// Login simple contra la hoja "Usuarios" (ver nota de seguridad arriba).
app.post('/auth/login', async (req, res, next) => {
  try {
    const { nombre, pin } = req.body || {};
    if (!nombre || !pin) {
      return res.status(400).json({ error: 'Faltan nombre y/o pin.' });
    }

    const usuarios = await repo.listarUsuarios();
    const usuario = usuarios.find(
      (u) => u.nombre.trim().toLowerCase() === String(nombre).trim().toLowerCase(),
    );

    if (!usuario || !usuario.activo || String(usuario.pin) !== String(pin)) {
      return res.status(401).json({ error: 'Nombre o PIN incorrecto.' });
    }
    if (!ROLES_VALIDOS.has(usuario.rol)) {
      return res.status(500).json({ error: `Rol inválido en la hoja de usuarios: ${usuario.rol}` });
    }

    res.json({ nombre: usuario.nombre, rol: usuario.rol });
  } catch (err) {
    next(err);
  }
});

// Auto-registro (ver nota de seguridad arriba). Siempre crea el usuario
// como "transportista" — las cuentas de administrador se dan de alta a
// mano en la hoja, para que el auto-registro no pueda auto-otorgarse ese
// rol.
app.post('/auth/registro', async (req, res, next) => {
  try {
    const { nombre, pin } = req.body || {};
    if (!nombre || !pin) {
      return res.status(400).json({ error: 'Faltan nombre y/o pin.' });
    }

    const nombreLimpio = String(nombre).trim();
    const usuarios = await repo.listarUsuarios();
    const yaExiste = usuarios.some(
      (u) => u.nombre.trim().toLowerCase() === nombreLimpio.toLowerCase(),
    );
    if (yaExiste) {
      return res.status(409).json({ error: `Ya existe un usuario con el nombre "${nombreLimpio}".` });
    }

    const nuevoUsuario = {
      nombre: nombreLimpio,
      rol: ROLES.TRANSPORTISTA,
      pin: String(pin).trim(),
      activo: true,
    };
    await repo.crearUsuario(nuevoUsuario);

    res.status(201).json({ nombre: nuevoUsuario.nombre, rol: nuevoUsuario.rol });
  } catch (err) {
    next(err);
  }
});

// Perímetros de sucursal (los marca el administrador en el mapa).
app.get('/sucursales', async (_req, res, next) => {
  try {
    const sucursales = await repo.listarSucursales();
    res.json(sucursales.map(sinCamposInternos));
  } catch (err) {
    next(err);
  }
});

app.put('/sucursales/:nombre', async (req, res, next) => {
  try {
    const nombre = String(req.params.nombre).trim();
    const { lat, lng, radioM } = req.body || {};
    if (!nombre) {
      return res.status(400).json({ error: 'Falta el nombre de la sucursal.' });
    }
    if (typeof lat !== 'number' || typeof lng !== 'number') {
      return res.status(400).json({ error: 'Marca el centro de la sucursal en el mapa.' });
    }
    if (typeof radioM !== 'number' || radioM < 20 || radioM > 5000) {
      return res.status(400).json({ error: 'El radio debe estar entre 20 y 5000 metros.' });
    }
    const sucursal = { nombre, lat, lng, radio_m: radioM };
    await repo.guardarSucursal(sucursal);
    res.json(sucursal);
  } catch (err) {
    next(err);
  }
});

app.delete('/sucursales/:nombre', async (req, res, next) => {
  try {
    const sucursal = buscarSucursal(await repo.listarSucursales(), req.params.nombre);
    if (!sucursal) {
      return res.status(404).json({ error: `Sucursal no encontrada: ${req.params.nombre}` });
    }
    await repo.eliminarSucursal(sucursal._row);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

// Lista de guías, con filtros opcionales: estado, y desde/hasta (fechas
// ISO) sobre la fecha de la tarea (fecha_creacion): desde <= f < hasta.
// El equipo comercial pide solo el rango que está buscando.
app.get('/guias', async (req, res, next) => {
  try {
    const { estado, desde, hasta } = req.query;
    let guias = await repo.listarGuias();
    if (estado) {
      if (!ESTADOS_VALIDOS.has(estado)) {
        return res.status(400).json({ error: `Estado inválido: ${estado}` });
      }
      guias = guias.filter((g) => g.estado === estado);
    }
    const inicio = desde ? Date.parse(desde) : null;
    const fin = hasta ? Date.parse(hasta) : null;
    if (Number.isNaN(inicio) || Number.isNaN(fin)) {
      return res.status(400).json({ error: 'Fechas inválidas (usa formato ISO).' });
    }
    if (inicio !== null || fin !== null) {
      guias = guias.filter((g) => {
        const t = Date.parse(g.fecha_creacion || g.fecha_actualizacion);
        if (Number.isNaN(t)) return false;
        return (inicio === null || t >= inicio) && (fin === null || t < fin);
      });
    }
    res.json(guias.map(sinCamposInternos));
  } catch (err) {
    next(err);
  }
});

// Transportista: sus tareas asignadas.
app.get('/guias/transportista/:nombre', async (req, res, next) => {
  try {
    const guias = await repo.listarGuias();
    const { nombre } = req.params;
    // Sus tareas y las que otro transportista le quiere pasar (transbordo
    // pendiente de su respuesta).
    const propias = guias.filter(
      (g) =>
        g.transportista === nombre
        || (g.transbordo_estado === TRANSBORDO.PENDIENTE && g.transbordo_a === nombre),
    );
    res.json(propias.map(sinCamposInternos));
  } catch (err) {
    next(err);
  }
});

// Guías que se pueden registrar de una vez (carga masiva desde la galería).
const MAX_GUIAS_POR_LOTE = 30;

/**
 * Valida los datos de una guía por registrar y arma su fila, o devuelve
 * { status, error }. `existentes` son las guías de la hoja (y las ya
 * aceptadas en el mismo lote); `sucursales`, las de la hoja.
 */
function prepararGuia(datos, existentes, sucursales) {
  const {
    numeroGuia,
    tipoEntrega,
    origen,
    destino,
    transportista,
    destinatario,
    geo,
    numeroPedido,
    numeroEntrega,
    comprobante,
  } = datos || {};

  if (!numeroGuia || !origen || !destino || !transportista || !destinatario) {
    return { status: 400, error: 'Faltan campos obligatorios.' };
  }
  if (!TIPOS_VALIDOS.has(tipoEntrega)) {
    return { status: 400, error: tipoInvalido(tipoEntrega) };
  }
  if (!geo || typeof geo.lat !== 'number' || typeof geo.lng !== 'number') {
    return {
      status: 400,
      error: 'GPS obligatorio: no se puede registrar una guía sin geolocalización.',
    };
  }

  // Un mismo número de guía se puede volver a registrar: otro
  // transportista que la lleva en el siguiente tramo, en cualquier
  // momento; el mismo transportista, no el mismo día (hora de Perú) de su
  // último registro: se puede asignar una guía una sola vez al día.
  // Un registro rechazado no cuenta: esa tarea nunca se hizo.
  const suyas = existentes.filter(
    (g) =>
      g.numero_guia === numeroGuia
      && g.estado !== ESTADOS.RECHAZADO
      && mismoNombre(g.transportista, transportista),
  );
  const registrada = Math.max(
    ...suyas.map((g) => Date.parse(g.fecha_creacion || g.fecha_actualizacion) || 0),
    0,
  );
  if (registrada > 0 && diaPeru(registrada) === diaPeru(Date.now())) {
    return {
      status: 409,
      error:
        `Ya registraste la guía ${numeroGuia} hoy a las ${horaPeru(registrada)}. `
        + 'Un transportista no puede asignarse la misma guía dos veces el mismo día.',
    };
  }

  // Si se registra dentro del perímetro de una sucursal, sale de ahí.
  const aqui = sucursalEnPunto(sucursales, geo.lat, geo.lng);

  const ahora = new Date().toISOString();
  return {
    guia: {
      numero_guia: numeroGuia,
      estado: ESTADOS.EN_RUTA,
      tipo_entrega: tipoEntrega,
      origen: aqui ? aqui.nombre : origen,
      destino,
      transportista,
      destinatario,
      geo_lat: geo.lat,
      geo_lng: geo.lng,
      corregido_por_admin: false,
      fecha_creacion: ahora,
      fecha_actualizacion: ahora,
      // Leídos por OCR de la sección "Datos adicionales" de la guía;
      // opcionales porque el OCR no siempre los encuentra.
      numero_pedido: numeroPedido || '',
      numero_entrega: numeroEntrega || '',
      ...columnasComprobante(comprobante),
    },
  };
}

/**
 * El comprobante de agencia que manda la app ({ razonSocial, ruc, monto },
 * leído por la IA de la foto) en las columnas de la hoja; vacías si no hay.
 */
function columnasComprobante(comprobante) {
  const c = comprobanteDe({
    agencia_razon_social: comprobante?.razonSocial,
    agencia_ruc: comprobante?.ruc,
    agencia_monto: comprobante?.monto,
    agencia_comprobante: comprobante?.numero,
  });
  return {
    agencia_razon_social: c.agencia_razon_social || '',
    agencia_ruc: c.agencia_ruc || '',
    agencia_monto: c.agencia_monto ?? '',
    agencia_comprobante: c.agencia_comprobante || '',
  };
}

// Lo que se espera a la IA por el comprobante al entregar: si tarda más,
// la entrega se guarda igual, sin esos datos.
const ESPERA_COMPROBANTE_MS = 6000;

/**
 * El comprobante de agencia de la foto de entrega: el que ya leyó la app
 * (Entrega inteligente lo manda en `comprobante`) o, si no vino, el que lee
 * ahora la IA. Nunca hace fallar la entrega: ante un error o demora, null.
 */
async function comprobanteDeEntrega(body, foto) {
  if (body && Object.prototype.hasOwnProperty.call(body, 'comprobante')) {
    const c = columnasComprobante(body.comprobante);
    return c.agencia_razon_social || c.agencia_ruc || c.agencia_monto !== '' || c.agencia_comprobante
      ? c
      : null;
  }
  if (!fotos.esFotoValida(foto)) return null;
  let espera;
  try {
    const leido = await Promise.race([
      leerComprobante(foto.base64, foto.mediaType || 'image/jpeg'),
      new Promise((resolve) => {
        espera = setTimeout(() => resolve(null), ESPERA_COMPROBANTE_MS);
      }),
    ]);
    if (!hayComprobante(leido)) return null;
    return {
      agencia_razon_social: leido.agencia_razon_social || '',
      agencia_ruc: leido.agencia_ruc || '',
      agencia_monto: leido.agencia_monto ?? '',
      agencia_comprobante: leido.agencia_comprobante || '',
    };
  } catch (err) {
    console.error(err);
    return null;
  } finally {
    clearTimeout(espera);
  }
}

// Las sucursales para el punto de partida; si no se pueden leer, la guía
// se registra igual con el punto de partida que vino.
async function sucursalesParaRegistro() {
  try {
    return await repo.listarSucursales();
  } catch (err) {
    console.error(err);
    return [];
  }
}

// Asignación: crea una guía "en ruta" a partir del número leído por OCR.
// GPS obligatorio (ARCHITECTURE.md, sección 5).
app.post('/guias', async (req, res, next) => {
  try {
    const existentes = await repo.listarGuias({ fresco: true });
    const sucursales = await sucursalesParaRegistro();
    const { guia: nueva, status, error } = prepararGuia(req.body, existentes, sucursales);
    if (error) return res.status(status).json({ error });
    await repo.crearGuias([nueva]);

    // La guía completa: la app la agrega a su lista sin volver a pedirlas
    // todas.
    res.status(201).json({ ...nueva, numeroGuia: nueva.numero_guia });
  } catch (err) {
    next(err);
  }
});

// Carga masiva: hasta MAX_GUIAS_POR_LOTE guías de una vez, con una sola
// lectura y una sola escritura en la hoja (así 30 guías no gastan la cuota
// de Google Sheets que comparten todos los transportistas). Cada guía se
// valida por separado: las que fallan vuelven con su error y las demás se
// registran igual. Responde { resultados: [{ guia } | { error }] } en el
// mismo orden.
app.post('/guias/lote', async (req, res, next) => {
  try {
    const { guias } = req.body || {};
    if (!Array.isArray(guias) || guias.length === 0) {
      return res.status(400).json({ error: 'Faltan las guías a registrar.' });
    }
    if (guias.length > MAX_GUIAS_POR_LOTE) {
      return res.status(400).json({
        error: `Máximo ${MAX_GUIAS_POR_LOTE} guías por carga.`,
      });
    }
    const existentes = await repo.listarGuias({ fresco: true });
    const sucursales = await sucursalesParaRegistro();
    const resultados = [];
    const nuevas = [];
    for (const datos of guias) {
      // Las ya aceptadas en este lote cuentan: la misma guía dos veces en
      // la misma carga se registra una sola vez.
      const preparada = prepararGuia(datos, [...existentes, ...nuevas], sucursales);
      if (preparada.error) {
        resultados.push({ error: preparada.error });
      } else {
        nuevas.push(preparada.guia);
        resultados.push({ guia: preparada.guia });
      }
    }
    if (nuevas.length > 0) await repo.crearGuias(nuevas);
    res.json({ resultados });
  } catch (err) {
    next(err);
  }
});

/**
 * Código de un Despacho Corte: DC-AAMMDD-HHMM-XX (hora de Perú y dos
 * caracteres al azar para que dos cortes del mismo minuto no choquen).
 */
function nuevoCodigoCorte(ahora = new Date()) {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat('en-GB', {
      timeZone: 'America/Lima',
      year: '2-digit',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    })
      .formatToParts(ahora)
      .map((x) => [x.type, x.value]),
  );
  const azar = Math.random().toString(36).slice(2, 4).toUpperCase().padEnd(2, '0');
  return `DC-${p.year}${p.month}${p.day}-${p.hour}${p.minute}-${azar}`;
}

/** Las guías de un corte que siguen en camino (no cerradas). */
function abiertasDelCorte(guias, codigo) {
  return guias.filter(
    (g) => g.despacho_corte === codigo && !ESTADOS_CERRADOS.has(g.estado),
  );
}

// Despacho Corte: como la carga masiva (POST /guias/lote), pero todas las
// guías quedan unidas en un corte con un mismo código; salen juntas y
// llegan juntas (POST /despachos-corte/:codigo/llegada). Con
// `despachoCorte` (el código de uno que sigue en camino) las suma a ese
// corte en vez de crear otro. Responde { despacho_corte, resultados }.
app.post('/despachos-corte', async (req, res, next) => {
  try {
    const { guias, despachoCorte } = req.body || {};
    if (!Array.isArray(guias) || guias.length === 0) {
      return res.status(400).json({ error: 'Faltan las guías del despacho.' });
    }
    if (guias.length > MAX_GUIAS_POR_LOTE) {
      return res.status(400).json({
        error: `Máximo ${MAX_GUIAS_POR_LOTE} guías por despacho.`,
      });
    }
    const existentes = await repo.listarGuias({ fresco: true });
    if (
      despachoCorte
      && !abiertasDelCorte(existentes, despachoCorte).some((g) =>
        mismoNombre(g.transportista, guias[0] && guias[0].transportista))
    ) {
      return res.status(409).json({
        error: `El despacho ${despachoCorte} ya llegó o no es tuyo.`,
      });
    }
    const codigo = despachoCorte || nuevoCodigoCorte();
    const sucursales = await sucursalesParaRegistro();
    const resultados = [];
    const nuevas = [];
    for (const datos of guias) {
      const preparada = prepararGuia(datos, [...existentes, ...nuevas], sucursales);
      if (preparada.error) {
        resultados.push({ error: preparada.error });
      } else {
        preparada.guia.despacho_corte = codigo;
        nuevas.push(preparada.guia);
        resultados.push({ guia: preparada.guia });
      }
    }
    if (nuevas.length > 0) await repo.crearGuias(nuevas);
    res.json({ despacho_corte: nuevas.length > 0 ? codigo : null, resultados });
  } catch (err) {
    next(err);
  }
});

// Llegada del Despacho Corte: todas las guías del corte que siguen en
// camino pasan a "entregado" a la vez, sin foto, con la hora y el GPS de
// la llegada. Las quitadas o rechazadas antes no se tocan.
app.post('/despachos-corte/:codigo/llegada', async (req, res, next) => {
  try {
    const { codigo } = req.params;
    const { geo, transportista } = req.body || {};
    if (!geo || typeof geo.lat !== 'number' || typeof geo.lng !== 'number') {
      return res.status(400).json({ error: 'GPS obligatorio para registrar la llegada.' });
    }
    const guias = abiertasDelCorte(await repo.listarGuias({ fresco: true }), codigo);
    if (guias.length === 0) {
      return res.status(404).json({
        error: `El despacho ${codigo} no tiene guías en camino.`,
      });
    }
    if (transportista && guias.some((g) => !mismoNombre(g.transportista, transportista))) {
      return res.status(403).json({ error: 'Este despacho es de otro transportista.' });
    }
    const ahora = new Date().toISOString();
    for (const guia of guias) {
      guia.estado = ESTADOS.ENTREGADO;
      guia.fecha_actualizacion = ahora;
      guia.fecha_cierre = ahora;
      guia.geo_lat = geo.lat;
      guia.geo_lng = geo.lng;
      guia.cierre_lat = geo.lat;
      guia.cierre_lng = geo.lng;
      guia.eliminacion = '';
      guia.motivo_eliminacion = '';
      limpiarTransbordoAbierto(guia);
    }
    await repo.actualizarGuias(guias);
    res.json({ despacho_corte: codigo, guias: guias.map(sinCamposInternos) });
  } catch (err) {
    next(err);
  }
});

// Quita una guía de su Despacho Corte (por ejemplo, mal escaneada): sigue
// como una tarea normal del transportista, que puede entregarla aparte o
// pedir que se elimine.
app.post('/despachos-corte/:codigo/quitar', async (req, res, next) => {
  try {
    const { codigo } = req.params;
    const { numeroGuia, fechaCreacion } = req.body || {};
    if (!numeroGuia) return res.status(400).json({ error: 'Falta numeroGuia.' });
    const guia = await buscarRegistro(numeroGuia, fechaCreacion);
    if (!guia || guia.despacho_corte !== codigo) {
      return res.status(404).json({
        error: `La guía ${numeroGuia} no está en el despacho ${codigo}.`,
      });
    }
    if (ESTADOS_CERRADOS.has(guia.estado)) {
      return res.status(409).json({ error: 'La guía ya está cerrada.' });
    }
    guia.despacho_corte = '';
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// Actualiza el estado de una guía (entrega, trasbordo, recepción, o
// corrección manual de administrador). GPS obligatorio salvo cuando lo
// hace un administrador desde el panel (porAdmin: true).
app.patch('/guias/:numeroGuia/estado', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const { estado, geo, porAdmin, foto, fechaCreacion } = req.body || {};

    if (!ESTADOS_VALIDOS.has(estado)) {
      return res.status(400).json({ error: `Estado inválido: ${estado}` });
    }
    if (!porAdmin && estado === ESTADOS.RECHAZADO) {
      return res.status(400).json({
        error: 'Para rechazar una tarea usa POST /guias/:numeroGuia/rechazo con el motivo.',
      });
    }
    if (!porAdmin && (!geo || typeof geo.lat !== 'number' || typeof geo.lng !== 'number')) {
      return res.status(400).json({
        error: 'GPS obligatorio para registrar este evento.',
      });
    }

    const guia = await buscarRegistro(numeroGuia, fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }

    // Geocerca: la llegada a la sucursal solo cuenta dentro de su perímetro.
    if (!porAdmin && estado === ESTADOS.RECEPCION_SUCURSAL) {
      const sucursal = buscarSucursal(await repo.listarSucursales(), guia.destino);
      if (!sucursal) {
        return res.status(409).json({
          error: `La sucursal "${guia.destino}" no tiene perímetro en el mapa. Pide al administrador que lo marque.`,
        });
      }
      const distancia = distanciaMetros(geo.lat, geo.lng, sucursal.lat, sucursal.lng);
      if (distancia > sucursal.radio_m) {
        return res.status(403).json({
          error: `Estás a ${Math.round(distancia)} m de ${sucursal.nombre}; debes estar dentro de ${sucursal.radio_m} m para registrar la llegada.`,
        });
      }
    }

    // Solo se guarda la foto de la entrega final (guía firmada por el
    // cliente, o comprobante de agencia) — no la de pasos intermedios.
    const entregaFinal = !porAdmin && ESTADOS_FINALES.has(estado);
    // La foto se guarda y, a la vez, la IA busca un comprobante de agencia.
    const [fotoEntrega, comprobante] = entregaFinal
      ? await Promise.all([
          intentarGuardarFoto(guia.numero_guia, foto),
          comprobanteDeEntrega(req.body, foto),
        ])
      : [{ url: null, aviso: null }, null];
    if (fotoEntrega.url) guia.foto_entrega_url = fotoEntrega.url;
    if (comprobante) Object.assign(guia, comprobante);

    guia.estado = estado;
    guia.fecha_actualizacion = new Date().toISOString();
    // Si ya avanzó, un pedido de eliminación pendiente deja de valer, y un
    // transbordo sin aceptar también (el aceptado queda como historia).
    if (estado !== ESTADOS.EN_RUTA) {
      guia.eliminacion = '';
      guia.motivo_eliminacion = '';
      limpiarTransbordoAbierto(guia);
    }
    if (geo) {
      guia.geo_lat = geo.lat;
      guia.geo_lng = geo.lng;
    }
    if (porAdmin) {
      guia.corregido_por_admin = true;
    } else if (ESTADOS_FINALES.has(estado)) {
      guia.cierre_lat = geo.lat;
      guia.cierre_lng = geo.lng;
      guia.fecha_cierre = guia.fecha_actualizacion;
      // Entregada dentro del perímetro de una sucursal: quedó ahí.
      try {
        const aqui = sucursalEnPunto(await repo.listarSucursales(), geo.lat, geo.lng);
        if (aqui) guia.destino = aqui.nombre;
      } catch (err) {
        console.error(err);
      }
    }
    await repo.actualizarGuia(guia._row, guia);

    res.json({
      ...sinCamposInternos(guia),
      ...(fotoEntrega.aviso && { aviso_foto: fotoEntrega.aviso }),
    });
  } catch (err) {
    next(err);
  }
});

// El transportista rechaza una tarea abierta; el motivo es obligatorio y
// queda en la hoja (motivo_rechazo). El GPS se guarda si viene, pero no se
// exige: el rechazo no debe bloquearse por no tener señal.
app.post('/guias/:numeroGuia/rechazo', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const { motivo, geo, fechaCreacion } = req.body || {};
    const motivoLimpio = String(motivo ?? '').trim();
    if (motivoLimpio.length < 3) {
      return res.status(400).json({ error: 'Indica el motivo del rechazo.' });
    }
    if (motivoLimpio.length > 300) {
      return res.status(400).json({ error: 'El motivo es muy largo (máx. 300 caracteres).' });
    }

    const guia = await buscarRegistro(numeroGuia, fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (ESTADOS_CERRADOS.has(guia.estado)) {
      return res.status(409).json({
        error: `La guía ${numeroGuia} ya está cerrada (${guia.estado}); no se puede rechazar.`,
      });
    }

    guia.estado = ESTADOS.RECHAZADO;
    guia.motivo_rechazo = motivoLimpio;
    guia.eliminacion = '';
    guia.motivo_eliminacion = '';
    limpiarTransbordoAbierto(guia);
    guia.fecha_actualizacion = new Date().toISOString();
    if (geo && typeof geo.lat === 'number' && typeof geo.lng === 'number') {
      guia.geo_lat = geo.lat;
      guia.geo_lng = geo.lng;
    }
    await repo.actualizarGuia(guia._row, guia);

    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// ¿Se están guardando las fotos? El panel del admin avisa si no.
app.get('/fotos/estado', (_req, res) => {
  res.json({ configurado: fotos.almacenamientoConfigurado() });
});

// Foto de la entrega de una guía. Las fotos son privadas en Vercel Blob:
// solo se ven pasando por aquí.
app.get('/guias/:numeroGuia/foto', async (req, res, next) => {
  try {
    const guia = await repo.buscarPorNumero(req.params.numeroGuia);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${req.params.numeroGuia}` });
    }
    if (!guia.foto_entrega_url) {
      return res.status(404).json({ error: 'Esta guía no tiene foto de entrega.' });
    }
    await fotos.enviarFoto(guia.foto_entrega_url, res);
  } catch (err) {
    next(err);
  }
});

// Corrección manual del número de guía (solo administrador — ver nota de
// seguridad al inicio de este archivo).
app.patch('/guias/:numeroGuia/numero', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const { numeroNuevo } = req.body || {};
    if (!numeroNuevo) {
      return res.status(400).json({ error: 'Falta numeroNuevo.' });
    }

    const guia = await repo.buscarPorNumero(numeroGuia, { fresco: true });
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }

    const duplicado = await repo.buscarPorNumero(numeroNuevo, { fresco: true });
    if (duplicado && !ESTADOS_CERRADOS.has(duplicado.estado)) {
      return res.status(409).json({ error: `Ya existe una guía activa con el número ${numeroNuevo}.` });
    }

    guia.numero_guia = numeroNuevo;
    guia.corregido_por_admin = true;
    guia.fecha_actualizacion = new Date().toISOString();
    await repo.actualizarGuia(guia._row, guia);

    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// Cambia el tipo de entrega. El transportista solo puede mientras la guía
// está en ruta (antes de iniciar un traslado o entregarla); el
// administrador (porAdmin: true), siempre.
app.patch('/guias/:numeroGuia/tipo', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const { tipoEntrega, destino, porAdmin, fechaCreacion } = req.body || {};
    if (!TIPOS_VALIDOS.has(tipoEntrega)) {
      return res.status(400).json({ error: tipoInvalido(tipoEntrega) });
    }
    const guia = await buscarRegistro(numeroGuia, fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (!porAdmin && guia.estado !== ESTADOS.EN_RUTA) {
      return res.status(409).json({
        error: 'Solo se puede cambiar el tipo de entrega mientras la guía está en ruta.',
      });
    }

    const destinoPedido = String(destino ?? '').trim();
    if (destinoPedido) guia.destino = destinoPedido;
    guia.tipo_entrega = tipoEntrega;
    guia.fecha_actualizacion = new Date().toISOString();
    if (porAdmin) guia.corregido_por_admin = true;
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// El transportista pide borrar una tarea que se asignó (solo en ruta). No se
// borra todavía: el administrador la ve como novedad y decide.
app.post('/guias/:numeroGuia/solicitud-eliminacion', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const { motivo, fechaCreacion } = req.body || {};
    const validado = motivoValido(motivo);
    if (validado.error) return res.status(400).json({ error: validado.error });

    const guia = await buscarRegistro(numeroGuia, fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (guia.estado !== ESTADOS.EN_RUTA) {
      return res.status(409).json({
        error: 'Solo se puede pedir eliminar una tarea que está en ruta.',
      });
    }
    guia.eliminacion = ELIMINACION.PENDIENTE;
    guia.motivo_eliminacion = validado.motivo;
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// El transportista retira su pedido de eliminación.
app.delete('/guias/:numeroGuia/solicitud-eliminacion', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const guia = await buscarRegistro(numeroGuia, req.query.fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    guia.eliminacion = '';
    guia.motivo_eliminacion = '';
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// El administrador no aprueba borrar la tarea: sigue como estaba y el
// transportista ve que se rechazó.
app.post('/guias/:numeroGuia/solicitud-eliminacion/rechazo', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const guia = await buscarRegistro(numeroGuia, (req.body || {}).fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (guia.eliminacion !== ELIMINACION.PENDIENTE) {
      return res.status(409).json({ error: 'Esta guía no tiene un pedido de eliminación pendiente.' });
    }
    guia.eliminacion = ELIMINACION.RECHAZADA;
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// Los transportistas activos, para elegir a quién pasar una tarea.
app.get('/transportistas', async (_req, res, next) => {
  try {
    res.json((await transportistasActivos()).map((nombre) => ({ nombre })));
  } catch (err) {
    next(err);
  }
});

// Transbordo: el transportista pasa una tarea en ruta a otro transportista.
// No cambia de dueño hasta que el otro acepte; mientras tanto sigue en la
// lista de quien la envió, que puede cancelarlo o entregarla él mismo.
app.post('/guias/:numeroGuia/transbordo', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const { fechaCreacion, de, a } = req.body || {};
    if (!String(a ?? '').trim()) {
      return res.status(400).json({ error: 'Elige a qué transportista pasar la tarea.' });
    }
    const guia = await buscarRegistro(numeroGuia, fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (guia.estado !== ESTADOS.EN_RUTA) {
      return res.status(409).json({
        error: 'Solo se puede hacer transbordo de una tarea que está en ruta.',
      });
    }
    if (de && !mismoNombre(de, guia.transportista)) {
      return res.status(403).json({ error: 'Esta tarea no es tuya.' });
    }
    if (guia.transbordo_estado === TRANSBORDO.PENDIENTE) {
      return res.status(409).json({
        error: `Ya estás esperando que ${guia.transbordo_a} acepte esta tarea.`,
      });
    }
    const destino = (await transportistasActivos()).find((n) => mismoNombre(n, a));
    if (!destino) {
      return res.status(400).json({ error: `"${a}" no es un transportista activo.` });
    }
    if (mismoNombre(destino, guia.transportista)) {
      return res.status(400).json({ error: 'No puedes pasarte la tarea a ti mismo.' });
    }
    guia.transbordo_estado = TRANSBORDO.PENDIENTE;
    guia.transbordo_a = destino;
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// Quien envió el transbordo lo cancela antes de que el otro responda.
app.delete('/guias/:numeroGuia/transbordo', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const guia = await buscarRegistro(numeroGuia, req.query.fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (guia.transbordo_estado !== TRANSBORDO.PENDIENTE) {
      return res.status(409).json({ error: 'Esta tarea no tiene un transbordo pendiente.' });
    }
    guia.transbordo_estado = '';
    guia.transbordo_a = '';
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// El transportista que recibe el transbordo lo acepta (la tarea pasa a ser
// suya; sale de donde salió originalmente) o lo rechaza (vuelve a quien la
// envió, que ve que no la aceptó).
app.post('/guias/:numeroGuia/transbordo/respuesta', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const { fechaCreacion, quien, acepta } = req.body || {};
    if (typeof acepta !== 'boolean') {
      return res.status(400).json({ error: 'Indica si aceptas o rechazas el transbordo.' });
    }
    const guia = await buscarRegistro(numeroGuia, fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (guia.transbordo_estado !== TRANSBORDO.PENDIENTE) {
      return res.status(409).json({
        error: 'Este transbordo ya no está pendiente (lo cancelaron o ya se respondió).',
      });
    }
    if (!mismoNombre(quien, guia.transbordo_a)) {
      return res.status(403).json({ error: 'Este transbordo no es para ti.' });
    }
    if (guia.estado !== ESTADOS.EN_RUTA) {
      limpiarTransbordoAbierto(guia);
      await repo.actualizarGuia(guia._row, guia);
      return res.status(409).json({ error: 'Esta tarea ya no está en ruta.' });
    }
    if (acepta) {
      guia.transbordo_de = guia.transportista;
      guia.transportista = guia.transbordo_a;
      guia.transbordo_estado = TRANSBORDO.ACEPTADO;
      guia.transbordo_a = '';
      // El pedido de eliminación era de quien la envió.
      guia.eliminacion = '';
      guia.motivo_eliminacion = '';
      // Ya no viaja en el Despacho Corte de quien la envió.
      guia.despacho_corte = '';
      guia.fecha_actualizacion = new Date().toISOString();
    } else {
      guia.transbordo_estado = TRANSBORDO.RECHAZADO;
    }
    await repo.actualizarGuia(guia._row, guia);
    res.json(sinCamposInternos(guia));
  } catch (err) {
    next(err);
  }
});

// Borra la tarea por completo de la hoja (solo administrador; por ejemplo al
// aprobar el pedido del transportista). Solo mientras está en ruta: una
// guía entregada o en trasbordo ya es historia y no se borra (el
// administrador puede corregir datos o quitar la foto).
app.delete('/guias/:numeroGuia', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const guia = await buscarRegistro(numeroGuia, req.query.fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (guia.estado !== ESTADOS.EN_RUTA) {
      return res.status(409).json({
        error:
          'Solo se pueden eliminar tareas en ruta. En una guía cerrada puedes '
          + 'corregir los datos o quitar la foto.',
      });
    }
    await repo.eliminarGuia(guia);
    res.json({ eliminada: true, numero_guia: guia.numero_guia });
  } catch (err) {
    next(err);
  }
});

// Quita la foto de la entrega (solo administrador). La guía sigue igual.
app.delete('/guias/:numeroGuia/foto', async (req, res, next) => {
  try {
    const { numeroGuia } = req.params;
    const guia = await buscarRegistro(numeroGuia, req.query.fechaCreacion);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }
    if (!guia.foto_entrega_url) {
      return res.status(404).json({ error: 'Esta guía no tiene foto de entrega.' });
    }
    let aviso = null;
    try {
      await fotos.eliminarFoto(guia.foto_entrega_url);
    } catch (err) {
      console.error(err);
      aviso = `Se quitó de la guía, pero el archivo no se pudo borrar: ${err.message}`;
    }
    guia.foto_entrega_url = '';
    guia.corregido_por_admin = true;
    guia.fecha_actualizacion = new Date().toISOString();
    await repo.actualizarGuia(guia._row, guia);
    res.json({ ...sinCamposInternos(guia), ...(aviso && { aviso_foto: aviso }) });
  } catch (err) {
    next(err);
  }
});

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error(err);
  if (err.status) return res.status(err.status).json({ error: err.message });
  res.status(500).json({ error: 'Error interno del servidor.' });
});

module.exports = app;
