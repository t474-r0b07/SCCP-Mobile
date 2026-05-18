class AppConstants {
  static const String appName = 'SCCP Móvil';
  static const String notificationChannelId = 'sccp_alerts';
  static const String notificationChannelName = 'SCCP Alertas';
  static const String notificationPartesMilitarChannelId =
      'sccp_partes_militar_v4';
  static const String notificationPartesMilitarChannelName =
      'SCCP Partes Obligatorios';
  static const String notificationPartesSorpresaChannelId =
      'sccp_partes_sorpresa_v4';
  static const String notificationPartesSorpresaChannelName =
      'SCCP Partes Sorpresa';
  static const String notificationShiftChannelId = 'sccp_shift_activation_v1';
  static const String notificationShiftChannelName =
      'SCCP Activacion de Turno';
  static const String backgroundNotificationChannelId = 'sccp_background';
  static const String backgroundNotificationChannelName =
      'SCCP Servicio en Segundo Plano';
  static const String backgroundServiceId = 'sccp_background_service';

  static const int notificationIdPartesOficiales = 1000;
  static const int notificationIdPartesSorpresa = 2000;
  static const int notificationIdInconsistencias = 3000;
  static const int notificationIdRadio = 4000;
  static const int notificationIdRadioCall = 4100;
  static const int notificationIdShiftReactivation = 4200;
}
