import 'package:flutter_test/flutter_test.dart';
import 'package:sccp_mobile/core/utils/time_utils.dart';

void main() {
  group('TimeUtils', () {
    test('getNextReportTime returns next slot in same day', () {
      final next = TimeUtils.getNextReportTime(
        ['08:00', '12:00', '15:00'],
        now: DateTime(2026, 2, 18, 9, 0),
      );

      expect(next, DateTime(2026, 2, 18, 12, 0));
    });

    test('getNextReportTime rolls to next day after final slot', () {
      final next = TimeUtils.getNextReportTime(
        ['08:00', '12:00', '15:00'],
        now: DateTime(2026, 2, 18, 23, 0),
      );

      expect(next, DateTime(2026, 2, 19, 8, 0));
    });

    test('getAlertTime is five minutes before report', () {
      final alert = TimeUtils.getAlertTime(DateTime(2026, 2, 18, 12, 0));
      expect(alert, DateTime(2026, 2, 18, 11, 55));
    });
  });
}
