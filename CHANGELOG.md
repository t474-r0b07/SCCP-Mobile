# Changelog

## 2026-02-28

### Corrección crítica de ciclo de grupos (turno ALFA/BRAVO)
- `lib/core/utils/shift_utils.dart`:
  - ancla operativa diaria definida en `08:00` (día operativo `08:00 -> 07:59`).
  - ciclo de 14 días anclado a `2026-02-28` (día 1).
  - distribución final solicitada:
    - `ALFA`: días `{1, 4, 6, 9, 10, 12, 14}`
    - `BRAVO`: días `{2, 3, 5, 7, 8, 11, 13}`
- `test/core/utils/shift_utils_test.dart`:
  - expectativas actualizadas por ancla `08:00`, secuencia real de ciclo y cálculo de próxima ventana combinada.

### Validación final de estabilidad (sin retroceso)
- `test/core/utils/shift_utils_test.dart`:
  - corrección de expectativa para `2026-02-27` según ciclo final (día 14 = `ALFA`).
- Verificación de integridad:
  - barrida de referencias `assets/*` en código: `MISSING_COUNT=0`.
  - `flutter analyze` OK.
  - `flutter test` OK.
  - `flutter build apk --debug` OK.

### Documentación de esquema (jurisdicción)
- `docs/supabase_schema_reference.md`:
  - tabla `oficiales` ahora documenta explícitamente el campo `jurisdiccion`.

### Firebase Distribution (Android) integrado
- `android/settings.gradle`:
  - agregado plugin `com.google.gms.google-services` (`4.4.4`) con `apply false`.
  - agregado plugin `com.google.firebase.appdistribution` (`5.2.0`) con `apply false`.
- `android/app/build.gradle`:
  - activados plugins `com.google.gms.google-services` y `com.google.firebase.appdistribution`.
  - agregado bloque `firebaseAppDistribution` para release (configurable por `-P`):
    - `FIREBASE_TESTERS`
    - `FIREBASE_GROUPS`
    - `FIREBASE_CREDENTIALS`
    - `FIREBASE_RELEASE_NOTES`
  - agregada integración base de Firebase con BoM `34.9.0` + `firebase-analytics`.
- `android/app/google-services.json` detectado y válido en ruta esperada.

### Cierre automático estricto por fin de turno
- `lib/presentation/providers/auth_provider.dart`:
  - al detectar fin de turno, ahora ejecuta **logout automático por sistema**:
    - cierra sesión operativa (`off_shift`),
    - detiene `BackgroundService` + `AlarmWatchdog`,
    - limpia sesión local (`user_id`, `user_shift`, `user_grupo`, etc.),
    - obliga reingreso manual en siguiente turno.
  - mantiene `device_identifier` para evitar pérdida de identidad de equipo.
- `lib/data/services/background_service.dart`:
  - si detecta fuera de turno en segundo plano, aplica cierre total equivalente:
    - cierre de sesión operativa,
    - limpieza de sesión local,
    - detención de servicio y watchdog.

### Recordatorio fuerte de reactivación de turno
- `lib/core/constants/app_constants.dart`:
  - nuevo canal `sccp_shift_activation_v1`.
- `lib/data/services/notification_service.dart`:
  - creado canal dedicado de activación de turno (importancia máxima).
  - recordatorio de inicio de turno reforzado con:
    - `Priority.max`
    - vibración fuerte
    - `fullScreenIntent`
    - categoría `alarm`
  - programación automática al cerrar turno y disparo inmediato si corresponde.

### Gráficos dashboard móvil: de decorativos a funcionales
- `lib/data/repositories/supabase_repository.dart`:
  - nuevo `getMonitoringTrendSnapshot` con serie real reciente (`monitoreo_reportes`) + conteos recientes (`inconsistencias`, `partes_oficiales`).
- `lib/presentation/providers/monitoring_provider.dart`:
  - nuevo pipeline de series HUD reales (`hudOperationalTrend`, `hudLockTrend`, `hudSpectrumLevels`, `hudCadencePerHour`, `hudLastReportAgeSec`, `hudLateralDrift`).
