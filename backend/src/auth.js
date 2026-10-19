/*
 * Sesiones de la API.
 *
 * El login entrega un token firmado (HMAC-SHA256) con el nombre, el rol y
 * el vencimiento. La app lo manda en cada pedido como
 * "Authorization: Bearer <token>" y el servidor lo verifica sin leer la
 * hoja. Nadie puede fabricar ni cambiar un token sin la clave de firma.
 *
 * La clave de firma es AUTH_SECRET si está configurada en Vercel (se
 * recomienda una de 32 caracteres o más). Si no, se deriva de la clave de la
 * cuenta de servicio de Google, que ya está en Vercel y nunca sale del
 * servidor. Cambiar cualquiera de las dos cierra todas las sesiones.
 */
const crypto = require('crypto');

// La app vuelve a entrar sola con la cuenta guardada cuando vence, así que
// puede ser corta: un usuario dado de baja pierde el acceso en ese plazo.
const DURACION_SESION_MS = 12 * 60 * 60 * 1000;

// Freno a quien prueba PINs: tras MAX_FALLOS intentos fallidos con un mismo
// nombre, ese nombre queda bloqueado BLOQUEO_MS. Vive en la memoria de cada
// instancia del servidor (no es perfecto, pero frena un ataque simple).
const MAX_FALLOS = 5;
const BLOQUEO_MS = 15 * 60 * 1000;

function claveFirma() {
  const propia = process.env.AUTH_SECRET;
  if (propia) return propia;
  const google = process.env.GOOGLE_SERVICE_ACCOUNT_KEY;
  if (!google) {
    throw new Error('Falta AUTH_SECRET o GOOGLE_SERVICE_ACCOUNT_KEY para firmar las sesiones.');
  }
  return crypto.createHash('sha256').update(`ipesa-sesiones-v1\n${google}`).digest();
}

function firmar(cuerpo) {
  return crypto.createHmac('sha256', claveFirma()).update(cuerpo).digest('base64url');
}

/** Token para { nombre, rol }; `expira` en ISO. */
function crearToken({ nombre, rol }, ahora = Date.now()) {
  const exp = ahora + DURACION_SESION_MS;
  const cuerpo = Buffer.from(JSON.stringify({ n: nombre, r: rol, exp })).toString('base64url');
  return { token: `${cuerpo}.${firmar(cuerpo)}`, expira: new Date(exp).toISOString() };
}

/** { nombre, rol } si el token es auténtico y no venció; si no, null. */
function leerToken(token, ahora = Date.now()) {
  if (typeof token !== 'string') return null;
  const partes = token.split('.');
  if (partes.length !== 2 || !partes[0] || !partes[1]) return null;
  const [cuerpo, firma] = partes;
  const esperada = Buffer.from(firmar(cuerpo));
  const recibida = Buffer.from(firma);
  if (esperada.length !== recibida.length || !crypto.timingSafeEqual(esperada, recibida)) {
    return null;
  }
  let datos;
  try {
    datos = JSON.parse(Buffer.from(cuerpo, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (
    !datos
    || typeof datos.n !== 'string'
    || typeof datos.r !== 'string'
    || typeof datos.exp !== 'number'
    || datos.exp <= ahora
  ) {
    return null;
  }
  return { nombre: datos.n, rol: datos.r };
}

const fallos = new Map();
const claveNombre = (nombre) => String(nombre ?? '').trim().toLowerCase();

/** ¿Este nombre está bloqueado por demasiados intentos fallidos? */
function loginBloqueado(nombre, ahora = Date.now()) {
  const f = fallos.get(claveNombre(nombre));
  if (!f) return false;
  if (ahora - f.desde > BLOQUEO_MS) {
    fallos.delete(claveNombre(nombre));
    return false;
  }
  return f.n >= MAX_FALLOS;
}

function registrarFallo(nombre, ahora = Date.now()) {
  const clave = claveNombre(nombre);
  const f = fallos.get(clave);
  if (!f || ahora - f.desde > BLOQUEO_MS) {
    fallos.set(clave, { n: 1, desde: ahora });
  } else {
    f.n += 1;
  }
}

function limpiarFallos(nombre) {
  fallos.delete(claveNombre(nombre));
}

/** Solo para las pruebas. */
function olvidarFallos() {
  fallos.clear();
}

module.exports = {
  DURACION_SESION_MS,
  MAX_FALLOS,
  BLOQUEO_MS,
  crearToken,
  leerToken,
  loginBloqueado,
  registrarFallo,
  limpiarFallos,
  olvidarFallos,
};
