import 'dart:io';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_service.dart';

@pragma('vm:entry-point')
Future<void> sccpAlarmWatchdogCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  String? serviceError;
  try {
    await AlarmWatchdogService._recordWatchdogTick(status: 'CALLBACK_START');
    try {
      await BackgroundServiceManager.ensureServiceRunning();
    } catch (e) {
      serviceError = e.toString();
      await AlarmWatchdogService._recordWatchdogTick(
        status: 'CALLBACK_SERVICE_WARN',
        error: serviceError,
      );
    }

    await BackgroundServiceManager.runOperationalSnapshotNow(force: true);
    await AlarmWatchdogService._recordWatchdogTick(
      status: serviceError == null ? 'CALLBACK_OK' : 'CALLBACK_OK_NO_SERVICE',
      error: serviceError,
    );
  } catch (e) {
    final mergedError = serviceError == null
        ? e.toString()
        : 'service=$serviceError | snapshot=${e.toString()}';
    await AlarmWatchdogService._recordWatchdogTick(
      status: 'CALLBACK_ERROR',
      error: mergedError,
    );
    // Watchdog de respaldo: evita romper el isolate si falla un ciclo.
  }
}

class AlarmWatchdogService {
  static const int _alarmIdExact = 630061;
  static const int _alarmIdInexact = 630062;
  static const Duration _interval = Duration(minutes: 1);
  static bool _initialized = false;
  static const String _wdCountKey = 'bg_watchdog_rx_count';
  static const String _wdAtKey = 'bg_watchdog_last_at';
  static const String _wdStatusKey = 'bg_watchdog_last_status';
  static const String _wdErrorKey = 'bg_watchdog_last_error';
  static const String _wdScheduleKey = 'bg_watchdog_schedule_mode';

  static bool get _isSupported => !kIsWeb && Platform.isAndroid;

  static Future<bool> initializeAndSchedule() async {
    if (!_isSupported) return false;

    try {
      if (!_initialized) {
        await AndroidAlarmManager.initialize();
        _initialized = true;
      }

      await AndroidAlarmManager.cancel(_alarmIdExact);
      await AndroidAlarmManager.cancel(_alarmIdInexact);
      final startAt = DateTime.now().add(const Duration(seconds: 20));

      var exactScheduled = false;
      try {
        exactScheduled = await AndroidAlarmManager.periodic(
          _interval,
          _alarmIdExact,
          sccpAlarmWatchdogCallback,
          startAt: startAt,
          wakeup: true,
          rescheduleOnReboot: true,
          allowWhileIdle: true,
          exact: true,
        );
      } catch (_) {
        exactScheduled = false;
      }

      final inexactScheduled = await AndroidAlarmManager.periodic(
        _interval,
        _alarmIdInexact,
        sccpAlarmWatchdogCallback,
        startAt: startAt,
        wakeup: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
        exact: false,
      );
      await _recordScheduleMode(
        exactScheduled: exactScheduled,
        inexactScheduled: inexactScheduled,
      );
      return exactScheduled || inexactScheduled;
    } catch (_) {
      await _recordScheduleMode(exactScheduled: false, inexactScheduled: false);
      return false;
    }
  }

  static Future<void> cancel() async {
    if (!_isSupported || !_initialized) return;
    await AndroidAlarmManager.cancel(_alarmIdExact);
    await AndroidAlarmManager.cancel(_alarmIdInexact);
  }

  static Future<void> _recordScheduleMode({
    required bool exactScheduled,
    required bool inexactScheduled,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode =
          'EXACT:${exactScheduled ? 'ON' : 'OFF'}|INEXACT:${inexactScheduled ? 'ON' : 'OFF'}';
      await prefs.setString(_wdScheduleKey, mode);
    } catch (_) {
      // Silencioso
    }
  }

  static Future<void> _recordWatchdogTick({
    required String status,
    String? error,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_wdCountKey) ?? 0;
      await prefs.setInt(_wdCountKey, current + 1);
      await prefs.setString(_wdAtKey, DateTime.now().toUtc().toIso8601String());
      await prefs.setString(_wdStatusKey, status);
      if (error != null && error.trim().isNotEmpty) {
        final trimmed = error.trim();
        await prefs.setString(
          _wdErrorKey,
          trimmed.length > 180 ? trimmed.substring(0, 180) : trimmed,
        );
      } else {
        await prefs.remove(_wdErrorKey);
      }
    } catch (_) {
      // Silencioso
    }
  }
}
