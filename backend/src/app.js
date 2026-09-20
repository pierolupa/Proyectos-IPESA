const express = require('express');
const cors = require('cors');
const { ESTADOS, ESTADOS_FINALES, TIPOS_ENTREGA } = require('./columns');
const repo = require('./sheetsRepository');

const app = express();
app.use(cors({ origin: true }));
app.use(express.json());

const ESTADOS_VALIDOS = new Set(Object.values(ESTADOS));
const TIPOS_VALIDOS = new Set(Object.values(TIPOS_ENTREGA));

/**
 * NOTA DE SEGURIDAD: esta API todavía no implementa autenticación ni
 * autorización por rol (ver ARCHITECTURE.md, sección 8 — decisión
 * pendiente). Antes de un despliegue real hay que exigir un token válido
 * (Firebase Auth, por ejemplo) y verificar el rol del usuario en cada
 * endpoint sensible (asignar, corregir número, editar estado como admin).
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
