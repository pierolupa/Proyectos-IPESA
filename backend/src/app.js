const express = require('express');
const cors = require('cors');
const { ESTADOS, ESTADOS_FINALES, TIPOS_ENTREGA, ROLES } = require('./columns');
const repo = require('./sheetsRepository');
const { leerGuiaConIA } = require('./ocrAgente');

const app = express();
app.use(cors({ origin: true }));
// Límite alto: el body incluye la foto de la guía en base64 para /ocr/leer-guia.
app.use(express.json({ limit: '8mb' }));

const ESTADOS_VALIDOS = new Set(Object.values(ESTADOS));
const TIPOS_VALIDOS = new Set(Object.values(TIPOS_ENTREGA));
const ROLES_VALIDOS = new Set(Object.values(ROLES));

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

function guiaPublica(guia) {
  // Vista de rastreo (equipo comercial): nunca exponer datos completos del
  // destinatario ni del transportista (ARCHITECTURE.md, sección 6).
  return {
    ultimos_cuatro: guia.numero_guia.slice(-4),
    estado: guia.estado,
    destino: guia.destino,
  };
}

function sinCamposInternos(guia) {
  const { _row, ...resto } = guia;
  return resto;
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

// Administrador: lista completa, con filtro opcional por estado.
app.get('/guias', async (req, res, next) => {
  try {
    const { estado } = req.query;
    let guias = await repo.listarGuias();
    if (estado) {
      if (!ESTADOS_VALIDOS.has(estado)) {
        return res.status(400).json({ error: `Estado inválido: ${estado}` });
      }
      guias = guias.filter((g) => g.estado === estado);
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

// Equipo comercial / público: rastreo por últimos 4 dígitos, sin login.
app.get('/guias/rastreo/:ultimosCuatro', async (req, res, next) => {
  try {
    const { ultimosCuatro } = req.params;
    if (!/^\d{4}$/.test(ultimosCuatro)) {
      return res.status(400).json({ error: 'Debe enviar exactamente 4 dígitos.' });
    }
    const guias = await repo.listarGuias();
    const encontradas = guias.filter((g) => g.numero_guia.endsWith(ultimosCuatro));
    res.json(encontradas.map(guiaPublica));
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
      return res.status(400).json({ error: `tipoEntrega inválido: ${tipoEntrega}` });
    }
    if (!geo || typeof geo.lat !== 'number' || typeof geo.lng !== 'number') {
      return res.status(400).json({
        error: 'GPS obligatorio: no se puede registrar una guía sin geolocalización.',
      });
    }

    const existente = await repo.buscarPorNumero(numeroGuia);
    if (existente && !ESTADOS_FINALES.has(existente.estado)) {
      return res.status(409).json({
        error: `La guía ${numeroGuia} ya está activa (estado: ${existente.estado}).`,
      });
    }

    const ahora = new Date().toISOString();
    await repo.crearGuia({
      numero_guia: numeroGuia,
      estado: ESTADOS.EN_RUTA,
      tipo_entrega: tipoEntrega,
      origen,
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
    });

    res.status(201).json({ numeroGuia, estado: ESTADOS.EN_RUTA });
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
    const { estado, geo, porAdmin } = req.body || {};

    if (!ESTADOS_VALIDOS.has(estado)) {
      return res.status(400).json({ error: `Estado inválido: ${estado}` });
    }
    if (!porAdmin && (!geo || typeof geo.lat !== 'number' || typeof geo.lng !== 'number')) {
      return res.status(400).json({
        error: 'GPS obligatorio para registrar este evento.',
      });
    }

    const guia = await repo.buscarPorNumero(numeroGuia);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }

    guia.estado = estado;
    guia.fecha_actualizacion = new Date().toISOString();
    if (geo) {
      guia.geo_lat = geo.lat;
      guia.geo_lng = geo.lng;
    }
    if (porAdmin) {
      guia.corregido_por_admin = true;
    }
    await repo.actualizarGuia(guia._row, guia);

    res.json(sinCamposInternos(guia));
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

    const guia = await repo.buscarPorNumero(numeroGuia);
    if (!guia) {
      return res.status(404).json({ error: `Guía no encontrada: ${numeroGuia}` });
    }

    const duplicado = await repo.buscarPorNumero(numeroNuevo);
    if (duplicado && !ESTADOS_FINALES.has(duplicado.estado)) {
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

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'Error interno del servidor.' });
});

module.exports = app;
