# IPESA · Tracking Distribución — Backend (Vercel)

API HTTP que hace de intermediario entre la app y Google Sheets, según
[`../ARCHITECTURE.md`](../ARCHITECTURE.md) sección 2.3. La app **nunca**
escribe directo a la hoja de cálculo.

Se despliega en **Vercel** (plan gratuito "Hobby"). Autentica contra Google
Sheets con una cuenta de servicio cuya clave se guarda como variable de
entorno secreta en Vercel — no requiere el plan Blaze de Google Cloud. La
lectura de la foto de la guía usa la API de Gemini, que tiene un nivel
gratis con cuota diaria — ver sección "Leer la guía con IA" más abajo.

## ⚠️ Antes de desplegar en serio

El login (`POST /auth/login`) es deliberadamente simple: compara nombre y
PIN en texto plano contra la hoja "Usuarios", sin tokens, sin expiración de
sesión, sin hashing. Sirve para que el equipo pruebe la app internamente —
**no es un mecanismo de autenticación real**. El resto de la API tampoco
valida quién llama cada endpoint (ver `src/app.js`, nota al inicio del
archivo): cualquiera con la URL puede llamar cualquier endpoint sin pasar
por el login. **No debe usarse en producción con transportistas reales sin
migrar a un proveedor de autenticación de verdad** (por ejemplo, Firebase
Auth) y verificar un token en cada endpoint sensible.

## Qué necesitas antes de desplegar (una sola vez, todo gratis)

### 1. Habilitar la API de Google Sheets

En https://console.cloud.google.com, con tu proyecto (el mismo que
`ipesa---distribucion` si lo creaste desde Firebase) seleccionado:
"APIs & Services" → "Library" → busca "Google Sheets API" → **Enable**.
No requiere facturación activada.

### 2. Crear la cuenta de servicio

"IAM y administración" → "Cuentas de servicio" → **Crear cuenta de
servicio**:
- Nombre: `ipesa-guias-backend` (o el que prefieras).
- No hace falta asignarle ningún rol de IAM (el acceso a la hoja se da
  compartiéndola directamente, no por rol de proyecto).
- Termina la creación, entra a la cuenta creada → pestaña **Claves** →
  **Agregar clave** → **Crear clave nueva** → tipo **JSON** → se descarga
  un archivo. Ese archivo es lo que va en `GOOGLE_SERVICE_ACCOUNT_KEY`.
  **No lo subas a git ni lo compartas.**

### 3. Crear la hoja de cálculo

Crea una hoja de Google Sheets con una pestaña llamada exactamente `Guias`
y esta fila de encabezados (columnas A a N):

```
numero_guia | estado | tipo_entrega | origen | destino | transportista | destinatario | geo_lat | geo_lng | corregido_por_admin | fecha_creacion | fecha_actualizacion | numero_pedido | numero_entrega
```

Si ya tenías la hoja creada con solo A-L, agrega `numero_pedido` en M1 y
`numero_entrega` en N1 — las filas existentes quedan igual, esas dos
columnas se leen vacías para ellas.

Valores válidos de `estado`: `en_ruta`, `en_proceso_trasbordo`,
`recepcion_sucursal`, `entregado`, `finalizado`.

Valores válidos de `tipo_entrega`: `cliente_final`, `agencia`,
`entre_sucursales`.

Agrega además una **segunda pestaña** llamada exactamente `Usuarios`, con
esta fila de encabezados (columnas A a D):

```
nombre | rol | pin | activo
```

- `rol`: `transportista` o `administrador` (el rol `comercial` no necesita
  login — ver ARCHITECTURE.md sección 6).
- `pin`: cualquier texto/número que uses como clave simple (ver advertencia
  de seguridad arriba).
- `activo`: `true`/`false` — para desactivar un usuario sin borrar la fila.

Ejemplo de fila: `Juan Pérez | transportista | 1234 | true`.

Copia el **ID de la hoja** de su URL:
`https://docs.google.com/spreadsheets/d/ESTE_ES_EL_ID/edit`.

### 4. Compartir la hoja con la cuenta de servicio

Abre el archivo JSON descargado en el paso 2, copia el valor de
`client_email` (algo como
`ipesa-guias-backend@ipesa---distribucion.iam.gserviceaccount.com`), y
comparte la hoja con ese correo como **Editor** (botón "Compartir" en
Google Sheets).

