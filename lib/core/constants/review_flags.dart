import 'package:flutter/foundation.dart';

class ReviewFlags {
  // Temporal: mantener en true mientras se hace revision sin movil.
  // Cambiar a false para restaurar flujo completo de seguridad en web.
  static const bool enableBrowserReviewMode = false;
  // Seguridad operacional: no aprobar partes solo con speech-to-text.
  // Debe existir motor biometrico real conectado via RPC.
  static const bool requireRealVoiceBiometricForPartes = true;

  static bool get skipPermissionsAndVoiceInWeb =>
      enableBrowserReviewMode && kIsWeb;
}
