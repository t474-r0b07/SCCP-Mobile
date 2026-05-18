import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/radio_message_model.dart';
import '../repositories/supabase_repository.dart';
import 'alarm_watchdog_service.dart';
import 'notification_service.dart';
import '../../core/utils/distance_calculator.dart';
import '../../core/utils/pending_reports_queue_utils.dart';
import '../../core/utils/shift_utils.dart';
import '../../core/utils/utc_time_utils.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/supabase_config.dart';

@pragma('vm:entry-point')
void sccpBackgroundOnStart(ServiceInstance service) {
  BackgroundServiceManager.onStart(service);
}

@pragma('vm:entry-point')
Future<bool> sccpBackgroundOnIosBackground(ServiceInstance service) {
  return BackgroundServiceManager.onIosBackground(service);
}

@pragma('vm:entry-point')
class BackgroundServiceManager {
  static const String _diagStatusKey = 'bg_diag_status';
  static const String _diagUpdatedAtKey = 'bg_diag_updated_at';
  static const String _diagUpdatedAtMsKey = 'bg_diag_updated_at_ms';
  static const String _diagErrorKey = 'bg_diag_error';
  static const String _diagHistoryKey = 'bg_diag_history';
  static const String _pendingReportsKey = 'bg_pending_reports';
  static const String _sessionOwnerUserKey = 'bg_session_owner_user';
  static const String _offShiftClosedUserKey = 'bg_off_shift_closed_user';
  static const String _lastOperationalAlertAtKey = 'bg_last_alert_at';
  static const String _lastOperationalAlertHashKey = 'bg_last_alert_hash';
  static const String _seenRadioIdsKey = 'bg_seen_radio_ids';
  static const String _seenParteIdsKey = 'bg_seen_parte_ids';
  static const String _lastReportSlotKey = 'bg_last_report_slot';
  static const String _lastReportAtKeyLegacy = 'bg_last_report_at';
  static const String _operationalReadyKey = 'operational_ready';
  static const String _lastHeartbeatPushAtKey = 'bg_last_hb_push_at';
  static const String _lastFixLatKey = 'bg_last_fix_lat';
  static const String _lastFixLngKey = 'bg_last_fix_lng';
  static const String _lastFixAccKey = 'bg_last_fix_acc';
  static const String _lastFixAtKey = 'bg_last_fix_at';
  static const String _lastFixOwnerUserKey = 'bg_last_fix_owner_user';
  static const String _outsideRangeStateKey = 'bg_outside_range_state';
  static const String _outsideRangeStreakKey = 'bg_outside_range_streak';
  static const String _insideRangeStreakKey = 'bg_inside_range_streak';
  static const String _mockedGpsStateKey = 'bg_mocked_gps_state';
  static const String _mockedGpsStreakKey = 'bg_mocked_gps_streak';
  static const String _trustedGpsStreakKey = 'bg_trusted_gps_streak';
  static const int _maxPendingReports = 240;
  static const int _maxDiagHistoryEntries = 80;
  static const int _maxFlushAttemptsPerCycle = 36;
  static const int _maxSeenIds = 220;
  static const int _maxCatchupSlotsPerCycle = 60;
  static const int _outOfRangeConfirmations = 2;
  static const int _inRangeConfirmations = 2;
  static const int _mockGpsConfirmations = 2;
  static const int _trustedGpsConfirmations = 2;
  static const int _reportCadenceMinutes = 6;
  static const Duration _minOperationalAlertGap = Duration(seconds: 90);
  static const Duration _incomingPollInterval = Duration(seconds: 15);
  static const Duration _maxCachedFixAge = Duration(minutes: 12);
  static const Duration _manualSnapshotMinGap = Duration(seconds: 90);
  static const Duration _heartbeatPushMinGap = Duration(minutes: 1);
  static const Duration _radioReplayWindow = Duration(minutes: 12);
  static const Duration _parteReplayWindow = Duration(minutes: 15);
  static const Duration _repoTimeout = Duration(seconds: 8);
  static const Duration _sessionRepoTimeout = Duration(seconds: 5);
  static const Duration _reoLookupTimeout = Duration(seconds: 5);
  static const Duration _parteSchedulerTimeout = Duration(seconds: 10);
  static Timer? _reportTaskTimer;
  static Timer? _incomingPollTimer;
  static Timer? _parteSchedulerTimer;
  static DateTime? _lastManualSnapshotAt;
  static bool _backgroundTaskRunning = false;
  static bool _backgroundTaskQueued = false;
  static DateTime? _backgroundTaskStartedAt;
  static const Duration _backgroundTaskMaxRuntime = Duration(minutes: 3);
  static bool _pollingCommRunning = false;

  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    if (!_supportsBackgroundService()) return;

