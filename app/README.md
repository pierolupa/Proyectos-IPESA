# IPESA · Control de Guías (scaffold)

Scaffold navegable en Flutter de la app descrita en
[`../ARCHITECTURE.md`](../ARCHITECTURE.md). **Toda la data es simulada en
memoria** (sin Google Sheets, sin OCR real, sin geolocalización real):
sirve para validar pantallas, flujos y navegación antes de conectar los
servicios reales.

## Qué incluye

- **Selector de rol** (sin login real): Transportista, Administrador,
  Equipo Comercial.
- **Transportista**: lista de tareas asignadas, flujo de "Nueva guía"
  (simula foto + OCR + GPS obligatorio + validación de duplicados), y
  flujo de entrega (firma a cliente final, comprobante de agencia, o
  geofencing simulado para traslados entre sucursales).
- **Administrador**: panel con todas las guías, filtro por estado, edición
  manual de estado y corrección manual del número de guía.
- **Equipo Comercial**: rastreo público por los últimos 4 dígitos de la
  guía, sin usuario registrado.

## Qué falta (fuera de alcance de este scaffold)

- Integración real con la API de Google Sheets / backend intermedio.
- OCR real (Google ML Kit / Cloud Vision).
- Cámara real y geolocalización/geofencing real.
- Autenticación de usuarios.

Ver la sección 8 de `ARCHITECTURE.md` para las decisiones pendientes.

## Cómo correrlo

```bash
flutter pub get
flutter run          # dispositivo/emulador Android o iOS
flutter test         # tests de widgets
flutter analyze       # análisis estático
```
