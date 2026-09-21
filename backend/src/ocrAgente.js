const Anthropic = require('@anthropic-ai/sdk');

let clientePromise = null;

function getClient() {
  if (!clientePromise) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error('Falta la variable de entorno ANTHROPIC_API_KEY.');
    }
    clientePromise = new Anthropic({ apiKey });
  }
  return clientePromise;
}

const MODELO = 'claude-haiku-4-5-20251001';

const PROMPT = `Esta es una foto de una guía de remisión electrónica peruana \
(formato SUNAT), emitida por la empresa IPESA. Lee la foto con cuidado y \
extrae exactamente estos 5 campos:

- numero_guia: el número de la guía, arriba a la derecha, formato \
  "serie-correlativo" (una letra + 3 dígitos + guion + dígitos), ej. \
  "T028-130133".
- destinatario: el campo "Señor(es)" dentro de "Datos del Destinatario".
- destino: el campo "Punto de Llegada" dentro de "Datos del Destinatario".
- numero_pedido: el valor de "Pedido" dentro de la línea "Documentos" en \
  "Datos adicionales" (ej. si dice "Pedido:0188173910", el valor es \
  "0188173910").
- numero_entrega: el valor de "Entrega" en esa misma línea de "Documentos".

Responde ÚNICAMENTE con un objeto JSON válido, sin texto adicional, sin \
explicaciones y sin bloques de código markdown, con exactamente esta forma:

{"numero_guia": string|null, "destinatario": string|null, "destino": string|null, "numero_pedido": string|null, "numero_entrega": string|null}

Si no puedes leer un campo con confianza, usa null para ese campo en vez de \
inventar un valor.`;

/**
 * Manda la foto a Claude (con visión) para extraer los datos de la guía.
 * Cuesta una fracción de centavo por foto (modelo Haiku) — requiere
 * ANTHROPIC_API_KEY configurada en Vercel. Ver backend/README.md.
 */
async function leerGuiaConIA(imagenBase64, mediaType) {
  const client = getClient();
  const respuesta = await client.messages.create({
    model: MODELO,
    max_tokens: 500,
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'image',
            source: { type: 'base64', media_type: mediaType, data: imagenBase64 },
          },
          { type: 'text', text: PROMPT },
        ],
      },
    ],
  });

  const texto = respuesta.content.find((bloque) => bloque.type === 'text')?.text || '';
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
    numero_pedido: datos.numero_pedido || null,
    numero_entrega: datos.numero_entrega || null,
  };
}

module.exports = { leerGuiaConIA };