    await NotificationService.initialize(startScheduler: false);
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: sccpBackgroundOnStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: AppConstants.backgroundNotificationChannelId,
        initialNotificationTitle: 'SCCP Activo',
        initialNotificationContent: 'Monitoreo en segundo plano',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: sccpBackgroundOnStart,
        onBackground: sccpBackgroundOnIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> ensureServiceRunning() async {
    if (!_supportsBackgroundService()) return;
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) {
      await initializeService();
      await service.startService();
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      service.invoke('setAsForeground');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> stopServiceIfRunning() async {
    if (!_supportsBackgroundService()) return;
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (!running) return;
    service.invoke('stopService');
  }

  static bool _supportsBackgroundService() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    await _ensureSupabaseInitialized();
    await NotificationService.initialize(startScheduler: false);

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });
      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
      await service.setAsForegroundService();
      service.on('stopService').listen((event) {
        service.stopSelf();
      });
      service.setForegroundNotificationInfo(
        title: 'SCCP Activo',
        content: 'Monitoreo en segundo plano',
      );
    }

    _reportTaskTimer?.cancel();
    _incomingPollTimer?.cancel();
    _parteSchedulerTimer?.cancel();

    // Arranca timers antes de ejecutar ciclos para evitar bloqueo de arranque.
    unawaited(_performBackgroundTask());
    unawaited(_pollIncomingCommunications());
    unawaited(_runParteSchedulerSafe());

    // Tick liviano cada minuto; el guard interno mantiene insercion por slot de 6 min.
    _reportTaskTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      unawaited(_performBackgroundTask());
      unawaited(_pollIncomingCommunications());
      unawaited(_runParteSchedulerSafe());
    });
    _incomingPollTimer = Timer.periodic(_incomingPollInterval, (timer) async {
      await _pollIncomingCommunications();
      await _refreshOperationalHeartbeat();
    });
    _parteSchedulerTimer =
        Timer.periodic(const Duration(minutes: 1), (timer) async {
      try {
        await _runParteSchedulerSafe();
      } catch (e) {
        await _writeDiag(status: 'PARTE_SCHEDULER_ERROR', error: e.toString());
      }
    });
  }

  static Future<void> _runParteSchedulerSafe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (!_isOperationalReady(prefs)) {
        return;
      }
      await NotificationService.pollParteSchedulerNow().timeout(
        _parteSchedulerTimeout,
        onTimeout: () async {
          await _writeDiag(status: 'PARTE_SCHEDULER_TIMEOUT');
        },
      );
    } catch (e) {
      await _writeDiag(status: 'PARTE_SCHEDULER_ERROR', error: e.toString());
    }
  }

  @pragma('vm:entry-point')
  static Future<void> runOperationalSnapshotNow({bool force = false}) async {
    if (!_supportsBackgroundService()) return;

    final prefs = await SharedPreferences.getInstance();
    final operationalReady = _isOperationalReady(prefs);
    final hasSession = (prefs.getString('user_id') ?? '').trim().isNotEmpty &&
        ((prefs.getString('user_device_id') ??
                prefs.getString('user_imei') ??
                '')
            .trim()
            .isNotEmpty) &&
        operationalReady;
    if (!hasSession) {
      await _writeDiag(
        status: operationalReady
            ? 'SNAPSHOT_SKIP_NO_SESSION'
            : 'SNAPSHOT_SKIP_NOT_READY',
      );
      return;
    }

    final now = DateTime.now().toUtc();
    if (!force && _lastManualSnapshotAt != null) {
      final elapsed = now.difference(_lastManualSnapshotAt!);
      if (elapsed < _manualSnapshotMinGap) {
        return;
      }
    }
    await _ensureSupabaseInitialized();
    await NotificationService.initialize(startScheduler: false);
    await _performBackgroundTask();
    await _pollIncomingCommunications();
    await _runParteSchedulerSafe();
    await _refreshOperationalHeartbeat();
    _lastManualSnapshotAt = now;
  }

  static Future<void> _ensureSupabaseInitialized() async {
    try {
      Supabase.instance.client;
      return;
    } catch (_) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    }
  }

  static Future<void> _writeDiag({
    required String status,
    String? error,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    final nowIso = UtcTimeUtils.nowIso();
    await prefs.setString(_diagStatusKey, status);
    await prefs.setString(_diagUpdatedAtKey, nowIso);
    await prefs.setInt(_diagUpdatedAtMsKey, now.millisecondsSinceEpoch);
    final normalizedError = (error ?? '').replaceAll('\n', ' ').trim();
    final shortError = normalizedError.length > 220
        ? normalizedError.substring(0, 220)
        : normalizedError;
    if (error != null && error.isNotEmpty) {
      await prefs.setString(_diagErrorKey, shortError);
    } else {
      await prefs.remove(_diagErrorKey);
    }
    final pendingCount = PendingReportsQueueUtils.decode(
      prefs.getString(_pendingReportsKey),
    ).length;
    await _appendDiagHistory(
      prefs: prefs,
      atIso: nowIso,
      status: status,
      error: shortError,
      pendingCount: pendingCount,
    );
  }

  static Future<void> _appendDiagHistory({
    required SharedPreferences prefs,
    required String atIso,
    required String status,
    required String error,
    required int pendingCount,
  }) async {
    final next = <Map<String, dynamic>>[];
    final raw = prefs.getString(_diagHistoryKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              next.add(Map<String, dynamic>.from(item));
            }
          }
        }
      } catch (_) {
        // Silencioso: reconstruye historial limpio.
      }
    }

    next.add({
      'at': atIso,
      'status': status,
      'error': error,
      'pending': pendingCount,
    });
    if (next.length > _maxDiagHistoryEntries) {
      next.removeRange(0, next.length - _maxDiagHistoryEntries);
    }
    await prefs.setString(_diagHistoryKey, jsonEncode(next));
  }

  static Future<void> _performBackgroundTask() async {
    if (_backgroundTaskRunning) {
      final startedAt = _backgroundTaskStartedAt;
      if (startedAt != null &&
          DateTime.now().toUtc().difference(startedAt) >
              _backgroundTaskMaxRuntime) {
        _backgroundTaskRunning = false;
        _backgroundTaskStartedAt = null;
        await _writeDiag(status: 'WARN_BG_TASK_RESET_STALE');
      } else {
        _backgroundTaskQueued = true;
        await _writeDiag(status: 'SKIP_BG_TASK_BUSY');
        return;
      }
    }
    _backgroundTaskRunning = true;
    _backgroundTaskStartedAt = DateTime.now().toUtc();
    try {
      await _ensureSupabaseInitialized();

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final deviceId =
          prefs.getString('user_device_id') ?? prefs.getString('user_imei');
      final idOficial = prefs.getString('user_id');
      final nombreOficial = prefs.getString('user_name');
      final reoAsignado = prefs.getString('reo_asignado');
      final grupo = prefs.getString('user_grupo');
      final turno = prefs.getString('user_shift');

      if (deviceId == null ||
          idOficial == null ||
          deviceId.trim().isEmpty ||
          idOficial.trim().isEmpty) {
        await _writeDiag(status: 'SKIP_NO_SESSION_DATA');
        return;
      }
      if (!_isOperationalReady(prefs)) {
        await _writeDiag(status: 'SKIP_OPERATIONAL_NOT_READY');
        return;
      }

      await _resetRuntimeIfSessionUserChanged(
        prefs: prefs,
        idOficial: idOficial,
      );
      final purgedFromQueue = await _purgePendingQueueForActiveSession(
        prefs: prefs,
        idOficial: idOficial,
        deviceId: deviceId,
      );

      final isOperationalShift = ShiftUtils.isWithinShift(turno, grupo: grupo);
      if (!isOperationalShift) {
        await _terminateForOffShift(
          prefs: prefs,
          idOficial: idOficial,
          deviceId: deviceId,
          grupo: grupo,
          turno: turno,
        );
        await _writeDiag(status: 'SHIFT_END_AUTO_LOGOUT');
        return;
      }
      await _clearOffShiftClosedMarkerIfNeeded(
        prefs: prefs,
        idOficial: idOficial,
      );

      final repo = SupabaseRepository();
      unawaited(_safeOpenAndHeartbeatSession(
        repo: repo,
        idOficial: idOficial,
        nombreOficial: nombreOficial ?? idOficial,
        deviceId: deviceId,
      ));

      final nowUtc = DateTime.now().toUtc();
      final reportSlotUtc = _currentReportSlotUtc(nowUtc);
      final dueSlots = _computeDueSlots(
        prefs: prefs,
        currentSlotUtc: reportSlotUtc,
      );
      final hasPendingQueue =
          (prefs.getString(_pendingReportsKey) ?? '').trim().isNotEmpty;
      if (dueSlots.isEmpty) {
        if (hasPendingQueue) {
          final flushedIdleQueue = await _flushPendingReports(repo, prefs);
          if (!flushedIdleQueue) {
            await _writeDiag(status: 'PENDING_QUEUE_RETRY_IDLE');
            return;
          }
          if (purgedFromQueue > 0) {
            await _writeDiag(
              status: 'OK_PENDING_FLUSH_IDLE_PURGE_$purgedFromQueue',
            );
          } else {
            await _writeDiag(status: 'OK_PENDING_FLUSH_IDLE');
          }
          return;
        }
        if (purgedFromQueue > 0) {
          await _writeDiag(status: 'OK_HEARTBEAT_ONLY_PURGE_$purgedFromQueue');
          return;
        }
        await _writeDiag(status: 'OK_HEARTBEAT_ONLY');
        return;
      }

      final flushed = await _flushPendingReports(repo, prefs);
      if (!flushed) {
        await _writeDiag(status: 'PENDING_QUEUE_RETRY');
      }

      final battery = Battery();
      final batteryLevel = await battery.batteryLevel;
      BatteryState? batteryState;
      try {
        batteryState = await battery.batteryState;
      } catch (_) {
        batteryState = null;
      }
      final isCharging =
          batteryState == BatteryState.charging ||
              batteryState == BatteryState.full;
      final powerTag = isCharging ? 'POWER_CHARGING' : 'POWER_DISCHARGING';

      const bool isMoving = false;

      Position? position;
      bool usingCachedFix = false;
      double? latitude;
      double? longitude;
      double gpsAccuracy = 120;
      bool isMocked = false;
      String locationDiag = 'GPS_OK';
      String telemetryNote = 'MONITOREO_NORMAL';

      final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isLocationEnabled) {
        locationDiag = 'GPS_DISABLED';
        telemetryNote = 'SIN_GPS_SERVICIO_DESACTIVADO';
      } else {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          locationDiag = 'GPS_PERMISSION_DENIED';
          telemetryNote = 'SIN_GPS_PERMISO_DENEGADO';
        } else if (permission != LocationPermission.always) {
          locationDiag = 'GPS_ALWAYS_REQUIRED';
          telemetryNote = 'SIN_GPS_PERMISO_BACKGROUND';
        } else {
          try {
            position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium,
              timeLimit: const Duration(seconds: 4),
            );
          } catch (_) {
            try {
              position = await Geolocator.getLastKnownPosition();
              if (position != null &&
                  !_isUsableFallbackPosition(
                    position: position,
                    nowUtc: nowUtc,
                  )) {
                position = null;
              }
            } catch (_) {
              position = null;
            }
          }

          if (position != null) {
            latitude = position.latitude;
            longitude = position.longitude;
            gpsAccuracy = position.accuracy;
            isMocked = position.isMocked;
            await _cacheLastFix(
              prefs: prefs,
              latitude: latitude,
              longitude: longitude,
              accuracy: gpsAccuracy,
              capturedAtUtc: nowUtc,
              ownerUser: idOficial,
            );
          } else {
            final cached = _readCachedFix(
              prefs: prefs,
              ownerUser: idOficial,
            );
            if (cached != null) {
              latitude = cached.latitude;
              longitude = cached.longitude;
              gpsAccuracy = cached.accuracy;
              isMocked = false;
              usingCachedFix = true;
              locationDiag = 'GPS_CACHED_FIX';
              telemetryNote = 'GPS_CACHE_USADO';
            } else {
              locationDiag = 'GPS_NO_FIX';
              telemetryNote = 'SIN_DATOS_GPS';
            }
          }
        }
      }

      double? distancia;
      String estadoAlerta = 'NORMAL';
      String? inconsistenciaTipo;
      String? inconsistenciaDescripcion;

      final hasLocationFix = latitude != null && longitude != null;
      if (!hasLocationFix) {
        estadoAlerta = 'ALERTA';
        inconsistenciaTipo = 'SIN_DATOS_GPS';
        inconsistenciaDescripcion =
            'Reporte degradado: sin coordenadas ($telemetryNote)';
      } else {
        if (reoAsignado != null) {
          final reo = await repo
              .getReoBycodigo(reoAsignado)
              .timeout(_reoLookupTimeout, onTimeout: () => null);

          if (reo != null && reo.coordenadas != null) {
            distancia = DistanceCalculator.calculateDistance(
              latitude,
              longitude,
              reo.coordenadas![0],
              reo.coordenadas![1],
            );
            final transition = _evaluateRangeTransition(
              prefs: prefs,
              distanceMeters: distancia,
              gpsAccuracyMeters: gpsAccuracy,
            );
            if (transition.outsideConfirmed) {
              estadoAlerta = 'CRITICO';
            }
            if (transition.justEnteredOutside) {
              inconsistenciaTipo = 'DISTANCIA_EXCEDIDA';
              inconsistenciaDescripcion = transition.description;
              await _maybeNotifyOperationalAlert(
                prefs: prefs,
                title: 'ALERTA DISTANCIA_EXCEDIDA',
                message: inconsistenciaDescripcion,
              );
            }
          }
        }

        final mockTransition = _evaluateMockGpsTransition(
          prefs: prefs,
          observedMocked: hasLocationFix && isMocked,
        );
        if (mockTransition.mockConfirmed) {
          estadoAlerta = 'CRITICO';
        }
        if (mockTransition.justEnteredMocked) {
          inconsistenciaTipo = 'GPS_FALSO';
          inconsistenciaDescripcion =
              'Se detectó ubicación simulada (isMocked=true en $_mockGpsConfirmations lecturas consecutivas).';
        }
      }

      if (inconsistenciaTipo != null) {
        if (inconsistenciaTipo != 'DISTANCIA_EXCEDIDA') {
          await _maybeNotifyOperationalAlert(
            prefs: prefs,
            title: 'ALERTA $inconsistenciaTipo',
            message: inconsistenciaDescripcion ?? 'Alerta operativa detectada',
          );
        }
      }

      var savedCount = 0;
      var queuedCount = 0;
      String? latestReportId;
      DateTime? latestSlotUtc;

      for (final slotUtc in dueSlots) {
        final reportId = '${idOficial}_S${slotUtc.millisecondsSinceEpoch}';
        latestReportId = reportId;
        latestSlotUtc = slotUtc;
        final slotDelaySec = nowUtc.difference(slotUtc).inSeconds;
        final telemetryWithDelay = slotDelaySec > 90
            ? '$telemetryNote|DELAY_${slotDelaySec}s'
            : telemetryNote;
        final telemetryWithPower = '$telemetryWithDelay|$powerTag';
        final withRecoveryTag =
            slotUtc.isAtSameMomentAs(reportSlotUtc) || dueSlots.length == 1
                ? telemetryWithPower
                : '$telemetryWithPower|RECOVERED_SLOT';
        final data = {
          'id_reporte': reportId,
          'id_oficial_ref': idOficial,
          'nombre_oficial': nombreOficial ?? idOficial,
          'fecha_hora': slotUtc.toIso8601String(),
          'reo_asignado': reoAsignado,
          'ubicacion_actual':
              hasLocationFix ? '$latitude,$longitude' : 'SIN_DATOS_GPS',
          'latitud': latitude,
          'longitud': longitude,
          'distancia_metros': distancia,
          'estado_alerta': estadoAlerta,
          'nivel_bateria': batteryLevel,
          'gps_real': hasLocationFix ? !isMocked : false,
          'movimiento': hasLocationFix ? isMoving : false,
          'parte_novedad': isOperationalShift
              ? withRecoveryTag
              : '$withRecoveryTag|FUERA_TURNO',
          'imei': deviceId,
          'grupo': grupo?.toUpperCase(),
        };

        final reportSaved = await repo
            .upsertMonitoreo(data)
            .timeout(_repoTimeout, onTimeout: () => false);
        if (!reportSaved) {
          final queued = await _enqueuePendingReport(prefs, data);
          if (queued) {
            queuedCount += 1;
          }
        } else {
          savedCount += 1;
          await _markReportEmission(prefs, slotUtc);
        }
      }

      if (savedCount == 0 && queuedCount > 0) {
        await _writeDiag(status: 'QUEUED_NO_NETWORK');
        return;
      }

      final locationStatus = hasLocationFix
          ? (usingCachedFix
              ? 'OK_REPORT_SENT_CACHED_FIX'
              : (flushed
                  ? 'OK_REPORT_SENT'
                  : 'OK_REPORT_SENT_WITH_PENDING_RETRY'))
          : 'OK_REPORT_SENT_DEGRADED_$locationDiag';
      final catchupSuffix = dueSlots.length > 1
          ? '_CATCHUP_${dueSlots.length}_Q$queuedCount'
          : '';
      await _writeDiag(status: '$locationStatus$catchupSuffix');

      if (inconsistenciaTipo != null) {
        await repo.insertInconsistencia({
          'id_oficial': idOficial,
          'id_reporte': latestReportId ??
              '${idOficial}_S${(latestSlotUtc ?? reportSlotUtc).millisecondsSinceEpoch}',
          'tipo_inconsistencia': inconsistenciaTipo,
          'descripcion':
              inconsistenciaDescripcion ?? 'Inconsistencia detectada',
          'prioridad': 'ALTA',
        }).timeout(_repoTimeout, onTimeout: () => false);
      }
    } catch (e) {
      await _writeDiag(status: 'ERROR', error: e.toString());
      debugPrint('BackgroundService error: $e');
    } finally {
      _backgroundTaskRunning = false;
      _backgroundTaskStartedAt = null;
      if (_backgroundTaskQueued) {
        _backgroundTaskQueued = false;
        unawaited(_performBackgroundTask());
      }
    }
  }

  static Future<void> _safeOpenAndHeartbeatSession({
    required SupabaseRepository repo,
    required String idOficial,
    required String nombreOficial,
    required String deviceId,
  }) async {
    try {
      await repo
          .openOperationalSession(
            idOficial: idOficial,
            nombreOficial: nombreOficial,
            deviceId: deviceId,
          )
          .timeout(_sessionRepoTimeout);
    } catch (_) {
      // No bloquea el reporte operacional.
    }
    try {
      await repo
          .heartbeatOperationalSession(
            idOficial: idOficial,
            deviceId: deviceId,
          )
          .timeout(_sessionRepoTimeout);
    } catch (_) {
      // No bloquea el reporte operacional.
    }
  }

  static Future<void> _refreshOperationalHeartbeat() async {
    try {
      await _ensureSupabaseInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final nowUtc = DateTime.now().toUtc();
      final lastRaw = prefs.getString(_lastHeartbeatPushAtKey);
      if (lastRaw != null && lastRaw.isNotEmpty) {
        final last = DateTime.tryParse(lastRaw);
        if (last != null &&
            nowUtc.difference(last.toUtc()) < _heartbeatPushMinGap) {
          return;
        }
      }

      final deviceId =
          prefs.getString('user_device_id') ?? prefs.getString('user_imei');
      final idOficial = prefs.getString('user_id');
      final nombreOficial = prefs.getString('user_name');
      final grupo = prefs.getString('user_grupo');
      final turno = prefs.getString('user_shift');
      if (deviceId == null ||
          idOficial == null ||
          deviceId.trim().isEmpty ||
          idOficial.trim().isEmpty) {
        return;
      }
      if (!_isOperationalReady(prefs)) return;
      if (!ShiftUtils.isWithinShift(turno, grupo: grupo)) return;

      final repo = SupabaseRepository();
      await _safeOpenAndHeartbeatSession(
        repo: repo,
        idOficial: idOficial,
        nombreOficial: nombreOficial ?? idOficial,
        deviceId: deviceId,
      );
      final hasPendingQueue =
          (prefs.getString(_pendingReportsKey) ?? '').trim().isNotEmpty;
      if (hasPendingQueue) {
        await _flushPendingReports(repo, prefs);
      }
      await prefs.setString(_lastHeartbeatPushAtKey, nowUtc.toIso8601String());
    } catch (_) {
      // Silencioso: heartbeat de soporte.
    }
  }

  static DateTime _currentReportSlotUtc(DateTime nowUtc) {
    final utc = nowUtc.toUtc();
    final minuteBucket = utc.minute - (utc.minute % _reportCadenceMinutes);
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      minuteBucket,
    );
  }

  static String _reportSlotKeyUtc(DateTime slotUtc) {
    return slotUtc.toIso8601String();
  }

  static List<DateTime> _computeDueSlots({
    required SharedPreferences prefs,
    required DateTime currentSlotUtc,
  }) {
    final currentKey = _reportSlotKeyUtc(currentSlotUtc);
    final lastSlotRaw = prefs.getString(_lastReportSlotKey);

    DateTime? lastSlotUtc;
    if (lastSlotRaw != null && lastSlotRaw.isNotEmpty) {
      lastSlotUtc = DateTime.tryParse(lastSlotRaw)?.toUtc();
    }

    if (lastSlotUtc == null) {
      final legacy = prefs.getString(_lastReportAtKeyLegacy);
      if (legacy != null && legacy.isNotEmpty) {
        final legacyAt = DateTime.tryParse(legacy)?.toUtc();
        if (legacyAt != null) {
          lastSlotUtc = _currentReportSlotUtc(legacyAt);
        }
      }
    }

    if (lastSlotUtc == null) {
      return <DateTime>[currentSlotUtc];
    }

    if (_reportSlotKeyUtc(lastSlotUtc) == currentKey) {
      return const <DateTime>[];
    }

    if (lastSlotUtc.isAfter(currentSlotUtc)) {
      return <DateTime>[currentSlotUtc];
    }

    final allDue = <DateTime>[];
    var slot = lastSlotUtc.add(
      const Duration(minutes: _reportCadenceMinutes),
    );
    while (!slot.isAfter(currentSlotUtc)) {
      allDue.add(slot);
      slot = slot.add(const Duration(minutes: _reportCadenceMinutes));
    }

    if (allDue.length <= _maxCatchupSlotsPerCycle) {
      return allDue;
    }
    // Recupera en orden cronologico (mas antiguos primero) para no crear huecos
    // permanentes al reconectar despues de varias horas sin red.
    return allDue.sublist(0, _maxCatchupSlotsPerCycle);
  }

  static Future<void> _markReportEmission(
    SharedPreferences prefs,
    DateTime slotUtc,
  ) async {
    await prefs.setString(_lastReportSlotKey, _reportSlotKeyUtc(slotUtc));
    await prefs.setString(_lastReportAtKeyLegacy, slotUtc.toIso8601String());
  }

  static Future<void> _resetRuntimeIfSessionUserChanged({
    required SharedPreferences prefs,
    required String idOficial,
  }) async {
    final current = idOficial.trim();
    final previous = (prefs.getString(_sessionOwnerUserKey) ?? '').trim();
    if (current.isEmpty) return;
    if (previous.isEmpty || previous == current) {
      await prefs.setString(_sessionOwnerUserKey, current);
      return;
    }

    await prefs.remove(_lastReportSlotKey);
    await prefs.remove(_lastReportAtKeyLegacy);
    await prefs.remove(_lastHeartbeatPushAtKey);
    await prefs.remove(_outsideRangeStateKey);
    await prefs.remove(_outsideRangeStreakKey);
    await prefs.remove(_insideRangeStreakKey);
    await prefs.remove(_mockedGpsStateKey);
    await prefs.remove(_mockedGpsStreakKey);
    await prefs.remove(_trustedGpsStreakKey);
    await prefs.remove(_offShiftClosedUserKey);
    await prefs.remove(_lastFixLatKey);
    await prefs.remove(_lastFixLngKey);
    await prefs.remove(_lastFixAccKey);
    await prefs.remove(_lastFixAtKey);
    await prefs.remove(_lastFixOwnerUserKey);
    await prefs.setString(_sessionOwnerUserKey, current);
  }

  static Future<int> _purgePendingQueueForActiveSession({
    required SharedPreferences prefs,
    required String idOficial,
    required String deviceId,
  }) async {
    final raw = prefs.getString(_pendingReportsKey);
    final queue = PendingReportsQueueUtils.decode(raw);
    if (queue.isEmpty) return 0;

    final targetUser = idOficial.trim();
    final targetDevice = deviceId.trim().toUpperCase();
    final filtered = <Map<String, dynamic>>[];
    var removed = 0;

    for (final report in queue) {
      final reportUser =
          (report['id_oficial_ref'] ?? report['id_oficial'] ?? '')
              .toString()
              .trim();
      final reportDevice = (report['imei'] ?? report['device_id'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final sameUser = reportUser.isNotEmpty && reportUser == targetUser;
      final sameDevice = reportDevice.isEmpty || reportDevice == targetDevice;
      if (sameUser && sameDevice) {
        filtered.add(report);
      } else {
        removed += 1;
      }
    }

    if (removed == 0) return 0;
    if (filtered.isEmpty) {
      await prefs.remove(_pendingReportsKey);
      return removed;
    }

    await prefs.setString(
      _pendingReportsKey,
      PendingReportsQueueUtils.encode(filtered),
    );
    return removed;
  }

  static Future<void> _ensureOffShiftSessionClosed({
    required SharedPreferences prefs,
    required String idOficial,
    required String deviceId,
  }) async {
    final closedFor = (prefs.getString(_offShiftClosedUserKey) ?? '').trim();
    if (closedFor == idOficial) return;

    final repo = SupabaseRepository();
    try {
      await repo
          .closeOperationalSession(
            idOficial: idOficial,
            deviceId: deviceId,
            status: 'off_shift',
            durationMinutes: 0,
          )
          .timeout(_sessionRepoTimeout);
    } catch (_) {
      // Silencioso: el cierre de sesion no debe romper el bloqueo de tracking.
    }
    await prefs.setString(_offShiftClosedUserKey, idOficial);
  }

  static Future<void> _clearOffShiftClosedMarkerIfNeeded({
    required SharedPreferences prefs,
    required String idOficial,
  }) async {
    final closedFor = (prefs.getString(_offShiftClosedUserKey) ?? '').trim();
    if (closedFor == idOficial) {
      await prefs.remove(_offShiftClosedUserKey);
    }
  }

  static Future<void> _terminateForOffShift({
    required SharedPreferences prefs,
    required String idOficial,
    required String deviceId,
    required String? grupo,
    required String? turno,
  }) async {
    await _ensureOffShiftSessionClosed(
      prefs: prefs,
      idOficial: idOficial,
      deviceId: deviceId,
    );

    final remaining = ShiftUtils.timeUntilShiftStart(turno, grupo: grupo);
    final reminderAt = (remaining != null && remaining > Duration.zero)
        ? DateTime.now().add(remaining)
        : null;
    final groupLabel = (grupo ?? '').trim();
    final shiftLabel = (turno ?? '').trim();

    try {
      await NotificationService.cancelShiftActivationReminder();
      if (groupLabel.isNotEmpty) {
        if (reminderAt != null && reminderAt.isAfter(DateTime.now())) {
          await NotificationService.scheduleShiftActivationReminder(
            reminderAt: reminderAt,
            group: groupLabel,
            turno: shiftLabel.isEmpty ? null : shiftLabel,
          );
        } else {
          await NotificationService.showShiftActivationReminder(
            group: groupLabel,
            turno: shiftLabel.isEmpty ? null : shiftLabel,
          );
        }
      }
    } catch (_) {
      // Silencioso: no bloquear cierre por fallo de notificación.
    }

    final stableDeviceId = prefs.getString('device_identifier');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_grupo');
    await prefs.remove('user_shift');
    await prefs.remove('user_device_id');
    await prefs.remove('user_imei');
    await prefs.remove('reo_asignado');
    await prefs.remove(_operationalReadyKey);
    await prefs.remove(_pendingReportsKey);
    await prefs.remove(_sessionOwnerUserKey);
    await prefs.remove(_lastReportSlotKey);
    await prefs.remove(_lastReportAtKeyLegacy);
    await prefs.remove(_lastHeartbeatPushAtKey);
    await prefs.remove(_offShiftClosedUserKey);

    if (stableDeviceId != null && stableDeviceId.isNotEmpty) {
      await prefs.setString('device_identifier', stableDeviceId);
    }

    try {
      await AlarmWatchdogService.cancel();
    } catch (_) {
      // Silencioso
    }
    try {
      await stopServiceIfRunning();
    } catch (_) {
      // Silencioso
    }
  }

  static ({
    bool outsideConfirmed,
    bool justEnteredOutside,
    String description,
  }) _evaluateRangeTransition({
    required SharedPreferences prefs,
    required double distanceMeters,
    required double gpsAccuracyMeters,
  }) {
    final wasOutside = prefs.getBool(_outsideRangeStateKey) ?? false;
    var outStreak = prefs.getInt(_outsideRangeStreakKey) ?? 0;
    var inStreak = prefs.getInt(_insideRangeStreakKey) ?? 0;

    final accuracy = gpsAccuracyMeters.isFinite ? gpsAccuracyMeters : 0.0;
    final boundedAccuracy = accuracy.clamp(0.0, 80.0);
    // Regla operativa estricta:
    // ALERTA solo por encima del umbral fijo (50m por configuracion).
    // Se aplica histeresis corta para evitar spam al oscilar cerca del borde.
    const thresholdAlert = SupabaseConfig.maxDistanceMeters;
    final thresholdClear =
        (SupabaseConfig.maxDistanceMeters - 4.0).clamp(0.0, thresholdAlert);

    final outsideNow = distanceMeters > thresholdAlert;
    final insideNow = distanceMeters <= thresholdClear;

    if (outsideNow) {
      outStreak += 1;
      inStreak = 0;
    } else if (insideNow) {
      inStreak += 1;
      outStreak = 0;
    } else {
      outStreak = 0;
      inStreak = 0;
    }

    var outsideConfirmed = wasOutside;
    var justEnteredOutside = false;

    if (!wasOutside) {
      if (outStreak >= _outOfRangeConfirmations) {
        outsideConfirmed = true;
        justEnteredOutside = true;
      }
    } else if (inStreak >= _inRangeConfirmations) {
      outsideConfirmed = false;
    }

    unawaited(prefs.setBool(_outsideRangeStateKey, outsideConfirmed));
    unawaited(prefs.setInt(_outsideRangeStreakKey, outStreak));
    unawaited(prefs.setInt(_insideRangeStreakKey, inStreak));

    final description =
        'Distancia ${distanceMeters.toStringAsFixed(0)}m (umbral ${thresholdAlert.toStringAsFixed(0)}m, recupera <=${thresholdClear.toStringAsFixed(0)}m, precision ±${boundedAccuracy.toStringAsFixed(0)}m)';

    return (
      outsideConfirmed: outsideConfirmed,
      justEnteredOutside: justEnteredOutside,
      description: description,
    );
  }

  static ({bool mockConfirmed, bool justEnteredMocked})
  _evaluateMockGpsTransition({
    required SharedPreferences prefs,
    required bool observedMocked,
  }) {
    final wasMocked = prefs.getBool(_mockedGpsStateKey) ?? false;
    var mockStreak = prefs.getInt(_mockedGpsStreakKey) ?? 0;
    var trustedStreak = prefs.getInt(_trustedGpsStreakKey) ?? 0;

    if (observedMocked) {
      mockStreak += 1;
      trustedStreak = 0;
    } else {
      trustedStreak += 1;
      mockStreak = 0;
    }

    var mockConfirmed = wasMocked;
    var justEnteredMocked = false;

    if (!wasMocked) {
      if (mockStreak >= _mockGpsConfirmations) {
        mockConfirmed = true;
        justEnteredMocked = true;
      }
    } else if (trustedStreak >= _trustedGpsConfirmations) {
      mockConfirmed = false;
    }

    unawaited(prefs.setBool(_mockedGpsStateKey, mockConfirmed));
    unawaited(prefs.setInt(_mockedGpsStreakKey, mockStreak));
    unawaited(prefs.setInt(_trustedGpsStreakKey, trustedStreak));

    return (
      mockConfirmed: mockConfirmed,
      justEnteredMocked: justEnteredMocked,
    );
  }

  static Future<bool> _enqueuePendingReport(
    SharedPreferences prefs,
    Map<String, dynamic> report,
  ) async {
    try {
      final queue = PendingReportsQueueUtils.decode(
        prefs.getString(_pendingReportsKey),
      );
      final next = PendingReportsQueueUtils.enqueue(
        queue: queue,
        report: report,
        maxItems: _maxPendingReports,
      );
      await prefs.setString(
        _pendingReportsKey,
        PendingReportsQueueUtils.encode(next),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _flushPendingReports(
    SupabaseRepository repo,
    SharedPreferences prefs,
  ) async {
    final queue = PendingReportsQueueUtils.decode(
      prefs.getString(_pendingReportsKey),
    );

    if (queue.isEmpty) {
      await prefs.remove(_pendingReportsKey);
      return true;
    }

    final attempts = queue.length > _maxFlushAttemptsPerCycle
        ? _maxFlushAttemptsPerCycle
        : queue.length;
    final remaining = <Map<String, dynamic>>[];

    for (int i = 0; i < attempts; i++) {
      final ok = await repo
          .upsertMonitoreo(queue[i])
          .timeout(_repoTimeout, onTimeout: () => false);
      if (!ok) {
        remaining.add(queue[i]);
      }
    }

    if (attempts < queue.length) {
      remaining.addAll(queue.sublist(attempts));
    }

    if (remaining.isEmpty) {
      await prefs.remove(_pendingReportsKey);
      return true;
    }

    final trimmed =
        PendingReportsQueueUtils.trim(remaining, _maxPendingReports);
    await prefs.setString(
      _pendingReportsKey,
      PendingReportsQueueUtils.encode(trimmed),
    );
    return false;
  }

  static Future<void> _maybeNotifyOperationalAlert({
    required SharedPreferences prefs,
    required String title,
    required String message,
  }) async {
    final now = DateTime.now().toUtc();
    final marker = '${title.trim()}|${message.trim()}';
    final previousMarker = prefs.getString(_lastOperationalAlertHashKey);
    final previousAtRaw = prefs.getString(_lastOperationalAlertAtKey);
    final previousAt =
        previousAtRaw == null ? null : DateTime.tryParse(previousAtRaw);

    if (previousMarker == marker && previousAt != null) {
      final elapsed = now.difference(previousAt.toUtc());
      if (elapsed < _minOperationalAlertGap) {
        return;
      }
    }

    await NotificationService.showOperationalAlert(
      title: title,
      message: message,
    );
    await prefs.setString(_lastOperationalAlertHashKey, marker);
    await prefs.setString(_lastOperationalAlertAtKey, now.toIso8601String());
  }

  static Future<void> _pollIncomingCommunications() async {
    if (_pollingCommRunning) return;
    _pollingCommRunning = true;
    try {
      await _ensureSupabaseInitialized();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final idOficial = prefs.getString('user_id');
      if (idOficial == null || idOficial.isEmpty) return;
      if (!_isOperationalReady(prefs)) return;
      final grupo = prefs.getString('user_grupo');
      final turno = prefs.getString('user_shift');
      if (!ShiftUtils.isWithinShift(turno, grupo: grupo)) return;

      final repo = SupabaseRepository();
      final seenRadio = _decodeSeenSet(prefs.getString(_seenRadioIdsKey));
      final unread = await repo
          .getUnreadIncomingRadioMessages(
            idOficial: idOficial,
            limit: 20,
          )
          .timeout(_repoTimeout, onTimeout: () => <RadioMessageModel>[]);
      var notifiedRadio = 0;
      var droppedRadioReplay = 0;
      final now = DateTime.now();
      for (final msg in unread.reversed) {
        final id = msg.id.trim();
        if (id.isEmpty || seenRadio.contains(id)) continue;
        final age = now.toUtc().difference(msg.timestamp.toUtc());
        if (age > _radioReplayWindow) {
          seenRadio.add(id);
          droppedRadioReplay += 1;
          continue;
        }
        await NotificationService.showRadioMessageAlert(
          fromUser: msg.fromUser,
          message: msg.message,
          type: msg.type,
        );
        notifiedRadio += 1;
        seenRadio.add(id);
      }
      await _storeSeenSet(prefs, _seenRadioIdsKey, seenRadio);

      final seenPartes = _decodeSeenSet(prefs.getString(_seenParteIdsKey));
      final pendientes = await repo
          .getPendingPartesSorpresaByOficial(
            idOficial: idOficial,
            limit: 20,
          )
          .timeout(_repoTimeout, onTimeout: () => <Map<String, dynamic>>[]);
      var notifiedPartes = 0;
      var droppedParteReplay = 0;
      for (final parte in pendientes.reversed) {
        final estado = (parte['estado'] ?? '').toString().trim().toUpperCase();
        final isNuevo = estado.isEmpty ||
            estado == 'NUEVO' ||
            estado == 'NUEVA' ||
            estado == 'LEIDO' ||
            estado == 'PENDIENTE';
        if (!isNuevo) continue;
        final id = (parte['id_sorpresa'] ?? '').toString().trim();
        if (id.isEmpty || seenPartes.contains(id)) continue;
        final rawTs = (parte['timestamp'] ??
                parte['fecha_deteccion'] ??
                parte['fecha_creacion'] ??
                '')
            .toString()
            .trim();
        final ts = DateTime.tryParse(rawTs);
        if (ts != null &&
            now.toUtc().difference(ts.toUtc()) > _parteReplayWindow) {
          seenPartes.add(id);
          droppedParteReplay += 1;
          continue;
        }
        await NotificationService.showParteSorpresaAlert(parte);
        await repo
            .markParteLeido(id)
            .timeout(_repoTimeout, onTimeout: () async {});
        notifiedPartes += 1;
        seenPartes.add(id);
      }
      await _storeSeenSet(prefs, _seenParteIdsKey, seenPartes);
      await _writeDiag(
        status:
            'COMM_OK_R${notifiedRadio}_P${notifiedPartes}_DROP_R${droppedRadioReplay}_P$droppedParteReplay',
      );
    } catch (e) {
      await _writeDiag(status: 'COMM_POLL_ERROR', error: e.toString());
    } finally {
      _pollingCommRunning = false;
    }
  }

  static Set<String> _decodeSeenSet(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String>{};
    return raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static Future<void> _storeSeenSet(
    SharedPreferences prefs,
    String key,
    Set<String> values,
  ) async {
    if (values.isEmpty) {
      await prefs.remove(key);
      return;
    }
    final list = values.toList();
    if (list.length > _maxSeenIds) {
      final start = list.length - _maxSeenIds;
      await prefs.setString(key, list.sublist(start).join('|'));
      return;
    }
    await prefs.setString(key, list.join('|'));
  }

  static Future<void> _cacheLastFix({
    required SharedPreferences prefs,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime capturedAtUtc,
    required String ownerUser,
  }) async {
    await prefs.setDouble(_lastFixLatKey, latitude);
    await prefs.setDouble(_lastFixLngKey, longitude);
    await prefs.setDouble(_lastFixAccKey, accuracy);
    await prefs.setString(_lastFixAtKey, capturedAtUtc.toIso8601String());
    await prefs.setString(_lastFixOwnerUserKey, ownerUser.trim());
  }

  static _CachedFix? _readCachedFix({
    required SharedPreferences prefs,
    required String ownerUser,
  }) {
    final cachedOwner = (prefs.getString(_lastFixOwnerUserKey) ?? '').trim();
    final currentOwner = ownerUser.trim();
    if (cachedOwner.isEmpty ||
        currentOwner.isEmpty ||
        cachedOwner != currentOwner) {
      return null;
    }

    final lat = prefs.getDouble(_lastFixLatKey);
    final lng = prefs.getDouble(_lastFixLngKey);
    if (lat == null || lng == null) return null;

    final capturedRaw = prefs.getString(_lastFixAtKey);
    if (capturedRaw != null && capturedRaw.isNotEmpty) {
      final captured = DateTime.tryParse(capturedRaw);
      if (captured != null) {
        final age = DateTime.now().toUtc().difference(captured.toUtc());
        if (age > _maxCachedFixAge) return null;
      }
    }

    return _CachedFix(
      latitude: lat,
      longitude: lng,
      accuracy: prefs.getDouble(_lastFixAccKey) ?? 65.0,
    );
  }

  static bool _isOperationalReady(SharedPreferences prefs) {
    return prefs.getBool(_operationalReadyKey) ?? false;
  }

  static bool _isUsableFallbackPosition({
    required Position position,
    required DateTime nowUtc,
  }) {
    final lat = position.latitude;
    final lng = position.longitude;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;

    final accuracy = position.accuracy;
    if (accuracy.isNaN || accuracy <= 0 || accuracy > 2500) return false;

    final timestamp = position.timestamp;
    final age = nowUtc.difference(timestamp.toUtc());
    return age <= _maxCachedFixAge;
  }
}

class _CachedFix {
  final double latitude;
  final double longitude;
  final double accuracy;

  const _CachedFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}