- `lib/presentation/screens/home_screen.dart`:
  - `VELAS / FRECUENCIA` ahora dibuja OHLC sobre datos reales de tendencia operativa.
  - `GRID3D / COORD` ahora refleja bloqueo real y deriva lateral real.
  - `RESUMEN PERFIL` usa espectro derivado de serie real (fallback solo si no hay historial).

## 2026-02-27

### Alineación cadena 09:00 (partes)
- `SupabaseRepository.getTodayOperationalSummary` ahora ancla el resumen diario con `ParteScheduleUtils.firstSlotHour` (09:00) en vez de hora fija 08:00.
- Script base actualizado para partes obligatorios:
  - `docs/supabase_full_setup_v2.sql` cambia primer slot de control de `08:00` a `09:00` en `fn_register_missing_reports`.

### Dashboard móvil - gráficos más legibles
- `home_screen.dart`:
  - Se amplió altura de gráficos tácticos (spectrum / velas / grid) para lectura más clara.
  - `HudSpectrum` ahora enfatiza el centro con mayor contraste y pulso visual central.
  - `HudCandles` ahora dibuja velas más notorias (cuerpo mínimo visible, wick más claro, contraste de alza/baja).
  - `HudGrid3D` ahora incluye núcleo central y retícula de referencia más visible.

### Voz en parte obligatorio/sorpresa - robustez de reconocimiento
- `VoiceMatchUtils` reforzado:
  - Similaridad híbrida (caracteres + tokens) para tolerar texto extra/ruido al final.
  - Nuevo `hasCoreChallengeMatch` para validar tokens clave y código numérico del challenge.
- `home_screen.dart`:
  - Captura de voz conserva la mejor hipótesis reconocida (ya no pisa con un resultado parcial peor).
  - Ventana de escucha ampliada (`10s -> 12s`) y pausa (`3s -> 4s`) para mejorar reconocimiento real.
  - Si la similitud global no alcanza umbral, se acepta solo si pasa validación de núcleo de challenge (clave + código + tokens).

### Perfil oficial - jurisdiccion desde BD
- `OficialModel` ahora incluye campo `jurisdiccion` mapeado desde tabla `oficiales`.
- `home_screen.dart`:
  - perfil resumen muestra chip `JUR ...` cuando el dato está disponible.
  - perfil completo agrega detalle `Jurisdiccion`.

### Hotfix visual urgente (dashboard + splash web móvil)
- `home_screen.dart`:
  - corrección crítica de layout en `CustomPaint` (`SizedBox` ahora fuerza `width: double.infinity`) para evitar render en línea vertical.
  - `VELAS / FRECUENCIA`: velas más visibles (menos velas, cuerpo mínimo mayor, wick más grueso, mayor contraste y glow).
  - `GRID3D / COORD`: perspectiva reajustada para que el grid quede centrado/alineado.
  - `RESUMEN PERFIL`: el gráfico inferior vuelve a dibujarse correctamente al ocupar ancho completo.
- `hud_splash_screen.dart`:
  - splash/index centrado con bloque de contenido en `mainAxisSize.min` + `mainAxisAlignment.center`.
  - escalado móvil aumentado (núcleo HUD, tipografías y barra de progreso más grandes).
  - padding móvil ajustado para evitar que se vea pequeño o desbalanceado.

### Hotfix biometría de voz (evita contingencia falsa con frase alta)
- `home_screen.dart`:
  - `verifyVoiceBiometric` ahora devuelve resultado estructurado (`error` + `technicalFailure`) para distinguir fallo técnico real vs no-coincidencia biométrica.
  - se corrige captura local de muestra: si la primera captura falla, ahora reinicia micrófono y reintenta capturar (antes no reintentaba).
  - al fallar biometría local por `no coincide`, ya no fuerza contingencia por mezclar motivo técnico del servidor en el mismo mensaje.
  - resultado: evita casos de `Similitud alta` que terminaban en `FALLA TECNICA BIOMETRIA` por clasificación incorrecta.

