import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/repositories/supabase_repository.dart';
import '../../data/services/background_service.dart';
import '../../data/services/notification_service.dart';
import '../../core/constants/supabase_config.dart';
import '../../core/utils/distance_calculator.dart';

class MonitoringProvider with ChangeNotifier {
  final SupabaseRepository _repository = SupabaseRepository();

  Position? _currentPosition;
  double? _distanceToReo;
  bool _isGpsActive = false;
  int _batteryLevel = 100;
  String _alertStatus = 'NORMAL';
  String _alertReason = 'Sin alertas activas';
  int _todayReportCount = 0;
  int _todayAlertCount = 0;
  int _todayInconsistencyCount = 0;
  int _todayPartesCount = 0;
  Map<String, dynamic>? _pendingParteSorpresa;
  List<double> _hudOperationalTrend = const [];
  List<double> _hudLockTrend = const [];
  List<double> _hudSpectrumLevels = const [];
  double _hudLateralDrift = 0;
  double _hudCadencePerHour = 0;
  int _hudLastReportAgeSec = 0;
  bool _hudHasSeriesData = false;

  StreamSubscription? _partesSorpresaSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _batteryTimer;
  Timer? _summaryTimer;
  Timer? _snapshotFallbackTimer;
  List<double>? _reoCoordenadas;
  String? _currentOficialId;
  String? _lastParteSorpresaAlertedId;

  Position? get currentPosition => _currentPosition;
  double? get distanceToReo => _distanceToReo;
  bool get isGpsActive => _isGpsActive;
  int get batteryLevel => _batteryLevel;
  String get alertStatus => _alertStatus;
  String get alertReason => _alertReason;
  int get todayReportCount => _todayReportCount;
  int get todayAlertCount => _todayAlertCount;
  int get todayInconsistencyCount => _todayInconsistencyCount;
  int get todayPartesCount => _todayPartesCount;
  Map<String, dynamic>? get pendingParteSorpresa => _pendingParteSorpresa;
  List<double> get hudOperationalTrend => _hudOperationalTrend;
  List<double> get hudLockTrend => _hudLockTrend;
  List<double> get hudSpectrumLevels => _hudSpectrumLevels;
  double get hudLateralDrift => _hudLateralDrift;
  double get hudCadencePerHour => _hudCadencePerHour;
  int get hudLastReportAgeSec => _hudLastReportAgeSec;
  bool get hudHasSeriesData => _hudHasSeriesData;

  void startMonitoring(String idOficial, {List<double>? reoCoordenadas}) {
    _reoCoordenadas = reoCoordenadas;
    _currentOficialId = idOficial;

    _positionSubscription?.cancel();
    _batteryTimer?.cancel();
    _summaryTimer?.cancel();
    _snapshotFallbackTimer?.cancel();
    _partesSorpresaSubscription?.cancel();

    _startDeviceMonitoring();
    _refreshOperationalSummary();
    _summaryTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshOperationalSummary(),
    );
    unawaited(_startSnapshotFallbackIfNeeded());

