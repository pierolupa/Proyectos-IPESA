/*
 * Archivo por año de la hoja de guías (lógica pura, sin llamar a Google).
 *
 * Las guías cerradas de años anteriores se mueven a pestañas aparte
 * ("Guías 2026", "Guías 2027"...), con la misma estructura que "Guias". Así
 * la hoja activa queda chica y las lecturas siguen rápidas.
 *
 * - Las pestañas se reconocen solas por el nombre ("Guías " + año): no hay
 *   nada que configurar en Vercel. Sin pestañas, todo funciona como antes.
 * - Solo se leen cuando una consulta pide fechas que pueden estar archivadas
 *   (anteriores a la última guía archivada).
 */
const { ESTADOS_CERRADOS } = require('./columns');

/** "Guías 2026": el nombre de la pestaña de un año. */
function pestanaDeAnio(anio) {
  return `Guías ${anio}`;
}

/** ¿Es una pestaña de archivo? "Guías 2026" sí; "Guias", "Usuarios" no. */
function esPestanaArchivo(titulo) {
  return /^Guías \d{4}$/.test(String(titulo).trim());
}

/**
 * ¿Hace falta revisar el archivo para una consulta desde `desdeMs`?
 * `info` = { pestanas, ultima }: las pestañas de archivo y la fecha de la
 * guía archivada más reciente. Si la consulta empieza después, nada del
 * archivo puede entrar (así el refresco cada 15 s nunca lo lee).
 */
function hacenFaltaArchivo(desdeMs, info) {
  if (!Number.isFinite(desdeMs) || !info || info.pestanas.length === 0) return false;
  return !Number.isFinite(info.ultima) || desdeMs <= info.ultima;
}

/**
 * El corte más reciente permitido: el día 1 del mes en curso (hora de
 * Perú). Se archiva por meses completos y nunca el mes que está corriendo.
 */
function corteMaximo(ahoraMs = Date.now()) {
  const peru = new Date(ahoraMs - 5 * 60 * 60 * 1000);
  const mes = String(peru.getUTCMonth() + 1).padStart(2, '0');
  return `${peru.getUTCFullYear()}-${mes}-01`;
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
  esPestanaArchivo,
  hacenFaltaArchivo,
  corteMaximo,
  seleccionarParaArchivar,
  agruparPorAnio,
  anioDePestana,
  anioEnRango,
  rangoDeFilas,
};
