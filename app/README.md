# IPESA · Tracking Distribución — App (Flutter Web)

App descrita en [`../ARCHITECTURE.md`](../ARCHITECTURE.md), conectada al
backend real (`../backend/`, desplegado en Vercel) que a su vez lee/escribe
la hoja de Google Sheets "IPESA - Guías". No hay datos simulados: todo lo
que hace la app queda guardado de verdad.

Se despliega como **sitio web en Vercel** (no como app nativa de tienda) —
ver la sección "Desplegar en Vercel" más abajo.

## Qué incluye

- **Login simple** (nombre + PIN, ver advertencia de seguridad abajo) como
  pantalla de inicio, con opción de auto-registro ("Crear cuenta" — siempre
  crea la cuenta como Transportista, nunca Administrador). El rol con el
  que se entra lo decide el backend, no un selector previo. Equipo
  Comercial entra sin cuenta, con el link "Rastrear un envío sin cuenta".
- **Transportista**: lista de tareas asignadas (cargadas de la API), flujo
  de "Nueva guía" (foto real con la cámara del dispositivo + GPS real
  obligatorio + validación de duplicados contra el backend), y flujo de
  entrega (firma a cliente final, comprobante de agencia, o geofencing
  simulado para traslados entre sucursales).
- **Administrador**: panel con todas las guías, filtro por estado, edición
  manual de estado y corrección manual del número de guía.
- **Equipo Comercial**: rastreo público por los últimos 4 dígitos de la
  guía, consultando la API directo (nunca baja la lista completa al
  dispositivo).

## ⚠️ Advertencia de seguridad (login)

El login es **deliberadamente simple** (nombre + PIN en texto plano,
comparado en el backend contra una hoja de cálculo) — no hay tokens, ni
expiración de sesión, ni cifrado del PIN. Sirve para que el equipo pruebe
la app internamente, **no para producción con datos sensibles**. Ver
`../backend/README.md`.

## Qué falta (ver sección 8 de `ARCHITECTURE.md`)

- OCR real (la cámara y el GPS son reales; el número de guía leído de la
  foto todavía se simula — el usuario lo corrige a mano).
- Geofencing real para traslados entre sucursales (hoy es un switch manual).
- Autenticación real (Firebase Auth u otro, en vez del login simple).

## Cómo correrlo en desarrollo

```bash
flutter pub get
flutter run -d chrome  # abre la app en el navegador con hot reload
flutter test           # tests de widgets (usan un cliente HTTP simulado)
flutter analyze        # análisis estático
```

El `web/flutter_bootstrap.js` está configurado para cargar CanvasKit desde
los assets locales en vez del CDN de Google, así la app también funciona
detrás de redes corporativas restrictivas.

## Desplegar en Vercel

Es un **proyecto de Vercel separado** del backend (`../backend/`), aunque
viven en el mismo repositorio — Vercel soporta varios proyectos por
repo, cada uno con su propio "Root Directory".

1. En https://vercel.com/new, importa de nuevo el repositorio
   `Proyectos-IPESA` (se puede importar el mismo repo más de una vez, como
   un proyecto nuevo).
2. **Root Directory** → Edit → selecciona **`app`**.
3. **Framework Preset**: "Other".
4. Abre **"Build and Output Settings"** y sobrescribe:
   - **Install Command**: `echo "sin dependencias node"`
   - **Build Command**:
     ```
     git clone https://github.com/flutter/flutter.git -b stable --depth 1 /tmp/flutter && /tmp/flutter/bin/flutter config --enable-web --no-analytics && /tmp/flutter/bin/flutter pub get && /tmp/flutter/bin/flutter build web --release
     ```
   - **Output Directory**: `build/web`
5. No hace falta ninguna variable de entorno (la URL del backend está
   fija en `lib/services/guias_api.dart`).
6. **Deploy**.

La primera build tarda más (~2-3 min, porque descarga Flutter), las
siguientes también (no hay caché de Flutter entre builds) — es normal.

Cada push a la rama conectada vuelve a desplegar automáticamente, igual
que el backend.
