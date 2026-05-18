import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/utils/parte_schedule_utils.dart';
import '../../core/utils/grado_assets.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/review_flags.dart';
import '../../core/utils/utc_time_utils.dart';
import '../../core/utils/voice_challenge_utils.dart';
import '../../core/utils/voice_match_utils.dart';
import '../../core/utils/pending_reports_queue_utils.dart';
import '../../data/repositories/supabase_repository.dart';
import '../../data/services/alarm_watchdog_service.dart';
import '../../data/services/background_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/security_storage_service.dart';
import '../../data/services/validation_hash_service.dart';
import '../../data/services/voice_biometric_service.dart';
import '../../data/services/voice_recorder_service.dart';
import '../providers/auth_provider.dart';
import '../providers/monitoring_provider.dart';
import '../providers/radio_provider.dart';
import '../widgets/huc_background.dart';
import '../widgets/hud_screen_entry.dart';
import 'hud_splash_screen.dart';
import 'map_screen.dart';
import 'radio_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final MonitoringProvider _monitoringProvider;
  late final RadioProvider _radioProvider;
  late final AnimationController _hudAnim;
  final SupabaseRepository _repository = SupabaseRepository();
  Timer? _parteWindowTimer;
  DateTime? _activeParteSlot;
  DateTime? _nextParteSlot;
  bool _parteWindowOpen = false;
  String _bgDiagStatus = '--';
  String _bgDiagAt = '--';
  String _bgDiagError = '--';
  int _bgPendingReports = 0;
  List<Map<String, dynamic>> _bgDiagHistory = const [];
  String _bgNativeRxAt = '--';
  String _bgNativeAction = '--';
  int _bgNativeRxCount = 0;
  String _bgNativeStartStatus = '--';
  String _bgNativeNextAt = '--';
  String _bgNativeScheduleMode = '--';
  int _bgWatchdogRxCount = 0;
  String _bgWatchdogAt = '--';
  String _bgWatchdogStatus = '--';
  String _bgWatchdogSchedule = '--';
  String _bgWatchdogError = '--';
  bool _handlingNotificationAction = false;
  bool _showingParteSorpresaDialog = false;
  DateTime? _lastOperationalSnapshotAt;
  StreamSubscription<Map<String, String>>? _notificationActionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hudAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    final auth = context.read<AuthProvider>();
    _monitoringProvider = context.read<MonitoringProvider>();
    _radioProvider = context.read<RadioProvider>();

    if (auth.oficial != null) {
      _refreshParteWindowState();
      _parteWindowTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshParteWindowState(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 650), () async {
          if (!mounted) return;
          await _runGuarded('startup_operational_stack', () async {
            await _startOperationalStack(forceSnapshot: true);
          });
        });
        unawaited(_runGuarded('startup_pending_notification', () async {
          await _handlePendingNotificationAction();
        }));
      });
    }
    _notificationActionSub = NotificationService.actionEvents.listen((_) {
      unawaited(_runGuarded('stream_notification_action', () async {
        await _handlePendingNotificationAction();
      }));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hudAnim.dispose();
    _parteWindowTimer?.cancel();
    _notificationActionSub?.cancel();
    _monitoringProvider.stopMonitoring();
    _radioProvider.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (!auth.canAccessOperations) return;
      unawaited(_runGuarded('lifecycle_schedule_watchdog', () async {
        await AlarmWatchdogService.initializeAndSchedule();
      }));
      unawaited(_runGuarded('lifecycle_ensure_service', () async {
        await BackgroundServiceManager.ensureServiceRunning();
      }));
      unawaited(_runGuarded('lifecycle_snapshot', () async {
        await BackgroundServiceManager.runOperationalSnapshotNow();
      }));
    }
    if (state == AppLifecycleState.resumed) {
      auth.refreshShiftStateNow();
      if (!auth.canAccessOperations) {
        _monitoringProvider.stopMonitoring();
        _radioProvider.stop();
        return;
      }
      unawaited(_runGuarded('lifecycle_resume_watchdog', () async {
        await AlarmWatchdogService.initializeAndSchedule();
      }));
      unawaited(_runGuarded('lifecycle_resume_operational_stack', () async {
        await _startOperationalStack(
          forceReconnectRadio: true,
          forceSnapshot: true,
        );
      }));
      unawaited(_runGuarded('lifecycle_resume_notification', () async {
        await _handlePendingNotificationAction();
      }));
    }
  }

  Future<void> _startOperationalStack({
    bool forceReconnectRadio = false,
    bool forceSnapshot = false,
  }) async {
    try {
      final auth = context.read<AuthProvider>();
      auth.refreshShiftStateNow();
      if (!auth.canAccessOperations) return;
      final ok = await _enforceOperationalPrerequisites();
      if (!mounted || !ok) return;

      final officialId = auth.oficial?.id;
      if (officialId == null || officialId.isEmpty) return;

      await BackgroundServiceManager.ensureServiceRunning();
      await AlarmWatchdogService.initializeAndSchedule();
      _monitoringProvider.startMonitoring(
        officialId,
        reoCoordenadas: auth.reoAsignado?.coordenadas,
      );
      _radioProvider.start(officialId, forceReconnect: forceReconnectRadio);
      await _triggerOperationalSnapshot(force: forceSnapshot);
    } catch (e) {
      debugPrint('HomeScreen _startOperationalStack error: $e');
      if (mounted) {
        _showInfo(
          'Error operativo',
          'No se pudo iniciar el stack operativo. Reintenta en unos segundos.',
        );
      }
    }
  }

  Future<void> _triggerOperationalSnapshot({bool force = false}) async {
    try {
      final now = DateTime.now();
      if (!force && _lastOperationalSnapshotAt != null) {
        final elapsed = now.difference(_lastOperationalSnapshotAt!);
        if (elapsed < const Duration(minutes: 2)) {
          return;
        }
      }
      _lastOperationalSnapshotAt = now;
      await BackgroundServiceManager.runOperationalSnapshotNow(force: force);
    } catch (e) {
      debugPrint('HomeScreen _triggerOperationalSnapshot error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SCCP OPERATIVO'),
        actions: [
          IconButton(
            tooltip: 'Radio',
            icon: const Icon(Icons.settings_input_antenna_rounded),
            onPressed: _openRadio,
          ),
        ],
      ),
      body: HucBackground(
        child: SafeArea(
          child: HudScreenEntry(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildHeader(),
                      const SizedBox(height: 12),
                      _buildProfileSummary(),
                      const SizedBox(height: 12),
                      _buildMapCard(),
                      const SizedBox(height: 12),
                      _buildTelemetryAndAlerts(),
                      const SizedBox(height: 12),
                      _buildHudCharts(),
                      const SizedBox(height: 12),
                      _buildBodyCards(),
                      const SizedBox(height: 12),
                      _buildRadioCard(),
                      const SizedBox(height: 12),
                      _buildFooterButtons(),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return GlassPanel(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          ClipOval(
            child: Image.asset(
              'assets/images/logo.png',
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Consumer<AuthProvider>(
              builder: (context, auth, _) {
                final group = (auth.oficial?.grupo ?? '--').toUpperCase();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SISTEMA DE CONTROL POLICIAL',
                      style: TextStyle(
                        fontFamily: 'Orbitron',
                        color: AppTheme.primary,
                        fontSize: 12,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'GRUPO $group EN TURNO',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Consumer<MonitoringProvider>(
            builder: (context, monitoring, _) {
              final color = monitoring.alertStatus == 'NORMAL'
                  ? AppTheme.success
                  : AppTheme.error;
              final label =
                  monitoring.alertStatus == 'NORMAL' ? 'OPERATIVO' : 'ALERTA';
              return _chip(label, color);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSummary() {
    return Consumer3<AuthProvider, MonitoringProvider, RadioProvider>(
      builder: (context, auth, monitoring, radio, _) {
        final official = auth.oficial;
        final reo = auth.reoAsignado;
        final distance = monitoring.distanceToReo == null
            ? '--'
            : '${monitoring.distanceToReo!.toStringAsFixed(0)} m';
        final spectrumLevels =
            _buildHudSpectrumLevels(monitoring: monitoring, radio: radio);
        final coords = monitoring.currentPosition == null
            ? '--'
            : '${monitoring.currentPosition!.latitude.toStringAsFixed(4)}, ${monitoring.currentPosition!.longitude.toStringAsFixed(4)}';
        final jurisdiction = (official?.jurisdiccion ?? '').trim();
        final jurisdictionShort = jurisdiction.isEmpty
            ? '--'
            : (jurisdiction.length > 18
                ? '${jurisdiction.substring(0, 18)}...'
                : jurisdiction);

        return _tapPanel(
          onTap: () => _openProfileDetail(auth, monitoring, radio),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle('RESUMEN PERFIL'),
              const SizedBox(height: 8),
              Row(
                children: [
                  _gradeIcon(official?.grado),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          official?.nombre ?? 'Oficial',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'REO: ${reo?.nombre ?? official?.reoAsignado ?? 'N/D'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'COORD: $coords',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _chip('DIST $distance', AppTheme.primary),
                  _chip('REP ${monitoring.todayReportCount}', AppTheme.success),
                  _chip('ALT ${monitoring.todayAlertCount}', AppTheme.warning),
                  _chip('INC ${monitoring.todayInconsistencyCount}',
                      AppTheme.error),
                  _chip('RAD ${radio.unreadCount}', AppTheme.primary),
                  _chip('JUR ${jurisdictionShort.toUpperCase()}',
                      AppTheme.primary),
                ],
              ),
              const SizedBox(height: 9),
              AnimatedBuilder(
                animation: _hudAnim,
                builder: (context, _) {
                  return SizedBox(
                    width: double.infinity,
                    height: 74,
                    child: CustomPaint(
                      painter: _HudSpectrumPainter(
                        phase: _hudAnim.value,
                        color: AppTheme.primary,
                        levels: spectrumLevels,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapCard() {
    return Consumer2<AuthProvider, MonitoringProvider>(
      builder: (context, auth, monitoring, _) {
        return _tapPanel(
          onTap: _openMapOverlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle('MAPA: UBICACION + CASA CONTROL'),
              const SizedBox(height: 8),
              SizedBox(
                height: 188,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: _MiniMap(
                    officialLat: monitoring.currentPosition?.latitude,
                    officialLng: monitoring.currentPosition?.longitude,
                    controlCoords: auth.reoAsignado?.coordenadas,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Click: ventana de mapa casi completa (oficial, control, EPI y bases).',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontSize: 11.4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTelemetryAndAlerts() {
    return Consumer<MonitoringProvider>(
      builder: (context, monitoring, _) {
        final gpsColor =
            monitoring.isGpsActive ? AppTheme.success : AppTheme.error;
        final batColor =
            monitoring.batteryLevel > 20 ? AppTheme.success : AppTheme.warning;
        final critical = monitoring.alertStatus != 'NORMAL';
        final gpsPct = monitoring.isGpsActive ? 0.92 : 0.28;
        final batteryPct = (monitoring.batteryLevel / 100).clamp(0.0, 1.0);
        final alertPct = (monitoring.todayAlertCount / 10).clamp(0.0, 1.0);
        final incPct =
            (monitoring.todayInconsistencyCount / 10).clamp(0.0, 1.0);
        final distanceLabel = monitoring.distanceToReo == null
            ? 'N/D'
            : '${monitoring.distanceToReo!.toStringAsFixed(0)} m';

        return Row(
          children: [
            Expanded(
              child: GlassPanel(
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PanelTitle('TELEMETRIA'),
                    const SizedBox(height: 8),
                    _metricLine(
                        'GPS',
                        monitoring.isGpsActive ? 'ACTIVO' : 'INACTIVO',
                        gpsColor,
                        true),
                    const SizedBox(height: 5),
                    _hudMeter(
                      label: 'SEÑAL',
                      pct: gpsPct,
                      color: gpsColor,
                    ),
                    const SizedBox(height: 7),
                    _metricLine('BATERIA', '${monitoring.batteryLevel}%',
                        batColor, monitoring.batteryLevel <= 20),
                    const SizedBox(height: 5),
                    _hudMeter(
                      label: 'ENERGIA',
                      pct: batteryPct,
                      color: batColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassPanel(
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PanelTitle('ALERTAS / INC.'),
                    const SizedBox(height: 8),
                    _metricLine('ALERTAS DIA', '${monitoring.todayAlertCount}',
                        critical ? AppTheme.error : AppTheme.warning, critical),
                    const SizedBox(height: 5),
                    _hudMeter(
                      label: 'RIESGO',
                      pct: alertPct,
                      color: critical ? AppTheme.error : AppTheme.warning,
                    ),
                    const SizedBox(height: 7),
                    _metricLine(
                        'INCONSIST.',
                        '${monitoring.todayInconsistencyCount}',
                        AppTheme.error,
                        monitoring.todayInconsistencyCount > 0),
                    const SizedBox(height: 5),
                    _hudMeter(
                      label: 'FALLOS',
                      pct: incPct,
                      color: AppTheme.error,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'MOTIVO: ${monitoring.alertReason}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 11.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'DISTANCIA OFICIAL-CONTROL: $distanceLabel',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBodyCards() {
    return Consumer<MonitoringProvider>(
      builder: (context, monitoring, _) {
        final trend = monitoring.hudOperationalTrend;
        final lockTrend = monitoring.hudLockTrend;
        final lat = monitoring.currentPosition?.latitude;
        final lng = monitoring.currentPosition?.longitude;
        final coords = lat == null || lng == null
            ? 'SIN FIX'
            : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
        final cadence = monitoring.hudCadencePerHour;
        final age = monitoring.hudLastReportAgeSec;
        final cadenceLabel = monitoring.hudHasSeriesData
            ? 'CAD: ${cadence.toStringAsFixed(1)} rpt/h   ULT: ${_formatAgeShort(age)}'
            : 'CAD: N/D   ULT: N/D';

        return Row(
          children: [
            Expanded(
              child: GlassPanel(
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PanelTitle('VELAS / FRECUENCIA'),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _hudAnim,
                      builder: (context, _) {
                        return SizedBox(
                          width: double.infinity,
                          height: 106,
                          child: CustomPaint(
                            painter: _HudCandlesPainter(
                              phase: _hudAnim.value,
                              color: AppTheme.warning,
                              trend: trend,
                              gpsActive: monitoring.isGpsActive,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      cadenceLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlassPanel(
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PanelTitle('GRID3D / COORD'),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _hudAnim,
                      builder: (context, _) {
                        return SizedBox(
                          width: double.infinity,
                          height: 106,
                          child: CustomPaint(
                            painter: _HudGrid3DPainter(
                              phase: _hudAnim.value,
                              color: AppTheme.primary,
                              lockTrend: lockTrend,
                              lateralDrift: monitoring.hudLateralDrift,
                              gpsActive: monitoring.isGpsActive,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'COORD: $coords',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHudCharts() {
    return Consumer2<AuthProvider, MonitoringProvider>(
      builder: (context, auth, monitoring, _) {
        final reo = auth.reoAsignado;
        final distance = monitoring.distanceToReo;

        return GlassPanel(
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle('ESTADO OPERATIVO / PERFIL OFICIAL'),
              if (monitoring.todayReportCount == 0 &&
                  monitoring.todayPartesCount == 0 &&
                  monitoring.todayInconsistencyCount == 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Sin datos operativos recientes. Se mostraran aqui cuando entren reportes.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 11.5,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _timeline('Partes oficiales del dia',
                  '${monitoring.todayPartesCount} registros', AppTheme.primary),
              _timeline(
                  'Control de domicilio reo',
                  distance == null
                      ? 'Distancia no disponible'
                      : '${distance.toStringAsFixed(0)} m',
                  AppTheme.success),
              _timeline(
                  'Reo asignado',
                  reo?.nombre ?? auth.oficial?.reoAsignado ?? 'N/D',
                  AppTheme.warning),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRadioCard() {
    return Consumer<RadioProvider>(
      builder: (context, radio, _) {
        final subtitle = !radio.isConnected
            ? (radio.errorMessage?.isNotEmpty ?? false)
                ? 'Canal supervisor inestable: ${radio.errorMessage}'
                : 'Canal supervisor inestable. Verifica señal de red.'
            : radio.unreadCount > 0
                ? 'Canal supervisor: ${radio.unreadCount} mensaje(s) nuevo(s)'
                : 'Canal supervisor listo para consulta y emergencia.';
        return _tapPanel(
          onTap: _openRadio,
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_input_antenna_rounded,
                    color: AppTheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _PanelTitle('RADIO'),
                    Text(subtitle,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.73),
                            fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.primary),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFooterButtons() {
    return Consumer<MonitoringProvider>(
      builder: (context, monitoring, _) {
        final activeLabel = _activeParteSlot == null
            ? '--:--'
            : '${_activeParteSlot!.hour.toString().padLeft(2, '0')}:${_activeParteSlot!.minute.toString().padLeft(2, '0')}';
        final nextLabel = _nextParteSlot == null
            ? '--:--'
            : '${_nextParteSlot!.hour.toString().padLeft(2, '0')}:${_nextParteSlot!.minute.toString().padLeft(2, '0')}';
        final slotStatus = _parteWindowOpen
            ? 'PARTE HABILITADO: $activeLabel (10 min)'
            : 'SIGUIENTE PARTE: $nextLabel';
        final hasParteSorpresa = monitoring.pendingParteSorpresa != null;

        return GlassPanel(
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PanelTitle('FOOTER: TEMPORALES / PARTES'),
              const SizedBox(height: 6),
              Text(
                slotStatus,
                style: TextStyle(
                  color: _parteWindowOpen
                      ? AppTheme.success
                      : Colors.white.withValues(alpha: 0.72),
                  fontFamily: 'Orbitron',
                  fontSize: 10.4,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'BG: $_bgDiagStatus @ $_bgDiagAt',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 10.4,
                  fontFamily: 'Orbitron',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'NATIVE RX: $_bgNativeRxCount @ $_bgNativeRxAt | $_bgNativeAction',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 10.1,
                  fontFamily: 'Orbitron',
                ),
              ),
              Text(
                'DART WD: $_bgWatchdogRxCount @ $_bgWatchdogAt | $_bgWatchdogStatus',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 10.1,
                  fontFamily: 'Orbitron',
                ),
              ),
              Text(
                'NATIVE MODE: $_bgNativeScheduleMode | NEXT: $_bgNativeNextAt | START: $_bgNativeStartStatus',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.54),
                  fontSize: 9.9,
                  fontFamily: 'Orbitron',
                ),
              ),
              Text(
                'DART WD MODE: $_bgWatchdogSchedule',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.52),
                  fontSize: 9.7,
                  fontFamily: 'Orbitron',
                ),
              ),
              if (_bgPendingReports > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'BG QUEUE: $_bgPendingReports pendientes',
                  style: TextStyle(
                    color: AppTheme.warning.withValues(alpha: 0.82),
                    fontSize: 10.2,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
              if (_bgDiagError != '--' && _bgDiagError.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'BG ERR: $_bgDiagError',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.error.withValues(alpha: 0.85),
                    fontSize: 10.1,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
              if (_bgWatchdogError != '--' &&
                  _bgWatchdogError.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'WD ERR: $_bgWatchdogError',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.warning.withValues(alpha: 0.86),
                    fontSize: 10.1,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _footerButton(
                    'TEMPORAL',
                    Icons.timer_rounded,
                    AppTheme.primary,
                    () => _showInfo('Temporal', 'Timer tactico habilitado.'),
                  ),
                  _footerButton(
                    'LOG BG',
                    Icons.history_rounded,
                    AppTheme.primary,
                    _showBgDiagLog,
                  ),
                  _footerButton(
                    hasParteSorpresa ? 'PARTE SORPRESA' : 'PARTE OBLIGATORIO',
                    hasParteSorpresa
                        ? Icons.flash_on_rounded
                        : Icons.fact_check_rounded,
                    hasParteSorpresa ? AppTheme.error : AppTheme.warning,
                    hasParteSorpresa
                        ? () => _showParteDialog(
                              parteSorpresa: monitoring.pendingParteSorpresa,
                            )
                        : _parteWindowOpen
                            ? _showParteDialog
                            : () => _showInfo(
                                  'Parte no habilitado',
                                  'Debes esperar la ventana de parte programado.',
                                ),
                  ),
                  _footerButton(
                    'EMERGENCIA',
                    Icons.emergency_rounded,
                    AppTheme.error,
                    _sendEmergencyPing,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tapPanel({required Widget child, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: GlassPanel(
          borderRadius: BorderRadius.circular(14),
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _gradeIcon(String? grado) {
    final level = GradoAssets.hierarchyLevel(grado);
    final path = GradoAssets.iconAsset(grado);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: Colors.black.withValues(alpha: 0.26),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.22),
            blurRadius: 10,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Image.asset(
          path,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Text(
                'G$level',
                style: const TextStyle(
                  fontFamily: 'Orbitron',
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _hudMeter({
    required String label,
    required double pct,
    required Color color,
  }) {
    final safePct = pct.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 9.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: safePct,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 28,
          child: Text(
            '${(safePct * 100).round()}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metricLine(String label, String value, Color color, bool pulse) {
    return Row(
      children: [
        _SignalIcon(color: color, pulse: pulse),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 11))),
        Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _timeline(String title, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5)),
              Text(subtitle,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11.5)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _footerButton(
      String label, IconData icon, Color color, VoidCallback? onTap) {
    return SizedBox(
      height: 37,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label,
            style:
                const TextStyle(fontSize: 11.4, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.2),
          foregroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(color: color.withValues(alpha: 0.45)),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _decodeBgDiagHistory(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final history = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          history.add(Map<String, dynamic>.from(item));
        }
      }
      return history;
    } catch (_) {
      return const [];
    }
  }

  String _formatDiagDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '--';
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return parsed
          .toLocal()
          .toIso8601String()
          .replaceFirst('T', ' ')
          .split('.')
          .first;
    }
    return raw.replaceFirst('T', ' ').split('.').first;
  }

  String _formatDiagMillis(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '--';
    final millis = int.tryParse(raw.trim());
    if (millis == null) return _formatDiagDateTime(raw);
    final dt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: false);
    return dt.toIso8601String().replaceFirst('T', ' ').split('.').first;
  }

  Future<void> _showBgDiagLog() async {
    if (!mounted) return;
    final entries = _bgDiagHistory.reversed.toList(growable: false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Material(
              color: AppTheme.background,
              child: HucBackground(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: GlassPanel(
                      borderRadius: BorderRadius.circular(14),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'LOG DIAGNOSTICO BG',
                                  style: TextStyle(
                                    fontFamily: 'Orbitron',
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          Text(
                            'Eventos: ${entries.length}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 11.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Native RX: $_bgNativeRxCount @ $_bgNativeRxAt | $_bgNativeAction',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Native mode: $_bgNativeScheduleMode | Next: $_bgNativeNextAt | Start: $_bgNativeStartStatus',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.64),
                              fontSize: 10.6,
                            ),
                          ),
                          Text(
                            'Dart WD: $_bgWatchdogRxCount @ $_bgWatchdogAt | $_bgWatchdogStatus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.64),
                              fontSize: 10.6,
                            ),
                          ),
                          Text(
                            'Dart WD mode: $_bgWatchdogSchedule',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: entries.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Sin historial de BG disponible.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: entries.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 7),
                                    itemBuilder: (_, index) {
                                      final row = entries[index];
                                      final at = _formatDiagDateTime(
                                          row['at']?.toString());
                                      final status =
                                          (row['status'] ?? '--').toString();
                                      final pending = int.tryParse(
                                            (row['pending'] ?? 0).toString(),
                                          ) ??
                                          0;
                                      final error = (row['error'] ?? '')
                                          .toString()
                                          .trim();
                                      return Container(
                                        padding: const EdgeInsets.all(9),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          color: Colors.black
                                              .withValues(alpha: 0.24),
                                          border: Border.all(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.24),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$at | $status',
                                              style: const TextStyle(
                                                fontFamily: 'Orbitron',
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 10.7,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Queue: $pending',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.75),
                                                fontSize: 11,
                                              ),
                                            ),
                                            if (error.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Error: $error',
                                                style: TextStyle(
                                                  color: AppTheme.error
                                                      .withValues(alpha: 0.86),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openRadio() {
    Navigator.of(context).push(buildHudTransitionRoute(const RadioScreen()));
  }

  Future<void> _openMapOverlay() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.94,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Material(
              color: AppTheme.background,
              child: HucBackground(
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'MAPA OPERATIVO',
                                style: TextStyle(
                                  fontFamily: 'Orbitron',
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      const Expanded(
                          child: OperationalMapPanel(compact: false)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openProfileDetail(
      AuthProvider auth, MonitoringProvider monitoring, RadioProvider radio) {
    final official = auth.oficial;
    final reo = auth.reoAsignado;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.82,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Material(
              color: AppTheme.background,
              child: HucBackground(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: GlassPanel(
                      borderRadius: BorderRadius.circular(16),
                      padding: const EdgeInsets.all(14),
                      child: ListView(
                        children: [
                          const Text('PERFIL COMPLETO',
                              style: TextStyle(
                                  fontFamily: 'Orbitron',
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _gradeIcon(official?.grado),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  official?.nombre ?? '--',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _detail('Nombre', official?.nombre ?? '--'),
                          _detail('ID', official?.id ?? '--'),
                          _detail('Grado', official?.gradoDisplay ?? '--'),
                          _detail(
                              'Grupo', (official?.grupo ?? '--').toUpperCase()),
                          _detail(
                              'Jurisdiccion', official?.jurisdiccion ?? '--'),
                          _detail('Reo asignado',
                              reo?.nombre ?? official?.reoAsignado ?? '--'),
                          _detail('Telefono reo', reo?.telefono ?? 'N/D'),
                          _detail('GPS',
                              monitoring.isGpsActive ? 'ACTIVO' : 'INACTIVO'),
                          _detail('Bateria', '${monitoring.batteryLevel}%'),
                          _detail(
                              'Alertas dia', '${monitoring.todayAlertCount}'),
                          _detail('Registros telemetria',
                              '${monitoring.todayReportCount}'),
                          _detail('Inconsistencias dia',
                              '${monitoring.todayInconsistencyCount}'),
                          _detail('Mensajes radio sin leer',
                              '${radio.unreadCount}'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
            width: 150,
            child: Text('$label:',
                style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w700))),
        Expanded(child: Text(value)),
      ]),
    );
  }

  Future<void> _refreshParteWindowState() async {
    final auth = context.read<AuthProvider>();
    final prefs = await SharedPreferences.getInstance();
    final bgStatus = prefs.getString('bg_diag_status') ?? '--';
    final bgUpdatedRaw = prefs.getString('bg_diag_updated_at');
    final bgDiagError = prefs.getString('bg_diag_error') ?? '--';
    final bgHistory = _decodeBgDiagHistory(prefs.getString('bg_diag_history'));
    final nativeRxAt =
        _formatDiagMillis(prefs.getString('bg_native_last_rx_at'));
    final nativeAction = prefs.getString('bg_native_last_action') ?? '--';
    final nativeRxCount = prefs.getInt('bg_native_rx_count') ?? 0;
    final nativeStart = prefs.getString('bg_native_last_start_status') ?? '--';
    final nativeNextAt =
        _formatDiagMillis(prefs.getString('bg_native_next_check_at'));
    final nativeMode = prefs.getString('bg_native_schedule_mode') ?? '--';
    final watchdogCount = prefs.getInt('bg_watchdog_rx_count') ?? 0;
    final watchdogAt =
        _formatDiagDateTime(prefs.getString('bg_watchdog_last_at'));
    final watchdogStatus = prefs.getString('bg_watchdog_last_status') ?? '--';
    final watchdogSchedule =
        prefs.getString('bg_watchdog_schedule_mode') ?? '--';
    final watchdogError = prefs.getString('bg_watchdog_last_error') ?? '--';
    final pendingCount = PendingReportsQueueUtils.decode(
      prefs.getString('bg_pending_reports'),
    ).length;
    final bgUpdatedAt = _formatDiagDateTime(bgUpdatedRaw);

    if (!mounted || !auth.isOnShift || auth.oficial == null) {
      if (_parteWindowOpen ||
          _activeParteSlot != null ||
          _nextParteSlot != null) {
        setState(() {
          _parteWindowOpen = false;
          _activeParteSlot = null;
          _nextParteSlot = null;
          _bgDiagStatus = bgStatus;
          _bgDiagAt = bgUpdatedAt;
          _bgDiagError = bgDiagError;
          _bgPendingReports = pendingCount;
          _bgDiagHistory = bgHistory;
          _bgNativeRxAt = nativeRxAt;
          _bgNativeAction = nativeAction;
          _bgNativeRxCount = nativeRxCount;
          _bgNativeStartStatus = nativeStart;
          _bgNativeNextAt = nativeNextAt;
          _bgNativeScheduleMode = nativeMode;
          _bgWatchdogRxCount = watchdogCount;
          _bgWatchdogAt = watchdogAt;
          _bgWatchdogStatus = watchdogStatus;
          _bgWatchdogSchedule = watchdogSchedule;
          _bgWatchdogError = watchdogError;
        });
      }
      return;
    }

    final now = DateTime.now();
    final active = ParteScheduleUtils.activeSlot(
      now,
      grace: ParteScheduleUtils.graceMinutes,
    );
    final next = ParteScheduleUtils.nextSlot(now);

    bool open = active != null;
    if (open) {
      final completed = await _isParteCompletedForSlot(active);
      final blocked = await _isParteBlockedForSlot(active);
      if (completed || blocked) open = false;
    }

    if (!mounted) return;
    setState(() {
      _activeParteSlot = active;
      _nextParteSlot = next;
      _parteWindowOpen = open;
      _bgDiagStatus = bgStatus;
      _bgDiagAt = bgUpdatedAt;
      _bgDiagError = bgDiagError;
      _bgPendingReports = pendingCount;
      _bgDiagHistory = bgHistory;
      _bgNativeRxAt = nativeRxAt;
      _bgNativeAction = nativeAction;
      _bgNativeRxCount = nativeRxCount;
      _bgNativeStartStatus = nativeStart;
      _bgNativeNextAt = nativeNextAt;
      _bgNativeScheduleMode = nativeMode;
      _bgWatchdogRxCount = watchdogCount;
      _bgWatchdogAt = watchdogAt;
      _bgWatchdogStatus = watchdogStatus;
      _bgWatchdogSchedule = watchdogSchedule;
      _bgWatchdogError = watchdogError;
    });
  }

  Future<bool> _isParteCompletedForSlot(DateTime slot) async {
    final auth = context.read<AuthProvider>();
    final oficialId = auth.oficial?.id;
    if (oficialId == null || oficialId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = 'parte_done_${oficialId}_${ParteScheduleUtils.slotKey(slot)}';
    final localDone = prefs.getBool(key) ?? false;
    if (localDone) return true;

    final existsInDb = await _repository.hasParteOficialForSlot(
      idOficial: oficialId,
      slotTime: slot,
    );
    if (existsInDb) {
      await prefs.setBool(key, true);
    }
    return existsInDb;
  }

  Future<bool> _isParteBlockedForSlot(DateTime slot) async {
    final auth = context.read<AuthProvider>();
    final oficialId = auth.oficial?.id;
    if (oficialId == null || oficialId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = 'parte_block_${oficialId}_${ParteScheduleUtils.slotKey(slot)}';
    return prefs.getBool(key) ?? false;
  }

  Future<void> _markParteBlockedForSlot(DateTime slot) async {
    final auth = context.read<AuthProvider>();
    final oficialId = auth.oficial?.id;
    if (oficialId == null || oficialId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'parte_block_${oficialId}_${ParteScheduleUtils.slotKey(slot)}';
    await prefs.setBool(key, true);
  }

  Future<void> _markParteCompletedForSlot(DateTime slot) async {
    final auth = context.read<AuthProvider>();
    final oficialId = auth.oficial?.id;
    if (oficialId == null || oficialId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'parte_done_${oficialId}_${ParteScheduleUtils.slotKey(slot)}';
    await prefs.setBool(key, true);
  }

  double _similarity(String recognized, String expected) {
    return VoiceMatchUtils.similarity(recognized, expected);
  }

  Future<void> _showParteDialog({
    Map<String, dynamic>? parteSorpresa,
    DateTime? forcedSlot,
  }) async {
    final auth = context.read<AuthProvider>();
    final monitoring = context.read<MonitoringProvider>();
    final oficial = auth.oficial;
    if (oficial == null) return;
    final skipVoiceForWebReview = ReviewFlags.skipPermissionsAndVoiceInWeb;
    final isParteSorpresa = parteSorpresa != null;
    final requireRealBiometric = !skipVoiceForWebReview &&
        ReviewFlags.requireRealVoiceBiometricForPartes;
    final idSorpresa = (parteSorpresa?['id_sorpresa'] ?? '').toString().trim();
    final razonSorpresa =
        (parteSorpresa?['razon'] ?? 'Control sorpresa').toString().trim();

    final DateTime slot;
    if (isParteSorpresa) {
      slot = DateTime.now();
    } else {
      final now = DateTime.now();
      DateTime? resolved = ParteScheduleUtils.activeSlot(
        now,
        grace: ParteScheduleUtils.graceMinutes,
      );

      if (resolved == null && forcedSlot != null) {
        final forcedLocal = forcedSlot.toLocal();
        final normalizedForced = DateTime(
          forcedLocal.year,
          forcedLocal.month,
          forcedLocal.day,
          forcedLocal.hour,
          forcedLocal.minute,
        );
        final lateTolerance = Duration(
          minutes: ParteScheduleUtils.graceMinutes + 20,
        );
        final allowedUntil = normalizedForced.add(lateTolerance);
        if (now.isBefore(allowedUntil)) {
          resolved = normalizedForced;
        }
      }

      if (resolved == null) {
        _showInfo(
          'Parte no habilitado',
          'No hay ventana activa de parte en este momento.',
        );
        return;
      }
      if (await _isParteBlockedForSlot(resolved)) {
        _showInfo(
          'Parte bloqueado por seguridad',
          'Esta ventana ya fue bloqueada por fallos de validacion.',
        );
        await _refreshParteWindowState();
        return;
      }
      if (await _isParteCompletedForSlot(resolved)) {
        _showInfo(
            'Parte ya registrado', 'El parte de esta ventana ya fue enviado.');
        await _refreshParteWindowState();
        return;
      }
      slot = resolved;
    }

    String voiceCode = '';
    bool voiceValidationEnabled = false;
    if (!skipVoiceForWebReview) {
      voiceCode =
          (await SecurityStorageService.readVoiceProfileCode() ?? '').trim();
    }

    final slotLabel = isParteSorpresa
        ? 'SORPRESA'
        : '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}';
    final expectedPhrase = skipVoiceForWebReview
        ? 'MODO REVISION WEB'
        : VoiceChallengeUtils.generateChallengePhrase(
            isParteSorpresa: isParteSorpresa,
            slot: slot,
            idSorpresa: idSorpresa.isEmpty ? null : idSorpresa,
          );

    final speech = SpeechToText();
    String? speechLocaleId;
    String lastSpeechError = '';

    Future<bool> ensureSpeechEngineReady() async {
      if (skipVoiceForWebReview) return true;

      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final requested = await Permission.microphone.request();
        if (!requested.isGranted) {
          return false;
        }
      }

      try {
        await VoiceRecorderService.stopIfRecording();
      } catch (_) {}
      try {
        await speech.stop();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 180));

      final ready = await speech.initialize(
        onError: (error) {
          lastSpeechError = error.errorMsg;
        },
      );
      if (!ready) return false;

      try {
        final locales = await speech.locales();
        for (final locale in locales) {
          final id = locale.localeId.toLowerCase();
          if (id.startsWith('es_') || id.startsWith('es-') || id == 'es') {
            speechLocaleId = locale.localeId;
            break;
          }
        }
        speechLocaleId ??= (await speech.systemLocale())?.localeId;
      } catch (_) {
        speechLocaleId = null;
      }

      return true;
    }

    Future<void> forceResetMicrophoneSession() async {
      if (skipVoiceForWebReview) return;
      try {
        await speech.stop();
      } catch (_) {}
      try {
        await VoiceRecorderService.stopIfRecording();
      } catch (_) {}
      await ensureSpeechEngineReady();
    }

    if (!skipVoiceForWebReview) {
      if (voiceCode.isEmpty) {
        _showInfo(
          'Parte bloqueado',
          'No existe perfil de voz registrado. Completa la certificacion de voz para enviar partes.',
        );
        return;
      }
      if (!requireRealBiometric) {
        final speechReady = await ensureSpeechEngineReady();
        if (!speechReady) {
          _showInfo(
            'Parte bloqueado',
            'No se pudo iniciar el microfono para validacion obligatoria de voz.',
          );
          return;
        }
      }
      voiceValidationEnabled = true;
    }

    int attempts = 0;
    bool isListening = false;
    bool isValidatingVoice = false;
    String recognizedText = '';
    double recognizedSimilarity = skipVoiceForWebReview ? 1 : 0;
    bool voiceApproved = skipVoiceForWebReview;
    String voiceLiveStatus =
        skipVoiceForWebReview ? 'REVISION WEB ACTIVA' : 'MICROFONO EN ESPERA';
    String voiceCriticalError = '';
    String submitCriticalError = '';
    bool isSubmitting = false;
    bool withNovedad = false;
    int evidenciasFotos = 0;
    bool isProcessingImageEvidence = false;
    final evidenceHashes = <String>[];
    final evidenceProofTokens = <String>[];
    bool voiceValidatedByTechnicalFallback = false;
    bool parteSubmitted = false;
    bool closureLogged = false;
    bool securityAutoClosed = false;
    final picker = ImagePicker();
    final novedadController = TextEditingController();
    final rootContext = context;
    if (!rootContext.mounted) return;

    await showModalBottomSheet<void>(
      context: rootContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> registerParteInconsistency({
              required String tipo,
              required String descripcion,
              String prioridad = 'ALTA',
            }) async {
              final payload = <String, dynamic>{
                'id_oficial': oficial.id,
                'tipo_inconsistencia': tipo,
                'descripcion': descripcion,
                'prioridad': prioridad,
                'fecha_deteccion': UtcTimeUtils.nowIso(),
              };

              var saved = false;
              for (var i = 0; i < 3; i++) {
                saved = await _repository.insertInconsistencia(payload);
                if (saved) break;
                await Future<void>.delayed(
                  Duration(milliseconds: 250 * (i + 1)),
                );
              }
              if (saved) return;

              // Fallback operativo: al menos deja rastro en monitoreo si
              // inconsistencias no pudo persistir en ese momento.
              final pos = monitoring.currentPosition;
              await _repository.upsertMonitoreo({
                'id_reporte':
                    'INCFAIL_${oficial.id}_${DateTime.now().millisecondsSinceEpoch}',
                'id_oficial_ref': oficial.id,
                'nombre_oficial': oficial.nombre,
                'fecha_hora': UtcTimeUtils.nowIso(),
                'reo_asignado': oficial.reoAsignado,
                'ubicacion_actual': pos == null
                    ? 'SIN_DATOS_GPS'
                    : '${pos.latitude},${pos.longitude}',
                'latitud': pos?.latitude,
                'longitud': pos?.longitude,
                'distancia_metros': monitoring.distanceToReo,
                'estado_alerta': 'ALERTA',
                'nivel_bateria': monitoring.batteryLevel,
                'gps_real': monitoring.isGpsActive,
                'movimiento': false,
                'parte_novedad': 'INC_FALLBACK|$tipo|$descripcion',
                'imei': auth.deviceId,
                'grupo': oficial.grupo.toUpperCase(),
              });
            }

            Future<void> closeParteWindowWithInconsistency({
              required String tipo,
              required String descripcion,
            }) async {
              if (closureLogged || parteSubmitted) {
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
                return;
              }
              closureLogged = true;
              await registerParteInconsistency(
                tipo: tipo,
                descripcion: descripcion,
              );
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
            }

            Future<void> registerRejectedParteByVoice({
              required String reason,
              required bool technicalFailure,
            }) async {
              if (isParteSorpresa) return;
              final lat = monitoring.currentPosition?.latitude;
              final lng = monitoring.currentPosition?.longitude;
              final reasonTag = technicalFailure
                  ? 'RECHAZADO_FALLA_TECNICA_VOZ'
                  : 'RECHAZADO_NO_COINCIDE_VOZ';
              var ok = false;
              for (var i = 0; i < 3; i++) {
                ok = await _repository.upsertParteOficial(
                  idOficial: oficial.id,
                  slotTime: slot,
                  resultadoVoz: 'RECHAZADO',
                  estado: 'RECHAZADO',
                  novedad: '$reasonTag | MOTIVO:$reason',
                  latitud: lat,
                  longitud: lng,
                  rutaAudio:
                      recognizedText.trim().isEmpty ? null : recognizedText,
                );
                if (ok) break;
                await Future<void>.delayed(
                  Duration(milliseconds: 250 * (i + 1)),
                );
              }
              if (!ok) {
                await registerParteInconsistency(
                  tipo: 'PARTE_RECHAZADO_NO_GUARDADO',
                  descripcion:
                      'No se pudo guardar parte RECHAZADO por voz en slot $slotLabel.',
                  prioridad: 'ALTA',
                );
              }
            }

            Future<void> captureVoiceSampleAuto() async {
              if (skipVoiceForWebReview) return;
              if (isListening || isSubmitting || isValidatingVoice) return;
              final speechReady = await ensureSpeechEngineReady();
              if (!speechReady) {
                if (!sheetContext.mounted) return;
                setModalState(() {
                  isListening = false;
                  isValidatingVoice = false;
                  voiceLiveStatus = 'MICROFONO NO DISPONIBLE';
                  voiceCriticalError =
                      'ERROR: VOZ NO CAPTURADA\nNo se pudo iniciar el microfono.';
                });
                return;
              }
              if (!sheetContext.mounted) return;
              setModalState(() {
                isValidatingVoice = true;
                isListening = true;
                recognizedText = '';
                recognizedSimilarity = 0;
                voiceApproved = false;
                submitCriticalError = '';
                voiceCriticalError = '';
                voiceLiveStatus = 'GRABANDO VOZ... HABLA AHORA';
              });

              Future<void> runListenAttempt() async {
                final captureDone = Completer<void>();
                Timer? guardTimer;
                void completeCapture() {
                  if (!captureDone.isCompleted) {
                    captureDone.complete();
                  }
                }

                void onSpeechResult(dynamic result) {
                  final words =
                      (result.recognizedWords ?? '').toString().trim();
                  if (words.isNotEmpty) {
                    final score = _similarity(words, expectedPhrase);
                    if (sheetContext.mounted) {
                      setModalState(() {
                        final betterScore = score > recognizedSimilarity;
                        final slightlyBetterWithMoreContext =
                            score >= (recognizedSimilarity - 0.03) &&
                                words.length > recognizedText.length;
                        if (recognizedText.trim().isEmpty ||
                            betterScore ||
                            slightlyBetterWithMoreContext) {
                          recognizedText = words;
                          recognizedSimilarity = score;
                        }
                      });
                    }
                  }
                  final finalResult = (result.finalResult ?? false) == true;
                  if (finalResult) {
                    completeCapture();
                  }
                }

                guardTimer =
                    Timer(const Duration(seconds: 12), completeCapture);
                try {
                  if (speechLocaleId != null &&
                      speechLocaleId!.trim().isNotEmpty) {
                    await speech.listen(
                      listenFor: const Duration(seconds: 12),
                      pauseFor: const Duration(seconds: 4),
                      listenOptions: SpeechListenOptions(partialResults: true),
                      onResult: onSpeechResult,
                      localeId: speechLocaleId,
                    );
                  } else {
                    await speech.listen(
                      listenFor: const Duration(seconds: 12),
                      pauseFor: const Duration(seconds: 4),
                      listenOptions: SpeechListenOptions(partialResults: true),
                      onResult: onSpeechResult,
                    );
                  }
                } catch (_) {
                  try {
                    await speech.listen(
                      listenFor: const Duration(seconds: 12),
                      pauseFor: const Duration(seconds: 4),
                      listenOptions: SpeechListenOptions(partialResults: true),
                      onResult: onSpeechResult,
                    );
                  } catch (_) {
                    completeCapture();
                  }
                }
                await captureDone.future;
                await speech.stop();
                guardTimer.cancel();
              }

              await runListenAttempt();
              if (recognizedText.trim().isEmpty) {
                await forceResetMicrophoneSession();
                if (sheetContext.mounted) {
                  setModalState(() {
                    voiceLiveStatus = 'REINTENTANDO CAPTURA DE VOZ...';
                  });
                }
                await runListenAttempt();
              }
              if (!sheetContext.mounted) return;
              setModalState(() {
                isListening = false;
                isValidatingVoice = false;
                voiceLiveStatus = 'MICROFONO EN ESPERA';
              });
            }

            Future<void> stopListening() async {
              if (skipVoiceForWebReview) return;
              if (!isListening && !isValidatingVoice) return;
              await speech.stop();
              if (!sheetContext.mounted) return;
              setModalState(() {
                isListening = false;
                isValidatingVoice = false;
                voiceLiveStatus = 'MICROFONO EN ESPERA';
              });
            }

            Future<void> handleVoiceValidationFailure(String reason) async {
              final lowerReason = reason.toLowerCase();
              bool isTechnicalVoiceFailureReason(String value) {
                final v = value.toLowerCase();
                return v.contains('microfono') ||
                    v.contains('audio') ||
                    v.contains('capturar muestra') ||
                    v.contains('no se detecto voz') ||
                    v.contains('motor biometrico') ||
                    v.contains('biometria servidor') ||
                    v.contains('huella biometrica') ||
                    v.contains('embedding') ||
                    v.contains('fn_voice_biometric_verify') ||
                    v.contains('rpc') ||
                    v.contains('timeout') ||
                    v.contains('no disponible') ||
                    v.contains('no existe huella biometrica');
              }

              final isNoCapture = lowerReason.contains('no se detecto voz') ||
                  lowerReason.contains('capturar muestra');
              final isTechnicalFailure =
                  isNoCapture || isTechnicalVoiceFailureReason(reason);
              final isNoMatch = lowerReason.contains('no coincide') ||
                  lowerReason.contains('frase');
              final errorTitle = isNoCapture
                  ? 'ERROR: VOZ NO CAPTURADA'
                  : isNoMatch
                      ? 'ERROR: VOZ NO COINCIDE'
                      : 'ERROR: VALIDACION DE VOZ';
              final errorBody = isNoCapture
                  ? 'No se pudo capturar voz util. Acerca el microfono y habla claro.'
                  : isNoMatch
                      ? 'La frase aleatoria no coincide con la voz reconocida.'
                      : reason;
              if (!sheetContext.mounted) return;
              setModalState(() {
                voiceApproved = false;
                voiceLiveStatus = 'VOZ RECHAZADA';
                voiceCriticalError = '$errorTitle\n$errorBody';
              });
              if (attempts >= 3) {
                if (!isParteSorpresa) {
                  await _markParteBlockedForSlot(slot);
                }
                securityAutoClosed = true;
                closureLogged = true;
                await registerRejectedParteByVoice(
                  reason: reason,
                  technicalFailure: isTechnicalFailure,
                );
                await registerParteInconsistency(
                  tipo: isTechnicalFailure
                      ? 'FALLA_TECNICA_VOZ'
                      : 'POSIBLE_SUPLANTACION',
                  descripcion: isTechnicalFailure
                      ? 'FALLA_TECNICA_VOZ - slot $slotLabel - $reason'
                      : 'POSIBLE_SUPLANTACION_VOZ - slot $slotLabel - $reason',
                );
                await NotificationService.cancelParteOficialAlert();
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                if (mounted) {
                  await _refreshParteWindowState();
                  _showInfo(
                    isTechnicalFailure
                        ? 'PARTE RECHAZADO POR FALLA TECNICA'
                        : 'BLOQUEO DE SEGURIDAD',
                    isTechnicalFailure
                        ? 'No se pudo validar voz por falla tecnica. Parte registrado como RECHAZADO.'
                        : 'Validacion de voz rechazada en 3 intentos. Parte cerrado automaticamente.',
                  );
                }
                return;
              }
              _showInfo(
                errorTitle,
                'Intento $attempts/3. $errorBody',
              );
            }

            Future<({String? error, bool technicalFailure})>
                verifyVoiceBiometric({
              double acceptThreshold =
                  VoiceBiometricService.defaultAcceptThreshold,
            }) async {
              bool isTechnicalBiometricReason(String value) {
                final v = value.toLowerCase();
                return v.contains('microfono') ||
                    v.contains('audio') ||
                    v.contains('capturar muestra') ||
                    v.contains('no se detecto voz') ||
                    v.contains('motor biometrico') ||
                    v.contains('biometria servidor') ||
                    v.contains('huella biometrica') ||
                    v.contains('embedding') ||
                    v.contains('fn_voice_biometric_verify') ||
                    v.contains('rpc') ||
                    v.contains('timeout') ||
                    v.contains('no disponible') ||
                    v.contains('no existe huella biometrica');
              }

              setModalState(() {
                voiceApproved = false;
              });

              // 1) Validacion primaria en servidor (perfil oficial persistente).
              final rpcResult = await _repository.verifyVoiceBiometric(
                idOficial: oficial.id,
                expectedPhrase: expectedPhrase,
                recognizedText: recognizedText,
              );
              if (rpcResult.ok) {
                return (error: null, technicalFailure: false);
              }

              // 2) Fallback local solo si existe perfil en el dispositivo.
              final profile =
                  await SecurityStorageService.readVoiceBiometricProfile();
              if (profile == null || profile.isEmpty) {
                final reason = (rpcResult.message ?? '').trim();
                if (reason.isNotEmpty) {
                  return (
                    error: 'Biometria servidor rechazo: $reason',
                    technicalFailure: isTechnicalBiometricReason(reason),
                  );
                }
                const fallbackError =
                    'No existe huella biometrica local y la validacion servidor no aprobo.';
                return (
                  error: fallbackError,
                  technicalFailure: isTechnicalBiometricReason(fallbackError),
                );
              }

              String? samplePath = await VoiceRecorderService.captureWavSample(
                duration: const Duration(seconds: 4),
              );
              if (samplePath == null || samplePath.trim().isEmpty) {
                await forceResetMicrophoneSession();
                await Future<void>.delayed(const Duration(milliseconds: 250));
                samplePath = await VoiceRecorderService.captureWavSample(
                  duration: const Duration(seconds: 4),
                );
              }
              if (samplePath == null || samplePath.trim().isEmpty) {
                const captureError =
                    'No se pudo capturar muestra de audio para biometria.';
                return (
                  error: captureError,
                  technicalFailure: true,
                );
              }

              final biometric =
                  await VoiceBiometricService.verifyWavAgainstProfile(
                wavPath: samplePath,
                profileEmbedding: profile,
                acceptThreshold: acceptThreshold,
              );

              try {
                await File(samplePath).delete();
              } catch (_) {}

              if (!biometric.ok) {
                final localReason =
                    '${biometric.message} (score ${(biometric.score * 100).toStringAsFixed(0)}%, calidad ${(biometric.quality * 100).toStringAsFixed(0)}%)';
                final localNoMatch =
                    localReason.toLowerCase().contains('no coincide');
                if (localNoMatch) {
                  return (
                    error: localReason,
                    technicalFailure: false,
                  );
                }
                final rpcReason = (rpcResult.message ?? '').trim();
                if (rpcReason.isNotEmpty) {
                  final merged = 'Servidor: $rpcReason | Local: $localReason';
                  return (
                    error: merged,
                    technicalFailure: isTechnicalBiometricReason(merged),
                  );
                }
                return (
                  error: localReason,
                  technicalFailure: isTechnicalBiometricReason(localReason),
                );
              }
              return (error: null, technicalFailure: false);
            }

            Future<void> validateVoice() async {
              if (skipVoiceForWebReview) {
                setModalState(() {
                  recognizedSimilarity = 1;
                  voiceApproved = true;
                });
                return;
              }
              if (isSubmitting || isValidatingVoice) return;

              await captureVoiceSampleAuto();
              if (!sheetContext.mounted) return;
              attempts += 1;
              if (recognizedText.trim().isEmpty) {
                await handleVoiceValidationFailure(
                  lastSpeechError.trim().isEmpty
                      ? 'No se detecto voz util. Habla claro y cerca del microfono.'
                      : 'No se detecto voz util ($lastSpeechError).',
                );
                return;
              }

              if (recognizedSimilarity < VoiceChallengeUtils.minSimilarity) {
                final coreMatch = VoiceMatchUtils.hasCoreChallengeMatch(
                  recognizedText,
                  expectedPhrase,
                );
                if (!coreMatch) {
                  await handleVoiceValidationFailure(
                    'La frase no coincide con el patron esperado.',
                  );
                  return;
                }
                if (!sheetContext.mounted) return;
                setModalState(() {
                  recognizedSimilarity = math.max(
                      recognizedSimilarity, VoiceChallengeUtils.minSimilarity);
                  voiceLiveStatus = 'VOZ CAPTURADA (CLAVE OK)';
                });
              }

              if (requireRealBiometric) {
                final biometricResult = await verifyVoiceBiometric();
                final biometricError = biometricResult.error;
                if (biometricError != null) {
                  final technicalBiometricFailure =
                      biometricResult.technicalFailure;
                  if (technicalBiometricFailure) {
                    voiceValidatedByTechnicalFallback = true;
                    await registerParteInconsistency(
                      tipo: 'FALLA_TECNICA_VOZ',
                      descripcion:
                          'FALLA_TECNICA_BIOMETRIA_FALLBACK - slot $slotLabel - $biometricError',
                    );
                    if (!sheetContext.mounted) return;
                    setModalState(() {
                      voiceApproved = true;
                      voiceCriticalError =
                          'FALLA TECNICA BIOMETRIA\nSe habilita contingencia por frase valida.';
                      voiceLiveStatus = 'VOZ VALIDADA (CONTINGENCIA)';
                    });
                    _showInfo(
                      'CONTINGENCIA DE VOZ',
                      'Frase validada. Biometria con falla tecnica; parte se registrará con revisión pendiente.',
                    );
                    return;
                  }
                  await handleVoiceValidationFailure(biometricError);
                  return;
                }
              }

              setModalState(() {
                voiceApproved = true;
                voiceCriticalError = '';
                voiceLiveStatus = 'VOZ VALIDADA';
              });
            }

            Future<void> submitParte() async {
              if (!voiceApproved && voiceValidationEnabled) {
                await validateVoice();
              }
              if (!voiceApproved) {
                setModalState(() {
                  submitCriticalError =
                      'ERROR REPORTE NO ENVIADO: validacion de voz incompleta.';
                });
                _showInfo(
                  'ERROR REPORTE NO ENVIADO',
                  'Primero valida la voz correctamente para enviar el parte.',
                );
                return;
              }

              if (evidenciasFotos < 1) {
                _showInfo(
                  'Evidencia requerida',
                  'Debes capturar al menos 1 fotografia para registrar el parte.',
                );
                return;
              }

              if (withNovedad && novedadController.text.trim().isEmpty) {
                _showInfo('Novedad requerida', 'Escribe la novedad del parte.');
                return;
              }

              setModalState(() {
                isSubmitting = true;
                submitCriticalError = '';
              });
              await stopListening();

              double? lat;
              double? lng;
              try {
                final pos = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.high,
                  timeLimit: const Duration(seconds: 8),
                );
                lat = pos.latitude;
                lng = pos.longitude;
              } catch (_) {
                // Si no hay fix, se registra igual con null.
              }

              final novedad = withNovedad
                  ? novedadController.text.trim()
                  : (skipVoiceForWebReview
                      ? 'SIN NOVEDAD (REVISION WEB)'
                      : 'SIN NOVEDAD');
              final parteConNovedad = withNovedad && novedad.isNotEmpty;
              final vozResumen = voiceValidationEnabled
                  ? (recognizedText.isEmpty ? 'NO REGISTRADA' : recognizedText)
                  : 'NO APLICA';
              final challengeResumen =
                  voiceValidationEnabled ? expectedPhrase : 'NO APLICA';
              final evidenceHashSummary =
                  evidenceHashes.isEmpty ? 'SIN_HASH' : evidenceHashes.last;
              final evidenceProofSummary = evidenceProofTokens.isEmpty
                  ? 'SIN_PROOF'
                  : evidenceProofTokens.last;
              final payloadNovedad =
                  '$novedad | CHALLENGE:$challengeResumen | VOZ_TXT:$vozResumen | VOZ_MODO:${voiceValidatedByTechnicalFallback ? 'FALLBACK_TECNICO' : 'BIOMETRIA_OK'} | EVID_HASH:$evidenceHashSummary | EVID_PROOF:$evidenceProofSummary | EVID_COUNT:$evidenciasFotos';

              if (isParteSorpresa && idSorpresa.isNotEmpty) {
                final respuesta =
                    'PARTE SORPRESA ${parteConNovedad ? 'CON NOVEDAD' : 'VERIFICADO'} | CHALLENGE:$challengeResumen | VOZ:$vozResumen | NOVEDAD:$payloadNovedad | FOTOS:$evidenciasFotos';
                final ok = await _repository.completarParteSorpresa(
                  idSorpresa: idSorpresa,
                  respuestaOficial: respuesta,
                  latitud: lat,
                  longitud: lng,
                );
                if (!ok) {
                  await registerParteInconsistency(
                    tipo: 'PARTE_ENVIO_FALLIDO',
                    descripcion:
                        'No se pudo registrar parte sorpresa ($idSorpresa) en slot $slotLabel.',
                  );
                  if (!sheetContext.mounted) return;
                  setModalState(() {
                    isSubmitting = false;
                    submitCriticalError =
                        'ERROR REPORTE NO ENVIADO: fallo de base de datos.';
                  });
                  _showInfo(
                    'ERROR REPORTE NO ENVIADO',
                    'No se pudo registrar el parte sorpresa.',
                  );
                  return;
                }
                monitoring.clearPendingParteSorpresa(idSorpresa);
                await NotificationService.cancelParteSorpresaAlert();
              } else {
                final okParte = await _repository.upsertParteOficial(
                  idOficial: oficial.id,
                  slotTime: slot,
                  resultadoVoz: voiceValidatedByTechnicalFallback
                      ? 'PENDIENTE'
                      : 'APROBADO',
                  estado: 'REGISTRADO',
                  novedad: payloadNovedad,
                  latitud: lat,
                  longitud: lng,
                  rutaAudio: skipVoiceForWebReview
                      ? null
                      : (recognizedText.isEmpty ? null : recognizedText),
                );
                if (!okParte) {
                  await registerParteInconsistency(
                    tipo: 'PARTE_ENVIO_FALLIDO',
                    descripcion:
                        'No se pudo guardar parte oficial en slot $slotLabel.',
                  );
                  if (!sheetContext.mounted) return;
                  setModalState(() {
                    isSubmitting = false;
                    submitCriticalError =
                        'ERROR REPORTE NO ENVIADO: fallo de base de datos.';
                  });
                  _showInfo(
                    'ERROR REPORTE NO ENVIADO',
                    'No se pudo guardar el parte en la base de datos.',
                  );
                  return;
                }
                await _markParteCompletedForSlot(slot);
                await NotificationService.cancelParteOficialAlert();
              }

              if (!sheetContext.mounted) return;
              parteSubmitted = true;
              Navigator.of(sheetContext).pop();
              if (!mounted) return;
              if (!isParteSorpresa) {
                await _refreshParteWindowState();
              }
              _showInfo(
                isParteSorpresa
                    ? 'Parte sorpresa registrado'
                    : (voiceValidatedByTechnicalFallback
                        ? 'Parte registrado (contingencia)'
                        : 'Parte registrado'),
                isParteSorpresa
                    ? 'Solicitud sorpresa atendida con exito.'
                    : (voiceValidatedByTechnicalFallback
                        ? 'Parte $slotLabel registrado con biometria pendiente por falla tecnica.'
                        : 'Parte $slotLabel registrado con exito.'),
              );
            }

            Future<void> capturePhotoEvidence() async {
              if (isSubmitting || isProcessingImageEvidence) return;
              try {
                final photo = await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 70,
                  maxWidth: 1280,
                );
                if (photo == null) return;
                if (!sheetContext.mounted) return;
                setModalState(() => isProcessingImageEvidence = true);

                final hashResult =
                    await ValidationHashService.buildEvidenceHash(
                  oficialId: oficial.id,
                  imagePath: photo.path,
                  slotLabel: slotLabel,
                  expectedPhrase: expectedPhrase,
                  recognizedText: recognizedText,
                  idSorpresa: idSorpresa,
                  isParteSorpresa: isParteSorpresa,
                );

                try {
                  await File(photo.path).delete();
                } catch (_) {}

                if (hashResult.mockSuspected) {
                  await registerParteInconsistency(
                    tipo: 'ANTI_MOCKING_ALERTA',
                    descripcion:
                        'Hash evidencia detecto posible mocking de ubicacion en parte $slotLabel.',
                  );
                }

                if (!hashResult.ok || hashResult.hash.trim().isEmpty) {
                  await registerParteInconsistency(
                    tipo: 'EVIDENCIA_HASH_FALLA',
                    descripcion:
                        'No se pudo generar hash de validacion de evidencia en parte $slotLabel.',
                    prioridad: 'MEDIA',
                  );
                  if (sheetContext.mounted) {
                    setModalState(() => isProcessingImageEvidence = false);
                  }
                  _showInfo(
                    'Evidencia no valida',
                    'No se pudo procesar imagen para generar hash de validacion.',
                  );
                  return;
                }

                if (!sheetContext.mounted) return;
                setModalState(() {
                  isProcessingImageEvidence = false;
                  evidenciasFotos += 1;
                  evidenceHashes.add(hashResult.hash);
                  final proofToken =
                      (hashResult.envelope['proof_token'] ?? '').toString();
                  if (proofToken.trim().isNotEmpty) {
                    evidenceProofTokens.add(proofToken.trim());
                  }
                });
              } catch (_) {
                if (sheetContext.mounted) {
                  setModalState(() => isProcessingImageEvidence = false);
                }
                _showInfo(
                    'Camara', 'No se pudo capturar evidencia fotografica.');
              }
            }

            return FractionallySizedBox(
              heightFactor: 0.92,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Material(
                  color: AppTheme.background,
                  child: HucBackground(
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        child: GlassPanel(
                          borderRadius: BorderRadius.circular(16),
                          padding: const EdgeInsets.all(14),
                          child: ListView(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isParteSorpresa
                                          ? 'PARTE SORPRESA INMEDIATO'
                                          : 'PARTE OFICIAL OBLIGATORIO',
                                      style: TextStyle(
                                        fontFamily: 'Orbitron',
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      await closeParteWindowWithInconsistency(
                                        tipo: 'OFICIAL_CERRO_VENTANA_PARTE',
                                        descripcion:
                                            'Oficial cerro ventana de parte ($slotLabel) sin confirmar envio.',
                                      );
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              Text(
                                isParteSorpresa
                                    ? 'Solicitud: $razonSorpresa'
                                    : 'Ventana activa: $slotLabel  (max ${ParteScheduleUtils.graceMinutes} min)',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 12,
                                ),
                              ),
                              if (skipVoiceForWebReview) ...[
                                const SizedBox(height: 10),
                                Text(
                                  'Revision navegador activa: validacion de voz temporalmente deshabilitada.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              if (voiceValidationEnabled) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.black.withValues(alpha: 0.26),
                                    border: Border.all(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    'Frase aleatoria del control: $expectedPhrase',
                                    style: const TextStyle(
                                      fontFamily: 'Orbitron',
                                      color: AppTheme.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  requireRealBiometric
                                      ? 'Doble validacion obligatoria: frase aleatoria + biometria de voz (maximo 3 intentos).'
                                      : 'Validacion de frase aleatoria: coincidencia minima 75% (maximo 3 intentos solo si falla).',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.68),
                                    fontSize: 11.3,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      isListening ? Icons.mic : Icons.mic_none,
                                      color: isListening
                                          ? AppTheme.success
                                          : AppTheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      voiceLiveStatus,
                                      style: TextStyle(
                                        color: voiceApproved
                                            ? AppTheme.success
                                            : (voiceCriticalError.isNotEmpty
                                                ? AppTheme.error
                                                : (isListening
                                                    ? AppTheme.success
                                                    : AppTheme.primary)),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Intentos: $attempts/3',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.72),
                                      ),
                                    ),
                                  ],
                                ),
                                if (voiceCriticalError.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: AppTheme.error
                                          .withValues(alpha: 0.16),
                                      border: Border.all(
                                        color: AppTheme.error
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Text(
                                      voiceCriticalError,
                                      style: const TextStyle(
                                        color: AppTheme.error,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                if (submitCriticalError.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: AppTheme.error
                                          .withValues(alpha: 0.18),
                                      border: Border.all(
                                        color: AppTheme.error
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: Text(
                                      submitCriticalError,
                                      style: const TextStyle(
                                        color: AppTheme.error,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  recognizedText.isEmpty
                                      ? 'Sin captura de voz.'
                                      : 'Reconocido: $recognizedText',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Similitud: ${(recognizedSimilarity * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    color: voiceApproved
                                        ? AppTheme.success
                                        : Colors.white.withValues(alpha: 0.72),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (voiceApproved) ...[
                                  const SizedBox(height: 4),
                                  const Text(
                                    'VOZ VALIDADA',
                                    style: TextStyle(
                                      color: AppTheme.success,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Orbitron',
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _footerButton(
                                      isValidatingVoice
                                          ? 'VALIDANDO...'
                                          : 'INICIAR VALIDACION DE VOZ',
                                      Icons.verified_user_rounded,
                                      AppTheme.warning,
                                      isValidatingVoice ? null : validateVoice,
                                    ),
                                    _footerButton(
                                      'REINICIAR MICROFONO',
                                      Icons.mic_external_off_rounded,
                                      AppTheme.primary,
                                      isValidatingVoice || isSubmitting
                                          ? null
                                          : () async {
                                              await forceResetMicrophoneSession();
                                              if (!mounted) return;
                                              _showInfo(
                                                'Microfono',
                                                'Sesion de microfono reiniciada.',
                                              );
                                            },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],
                              SwitchListTile(
                                value: withNovedad,
                                onChanged: (value) =>
                                    setModalState(() => withNovedad = value),
                                title: const Text('Parte con novedad'),
                                subtitle: const Text(
                                  'Si esta activo, debes describir la novedad.',
                                ),
                              ),
                              if (withNovedad)
                                TextField(
                                  controller: novedadController,
                                  minLines: 2,
                                  maxLines: 4,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Detalle de novedad...',
                                    filled: true,
                                    fillColor: const Color(0x70121D2C),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Evidencia fotografica obligatoria: $evidenciasFotos',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.78),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  _footerButton(
                                    isProcessingImageEvidence
                                        ? 'PROCESANDO IMAGEN...'
                                        : 'CAPTURAR FOTO',
                                    Icons.camera_alt_rounded,
                                    AppTheme.primary,
                                    isProcessingImageEvidence
                                        ? null
                                        : capturePhotoEvidence,
                                  ),
                                ],
                              ),
                              if (evidenceHashes.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Hash evidencia: ${evidenceHashes.last.substring(0, 16)}...',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.68),
                                    fontSize: 11.2,
                                  ),
                                ),
                                if (evidenceProofTokens.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Proof token: ${evidenceProofTokens.last}',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.62),
                                      fontSize: 10.6,
                                    ),
                                  ),
                                ],
                              ],
                              const SizedBox(height: 14),
                              Text(
                                'Chat radio es opcional y lo decide el supervisor.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.66),
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: isSubmitting
                                      ? null
                                      : () async {
                                          await closeParteWindowWithInconsistency(
                                            tipo: 'OFICIAL_RECHAZO_PARTE',
                                            descripcion:
                                                'Oficial rechazo realizar parte $slotLabel.',
                                          );
                                        },
                                  icon: const Icon(Icons.block_rounded),
                                  label: const Text('RECHAZAR PARTE'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.error,
                                    side: BorderSide(
                                      color:
                                          AppTheme.error.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      isSubmitting ? null : () => submitParte(),
                                  icon: const Icon(Icons.send_rounded),
                                  label: Text(
                                    isSubmitting
                                        ? 'REGISTRANDO...'
                                        : 'CONFIRMAR PARTE',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!skipVoiceForWebReview) {
      await speech.stop();
    }
    if (!parteSubmitted && !closureLogged && !securityAutoClosed) {
      final payload = <String, dynamic>{
        'id_oficial': oficial.id,
        'tipo_inconsistencia': 'OFICIAL_CERRO_VENTANA_PARTE',
        'descripcion':
            'Oficial cerro ventana de parte ($slotLabel) sin confirmar envio.',
        'prioridad': 'ALTA',
        'fecha_deteccion': UtcTimeUtils.nowIso(),
      };
      var saved = false;
      for (var i = 0; i < 3; i++) {
        saved = await _repository.insertInconsistencia(payload);
        if (saved) break;
        await Future<void>.delayed(Duration(milliseconds: 250 * (i + 1)));
      }
      if (!saved) {
        final pos = monitoring.currentPosition;
        await _repository.upsertMonitoreo({
          'id_reporte':
              'INCFAIL_${oficial.id}_${DateTime.now().millisecondsSinceEpoch}',
          'id_oficial_ref': oficial.id,
          'nombre_oficial': oficial.nombre,
          'fecha_hora': UtcTimeUtils.nowIso(),
          'reo_asignado': oficial.reoAsignado,
          'ubicacion_actual': pos == null
              ? 'SIN_DATOS_GPS'
              : '${pos.latitude},${pos.longitude}',
          'latitud': pos?.latitude,
          'longitud': pos?.longitude,
          'distancia_metros': monitoring.distanceToReo,
          'estado_alerta': 'ALERTA',
          'nivel_bateria': monitoring.batteryLevel,
          'gps_real': monitoring.isGpsActive,
          'movimiento': false,
          'parte_novedad':
              'INC_FALLBACK|OFICIAL_CERRO_VENTANA_PARTE|$slotLabel',
          'imei': auth.deviceId,
          'grupo': oficial.grupo.toUpperCase(),
        });
      }
    }
    novedadController.dispose();
  }

  Future<void> _sendEmergencyPing() async {
    await context.read<RadioProvider>().sendEmergencyPing();
    if (!mounted) return;
    _showInfo('Emergencia', 'Alerta de emergencia enviada al supervisor.');
  }

  Future<bool> _enforceOperationalPrerequisites() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.enforceOperationalPrerequisites();
    if (!mounted || ok) return ok;
    _monitoringProvider.stopMonitoring();
    _radioProvider.stop();
    _showInfo(
      'Permisos requeridos',
      auth.errorMessage ??
          'Faltan permisos o GPS. Debes completar la configuración.',
    );
    return false;
  }

  Future<void> _handlePendingNotificationAction() async {
    if (_handlingNotificationAction || !mounted) return;
    _handlingNotificationAction = true;
    try {
      final actionData = await NotificationService.takePendingAction();
      if (!mounted || actionData == null) return;

      final action = (actionData['action'] ?? '').toUpperCase();
      final data = actionData['data'] ?? '';
      if (action == NotificationService.actionOpenRadio) {
        _openRadio();
        return;
      }
      if (action == NotificationService.actionOpenParteObligatorio) {
        await NotificationService.cancelParteOficialAlert();
        final forcedSlot = DateTime.tryParse(data);
        await _showParteDialog(forcedSlot: forcedSlot);
        return;
      }
      if (action == NotificationService.actionOpenParteSorpresa) {
        await NotificationService.cancelParteSorpresaAlert();
        await _openPendingParteSorpresa(preferId: data);
      }
    } catch (e) {
      debugPrint('HomeScreen _handlePendingNotificationAction error: $e');
    } finally {
      _handlingNotificationAction = false;
    }
  }

  Future<void> _runGuarded(
    String tag,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      debugPrint('HomeScreen guarded task failed ($tag): $e');
    }
  }

  Future<void> _openPendingParteSorpresa({String? preferId}) async {
    if (_showingParteSorpresaDialog || !mounted) return;

    final auth = context.read<AuthProvider>();
    final monitoring = context.read<MonitoringProvider>();
    final oficialId = auth.oficial?.id;
    if (oficialId == null || oficialId.isEmpty) return;

    Map<String, dynamic>? parte = monitoring.pendingParteSorpresa;
    if (parte == null) {
      final pending = await _repository.getPendingPartesSorpresaByOficial(
        idOficial: oficialId,
        limit: 20,
      );
      if (pending.isEmpty) {
        if (mounted) {
          _showInfo('Parte sorpresa', 'No hay solicitudes pendientes.');
        }
        return;
      }
      if (preferId != null && preferId.trim().isNotEmpty) {
        parte = pending.firstWhere(
          (row) => (row['id_sorpresa'] ?? '').toString() == preferId.trim(),
          orElse: () => pending.first,
        );
      } else {
        parte = pending.first;
      }
    }

    _showingParteSorpresaDialog = true;
    try {
      final idSorpresa = (parte['id_sorpresa'] ?? '').toString().trim();
      if (idSorpresa.isNotEmpty) {
        await _repository.markParteLeido(idSorpresa);
      }
      await NotificationService.cancelParteSorpresaAlert();
      await _showParteDialog(parteSorpresa: parte);
    } finally {
      _showingParteSorpresaDialog = false;
    }
  }

  List<double> _buildHudSpectrumLevels({
    required MonitoringProvider monitoring,
    required RadioProvider radio,
  }) {
    if (monitoring.hudSpectrumLevels.isNotEmpty) {
      return monitoring.hudSpectrumLevels;
    }

    final battery = (monitoring.batteryLevel / 100).clamp(0.0, 1.0).toDouble();
    final gps = monitoring.isGpsActive ? 0.92 : 0.24;
    final reports = (monitoring.todayReportCount / 20).clamp(0.10, 1.0).toDouble();
    final alerts = (monitoring.todayAlertCount / 8).clamp(0.10, 1.0).toDouble();
    final inconsistencies =
        (monitoring.todayInconsistencyCount / 8).clamp(0.10, 1.0).toDouble();
    final radioUnread = (radio.unreadCount / 6).clamp(0.08, 1.0).toDouble();
    final distance = monitoring.distanceToReo == null
        ? 0.5
        : (1 - (monitoring.distanceToReo! / 900)).clamp(0.10, 1.0).toDouble();
    final anchors = <double>[
      gps,
      battery,
      reports,
      1 - alerts,
      1 - inconsistencies,
      1 - radioUnread,
      distance,
      reports,
      battery,
      gps,
    ];

    const bars = 20;
    return List<double>.generate(bars, (index) {
      final left = anchors[index % anchors.length];
      final right = anchors[(index + 1) % anchors.length];
      return ((left * 0.62) + (right * 0.38)).clamp(0.12, 1.0);
    });
  }

  String _formatAgeShort(int totalSeconds) {
    if (totalSeconds <= 0) return 'ahora';
    if (totalSeconds < 60) return '${totalSeconds}s';
    final minutes = totalSeconds ~/ 60;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remMin = minutes % 60;
    return remMin == 0 ? '${hours}h' : '${hours}h ${remMin}m';
  }

  void _showInfo(String title, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$title: $message')));
  }
}

class _PanelTitle extends StatelessWidget {
  final String text;
  const _PanelTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Orbitron',
        color: AppTheme.primary,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SignalIcon extends StatefulWidget {
  final Color color;
  final bool pulse;
  const _SignalIcon({required this.color, required this.pulse});

  @override
  State<_SignalIcon> createState() => _SignalIconState();
}

class _SignalIconState extends State<_SignalIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _SignalIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
    if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final glow = widget.pulse ? (0.2 + (_controller.value * 0.7)) : 0.2;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                  color: widget.color.withValues(alpha: glow * 0.5),
                  blurRadius: 8)
            ],
          ),
        );
      },
    );
  }
}

class _HudSpectrumPainter extends CustomPainter {
  final double phase;
  final Color color;
  final List<double> levels;

  const _HudSpectrumPainter({
    required this.phase,
    required this.color,
    required this.levels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bars = levels.isEmpty ? 20 : levels.length;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = color.withValues(alpha: 0.16);
    final paint = Paint()..style = PaintingStyle.fill;
    final w = size.width / bars;
    final centerX = size.width / 2;

    final centerLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.30);

    for (int row = 1; row <= 4; row++) {
      final y = size.height * (row / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), bg);
    }
    canvas.drawLine(
        Offset(centerX, 0), Offset(centerX, size.height), centerLinePaint);

    final pulseAlpha =
        (0.20 + (math.sin(phase * math.pi * 2) * 0.10)).clamp(0.10, 0.36);
    final globalPulse =
        ((math.sin(phase * math.pi * 2) + 1) / 2).clamp(0.0, 1.0) * 0.07;
    final corePulse = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: pulseAlpha);
    canvas.drawCircle(
      Offset(centerX, size.height * 0.56),
      12 + (math.sin(phase * math.pi * 2).abs() * 5),
      corePulse,
    );

    for (int i = 0; i < bars; i++) {
      final x = i * w;
      final base = levels.isEmpty ? 0.5 : levels[i].clamp(0.12, 1.0);
      final barCenter = x + (w / 2);
      final centerWeight =
          (1 - ((barCenter - centerX).abs() / centerX)).clamp(0.0, 1.0);
      final amp =
          (base + globalPulse + (centerWeight * 0.12)).clamp(0.12, 1.0);
      final h = size.height * (0.10 + (amp * 0.86));
      final top = size.height - h;
      final baseAlpha =
          (0.34 + (amp * 0.42) + (centerWeight * 0.16)).clamp(0.0, 1.0);
      paint.shader = ui.Gradient.linear(
        Offset(0, top),
        Offset(0, size.height),
        <Color>[
          color.withValues(alpha: (baseAlpha * 0.86).clamp(0.0, 1.0)),
          color.withValues(alpha: (baseAlpha * 0.42).clamp(0.0, 1.0)),
        ],
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 0.9, top, w - 1.8, h),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HudSpectrumPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.levels != levels;
  }
}

class _HudCandlesPainter extends CustomPainter {
  final double phase;
  final Color color;
  final List<double> trend;
  final bool gpsActive;

  const _HudCandlesPainter({
    required this.phase,
    required this.color,
    required this.trend,
    required this.gpsActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const candles = 9;
    final candleWidth = size.width / (candles * 1.18);
    final spacing = (size.width - (candles * candleWidth)) / (candles - 1);
    final bodyPaint = Paint()..style = PaintingStyle.fill;
    final wickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.18);

    for (int row = 1; row <= 4; row++) {
      final y = size.height * (row / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final source = trend.isEmpty
        ? List<double>.filled(candles * 2, gpsActive ? 0.60 : 0.38)
        : trend.map((v) => v.clamp(0.0, 1.0)).toList(growable: false);
    final bucketSize = source.length / candles;

    double yFrom(double normalized) {
      final safe = normalized.clamp(0.0, 1.0);
      return size.height * (0.90 - (safe * 0.78));
    }

    for (int i = 0; i < candles; i++) {
      final x = i * (candleWidth + spacing);
      final start = (i * bucketSize).floor().clamp(0, source.length - 1);
      final rawEnd = ((i + 1) * bucketSize).ceil();
      final end = rawEnd.clamp(start + 1, source.length);
      final segment = source.sublist(start, end);
      final openNorm = segment.first;
      final closeNorm = segment.last;
      final highNorm = segment.reduce(math.max);
      final lowNorm = segment.reduce(math.min);

      final open = yFrom(openNorm);
      var close = yFrom(closeNorm);
      final high = yFrom(highNorm);
      final low = yFrom(lowNorm);

      var bodyTop = math.min(open, close);
      var bodyBottom = math.max(open, close);
      const minBody = 11.0;
      if ((bodyBottom - bodyTop) < minBody) {
        final mid = (bodyTop + bodyBottom) / 2;
        bodyTop = (mid - (minBody / 2)).clamp(4.0, size.height - 10.0);
        bodyBottom = (mid + (minBody / 2)).clamp(10.0, size.height - 4.0);
        close = bodyTop == open ? bodyBottom : bodyTop;
      }
      final isUp = close < open;
      final quality = ((openNorm + closeNorm + highNorm + lowNorm) / 4)
          .clamp(0.0, 1.0);
      final candleColor = quality < 0.35
          ? AppTheme.error
          : quality < 0.60
              ? AppTheme.warning
              : isUp
                  ? (gpsActive ? AppTheme.success : AppTheme.primary)
                  : color;

      wickPaint.color = candleColor.withValues(alpha: 0.9);
      canvas.drawLine(
        Offset(x + (candleWidth / 2), high.clamp(2.0, size.height - 4.0)),
        Offset(x + (candleWidth / 2), low.clamp(4.0, size.height - 2.0)),
        wickPaint,
      );

      bodyPaint.color = candleColor.withValues(alpha: 0.82);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, bodyTop, x + candleWidth, bodyBottom),
          const Radius.circular(3),
        ),
        bodyPaint,
      );

      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = candleColor.withValues(alpha: 0.55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, bodyTop, x + candleWidth, bodyBottom),
          const Radius.circular(3),
        ),
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HudCandlesPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.trend != trend ||
        oldDelegate.gpsActive != gpsActive;
  }
}

class _HudGrid3DPainter extends CustomPainter {
  final double phase;
  final Color color;
  final List<double> lockTrend;
  final double lateralDrift;
  final bool gpsActive;

  const _HudGrid3DPainter({
    required this.phase,
    required this.color,
    required this.lockTrend,
    required this.lateralDrift,
    required this.gpsActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * 0.22;
    final centerX = size.width / 2;
    final latestLock =
        lockTrend.isEmpty ? 0.5 : lockTrend.last.clamp(0.0, 1.0).toDouble();
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final areaPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.07 + (latestLock * 0.10));

    final path = ui.Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(centerX, horizon)
      ..close();
    canvas.drawPath(path, areaPaint);

    for (int i = 0; i < 10; i++) {
      final t = ((i / 9) + phase) % 1;
      final y = horizon + (t * t) * (size.height - horizon);
      p.color = color.withValues(alpha: 0.16 + ((1 - t) * 0.38));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }

    for (double x = -size.width; x <= size.width * 2; x += 20) {
      final dx = x - centerX;
      final topX = centerX + (dx * 0.28);
      p.color = color.withValues(alpha: 0.24);
      canvas.drawLine(Offset(x, size.height), Offset(topX, horizon), p);
    }

    final pulse = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = (gpsActive ? AppTheme.warning : AppTheme.error)
          .withValues(alpha: 0.75);
    final r = 8 + ((1 - latestLock) * 8) + (math.sin(phase * math.pi).abs() * 2);
    final pulseCenter = Offset(
      centerX + (lateralDrift.clamp(-1.0, 1.0) * size.width * 0.28),
      horizon + ((1 - latestLock) * (size.height - horizon - 10)),
    );
    final trendPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withValues(alpha: 0.65);
    if (lockTrend.length > 1) {
      final track = ui.Path();
      for (int i = 0; i < lockTrend.length; i++) {
        final x = (i / (lockTrend.length - 1)) * size.width;
        final value = lockTrend[i].clamp(0.0, 1.0);
        final y = horizon + ((1 - value) * (size.height - horizon - 6));
        if (i == 0) {
          track.moveTo(x, y);
        } else {
          track.lineTo(x, y);
        }
      }
      canvas.drawPath(track, trendPaint);
    }

    canvas.drawCircle(
      pulseCenter,
      r,
      pulse,
    );

    final coreFill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.18 + (latestLock * 0.22));
    canvas.drawCircle(
      pulseCenter,
      10 + (latestLock * 5) + (math.sin(phase * math.pi * 2).abs() * 3),
      coreFill,
    );

    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: 0.34);
    final coreY = pulseCenter.dy;
    final coreX = pulseCenter.dx;
    canvas.drawLine(
        Offset(coreX - 22, coreY), Offset(coreX + 22, coreY), crossPaint);
    canvas.drawLine(
        Offset(coreX, coreY - 22), Offset(coreX, coreY + 22), crossPaint);
  }

  @override
  bool shouldRepaint(covariant _HudGrid3DPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.color != color ||
        oldDelegate.lockTrend != lockTrend ||
        oldDelegate.lateralDrift != lateralDrift ||
        oldDelegate.gpsActive != gpsActive;
  }
}

class _MiniMap extends StatelessWidget {
  final double? officialLat;
  final double? officialLng;
  final List<double>? controlCoords;

  const _MiniMap(
      {required this.officialLat,
      required this.officialLng,
      required this.controlCoords});

  @override
  Widget build(BuildContext context) {
    final official = (officialLat == null || officialLng == null)
        ? null
        : LatLng(officialLat!, officialLng!);
    final control = (controlCoords == null || controlCoords!.length != 2)
        ? null
        : LatLng(controlCoords![0], controlCoords![1]);

    LatLng center = const LatLng(-21.534034, -64.737505);
    if (official != null) center = official;
    if (official == null && control != null) center = control;

    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: 15,
          minZoom: 10,
          maxZoom: 18,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sccp.mobile'),
          if (control != null)
            CircleLayer(circles: [
              CircleMarker(
                point: control,
                radius: 50,
                color: AppTheme.warning.withValues(alpha: 0.14),
                borderColor: AppTheme.warning,
                borderStrokeWidth: 2,
              ),
            ]),
          if (official != null && control != null)
            PolylineLayer(polylines: [
              Polyline(
                  points: [official, control],
                  color: AppTheme.primary.withValues(alpha: 0.82),
                  strokeWidth: 2.8),
            ]),
          MarkerLayer(markers: [
            if (control != null)
              Marker(
                  point: control,
                  width: 52,
                  height: 52,
                  child: const Icon(Icons.home, color: AppTheme.warning)),
            if (official != null)
              Marker(
                  point: official,
                  width: 52,
                  height: 52,
                  child: const Icon(Icons.person_pin_circle,
                      color: AppTheme.primary)),
          ]),
        ],
      ),
    );
  }
}
