const { TIPOS_ENTREGA } = require('./columns');

/*
 * Algunos clientes, al recibir la mercadería, dan un documento propio que
 * el transportista debe fotografiar además de la guía firmada: sin esa
 * foto no puede cerrar la entrega. Si no se lo dan en físico ("se lo
 * enviamos al asesor por correo"), lo marca y cierra solo con la guía; en
 * la hoja queda DOC_POR_CORREO. Solo en entregas a cliente final. Esta foto
 * no pasa por la IA.
 *
 * La misma lista está en la app (app/lib/models/documento_cliente.dart).
 */
const DOCUMENTOS = [
  { cliente: 'MOTAENGILPERU', nombre: 'MIGO' },
  { cliente: 'SKRENTAL', nombre: 'H.E.S' },
];

const DOC_POR_CORREO = 'correo';

/** "MOTA-ENGIL PERÚ S.A." → "MOTAENGILPERUSA", para comparar. */
function claveCliente(texto) {
  return String(texto ?? '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}

/** El documento que pide el cliente de esta guía ({ nombre }) o null. */
function documentoCliente(guia) {
  if (guia.tipo_entrega !== TIPOS_ENTREGA.CLIENTE_FINAL) return null;
  const clave = claveCliente(guia.destinatario);
  return DOCUMENTOS.find((d) => clave.startsWith(d.cliente)) || null;
}

module.exports = { documentoCliente, DOC_POR_CORREO };
