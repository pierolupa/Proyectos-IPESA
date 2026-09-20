# IPESA · Control de Guías — Backend (Cloud Functions)

API HTTP que hace de intermediario entre la app y Google Sheets, según
[`../ARCHITECTURE.md`](../ARCHITECTURE.md) sección 2.3. La app **nunca**
escribe directo a la hoja de cálculo.

## ⚠️ Antes de desplegar en serio

Esta API **todavía no tiene autenticación ni autorización por rol** (ver
`src/app.js`, nota al inicio del archivo). Ahora mismo cualquiera con la URL
puede llamar cualquier endpoint. Es suficiente para desarrollo/pruebas, pero
**no debe usarse en producción con transportistas reales sin agregar
autenticación** (por ejemplo, Firebase Auth + verificación de rol en cada
endpoint).

## Qué necesitas antes de desplegar (una sola vez)

1. **Proyecto de Firebase con plan Blaze** activado.
2. **API de Google Sheets habilitada** en ese mismo proyecto de Google Cloud.
3. Una **hoja de cálculo de Google Sheets** llamada como quieras, con una
   pestaña llamada exactamente `Guias` (ver estructura de columnas abajo).
4. **Compartir esa hoja como Editor** con el correo de la service account
   que usará la función. Por defecto, Cloud Functions Gen 2 corre con la
   cuenta `PROJECT_ID@appspot.gserviceaccount.com` (el "App Engine default
   service account" del proyecto) — no hace falta crear ni descargar
   ninguna clave JSON. Puedes confirmarla en la consola de Google Cloud →
   Cloud Functions → tu función → pestaña "Detalles" → "Cuenta de servicio
   de tiempo de ejecución".

### Estructura de la hoja "Guias"

Fila 1 = encabezados, en este orden exacto (columnas A a L):

```
numero_guia | estado | tipo_entrega | origen | destino | transportista | destinatario | geo_lat | geo_lng | corregido_por_admin | fecha_creacion | fecha_actualizacion
```

Valores válidos de `estado`: `en_ruta`, `en_proceso_trasbordo`,
`recepcion_sucursal`, `entregado`, `finalizado`.

Valores válidos de `tipo_entrega`: `cliente_final`, `agencia`,
`entre_sucursales`.

## Configuración

```bash
cp .env.example .env
# Edita .env y pon el SHEET_ID (está en la URL de la hoja:
# https://docs.google.com/spreadsheets/d/ESTE_ES_EL_ID/edit)
```

## Desarrollo local

```bash
npm install
npm test              # corre los tests (mockean Sheets, no requieren credenciales)
npm run serve         # emulador local de Firebase Functions
```

## Desplegar

```bash
firebase login                  # una vez, en tu cuenta de Google
firebase use --add              # selecciona tu proyecto de Firebase/GCP
npm run deploy                  # sube la función y aplica el .env
```

Al terminar, la consola imprime la URL pública de la función (algo como
`https://us-central1-TU-PROYECTO.cloudfunctions.net/api`).

## Endpoints

| Método | Ruta | Uso |
|---|---|---|
| `POST` | `/guias` | Asignación: crea guía en `en_ruta`. Requiere GPS. Rechaza duplicados activos. |
| `PATCH` | `/guias/:numeroGuia/estado` | Cambia el estado (entrega, trasbordo, recepción). Requiere GPS salvo `porAdmin: true`. |
| `PATCH` | `/guias/:numeroGuia/numero` | Corrección manual del número (administrador). |
| `GET` | `/guias?estado=en_ruta` | Lista completa, con filtro opcional (administrador). |
| `GET` | `/guias/transportista/:nombre` | Tareas de un transportista. |
| `GET` | `/guias/rastreo/:ultimosCuatro` | Rastreo público, sin datos sensibles. |
| `GET` | `/health` | Chequeo de salud. |
