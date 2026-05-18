class UtcTimeUtils {
  static String nowIso() => DateTime.now().toUtc().toIso8601String();

  static String iso(DateTime value) => value.toUtc().toIso8601String();
}
