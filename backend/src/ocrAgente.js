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

// Comprobante de la agencia de transporte (boleta, factura, vale de
// encomienda u orden de traslado) que a veces se pega sobre la guía.
const RUC_IPESA = '20101639275';
const INSTRUCCIONES_COMPROBANTE = `A veces sobre la guía hay pegado (o al \
lado) un comprobante pequeño de una AGENCIA de transporte o encomiendas \
(boleta, factura, "vale de encomienda", "orden de traslado"; ej. Palomino, \
Señor de Luren, ITTSA, GH Bus, Shalom, Marvisur). Si lo hay, lee de ESE \
comprobante, aunque la guía no diga que es una entrega en agencia:

- agencia_razon_social: la razón social de la empresa que EMITE el \
  comprobante (la agencia, la del logo/encabezado). NO es IPESA ni el \
  cliente ni el consignado.
- agencia_ruc: el RUC de esa agencia (11 dígitos, solo números). NO el RUC \
  de IPESA (${RUC_IPESA}) ni el del cliente.
- agencia_monto: el importe TOTAL pagado (con IGV), como número con punto \
  decimal, sin "S/" (ej. 70.00). Si hay subtotal, IGV y total, es el total.

Si no hay comprobante de agencia en la foto, usa null en esos 3 campos.`;

const CAMPOS_COMPROBANTE = '"agencia_razon_social": string|null, "agencia_ruc": string|null, "agencia_monto": number|null';

const PROMPT = `Esta es una foto de una guía de remisión electrónica peruana \
(formato SUNAT), emitida por la empresa IPESA. Lee la foto con cuidado y \
extrae estos campos:

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

${INSTRUCCIONES_COMPROBANTE}

Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional, sin \
explicaciones y sin bloques de código markdown, con exactamente esta forma:

{"numero_guia": string|null, "destinatario": string|null, "destino": string|null, "origen": string|null, "numero_pedido": string|null, "numero_entrega": string|null, ${CAMPOS_COMPROBANTE}}

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
    ...comprobanteDe(datos),
  };
}

/** El monto como número (acepta "S/ 70.00", "70,00", 70). */
function montoDe(valor) {
  if (typeof valor === 'number') return Number.isFinite(valor) && valor > 0 ? valor : null;
  const texto = String(valor ?? '').replace(/s\/|soles|\s/gi, '');
  if (!texto) return null;
  // "1.234,50" o "1,234.50" → 1234.50; "70,00" → 70.00
  const decimal = texto.match(/[.,](\d{1,2})$/);
  const entero = (decimal ? texto.slice(0, -decimal[0].length) : texto).replace(/[.,]/g, '');
  const numero = Number(decimal ? `${entero}.${decimal[1]}` : entero);
  return Number.isFinite(numero) && numero > 0 ? numero : null;
}

/**
 * Los datos del comprobante de agencia leídos por la IA, limpios: el RUC
 * solo si tiene 11 dígitos y no es el de IPESA. Todo null si no hay.
 */
function comprobanteDe(datos) {
  const razon = String(datos?.agencia_razon_social ?? '').trim();
  const ruc = String(datos?.agencia_ruc ?? '').replace(/\D/g, '');
  const monto = montoDe(datos?.agencia_monto);
  const rucValido = ruc.length === 11 && ruc !== RUC_IPESA ? ruc : null;
  const esIpesa = /^ipesa\b/i.test(razon);
  return {
    agencia_razon_social: razon && !esIpesa ? razon : null,
    agencia_ruc: rucValido,
    agencia_monto: monto,
  };
}

/** true si se leyó algo del comprobante. */
function hayComprobante(c) {
  return Boolean(c && (c.agencia_razon_social || c.agencia_ruc || c.agencia_monto));
}

function jsonDeLaIA(respuesta) {
  const texto = respuesta.text || '';
  try {
    return JSON.parse(texto.replace(/```json\s*|```\s*/g, '').trim());
  } catch (err) {
    throw new Error(`La IA no devolvió un JSON válido: ${texto}`);
  }
}

/**
 * Lee solo el comprobante de agencia de una foto de entrega (la que se
 * sube al entregar). Devuelve los 3 campos (null si no hay comprobante).
 */
async function leerComprobante(imagenBase64, mediaType) {
  const client = getClient();
  const respuesta = await client.models.generateContent({
    model: MODELO,
    contents: [
      { inlineData: { mimeType: mediaType, data: imagenBase64 } },
      {
        text: `Esta es la foto de la entrega de una guía de remisión de IPESA.

${INSTRUCCIONES_COMPROBANTE}

Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional, con \
esta forma: {${CAMPOS_COMPROBANTE}}. No inventes valores.`,
      },
    ],
    config: { responseMimeType: 'application/json' },
  });
  return comprobanteDe(jsonDeLaIA(respuesta));
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

Además: ${INSTRUCCIONES_COMPROBANTE}

Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional, con \
esta forma: {"numero_guia": string|null, ${CAMPOS_COMPROBANTE}}. Si no se \
ve el número de guía con confianza, usa null en vez de inventarlo.`,
      },
    ],
    config: { responseMimeType: 'application/json' },
  });

  const datos = jsonDeLaIA(respuesta);
  const comprobante = comprobanteDe(datos);
  const leido = typeof datos.numero_guia === 'string' ? datos.numero_guia.trim() : '';
  if (!leido) return { numero_guia: null, ...comprobante };
  const clave = claveGuia(leido);
  const igual = candidatos.find((c) => claveGuia(c) === clave);
  return { numero_guia: igual || leido, ...comprobante };
}

module.exports = {
  leerGuiaConIA,
  leerNumeroGuia,
  leerComprobante,
  claveGuia,
  comprobanteDe,
  hayComprobante,
};
