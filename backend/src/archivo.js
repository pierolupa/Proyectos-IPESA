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
 * Fecha de corte del archivo (ARCHIVO_HASTA): todo lo registrado antes de
 * esa fecha está en las pestañas de año. Sin configurar, Infinity: se mira
 * el archivo en cualquier consulta con fecha de inicio (más lento, pero
 * nunca deja guías afuera).
 */
function corteArchivo() {
  const t = Date.parse(process.env.ARCHIVO_HASTA || '');
  return Number.isFinite(t) ? t : Infinity;
}

/** ¿Hace falta mirar el archivo para una consulta que empieza en `desdeMs`? */
function hacenFaltaArchivo(desdeMs) {
  if (!Number.isFinite(desdeMs)) return false;
  return desdeMs < corteArchivo();
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
  corteArchivo,
  hacenFaltaArchivo,
  seleccionarParaArchivar,
  agruparPorAnio,
};
