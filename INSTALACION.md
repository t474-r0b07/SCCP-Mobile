# Instalación

## Estado

**Desarrollo / testing.**

## Requisitos

- Flutter compatible con Dart 3.
- Android SDK configurado.
- Dispositivo Android para probar GPS, permisos y servicios en segundo plano.
- Proyecto Supabase configurado.

## Configuración de Supabase

No coloques credenciales directamente en `lib/core/constants/supabase_config.dart`.

Ejecuta:

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=TU_ANON_KEY
```

## Android

La aplicación solicita permisos para:

- ubicación en primer y segundo plano;
- notificaciones;
- micrófono;
- Bluetooth;
- ejecución de servicios foreground;
- alarmas y recuperación después de reinicio;
- exclusión de optimización de batería.

Los permisos deben concederse en el dispositivo de prueba para validar el flujo operativo completo.

## Firebase App Distribution

La configuración de Firebase no forma parte del repositorio público. Las propiedades de Gradle pueden suministrarse localmente:

```text
FIREBASE_TESTERS
FIREBASE_GROUPS
FIREBASE_CREDENTIALS
FIREBASE_RELEASE_NOTES
```

No subas `google-services.json`, credenciales de servicio ni claves privadas.

## Build Android

La configuración actual de release usa firma debug para facilitar pruebas internas. Esto **no es una firma de producción**.

Antes de distribuir públicamente:

- configurar un keystore de release;
- sacar las credenciales de firma del repositorio;
- revisar minificación y shrink;
- configurar correctamente Firebase;
- probar background service, alarmas y reinicio;
- validar políticas de Supabase.

## Verificación

Después de instalar:

1. Configura las credenciales de Supabase.
2. Inicia sesión con un oficial válido.
3. Completa los permisos operativos.
4. Comprueba GPS y ubicación en segundo plano.
5. Comprueba notificaciones.
6. Comprueba creación de reportes.
7. Comprueba radio y Realtime.
8. Comprueba recuperación después de cerrar la aplicación.