### Blindaje completo de evidencia fotográfica (anti-manipulación)
- `validation_hash_service.dart`:
  - versión de sobre de seguridad `v2` con firma HMAC-SHA256 por dispositivo.
  - hash SHA-256 de bytes de imagen (`image_sha256`) además del hash canónico del sobre.
  - anti-replay activo: secuencia monotónica (`proof.sequence`) + `previous_hash` + historial local de hashes recientes.
  - detección y bloqueo de evidencia reciclada (`EVIDENCIA_REPLAY_DETECTADO`).
  - validación de frescura de captura (`<= 180s`) y bloqueo de captura vieja.
  - validación de GPS no-mock y precisión mínima operativa (`<=120m`) antes de aceptar evidencia.
  - token criptográfico corto (`proof_token`) generado por evidencia para auditoría.
  - archivo local rotativo de sobres firmados para trazabilidad forense.
- `home_screen.dart`:
  - integración de contexto de seguridad en captura (`slot`, frase esperada, texto reconocido, tipo de parte, id sorpresa).
  - payload operativo ahora incluye `EVID_PROOF` además de `EVID_HASH` y contador.
  - UI muestra `proof token` de la última evidencia capturada.

### Validación
- `flutter analyze` OK
- `flutter test` OK

## 2026-02-25

### Hotfix BG + Notificaciones en Bloqueo (Doze/OEM)
- `BackgroundServiceManager`:
  - se elimina invocacion duplicada de `_performBackgroundTask` desde el timer
    de polling de comunicaciones (evita contencion y ciclos perdidos).
  - `SKIP_BG_TASK_BUSY` ahora encola reintento inmediato (`_backgroundTaskQueued`)
    para no perder ejecucion cuando hay solape temporal.
  - umbral de tarea colgada ampliado (`35s -> 3m`) para evitar resets falsos y
    ejecuciones concurrentes superpuestas.
  - nuevo marcador `bg_diag_updated_at_ms` para deteccion nativa de ciclo Dart
    congelado.
- `ServiceRestarterReceiver` (Android nativo):
  - ahora revisa si el ciclo Dart quedo stale (`bg_diag_updated_at_ms` > 3 min).
  - si detecta stale, fuerza reinicio controlado de `BackgroundService`.
  - si el servicio no esta corriendo, solicita arranque inmediato.
  - diagnostico nativo conserva estado de arranque/error para trazabilidad.
  - fallback nativo endurecido a 1 minuto y reprogramado en cada tick para
    evitar pérdida de watchdog tras suspensión OEM.
  - tick de fallback ahora envía ping de keepalive al servicio cuando está
    activo, reduciendo cierres silenciosos por inactividad prolongada.

### Hotfix anti-"replay masivo" de notificaciones
- `BackgroundServiceManager._pollIncomingCommunications`:
  - se suprime replay de eventos antiguos al reabrir app.
  - notificaciones individuales solo para eventos recientes:
    - radio: ventana de 12 minutos,
    - parte sorpresa: ventana de 15 minutos.
  - eventos fuera de ventana se marcan como vistos localmente y se reflejan en
    diagnóstico (`COMM_OK_..._DROP_Rx_Py`) para trazabilidad sin spam.

### Hotfix Voz en Partes (Obligatorio/Sorpresa)
- `home_screen.dart`:
  - correccion critica: resultados vacios de `SpeechToText` ya no sobrescriben
    una transcripcion valida (evita falsos `0 coincidencia`).
  - captura de voz con ventana ampliada (`10s`) y reintento automatico de
    microfono en el mismo intento si no hay texto reconocido.
  - endurecimiento de persistencia de fallos:
    - `insertInconsistencia` con reintento (3 intentos).
    - `upsertParteOficial` RECHAZADO por voz con reintento (3 intentos).
    - fallback a `monitoreo_reportes` cuando no se puede guardar
      inconsistencia, para no perder evidencia operativa.
  - cierre manual de ventana de parte tambien persiste inconsistencia con
    reintento + fallback operativo.

### Calidad
- `flutter analyze` OK
- `flutter build apk --debug` OK
- APK generado: `build/app/outputs/flutter-apk/app-debug.apk`

