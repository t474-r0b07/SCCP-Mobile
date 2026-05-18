import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/voice_match_utils.dart';
import '../../data/services/voice_biometric_service.dart';
import '../../data/services/voice_recorder_service.dart';
import '../../data/services/android_system_service.dart';
import '../../data/services/security_storage_service.dart';
import '../providers/auth_provider.dart';
import '../widgets/huc_background.dart';
import '../widgets/hud_screen_entry.dart';

class FirstAccessOnboardingScreen extends StatefulWidget {
  const FirstAccessOnboardingScreen({super.key});

  @override
  State<FirstAccessOnboardingScreen> createState() =>
      _FirstAccessOnboardingScreenState();
}

class _FirstAccessOnboardingScreenState
    extends State<FirstAccessOnboardingScreen> {
  int _step = 0;
  bool _isSubmitting = false;
  bool _checkingPermissions = false;
  bool _initializingSpeech = false;
  bool _isListening = false;
  bool _speechReady = false;
  String? _voiceCode;
  String _recognizedText = '';
  double _similarity = 0;
  bool _isCapturingBiometric = false;
  final List<List<double>> _biometricSamples = <List<double>>[];
  double _lastBiometricQuality = 0;
  String _biometricStatus = 'Pendiente';
  final SpeechToText _speech = SpeechToText();

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapVoiceCode());
  }

  Future<void> _initSpeech() async {
    if (_speechReady || _initializingSpeech) return;
    _initializingSpeech = true;
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          final listening = status == 'listening';
          if (!mounted) return;
          if (_isListening != listening) {
            setState(() => _isListening = listening);
          }
        },
      );
      if (mounted) {
        setState(() => _speechReady = ready);
      }
    } finally {
      _initializingSpeech = false;
    }
  }

  @override
  void dispose() {
    _speech.stop();
    VoiceRecorderService.stopIfRecording();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();

    return Scaffold(
      body: HucBackground(
        child: SafeArea(
          child: HudScreenEntry(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    child: _step == 0
                        ? _buildPermissionsStep(context)
                        : _buildVoiceStep(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsStep(BuildContext context) {
    return GlassPanel(
      key: const ValueKey('permissions_step'),
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONFIGURACION INICIAL',
            style: TextStyle(
              fontFamily: 'Orbitron',
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Primera instalación detectada. Debes conceder permisos para monitoreo y certificación de identidad.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          const _PermissionItem(
            icon: Icons.location_on_outlined,
            title: 'Ubicación precisa y en segundo plano',
          ),
          const _PermissionItem(
            icon: Icons.gps_fixed,
            title: 'GPS del dispositivo encendido',
          ),
          const _PermissionItem(
            icon: Icons.notifications_active_outlined,
            title: 'Notificaciones operativas',
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            const _PermissionItem(
              icon: Icons.bluetooth_searching_rounded,
              title: 'Escaneo Bluetooth (huella ambiental)',
            ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            const _PermissionItem(
              icon: Icons.devices_other_outlined,
              title: 'Dispositivos cercanos (audio de radio)',
            ),
          const _PermissionItem(
            icon: Icons.mic_none_outlined,
            title: 'Micrófono para certificación de voz',
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            const _PermissionItem(
              icon: Icons.battery_charging_full_outlined,
              title: 'Batería sin optimización para segundo plano',
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _checkingPermissions ? null : _requestPermissionsAndContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _checkingPermissions ? 'VERIFICANDO...' : 'CONCEDER PERMISOS',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: Geolocator.openLocationSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text('ACTIVAR GPS'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: openAppSettings,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Text('AJUSTES APP'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceStep(BuildContext context) {
    return GlassPanel(
      key: const ValueKey('voice_step'),
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CERTIFICACION DE VOZ',
            style: TextStyle(
              fontFamily: 'Orbitron',
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Lee el codigo de forma clara usando las palabras mostradas. Esto mejora la validacion de voz.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.black.withValues(alpha: 0.28),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
            ),
            child: Text(
              _voiceCode ?? '--',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Orbitron',
                color: AppTheme.primary,
                fontSize: 24,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'ID asociado: ${context.read<AuthProvider>().oficial?.id ?? '--'}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.black.withValues(alpha: 0.22),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.26)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening ? AppTheme.success : AppTheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isListening ? 'MICROFONO ACTIVO' : 'MICROFONO EN ESPERA',
                      style: TextStyle(
                        fontFamily: 'Orbitron',
                        color:
                            _isListening ? AppTheme.success : AppTheme.primary,
                        fontSize: 11,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Puedes hablar con calma. Tiempo de captura: hasta 18 segundos.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _recognizedText.isEmpty
                      ? 'Sin captura de voz.'
                      : 'Reconocido: $_recognizedText',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Similitud: ${(_similarity * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: _similarity >= 0.66
                        ? AppTheme.success
                        : Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: !_speechReady
                            ? null
                            : (_isListening ? _stopListening : _startListening),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              _isListening ? AppTheme.error : AppTheme.primary,
                          side: BorderSide(
                            color: (_isListening
                                    ? AppTheme.error
                                    : AppTheme.primary)
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        icon: Icon(_isListening ? Icons.stop : Icons.mic),
                        label: Text(_isListening
                            ? 'DETENER CAPTURA'
                            : 'INICIAR CAPTURA'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.black.withValues(alpha: 0.22),
              border: Border.all(
                color: (_biometricReady ? AppTheme.success : AppTheme.primary)
                    .withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HUELLA BIOMETRICA: ${_biometricSamples.length}/3',
                  style: TextStyle(
                    fontFamily: 'Orbitron',
                    color:
                        _biometricReady ? AppTheme.success : AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Estado: $_biometricStatus | Calidad: ${(_lastBiometricQuality * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isCapturingBiometric || _biometricReady
                            ? null
                            : _captureBiometricSample,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: BorderSide(
                            color: AppTheme.primary.withValues(alpha: 0.45),
                          ),
                        ),
                        icon: Icon(
                          _isCapturingBiometric
                              ? Icons.graphic_eq_rounded
                              : Icons.fingerprint_rounded,
                        ),
                        label: Text(
                          _isCapturingBiometric
                              ? 'CAPTURANDO...'
                              : 'CAPTURAR MUESTRA',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isCapturingBiometric
                            ? null
                            : () {
                                setState(() {
                                  _biometricSamples.clear();
                                  _lastBiometricQuality = 0;
                                  _biometricStatus = 'Reiniciado';
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.85),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Text('REINICIAR'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting || !_voiceValidated
                  ? null
                  : _finishVoiceEnrollment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isSubmitting ? 'REGISTRANDO...' : 'FINALIZAR CERTIFICACION',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermissionsAndContinue() async {
    if (_checkingPermissions) return;
    setState(() => _checkingPermissions = true);

    try {
      await _setOnboardingDiag('START_REQUEST_PERMISSIONS');
      final isAndroid =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final permissions = <_GuidedPermissionStep>[
        _GuidedPermissionStep(
          permission: Permission.location,
          title: isAndroid
              ? 'PERMISO 1/7: UBICACION PRECISA'
              : 'PERMISO 1/4: UBICACION PRECISA',
          instruction:
              'En la siguiente pantalla debes elegir "Permitir". Esto habilita el posicionamiento operativo.',
          requiredSelectionHint: 'Seleccion requerida: Permitir',
        ),
        _GuidedPermissionStep(
          permission: Permission.locationAlways,
          title: isAndroid
              ? 'PERMISO 2/7: UBICACION EN SEGUNDO PLANO'
              : 'PERMISO 2/4: UBICACION EN SEGUNDO PLANO',
          instruction:
              'Debes elegir "Permitir todo el tiempo". Si seleccionas otra opcion, el monitoreo se detiene al minimizar la app.',
          requiredSelectionHint: 'Seleccion requerida: Permitir todo el tiempo',
        ),
        if (isAndroid)
          const _GuidedPermissionStep(
            permission: Permission.bluetoothScan,
            title: 'PERMISO 3/7: ESCANEO BLUETOOTH',
            instruction:
                'Debes aceptar para levantar huella ambiental de dispositivos cercanos.',
            requiredSelectionHint: 'Seleccion requerida: Permitir',
          ),
        if (isAndroid)
          const _GuidedPermissionStep(
            permission: Permission.bluetoothConnect,
            title: 'PERMISO 4/7: DISPOSITIVOS CERCANOS',
            instruction:
                'Debes aceptar para habilitar audio de radio y conexión con dispositivos cercanos.',
            requiredSelectionHint: 'Seleccion requerida: Permitir',
          ),
        _GuidedPermissionStep(
          permission: Permission.notification,
          title: isAndroid
              ? 'PERMISO 5/7: NOTIFICACIONES'
              : 'PERMISO 3/4: NOTIFICACIONES',
          instruction:
              'Debes aceptar para recibir partes obligatorios y alertas de control.',
          requiredSelectionHint: 'Seleccion requerida: Permitir',
        ),
        _GuidedPermissionStep(
          permission: Permission.microphone,
          title:
              isAndroid ? 'PERMISO 6/7: MICROFONO' : 'PERMISO 4/4: MICROFONO',
          instruction:
              'Debes aceptar para registro de voz y validacion de partes oficiales.',
          requiredSelectionHint: 'Seleccion requerida: Permitir',
        ),
      ];

      for (final step in permissions) {
        final stepId = step.permission.toString().replaceAll('Permission.', '');
        await _setOnboardingDiag('REQUEST_$stepId');
        final ok = await _requestGuidedPermission(step);
        if (!ok) {
          await _setOnboardingDiag('DENIED_$stepId');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Permiso obligatorio no concedido. No puedes continuar.'),
            ),
          );
          return;
        }
      }

      if (isAndroid) {
        await _setOnboardingDiag('REQUEST_IGNORE_BATTERY');
        final ignoreBattery = await _requestGuidedPermission(
          const _GuidedPermissionStep(
            permission: Permission.ignoreBatteryOptimizations,
            title: 'PERMISO 7/7: BATERIA (ANDROID)',
            instruction:
                'Debes permitir que SCCP ignore optimizacion de bateria para mantener reportes de fondo estables.',
            requiredSelectionHint:
                'Seleccion requerida: Permitir / No optimizar',
          ),
        );

        if (!ignoreBattery) {
          await _setOnboardingDiag('DENIED_IGNORE_BATTERY');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sin permiso de bateria la app puede perder reportes en segundo plano.',
              ),
            ),
          );
          return;
        }

        final dataRestricted =
            await AndroidSystemService.isBackgroundDataRestricted();
        if (dataRestricted) {
          await _setOnboardingDiag('DATA_RESTRICTED_WARN');
          if (!mounted) return;
          final openDataSettings = await _showMandatoryDialog(
            title: 'ADVERTENCIA DATOS DE FONDO',
            message:
                'El sistema reporta posible restricción de datos en segundo plano.\n\nEn varios modelos este ajuste no existe por aplicación. Puedes continuar y probar operación real.',
            confirmLabel: 'ABRIR AJUSTES',
            cancelLabel: 'CONTINUAR',
          );
          if (openDataSettings) {
            await AndroidSystemService.openDataUsageSettings();
            await Future<void>.delayed(const Duration(milliseconds: 700));
          }
        }
      }

      final gpsReady = await _ensureGpsEnabledGuided();
      if (!gpsReady) {
        await _setOnboardingDiag('GPS_NOT_READY');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'GPS obligatorio apagado. Activalo para continuar.',
            ),
          ),
        );
        return;
      }

      if (!mounted) return;
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.needsVoiceEnrollment) {
        await _setOnboardingDiag('COMPLETE_PERMISSIONS_SETUP');
        await authProvider.completePermissionsSetup();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permisos validados. Operación habilitada.'),
          ),
        );
        return;
      }

      setState(() => _step = 1);
      await _setOnboardingDiag('STEP_VOICE_ENROLLMENT');
      await _initSpeech();
    } catch (e) {
      await _setOnboardingDiag('ERROR_${e.runtimeType}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error validando permisos. Reabre la app y vuelve a intentar.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checkingPermissions = false);
      }
    }
  }

  Future<void> _bootstrapVoiceCode() async {
    final existing = await SecurityStorageService.readVoiceProfileCode();
    if (!mounted) return;
    setState(() {
      _voiceCode = (existing != null && existing.trim().isNotEmpty)
          ? existing.trim()
          : _generateVoiceCode();
    });
  }

  Future<bool> _requestGuidedPermission(_GuidedPermissionStep step) async {
    try {
      if (!mounted) return false;

      final alreadyGranted = await step.permission.isGranted;
      if (alreadyGranted) return true;
      final forceSettingsFlow =
          step.permission == Permission.ignoreBatteryOptimizations;

      final acceptedInstruction = await _showMandatoryDialog(
        title: step.title,
        message:
            '${step.instruction}\n\n${step.requiredSelectionHint}\n\nSi no aceptas, no podras usar la app.',
        confirmLabel: 'ENTENDIDO',
        cancelLabel: 'CANCELAR',
      );
      if (!acceptedInstruction) return false;

      var status = await step.permission.request();
      while (!status.isGranted) {
        if (!mounted) return false;

        final goSettingsOrRetry = await _showMandatoryDialog(
          title: 'PERMISO REQUERIDO',
          message:
              '${step.requiredSelectionHint}\n\nEste permiso es obligatorio para operar.',
          confirmLabel: (status.isPermanentlyDenied || forceSettingsFlow)
              ? 'ABRIR AJUSTES'
              : 'REINTENTAR',
          cancelLabel: 'CANCELAR',
        );
        if (!goSettingsOrRetry) return false;

        if (status.isPermanentlyDenied ||
            status.isRestricted ||
            forceSettingsFlow) {
          if (forceSettingsFlow) {
            await AndroidSystemService.requestIgnoreBatteryOptimizations();
            await Future<void>.delayed(const Duration(milliseconds: 900));
            status = await step.permission.status;
            final whitelisted =
                await AndroidSystemService.isIgnoringBatteryOptimizations();
            if (whitelisted) return true;
            await AndroidSystemService.openIgnoreBatteryOptimizationSettings();
            await Future<void>.delayed(const Duration(milliseconds: 900));
            status = await step.permission.status;
          } else {
            await openAppSettings();
            await Future<void>.delayed(const Duration(milliseconds: 700));
            status = await step.permission.status;
          }
        } else {
          status = await step.permission.request();
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _setOnboardingDiag(String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('onboarding_diag_status', status);
      await prefs.setString(
        'onboarding_diag_at',
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Silencioso
    }
  }

  Future<bool> _ensureGpsEnabledGuided() async {
    if (!mounted) return false;
    while (mounted) {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) return true;

      final openGps = await _showMandatoryDialog(
        title: 'GPS OBLIGATORIO',
        message:
            'Debes encender el GPS del dispositivo para continuar. Sin GPS no hay control operativo.',
        confirmLabel: 'ABRIR GPS',
        cancelLabel: 'CANCELAR',
      );

      if (!openGps) return false;
      await Geolocator.openLocationSettings();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<bool> _showMandatoryDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121A27),
          title: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Orbitron',
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                cancelLabel,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
              ),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _finishVoiceEnrollment() async {
    if (_voiceCode == null || _voiceCode!.isEmpty || !_biometricReady) return;
    final authProvider = context.read<AuthProvider>();
    await _stopListening();
    if (!mounted) return;

    setState(() => _isSubmitting = true);
    final biometricEmbedding =
        VoiceBiometricService.averageEmbeddings(_biometricSamples);
    if (biometricEmbedding == null || biometricEmbedding.isEmpty) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo consolidar la huella biometrica.'),
        ),
      );
      return;
    }

    final ok = await authProvider.completeVoiceEnrollment(
      _voiceCode!,
      biometricEmbedding: biometricEmbedding,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!ok) {
      final reason = authProvider.errorMessage?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (reason != null && reason.isNotEmpty)
                ? reason
                : 'No se pudo completar el registro vocal.',
          ),
        ),
      );
    }
  }

  bool get _biometricReady => _biometricSamples.length >= 3;

  bool get _voiceValidated =>
      _recognizedText.isNotEmpty && _similarity >= 0.66 && _biometricReady;

  Future<void> _startListening() async {
    if (!_speechReady || _isListening || _voiceCode == null) return;
    final expected = _voiceCode!;
    setState(() {
      _recognizedText = '';
      _similarity = 0;
      _isListening = true;
    });

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 18),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(partialResults: true),
        onResult: (result) {
          final words = result.recognizedWords.trim();
          final similarity = VoiceMatchUtils.similarity(words, expected);
          if (!mounted) return;
          setState(() {
            _recognizedText = words;
            _similarity = similarity;
          });
        },
        onSoundLevelChange: (_) {},
        localeId: 'es_ES',
      );
    } catch (_) {
      await _speech.listen(
        listenFor: const Duration(seconds: 18),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(partialResults: true),
        onResult: (result) {
          final words = result.recognizedWords.trim();
          final similarity = VoiceMatchUtils.similarity(words, expected);
          if (!mounted) return;
          setState(() {
            _recognizedText = words;
            _similarity = similarity;
          });
        },
      );
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;
    await _speech.stop();
    if (!mounted) return;
    setState(() => _isListening = false);
  }

  Future<void> _captureBiometricSample() async {
    if (_isCapturingBiometric || _biometricReady) return;
    setState(() {
      _isCapturingBiometric = true;
      _biometricStatus = 'Grabando muestra ${_biometricSamples.length + 1}/3';
    });

    try {
      final path = await VoiceRecorderService.captureWavSample(
        duration: const Duration(seconds: 4),
      );
      if (path == null) {
        if (!mounted) return;
        setState(() {
          _biometricStatus = 'Microfono no disponible para captura';
        });
        return;
      }

      final extract =
          await VoiceBiometricService.extractEmbeddingFromWavFile(path);
      if (!extract.ok || extract.embedding == null) {
        if (!mounted) return;
        setState(() {
          _lastBiometricQuality = extract.quality;
          _biometricStatus = extract.message;
        });
        return;
      }

      if (_biometricSamples.isNotEmpty) {
        final reference =
            VoiceBiometricService.averageEmbeddings(_biometricSamples);
        if (reference != null) {
          final consistency = VoiceBiometricService.cosineSimilarity(
            extract.embedding!,
            reference,
          );
          if (consistency < 0.78) {
            if (!mounted) return;
            setState(() {
              _lastBiometricQuality = extract.quality;
              _biometricStatus =
                  'Muestra inconsistente. Repite con voz natural.';
            });
            return;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _biometricSamples.add(extract.embedding!);
        _lastBiometricQuality = extract.quality;
        _biometricStatus = _biometricReady
            ? 'Huella biometrica lista'
            : 'Muestra ${_biometricSamples.length}/3 registrada';
      });
      try {
        await File(path).delete();
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _isCapturingBiometric = false);
      }
    }
  }

  String _generateVoiceCode() {
    return 'OFICIAL ACTIVO CUSTODIA DOMICILIARIA SIN NOVEDAD';
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PermissionItem({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuidedPermissionStep {
  final Permission permission;
  final String title;
  final String instruction;
  final String requiredSelectionHint;

  const _GuidedPermissionStep({
    required this.permission,
    required this.title,
    required this.instruction,
    required this.requiredSelectionHint,
  });
}