## Leer la guía con IA (`GEMINI_API_KEY`)

`POST /api/ocr/leer-guia` manda la foto a Gemini (con visión, ver
`src/ocrAgente.js`) para extraer número de guía, destinatario, destino,
número de pedido y número de entrega. Reemplaza el intento anterior de
leerlo gratis en el navegador (Tesseract.js), que no lograba leer de forma
confiable un formulario denso con tablas.

Se usa Gemini (no Claude/OpenAI) porque tiene un **nivel gratis** con cuota
diaria de solicitudes — de sobra para el volumen de IPESA, así que esto no
debería generar ningún costo.

Para activarlo:
1. Entra a https://aistudio.google.com/apikey (Google AI Studio) con tu
   cuenta de Google.
2. **Create API Key** → elige o crea un proyecto de Google Cloud → copia la
   clave.
3. En el proyecto `proyectos-ipesa` de Vercel → **Settings → Environment
   Variables** → agrega `GEMINI_API_KEY` con esa clave → guarda y vuelve a
   desplegar (o espera al próximo push).

Sin esta variable configurada, `/api/ocr/leer-guia` devuelve error 500 — el
resto de la API sigue funcionando normal, y el formulario de la app sigue
dejando escribir todos los campos a mano.

El modelo por defecto es `gemini-3.8-flash`. Si Google lo retira (el error
dirá algo como "This model ... is no longer available"), agrega en Vercel
la variable `GEMINI_MODEL` con el modelo que recomiende el mensaje y
vuelve a desplegar — no hace falta cambiar código.

## Desarrollo local

```bash
npm install
npm test              # corre los tests (mockean Sheets, no requieren credenciales)
cp .env.example .env   # completa SHEET_ID y GOOGLE_SERVICE_ACCOUNT_KEY
npx vercel dev         # levanta la API localmente
```

## Desplegar en Vercel

1. Sube este repo a GitHub (ya lo está) y entra a https://vercel.com con
   tu cuenta (puedes iniciar sesión directo con GitHub).
2. **Add New… → Project** → importa el repositorio `Proyectos-IPESA`.
3. En "Root Directory" selecciona la carpeta **`backend`** (importante:
   no la raíz del repo).
4. En "Environment Variables" agrega:
   - `SHEET_ID` → el ID de la hoja del paso 3.
   - `GOOGLE_SERVICE_ACCOUNT_KEY` → pega el contenido completo del JSON
     de la cuenta de servicio (todo el archivo, tal cual).
   - `GEMINI_API_KEY` → ver sección "Leer la guía con IA" más abajo
     (opcional para desplegar, pero sin ella el lector de fotos no
     funciona).
5. **Deploy**.

Al terminar, Vercel te da una URL pública (algo como
`https://ipesa-guias-backend.vercel.app`). La API queda disponible bajo
`/api/...` (por ejemplo `https://ipesa-guias-backend.vercel.app/api/health`).

## Endpoints

| Método | Ruta | Uso |
|---|---|---|
| `POST` | `/api/ocr/leer-guia` | Lee la foto de una guía con IA (ver "Leer la guía con IA"). Requiere `GEMINI_API_KEY`. |
| `POST` | `/api/auth/login` | Login simple por nombre + PIN (ver advertencia de seguridad). |
| `POST` | `/api/auth/registro` | Auto-registro. Siempre crea el usuario como `transportista` (nunca `administrador`). |
| `POST` | `/api/guias` | Asignación: crea guía en `en_ruta`. Requiere GPS. Rechaza duplicados activos. |
| `PATCH` | `/api/guias/:numeroGuia/estado` | Cambia el estado (entrega, trasbordo, recepción). Requiere GPS salvo `porAdmin: true`. |
| `PATCH` | `/api/guias/:numeroGuia/numero` | Corrección manual del número (administrador). |
| `GET` | `/api/guias?estado=en_ruta` | Lista completa, con filtro opcional (administrador). |
| `GET` | `/api/guias/transportista/:nombre` | Tareas de un transportista. |
| `GET` | `/api/guias/rastreo/:ultimosCuatro` | Rastreo público, sin datos sensibles. |
| `GET` | `/api/health` | Chequeo de salud. |