    _partesSorpresaSubscription =
        _repository.watchPartesSorpresa(idOficial).listen((partes) {
      if (partes.isNotEmpty) {
        _handleParteSorpresa(partes.first);
      }
    }, onError: (_) {
      // Silencioso: no derribar monitoreo por stream inestable.
    });
  }

  Future<void> _startSnapshotFallbackIfNeeded() async {
    try {
      if (kIsWeb) return;
      final serviceRunning = await FlutterBackgroundService().isRunning();
      if (serviceRunning) return;
      _snapshotFallbackTimer = Timer.periodic(
        SupabaseConfig.backgroundInterval,
        (_) => unawaited(BackgroundServiceManager.runOperationalSnapshotNow()),
      );
    } catch (_) {
      // Silencioso: fallback opcional.
    }
  }

  void stopMonitoring() {
    _partesSorpresaSubscription?.cancel();
    _partesSorpresaSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    _summaryTimer?.cancel();
    _summaryTimer = null;
    _snapshotFallbackTimer?.cancel();
    _snapshotFallbackTimer = null;
    _isGpsActive = false;
    _distanceToReo = null;
    _alertStatus = 'NORMAL';
    _alertReason = 'Sin alertas activas';
    _todayReportCount = 0;
    _todayAlertCount = 0;
    _todayInconsistencyCount = 0;
    _todayPartesCount = 0;
    _pendingParteSorpresa = null;
    _hudOperationalTrend = const [];
    _hudLockTrend = const [];
    _hudSpectrumLevels = const [];
    _hudLateralDrift = 0;
    _hudCadencePerHour = 0;
    _hudLastReportAgeSec = 0;
    _hudHasSeriesData = false;
    _currentOficialId = null;
    _lastParteSorpresaAlertedId = null;
    notifyListeners();
  }

  Future<void> _startDeviceMonitoring() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _isGpsActive = false;
      notifyListeners();
      return;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _isGpsActive = false;
      notifyListeners();
      return;
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      updatePosition,
      onError: (_) {
        _isGpsActive = false;
        notifyListeners();
      },
    );

    _updateBatteryLevel();
    _batteryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _updateBatteryLevel(),
    );
  }

  void _handleParteSorpresa(Map<String, dynamic> parte) {
    _pendingParteSorpresa = parte;
    _alertStatus = 'PARTE_SORPRESA';
    _alertReason = (parte['razon']?.toString().trim().isNotEmpty ?? false)
        ? 'Parte sorpresa: ${parte['razon']}'
        : 'Parte sorpresa pendiente';
    notifyListeners();
    final id = (parte['id_sorpresa'] ?? '').toString().trim();
    final estado = (parte['estado'] ?? '').toString().trim().toUpperCase();
    final isNuevo = estado.isEmpty || estado == 'NUEVO' || estado == 'NUEVA';
    if (isNuevo && id.isNotEmpty && id != _lastParteSorpresaAlertedId) {
      _lastParteSorpresaAlertedId = id;
      unawaited(_notifyParteSorpresa(parte));
    }
  }

  Future<void> _notifyParteSorpresa(Map<String, dynamic> parte) async {
    await NotificationService.showParteSorpresaAlert(parte);
  }

  void clearPendingParteSorpresa([String? idSorpresa]) {
    if (_pendingParteSorpresa == null) return;
    if (idSorpresa != null && idSorpresa.isNotEmpty) {
      final currentId =
          (_pendingParteSorpresa!['id_sorpresa'] ?? '').toString();
      if (currentId != idSorpresa) return;
    }
    _pendingParteSorpresa = null;
    if (_alertStatus == 'PARTE_SORPRESA') {
      _alertStatus = 'NORMAL';
      _alertReason = 'Sin alertas activas';
    }
    notifyListeners();
  }

  void updatePosition(Position position) {
    _currentPosition = position;
    _isGpsActive = !position.isMocked;
    if (position.isMocked) {
      _alertStatus = 'CRITICO';
      _alertReason = 'GPS simulado detectado';
      notifyListeners();
      return;
    }

    if (_reoCoordenadas != null && _reoCoordenadas!.length == 2) {
      updateDistance(
        DistanceCalculator.calculateDistance(
          position.latitude,
          position.longitude,
          _reoCoordenadas![0],
          _reoCoordenadas![1],
        ),
      );
      return;
    }

    _alertStatus = 'NORMAL';
    _alertReason = 'Ubicacion recibida. Sin coordenadas de control.';
    notifyListeners();
  }

  void updateDistance(double distance) {
    _distanceToReo = distance;
    if (distance > SupabaseConfig.maxDistanceMeters) {
      _alertStatus = 'FUERA_RANGO';
      _alertReason =
          'Distancia ${distance.toStringAsFixed(0)}m supera ${SupabaseConfig.maxDistanceMeters.toStringAsFixed(0)}m.';
    } else {
      _alertStatus = 'NORMAL';
      _alertReason =
          'Dentro de rango (${distance.toStringAsFixed(0)}m del control).';
    }
    notifyListeners();
  }

  void updateBattery(int level) {
    _batteryLevel = level;
    notifyListeners();
  }

  Future<void> _updateBatteryLevel() async {
    try {
      final level = await Battery().batteryLevel;
      if (level != _batteryLevel) {
        _batteryLevel = level;
        notifyListeners();
      }
    } catch (_) {
      // Silencioso
    }
  }

  Future<void> _refreshOperationalSummary() async {
    try {
      final idOficial = _currentOficialId;
      if (idOficial == null || idOficial.isEmpty) return;

      final snapshot = await _repository.getTodayOperationalSummary(
        idOficial: idOficial,
      );
      _todayReportCount = snapshot['reportes'] ?? 0;
      _todayAlertCount = snapshot['alertas'] ?? 0;
      _todayInconsistencyCount = snapshot['inconsistencias'] ?? 0;
      _todayPartesCount = snapshot['partes'] ?? 0;

      final trendSnapshot = await _repository.getMonitoringTrendSnapshot(
        idOficial: idOficial,
        now: DateTime.now(),
      );
      _applyHudSeries(
        reportsRaw: (trendSnapshot['reportes'] as List?) ?? const [],
        inconsistenciesRecent:
            (trendSnapshot['inconsistencias'] as num?)?.toInt() ?? 0,
        partesRecent: (trendSnapshot['partes'] as num?)?.toInt() ?? 0,
      );

      notifyListeners();
    } catch (_) {
      // Silencioso: evita cortar telemetria UI por fallo de resumen.
    }
  }

  void _applyHudSeries({
    required List reportsRaw,
    required int inconsistenciesRecent,
    required int partesRecent,
  }) {
    final now = DateTime.now();
    final reports = reportsRaw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    if (reports.isEmpty) {
      _hudHasSeriesData = false;
      _hudOperationalTrend = const [];
      _hudLockTrend = const [];
      _hudSpectrumLevels = _buildFallbackSpectrum();
      _hudLateralDrift = 0;
      _hudCadencePerHour = 0;
      _hudLastReportAgeSec = 0;
      return;
    }

    reports.sort((a, b) {
      final at = _parseDate(a['fecha_hora']);
      final bt = _parseDate(b['fecha_hora']);
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return at.compareTo(bt);
    });

    final operationalScores = <double>[];
    final lockScores = <double>[];
    final batteryScores = <double>[];
    final riskScores = <double>[];
    final latitudes = <double>[];
    final longitudes = <double>[];
    DateTime? firstTs;
    DateTime? lastTs;

    for (final row in reports) {
      final ts = _parseDate(row['fecha_hora']);
      if (ts != null) {
        firstTs ??= ts;
        lastTs = ts;
      }

      final battery = ((row['nivel_bateria'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 100.0);
      final batteryNorm = (battery / 100).clamp(0.0, 1.0);
      final gpsNorm = _isGpsReal(row['gps_real']) ? 1.0 : 0.12;
      final distanceMeters = (row['distancia_metros'] as num?)?.toDouble();
      final distanceNorm = distanceMeters == null
          ? 0.45
          : (1 - (distanceMeters / SupabaseConfig.maxDistanceMeters))
              .clamp(0.0, 1.0);
      final riskNorm = _alertRisk(row['estado_alerta']);
      final score =
          ((batteryNorm * 0.34) + (gpsNorm * 0.28) + (distanceNorm * 0.30) +
                  ((1 - riskNorm) * 0.08))
              .clamp(0.0, 1.0);
      final lock = ((distanceNorm * 0.72) + (gpsNorm * 0.28)).clamp(0.0, 1.0);

      operationalScores.add(score);
      lockScores.add(lock);
      batteryScores.add(batteryNorm);
      riskScores.add(riskNorm);

      final lat = (row['latitud'] as num?)?.toDouble();
      final lng = (row['longitud'] as num?)?.toDouble();
      if (lat != null && lat.isFinite) latitudes.add(lat);
      if (lng != null && lng.isFinite) longitudes.add(lng);
    }

    _hudHasSeriesData = operationalScores.isNotEmpty;
    _hudOperationalTrend = _resampleSeries(operationalScores, target: 36);
    _hudLockTrend = _resampleSeries(lockScores, target: 24);

    final scoreBars = _resampleSeries(operationalScores, target: 20);
    final lockBars = _resampleSeries(lockScores, target: 20);
    final batteryBars = _resampleSeries(batteryScores, target: 20);
    final riskBars = _resampleSeries(riskScores, target: 20);
    final inconsistenciesPenalty =
        (inconsistenciesRecent / 10).clamp(0.0, 0.25).toDouble();
    final partesBoost = (partesRecent / 12).clamp(0.0, 0.14).toDouble();

    _hudSpectrumLevels = List<double>.generate(20, (i) {
      final base =
          (scoreBars[i] * 0.48) + (lockBars[i] * 0.26) + (batteryBars[i] * 0.16);
      final riskPenalty = riskBars[i] * 0.24;
      return (base - riskPenalty - inconsistenciesPenalty + partesBoost)
          .clamp(0.10, 1.0);
    });

    _hudLateralDrift = _computeLateralDrift(longitudes);

    if (lastTs != null) {
      _hudLastReportAgeSec = math.max(0, now.difference(lastTs).inSeconds);
    } else {
      _hudLastReportAgeSec = 0;
    }

    if (firstTs != null && lastTs != null && lastTs.isAfter(firstTs)) {
      final spanHours = lastTs.difference(firstTs).inMinutes / 60.0;
      final cadence = reports.length / spanHours;
      _hudCadencePerHour = cadence.isFinite ? cadence.clamp(0.0, 20.0) : 0.0;
    } else {
      _hudCadencePerHour = reports.isNotEmpty ? reports.length.toDouble() : 0.0;
    }

    if (_hudSpectrumLevels.isEmpty) {
      _hudSpectrumLevels = _buildFallbackSpectrum();
    }
  }

  List<double> _buildFallbackSpectrum() {
    final gps = _isGpsActive ? 0.9 : 0.24;
    final battery = (_batteryLevel / 100).clamp(0.0, 1.0).toDouble();
    final reports = (_todayReportCount / 20).clamp(0.08, 1.0).toDouble();
    final alerts = (_todayAlertCount / 8).clamp(0.08, 1.0).toDouble();
    final incs = (_todayInconsistencyCount / 8).clamp(0.08, 1.0).toDouble();
    final dist = _distanceToReo == null
        ? 0.5
        : (1 - (_distanceToReo! / 900)).clamp(0.08, 1.0).toDouble();
    final anchors = <double>[
      gps,
      battery,
      reports,
      1 - alerts,
      1 - incs,
      dist,
      reports,
      battery,
    ];
    return List<double>.generate(20, (index) {
      final left = anchors[index % anchors.length];
      final right = anchors[(index + 1) % anchors.length];
      return ((left * 0.62) + (right * 0.38)).clamp(0.12, 1.0);
    });
  }

  List<double> _resampleSeries(
    List<double> values, {
    required int target,
    double fallback = 0.5,
  }) {
    if (target <= 0) return const [];
    if (values.isEmpty) {
      return List<double>.filled(target, fallback);
    }
    if (values.length == 1) {
      return List<double>.filled(target, values.first.clamp(0.0, 1.0));
    }
    return List<double>.generate(target, (i) {
      final pos = (i * (values.length - 1)) / (target - 1);
      final left = pos.floor();
      final right = pos.ceil();
      final t = pos - left;
      final l = values[left].clamp(0.0, 1.0);
      final r = values[right].clamp(0.0, 1.0);
      return (l + ((r - l) * t)).clamp(0.0, 1.0);
    });
  }

  DateTime? _parseDate(dynamic raw) {
    final text = raw?.toString();
    if (text == null || text.trim().isEmpty) return null;
    final dt = DateTime.tryParse(text.trim());
    return dt?.toLocal();
  }

  bool _isGpsReal(dynamic raw) {
    if (raw is bool) return raw;
    final value = raw?.toString().trim().toLowerCase();
    return value == 'true' || value == '1' || value == 't' || value == 'si';
  }

  double _alertRisk(dynamic raw) {
    final status = raw?.toString().trim().toUpperCase() ?? 'NORMAL';
    if (status == 'CRITICO') return 0.95;
    if (status == 'ALERTA') return 0.60;
    if (status == 'FUERA_RANGO') return 0.85;
    return 0.12;
  }

  double _computeLateralDrift(List<double> longitudes) {
    if (longitudes.length < 2) return 0;
    final tail = longitudes.sublist(math.max(0, longitudes.length - 8));
    final mean = tail.reduce((a, b) => a + b) / tail.length;
    final delta = tail.last - mean;
    return (delta / 0.0012).clamp(-1.0, 1.0);
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}
