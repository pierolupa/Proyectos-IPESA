// Avisos al celular (Web Push): suenan aunque la app esté cerrada.
//
// Las claves VAPID salen de la clave de firma de las sesiones (ver
// auth.derivarClave): no hay otro secreto que guardar. La pública la pide
// la app para suscribirse; la privada solo vive en memoria del servidor.
const crypto = require('crypto');
const webpush = require('web-push');
const auth = require('./auth');
const { ESTADOS_CERRADOS } = require('./columns');

// Quién manda los avisos (lo exige el protocolo: una URL o un correo).
const REMITENTE = 'https://distribucion-ipesa-app.vercel.app';

// Si el celular está apagado, el aviso espera hasta 4 horas; después ya no
// sirve.
const VIGENCIA_S = 4 * 60 * 60;

let claves = null;

/** { publica, privada } en base64url, siempre las mismas para el servidor. */
function clavesVapid() {
  if (claves) return claves;
  for (let intento = 0; intento < 5; intento += 1) {
    const privada = auth.derivarClave(`avisos-vapid-v1-${intento}`);
    try {
      const ecdh = crypto.createECDH('prime256v1');
      ecdh.setPrivateKey(privada);
      claves = {
        publica: ecdh.getPublicKey().toString('base64url'),
        privada: privada.toString('base64url'),
      };
      return claves;
    } catch {
      // Casi imposible (la clave cae fuera de la curva): se prueba otra.
    }
  }
  throw new Error('No se pudieron preparar las claves de los avisos.');
}

/**
 * Manda un aviso a una suscripción { endpoint, p256dh, auth }.
 * Devuelve 'ok', 'vencida' (el celular la dio de baja: hay que borrarla) o
 * 'error'.
 */
async function enviar(suscripcion, datos) {
  const { publica, privada } = clavesVapid();
  try {
    await webpush.sendNotification(
      {
        endpoint: suscripcion.endpoint,
        keys: { p256dh: suscripcion.p256dh, auth: suscripcion.auth },
      },
      JSON.stringify(datos),
      {
        vapidDetails: { subject: REMITENTE, publicKey: publica, privateKey: privada },
        TTL: VIGENCIA_S,
        urgency: 'high',
      },
    );
    return 'ok';
  } catch (err) {
    if (err && (err.statusCode === 404 || err.statusCode === 410)) return 'vencida';
    console.error('Aviso no enviado:', err && (err.statusCode || err.message));
    return 'error';
  }
}

const clave = (nombre) => String(nombre ?? '').trim().toLowerCase();

/**
 * Las tareas que cada transportista tiene por cerrar: abiertas y que no
 * dejó en custodia. Map nombre (en minúsculas) → guías.
 */
function pendientesPorTransportista(guias) {
  const porNombre = new Map();
  for (const g of guias) {
    if (!g || ESTADOS_CERRADOS.has(g.estado)) continue;
    if (String(g.custodia_desde ?? '').trim()) continue;
    const k = clave(g.transportista);
    if (!k) continue;
    if (!porNombre.has(k)) porNombre.set(k, []);
    porNombre.get(k).push(g);
  }
  return porNombre;
}

/** Título y texto del recordatorio de las 6 p. m. */
function mensajeRecordatorio(pendientes) {
  const n = pendientes.length;
  const numeros = pendientes.slice(0, 3).map((g) => g.numero_guia);
  const resto = n - numeros.length;
  const lista = resto > 0 ? `${numeros.join(', ')} y ${resto} más` : numeros.join(', ');
  return {
    titulo: n === 1 ? 'Tienes 1 tarea por cerrar' : `Tienes ${n} tareas por cerrar`,
    cuerpo: `${lista}. Entrégalas, recházalas o déjalas en custodia.`,
    tag: 'recordatorio-6pm',
  };
}

module.exports = {
  clavesVapid,
  enviar,
  pendientesPorTransportista,
  mensajeRecordatorio,
  claveNombre: clave,
};