## 2026-02-23

### Orden Operativa Inquebrantable
- Directriz permanente del proyecto SCCP:
  la seguridad biometrica de voz y la automatizacion de tareas de control
  en primer plano y segundo plano son prioridad absoluta.
- Ningun cambio funcional, de UX o de rendimiento puede reducir, omitir o
  debilitar estos dos pilares.
- Toda decision tecnica debe preservar y reforzar:
  - validacion robusta de identidad (frase aleatoria + biometria en vivo),
  - continuidad autonoma del monitoreo y reportes sin dependencia de accion
    manual del oficial.

### Hotfix Critico de Estabilidad (post-login + BG)
- Correccion de cierre de app al acceder:
  - causa raiz: `RemoteServiceException` por `startForegroundService`
    disparado desde `ServiceRestarterReceiver`.
  - solucion: el receiver nativo deja de forzar arranque directo del servicio
    y delega recuperacion al watchdog Dart (evita crash del proceso principal).
- Blindaje anti-crash en flujo post-login:
  - `HomeScreen` ahora ejecuta tareas async de arranque/lifecycle en wrapper
    protegido (`_runGuarded`) para impedir cierres por excepciones no capturadas.
  - `startOperationalStack`, snapshots y acciones de notificacion ahora
    manejan errores con degradacion segura.
- Fiabilidad de reportes en segundo plano reforzada:
  - timeout de repositorio reducido (`15s -> 8s`) para evitar ciclos bloqueados.
  - flush de cola limitado por ciclo (`20 -> 4`) para priorizar continuidad.
  - recuperacion de slots por ciclo ajustada (`6 -> 3`) para evitar sobrecarga.
  - watchdog de tarea ocupado endurecido (`55s -> 35s`) para reset mas rapido.
  - timer de polling (25s) ahora intenta tambien snapshot operacional
    deduplicado por slot, reduciendo huecos cuando un tick de 1 min no dispara.

### Seguridad Biométrica (anti-bypass por reinstalación)
- Login endurecido:
  - si no es primer acceso y no se encuentra perfil de voz ni remoto ni local,
    el acceso queda bloqueado por seguridad (no permite re-registro libre).
  - objetivo: impedir evasión de biometría mediante desinstalar/reinstalar
    y registrar una voz distinta sin validación de supervisor.

### Seguridad de Partes (Obligatorio + Sorpresa)
- Validacion de voz reforzada en el flujo de partes:
  - ahora exige frase de control aleatoria por cada parte,
  - y, cuando aplica biometria real, exige doble validacion en el mismo intento:
    `frase aleatoria + biometria de voz`.
- Se mantiene cierre automatico por seguridad al 3er fallo con inconsistencia
  `POSIBLE_SUPLANTACION`.
- Se agrega trazabilidad operativa en payload:
  - `CHALLENGE:<frase>` y `VOZ_TXT:<transcripcion>` en registro de parte.

### Fiabilidad de Segundo Plano
- Confirmado stack activo:
  - `ForegroundService` con `stopWithTask=false` para continuidad al minimizar.
  - `AlarmWatchdog` periodico de respaldo (2 min).
- Ajuste aplicado en Android manifest:
  - `RebootBroadcastReceiver` de `android_alarm_manager_plus` habilitado para
    reprogramar watchdog tras reinicio del dispositivo.
- Hardening anti-cierre por swipe:
  - se registra `ServiceRestarterReceiver` nativo en Android.
  - `MainActivity` agenda un reinicio corto al destruirse la tarea.
  - el receiver arranca de nuevo `BackgroundService` en `BOOT_COMPLETED`,
    `MY_PACKAGE_REPLACED` y accion explicita de reinicio.
  - `MainActivity` agenda ademas un chequeo nativo periodico (2 min) para
    auto-recuperar servicio aunque la UI este cerrada.
  - `AlarmWatchdog` ahora intenta primero programacion exacta y si no puede,
    usa fallback inexacto.
- Diagnostico operativo ampliado:
  - footer muestra `BG ERR` (ultimo error de background) y `BG QUEUE`
    (reportes pendientes en cola local).
