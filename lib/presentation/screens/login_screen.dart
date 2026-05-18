import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import 'home_screen.dart';
import 'hud_splash_screen.dart';
import 'first_access_onboarding_screen.dart';
import 'off_shift_screen.dart';
import '../widgets/huc_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _idController = TextEditingController();
  late final AnimationController _entryController;
  late final AnimationController _glitchController;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _glitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _glitchController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final idOficial = _idController.text.trim();
    if (idOficial.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingrese su ID de oficial')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.loginWithId(idOficial);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        buildHudTransitionRoute(
          const TurnStartSplashScreen(
            destination: _PostLoginGateScreen(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HucBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final contentWidth = isWide ? 560.0 : constraints.maxWidth;

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _staggeredIn(
                          index: 0,
                          drop: 32,
                          child: _buildBrandSection(isWide: isWide),
                        ),
                        const SizedBox(height: 22),
                        _staggeredIn(
                          index: 1,
                          drop: 30,
                          child: _buildAccessCard(context),
                        ),
                        const SizedBox(height: 14),
                        _staggeredIn(
                          index: 2,
                          drop: 18,
                          child: _buildFooter(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBrandSection({required bool isWide}) {
    final logoSize = isWide ? 168.0 : 132.0;

    return Column(
      children: [
        _GlitchLogo(
          size: logoSize,
          animation: _glitchController,
        ),
        const SizedBox(height: 14),
        const Text(
          'SCCP',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Orbitron',
            fontSize: 34,
            letterSpacing: 1.8,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'SISTEMA DE CONTROL Y CUSTODIA POLICIAL',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 10.5,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }

  Widget _buildAccessCard(BuildContext context) {
    return GlassPanel(
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _staggeredIn(
            index: 3,
            child: const Text(
              'INICIAR TURNO',
              style: TextStyle(
                fontFamily: 'Orbitron',
                letterSpacing: 1.0,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _staggeredIn(
            index: 4,
            child: Text(
              'Ingresa tu ID oficial para acceder al turno.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _staggeredIn(
            index: 5,
            child: TextField(
              controller: _idController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleLogin(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'ID OFICIAL',
                labelStyle: TextStyle(
                  color: AppTheme.primary.withValues(alpha: 0.7),
                ),
                filled: true,
                fillColor: const Color(0x7A07101B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.isLoading) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                );
              }

              return SizedBox(
                width: double.infinity,
                child: _staggeredIn(
                  index: 6,
                  child: ElevatedButton(
                    onPressed: _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'ACCEDER',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.errorMessage == null) {
                return const SizedBox(height: 16);
              }
              return _staggeredIn(
                index: 7,
                drop: 8,
                child: Text(
                  auth.errorMessage!,
                  style: const TextStyle(
                    color: AppTheme.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        Icon(Icons.grid_4x4,
            color: Colors.white.withValues(alpha: 0.58), size: 14),
        const SizedBox(width: 8),
        Text(
          'SOFTWARE ENCRIPTADO SEGURO-AES LEVEL7',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.58),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _staggeredIn({
    required int index,
    required Widget child,
    double drop = 24,
  }) {
    final start = (0.1 + (index * 0.08)).clamp(0.0, 0.88);
    final end = (start + 0.32).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _entryController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, item) {
        final t = animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * drop),
            child: item,
          ),
        );
      },
    );
  }
}

class _PostLoginGateScreen extends StatelessWidget {
  const _PostLoginGateScreen();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (!auth.isAuthenticated) {
          return const LoginScreen();
        }
        if (auth.requiresOnboarding) {
          return const FirstAccessOnboardingScreen();
        }
        if (!auth.isOnShift) {
          return const OffShiftScreen();
        }
        return const HomeScreen();
      },
    );
  }
}

class _GlitchLogo extends StatelessWidget {
  final double size;
  final Animation<double> animation;

  const _GlitchLogo({
    required this.size,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final phase = animation.value;
        final fastWave = math.sin(phase * math.pi * 14);
        final glitch = math.max(0.0, fastWave.abs() - 0.45) * 6;
        final scanY = -1 + (((phase * 1.8) % 1.0) * 2);

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: Container(
                  width: size * 0.72,
                  height: size * 0.72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x6600FFD1),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Color(0x33FF33EE),
                        blurRadius: 36,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  width: size * 0.74,
                  height: size * 0.74,
                  fit: BoxFit.cover,
                ),
              ),
              Transform.translate(
                offset: Offset(glitch, 0),
                child: Opacity(
                  opacity: 0.2,
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: size * 0.74,
                      height: size * 0.74,
                      fit: BoxFit.cover,
                      color: const Color(0xAA00FFD1),
                      colorBlendMode: BlendMode.screen,
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(-glitch, 0),
                child: Opacity(
                  opacity: 0.16,
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: size * 0.74,
                      height: size * 0.74,
                      fit: BoxFit.cover,
                      color: const Color(0xAAFF33EE),
                      colorBlendMode: BlendMode.screen,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment(0, scanY),
                child: Container(
                  width: size * 0.78,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xAA00FFD1),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8800FFD1),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
