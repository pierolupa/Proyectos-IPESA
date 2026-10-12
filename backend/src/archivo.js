/*
 * Archivo por año de la hoja de guías (lógica pura, sin llamar a Google).
 *
 * Las guías cerradas de años anteriores se mueven a pestañas aparte
 * ("Guías 2026", "Guías 2027"...), con la misma estructura que "Guias". Así
 * la hoja activa queda chica y las lecturas siguen rápidas.
 *
 * - La app nunca escribe en las pestañas de archivo: solo se leen cuando una
 *   consulta pide fechas anteriores a lo que tiene la hoja activa.
 * - Las pestañas que existen se listan en PESTANAS_ARCHIVO (separadas por
 *   coma). Sin esa variable, todo funciona como antes.
 */
const { ESTADOS_CERRADOS } = require('./columns');

/** "Guías 2026": el nombre de la pestaña de un año. */
function pestanaDeAnio(anio) {
  return `Guías ${anio}`;
}

/** Las pestañas de archivo configuradas en PESTANAS_ARCHIVO. */
function pestanasArchivo() {
  return String(process.env.PESTANAS_ARCHIVO || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * ¿Hace falta revisar el archivo para una consulta con fecha de inicio?
 * Siempre que haya pestañas de archivo y la consulta tenga fecha de inicio:
 * como solo se leen las filas del rango, no pesa, y así ninguna guía se
 * queda fuera aunque cambie la fecha de corte.
 */
function hacenFaltaArchivo(desdeMs) {
  return Number.isFinite(desdeMs) && pestanasArchivo().length > 0;
}

/** El año de una pestaña de archivo: "Guías 2026" → 2026 (null si no tiene). */
function anioDePestana(titulo) {
  const m = /(\d{4})\s*$/.exec(String(titulo));
  return m ? Number(m[1]) : null;
}

/** ¿La pestaña de ese año puede tener guías entre `desdeMs` y `hastaMs`? */
function anioEnRango(anio, desdeMs, hastaMs) {
  if (anio === null) return true;
  const inicio = Date.UTC(anio, 0, 1);
  const fin = Date.UTC(anio + 1, 0, 1);
  if (Number.isFinite(desdeMs) && fin <= desdeMs) return false;
  if (Number.isFinite(hastaMs) && inicio > hastaMs) return false;
  return true;
}

/**
 * De una lista de fechas (una por fila, en orden), las posiciones de la
 * primera y la última que caen en [desdeMs, hastaMs). Las filas se leen
 * de corrido entre ambas. null si ninguna cae en el rango.
 */
function rangoDeFilas(fechas, desdeMs, hastaMs) {
  let primera = -1;
  let ultima = -1;
  fechas.forEach((f, i) => {
    const t = Date.parse(f);
    if (!Number.isFinite(t)) return;
    if (Number.isFinite(desdeMs) && t < desdeMs) return;
    if (Number.isFinite(hastaMs) && t >= hastaMs) return;
    if (primera === -1) primera = i;
    ultima = i;
  });
  return primera === -1 ? null : { primera, ultima };
}

/**
 * Las guías que se pueden archivar: cerradas (entregadas, finalizadas o
 * rechazadas), registradas antes de `hasta`, y sin nada pendiente (ni una
 * eliminación ni un transbordo esperando respuesta).
 */
function seleccionarParaArchivar(guias, hasta) {
  const corte = Date.parse(hasta);
  if (!Number.isFinite(corte)) throw new Error('Fecha de corte inválida (usa AAAA-MM-DD).');
  return guias
    .filter((g) => ESTADOS_CERRADOS.has(g.estado))
    .filter((g) => !g.eliminacion && !g.transbordo_estado)
    .filter((g) => {
      const t = Date.parse(g.fecha_creacion);
      return Number.isFinite(t) && t < corte;
    })
    .sort((a, b) => a.fecha_creacion.localeCompare(b.fecha_creacion));
}

/** Agrupa las guías por año de registro: { "2026": [...], ... }. */
function agruparPorAnio(guias) {
  const grupos = {};
  for (const g of guias) {
    const anio = String(new Date(g.fecha_creacion).getUTCFullYear());
    (grupos[anio] ||= []).push(g);
  }
  return grupos;
}

module.exports = {
  pestanaDeAnio,
  pestanasArchivo,
  hacenFaltaArchivo,
  seleccionarParaArchivar,
  agruparPorAnio,
  anioDePestana,
  anioEnRango,
  rangoDeFilas,
};
