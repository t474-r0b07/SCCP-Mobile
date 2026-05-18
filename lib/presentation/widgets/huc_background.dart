import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

class HucBackground extends StatefulWidget {
  final Widget child;

  const HucBackground({super.key, required this.child});

  @override
  State<HucBackground> createState() => _HucBackgroundState();
}

class _HucBackgroundState extends State<HucBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
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
      builder: (context, _) {
        final phase = _controller.value;
        final scanY = 0.28 + ((phase * 1.7) % 1.0) * 0.62;

        return Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF03060C),
                    Color(0xFF08111E),
                    Color(0xFF04060B)
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PerspectiveGridPainter(phase: phase),
                ),
              ),
            ),
            Align(
              alignment: Alignment(0, (scanY * 2) - 1),
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: const [
                        Colors.transparent,
                        Color(0xAA00FFD1),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x6600FFD1),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -120,
              right: -100,
              child: _GlowOrb(
                size: 320,
                color: const Color(0x3300FFD1),
              ),
            ),
            Positioned(
              bottom: -140,
              left: -90,
              child: _GlowOrb(
                size: 300,
                color: const Color(0x29FF33EE),
              ),
            ),
            widget.child,
          ],
        );
      },
    );
  }
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _PerspectiveGridPainter extends CustomPainter {
  final double phase;

  const _PerspectiveGridPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * 0.3;
    final centerX = size.width / 2;
    final verticalPaint = Paint()..strokeWidth = 1;
    final horizontalPaint = Paint()..strokeWidth = 1;
    final rowCount = (size.height / 22).clamp(20, 42).toInt();

    for (int i = 0; i < rowCount; i++) {
      final wrapped = ((i / rowCount) + phase) % 1;
      final depth = math.pow(wrapped, 2.1).toDouble();
      final y = horizonY + depth * (size.height - horizonY);
      final alpha = (0.04 + (1 - depth) * 0.2).clamp(0.04, 0.24);
      horizontalPaint.color = const Color(0xFF00FFD1).withValues(alpha: alpha);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), horizontalPaint);
    }

    for (double x = -size.width; x <= size.width * 2; x += 42) {
      final dx = x - centerX;
      final wobble =
          0.055 + (0.005 * math.sin((dx / 86) + (phase * math.pi * 2)));
      verticalPaint.color = const Color(0xFF00FFD1).withValues(alpha: 0.12);
      canvas.drawLine(
        Offset(x, size.height),
        Offset(centerX + dx * wobble, horizonY),
        verticalPaint,
      );
    }

    final horizonGlow = Paint()
      ..shader = LinearGradient(
        colors: const [
          Colors.transparent,
          Color(0x6A00FFD1),
          Color(0x33FF33EE),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, horizonY - 3, size.width, 8));
    canvas.drawRect(Rect.fromLTWH(0, horizonY - 3, size.width, 7), horizonGlow);
  }

  @override
  bool shouldRepaint(covariant _PerspectiveGridPainter oldDelegate) {
    return oldDelegate.phase != phase;
  }
}
