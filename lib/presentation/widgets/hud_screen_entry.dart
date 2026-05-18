import 'package:flutter/material.dart';

class HudScreenEntry extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double offsetY;

  const HudScreenEntry({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 520),
    this.offsetY = 0.035,
  });

  @override
  State<HudScreenEntry> createState() => _HudScreenEntryState();
}

class _HudScreenEntryState extends State<HudScreenEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();

    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offsetY),
      end: Offset.zero,
    ).animate(curve);
    _scale = Tween<double>(begin: 0.994, end: 1).animate(curve);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}