- Hotfix de continuidad en bloqueo de pantalla:
  - se agrega anti-bloqueo del ciclo de background (`WARN_BG_TASK_RESET_STALE`)
    para evitar estado `SKIP_BG_TASK_BUSY` permanente.
  - `openOperationalSession` y `heartbeatOperationalSession` ahora usan timeout
    defensivo en background para que una llamada colgada no congele reportes.
  - watchdog por `android_alarm_manager_plus` vuelve a modo periodico
    `inexact + allowWhileIdle` para mejor estabilidad en dispositivos con Doze.
- Observabilidad de background ampliada:
  - nuevo historial persistente `bg_diag_history` (ultimos 80 eventos) con:
    hora, estado, error resumido y cola pendiente.
  - boton `LOG BG` en footer operativo para inspeccionar trazas completas
    directamente en campo desde el movil.
- Hardening extra anti-suspension en Android:
  - `ServiceRestarterReceiver` cambia a watchdog nativo encadenado:
    cada ejecucion reprograma siguiente chequeo con
    `setExactAndAllowWhileIdle` (fallback `setAndAllowWhileIdle`).
  - `AlarmWatchdogService` vuelve a intentar `exact: true` con fallback
    inexacto para aumentar probabilidad de recuperacion en bloqueo profundo.
- Diagnostico nativo de watchdog:
  - `ServiceRestarterReceiver` escribe telemetria nativa en preferencias
    compartidas (`bg_native_*`): ultimo disparo, accion, contador, proximo
    chequeo, modo de scheduling y estado de arranque del servicio.
  - footer y `LOG BG` muestran tambien estado nativo para detectar si Android
    realmente dispara el receiver durante bloqueo.
- Hotfix critico BG (bloqueado/minimizado/otras apps):
  - el servicio ya no espera tareas de notificaciones/partes para arrancar los
    timers de monitoreo; primero levanta timers y luego ejecuta ciclos en modo
    no bloqueante.
  - `pollParteSchedulerNow` y verificacion de faltas ahora tienen timeout
    defensivo para evitar cuelgues silenciosos que detenian reportes.
  - watchdog Dart (`AlarmWatchdog`) y watchdog nativo encadenado pasan a
    chequeo cada 1 minuto para recuperar servicio mas rapido si Android lo
    suspende.
- Hotfix de estabilidad watchdog OEM (Tecno/Honor/Xiaomi):
  - se elimina dependencia de `exact alarms` para el watchdog nativo
    encadenado y para `android_alarm_manager_plus`.
  - ambos pasan a programacion `setAndAllowWhileIdle` / `exact:false`
    (inexacta) para mejorar disparo real en campo cuando Android degrada
    alarmas exactas en idle.
  - `LOG BG` ahora debe reflejar `NATIVE MODE: ALLOW_WHILE_IDLE_INEXACT`
    cuando el parche esta activo.
- Recuperacion de slots perdidos en reportes:
  - cuando el BG despierta tarde (por Doze/OEM), ahora recupera slots de 6 min
    no emitidos en el mismo ciclo (`catchup`) hasta un maximo de 6 slots.
  - los reportes recuperados quedan marcados en `parte_novedad` con
    `RECOVERED_SLOT` para trazabilidad forense.
  - objetivo: evitar huecos amplios en `monitoreo_reportes` aun cuando Android
    congele ejecuciones intermedias.
- UX critica en partes obligatorios/sorpresa (voz + notificacion):
  - mensajes de error de voz reforzados y explicitos en la misma ventana:
    - `ERROR: VOZ NO CAPTURADA`
    - `ERROR: VOZ NO COINCIDE`
    - `ERROR REPORTE NO ENVIADO`
  - estado de voz visible y persistente en panel (grabando, validada,
    rechazada, microfono no disponible).
  - notificaciones de partes dejan de usar `fullScreenIntent` para evitar
    apertura automatica directa al parte sin accion del oficial.
  - canales de partes migran a `v3` para forzar recreacion de canal Android y
    recuperar configuracion de sonido/vibracion en equipos que cacheaban estado
    anterior del canal.
