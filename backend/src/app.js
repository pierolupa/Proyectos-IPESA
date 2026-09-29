const express = require('express');
const cors = require('cors');
const {
  ESTADOS,
  ESTADOS_FINALES,
  ESTADOS_CERRADOS,
  ELIMINACION,
  TIPOS_ENTREGA,
  ROLES,
} = require('./columns');
const repo = require('./sheetsRepository');
const { leerGuiaConIA } = require('./ocrAgente');
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

// Tiempo mínimo entre dos registros del mismo número de guía.
const ESPERA_MISMA_GUIA_MS = 2 * 60 * 60 * 1000;

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

function sinCamposInternos(guia) {
  const { _row, ...resto } = guia;
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

// Lee la foto de una guía con IA (Claude, con visión) y devuelve los datos
// extraídos. Ver ocrAgente.js — reemplaza el OCR anterior (Tesseract.js en
// el navegador), que no leía de forma confiable formularios densos con
// tablas. Requiere ANTHROPIC_API_KEY (ver README.md); tiene un costo
// pequeño por foto.
app.post('/ocr/leer-guia', async (req, res, next) => {
  try {
    const { imagenBase64, mediaType } = req.body || {};
    if (!imagenBase64) {
      return res.status(400).json({ error: 'Falta imagenBase64.' });
    }
    const datos = await leerGuiaConIA(imagenBase64, mediaType || 'image/jpeg');
    res.json(datos);
  } catch (err) {
    // Se responde con el mensaje real (a diferencia del resto de rutas, que
    // usan el manejador genérico) porque este proyecto de Vercel no tiene
    // acceso a runtime logs (403) — sin esto, un fallo de la IA es
    // indiagnosticable desde afuera. No es información sensible: es un
    // error de la librería de Gemini, no un dato de la guía ni la API key.
    console.error(err);
    res.status(500).json({ error: `Fallo al leer la guía con IA: ${err.message}` });
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
    const propias = guias.filter((g) => g.transportista === req.params.nombre);
    res.json(propias.map(sinCamposInternos));
  } catch (err) {
    next(err);
  }
});

// Asignación: crea una guía "en ruta" a partir del número leído por OCR.
// GPS obligatorio (ARCHITECTURE.md, sección 5).
app.post('/guias', async (req, res, next) => {
  try {
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
    } = req.body || {};

    if (!numeroGuia || !origen || !destino || !transportista || !destinatario) {
      return res.status(400).json({ error: 'Faltan campos obligatorios.' });
    }
    if (!TIPOS_VALIDOS.has(tipoEntrega)) {
      return res.status(400).json({ error: tipoInvalido(tipoEntrega) });
    }
    if (!geo || typeof geo.lat !== 'number' || typeof geo.lng !== 'number') {
      return res.status(400).json({
        error: 'GPS obligatorio: no se puede registrar una guía sin geolocalización.',
      });
    }


    // Un mismo número de guía se puede volver a registrar (otro viaje de
    // la misma guía), pero no dentro de las 2 horas siguientes al último
    // registro: eso casi siempre es la misma foto enviada dos veces. Si el
    // último fue rechazado, la tarea nunca se hizo: se puede volver a
    // registrar al momento.
    const existente = await repo.buscarPorNumero(numeroGuia, { fresco: true });
    if (existente && existente.estado !== ESTADOS.RECHAZADO) {
      const registrada = Date.parse(existente.fecha_creacion || existente.fecha_actualizacion);
      const libreDesde = registrada + ESPERA_MISMA_GUIA_MS;
      if (!Number.isNaN(registrada) && Date.now() < libreDesde) {
        const minutos = Math.max(1, Math.round((Date.now() - registrada) / 60000));
        return res.status(409).json({
          error:
            `La guía ${numeroGuia} ya se registró hace ${minutos} min. `
            + `Podrás volver a registrarla desde las ${horaPeru(libreDesde)}.`,
        });
      }
    }

    // Si se registra dentro del perímetro de una sucursal, sale de ahí.
    let origenFinal = origen;
    try {
      const aqui = sucursalEnPunto(await repo.listarSucursales(), geo.lat, geo.lng);
      if (aqui) origenFinal = aqui.nombre;
    } catch (err) {
      console.error(err);
    }

    const ahora = new Date().toISOString();
    const nueva = {
      numero_guia: numeroGuia,
      estado: ESTADOS.EN_RUTA,
      tipo_entrega: tipoEntrega,
      origen: origenFinal,
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
    };
    await repo.crearGuia(nueva);

    // La guía completa: la app la agrega a su lista sin volver a pedirlas
    // todas.
    res.status(201).json({ ...nueva, numeroGuia, estado: ESTADOS.EN_RUTA });
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
    const { estado, geo, porAdmin, foto } = req.body || {};

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

    const guia = await repo.buscarPorNumero(numeroGuia, { fresco: true });
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
    const fotoEntrega =
      porAdmin || !ESTADOS_FINALES.has(estado)
        ? { url: null, aviso: null }
        : await intentarGuardarFoto(guia.numero_guia, foto);
    if (fotoEntrega.url) guia.foto_entrega_url = fotoEntrega.url;

    guia.estado = estado;
    guia.fecha_actualizacion = new Date().toISOString();
    // Si ya avanzó, un pedido de eliminación pendiente deja de valer.
    if (estado !== ESTADOS.EN_RUTA) {
      guia.eliminacion = '';
      guia.motivo_eliminacion = '';
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
    const { motivo, geo } = req.body || {};
    const motivoLimpio = String(motivo ?? '').trim();
    if (motivoLimpio.length < 3) {
      return res.status(400).json({ error: 'Indica el motivo del rechazo.' });
    }
    if (motivoLimpio.length > 300) {
      return res.status(400).json({ error: 'El motivo es muy largo (máx. 300 caracteres).' });
    }

    const guia = await repo.buscarPorNumero(numeroGuia, { fresco: true });
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
