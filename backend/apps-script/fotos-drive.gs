/**
 * IPESA · Tracking Distribución — fotos de entregas en Google Drive.
 *
 * Este script vive en la cuenta de Google de IPESA y guarda las fotos de
 * las entregas en la carpeta "Fotos RPA" de su Drive (se
 * crea sola). El backend (backend/src/fotos.js) lo llama con una clave;
 * las fotos NO quedan públicas: solo se ven a través de la app.
 *
 * Cómo instalarlo (una sola vez; pasos completos en backend/README.md):
 *  1. script.google.com → Nuevo proyecto → pega este archivo completo.
 *  2. Cambia CLAVE por una clave larga que inventes (la misma irá en
 *     Vercel como DRIVE_FOTOS_CLAVE). No la compartas.
 *  3. Ejecuta la función `autorizar` una vez y acepta los permisos.
 *  4. Implementar → Nueva implementación → Aplicación web:
 *     Ejecutar como "Yo", Quién tiene acceso "Cualquier persona".
 *     Copia la URL (termina en /exec) → Vercel: DRIVE_FOTOS_URL.
 *
 * Para actualizarlo (cuando cambie este archivo): pega el código nuevo,
 * deja tu CLAVE, guarda y ve a Implementar → Gestionar implementaciones →
 * lápiz → Versión: "Nueva versión" → Implementar. Así la URL no cambia.
 */

const CLAVE = 'ESCRIBE_AQUI_TU_CLAVE';
const NOMBRE_CARPETA = 'Fotos RPA';

function doPost(e) {
  try {
    const datos = JSON.parse(e.postData.contents);
    if (CLAVE === 'ESCRIBE_AQUI_TU_CLAVE' || datos.clave !== CLAVE) {
      return responder({ error: 'Clave incorrecta.' });
    }
    if (datos.accion === 'guardar') return responder({ id: guardar(datos) });
    if (datos.accion === 'leer') return responder(leer(datos.id));
    if (datos.accion === 'eliminar') return responder(eliminar(datos.id));
    if (datos.accion === 'buscar') return responder(buscar(datos));
    return responder({ error: 'Acción desconocida.' });
  } catch (err) {
    return responder({ error: String((err && err.message) || err) });
  }
}

/** Ejecútala una vez desde el editor para dar los permisos de Drive. */
function autorizar() {
  Logger.log('Carpeta lista: ' + carpeta().getUrl());
}

function carpeta() {
  const encontradas = DriveApp.getFoldersByName(NOMBRE_CARPETA);
  return encontradas.hasNext()
    ? encontradas.next()
    : DriveApp.createFolder(NOMBRE_CARPETA);
}

function guardar(datos) {
  const bytes = Utilities.base64Decode(datos.base64);
  const archivo = Utilities.newBlob(
    bytes,
    datos.tipo || 'image/jpeg',
    datos.nombre || 'foto.jpg',
  );
  return carpeta().createFile(archivo).getId();
}

/** Solo fotos de la carpeta de entregas: la clave no abre cualquier
 * archivo del Drive. */
function estaEnCarpeta(archivo) {
  const idCarpeta = carpeta().getId();
  const padres = archivo.getParents();
  while (padres.hasNext()) {
    if (padres.next().getId() === idCarpeta) return true;
  }
  return false;
}

function leer(id) {
  const archivo = DriveApp.getFileById(id);
  if (!estaEnCarpeta(archivo)) return { error: 'No es una foto de entregas.' };
  const contenido = archivo.getBlob();
  return {
    tipo: contenido.getContentType(),
    base64: Utilities.base64Encode(contenido.getBytes()),
  };
}

/**
 * La foto más reciente de la carpeta cuyo nombre empieza con `prefijo`,
 * creada entre `desde` y `hasta` (fechas ISO, opcionales). Sirve para
 * encontrar una foto que se guardó cuando el backend ya no esperaba la
 * respuesta. Devuelve { id } o { id: null }.
 */
function buscar(datos) {
  const prefijo = String(datos.prefijo || '');
  if (prefijo.length < 6) return { error: 'Falta el nombre a buscar.' };
  const desde = datos.desde ? new Date(datos.desde).getTime() : 0;
  const hasta = datos.hasta ? new Date(datos.hasta).getTime() : Infinity;
  const archivos = carpeta().searchFiles(
    'title contains "' + prefijo.replace(/["\\]/g, '') + '" and trashed = false',
  );
  let mejor = null;
  while (archivos.hasNext()) {
    const archivo = archivos.next();
    const creado = archivo.getDateCreated().getTime();
    if (archivo.getName().indexOf(prefijo) !== 0) continue;
    if (creado < desde || creado > hasta) continue;
    if (!mejor || creado > mejor.getDateCreated().getTime()) mejor = archivo;
  }
  return { id: mejor ? mejor.getId() : null };
}

/** La manda a la papelera de Drive (se puede recuperar 30 días). */
function eliminar(id) {
  const archivo = DriveApp.getFileById(id);
  if (!estaEnCarpeta(archivo)) return { error: 'No es una foto de entregas.' };
  archivo.setTrashed(true);
  return { ok: true };
}

function responder(objeto) {
  return ContentService.createTextOutput(JSON.stringify(objeto)).setMimeType(
    ContentService.MimeType.JSON,
  );
}
