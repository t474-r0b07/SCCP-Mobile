# SCCP-Mobile

**SCCP-Mobile** es una aplicación Android desarrollada con Flutter/Dart para experimentar con monitoreo operativo, GPS, reportes, alertas, radio y servicios en segundo plano dentro del ecosistema SCCP.

> **Estado público: desarrollo / testing**

El repositorio contiene el cliente móvil. El backend de Supabase **no forma parte de este repositorio**: cada instalación o revisión independiente debe utilizar su propio proyecto Supabase y sus propias políticas de acceso.

## Qué contiene

- Aplicación Android en Flutter/Dart.
- Captura y validación de ubicación.
- Reportes operativos y partes.
- Verificación de voz mediante el flujo implementado por el cliente y RPCs de Supabase.
- Sesiones operativas y heartbeat.
- Radio/mensajería operativa.
- Servicios foreground y recuperación de tareas en segundo plano.
- Almacenamiento local de estado y material sensible mediante los mecanismos correspondientes.

El código refleja el estado actual del prototipo. Las capacidades de background, GPS, permisos, audio y compatibilidad entre dispositivos requieren pruebas físicas antes de considerarlas aptas para operación real.

## Arquitectura

```text
Flutter / Dart
├── Presentation
├── Data
│   └── SupabaseRepository
└── Core
    ├── configuración
    ├── servicios de background
    └── utilidades

Android
├── Foreground service
├── Alarm / recovery components
└── Location / audio / notification permissions

Backend externo por instalación
└── Supabase
    ├── PostgreSQL
    ├── RPCs utilizadas por el cliente
    └── Realtime según la configuración de la instalación
```

## Backend Supabase

El repositorio **no incluye**:
- URL real de un proyecto Supabase.
- Claves o credenciales privadas.
- Datos operativos reales.
- Migraciones o políticas RLS de una instancia de producción.
- Perfiles de voz, embeddings biométricos u otros datos sensibles.

La integración se configura en cada entorno mediante:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY
```

El contrato de integración visible desde el cliente está documentado en [`BACKEND_SUPABASE.md`](./BACKEND_SUPABASE.md).

## Seguridad y estado de despliegue

Este repositorio es un proyecto público de **desarrollo/testing**, no un sistema certificado para operación productiva.

Antes de un despliegue real deben revisarse, en el backend elegido y en el dispositivo:
- autenticación y autorización;
- RLS/policies de Supabase;
- permisos de los RPC;
- permisos Android;
- vinculación de dispositivo;
- ejecución en segundo plano y comportamiento con Doze/OEM;
- protección y ciclo de vida de datos sensibles;
- firma release;
- pruebas físicas de GPS, audio, notificaciones y recuperación.

La implementación de verificación de voz incluida en el cliente es experimental y no debe interpretarse como una certificación biométrica.

## Instalación

Consulta [`INSTALACION.md`](./INSTALACION.md) para configurar Flutter, Supabase y Android.

## Documentación

- [`INSTALACION.md`](./INSTALACION.md) — instalación y configuración local.
- [`BACKEND_SUPABASE.md`](./BACKEND_SUPABASE.md) — contrato del backend esperado por el cliente.
- [`SECURITY.md`](./SECURITY.md) — límites y consideraciones de seguridad.
- [`CHALLENGE.md`](./CHALLENGE.md) — contexto del proyecto y canal de referencia.

## Autor

**Tata Robot** · GitHub: [t474-r0b07](https://github.com/t474-r0b07)

Este repositorio funciona como evidencia técnica del desarrollo y como base reproducible para revisión y experimentación.