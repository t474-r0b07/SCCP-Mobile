import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../../core/constants/app_constants.dart';
import '../../core/utils/parte_schedule_utils.dart';
import '../../core/utils/shift_utils.dart';
import '../../core/utils/utc_time_utils.dart';
import '../repositories/supabase_repository.dart';
import 'radio_rtc_signaling.dart';

@pragma('vm:entry-point')
void onNotificationTapBackground(NotificationResponse response) {
  unawaited(
      NotificationService.storePendingActionFromPayload(response.payload));
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static final SupabaseRepository _repository = SupabaseRepository();
  static final StreamController<Map<String, String>> _actionEvents =
      StreamController<Map<String, String>>.broadcast();
  static const String _pendingActionKey = 'notif_pending_action';
  static const String _pendingActionDataKey = 'notif_pending_action_data';
  static const String actionOpenRadio = 'OPEN_RADIO';
  static const String actionOpenParteSorpresa = 'OPEN_PARTE_SORPRESA';
  static const String actionOpenParteObligatorio = 'OPEN_PARTE_OBLIGATORIO';
  static Timer? _parteOficialTimer;
  static bool _enabled = false;
  static bool _schedulerStarted = false;
  static bool _parteCheckRunning = false;
  static bool _launchPayloadChecked = false;
  static bool _timezoneReady = false;
  static const Duration _parteSchedulerTimeout = Duration(seconds: 10);
  static const Duration _repoTimeout = Duration(seconds: 8);
  static const int _parteLateToleranceMinutes = 20;
  static const Duration _missingAlertRecencyWindow = Duration(minutes: 90);
  static const int _maxMissingSlotsPerCycle = 4;
  static final Int64List _alarmVibration = Int64List.fromList(
    [0, 900, 350, 900, 350, 1200],
  );
  static Stream<Map<String, String>> get actionEvents => _actionEvents.stream;

  static Future<void> initialize({bool startScheduler = true}) async {
    if (!_supportsLocalNotifications()) {
      _enabled = false;
      return;
    }

    if (_enabled) {
      if (startScheduler && !_schedulerStarted) {
        _startParteOficialScheduler();
      }
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) async {
        await storePendingActionFromPayload(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: onNotificationTapBackground,
    );
    await _captureLaunchNotificationAction();
    await _ensureTimezoneConfigured();

    final androidAlertsChannel = AndroidNotificationChannel(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _alarmVibration,
    );

    final androidBackgroundChannel = AndroidNotificationChannel(
      AppConstants.backgroundNotificationChannelId,
      AppConstants.backgroundNotificationChannelName,
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    final androidPartesMilitarChannel = AndroidNotificationChannel(
      AppConstants.notificationPartesMilitarChannelId,
      AppConstants.notificationPartesMilitarChannelName,
      description: 'Canal critico para partes obligatorios',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _alarmVibration,
    );
    final androidPartesSorpresaChannel = AndroidNotificationChannel(
      AppConstants.notificationPartesSorpresaChannelId,
      AppConstants.notificationPartesSorpresaChannelName,
      description: 'Canal critico para partes sorpresa',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _alarmVibration,
    );
    final androidShiftChannel = AndroidNotificationChannel(
      AppConstants.notificationShiftChannelId,
      AppConstants.notificationShiftChannelName,
      description: 'Canal critico para reactivacion de turno y reingreso',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: _alarmVibration,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidAlertsChannel);
    await androidPlugin?.createNotificationChannel(androidBackgroundChannel);
    await androidPlugin?.createNotificationChannel(androidPartesMilitarChannel);
    await androidPlugin
        ?.createNotificationChannel(androidPartesSorpresaChannel);
    await androidPlugin?.createNotificationChannel(androidShiftChannel);
    // El prompt de permisos se gestiona en onboarding con permission_handler.
    // No solicitar aquí para evitar ventana de permiso antes de abrir app.

    _enabled = true;
    if (startScheduler) {
      _startParteOficialScheduler();
    }
  }

  static void _startParteOficialScheduler() {
    _parteOficialTimer?.cancel();
    _schedulerStarted = true;
    unawaited(_safeCheckAndTriggerParteOficial());
    _parteOficialTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_safeCheckAndTriggerParteOficial()),
    );
  }

  static Future<void> pollParteSchedulerNow() async {
    if (!_supportsLocalNotifications()) return;
    await initialize(startScheduler: false);
    await _safeCheckAndTriggerParteOficial();
  }

  static Future<void> _safeCheckAndTriggerParteOficial() async {
    if (_parteCheckRunning) return;
    _parteCheckRunning = true;
    try {
      await _checkAndTriggerParteOficial().timeout(_parteSchedulerTimeout);
    } on TimeoutException {
      debugPrint('NotificationService: parte scheduler timeout');
    } catch (_) {
      // Silencioso: evita que excepciones maten el scheduler.
    } finally {
      _parteCheckRunning = false;
    }
  }

  static Future<void> _checkAndTriggerParteOficial() async {
    if (!await _isOperationalShift()) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final oficialId = prefs.getString('user_id');
    if (oficialId == null || oficialId.isEmpty) return;

    final activeSlot = ParteScheduleUtils.activeSlot(
      now,
      grace: ParteScheduleUtils.graceMinutes,
    );
    if (activeSlot != null) {
      final alertKey =
          'parte_alert_${oficialId}_${ParteScheduleUtils.slotKey(activeSlot)}';
      final wasAlerted = prefs.getBool(alertKey) ?? false;
      if (!wasAlerted) {
        await showParteOficialAlert(activeSlot);
        await prefs.setBool(alertKey, true);
      }
    }
    await _checkAndRegisterMissingPartes(now).timeout(
      _parteSchedulerTimeout,
      onTimeout: () {},
    );
  }

  static Future<void> showParteOficialAlert(DateTime reportTime) async {
    if (!_enabled) return;
    if (!await _isOperationalShift()) return;

    try {
      await _audioPlayer.play(AssetSource('sounds/militar_alarm.wav'));
    } catch (_) {
      // Silencioso: algunos dispositivos bloquean audio en background.
    }

    final payload =
        '$actionOpenParteObligatorio|${reportTime.toLocal().toIso8601String()}';
    try {
      await _notifications.show(
        AppConstants.notificationIdPartesOficiales,
        'PARTE OFICIAL PROGRAMADO',
        'Parte habilitado ${reportTime.hour.toString().padLeft(2, "0")}:${reportTime.minute.toString().padLeft(2, "0")} - ventana ${ParteScheduleUtils.graceMinutes} min (+$_parteLateToleranceMinutes min tolerancia tecnica)',
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationPartesMilitarChannelId,
            AppConstants.notificationPartesMilitarChannelName,
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: false,
            category: AndroidNotificationCategory.alarm,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _alarmVibration,
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> showParteSorpresaAlert(Map<String, dynamic> parte) async {
    if (!_enabled) return;

    try {
      await _audioPlayer.play(AssetSource('sounds/sorpresa_alarm.wav'));
    } catch (_) {
      // Silencioso
    }

    try {
      final idSorpresa = (parte['id_sorpresa'] ?? '').toString();
      final payload = idSorpresa.isEmpty
          ? actionOpenParteSorpresa
          : '$actionOpenParteSorpresa|$idSorpresa';
      await _notifications.show(
        AppConstants.notificationIdPartesSorpresa,
        'PARTE SORPRESA',
        parte['razon'] as String? ?? 'Verificacion solicitada',
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationPartesSorpresaChannelId,
            AppConstants.notificationPartesSorpresaChannelName,
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: false,
            category: AndroidNotificationCategory.alarm,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _alarmVibration,
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> cancelParteSorpresaAlert() async {
    if (!_enabled) return;
    try {
      await _notifications.cancel(AppConstants.notificationIdPartesSorpresa);
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> cancelParteOficialAlert() async {
    if (!_enabled) return;
    try {
      await _notifications.cancel(AppConstants.notificationIdPartesOficiales);
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> showRadioMessageAlert({
    required String fromUser,
    required String message,
    required String type,
  }) async {
    if (!_enabled) return;
    if (RadioRtcSignal.isRtcPayload(message)) return;

    final cleanMessage = message.trim().isEmpty ? '(Sin contenido)' : message;
    final cleanType = type.trim().isEmpty ? 'RADIO' : type.toUpperCase();
    final sender = fromUser.trim().isEmpty ? 'Supervisor' : fromUser.trim();
    final upperMsg = cleanMessage.toUpperCase();
    final isCallStart = cleanType == 'CALL_START' ||
        upperMsg.contains('INICIO LLAMADA DE VOZ') ||
        upperMsg.contains('INICIO CONTACTO RADIO');
    final isCallEnd = cleanType == 'CALL_END' ||
        upperMsg.contains('FIN LLAMADA DE VOZ') ||
        upperMsg.contains('FIN CONTACTO RADIO');
    final soundName = _soundForRadioType(cleanType);
    final title = isCallStart
        ? 'CONTACTO RADIO SOLICITADO'
        : isCallEnd
            ? 'CONTACTO RADIO FINALIZADO'
            : 'RADIO: $cleanType';
    final category = isCallStart || isCallEnd
        ? AndroidNotificationCategory.call
        : AndroidNotificationCategory.message;
    final notificationId = isCallStart || isCallEnd
        ? AppConstants.notificationIdRadioCall
        : AppConstants.notificationIdRadio +
            (DateTime.now().millisecondsSinceEpoch % 100000);

    try {
      await _audioPlayer.play(AssetSource('sounds/$soundName.wav'));
    } catch (_) {
      // Silencioso
    }

    try {
      await _notifications.show(
        notificationId,
        title,
        '$sender: $cleanMessage',
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationChannelId,
            AppConstants.notificationChannelName,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _alarmVibration,
            fullScreenIntent: isCallStart,
            category: category,
            sound: RawResourceAndroidNotificationSound(soundName),
          ),
        ),
        payload: actionOpenRadio,
      );
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> showOperationalAlert({
    required String title,
    required String message,
  }) async {
    if (!_enabled) return;

    final body =
        message.trim().isEmpty ? 'Alerta operativa detectada.' : message;
    try {
      await _notifications.show(
        AppConstants.notificationIdInconsistencias + 99,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationShiftChannelId,
            AppConstants.notificationShiftChannelName,
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _alarmVibration,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
      );
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> showShiftActivationReminder({
    required String group,
    String? turno,
  }) async {
    if (!_supportsLocalNotifications()) return;
    await initialize(startScheduler: false);
    if (!_enabled) return;

    final groupLabel = group.trim().isEmpty ? '--' : group.trim().toUpperCase();
    final shiftLabel = (turno ?? '').trim();
    final body = shiftLabel.isEmpty
        ? 'Turno $groupLabel activo. Ingresa y confirma activación operativa.'
        : 'Turno $groupLabel activo ($shiftLabel). Ingresa y confirma activación operativa.';

    try {
      await _notifications.show(
        AppConstants.notificationIdShiftReactivation,
        'TURNO ACTIVO',
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationShiftChannelId,
            AppConstants.notificationShiftChannelName,
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _alarmVibration,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
      );
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> cancelShiftActivationReminder() async {
    if (!_supportsLocalNotifications()) return;
    await initialize(startScheduler: false);
    if (!_enabled) return;
    try {
      await _notifications.cancel(AppConstants.notificationIdShiftReactivation);
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> scheduleShiftActivationReminder({
    required DateTime reminderAt,
    required String group,
    String? turno,
  }) async {
    if (!_supportsLocalNotifications()) return;
    await initialize(startScheduler: false);
    if (!_enabled) return;

    await _ensureTimezoneConfigured();
    final now = DateTime.now();
    if (!reminderAt.isAfter(now)) return;

    final groupLabel = group.trim().isEmpty ? '--' : group.trim().toUpperCase();
    final shiftLabel = (turno ?? '').trim();
    final body = shiftLabel.isEmpty
        ? 'Turno $groupLabel activo. Ingresa y confirma activación operativa.'
        : 'Turno $groupLabel activo ($shiftLabel). Ingresa y confirma activación operativa.';

    final scheduled = tz.TZDateTime.from(reminderAt.toLocal(), tz.local);

    try {
      await _notifications.zonedSchedule(
        AppConstants.notificationIdShiftReactivation,
        'TURNO ACTIVO',
        body,
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationChannelId,
            AppConstants.notificationChannelName,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _alarmVibration,
          ),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> _checkAndRegisterMissingPartes(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final oficialId = prefs.getString('user_id');
    if (oficialId == null || oficialId.isEmpty) return;

    final slots = ParteScheduleUtils.slotsForNow(now).toList()
      ..sort((a, b) => b.compareTo(a));
    var processed = 0;
    for (final slot in slots) {
      if (processed >= _maxMissingSlotsPerCycle) {
        break;
      }
      final missingAt = slot.add(
        const Duration(
          minutes:
              ParteScheduleUtils.graceMinutes + _parteLateToleranceMinutes + 1,
        ),
      );
      if (now.isBefore(missingAt)) continue;
      final slotAge = now.difference(slot);
      final shouldNotifySlot = slotAge <= _missingAlertRecencyWindow;

      final slotKey = ParteScheduleUtils.slotKey(slot);
      final doneKey = 'parte_done_${oficialId}_$slotKey';
      final faltaKey = 'parte_falta_${oficialId}_$slotKey';
      final alertKey = 'parte_alert_${oficialId}_$slotKey';
      var isDone = prefs.getBool(doneKey) ?? false;
      if (!isDone) {
        final existsInDb = await _repository
            .hasParteOficialForSlot(
              idOficial: oficialId,
              slotTime: slot,
            )
            .timeout(_repoTimeout, onTimeout: () => false);
        if (existsInDb) {
          isDone = true;
          await prefs.setBool(doneKey, true);
        }
      }
      final faltaSent = prefs.getBool(faltaKey) ?? false;
      if (isDone || faltaSent) continue;
      final wasAlerted = prefs.getBool(alertKey) ?? false;
      if (!wasAlerted) {
        // Evita ráfagas de notificaciones viejas tras reconexión prolongada.
        if (shouldNotifySlot) {
          await showParteOficialAlert(slot);
        }
        await prefs.setBool(alertKey, true);
        processed += 1;
        continue;
      }

      await _repository.insertInconsistencia({
        'id_oficial': oficialId,
        'tipo_inconsistencia': 'FALTA_REPORTE',
        'descripcion': 'ALERTA-SIN PARTE - slot $slotKey',
        'prioridad': 'ALTA',
        'fecha_deteccion': UtcTimeUtils.nowIso(),
      }).timeout(_repoTimeout, onTimeout: () => false);
      await prefs.setBool(faltaKey, true);
      if (shouldNotifySlot) {
        await _showMissingPartAlert(slot);
      }
      processed += 1;
    }
  }

  static Future<void> _showMissingPartAlert(DateTime slot) async {
    if (!_enabled) return;
    try {
      await _notifications.show(
        AppConstants.notificationIdInconsistencias +
            (slot.hour * 10) +
            slot.minute,
        'FALTA DE PARTE',
        'No se registro parte ${slot.hour.toString().padLeft(2, "0")}:${slot.minute.toString().padLeft(2, "0")} en la ventana de control.',
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.notificationPartesMilitarChannelId,
            AppConstants.notificationPartesMilitarChannelName,
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            enableVibration: true,
            vibrationPattern: _alarmVibration,
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        ),
      );
    } catch (_) {
      // Silencioso
    }
  }

  static bool _supportsLocalNotifications() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<bool> _isOperationalShift() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final shift = prefs.getString('user_shift');
    final group = prefs.getString('user_grupo');
    if (userId == null || userId.isEmpty) return false;
    return ShiftUtils.isWithinShift(shift, grupo: group);
  }

  static String _soundForRadioType(String type) {
    switch (type) {
      case 'CALL_START':
      case 'EMERGENCIA':
        return 'militar_alarm';
      case 'CONTROL_SORPRESA':
      case 'PARTE_NOVEDAD':
        return 'sorpresa_alarm';
      case 'CALL_END':
      case 'RADIO':
      case 'CONSULTA':
      default:
        return 'militar_alarm';
    }
  }

  static Future<void> storePendingActionFromPayload(String? payload) async {
    final raw = payload?.trim() ?? '';
    if (raw.isEmpty) return;

    final segments = raw.split('|');
    final action = segments.first.trim().toUpperCase();
    final data =
        segments.length > 1 ? segments.sublist(1).join('|').trim() : '';
    if (action.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final previousAction = prefs.getString(_pendingActionKey)?.trim() ?? '';
    final previousData = prefs.getString(_pendingActionDataKey)?.trim() ?? '';
    if (previousAction == action && previousData == data) {
      return;
    }
    if (action == actionOpenParteSorpresa) {
      await cancelParteSorpresaAlert();
    }
    if (action == actionOpenParteObligatorio) {
      await cancelParteOficialAlert();
    }
    await prefs.setString(_pendingActionKey, action);
    if (data.isEmpty) {
      await prefs.remove(_pendingActionDataKey);
    } else {
      await prefs.setString(_pendingActionDataKey, data);
    }
    _actionEvents.add({'action': action, 'data': data});
  }

  static Future<Map<String, String>?> takePendingAction() async {
    final prefs = await SharedPreferences.getInstance();
    final action = prefs.getString(_pendingActionKey)?.trim();
    if (action == null || action.isEmpty) return null;

    final data = prefs.getString(_pendingActionDataKey)?.trim() ?? '';
    await prefs.remove(_pendingActionKey);
    await prefs.remove(_pendingActionDataKey);
    return {'action': action, 'data': data};
  }

  static Future<void> _captureLaunchNotificationAction() async {
    if (_launchPayloadChecked) return;
    _launchPayloadChecked = true;
    try {
      final launchDetails =
          await _notifications.getNotificationAppLaunchDetails();
      final launchedByNotification =
          launchDetails?.didNotificationLaunchApp ?? false;
      if (!launchedByNotification) return;
      final payload =
          launchDetails?.notificationResponse?.payload?.trim() ?? '';
      if (payload.isEmpty) return;
      await storePendingActionFromPayload(payload);
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> _ensureTimezoneConfigured() async {
    if (_timezoneReady) return;
    tz_data.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    _timezoneReady = true;
  }
}
