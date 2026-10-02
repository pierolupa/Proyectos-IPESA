const { GoogleGenAI } = require('@google/genai');

let cliente = null;

function getClient() {
  if (!cliente) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      throw new Error('Falta la variable de entorno GEMINI_API_KEY.');
    }
    cliente = new GoogleGenAI({ apiKey });
  }
  return cliente;
}

// Google retira modelos viejos para claves nuevas (gemini-2.5-flash ya
// respondía 404); GEMINI_MODEL permite cambiarlo desde Vercel sin tocar código.
const MODELO = process.env.GEMINI_MODEL || 'gemini-3.1-flash-lite';

const PROMPT = `Esta es una foto de una guía de remisión electrónica peruana \
(formato SUNAT), emitida por la empresa IPESA. Lee la foto con cuidado y \
extrae exactamente estos 6 campos:

- numero_guia: el número de la guía, arriba a la derecha, formato \
  "serie-correlativo" (una letra + 3 dígitos + guion + dígitos), ej. \
  "T028-130133".
- destinatario: el campo "Señor(es)" dentro de "Datos del Destinatario".
- destino: el campo "Punto de Llegada" dentro de "Datos del Destinatario".
- origen: el campo "Punto de Partida" (la dirección desde donde sale la \
  mercadería; suele estar en "Datos del Traslado" o junto al remitente).
- numero_pedido: el valor de "Pedido" dentro de la línea "Documentos" en \
  "Datos adicionales" (ej. si dice "Pedido:0188173910", el valor es \
  "0188173910").
- numero_entrega: el valor de "Entrega" en esa misma línea de "Documentos".

Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional, sin \
explicaciones y sin bloques de código markdown, con exactamente esta forma:

{"numero_guia": string|null, "destinatario": string|null, "destino": string|null, "origen": string|null, "numero_pedido": string|null, "numero_entrega": string|null}

Si no puedes leer un campo con confianza, usa null para ese campo en vez de \
inventar un valor.`;

/**
 * Manda la foto a Gemini (con visión) para extraer los datos de la guía.
 * Gemini tiene un nivel gratis con cuota diaria que alcanza de sobra para
 * el volumen de IPESA — requiere GEMINI_API_KEY configurada en Vercel (ver
 * backend/README.md).
 */
async function leerGuiaConIA(imagenBase64, mediaType) {
  const client = getClient();
  const respuesta = await client.models.generateContent({
    model: MODELO,
    contents: [
      { inlineData: { mimeType: mediaType, data: imagenBase64 } },
      { text: PROMPT },
    ],
    config: { responseMimeType: 'application/json' },
  });

  const texto = respuesta.text || '';
  const jsonLimpio = texto.replace(/```json\s*|```\s*/g, '').trim();

  let datos;
  try {
    datos = JSON.parse(jsonLimpio);
  } catch (err) {
    throw new Error(`La IA no devolvió un JSON válido: ${texto}`);
  }

  return {
    numero_guia: datos.numero_guia || null,
    destinatario: datos.destinatario || null,
    destino: datos.destino || null,
    origen: datos.origen || null,
    numero_pedido: datos.numero_pedido || null,
    numero_entrega: datos.numero_entrega || null,
  };
}

const PROMPT_NUMERO = `Esta es una foto tomada al entregar una guía de \
remisión electrónica peruana (formato SUNAT) de la empresa IPESA. La foto \
puede estar de lado o girada, movida, cortada, doblada, con firma, sello o \
dedos encima. Solo necesito UN dato: el número de la guía.

El número de guía es el texto más grande y legible del recuadro de arriba \
a la derecha (junto a "GUÍA DE REMISIÓN ELECTRÓNICA REMITENTE" y el RUC). \
Tiene el formato serie-correlativo: una letra + 3 dígitos, un guion y el \
correlativo, ej. "T028-130133" o "T001-0093506". Puede aparecer con "N°", \
espacios o ceros a la izquierda en el correlativo. No lo confundas con el \
RUC, el número de pedido, de entrega ni de factura.`;

/** El correlativo sin ceros a la izquierda, para comparar números. */
function claveGuia(numero) {
  const limpio = String(numero || '')
    .toUpperCase()
    .replace(/N[°º]/g, '')
    .replace(/[^A-Z0-9]/g, '');
  const m = limpio.match(/^([A-Z])([0-9OIL]{3})0*(\d+)$/);
  if (!m) return limpio;
  const serie = m[2].replace(/O/g, '0').replace(/[IL]/g, '1');
  return `${m[1]}${serie}-${m[3]}`;
}

/**
 * Lee solo el número de guía de una foto de entrega (Entrega inteligente).
 * Con [candidatos] (las guías en ruta del transportista) la IA dice cuál
 * de ellas es; si la foto no es de ninguna, devuelve lo que leyó. Al final
 * se compara también sin ceros a la izquierda ni confusiones O/0 o I/1.
 */
async function leerNumeroGuia(imagenBase64, mediaType, candidatos = []) {
  const client = getClient();
  const lista = candidatos.length
    ? `\n\nEl transportista tiene en ruta estas guías:\n${candidatos
        .map((c) => `- ${c}`)
        .join('\n')}\n\nSi el número de la foto es uno de ellos (aunque \
cambien los ceros a la izquierda o los espacios), responde ese valor \
EXACTAMENTE como está en la lista. Si no es ninguno, responde el número tal \
como lo lees.`
    : '';
  const respuesta = await client.models.generateContent({
    model: MODELO,
    contents: [
      { inlineData: { mimeType: mediaType, data: imagenBase64 } },
      {
        text: `${PROMPT_NUMERO}${lista}

Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional, con \
esta forma: {"numero_guia": string|null}. Si no se ve el número de guía \
con confianza, usa null en vez de inventarlo.`,
      },
    ],
    config: { responseMimeType: 'application/json' },
  });

  const texto = respuesta.text || '';
  let datos;
  try {
    datos = JSON.parse(texto.replace(/```json\s*|```\s*/g, '').trim());
  } catch (err) {
    throw new Error(`La IA no devolvió un JSON válido: ${texto}`);
  }
  const leido = typeof datos.numero_guia === 'string' ? datos.numero_guia.trim() : '';
  if (!leido) return { numero_guia: null };
  const clave = claveGuia(leido);
  const igual = candidatos.find((c) => claveGuia(c) === clave);
  return { numero_guia: igual || leido };
}

module.exports = { leerGuiaConIA, leerNumeroGuia, claveGuia };
