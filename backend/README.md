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
y esta fila de encabezados (columnas A a S):

```
numero_guia | estado | tipo_entrega | origen | destino | transportista | destinatario | geo_lat | geo_lng | corregido_por_admin | fecha_creacion | fecha_actualizacion | numero_pedido | numero_entrega | cierre_lat | cierre_lng | fecha_cierre | foto_entrega_url | motivo_rechazo
```

Si ya tenías la hoja creada con menos columnas, agrega las que falten al
final (`numero_pedido` en M1, `numero_entrega` en N1, `cierre_lat` en O1,
`cierre_lng` en P1, `fecha_cierre` en Q1, `foto_entrega_url` en R1,
`motivo_rechazo` en S1) — las filas existentes quedan
igual y esas columnas se leen vacías para ellas.

`geo_lat`/`geo_lng` guardan la ubicación del último evento. `cierre_*` se
llenan solo cuando el transportista cierra la guía (entregado/finalizado)
con su GPS — es lo que el administrador ve en el mapa. Un cierre manual del
administrador no las llena.

`foto_entrega_url` guarda dónde quedó la foto de la entrega (la guía
firmada por el cliente, o el comprobante de agencia): `drive:<id>` si está
en Google Drive, o la URL del blob si está en Vercel Blob. Solo se guarda
la foto de la entrega final. Es **privada**: no se abre directo, se ve en
la app vía `GET /guias/:numeroGuia/foto`.

### Fotos en Google Drive (recomendado, gratis)

Las fotos quedan en la carpeta **IPESA · Fotos de entregas** del Drive de
la cuenta de Google que instale el script (usa sus 15 GB gratis). La cuenta
de servicio de la hoja no sirve para esto: Google no le da espacio en Drive.

