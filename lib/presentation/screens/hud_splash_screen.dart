import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/huc_background.dart';

PageRouteBuilder<T> buildHudTransitionRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 900),
    reverseTransitionDuration: const Duration(milliseconds: 500),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(fade);
      final scale = Tween<double>(
        begin: 0.985,
        end: 1,
      ).animate(fade);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(
            scale: scale,
            child: child,
          ),
        ),
      );
    },
  );
}

class HudSplashScreen extends StatefulWidget {
  final VoidCallback onCompleted;
  final Duration duration;
  final String title;
  final String subtitle;
  final String statusLabel;

  const HudSplashScreen({
    super.key,
    required this.onCompleted,
    this.duration = const Duration(seconds: 10),
    this.title = 'SCCP HUD',
    this.subtitle = 'BOOTSTRAP OPERATIVO',
    this.statusLabel = 'CARGANDO MODULO CENTRAL',
  });

  @override
  State<HudSplashScreen> createState() => _HudSplashScreenState();
}

class TurnStartSplashScreen extends StatelessWidget {
  final Widget destination;
  final String title;
  final String subtitle;
  final String statusLabel;

  const TurnStartSplashScreen({
    super.key,
    required this.destination,
    this.title = 'SCCP HUD',
    this.subtitle = 'MODO TURNO',
    this.statusLabel = 'CARGANDO PROTOCOLOS DE CUSTODIA',
  });

  @override
  Widget build(BuildContext context) {
    return HudSplashScreen(
      title: title,
      subtitle: subtitle,
      statusLabel: statusLabel,
      onCompleted: () {
        if (!context.mounted) return;
        Navigator.of(context).pushReplacement(
          buildHudTransitionRoute(destination),
        );
      },
    );
  }
}

