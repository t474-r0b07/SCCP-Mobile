# Contrato de backend — Supabase

SCCP-Mobile utiliza Supabase como backend externo. **Este archivo documenta el contrato que consume el cliente; no contiene el backend real ni pretende definir las políticas de seguridad de una instalación.**

Cada persona que quiera revisar o ejecutar el proyecto debe utilizar su propio proyecto Supabase.

## Configuración

El cliente recibe estos valores mediante `--dart-define`:
```text
SUPABASE_URL
SUPABASE_ANON_KEY
```

Ejemplo:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY
```

No se incluyen URLs reales, credenciales, datos operativos ni secretos.

## Recursos utilizados por el cliente

El repositorio consume actualmente los siguientes recursos de Supabase:

### Tablas

- `oficiales`
- `reos`
- `partes_oficiales`
- `monitoreo_reportes`
- `inconsistencias`
- `radio_mensajes`
- `oficial_sesiones`
- `login_logs`

El cliente realiza operaciones de lectura, inserción, actualización o upsert sobre estas tablas según el flujo.

### RPCs

El cliente utiliza estas funciones remotas:
- `fn_get_voice_profile_secure`
- `fn_upsert_voice_profile_secure`
- `fn_voice_biometric_verify`

Los nombres y parámetros esperados deben mantenerse compatibles con el código cliente.

## Autorización

La existencia de una `SUPABASE_ANON_KEY` no sustituye la autorización del backend.

Cada instalación debe definir sus propias:
- políticas RLS;
- permisos de ejecución de RPC;
- restricciones de lectura/escritura;
- reglas de acceso por usuario/dispositivo;
- controles sobre datos sensibles.

Este repositorio no incluye ni afirma una política RLS de producción.

## Datos sensibles

Los datos reales de oficiales, ubicaciones, sesiones, registros operativos, perfiles de voz o embeddings biométricos deben permanecer fuera del repositorio público.

Para una revisión independiente se recomienda utilizar datos sintéticos y una instancia Supabase separada.

## Alcance

Este documento describe únicamente la interfaz que el cliente espera encontrar. No garantiza que una instancia Supabase recién creada sea compatible sin implementar el esquema, RPCs y políticas correspondientes.

La configuración del backend es responsabilidad de cada entorno de ejecución.