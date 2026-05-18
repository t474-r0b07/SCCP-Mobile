import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'data/services/alarm_watchdog_service.dart';
import 'data/services/background_service.dart';
import 'data/services/notification_service.dart';
import 'presentation/providers/auth_provider.dart';
import 'presentation/providers/monitoring_provider.dart';
import 'presentation/providers/radio_provider.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/hud_splash_screen.dart';
import 'presentation/screens/first_access_onboarding_screen.dart';
import 'presentation/screens/off_shift_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher error: $error');
    return true;
  };

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runZonedGuarded(
    () => runApp(const MyApp()),
    (error, stack) {
      debugPrint('runZonedGuarded error: $error');
    },
  );
}

Future<void> _bootstrapBackgroundStack() async {
  // Evita competir con el render inicial y permisos del primer frame.
  await Future.delayed(const Duration(milliseconds: 700));
  try {
    await NotificationService.initialize();
  } catch (e) {
    debugPrint('Bootstrap NotificationService failed: $e');
  }

  final prefs = await SharedPreferences.getInstance();
  final operationalReady = prefs.getBool('operational_ready') ?? false;
  final hasSession = (prefs.getString('user_id') ?? '').trim().isNotEmpty &&
      ((prefs.getString('user_device_id') ?? prefs.getString('user_imei') ?? '')
          .trim()
          .isNotEmpty) &&
      operationalReady;

  try {
    if (hasSession) {
      await BackgroundServiceManager.initializeService();
      await BackgroundServiceManager.ensureServiceRunning();
    } else {
      await BackgroundServiceManager.stopServiceIfRunning();
    }
  } catch (e) {
    debugPrint('Bootstrap BackgroundService failed: $e');
  }

  try {
    if (hasSession) {
      final ok = await AlarmWatchdogService.initializeAndSchedule();
      if (!ok) {
        debugPrint('Bootstrap AlarmWatchdog schedule not applied');
      }
    } else {
      await AlarmWatchdogService.cancel();
    }
  } catch (e) {
    debugPrint('Bootstrap AlarmWatchdog failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthProvider()..loadSavedSession()),
        ChangeNotifierProvider(create: (_) => MonitoringProvider()),
        ChangeNotifierProvider(create: (_) => RadioProvider()),
      ],
      child: MaterialApp(
        title: 'SCCP',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _AppEntryGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/home': (_) => const HomeScreen(),
        },
      ),
    );
  }
}

class _AppEntryGate extends StatefulWidget {
  const _AppEntryGate();

  @override
  State<_AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends State<_AppEntryGate> {
  bool _splashCompleted = false;
  bool _backgroundBootstrapScheduled = false;

  void _handleSplashDone() {
    if (!mounted || _splashCompleted) {
      return;
    }
    setState(() {
      _splashCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isAuthenticated &&
            !auth.requiresOnboarding &&
            auth.isOnShift &&
            !_backgroundBootstrapScheduled) {
          _backgroundBootstrapScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future<void>.delayed(const Duration(milliseconds: 900), () async {
              try {
                await _bootstrapBackgroundStack();
              } catch (e) {
                debugPrint('Deferred background bootstrap failed: $e');
              }
            });
          });
        }

        final showSplash = !_splashCompleted || auth.isLoading;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 900),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(fade);

            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: slide,
                child: child,
              ),
            );
          },
          child: showSplash
              ? HudSplashScreen(
                  key: const ValueKey('startup_splash'),
                  onCompleted: _handleSplashDone,
                  title: 'SCCP HUD',
                  subtitle: 'ENLACE TACTICO',
                  statusLabel: 'INICIALIZANDO CENTRO DE COMANDO',
                )
              : !auth.isAuthenticated
                  ? const LoginScreen(key: ValueKey('login'))
                  : auth.requiresOnboarding
                      ? const FirstAccessOnboardingScreen(
                          key: ValueKey('onboarding'),
                        )
                      : !auth.isOnShift
                          ? const OffShiftScreen(
                              key: ValueKey('off_shift'),
                            )
                          : const HomeScreen(key: ValueKey('home')),
        );
      },
    );
  }
}