class _HudSplashScreenState extends State<HudSplashScreen>
    with SingleTickerProviderStateMixin {
  static const int _scanPassCount = 3;
  static const List<String> _logoSequence = [
    'assets/images/logo3.png',
    'assets/images/logo2.png',
    'assets/images/logo.png',
  ];

  late final AnimationController _controller;
  bool _didNotify = false;
  int _lastStageIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
    _controller.addListener(_handleTick);
  }

  void _handleTick() {
    final raw = _controller.value;
    final visual = _computeVisualProgress(raw);
    final stageIndex = _bootStageIndex(visual);

    if (stageIndex != _lastStageIndex) {
      _lastStageIndex = stageIndex;
      // Beep táctico corto por etapa (estilo consola HUD, sin audio invasivo).
      SystemSound.play(SystemSoundType.click);
    }

    if (!_didNotify && raw >= 1) {
      _didNotify = true;
      widget.onCompleted();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final maxWidth = viewport.width;
    final mobileViewport = maxWidth < 600;
    final hudSize =
        mobileViewport ? (maxWidth * 0.74).clamp(252.0, 320.0) : 286.0;

    return Scaffold(
      body: HucBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  mobileViewport ? 18 : 24,
                  mobileViewport ? 16 : 24,
                  mobileViewport ? 18 : 24,
                  mobileViewport ? 20 : 30,
                ),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final rawProgress = _controller.value;
                    final visualProgress = _computeVisualProgress(rawProgress);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildHudCore(size: hudSize, progress: visualProgress),
                        SizedBox(height: mobileViewport ? 24 : 26),
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Orbitron',
                            color: Color(0xFF00FFD1),
                            fontSize: mobileViewport ? 30 : 26,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Rajdhani',
                            color: Color(0xDDDDFEFF),
                            fontSize: mobileViewport ? 16 : 14,
                            letterSpacing: 2.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: mobileViewport ? 34 : 28),
                        _buildProgressSection(
                          progress: visualProgress,
                          rawProgress: rawProgress,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.statusLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Rajdhani',
                            color: Color(0xB3FF33EE),
                            fontSize: 12,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _computeVisualProgress(double rawProgress) {
    // Estilo JARVIS: avance con micro-pausas y aceleraciones por bloques.
    const checkpoints = [0.0, 0.09, 0.23, 0.37, 0.55, 0.72, 0.86, 1.0];
    const outputs = [0.0, 0.06, 0.25, 0.33, 0.58, 0.69, 0.91, 1.0];

    for (int i = 0; i < checkpoints.length - 1; i++) {
      final start = checkpoints[i];
      final end = checkpoints[i + 1];
      if (rawProgress >= start && rawProgress <= end) {
        final t = ((rawProgress - start) / (end - start)).clamp(0.0, 1.0);
        final eased = Curves.easeInOutCubic.transform(t);
        final value = outputs[i] + ((outputs[i + 1] - outputs[i]) * eased);
        final microPulse = math.sin(rawProgress * math.pi * 24) * 0.004;
        return (value + microPulse).clamp(0.0, 1.0);
      }
    }
    return rawProgress.clamp(0.0, 1.0);
  }

  Widget _buildHudCore({required double size, required double progress}) {
    final scanner = (progress * _scanPassCount) % 1;
    final logoState = _calculateLogoState(progress);
    final logoSize = size * 0.56;
    final radarSize = size * 0.76;
    final pulse = 0.94 + (math.sin(progress * math.pi * 8) * 0.04);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: radarSize,
            height: radarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xCC00FFD1),
                width: 1.8,
              ),
              gradient: const RadialGradient(
                colors: [
                  Color(0x2600FFD1),
                  Color(0x10002532),
                  Colors.transparent,
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x6600FFD1),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Color(0x44FF33EE),
                  blurRadius: 38,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: pulse,
            child: Container(
              width: radarSize * 1.06,
              height: radarSize * 1.06,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0x4D00FFD1),
                  width: 1.1,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              size: Size.square(radarSize),
              painter: _HudReticlePainter(progress: progress),
            ),
          ),
          _LogoLayer(
            path: _logoSequence[0],
            size: logoSize,
            opacity: logoState.firstOpacity,
            scale: logoState.firstScale,
          ),
          _LogoLayer(
            path: _logoSequence[1],
            size: logoSize,
            opacity: logoState.secondOpacity,
            scale: logoState.secondScale,
          ),
          _LogoLayer(
            path: _logoSequence[2],
            size: logoSize,
            opacity: logoState.thirdOpacity,
            scale: logoState.thirdScale,
          ),
          IgnorePointer(
            child: CustomPaint(
              size: Size.square(radarSize),
              painter: _ScannerBeamPainter(scanProgress: scanner),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection({
    required double progress,
    required double rawProgress,
  }) {
    const barCount = 16;
    final trackWidth =
        (MediaQuery.sizeOf(context).width * 0.62).clamp(220.0, 320.0);
    final statusLine = _buildBootStatus(progress, rawProgress);
    final throughput = (12.4 + (rawProgress * 19.6));
    final packets = (rawProgress * 842).round();

    return Column(
      children: [
        SizedBox(
          width: trackWidth.toDouble(),
          child: Row(
            children: List.generate(barCount, (index) {
              final point = (index + 1) / barCount;
              final isActive = progress >= point;
              final localGlow = (progress * barCount - index).clamp(0.0, 1.0);
              final neon = isActive
                  ? Color.lerp(
                      const Color(0xFF008A73),
                      const Color(0xFF00FFD1),
                      localGlow,
                    )!
                  : const Color(0x33254A63);

              return Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsets.only(
                    right: index == barCount - 1 ? 0 : 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: neon,
                    boxShadow: isActive
                        ? const [
                            BoxShadow(
                              color: Color(0x6600FFD1),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${(progress * 100).clamp(0, 100).round()}%',
          style: const TextStyle(
            fontFamily: 'Orbitron',
            color: Color(0xFF00FFD1),
            fontSize: 16,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          statusLine,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Rajdhani',
            color: Color(0xDDE6FFFF),
            fontSize: 11,
            letterSpacing: 1.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'THR ${throughput.toStringAsFixed(1)} MB/s   PKT $packets',
          style: TextStyle(
            fontFamily: 'Orbitron',
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 9.8,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _buildBootStatus(double progress, double rawProgress) {
    const stages = [
      'SINC. ENLACE SATELITAL',
      'CARGA TABLA OFICIALES',
      'VALIDACION TOKEN OPERATIVO',
      'AJUSTE CANAL TELEMETRIA',
      'MONTAJE PROTOCOLO PARTE',
      'ENCRIPTACION AES NIVEL 7',
      'HUD TACTICO LISTO',
    ];

    final index = _bootStageIndex(progress);
    final ticks = ((rawProgress * 20).floor()) % 4;
    final suffix = '.' * ticks;
    return '${stages[index]}$suffix';
  }

  int _bootStageIndex(double progress) {
    const totalStages = 7;
    return (progress * totalStages).floor().clamp(0, totalStages - 1);
  }

  _LogoState _calculateLogoState(double progress) {
    final timeline =
        (progress * _scanPassCount).clamp(0.0, _scanPassCount * 1.0);
    int passIndex = timeline.floor();
    if (passIndex >= _scanPassCount) {
      passIndex = _scanPassCount - 1;
    }

    final passProgress = (timeline - passIndex).clamp(0.0, 1.0);
    final transitionWindow = (passProgress / 0.36).clamp(0.0, 1.0);
    final blend = Curves.easeInOutCubic.transform(transitionWindow);

    double firstOpacity = 0;
    double secondOpacity = 0;
    double thirdOpacity = 0;

    if (passIndex == 0) {
      final intro =
          Curves.easeOutCubic.transform((passProgress / 0.5).clamp(0.0, 1.0));
      firstOpacity = intro;
    } else if (passIndex == 1) {
      firstOpacity = 1 - blend;
      secondOpacity = blend;
    } else {
      secondOpacity = 1 - blend;
      thirdOpacity = blend;
    }

    return _LogoState(
      firstOpacity: firstOpacity,
      secondOpacity: secondOpacity,
      thirdOpacity: thirdOpacity,
      firstScale: 0.9 + (firstOpacity * 0.1),
      secondScale: 0.9 + (secondOpacity * 0.1),
      thirdScale: 0.9 + (thirdOpacity * 0.1),
    );
  }
}

class _LogoState {
  final double firstOpacity;
  final double secondOpacity;
  final double thirdOpacity;
  final double firstScale;
  final double secondScale;
  final double thirdScale;

  const _LogoState({
    required this.firstOpacity,
    required this.secondOpacity,
    required this.thirdOpacity,
    required this.firstScale,
    required this.secondScale,
    required this.thirdScale,
  });
}

class _LogoLayer extends StatelessWidget {
  final String path;
  final double size;
  final double opacity;
  final double scale;

  const _LogoLayer({
    required this.path,
    required this.size,
    required this.opacity,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0, 1),
      child: Transform.scale(
        scale: scale,
        child: Image.asset(
          path,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _HudReticlePainter extends CustomPainter {
  final double progress;

  const _HudReticlePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final cyan = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xDD00FFD1);
    final magenta = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xAAFF33EE);

    final sweep = 0.9 + (math.sin(progress * math.pi * 4) * 0.16);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.9),
      -math.pi / 2,
      math.pi * sweep,
      false,
      cyan,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.74),
      math.pi * 0.2,
      math.pi * 0.42,
      false,
      magenta,
    );

    final tickPaint = Paint()
      ..strokeWidth = 2
      ..color = const Color(0xAA00FFD1);
    for (int i = 0; i < 12; i++) {
      final angle = (math.pi * 2 * i) / 12;
      final p1 =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * 0.82);
      final p2 =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius * 0.91);
      canvas.drawLine(p1, p2, tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HudReticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ScannerBeamPainter extends CustomPainter {
  final double scanProgress;

  const _ScannerBeamPainter({required this.scanProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final left = size.width * 0.16;
    final right = size.width * 0.84;
    final topLimit = size.height * 0.14;
    final bottomLimit = size.height * 0.86;
    final y = topLimit + (bottomLimit - topLimit) * scanProgress;

    final framePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0x2200FFD1);
    canvas.drawRect(
      Rect.fromLTRB(left, y - 5.5, right, y + 5.5),
      framePaint,
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xEE00FFD1);
    canvas.drawLine(Offset(left, y), Offset(right, y), linePaint);

    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xBBFF33EE);
    for (double x = left + 8; x < right; x += 14) {
      final t = ((x - left) / (right - left));
      final jitter = math.sin((scanProgress * math.pi * 6) + (t * math.pi * 8));
      final tickHeight = 2.5 + (jitter.abs() * 2.2);
      canvas.drawLine(
        Offset(x, y - tickHeight),
        Offset(x, y + tickHeight),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerBeamPainter oldDelegate) {
    return oldDelegate.scanProgress != scanProgress;
  }
}
