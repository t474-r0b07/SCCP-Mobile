import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/monitoring_provider.dart';
import '../widgets/huc_background.dart';
import '../widgets/hud_screen_entry.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MAPA DE CUSTODIA'),
      ),
      body: HucBackground(
        child: SafeArea(
          child: HudScreenEntry(
            child: const OperationalMapPanel(),
          ),
        ),
      ),
    );
  }
}

class OperationalMapPanel extends StatelessWidget {
  final bool compact;

  const OperationalMapPanel({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_JurisdictionArea>>(
      future: _JurisdictionKmlCache.future,
      builder: (context, snapshot) {
        final jurisdictionAreas = snapshot.data ?? const <_JurisdictionArea>[];

        return Consumer2<AuthProvider, MonitoringProvider>(
          builder: (context, auth, monitoring, _) {
            final reo = auth.reoAsignado;
            final position = monitoring.currentPosition;
            final reoPoint = reo?.coordenadas == null
                ? null
                : LatLng(reo!.coordenadas![0], reo.coordenadas![1]);
            final officialPoint = position == null
                ? null
                : LatLng(position.latitude, position.longitude);
            final basePoints = _dedupeBasePins(_operationalBasePins);
            final pinKeys = <String>{};
            final markers = <Marker>[];

            LatLng center = const LatLng(-21.534034, -64.737505);

            if (officialPoint != null) {
              center = officialPoint;
            } else if (reoPoint != null) {
              center = reoPoint;
            }

            for (final base in basePoints) {
              final key = _pinKey(base.name, base.point);
              if (pinKeys.contains(key)) continue;
              pinKeys.add(key);
              markers.add(
                Marker(
                  point: base.point,
                  width: compact ? 80 : 90,
                  height: compact ? 56 : 64,
                  child: _BaseMarker(label: base.name),
                ),
              );
            }

            if (!compact) {
              for (final area in jurisdictionAreas) {
                final key = _pinKey('area_${area.name}', area.center);
                if (pinKeys.contains(key)) continue;
                pinKeys.add(key);
                markers.add(
                  Marker(
                    point: area.center,
                    width: 114,
                    height: 30,
                    child: _AreaLabel(
                      label: area.name,
                      color: area.color,
                    ),
                  ),
                );
              }
            }

            if (reoPoint != null) {
              final key = _pinKey('control_reo', reoPoint);
              if (!pinKeys.contains(key)) {
                pinKeys.add(key);
                markers.add(
                  Marker(
                    point: reoPoint,
                    width: compact ? 86 : 92,
                    height: compact ? 66 : 72,
                    child: const _ControlMarker(
                      label: 'CONTROL REO',
                      color: AppTheme.warning,
                      icon: Icons.home,
                    ),
                  ),
                );
              }
            }

            if (officialPoint != null) {
              final key = _pinKey('oficial', officialPoint);
              if (!pinKeys.contains(key)) {
                pinKeys.add(key);
                markers.add(
                  Marker(
                    point: officialPoint,
                    width: compact ? 86 : 92,
                    height: compact ? 66 : 72,
                    child: _ControlMarker(
                      label: 'ULTIMA UBICACION',
                      color: auth.oficial?.grupo == 'alfa'
                          ? AppTheme.primary
                          : AppTheme.secondary,
                      icon: Icons.person_pin_circle,
                    ),
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.all(compact ? 8 : 12),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GlassPanel(
                      borderRadius: BorderRadius.circular(20),
                      padding: EdgeInsets.zero,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: compact ? 14.6 : 15.0,
                            maxZoom: 18.0,
                            minZoom: 10.0,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.sccp.mobile',
                            ),
                            if (jurisdictionAreas.isNotEmpty)
                              PolygonLayer(
                                polygons: jurisdictionAreas
                                    .map(
                                      (area) => Polygon(
                                        points: area.points,
                                        color: area.color.withValues(
                                            alpha: compact ? 0.20 : 0.30),
                                        borderColor: area.color.withValues(
                                            alpha: compact ? 0.82 : 0.95),
                                        borderStrokeWidth: compact ? 2.2 : 2.8,
                                      ),
                                    )
                                    .toList(),
                              ),
                            if (reoPoint != null)
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: reoPoint,
                                    radius: 50,
                                    color: AppTheme.warning
                                        .withValues(alpha: 0.16),
                                    borderColor: AppTheme.warning,
                                    borderStrokeWidth: 2,
                                  ),
                                ],
                              ),
                            if (officialPoint != null && reoPoint != null)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [officialPoint, reoPoint],
                                    color:
                                        AppTheme.primary.withValues(alpha: 0.8),
                                    strokeWidth: 3,
                                  ),
                                ],
                              ),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    right: 12,
                    child: _TopPanel(
                      groupLabel: (auth.oficial?.grupo ?? '--').toUpperCase(),
                      isGpsActive: monitoring.isGpsActive,
                      alertStatus: monitoring.alertStatus,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _BottomPanel(
                      batteryLevel: monitoring.batteryLevel,
                      distanceToReo: monitoring.distanceToReo,
                      hasReoReference: reo?.coordenadas != null,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TopPanel extends StatelessWidget {
  final String groupLabel;
  final bool isGpsActive;
  final String alertStatus;

  const _TopPanel({
    required this.groupLabel,
    required this.isGpsActive,
    required this.alertStatus,
  });

  @override
  Widget build(BuildContext context) {
    final critical = alertStatus != 'NORMAL';

    return GlassPanel(
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _MiniPill(
                  icon: Icons.groups,
                  label: 'GRUPO $groupLabel',
                  color: AppTheme.primary,
                ),
                _MiniPill(
                  icon: Icons.gps_fixed,
                  label: isGpsActive ? 'GPS OK' : 'GPS OFF',
                  color: isGpsActive ? AppTheme.success : AppTheme.error,
                ),
                _MiniPill(
                  icon: Icons.warning_amber,
                  label: alertStatus,
                  color: critical ? AppTheme.error : AppTheme.success,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  final int batteryLevel;
  final double? distanceToReo;
  final bool hasReoReference;

  const _BottomPanel({
    required this.batteryLevel,
    required this.distanceToReo,
    required this.hasReoReference,
  });

  @override
  Widget build(BuildContext context) {
    final distanceLabel = hasReoReference
        ? (distanceToReo == null
            ? '--'
            : '${distanceToReo!.toStringAsFixed(0)} m')
        : 'SIN REF';

    return GlassPanel(
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: _MetricTile(
              title: 'DISTANCIA',
              value: distanceLabel,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MetricTile(
              title: 'BATERIA',
              value: '$batteryLevel%',
              color: batteryLevel > 20 ? AppTheme.success : AppTheme.warning,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: _MetricTile(
              title: 'PERIMETRO',
              value: '50 m',
              color: AppTheme.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlMarker extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _ControlMarker({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.black, size: 18),
        ),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.8)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _BaseMarker extends StatelessWidget {
  final String label;

  const _BaseMarker({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F5FF),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF3A4D7A), width: 1.8),
          ),
          child: const Icon(
            Icons.military_tech,
            color: Color(0xFF2E3C60),
            size: 16,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.66),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _AreaLabel extends StatelessWidget {
  final String label;
  final Color color;

  const _AreaLabel({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.72)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _pinKey(String name, LatLng point) {
  return '${name.toUpperCase()}_${point.latitude.toStringAsFixed(6)}_${point.longitude.toStringAsFixed(6)}';
}

List<_OperationalBasePin> _dedupeBasePins(List<_OperationalBasePin> pins) {
  final keys = <String>{};
  final result = <_OperationalBasePin>[];
  for (final pin in pins) {
    final key = _pinKey(pin.name, pin.point);
    if (keys.add(key)) {
      result.add(pin);
    }
  }
  return result;
}

class _OperationalBasePin {
  final String name;
  final LatLng point;

  const _OperationalBasePin({
    required this.name,
    required this.point,
  });
}

class _JurisdictionArea {
  final String name;
  final List<LatLng> points;
  final LatLng center;
  final Color color;

  const _JurisdictionArea({
    required this.name,
    required this.points,
    required this.center,
    required this.color,
  });
}

class _JurisdictionKmlCache {
  static final Future<List<_JurisdictionArea>> future = _load();

  static Future<List<_JurisdictionArea>> _load() async {
    try {
      final xml =
          await rootBundle.loadString('assets/maps/jurisdicciones_epis.kml');
      final placemarkRegex = RegExp(
        r'<Placemark>([\s\S]*?)</Placemark>',
        caseSensitive: false,
      );
      final nameRegex =
          RegExp(r'<name>([\s\S]*?)</name>', caseSensitive: false);
      final coordsRegex = RegExp(
        r'<coordinates>([\s\S]*?)</coordinates>',
        caseSensitive: false,
      );

      final palette = <Color>[
        const Color(0xFF1DE9B6),
        const Color(0xFF29B6F6),
        const Color(0xFFFFCA28),
        const Color(0xFF7E57C2),
        const Color(0xFFEC407A),
        const Color(0xFF66BB6A),
      ];

      final areas = <_JurisdictionArea>[];
      var colorIndex = 0;

      for (final pm in placemarkRegex.allMatches(xml)) {
        final block = pm.group(1) ?? '';
        if (!block.toLowerCase().contains('<polygon>')) {
          continue;
        }

        final rawName = nameRegex.firstMatch(block)?.group(1) ?? 'JURISDICCION';
        final name = rawName.trim().replaceAll(RegExp(r'\s+'), ' ');
        final rawCoords = coordsRegex.firstMatch(block)?.group(1);
        if (rawCoords == null || rawCoords.trim().isEmpty) {
          continue;
        }

        final points = <LatLng>[];
        final chunks = rawCoords.trim().split(RegExp(r'\s+'));
        for (final chunk in chunks) {
          final parts = chunk.split(',');
          if (parts.length < 2) continue;
          final lng = double.tryParse(parts[0].trim());
          final lat = double.tryParse(parts[1].trim());
          if (lat == null || lng == null) continue;
          points.add(LatLng(lat, lng));
        }

        if (points.length < 3) continue;
        final center = _centroid(points);
        areas.add(
          _JurisdictionArea(
            name: name,
            points: points,
            center: center,
            color: palette[colorIndex % palette.length],
          ),
        );
        colorIndex++;
      }

      return areas;
    } catch (_) {
      return const <_JurisdictionArea>[];
    }
  }

  static LatLng _centroid(List<LatLng> points) {
    double lat = 0;
    double lng = 0;
    for (final p in points) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
  }
}

const List<_OperationalBasePin> _operationalBasePins = [
  _OperationalBasePin(
    name: 'EPI MORROS BLANCOS',
    point: LatLng(-21.5483132, -64.6989562),
  ),
  _OperationalBasePin(
    name: 'EPI CENTRAL',
    point: LatLng(-21.5336997, -64.7355013),
  ),
  _OperationalBasePin(
    name: 'EPI SENAC',
    point: LatLng(-21.5421969, -64.7466267),
  ),
  _OperationalBasePin(
    name: 'EPI MOTO MENDEZ',
    point: LatLng(-21.5348671, -64.7114756),
  ),
  _OperationalBasePin(
    name: 'EPI LOURDES',
    point: LatLng(-21.5135712, -64.7275175),
  ),
  _OperationalBasePin(
    name: 'API CHAPACOS',
    point: LatLng(-21.5123465, -64.7408198),
  ),
  _OperationalBasePin(
    name: 'FELCV',
    point: LatLng(-21.5321591, -64.7410211),
  ),
  _OperationalBasePin(
    name: 'FELCC',
    point: LatLng(-21.5293946, -64.7305313),
  ),
  _OperationalBasePin(
    name: 'COMANDO DPTAL.',
    point: LatLng(-21.534034, -64.737505),
  ),
  _OperationalBasePin(
    name: 'PAC',
    point: LatLng(-21.5186664, -64.7364318),
  ),
  _OperationalBasePin(
    name: 'BOMBEROS',
    point: LatLng(-21.5475722, -64.701675),
  ),
  _OperationalBasePin(
    name: 'TRANSITO',
    point: LatLng(-21.5307549, -64.7416813),
  ),
  _OperationalBasePin(
    name: 'DELTA',
    point: LatLng(-21.5262105, -64.7292879),
  ),
  _OperationalBasePin(
    name: 'DIPROVE',
    point: LatLng(-21.534958, -64.7123274),
  ),
];

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _MetricTile({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.2),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
