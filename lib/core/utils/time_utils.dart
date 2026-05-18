class TimeUtils {
  static DateTime getNextReportTime(List<String> times, {DateTime? now}) {
    final current = now ?? DateTime.now();

    for (final timeStr in times) {
      final parts = timeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final reportTime = DateTime(
        current.year,
        current.month,
        current.day,
        hour,
        minute,
      );

      if (reportTime.isAfter(current)) {
        return reportTime;
      }
    }

    final parts = times.first.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(current.year, current.month, current.day + 1, hour, minute);
  }

  static DateTime getAlertTime(DateTime reportTime) {
    return reportTime.subtract(const Duration(minutes: 5));
  }
}
