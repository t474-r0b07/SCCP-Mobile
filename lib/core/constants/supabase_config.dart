class SupabaseConfig {
  static const String url = 'YOUR_SUPABASE_URL';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY';
  static const Duration backgroundInterval = Duration(minutes: 6);
  static const double maxDistanceMeters = 50.0;
  static const List<String> reportTimes = [
    '09:00', '12:00', '15:00', '18:00', '21:00'
  ];
}