- Auditoria login oficial robusta:
  - `openOperationalSession` ahora soporta `recordLoginLog`.
  - al login interactivo del oficial se registra evento `active` incluso en
    sesion reusada o en ruta fallback.
  - insercion `login_logs` con compatibilidad dual (schema extendido + legacy).
- Hotfix final anti-corte de reportes (bloqueado/minimizado):
  - `ServiceRestarterReceiver` ahora usa doble estrategia:
    - one-shot encadenado con intento `setExactAndAllowWhileIdle` y fallback,
    - repetidor inexacto de respaldo cada 4 minutos.
  - compatibilidad de intent filter ampliada para accion fallback del watchdog.
  - en BG, un slot de 6 min solo se marca como emitido cuando realmente se
    guardo en Supabase; si falla, queda pendiente para reintento.
  - cola local de pendientes ahora deduplica por `id_reporte` para evitar
    crecimiento por reintentos del mismo slot.
- Seguridad biometrica anti-reinstalacion / anti-suplantacion:
  - el perfil biometrico de voz se serializa y respalda en Supabase dentro del
    registro `VOZ_<id_oficial>` para poder restaurar en reinstalaciones.
  - al login, si falta perfil local pero existe respaldo remoto, se restaura
    automaticamente y no se solicita re-registro.
  - se bloquea sobrescritura de voz cuando ya existe un perfil previo para el
    oficial (`saveVoiceProfileCode` rechaza reemplazo por defecto).
  - onboarding prioriza codigo de voz existente antes de generar uno nuevo.
- Hotfix critico "corte tras 4 reportes" (segundo plano):
  - `AlarmWatchdog` Dart reforzado:
    - doble programacion periodica simultanea (`exact` + `inexact`) como
      redundancia anti-Doze/OEM.
    - intervalo de watchdog ajustado a 1 minuto para recuperacion mas rapida.
    - callback ya no reconfigura el `BackgroundService` en cada tick
      (evita reinicializaciones repetidas del servicio).
  - nueva telemetria de watchdog Dart en preferencias:
    - `bg_watchdog_rx_count`, `bg_watchdog_last_at`,
      `bg_watchdog_last_status`, `bg_watchdog_last_error`,
      `bg_watchdog_schedule_mode`.
  - `HomeScreen` muestra diagnostico separado de `Native RX` y `Dart WD`
    para aislar rapidamente si falla el receiver nativo o el alarm callback.
  - al pausar/reanudar app se re-aplica schedule de `AlarmWatchdog` para
    evitar perdida de alarmas tras cambios de estado del proceso.
- Hotfix bloqueo al ingresar (crash tras login):
  - `BackgroundServiceManager` y metodos publicos de entrada para background
    quedan anotados con `@pragma('vm:entry-point')` para evitar cierre por
    error AOT: "must be annotated".
  - compatibilidad extra con esquemas `oficial_sesiones` sin columna `estado`:
    - `getActiveOperationalSession`, `openOperationalSession`,
      `heartbeatOperationalSession` y `closeOperationalSession` ahora tienen
      fallback sin `estado` y con `upsert` defensivo.
  - objetivo: evitar loops de error por `42703` / `23505` que degradaban
    sesion y segundo plano al iniciar.

### Partes Oficiales y Sorpresa (flujo operativo)
- Apertura directa por notificacion:
  - se captura payload de notificacion incluso cuando la app arranca desde
    estado cerrado (launch por notificacion).
  - `HomeScreen` ahora escucha eventos de accion de notificacion para abrir
    de inmediato la ventana de parte, sin navegar manualmente por botones.
- Al completar un parte oficial:
  - se cancela la notificacion de parte oficial para evitar reaperturas y
    mensajes confusos de validacion.
- Canal critico de alertas de partes reforzado:
  - nuevos canales Android dedicados para obligatorio/sorpresa con
    sonido+vibracion de alarma, prioridad maxima y visibilidad publica.
