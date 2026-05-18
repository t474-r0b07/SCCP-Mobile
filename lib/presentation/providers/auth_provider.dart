import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/supabase_repository.dart';
import '../../data/services/background_service.dart';
import '../../data/services/alarm_watchdog_service.dart';
import '../../data/services/android_system_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/security_storage_service.dart';
import '../../data/models/oficial_model.dart';
import '../../data/models/reo_model.dart';
import '../../core/constants/review_flags.dart';
import '../../core/utils/device_identity_utils.dart';
import '../../core/utils/shift_utils.dart';

class AuthProvider with ChangeNotifier {
  final SupabaseRepository _repository = SupabaseRepository();
  static const Duration _activeSessionStaleAfter = Duration(seconds: 90);
  static const String _operationalReadyKey = 'operational_ready';

  OficialModel? _oficial;
  ReoModel? _reoAsignado;
  bool _isLoading = false;
  bool _requiresOnboarding = false;
  bool _needsVoiceEnrollment = false;
  bool _isOnShift = true;
  Duration? _timeToNextShift;
  String? _errorMessage;
  String? _deviceId;
  Timer? _shiftTimer;
  Timer? _heartbeatTimer;
  DateTime? _sessionOpenedAt;

  OficialModel? get oficial => _oficial;
  ReoModel? get reoAsignado => _reoAsignado;
  bool get isLoading => _isLoading;
  bool get requiresOnboarding =>
      !ReviewFlags.skipPermissionsAndVoiceInWeb &&
      !kIsWeb &&
      _requiresOnboarding;
  bool get needsVoiceEnrollment => _needsVoiceEnrollment;
  bool get isOnShift => _isOnShift;
  Duration? get timeToNextShift => _timeToNextShift;
  String? get deviceId => _deviceId;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _oficial != null;
  bool get canAccessOperations =>
      isAuthenticated && !_requiresOnboarding && _isOnShift;

  Future<({bool ok, String message})> validateOperationalPrerequisites() async {
    if (kIsWeb) return (ok: true, message: '');

    final gpsEnabled = await Geolocator.isLocationServiceEnabled();
    if (!gpsEnabled) {
      return (
        ok: false,
        message: 'GPS desactivado. Activa ubicación para operar.'
      );
    }

    final locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.deniedForever) {
      return (
        ok: false,
        message: 'Permiso de ubicación no concedido. Debe estar habilitado.'
      );
    }

    if (locationPermission != LocationPermission.always) {
      return (
        ok: false,
        message:
            'Ubicación en segundo plano no habilitada. Selecciona "Permitir todo el tiempo".'
      );
    }

