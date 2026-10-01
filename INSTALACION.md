# Instalación

## Estado

**Desarrollo / testing.**

## Requisitos

- Flutter compatible con el `pubspec.yaml` del proyecto.
- Dart incluido con Flutter.
- Android SDK configurado.
- Dispositivo Android para validar GPS, permisos, audio y servicios en segundo plano.
- Un proyecto Supabase propio para la instalación.

## 1. Obtener dependencias

```bash
flutter pub get
```

## 2. Configurar Supabase

SCCP-Mobile no depende de una instancia Supabase incluida en el repositorio.

Cada instalación debe crear/configurar su propio proyecto y suministrar los valores de entorno durante la compilación o ejecución:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY
```

El cliente espera las tablas y RPC descritas en [`BACKEND_SUPABASE.md`](./BACKEND_SUPABASE.md). La autorización efectiva depende de las políticas configuradas en el proyecto Supabase de cada instalación.

No guardes credenciales directamente en `lib/core/constants/supabase_config.dart`.

## 3. Android

La aplicación declara permisos relacionados con:
- ubicación en primer y segundo plano;
- notificaciones;
- micrófono;
- Bluetooth;
- servicios foreground;
- alarmas y recuperación después de reinicio;
- optimización de batería.

La necesidad efectiva de cada permiso debe validarse durante las pruebas en el dispositivo objetivo.

## 4. Firebase

La configuración de Firebase para distribución o pruebas no forma parte del repositorio público.

No subas:
- `google-services.json`;
- credenciales de service account;
- claves privadas;
- archivos de firma.

## 5. Build Android

La configuración actual de release utiliza firma debug para facilitar pruebas internas. **No es una firma de producción.**

Antes de una distribución real:
- configurar un keystore release;
- mantener sus credenciales fuera del repositorio;
- revisar minificación/shrink;
- configurar Firebase si el entorno lo necesita;
- probar background service, alarmas y reinicio;
- validar autenticación, autorización, RLS y RPCs de Supabase.

## 6. Verificación básica

Después de instalar:
1. Configura tu propio proyecto Supabase.
2. Suministra `SUPABASE_URL` y `SUPABASE_ANON_KEY`.
3. Comprueba el flujo de identificación/sesión.
4. Valida permisos de ubicación y audio.
5. Comprueba GPS y ejecución en segundo plano.
6. Comprueba creación de reportes y partes.
7. Comprueba radio/Realtime si tu backend los habilita.
8. Comprueba recuperación después de cerrar o reiniciar la aplicación.

La compatibilidad real de background, GPS y permisos depende del dispositivo y de la versión de Android utilizada.