- Validacion de voz en partes ajustada:
  - umbral de coincidencia sube a `75%`.
  - al confirmar parte, si falta validacion, se intenta una validacion de voz
    automatica (reintentos solo cuando falla, hasta 3).
  - para partes se mantiene biometria en vivo por intento (`frase aleatoria +
    huella de voz`); si valida en el primer intento, no se repite.

### Calidad
- `flutter analyze` OK
- `flutter test` OK

## 2026-02-18

### Hotfix Beta (RTC Radio A-B) - 17:06 (-04)
- Integracion de llamada de radio con audio RTC real (WebRTC) para enlace supervisor-oficial.
- Proveedor de radio actualizado:
  - Recepcion de `OFFER`.
  - Acciones `ACEPTAR` / `RECHAZAR`.
  - Envio de `ANSWER`, intercambio `ICE`, y cierre `HANGUP`.
- Pantalla de radio:
  - Banner de llamada entrante.
  - Botones directos de aceptar/rechazar/finalizar llamada.
  - Estado visible de conexion de llamada.
- Mensajes tecnicos RTC (`__RTC__`) ocultos del chat y excluidos de notificaciones para no contaminar la operacion.
- Dependencia agregada: `flutter_webrtc: ^1.3.0`.
- Validacion: `flutter analyze` OK.

### Estado Operativo (Validado en prueba real)
- Registro/edicion de datos de oficiales: operativo.
- Envio de reportes automaticos: operativo.
- Ajuste de zona horaria Bolivia en consultas/verificacion: operativo (`docs/supabase_smoke_test_5min.sql` + `docs/supabase_set_timezone_bolivia.sql`).

### Soporte SQL/Backend Preparado
- Auditoria y diagnostico RLS global: `docs/supabase_auditoria_rls_global.sql`.
- Correcciones RLS para radio/oficiales/supervisor:
  - `docs/supabase_fix_radio_rls.sql`
  - `docs/supabase_fix_oficiales_supervisor_rls.sql`
  - `docs/supabase_fix_supervisor_allowed_admins.sql`
  - `docs/supabase_patch_control_catalogo_supervisor.sql`
- Correccion puntual de coordenadas por codigo de reo:
  - `docs/supabase_fix_reo_coordenadas_by_codigo.sql`.
- Smoke test operativo 5 minutos para validar flujo end-to-end:
  - `docs/supabase_smoke_test_5min.sql`.

### Cambios de Flujo Definidos para Continuidad
- Estrategia de trabajo sin dependencia de emulacion pesada (priorizar movil real + webapp).
- Plan de limpieza de datos de prueba para nuevo ciclo de validacion:
  - `docs/supabase_cleanup_test_data.sql`.

### Pendientes Criticos (Lunes)
- Cierre de sesion robusto ante desinstalacion/reinstalacion/cierre forzado para evitar bloqueo "sesion activa".
- Notificaciones push: validar entrega en movil para mensajes radio y solicitudes de parte sorpresa.
- Radio voz en vivo tipo walkie-talkie (sin subir audio), con registro de hora/duracion en BD.
- Orden guiado de permisos en onboarding/login y mejora UX de ingreso de ID (teclado numerico).
- Validar crash de foreground service en Android en build release final.

### Observaciones
- El comportamiento de hora "adelantada" se relaciono con manejo UTC; la lectura/consulta en Bolivia ya quedo alineada en scripts y verificaciones.
- Se recomienda conservar este archivo como punto de control para plan de cierre de release.

### Actualizacion de Flujo (parte con novedad)
- Se incorporo boton directo `PARTE CON NOVEDAD + ABRIR CHAT` en ventana de partes.
- Al confirmar parte con novedad:
  - Se registra formalmente el parte (obligatorio o sorpresa).
  - Se envia aviso de radio con tipo `PARTE_NOVEDAD` (no queda como chat comun).
  - Opcionalmente se abre radio al instante para ampliar detalle.
- El chat de radio muestra `PARTE_NOVEDAD` con estilo visual diferenciado.
- Notificaciones locales contemplan `PARTE_NOVEDAD` con alerta sonora.

### Validacion tecnica
- `flutter analyze` OK
- `flutter test` OK
