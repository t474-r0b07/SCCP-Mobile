class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const Duration backgroundInterval = Duration(minutes: 6);
  static const double maxDistanceMeters = 50.0;
  static const List<String> reportTimes = [
    '09:00', '12:00', '15:00', '18:00', '21:00'
  ];
}