    final notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      return (
        ok: false,
        message: 'Notificaciones desactivadas. Deben estar habilitadas.'
      );
    }

    final microphoneStatus = await Permission.microphone.status;
    if (!microphoneStatus.isGranted) {
      return (
        ok: false,
        message: 'Micrófono desactivado. Debe estar habilitado.'
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final btScanStatus = await Permission.bluetoothScan.status;
      if (!btScanStatus.isGranted) {
        return (
          ok: false,
          message:
              'Escaneo Bluetooth desactivado. Debes habilitarlo para evidencia ambiental.'
        );
      }

      final nearbyStatus = await Permission.bluetoothConnect.status;
      if (!nearbyStatus.isGranted) {
        return (
          ok: false,
          message:
              'Dispositivos cercanos desactivado. Debes habilitarlo para radio y audio.'
        );
      }

      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      final ignoringBattery = batteryStatus.isGranted ||
          await AndroidSystemService.isIgnoringBatteryOptimizations();
      if (!ignoringBattery) {
        return (
          ok: false,
          message:
              'Optimización de batería activa. Debes permitir "No optimizar" para SCCP.'
        );
      }

      final restrictedBackgroundData =
          await AndroidSystemService.isBackgroundDataRestricted();
      if (restrictedBackgroundData) {
        // En algunos fabricantes no existe ajuste por-app de datos de fondo.
        // Se registra como advertencia, pero no bloquea el acceso operativo.
        debugPrint('SCCP warning: background data reported as restricted.');
      }
    }

    return (ok: true, message: '');
  }

  Future<bool> enforceOperationalPrerequisites() async {
    final readiness = await validateOperationalPrerequisites();
    if (readiness.ok) {
      if (_requiresOnboarding && !_needsVoiceEnrollment) {
        _requiresOnboarding = false;
        _errorMessage = null;
        await _setOperationalReadyFlag(true);
        // El arranque operativo se hace desde HomeScreen para evitar dobles
        // inicializaciones al volver de dialogs de permisos.
        notifyListeners();
      }
      return true;
    }

    _requiresOnboarding = true;
    _errorMessage = readiness.message;
    await _setOperationalReadyFlag(false);
    await _closeOperationalSession(status: 'permissions_missing');
    notifyListeners();
    return false;
  }

  Future<void> completePermissionsSetup() async {
    _requiresOnboarding = _needsVoiceEnrollment;
    _errorMessage = null;
    // El stack operativo se inicia desde HomeScreen al entrar a operación.
    // Evita arrancar servicios durante la transición de permisos/onboarding.
    await _setOperationalReadyFlag(!_requiresOnboarding);
    notifyListeners();
  }

  Future<bool> loginWithId(String idOficial) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final cleanId = idOficial.trim();
      _deviceId =
          (await DeviceIdentityUtils.getOrCreateDeviceIdentifier()).trim();
      final oficial = await _repository.getOficialById(cleanId);

      if (oficial == null) {
        return _finishWithError('ID de oficial no registrado');
      }

      if (!oficial.activo) {
        return _finishWithError('El oficial está inactivo');
      }

      final onShiftNow = ShiftUtils.isWithinShift(
        oficial.turno,
        grupo: oficial.grupo,
      );
      if (!onShiftNow) {
        return _finishWithError(
            _buildOffShiftMessage(oficial.grupo, oficial.turno));
      }

      final dbDevice = oficial.imei?.trim();
      final normalizedDbDevice = dbDevice?.toUpperCase();
      final normalizedCurrentDevice = _deviceId?.trim().toUpperCase();
      final hasRegisteredDevice = dbDevice != null && dbDevice.isNotEmpty;
      final isSameDevice = normalizedDbDevice != null &&
          normalizedDbDevice == normalizedCurrentDevice;

      if (hasRegisteredDevice && !isSameDevice) {
        return _finishWithError(
          'Este equipo no está autorizado para ese oficial',
        );
      }

      final activeSession = await _repository.getActiveOperationalSession(
        oficial.id,
      );
      final activeDeviceId =
          activeSession?['device_id']?.toString().trim().toUpperCase();
      if (activeSession != null &&
          activeDeviceId != null &&
          activeDeviceId.isNotEmpty &&
          activeDeviceId != normalizedCurrentDevice) {
        final stale = _isStaleOperationalSession(activeSession);
        if (!stale) {
          return _finishWithError(
            'El oficial ya tiene una sesión activa en otro dispositivo. '
            'Si la app fue cerrada o desinstalada, espera ~2 minutos y vuelve a intentar.',
          );
        }
      }

      final isFirstAccess = !hasRegisteredDevice;
      if (isFirstAccess && normalizedCurrentDevice != null) {
        await _repository.registerDeviceToOficial(
          idOficial: oficial.id,
          deviceId: normalizedCurrentDevice,
        );
      }

      _oficial = oficial.copyWith(
        imei:
            hasRegisteredDevice ? normalizedDbDevice : normalizedCurrentDevice,
      );
      _reoAsignado = null;

      if (_oficial?.reoAsignado != null) {
        _reoAsignado = await _repository.getReoBycodigo(_oficial!.reoAsignado!);
      }

      final voiceProfile = await _repository.getVoiceProfileData(_oficial!.id);
      final voiceCode = voiceProfile.voiceCode;
      final hasVoiceCode = voiceCode != null && voiceCode.isNotEmpty;
      final localVoiceCode =
          await SecurityStorageService.readVoiceProfileCode();
      final hasLocalVoiceCode =
          localVoiceCode != null && localVoiceCode.isNotEmpty;
      final effectiveVoiceCode = hasVoiceCode
          ? voiceCode
          : (hasLocalVoiceCode ? localVoiceCode : null);
      final localBiometricProfile =
          await SecurityStorageService.readVoiceBiometricProfile();
      final hasLocalBiometricProfile =
          localBiometricProfile != null && localBiometricProfile.isNotEmpty;
      final remoteEmbedding = voiceProfile.biometricEmbedding;
      final hasRemoteBiometricProfile =
          remoteEmbedding != null && remoteEmbedding.isNotEmpty;
      final hasAnyBiometricProfile =
          hasLocalBiometricProfile || hasRemoteBiometricProfile;
      if (!hasLocalBiometricProfile &&
          remoteEmbedding != null &&
          remoteEmbedding.isNotEmpty) {
        await SecurityStorageService.writeVoiceBiometricProfile(
          remoteEmbedding,
        );
      }
      // Regla de seguridad:
      // - Si YA existe codigo de voz en servidor, no forzar re-registro por reinstalacion.
      // - Solo forzar onboarding vocal cuando el oficial aun no tiene perfil remoto.
      // - Si NO es primer acceso y no hay perfil remoto/local, bloquear (evita bypass por reinstalar).
      if (!kIsWeb && !hasVoiceCode && !hasLocalVoiceCode && !isFirstAccess) {
        return _finishWithError(
          'Perfil de voz no disponible. Bloqueado por seguridad: contacta al supervisor para restaurar biometria.',
        );
      }
      _needsVoiceEnrollment =
          !kIsWeb && (!hasVoiceCode || !hasAnyBiometricProfile);
      final readiness = await validateOperationalPrerequisites();
      _requiresOnboarding = ReviewFlags.skipPermissionsAndVoiceInWeb
          ? false
          : !kIsWeb &&
              (isFirstAccess || _needsVoiceEnrollment || !readiness.ok);
      if (!readiness.ok) {
        _errorMessage = readiness.message;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_device_id', normalizedCurrentDevice ?? '');
      await prefs.setString('user_imei', normalizedCurrentDevice ?? '');
      await prefs.setString('user_id', _oficial!.id);
      await prefs.setString('user_name', _oficial!.nombre);
      await prefs.setString('user_grupo', _oficial!.grupo);
      if (_oficial!.turno != null && _oficial!.turno!.isNotEmpty) {
        await prefs.setString('user_shift', _oficial!.turno!);
      }
      if (_oficial!.reoAsignado != null) {
        await prefs.setString('reo_asignado', _oficial!.reoAsignado!);
      }
      if (effectiveVoiceCode != null && effectiveVoiceCode.isNotEmpty) {
        await prefs.setString('voice_profile_code', effectiveVoiceCode);
        await SecurityStorageService.writeVoiceProfileCode(effectiveVoiceCode);
      }
      await prefs.setBool(_operationalReadyKey, !_requiresOnboarding);

      _startShiftWatcher();
      _updateShiftState();
      await NotificationService.cancelShiftActivationReminder();
      if (!kIsWeb) {
        final source = _requiresOnboarding
            ? 'auth_login_onboarding_pending'
            : 'auth_login_ready';
        final didLog = await _repository.registerOfficialLoginAudit(
          idOficial: _oficial!.id,
          nombreOficial: _oficial!.nombre,
          deviceId: normalizedCurrentDevice ?? _deviceId ?? '',
          source: source,
        );
        if (!didLog) {
          debugPrint(
            '⚠️ [AUTH] login audit no registrado para ${_oficial!.id}',
          );
        }
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      return _finishWithError('Error de conexión con Supabase');
    }
  }

  Future<bool> completeVoiceEnrollment(
    String voiceCode, {
    required List<double> biometricEmbedding,
  }) async {
    if (_oficial == null) {
      return false;
    }

    try {
      final saved = await _repository.saveVoiceProfileCode(
        idOficial: _oficial!.id,
        voiceCode: voiceCode,
        biometricEmbedding: biometricEmbedding,
      );
      if (!saved) {
        _errorMessage =
            'No se pudo guardar el perfil de voz de forma segura. '
            'Contacta al supervisor para habilitar RPC segura de biometria.';
        notifyListeners();
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('voice_profile_code', voiceCode);
      await SecurityStorageService.writeVoiceProfileCode(voiceCode);
      await SecurityStorageService.writeVoiceBiometricProfile(
        biometricEmbedding,
      );
      _errorMessage = null;
      _needsVoiceEnrollment = false;
      _requiresOnboarding = false;
      // El stack operativo se inicia desde HomeScreen al completar onboarding.
      await _setOperationalReadyFlag(true);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString('user_id');
      if (savedId != null && savedId.isNotEmpty) {
        await loginWithId(savedId);
        return;
      }

      final deviceId = await DeviceIdentityUtils.getOrCreateDeviceIdentifier();
      final officialFromDevice =
          await _repository.getOficialByDeviceId(deviceId);
      if (officialFromDevice != null) {
        await loginWithId(officialFromDevice.id);
      }
    } catch (_) {
      // Silencioso
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final stableDeviceId = prefs.getString('device_identifier');
    await _closeOperationalSession(status: 'logout');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_grupo');
    await prefs.remove('user_shift');
    await prefs.remove('user_device_id');
    await prefs.remove('user_imei');
    await prefs.remove('reo_asignado');
    await prefs.remove('voice_profile_code');
    await prefs.remove(_operationalReadyKey);
    await prefs.remove('bg_pending_reports');
    await prefs.remove('bg_session_owner_user');
    await prefs.remove('bg_off_shift_closed_user');
    await AlarmWatchdogService.cancel();
    await BackgroundServiceManager.stopServiceIfRunning();
    await prefs.clear();
    if (stableDeviceId != null && stableDeviceId.isNotEmpty) {
      await prefs.setString('device_identifier', stableDeviceId);
    }
    _shiftTimer?.cancel();
    _heartbeatTimer?.cancel();
    _oficial = null;
    _reoAsignado = null;
    _requiresOnboarding = false;
    _needsVoiceEnrollment = false;
    _isOnShift = true;
    _timeToNextShift = null;
    _errorMessage = null;
    _deviceId = null;
    _sessionOpenedAt = null;
    await SecurityStorageService.clearVoiceProfileCode();
    await SecurityStorageService.clearVoiceBiometricProfile();
    await NotificationService.cancelShiftActivationReminder();
    notifyListeners();
  }

  void _startShiftWatcher() {
    _shiftTimer?.cancel();
    _shiftTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateShiftState(),
    );
  }

  void _updateShiftState() {
    if (_oficial == null) {
      _isOnShift = true;
      _timeToNextShift = null;
      notifyListeners();
      return;
    }

    final wasOnShift = _isOnShift;
    _isOnShift = ShiftUtils.isWithinShift(
      _oficial!.turno,
      grupo: _oficial!.grupo,
    );
    _timeToNextShift = _isOnShift
        ? Duration.zero
        : ShiftUtils.timeUntilShiftStart(
            _oficial!.turno,
            grupo: _oficial!.grupo,
          );

    if (wasOnShift && !_isOnShift) {
      _errorMessage = _buildOffShiftMessage(_oficial!.grupo, _oficial!.turno);
      unawaited(_autoLogoutForShiftEnd());
      notifyListeners();
      return;
    } else if (!wasOnShift &&
        _isOnShift &&
        !kIsWeb &&
        !_requiresOnboarding) {
      _errorMessage = null;
      unawaited(NotificationService.cancelShiftActivationReminder());
      unawaited(_notifyShiftReactivation());
      unawaited(_startOperationalStackSafely(source: 'shift_resumed'));
    }
    notifyListeners();
  }

  void refreshShiftStateNow() {
    _updateShiftState();
  }

  bool _finishWithError(String message) {
    _errorMessage = message;
    _needsVoiceEnrollment = false;
    _isLoading = false;
    notifyListeners();
    return false;
  }

  String _buildOffShiftMessage(String grupo, String? turno) {
    final remaining = ShiftUtils.timeUntilShiftStart(
      turno,
      grupo: grupo,
    );
    final remainingLabel = remaining == null
        ? '--'
        : '${remaining.inHours.toString().padLeft(2, '0')}h '
            '${(remaining.inMinutes % 60).toString().padLeft(2, '0')}m';
    return 'Grupo ${grupo.toUpperCase()} en descanso. '
        'Monitoreo desactivado. '
        'Próximo turno en $remainingLabel.';
  }

  Future<void> _notifyShiftReactivation() async {
    final official = _oficial;
    if (official == null || kIsWeb) return;
    try {
      await NotificationService.showShiftActivationReminder(
        group: official.grupo,
        turno: official.turno,
      );
    } catch (_) {
      // Silencioso
    }
  }

  Future<void> _autoLogoutForShiftEnd() async {
    final official = _oficial;
    if (official == null) return;
    final group = official.grupo;
    final turno = official.turno;
    final remaining = ShiftUtils.timeUntilShiftStart(
      turno,
      grupo: group,
    );
    final reminderAt = (remaining != null && remaining > Duration.zero)
        ? DateTime.now().add(remaining)
        : null;

    final prefs = await SharedPreferences.getInstance();
    final stableDeviceId = prefs.getString('device_identifier');

    await _closeOperationalSession(status: 'off_shift');
    await AlarmWatchdogService.cancel();
    await BackgroundServiceManager.stopServiceIfRunning();

    await prefs.remove('user_id');
    await prefs.remove('user_name');
    await prefs.remove('user_grupo');
    await prefs.remove('user_shift');
    await prefs.remove('user_device_id');
    await prefs.remove('user_imei');
    await prefs.remove('reo_asignado');
    await prefs.remove(_operationalReadyKey);
    await prefs.remove('bg_pending_reports');
    await prefs.remove('bg_session_owner_user');
    await prefs.remove('bg_off_shift_closed_user');

    if (stableDeviceId != null && stableDeviceId.isNotEmpty) {
      await prefs.setString('device_identifier', stableDeviceId);
    }

    _shiftTimer?.cancel();
    _heartbeatTimer?.cancel();
    _oficial = null;
    _reoAsignado = null;
    _requiresOnboarding = false;
    _needsVoiceEnrollment = false;
    _isOnShift = true;
    _timeToNextShift = null;
    _errorMessage =
        'Turno finalizado. Debes iniciar sesión nuevamente al comenzar el próximo turno.';
    _deviceId = null;
    _sessionOpenedAt = null;

    await NotificationService.cancelShiftActivationReminder();
    if (!kIsWeb) {
      if (reminderAt != null && reminderAt.isAfter(DateTime.now())) {
        await NotificationService.scheduleShiftActivationReminder(
          reminderAt: reminderAt,
          group: group,
          turno: turno,
        );
      } else {
        await NotificationService.showShiftActivationReminder(
          group: group,
          turno: turno,
        );
      }
    }
    notifyListeners();
  }

  bool _isStaleOperationalSession(Map<String, dynamic> session) {
    final lastBeat = _parseSessionTimestamp(
      session['last_heartbeat'] ?? session['login_at'],
    );
    if (lastBeat == null) return true;
    final elapsed = DateTime.now().toUtc().difference(lastBeat.toUtc());
    return elapsed >= _activeSessionStaleAfter;
  }

  DateTime? _parseSessionTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  Future<void> _openOperationalSession() async {
    final official = _oficial;
    final deviceId = _deviceId;
    if (official == null || deviceId == null || deviceId.isEmpty) return;

    _sessionOpenedAt = DateTime.now();
    await _repository.openOperationalSession(
      idOficial: official.id,
      nombreOficial: official.nombre,
      deviceId: deviceId,
      recordLoginLog: true,
    );

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _sendHeartbeat(),
    );
    await _sendHeartbeat();
  }

  Future<void> _startOperationalStackSafely({required String source}) async {
    if (kIsWeb) return;
    try {
      if (_requiresOnboarding || _oficial == null) {
        return;
      }
      final readiness = await validateOperationalPrerequisites();
      if (!readiness.ok) {
        _errorMessage = readiness.message;
        await _setOperationalReadyFlag(false);
        notifyListeners();
        return;
      }

      await AlarmWatchdogService.initializeAndSchedule();
      await BackgroundServiceManager.ensureServiceRunning();
      await _openOperationalSession();
    } catch (e) {
      debugPrint(
        'SCCP warning [$source]: no se pudo iniciar stack operativo: $e',
      );
    }
  }

  Future<void> _sendHeartbeat() async {
    final official = _oficial;
    final deviceId = _deviceId;
    if (official == null || deviceId == null || deviceId.isEmpty) return;
    await _repository.heartbeatOperationalSession(
      idOficial: official.id,
      deviceId: deviceId,
    );
  }

  Future<void> _closeOperationalSession({required String status}) async {
    final official = _oficial;
    final deviceId = _deviceId;
    if (official == null || deviceId == null || deviceId.isEmpty) {
      _heartbeatTimer?.cancel();
      return;
    }

    _heartbeatTimer?.cancel();
    final start = _sessionOpenedAt;
    final duration = start == null
        ? 0
        : DateTime.now().difference(start).inMinutes.clamp(0, 1000000);
    await _repository.closeOperationalSession(
      idOficial: official.id,
      deviceId: deviceId,
      status: status,
      durationMinutes: duration,
    );
  }

  Future<void> _setOperationalReadyFlag(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_operationalReadyKey, value);
    } catch (_) {
      // Silencioso
    }
  }

  @override
  void dispose() {
    _shiftTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}