1. Entra a [script.google.com](https://script.google.com) con la cuenta de
   IPESA → **Nuevo proyecto** → borra lo que haya y pega todo
   `apps-script/fotos-drive.gs`. Ponle de nombre "IPESA fotos".
2. En la línea `const CLAVE = 'ESCRIBE_AQUI_TU_CLAVE';` cambia el texto por
   una clave larga que inventes (letras y números, 20 o más). Guarda (💾).
3. Arriba elige la función **autorizar** → **Ejecutar** → acepta los
   permisos (si dice "Google no verificó esta app": *Configuración
   avanzada* → *Ir a IPESA fotos*). Se crea la carpeta en tu Drive.
4. **Implementar → Nueva implementación** → tipo **Aplicación web** →
   *Ejecutar como*: **Yo**; *Quién tiene acceso*: **Cualquier persona** →
   Implementar. Copia la **URL de la aplicación web** (termina en `/exec`).
5. En Vercel, proyecto del backend (**proyectos-ipesa**) → Settings →
   Environment Variables, agrega:
   - `DRIVE_FOTOS_URL` = la URL del paso 4
   - `DRIVE_FOTOS_CLAVE` = la clave del paso 2
6. Deployments → ⋯ → **Redeploy** para que tome las variables.

"Cualquier persona" solo significa que el backend puede llamar al script
sin iniciar sesión; sin la clave el script no guarda ni muestra nada, y
solo entrega fotos de esa carpeta. Si cambias el código del script, vuelve
a *Implementar → Gestionar implementaciones → editar → Nueva versión* (la
URL no cambia).

### Fotos en Vercel Blob (alternativa, gratis en el plan Hobby)

Si Drive está configurado se usa Drive; si no, Vercel Blob.

1. En Vercel, abre el proyecto del backend → pestaña **Storage** →
   **Create Database** → **Blob**.
2. Nombre `ipesa-fotos`, acceso **Private**, y conéctalo a este proyecto
   (todos los entornos). Vercel agrega solo la variable
   `BLOB_READ_WRITE_TOKEN`; no hay que copiar ninguna clave.
3. Vuelve a desplegar (Deployments → ⋯ → Redeploy) para que tome la variable.

El plan Hobby incluye un cupo mensual gratis; si se llena, Vercel pausa el
almacenamiento, **no cobra**. Sin Drive ni Blob configurados las guías se
registran igual, solo que sin foto (la app muestra un aviso).

La pestaña `Sucursales` (columnas `nombre | lat | lng | radio_m`) **se crea
sola** la primera vez que la app la usa — no hace falta crearla a mano. Ahí
se guardan los perímetros que el administrador marca en el mapa. Las guías
"entre sucursales" guardan en `destino` el nombre exacto de la sucursal.

Valores válidos de `estado`: `en_ruta`, `en_proceso_trasbordo`,
`recepcion_sucursal`, `entregado`, `finalizado`, `rechazado`. `rechazado`
lo pone el transportista con un motivo (`motivo_rechazo`, columna S) desde
`POST /api/guias/:numeroGuia/rechazo`; no cuenta como entregada y el número
de guía se puede volver a registrar.

**Mismo número de guía:** se puede registrar más de una vez (otro viaje de
la misma guía), pero no dentro de las 2 horas siguientes a su último
registro (así no entra dos veces la misma foto); si ese registro fue
rechazado, se puede volver a registrar al momento. Las rutas que usan el
número (cambiar estado, rechazar, foto) actúan sobre el registro más
reciente.

**Caché:** el backend guarda la lista de guías 10 segundos en memoria para
no pasar el límite de lecturas de Google Sheets (~60 por minuto); cualquier
escritura la borra, y las rutas que escriben siempre leen la hoja fresca.

Valores válidos de `tipo_entrega`: `cliente_final`, `agencia`,
`entre_sucursales`.

Agrega además una **segunda pestaña** llamada exactamente `Usuarios`, con
esta fila de encabezados (columnas A a D):

```
nombre | rol | pin | activo
```

- `rol`: `transportista`, `administrador` o `comercial`. El equipo
  comercial entra a la vista **Rastreo de guías** (todas las guías, solo
  lectura, con filtros de fecha, número de guía, cliente, entrega y pedido).
  Las cuentas `administrador` y `comercial` se crean a mano en la hoja; el
  auto-registro siempre crea `transportista`.
- `pin`: cualquier texto/número que uses como clave simple (ver advertencia
  de seguridad arriba).
- `activo`: `true`/`false` — para desactivar un usuario sin borrar la fila.

Ejemplos de fila: `Juan Pérez | transportista | 1234 | true`,
`Lucía Ramos | comercial | 5678 | true`.

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

El modelo por defecto es `gemini-3.1-flash-lite`. Si Google lo retira (el error
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
| `POST` | `/api/guias` | Asignación: crea guía en `en_ruta` y la devuelve completa. Requiere GPS. Un mismo número solo se puede volver a registrar 2 horas después de su último registro. |
| `PATCH` | `/api/guias/:numeroGuia/estado` | Cambia el estado (entrega, trasbordo, recepción). Requiere GPS salvo `porAdmin: true`. `recepcion_sucursal` solo se acepta con el GPS dentro del perímetro de la sucursal destino. En `entregado`/`finalizado`, opcional `foto: {base64, mediaType}` (se guarda como `foto_entrega_url`); si no se puede guardar, el estado cambia igual y la respuesta trae `aviso_foto`. |
| `POST` | `/api/guias/:numeroGuia/rechazo` | El transportista rechaza una tarea abierta. Body `{motivo, geo?}`; el motivo es obligatorio (3–300 caracteres). 409 si la guía ya está cerrada. |
| `GET` | `/api/guias/:numeroGuia/foto` | Devuelve la foto de la entrega (privada en Vercel Blob). |
| `GET` | `/api/fotos/estado` | `{configurado}`: si el almacenamiento de fotos está conectado. |
| `PATCH` | `/api/guias/:numeroGuia/numero` | Corrección manual del número (administrador). |
| `GET` | `/api/sucursales` | Sucursales con su perímetro (centro + radio en metros). |
| `PUT` | `/api/sucursales/:nombre` | Crea o actualiza el perímetro de una sucursal (`lat`, `lng`, `radioM` entre 20 y 5000). |
| `DELETE` | `/api/sucursales/:nombre` | Elimina una sucursal. |
| `GET` | `/api/guias?estado=en_ruta&desde=…&hasta=…` | Lista de guías; filtros opcionales por estado y por fecha de la tarea (`fecha_creacion`, ISO, `desde` incluido y `hasta` excluido). |
| `GET` | `/api/guias/transportista/:nombre` | Tareas de un transportista. |
| `GET` | `/api/health` | Chequeo de salud. |
